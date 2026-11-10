#!/usr/bin/env bash
# Incident 03: start everything at once -> api crash-loops until Postgres is ready.
# WARNING: deletes the pgdata volume (fresh database). Captures REAL output into the md file.
set -uo pipefail
cd "$(dirname "$0")"
MD=docs/incidents/03-api-crash-loop-before-postgres.md
[ -f "$MD" ] || { echo "run this from the repo root"; exit 1; }
grep -q 'PASTE THE REAL OUTPUT' "$MD" || { echo "markers already filled; nothing to do"; exit 0; }
B=/tmp/inc03-before.txt; A=/tmp/inc03-after.txt
show() { echo "\$ $1"; }

echo "[1/3] fresh database + start everything WITHOUT waiting for health..."
./scripts/down.sh >/dev/null 2>&1
docker volume rm pgdata >/dev/null 2>&1
NO_WAIT=1 ./scripts/up.sh > /tmp/inc03-nowait.log 2>&1
sleep 4
{
  echo '```text'
  show "./scripts/down.sh && docker volume rm pgdata"
  echo "(containers and networks removed, pgdata volume deleted)"; echo
  show "NO_WAIT=1 ./scripts/up.sh"
  grep -E 'NO_WAIT|==> (db|cache|api|worker|proxy)' /tmp/inc03-nowait.log; echo
  show "docker ps -a --format 'table {{.Names}}\t{{.Status}}'"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}'; echo
  show "docker logs --tail 15 api"
  docker logs --tail 15 api 2>&1; echo
  show "docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker"
  docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker; echo
  echo '```'
} > "$B"
cat "$B"

echo "[2/3] applying the fix: fresh database again, but up.sh waits for each health check (about a minute)..."
./scripts/down.sh >/dev/null 2>&1
docker volume rm pgdata >/dev/null 2>&1
./scripts/up.sh > /tmp/inc03-up.log 2>&1 || { echo "up.sh failed, see /tmp/inc03-up.log"; tail -30 /tmp/inc03-up.log; exit 1; }
{
  echo '```text'
  show "./scripts/down.sh && docker volume rm pgdata && ./scripts/up.sh"
  grep -E 'waiting for|stack is up' /tmp/inc03-up.log; echo
  show "docker ps --format 'table {{.Names}}\t{{.Status}}'"
  docker ps --format 'table {{.Names}}\t{{.Status}}'; echo
  show "docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker"
  docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker; echo
  echo '```'
} > "$A"
cat "$A"

echo "[3/3] writing output into $MD ..."
python3 - "$MD" "$B" "$A" <<'PY'
import re, sys
md, b, a = sys.argv[1:4]
t = open(md).read()
before = open(b).read().rstrip(); after = open(a).read().rstrip()
t = t.replace("docker inspect -f 'restarts={{.RestartCount}}' api",
              "docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker")
t = re.sub(r'<!--\s*PASTE THE REAL OUTPUT HERE\s*-->', lambda m: before, t)
t = re.sub(r'<!--\s*PASTE THE REAL OUTPUT \(all healthy\)\s*-->', lambda m: after, t)
open(md, 'w').write(t)
PY
echo "remaining PASTE markers: $(grep -c 'PASTE' "$MD")"
