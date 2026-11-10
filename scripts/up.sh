#!/usr/bin/env bash
# Build and start the whole Linkly stack, in dependency order, waiting for health.
# Usage: ./scripts/up.sh            (normal)
#        NO_WAIT=1 ./scripts/up.sh  (do NOT wait for health: used to reproduce incident 03)
set -euo pipefail
cd "$(dirname "$0")/.."

HUB_USER="${DOCKERHUB_USER:-linkly}"
TAG="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
API_IMAGE="${HUB_USER}/linkly-api:${TAG}"
WORKER_IMAGE="${HUB_USER}/linkly-worker:${TAG}"
PROXY_IMAGE="nginxinc/nginx-unprivileged:1.27-alpine"
PG_IMAGE="postgres:16-alpine"
REDIS_IMAGE="redis:7.4-alpine"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
NO_WAIT="${NO_WAIT:-0}"

log() { printf '\n==> %s\n' "$*"; }

command -v docker >/dev/null || { echo "docker not found"; exit 1; }

# ---------- secrets & certs (generated, never committed) ----------
log "secrets and TLS certificate"
mkdir -p secrets
if [ ! -s secrets/db_password ]; then
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n' > secrets/db_password
  echo "generated secrets/db_password"
fi
chmod 755 secrets
chmod 644 secrets/db_password          # must be readable by uid 70 (postgres) and 10001 (api/worker)
if [ ! -s proxy/certs/tls.crt ]; then
  bash proxy/gen-cert.sh
fi

# ---------- networks & volumes ----------
log "networks and volumes"
net() { # name subnet [extra flags]
  local name=$1 subnet=$2; shift 2
  docker network inspect "$name" >/dev/null 2>&1 || docker network create --driver bridge --subnet "$subnet" "$@" "$name"
}
net dmz      172.30.1.0/24
net internal 172.30.2.0/24 --internal
net admin    172.30.3.0/24 --internal
for v in pgdata redisdata reports; do docker volume create "$v" >/dev/null; done

# ---------- build ----------
log "building images (tag $TAG)"
docker build -t "$API_IMAGE"    -t linkly-api:dev    api/
docker build -t "$WORKER_IMAGE" -t linkly-worker:dev worker/
docker pull -q "$PROXY_IMAGE" >/dev/null
docker pull -q "$PG_IMAGE"    >/dev/null
docker pull -q "$REDIS_IMAGE" >/dev/null

# ---------- helpers ----------
wait_healthy() {
  local name=$1 deadline=$((SECONDS + WAIT_TIMEOUT)) state status
  if [ "$NO_WAIT" = "1" ]; then echo "  (NO_WAIT=1: not waiting for $name)"; return 0; fi
  printf '  waiting for %s ' "$name"
  while (( SECONDS < deadline )); do
    state=$(docker inspect -f '{{.State.Status}}' "$name")
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name")
    if [ "$status" = "healthy" ]; then echo "healthy"; return 0; fi
    if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
      echo "FAILED ($state)"; docker logs --tail 30 "$name"; exit 1
    fi
    printf '.'; sleep 2
  done
  echo "TIMEOUT"; docker logs --tail 30 "$name"; exit 1
}

# every container gets these
HARDEN=(--cap-drop ALL --security-opt no-new-privileges:true --read-only --restart unless-stopped)
SECRET_MOUNT=(-v "$PWD/secrets/db_password:/run/secrets/db_password:ro")
HC=(--health-interval 5s --health-timeout 3s --health-retries 10)

log "removing old containers (volumes are kept)"
for c in proxy worker api cache db; do docker rm -f "$c" >/dev/null 2>&1 || true; done

# ---------- 1. db (internal + admin) ----------
log "db"
docker create --name db --network internal \
  "${HARDEN[@]}" \
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  --tmpfs /tmp --tmpfs /run/postgresql \
  --memory 512m --cpus 1.0 \
  -e POSTGRES_USER=linkly -e POSTGRES_DB=linkly \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  -v pgdata:/var/lib/postgresql/data "${SECRET_MOUNT[@]}" \
  --health-cmd 'pg_isready -h 127.0.0.1 -U linkly -d linkly' "${HC[@]}" --health-start-period 10s \
  "$PG_IMAGE" >/dev/null
docker network connect admin db          # attach 2nd network BEFORE start
docker start db >/dev/null
wait_healthy db

# ---------- 2. cache (internal) ----------
log "cache"
docker run -d --name cache --network internal \
  "${HARDEN[@]}" --user redis \
  --memory 128m --cpus 0.5 \
  -v redisdata:/data \
  --health-cmd 'redis-cli ping' "${HC[@]}" \
  "$REDIS_IMAGE" redis-server --appendonly yes --protected-mode no >/dev/null
wait_healthy cache

# ---------- 3. api (dmz + internal) ----------
log "api"
docker create --name api --network dmz \
  "${HARDEN[@]}" \
  --tmpfs /tmp \
  --memory 256m --cpus 0.5 \
  -e DB_HOST=db -e DB_NAME=linkly -e DB_USER=linkly \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -e REDIS_HOST=cache \
  -e LOG_FILE=- \
  "${SECRET_MOUNT[@]}" \
  "$API_IMAGE" >/dev/null
docker network connect internal api
docker start api >/dev/null
wait_healthy api

# ---------- 4. worker (internal) ----------
log "worker"
docker run -d --name worker --network internal \
  "${HARDEN[@]}" \
  --tmpfs /tmp \
  --memory 128m --cpus 0.5 \
  -e DB_HOST=db -e DB_NAME=linkly -e DB_USER=linkly \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -e REDIS_HOST=cache \
  -e REPORT_DIR=/reports \
  -e WEBHOOK_URL= \
  -v reports:/reports "${SECRET_MOUNT[@]}" \
  "$WORKER_IMAGE" >/dev/null
wait_healthy worker

# ---------- 5. proxy (dmz, the only one with published ports) ----------
log "proxy"
docker run -d --name proxy --network dmz \
  -p 80:8080 -p 443:8443 \
  "${HARDEN[@]}" \
  --tmpfs /tmp \
  --memory 64m --cpus 0.5 \
  -v "$PWD/proxy/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "$PWD/proxy/certs:/etc/nginx/certs:ro" \
  --health-cmd 'wget -qO- http://127.0.0.1:8080/healthz' "${HC[@]}" \
  "$PROXY_IMAGE" >/dev/null
wait_healthy proxy

log "stack is up"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
if [ "$NO_WAIT" != "1" ] && command -v curl >/dev/null; then
  curl -sk -o /dev/null -w 'smoke test https://localhost/health -> HTTP %{http_code}\n' https://localhost/health || true
fi
