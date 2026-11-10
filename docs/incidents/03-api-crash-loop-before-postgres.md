# 03: api crash-loops when all containers are started at once

## Symptom
`docker ps` shows the api as `Restarting`; its logs show connection errors to Postgres.

## Commands and output
```bash
./scripts/down.sh && docker volume rm pgdata     # fresh DB so Postgres needs to initialise (takes seconds)
NO_WAIT=1 ./scripts/up.sh                         # start everything without waiting for health
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker logs --tail 15 api
docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker
```
```text
$ ./scripts/down.sh && docker volume rm pgdata
(containers and networks removed, pgdata volume deleted)

$ NO_WAIT=1 ./scripts/up.sh
==> db
  (NO_WAIT=1: not waiting for db)
==> cache
  (NO_WAIT=1: not waiting for cache)
==> api
  (NO_WAIT=1: not waiting for api)
==> worker
  (NO_WAIT=1: not waiting for worker)
==> proxy
  (NO_WAIT=1: not waiting for proxy)

$ docker ps -a --format 'table {{.Names}}\t{{.Status}}'
NAMES     STATUS
proxy     Up 5 seconds (health: starting)
worker    Up 6 seconds (healthy)
api       Up 4 seconds (health: starting)
cache     Up 8 seconds (healthy)
db        Up 8 seconds (healthy)

$ docker logs --tail 15 api
  File "/app/app.py", line 54, in init_schema
    with db() as conn:
         ^^^^
  File "/app/app.py", line 48, in db
    return psycopg.connect(
           ^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/psycopg/connection.py", line 119, in connect
    raise last_ex.with_traceback(None)
psycopg.OperationalError: connection failed: connection to server at "172.30.2.2", port 5432 failed: Connection refused
	Is the server running on that host and accepting TCP/IP connections?
[2026-11-10 16:23:30 +0000] [1] [INFO] Starting gunicorn 23.0.0
[2026-11-10 16:23:30 +0000] [1] [INFO] Listening at: http://0.0.0.0:5000 (1)
[2026-11-10 16:23:30 +0000] [1] [INFO] Using worker: sync
[2026-11-10 16:23:30 +0000] [7] [INFO] Booting worker with pid: 7
[2026-11-10 16:23:30 +0000] [8] [INFO] Booting worker with pid: 8

$ docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker
/api restarts=1 status=running
/worker restarts=0 status=running

```

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
```text
$ ./scripts/down.sh && docker volume rm pgdata && ./scripts/up.sh
  waiting for db ...healthy
  waiting for cache ...healthy
  waiting for api ...healthy
  waiting for worker ...healthy
  waiting for proxy ...healthy
==> stack is up

$ docker ps --format 'table {{.Names}}\t{{.Status}}'
NAMES     STATUS
proxy     Up 6 seconds (healthy)
worker    Up 13 seconds (healthy)
api       Up 19 seconds (healthy)
cache     Up 26 seconds (healthy)
db        Up 33 seconds (healthy)

$ docker inspect -f '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' api worker
/api restarts=0 status=running
/worker restarts=0 status=running

```
