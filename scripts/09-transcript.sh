#!/usr/bin/env bash
# A short recorded session for the write-up: the commands and their real output.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
OUT=$RESULTS/09-transcript.txt
B=$WORK/base_config
S105=$(ssh_bin 10.5p1 ssh)
S106=$(ssh_bin 10.6p1 ssh)

start_sshd 10.6p1 18022 "$WORK/transcript-sshd.log" "LogLevel VERBOSE" || exit 1
trap 'stop_sshd 10.6p1 18022' EXIT

show() {  # show <displayed command> <command...>
  local shown=$1
  shift
  echo "\$ $shown"
  "$@" 2>&1 | grep -v '^\s*$'
  echo "[exit ${PIPESTATUS[0]}]"
  echo
}

{
  echo '# every ssh below also gets -F work/base_config: port 18022, the test key, BatchMode'
  echo
  show "ssh -V   # 10.5p1" "$S105" -V
  show "ssh -V   # 10.6p1" "$S106" -V
  show "ssh 'CORP\\alice@127.0.0.1' true   # 10.5p1" "$S105" -F "$B" 'CORP\alice@127.0.0.1' true
  show "ssh 'CORP\\alice@127.0.0.1' true   # 10.6p1" "$S106" -F "$B" 'CORP\alice@127.0.0.1' true
  show "ssh -o 'User=CORP\\alice' 127.0.0.1 true   # 10.6p1" "$S106" -F "$B" -o 'User=CORP\alice' 127.0.0.1 true
  printf 'Host winbox\n  HostName 127.0.0.1\n  User CORP\\alice\n' >"$WORK/cfg-transcript"
  cat "$B" >>"$WORK/cfg-transcript"
  show "head -3 ssh_config   # the Host block the next two commands use" sed -n 1,3p "$WORK/cfg-transcript"
  show "ssh winbox true   # 10.6p1, User line in ssh_config" "$S106" -F "$WORK/cfg-transcript" winbox true
  printf 'Host winbox\n  HostName 127.0.0.1\n  User ${WIN_USER}\n' >"$WORK/cfg-transcript-env"
  cat "$B" >>"$WORK/cfg-transcript-env"
  show "WIN_USER='CORP\\alice' ssh winbox true   # 10.6p1, User \${WIN_USER} in ssh_config" \
    env WIN_USER='CORP\alice' "$S106" -F "$WORK/cfg-transcript-env" winbox true
  show "ssh 'alice@corp.example.com@127.0.0.1' true   # 10.6p1, UPN form" "$S106" -F "$B" 'alice@corp.example.com@127.0.0.1' true
  echo "# what the 10.6 sshd logged for the three attempts that reached it:"
  grep -E '^Invalid user' "$WORK/transcript-sshd.log" | sed -E 's/port [0-9]+/port N/'
} 2>&1 | scrub >"$OUT"
cat "$OUT"
