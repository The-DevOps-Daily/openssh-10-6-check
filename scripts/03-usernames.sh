#!/usr/bin/env bash
# Which ways of passing a username does OpenSSH 10.6 refuse, and which still reach the server?
# One sshd (10.6) listens on 127.0.0.1:18022. Each client version tries every username
# through every entry path. The server log shows whether the name got through.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ -f "$WORK/base_config" ] || { echo "run 02-setup.sh first" >&2; exit 1; }

LOG=$WORK/usernames-sshd.log
OUT=$RESULTS/03-usernames.tsv
ME=$(id -un)
BASE=$WORK/base_config
ANSIBLE=$ROOT/.venv/bin/ansible

USERNAMES=("$ME" 'CORP\alice' 'alice@corp.example.com' 'svc-backup$')
PATHS=(user@host -l "-o User=" ssh-uri config-literal config-env scp sftp rsync git ansible ansible+ssh_config)

start_sshd 10.6p1 18022 "$LOG" "LogLevel VERBOSE" || exit 1
trap 'stop_sshd 10.6p1 18022; pkill -f "$WORK/cp" 2>/dev/null' EXIT

run_path() {
  local v=$1 path=$2 u=$3
  local ssh scp sftp cfg
  ssh=$(ssh_bin "$v" ssh); scp=$(ssh_bin "$v" scp); sftp=$(ssh_bin "$v" sftp)
  case "$path" in
    user@host) "$ssh" -F "$BASE" "$u@127.0.0.1" true ;;
    -l) "$ssh" -F "$BASE" -l "$u" 127.0.0.1 true ;;
    "-o User=") "$ssh" -F "$BASE" -o "User=$u" 127.0.0.1 true ;;
    ssh-uri) "$ssh" -F "$BASE" "ssh://$u@127.0.0.1:18022" true ;;
    config-literal)
      cfg=$WORK/cfg-literal
      printf 'Host t\n  HostName 127.0.0.1\n  User %s\n' "$u" >"$cfg"
      cat "$BASE" >>"$cfg"
      "$ssh" -F "$cfg" t true ;;
    config-env)
      cfg=$WORK/cfg-env
      printf 'Host t\n  HostName 127.0.0.1\n  User ${SSH_TEST_USER}\n' >"$cfg"
      cat "$BASE" >>"$cfg"
      SSH_TEST_USER=$u "$ssh" -F "$cfg" t true ;;
    scp) "$scp" -F "$BASE" -S "$ssh" "$u@127.0.0.1:/etc/hostname" "$WORK/scp.out" ;;
    sftp) echo bye | "$sftp" -F "$BASE" -S "$ssh" -b - "$u@127.0.0.1" ;;
    rsync) rsync -e "$ssh -F $BASE" "$u@127.0.0.1:/etc/hostname" "$WORK/rsync.out" ;;
    git) GIT_SSH_COMMAND="$ssh -F $BASE" git ls-remote "$u@127.0.0.1:$WORK/repo.git" ;;
    ansible|ansible+ssh_config)
      # ansible: the username in ansible_user, which Ansible passes as -o User=.
      # ansible+ssh_config: no ansible_user; the name sits in an ssh_config User line.
      local inv=$WORK/inventory.yml sshcfg=$BASE
      if [ "$path" = ansible+ssh_config ]; then
        sshcfg=$WORK/cfg-ansible
        printf 'Host 127.0.0.1\n  User %s\n' "$u" >"$sshcfg"
        cat "$BASE" >>"$sshcfg"
      fi
      U=$u SSHBIN=$ssh B=$sshcfg MODE=$path "$ROOT/.venv/bin/python" - >"$inv" <<'PY'
import json, os
host = {"ansible_host": "127.0.0.1", "ansible_port": 18022,
        "ansible_ssh_executable": os.environ["SSHBIN"],
        "ansible_ssh_common_args": "-F " + os.environ["B"],
        "ansible_python_interpreter": "/usr/bin/python3"}
if os.environ["MODE"] == "ansible":
    host["ansible_user"] = os.environ["U"]
print(json.dumps({"all": {"hosts": {"t": host}}}))
PY
      cfg=$inv
      # Ansible keys its ControlPath on the user it was given, so with no ansible_user every
      # name would reuse one master connection. A directory per run keeps them apart.
      # Ansible prints the failure on stdout; send it where the other paths print theirs.
      ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_SSH_CONTROL_PATH_DIR=$WORK/cp-$v-${path//+/_}-$(printf %s "$u" | md5sum | cut -c1-8) \
        "$ANSIBLE" all -i "$cfg" -m ping -o </dev/null 1>&2 ;;
  esac
}

printf 'client\tpath\tusername\texit\toutcome\tserver_saw\tclient_message\n' >"$OUT"
for v in "${VERSIONS[@]}"; do
  for path in "${PATHS[@]}"; do
    for u in "${USERNAMES[@]}"; do
      before=$(wc -l <"$LOG")
      err=$(run_path "$v" "$path" "$u" 2>&1 >/dev/null; echo "rc=$?")
      rc=${err##*rc=}
      err=${err%rc=*}
      sleep 0.2
      new=$(tail -n +"$((before + 1))" "$LOG")
      saw=$(printf '%s\n' "$new" | sed -nE 's/^(Invalid user|Accepted publickey for) (.*) from 127\.0\.0\.1.*/\2/p' | head -1)
      # Other connections (an Ansible master closing) can log in the same window, so the
      # client's own refusal message wins over the server log.
      if printf '%s' "$err" | grep -q 'remote username contains invalid characters'; then outcome=refused-by-client; saw=
      elif printf '%s\n' "$new" | grep -q '^Accepted publickey'; then outcome=logged-in
      elif printf '%s' "$err" | grep -q '^usage:'; then outcome=usage-error
      elif [ -n "$saw" ]; then outcome=reached-server
      elif [ -z "$new" ]; then outcome=refused-by-client
      else outcome=other
      fi
      msg=$(printf '%s' "$err" | grep -v '^\s*$' | grep -m1 -iE 'invalid|refus|error|denied|fatal|unreachable|failed|usage' | tr '\t' ' ' | cut -c1-160)
      label=$u; [ "$u" = "$ME" ] && label='<local user>'
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$path" "$label" "$rc" "$outcome" "$saw" "$msg" | scrub >>"$OUT"
    done
  done
done

# Pivot: one row per entry path and username, one column per client version.
"$ROOT/.venv/bin/python" - "$OUT" >"$RESULTS/03-usernames.txt" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
grid = {}
for r in rows:
    grid.setdefault((r["path"], r["username"]), {})[r["client"]] = r["outcome"]
print(f'{"path":<20}{"username":<26}{"10.5p1":<20}{"10.6p1":<20}')
for (path, user), cells in grid.items():
    a, b = cells.get("10.5p1", "?"), cells.get("10.6p1", "?")
    flag = "  <- changed" if a != b else ""
    print(f"{path:<20}{user:<26}{a:<20}{b:<20}{flag}")
PY
cat "$RESULTS/03-usernames.txt"
