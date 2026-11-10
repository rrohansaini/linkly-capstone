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
docker logs --tail 5 proxy
```
<!-- PASTE THE REAL OUTPUT HERE (502, "Listening at: http://127.0.0.1:8000", "connect() failed (111: Connection refused)") -->

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
<!-- PASTE THE REAL OUTPUT (200) -->
