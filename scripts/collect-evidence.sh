#!/usr/bin/env bash
# Runs every success-metric check against the LIVE stack and stores the real output
# in docs/evidence/. Needs: stack up, images pushed (for trivy), DOCKERHUB_USER set.
# Add --durability to also run the down/up persistence test (takes a few minutes).
set -uo pipefail
cd "$(dirname "$0")/.."
E=docs/evidence; mkdir -p "$E"
cap() { # file, description, shell snippet
  local f="$E/$1"; shift
  { echo "# $1"; echo "# date: $(date -u +%FT%TZ)"; shift; echo "\$ $*"; bash -c "$*"; echo "# exit code: $?"; } 2>&1 | tee "$f"
  echo
}
[ -n "${DOCKERHUB_USER:-}" ] || echo "WARNING: DOCKERHUB_USER not set (trivy section will fail)"
TAG="$(git rev-parse --short HEAD)"

cap 01-networks.txt "Only api is on both dmz and internal" \
  "docker network inspect dmz internal admin -f '{{.Name}} internal={{.Internal}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} containers:{{range .Containers}} {{.Name}}{{end}}'"
cap 02-published-ports.txt "Only the proxy publishes ports" \
  "docker ps --format '{{.Names}} {{.Ports}}'"
cap 03-app-works.txt "Create a link, follow it, stats count the click" \
  'code=$(curl -sk -X POST https://localhost/links -H "Content-Type: application/json" -d "{\"url\":\"https://example.com\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"code\"])"); echo "code=$code"; curl -sk -o /dev/null -w "follow -> HTTP %{http_code}\n" https://localhost/$code; sleep 5; curl -sk https://localhost/stats/$code'
cap 04-image-size.txt "api image size must be <= 200 MB" \
  "docker image inspect -f '{{.RepoTags}} {{.Size}} bytes' ${DOCKERHUB_USER:-linkly}/linkly-api:$TAG ${DOCKERHUB_USER:-linkly}/linkly-worker:$TAG; docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep linkly"
cap 05-process-user.txt "api and worker do not run as root" \
  "docker top api -o user,pid,cmd; docker top worker -o user,pid,cmd"
cap 06-hardening.txt "CapDrop ALL, ReadonlyRootfs, memory and CPU limits on every container" \
  "for c in proxy api worker cache db; do docker inspect -f '{{.Name}} CapDrop={{.HostConfig.CapDrop}} CapAdd={{.HostConfig.CapAdd}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} Memory={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}} SecurityOpt={{.HostConfig.SecurityOpt}} Privileged={{.HostConfig.Privileged}} NetworkMode={{.HostConfig.NetworkMode}}' \$c; done"
cap 07-secret-exposure.txt "Password is not in docker inspect env (only *_FILE paths)" \
  "for c in api worker db; do echo \"--- \$c\"; docker inspect -f '{{json .Config.Env}}' \$c; done; echo; if docker inspect api worker db | grep -qF \"\$(cat secrets/db_password)\"; then echo 'FAIL: password found in inspect output'; else echo 'OK: password value not present in docker inspect'; fi; echo; docker inspect api worker db -f '{{.Name}} mounts:{{range .Mounts}} {{.Source}}->{{.Destination}}(rw={{.RW}}){{end}}' | grep -v docker.sock"
cap 08-netcheck.txt "Reachability matrix" "./scripts/netcheck.sh"
cap 09-trivy.txt "Trivy: 0 fixable CRITICAL in pushed images" "./scripts/scan.sh"
cap 10-backup.txt "Backup is a .sql.gz containing links" \
  './scripts/backup.sh && f=$(ls -t backups/*.sql.gz | head -1) && echo "file: $f" && zcat "$f" | grep -m3 -E "^[A-Za-z0-9]{6}\s+https?://" ; zcat "$f" | grep -c "COPY public.links"'

if [ "${1:-}" = "--durability" ]; then
  cap 11-durability.txt "Link count identical after down.sh + up.sh" \
    'q() { docker exec db psql -U linkly -d linkly -tAc "select count(*) from links"; }; echo "before: $(q)"; ./scripts/down.sh >/dev/null; ./scripts/up.sh >/dev/null; echo "after:  $(q)"'
fi
echo "Evidence saved in $E/"
