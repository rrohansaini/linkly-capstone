# 05: api fails on its first write after adding `--read-only`

## Symptom
The api exits immediately at import time with an `OSError` about `logs`.

## Commands and output
```bash
docker run --rm --read-only linkly-api:dev      # LOG_FILE not set => default logs/api.log
```
```text
$ docker run --rm --read-only linkly-api:dev      # LOG_FILE not set => logs/api.log
  File "<frozen importlib._bootstrap>", line 1331, in _find_and_load_unlocked
  File "<frozen importlib._bootstrap>", line 935, in _load_unlocked
  File "<frozen importlib._bootstrap_external>", line 999, in exec_module
  File "<frozen importlib._bootstrap>", line 488, in _call_with_frames_removed
  File "/app/app.py", line 39, in <module>
    os.makedirs(os.path.dirname(LOG_FILE) or ".", exist_ok=True)
  File "<frozen os>", line 226, in makedirs
OSError: [Errno 30] Read-only file system: 'logs'

```

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
```text
$ docker run --rm --read-only --tmpfs /tmp -e LOG_FILE=- -e DB_HOST=nonexistent linkly-api:dev
  File "/usr/local/lib/python3.12/site-packages/psycopg/_conninfo_attempts.py", line 50, in conninfo_attempts
    raise e.OperationalError(str(last_exc))
psycopg.OperationalError: [Errno -2] Name or service not known

$ docker inspect -f 'ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} LOG_FILE={{range .Config.Env}}{{if eq (slice . 0 3) "LOG"}}{{.}}{{end}}{{end}}' api
ReadonlyRootfs=true LOG_FILE=-

$ curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health
200

$ docker logs --tail 2 api
127.0.0.1 - - [10/Nov/2026:16:32:17 +0000] "GET /health HTTP/1.1" 200 36 "-" "Python-urllib/3.12"
172.30.1.3 - - [10/Nov/2026:16:32:23 +0000] "GET /health HTTP/1.0" 200 36 "-" "curl/8.5.0"

```
