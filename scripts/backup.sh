#!/usr/bin/env bash
# pg_dump in a throwaway container attached to the admin network ONLY.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
ts="$(date +%Y%m%d-%H%M%S)"
out="backups/linkly-${ts}.sql.gz"

# runs as the host user so the bind-mounted ./backups is writable; password is read
# from the mounted secret inside the container (never put in the container's env)
docker run --rm --name backup-job --network admin \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --tmpfs /tmp \
  --memory 128m --cpus 0.5 \
  -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" \
  -v "$PWD/backups:/backups" \
  postgres:16-alpine \
  sh -c "set -o pipefail; PGPASSWORD=\$(cat /run/secrets/db_password) pg_dump -h db -U linkly -d linkly | gzip > /backups/.tmp-${ts}.gz && mv /backups/.tmp-${ts}.gz /backups/linkly-${ts}.sql.gz"

gzip -t "$out"
echo "backup written: $out ($(du -h "$out" | cut -f1))"
