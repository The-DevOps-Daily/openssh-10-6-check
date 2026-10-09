#!/usr/bin/env bash
# Keys, a client config and a bare git repo for the tests. Everything lands in ./work.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

rm -rf "$WORK"
mkdir -p "$WORK"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/hostkey_ed25519"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/id_ed25519"
cp "$WORK/id_ed25519.pub" "$WORK/authorized_keys"
git init -q --bare "$WORK/repo.git"

# Every client run uses this file, so the only thing that changes is the username.
cat >"$WORK/base_config" <<EOF
Host *
  Port 18022
  IdentityFile $WORK/id_ed25519
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
echo "setup done in ./work"
