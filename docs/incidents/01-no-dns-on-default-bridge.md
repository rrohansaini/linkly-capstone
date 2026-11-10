# 01: api cannot resolve `db` when run without `--network`

## Symptom
The api container exits at startup and fails with `psycopg.OperationalError: [Errno -2] Name or service not known` for the database name.

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
docker run --rm busybox:1.36 ping -c 1 -W 2 inc-db
```
]633;E;echo '```text';9f14e8f7-9949-4c87-a4c2-5916e186b95c]633;C```text
$ docker run --rm --name inc-api -e DB_HOST=inc-db -e REDIS_HOST=inc-cache -e LOG_FILE=- -e DB_PASSWORD_FILE=/run/secrets/db_password -v "$PWD/secrets/db_password:/run/secrets/db_password:ro" linkly-api:dev
    return psycopg.connect(
           ^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/psycopg/connection.py", line 98, in connect
    attempts = conninfo_attempts(params)
               ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/psycopg/_conninfo_attempts.py", line 50, in conninfo_attempts
    raise e.OperationalError(str(last_exc))
psycopg.OperationalError: [Errno -2] Name or service not known

$ docker run --rm busybox:1.36 nslookup inc-db
Server:		168.63.129.16
Address:	168.63.129.16:53

** server can't find inc-db.dxrpqgqhlb3ehogrxrezr215ye.rx.internal.cloudapp.net: NXDOMAIN

** server can't find inc-db.dxrpqgqhlb3ehogrxrezr215ye.rx.internal.cloudapp.net: NXDOMAIN

$ docker run --rm busybox:1.36 ping -c 1 -W 2 inc-db
ping: bad address 'inc-db'
```

## Root cause
The default `bridge` network has no embedded DNS: containers on it can only reach each other by IP.
Name resolution by container name only exists on user-defined networks. The nslookup output confirms it: the query went to the host resolver (168.63.129.16), not to the embedded Docker DNS (127.0.0.11), so `inc-db` returns NXDOMAIN.

## Fix
Put both containers on a user-defined network (our `internal`), then the name resolves.
```bash
docker network create inc-net && docker network connect inc-net inc-db
docker network inspect inc-net --format "{{range .Containers}}{{.Name}} {{end}}"
docker run --rm --network inc-net busybox:1.36 ping -c 1 -W 2 inc-db
docker run --rm --network inc-net busybox:1.36 nc -zw3 inc-db 5432
```
]633;E;echo '```text';9f14e8f7-9949-4c87-a4c2-5916e186b95c]633;C```text
$ docker network inspect inc-net --format "{{range .Containers}}{{.Name}} {{end}}"
inc-db 


$ docker run --rm --network inc-net busybox:1.36 ping -c 1 -W 2 inc-db
PING inc-db (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.185 ms

--- inc-db ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 0.185/0.185/0.185 ms

$ docker run --rm --network inc-net busybox:1.36 nc -zw3 inc-db 5432 && echo "inc-db:5432 reachable"
inc-db:5432 reachable
```
Note: busybox 1.36 `nslookup` returned NXDOMAIN even on the user-defined network (it queried the host search-domain name instead of the container name), so `ping` and `nc` are used to verify that Docker DNS now resolves `inc-db`.

Cleanup: `docker rm -f inc-db; docker network rm inc-net`
