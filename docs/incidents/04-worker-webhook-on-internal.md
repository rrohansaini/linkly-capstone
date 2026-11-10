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
<!-- PASTE THE REAL OUTPUT HERE (requests ConnectionError / name resolution failure) -->

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
<!-- PASTE THE REAL OUTPUT ("report written: ..." and no crash) -->
