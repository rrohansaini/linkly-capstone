# 02: proxy returns 502 when the api is started with the README laptop command

## Symptom
`https://localhost/health` returns `502 Bad Gateway` although the api container is "Up".

## Commands and output
```bash
./scripts/up.sh                      # healthy stack first
docker rm -f api
docker create --name api --network dmz --read-only --tmpfs /tmp \
  -e DB_HOST=db -e DB_NAME=linkly -e DB_USER=linkly -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -e REDIS_HOST=cache -e LOG_FILE=- \
  -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" \
  linkly-api:dev gunicorn app:app      # the README's laptop command
docker network connect internal api && docker start api
docker restart proxy                 # nginx caches the upstream IP at start
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
docker logs --tail 5 api
docker logs proxy 2>&1 | grep -E 'error|upstream' | tail -3
```
```text
$ docker rm -f api
api

$ docker create --name api --network dmz --read-only --tmpfs /tmp ... linkly-api:dev gunicorn app:app
009a6fd65c8fb535955f4a22dff1e9322eacc1809602fd7fc5a47d41bf93b1c3

$ docker network connect internal api && docker start api
api

$ docker restart proxy
proxy

$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
502

$ docker logs --tail 5 api
[2026-11-10 16:17:52 +0000] [1] [INFO] Starting gunicorn 23.0.0
[2026-11-10 16:17:52 +0000] [1] [INFO] Listening at: http://127.0.0.1:8000 (1)
[2026-11-10 16:17:52 +0000] [1] [INFO] Using worker: sync
[2026-11-10 16:17:52 +0000] [7] [INFO] Booting worker with pid: 7

$ docker logs proxy 2>&1 | grep -E 'error|upstream' | tail -3
2026/11/10 16:18:00 [error] 22#22: *2 connect() failed (111: Connection refused) while connecting to upstream, client: 172.30.1.1, server: , request: "GET /health HTTP/1.1", upstream: "http://172.30.1.2:5000/health", host: "localhost"

```

## Root cause
`gunicorn app:app` binds to `127.0.0.1:8000` by default. Inside the container, loopback is only
reachable from inside that container, and the proxy connects to `api:5000` on the container's
network IP. Wrong interface and wrong port, so nginx gets "connection refused" and answers 502.

## Fix
Bind to all interfaces on the port nginx expects: `gunicorn --bind 0.0.0.0:5000 ...` (in the Dockerfile CMD).
```bash
./scripts/up.sh
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
```
```text
$ ./scripts/up.sh
(stack rebuilt, all services healthy)

$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
200

$ docker logs api 2>&1 | grep Listening
[2026-11-10 16:18:21 +0000] [1] [INFO] Listening at: http://0.0.0.0:5000 (1)

```
