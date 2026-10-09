#!/usr/bin/env bash
# Bytes are the cause, seconds are what people notice. Download the access log over a
# 20 Mbit/s link and time it: ssh -C from a 10.5 server, ssh -C from a 10.6 server,
# no compression, and zstd -1 in a pipe with ssh compression off.
#
# The link is a tc token bucket on the loopback device that only matches port 18025,
# so nothing else on the machine is slowed down. Needs sudo for tc; removed on exit.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CORPUS=$WORK/corpus
OUT=$RESULTS/08-shaped-link.tsv
PORT=18025
RATE=20mbit
RUNS=${RUNS:-3}
FILE=access.log
CLIENT=$(ssh_bin 10.6p1 ssh)

shape_on() {
  sudo tc qdisc add dev lo root handle 1: prio bands 3 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
  # lo carries 64 KiB segments, so the bucket must hold several of them, and a 1 s
  # queue keeps tbf from dropping packets (drops add TCP retransmit stalls).
  sudo tc qdisc add dev lo parent 1:3 handle 30: tbf rate "$RATE" burst 256kb latency 1s
  sudo tc filter add dev lo parent 1: protocol ip prio 1 u32 match ip sport "$PORT" 0xffff flowid 1:3
  sudo tc filter add dev lo parent 1: protocol ip prio 1 u32 match ip dport "$PORT" 0xffff flowid 1:3
}
shape_off() { sudo tc qdisc del dev lo root 2>/dev/null || true; }
trap 'shape_off; for v in "${VERSIONS[@]}"; do stop_sshd "$v" "$PORT"; done' EXIT

shape_off
shape_on || exit 1
tc qdisc show dev lo >"$WORK/tc.txt"

timed() {  # timed <label> <server> <command...>
  local label=$1 server=$2 run t0 t1
  shift 2
  for run in $(seq 1 "$RUNS"); do
    t0=$(date +%s.%N)
    "$@" >"$WORK/shaped.out" 2>/dev/null || { echo "failed: $label" >&2; return 1; }
    t1=$(date +%s.%N)
    cmp -s "$WORK/shaped.out" "$CORPUS/$FILE" || { echo "corrupt transfer: $label" >&2; return 1; }
    printf '%s\t%s\t%s\t%.2f\n' "$label" "$server" "$run" "$(echo "$t1 - $t0" | bc)" >>"$OUT"
  done
}

printf 'method\tserver\trun\tseconds\n' >"$OUT"
for server in "${VERSIONS[@]}"; do
  start_sshd "$server" "$PORT" "$WORK/shaped-sshd-$server.log" || exit 1
  timed "ssh -C" "$server" "$CLIENT" -F "$WORK/base_config" -p "$PORT" -C 127.0.0.1 "cat $CORPUS/$FILE" || exit 1
  timed "ssh, no compression" "$server" "$CLIENT" -F "$WORK/base_config" -p "$PORT" -o Compression=no 127.0.0.1 "cat $CORPUS/$FILE" || exit 1
  timed "zstd -1 | ssh, no compression" "$server" \
    sh -c "'$CLIENT' -F '$WORK/base_config' -p $PORT -o Compression=no 127.0.0.1 'zstd -1 -c $CORPUS/$FILE' | zstd -dc" || exit 1
  stop_sshd "$server" "$PORT"
done

"$ROOT/.venv/bin/python" - "$OUT" "$RATE" <<'PY' | tee "$RESULTS/08-shaped-link.txt"
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
groups = {}
for r in rows:
    groups.setdefault((r["method"], r["server"]), []).append(float(r["seconds"]))
print(f"32 MiB access log, downloaded over a {sys.argv[2]} link, client OpenSSH 10.6p1")
print(f'{"method":<32}{"server":<9}{"median s":>9}   runs')
for (m, s), secs in groups.items():
    print(f"{m:<32}{s:<9}{statistics.median(secs):>9.2f}   {', '.join(f'{x:.2f}' for x in secs)}")
PY
