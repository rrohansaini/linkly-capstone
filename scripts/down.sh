#!/usr/bin/env bash
# Remove containers and networks. Named volumes (pgdata, redisdata, reports) are KEPT.
set -uo pipefail
for c in proxy worker api cache db; do
  docker stop -t 30 "$c" >/dev/null 2>&1 || true
  docker rm -f "$c" >/dev/null 2>&1 || true
done
for n in dmz internal admin; do docker network rm "$n" >/dev/null 2>&1 || true; done
echo "containers and networks removed; volumes kept:"
docker volume ls --format '  {{.Name}}' | grep -E '^  (pgdata|redisdata|reports)$' || true
