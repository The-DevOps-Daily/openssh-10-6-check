#!/usr/bin/env bash
# Record the machine the results came from, and which package repositories ship 10.6 today.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$RESULTS"
{
  echo "date: $(date -u +%Y-%m-%d)"
  echo "os: $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "arch: $(uname -m)"
  echo "cpus: $(nproc)"
  echo "memory: $(free -g | awk '/^Mem:/ {print $2}') GiB"
  echo "openssl: $(openssl version)"
  echo "system ssh: $(ssh -V 2>&1)"
  echo
  echo "# OpenSSH version in package repositories"
  curl -fsS https://formulae.brew.sh/api/formula/openssh.json |
    python3 -c 'import json, sys; print("homebrew:", json.load(sys.stdin)["versions"]["stable"])'
  curl -fsS https://archlinux.org/packages/core/x86_64/openssh/json/ |
    python3 -c 'import json, sys; d = json.load(sys.stdin); print("arch core:", d["pkgver"] + "-" + d["pkgrel"], "updated", d["last_update"][:10])'
  curl -fsS "https://sources.debian.org/api/src/openssh/" |
    python3 -c 'import json, sys; v = json.load(sys.stdin)["versions"][0]; print("debian:", v["version"], "in", ",".join(v["suites"]))'
} | tee "$RESULTS/00-environment.txt"
