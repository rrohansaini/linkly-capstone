# 01: api cannot resolve `db` when run without `--network`

## Symptom
The api container exits at startup and logs a "failed to resolve host" error for the database name.

## Commands and output
```bash
docker run -d --name inc-db -e POSTGRES_USER=linkly -e POSTGRES_DB=linkly \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" postgres:16-alpine

# no --network => Docker's default bridge
docker run --rm --name inc-api -e DB_HOST=inc-db -e REDIS_HOST=inc-cache -e LOG_FILE=- \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" linkly-api:dev
docker run --rm busybox:1.36 nslookup inc-db
```
<!-- PASTE THE REAL OUTPUT OF EACH COMMAND HERE -->

## Root cause
The default `bridge` network has no embedded DNS: containers on it can only reach each other by IP.
Name resolution by container name only exists on user-defined networks.

## Fix
Put both containers on a user-defined network (our `internal`), then the name resolves.
```bash
docker network create inc-net && docker network connect inc-net inc-db
docker run --rm --network inc-net busybox:1.36 nslookup inc-db
```
<!-- PASTE THE REAL OUTPUT (nslookup now returns an IP) -->
Cleanup: `docker rm -f inc-db; docker network rm inc-net`
