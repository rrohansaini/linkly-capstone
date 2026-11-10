#!/usr/bin/env bash
# Tests every cell of the reachability matrix from live containers.
# Sidecar (busybox) joins the source container's network namespace; the backup job
# is tested from a throwaway container on admin. Exits non-zero on any mismatch.
set -uo pipefail
cd "$(dirname "$0")/.."

BB="busybox:1.36"
SOURCES=(proxy api worker cache db backup)
TARGETS=(api db cache internet)
declare -A HOST=( [api]=api [db]=db [cache]=cache [internet]=1.1.1.1 )
declare -A PORT=( [api]=5000 [db]=5432 [cache]=6379 [internet]=443 )
# "-" = not tested (a service to itself)
declare -A EXPECT=(
  [proxy,api]=Allowed  [proxy,db]=Blocked  [proxy,cache]=Blocked  [proxy,internet]=Allowed
  [api,api]=-          [api,db]=Allowed    [api,cache]=Allowed    [api,internet]=Allowed
  [worker,api]=Allowed [worker,db]=Allowed [worker,cache]=Allowed [worker,internet]=Blocked
  [cache,api]=Allowed  [cache,db]=Allowed  [cache,cache]=-        [cache,internet]=Blocked
  [db,api]=Allowed     [db,db]=-           [db,cache]=Allowed     [db,internet]=Blocked
  [backup,api]=Blocked [backup,db]=Allowed [backup,cache]=Blocked [backup,internet]=Blocked
)

for s in proxy api worker cache db; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$s" 2>/dev/null)" != "true" ]; then
    echo "container '$s' is not running. Run ./scripts/up.sh first."; exit 2
  fi
done
docker pull -q "$BB" >/dev/null

# prints: "Allowed" or "Blocked (no-DNS|unreachable|timeout)"
probe() {
  local src=$1 host=$2 port=$3 net out rc
  if [ "$src" = backup ]; then net="admin"; else net="container:$src"; fi
  out=$(docker run --rm --network "$net" \
        --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 32m --cpus 0.2 \
        "$BB" nc -zw3 "$host" "$port" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then echo "Allowed"
  elif grep -qi 'bad address' <<<"$out"; then echo "Blocked (no-DNS)"
  elif grep -qi 'unreachable' <<<"$out"; then echo "Blocked (unreachable)"
  else echo "Blocked (timeout)"
  fi
}

fail=0
declare -A ACTUAL
echo "Reachability test (expected vs actual)"
printf '%-8s %-10s %-9s %-24s %s\n' FROM TO EXPECTED ACTUAL RESULT
for s in "${SOURCES[@]}"; do
  for t in "${TARGETS[@]}"; do
    exp=${EXPECT[$s,$t]}
    if [ "$exp" = "-" ]; then ACTUAL[$s,$t]="—"; continue; fi
    act=$(probe "$s" "${HOST[$t]}" "${PORT[$t]}")
    ACTUAL[$s,$t]=$act
    if [ "${act%% *}" = "$exp" ]; then res=PASS; else res=FAIL; fail=$((fail+1)); fi
    printf '%-8s %-10s %-9s %-24s %s\n' "$s" "$t" "$exp" "$act" "$res"
  done
done

echo
echo "| From \\ To | api :5000 | db :5432 | cache :6379 | Internet (1.1.1.1:443) |"
echo "| --- | --- | --- | --- | --- |"
for s in "${SOURCES[@]}"; do
  label=$s; [ "$s" = backup ] && label="backup job"
  echo "| $label | ${ACTUAL[$s,api]} | ${ACTUAL[$s,db]} | ${ACTUAL[$s,cache]} | ${ACTUAL[$s,internet]} |"
done

echo
if [ $fail -eq 0 ]; then echo "ALL CELLS MATCH: netcheck OK"; else echo "$fail MISMATCH(ES): netcheck FAILED"; fi
exit $(( fail > 0 ))
