#!/usr/bin/env bash
# sshd 10.6 turns on WarnWeakCrypto by default. Which common clients make it log a warning?
# Each client connects once to sshd 10.5p1 and once to sshd 10.6p1, both on default settings
# apart from LogLevel DEBUG1, which only adds the negotiated key exchange to the log.
# The warning itself is logged at INFO, the default level.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
OUT=$RESULTS/06-weakcrypto.tsv
PORT=18024
ME=$(id -un)
KEY=$WORK/id_ed25519
PY=$ROOT/.venv/bin/python

if [ ! -x "$ROOT/build/goclient" ]; then
  (cd "$ROOT/clients/go" && go build -o "$ROOT/build/goclient" .) || exit 1
fi

client_names=(
  "OpenSSH 10.6p1"
  "OpenSSH 10.5p1"
  "OpenSSH 9.2p1 (Debian 12)"
  "OpenSSH 10.6p1, KexAlgorithms=curve25519-sha256"
  "paramiko $($PY -c 'import paramiko; print(paramiko.__version__)')"
  "asyncssh $($PY -c 'import asyncssh; print(asyncssh.__version__)')"
  "Go x/crypto/ssh $(sed -nE 's#.*golang.org/x/crypto (v[0-9.]+).*#\1#p' "$ROOT/clients/go/go.mod")"
  "libssh2 $(curl -V | sed -nE 's#.*libssh2/([0-9.]+).*#\1#p') (curl sftp)"
)

run_client() {
  case $1 in
    0) "$(ssh_bin 10.6p1 ssh)" -F "$WORK/base_config" -p "$PORT" 127.0.0.1 true ;;
    1) "$(ssh_bin 10.5p1 ssh)" -F "$WORK/base_config" -p "$PORT" 127.0.0.1 true ;;
    2) /usr/bin/ssh -F "$WORK/base_config" -p "$PORT" 127.0.0.1 true ;;
    3) "$(ssh_bin 10.6p1 ssh)" -F "$WORK/base_config" -p "$PORT" -o KexAlgorithms=curve25519-sha256 127.0.0.1 true ;;
    4) "$PY" "$ROOT/clients/paramiko_client.py" "$PORT" "$ME" "$KEY" ;;
    5) "$PY" "$ROOT/clients/asyncssh_client.py" "$PORT" "$ME" "$KEY" ;;
    6) "$ROOT/build/goclient" "127.0.0.1:$PORT" "$ME" "$KEY" ;;
    7) curl -sS --insecure -u "$ME:" --key "$KEY" --pubkey "$KEY.pub" "sftp://127.0.0.1:$PORT/etc/hostname" -o /dev/null ;;
  esac
}

printf 'server\tclient\tclient_exit\tkex\twarning_logged\twarning_line\n' >"$OUT"
for server in "${VERSIONS[@]}"; do
  log=$WORK/weakcrypto-sshd-$server.log
  start_sshd "$server" "$PORT" "$log" "LogLevel DEBUG1" || exit 1
  for i in "${!client_names[@]}"; do
    before=$(wc -l <"$log")
    run_client "$i" >/dev/null 2>"$WORK/weakcrypto-client.err"
    rc=$?
    sleep 0.5
    new=$(tail -n +"$((before + 1))" "$log")
    kex=$(sed -nE 's/^debug1: kex: algorithm: ([^ ]+).*/\1/p' <<<"$new" | head -1)
    warn=$(grep -m1 'post-quantum' <<<"$new" | sed -E 's/port [0-9]+/port N/')
    logged=no; [ -n "$warn" ] && logged=yes
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$server" "${client_names[$i]}" "$rc" "${kex:-?}" "$logged" "$warn" | scrub >>"$OUT"
  done
  stop_sshd "$server" "$PORT"
done
column -t -s $'\t' "$OUT" | cut -c1-200 | tee "$RESULTS/06-weakcrypto.txt"

# Can the warning be switched off for one group of clients only? Try it in a Match block.
{
  echo
  echo "# sshd -t with 'Match Address 127.0.0.1' + 'WarnWeakCrypto no-pq-kex':"
  cfg=$WORK/sshd-match-test.conf
  sed -n '1,/^Subsystem/p' "$WORK/sshd-10.6p1-$PORT.conf" >"$cfg"
  printf 'Match Address 127.0.0.1\n  WarnWeakCrypto no-pq-kex\n' >>"$cfg"
  "$ROOT/opt/10.6p1/sbin/sshd" -t -f "$cfg" 2>&1; echo "[exit $?]"
  echo "# and as a global option:"
  sed -n '1,/^Subsystem/p' "$WORK/sshd-10.6p1-$PORT.conf" >"$cfg"
  echo 'WarnWeakCrypto no-pq-kex' >>"$cfg"
  "$ROOT/opt/10.6p1/sbin/sshd" -t -f "$cfg" 2>&1; echo "[exit $?]"
} | scrub | tee -a "$RESULTS/06-weakcrypto.txt"
