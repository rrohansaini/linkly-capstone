# 06: worker as UID 10001 gets "Permission denied" on a new reports volume

## Symptom
The worker (running as 10001) crashes on its first report with `PermissionError: [Errno 13]`.

## Commands and output
```bash
./scripts/up.sh && docker rm -f worker
docker volume create inc-reports
docker run --rm -v inc-reports:/v busybox:1.36 ls -ldn /v        # who owns a brand new volume?
docker run -d --name inc-worker --network internal \
  -e DB_HOST=db -e REDIS_HOST=cache -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -e REPORT_DIR=/data/reports -e WEBHOOK_URL= \
  -v inc-reports:/data/reports -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" linkly-worker:dev
sleep 6; docker logs inc-worker
```
```text
$ docker volume create inc-reports
inc-reports

$ docker run --rm -v inc-reports:/v busybox:1.36 ls -ldn /v
drwxr-xr-x    2 0        0             4096 Nov 10 16:32 /v

$ docker run -d --name inc-worker --network internal ... -e REPORT_DIR=/data/reports -v inc-reports:/data/reports linkly-worker:dev
b5bd9dd8ad16b2b6167b562cd6619dec6c0dfe7b6bc48f4bb133617a8d2eae86

$ docker logs inc-worker 2>&1 | tail -6
  File "/app/worker.py", line 79, in main
    write_report()
  File "/app/worker.py", line 58, in write_report
    with open(path, "w", newline="") as f:
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^
PermissionError: [Errno 13] Permission denied: '/data/reports/clicks-2026-11-10.csv'

$ docker inspect -f 'exit={{.State.ExitCode}} status={{.State.Status}}' inc-worker
exit=1 status=exited

```

## Root cause
A new named volume is created root-owned (0:0, mode 755) when the mount path does not exist in the
image. Docker only copies ownership from the image into an empty new volume if the directory
exists in the image with that owner. The worker runs as 10001, so it cannot write into it.

## Fix
In `worker/Dockerfile`: `RUN mkdir /reports && chown 10001:10001 /reports`, and mount the volume at
`/reports` (`REPORT_DIR=/reports`). On first use Docker copies that 10001 ownership into the volume.
```bash
docker rm -f inc-worker; docker volume rm inc-reports
docker volume rm reports 2>/dev/null; ./scripts/up.sh      # brand-new reports volume
docker run --rm -v reports:/v busybox:1.36 ls -ldn /v      # now owned by 10001
docker logs worker
```
```text
$ docker volume rm reports; ./scripts/up.sh      # brand-new reports volume
  waiting for worker ...healthy
==> stack is up

$ docker run --rm -v reports:/v busybox:1.36 ls -ldn /v
drwxr-xr-x    2 10001    10001         4096 Nov 10 16:33 /v

$ docker logs worker
worker started
report written: /reports/clicks-2026-11-10.csv (0 codes)

```
