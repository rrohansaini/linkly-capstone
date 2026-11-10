# 03: api crash-loops when all containers are started at once

## Symptom
`docker ps` shows the api as `Restarting`; its logs show connection errors to Postgres.

## Commands and output
```bash
./scripts/down.sh && docker volume rm pgdata     # fresh DB so Postgres needs to initialise (takes seconds)
NO_WAIT=1 ./scripts/up.sh                         # start everything without waiting for health
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker logs --tail 15 api
docker inspect -f 'restarts={{.RestartCount}}' api
```
<!-- PASTE THE REAL OUTPUT HERE -->

## Root cause
The api runs `init_schema()` at import time and needs Postgres to accept connections. Docker's
start order only means "the process started", not "the service is ready". Postgres was still
initialising, the api crashed, and `--restart unless-stopped` kept relaunching it.

## Fix
Start in dependency order and wait for each service's HEALTHCHECK to report `healthy` before
starting the next one (`wait_healthy` in `scripts/up.sh`). Postgres health uses
`pg_isready -h 127.0.0.1`, which only succeeds once the real server listens on TCP (not during init).
```bash
./scripts/up.sh
```
<!-- PASTE THE REAL OUTPUT (all healthy) -->
