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
<!-- PASTE THE REAL OUTPUT HERE (owner 0 0, PermissionError ... clicks-DATE.csv) -->

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
<!-- PASTE THE REAL OUTPUT (owner 10001 10001, "report written: /reports/clicks-DATE.csv") -->
