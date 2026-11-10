# 04: worker exits when it posts its first report (internal network only)

## Symptom
The worker prints `worker started`, then exits with a traceback when it writes the first report.

## Commands and output
```bash
./scripts/up.sh && docker rm -f worker
docker run -d --name inc-worker --network internal \
  -e DB_HOST=db -e REDIS_HOST=cache -e DB_PASSWORD_FILE=/run/secrets/db_password -e REPORT_DIR=/reports \
  -v reports:/reports -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" linkly-worker:dev
sleep 8
docker logs inc-worker
docker inspect -f 'exit={{.State.ExitCode}} status={{.State.Status}}' inc-worker
```
```text
$ docker rm -f worker
worker

$ docker run -d --name inc-worker --network internal ... linkly-worker:dev   # no WEBHOOK_URL override
1eb0e24e19a0163d73baa57ab7f843999ed5895eaa03223ceebf7c7fedc94443

$ docker logs inc-worker 2>&1 | tail -12
  File "/usr/local/lib/python3.12/site-packages/requests/api.py", line 59, in request
    return session.request(method=method, url=url, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/requests/sessions.py", line 589, in request
    resp = self.send(prep, **send_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/requests/sessions.py", line 703, in send
    r = adapter.send(request, **kwargs)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/requests/adapters.py", line 700, in send
    raise ConnectionError(e, request=request)
requests.exceptions.ConnectionError: HTTPSConnectionPool(host='httpbin.org', port=443): Max retries exceeded with url: /post (Caused by NameResolutionError("HTTPSConnection(host='httpbin.org', port=443): Failed to resolve 'httpbin.org' ([Errno -3] Temporary failure in name resolution)"))

$ docker inspect -f 'exit={{.State.ExitCode}} status={{.State.Status}}' inc-worker
exit=1 status=exited

```

## Root cause
`WEBHOOK_URL` defaults to `https://httpbin.org/post`. The `internal` network is created with
`--internal`, so it has no route to the internet. `requests.post()` raises, and the worker
has no try/except, so the process dies.

## Fix
Do not change the code and do not give the worker internet access (that would break the
matrix: worker to Internet must be Blocked). Disable the webhook with an empty env var:
`-e WEBHOOK_URL=` (the app skips the post when it is empty).
```bash
docker rm -f inc-worker
./scripts/up.sh
docker logs worker
```
```text
$ docker rm -f inc-worker && ./scripts/up.sh
  waiting for worker ...healthy
==> stack is up

$ docker logs worker
worker started
report written: /reports/clicks-2026-11-10.csv (0 codes)

$ docker inspect -f '{{json .Config.Env}}' worker | grep -o 'WEBHOOK_URL=[^"]*'
WEBHOOK_URL=

$ docker inspect -f 'status={{.State.Status}} health={{.State.Health.Status}} restarts={{.RestartCount}}' worker
status=running health=healthy restarts=0

```
