# 05: api fails on its first write after adding `--read-only`

## Symptom
The api exits immediately at import time with an `OSError` about `logs`.

## Commands and output
```bash
docker run --rm --read-only linkly-api:dev      # LOG_FILE not set => default logs/api.log
```
<!-- PASTE THE REAL OUTPUT HERE (traceback from os.makedirs / logging.basicConfig) -->

## Root cause
`LOG_FILE` defaults to `logs/api.log`. The app runs `os.makedirs("logs")` and opens that file in
the working directory (`/app`), which is part of the read-only root filesystem. (Without
`--read-only` it would still fail with "Permission denied", because /app is owned by root and we run as 10001.)
Gunicorn also wants a writable temp dir for its worker heartbeat files.

## Fix
Send logs to stdout, where `docker logs` collects them: `-e LOG_FILE=-`. Give the process a
RAM-backed writable `/tmp`: `--tmpfs /tmp`. The root filesystem stays read-only.
```bash
docker run --rm --read-only --tmpfs /tmp -e LOG_FILE=- -e DB_HOST=nonexistent linkly-api:dev   # gets past logging; now fails only on DB (expected, no db here)
docker inspect -f 'ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}}' api
```
<!-- PASTE THE REAL OUTPUT -->
