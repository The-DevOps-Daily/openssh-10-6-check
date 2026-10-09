# Shared helpers. Source this file; do not run it.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$ROOT/work
RESULTS=$ROOT/results
VERSIONS=(10.5p1 10.6p1)

ssh_bin() { echo "$ROOT/opt/$1/bin/$2"; }

# start_sshd <version> <port> <logfile> [extra sshd_config lines...]
start_sshd() {
  local v=$1 port=$2 log
  log=$(realpath -m "$3")  # sshd chdirs to / when it daemonises
  shift 3
  local cfg=$WORK/sshd-$v-$port.conf
  {
    echo "Port $port"
    echo "ListenAddress 127.0.0.1"
    echo "HostKey $WORK/hostkey_ed25519"
    echo "AuthorizedKeysFile $WORK/authorized_keys"
    echo "PidFile $WORK/sshd-$v-$port.pid"
    echo "StrictModes no"
    # The tests open many failing connections from one address on purpose.
    echo "PerSourcePenalties no"
    echo "Subsystem sftp $ROOT/opt/$v/libexec/sftp-server"
    for line in "$@"; do echo "$line"; done
  } >"$cfg"
  : >"$log"
  "$ROOT/opt/$v/sbin/sshd" -f "$cfg" -E "$log"
  local i
  for i in $(seq 1 50); do
    if ss -ltn "sport = :$port" | grep -q LISTEN; then return 0; fi
    sleep 0.1
  done
  echo "sshd $v did not start on $port" >&2
  cat "$log" >&2
  return 1
}

stop_sshd() {
  local v=$1 port=$2 pidfile=$WORK/sshd-$1-$2.pid
  if [ -f "$pidfile" ]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
  sleep 0.3
}

# Recorded output must not carry the local account name or home path.
scrub() { sed -e "s#$ROOT#.#g" -e "s#$HOME#~#g" -e "s#\\b$(id -un)\\b#localuser#g"; }
