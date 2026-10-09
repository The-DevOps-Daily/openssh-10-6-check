#!/usr/bin/env bash
# Build OpenSSH 10.5p1 and 10.6p1 side by side into ./opt/<version>.
# Nothing is installed system-wide and nothing needs root.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

# SHA256 sums are copied from the release notes, which publish them base64 encoded.
declare -A SUMS=(
  [10.5p1]="1E0oqDnqna+WnMaRUP3lmRCys5Nh2tgaO9bL0ZIY2xE="
  [10.6p1]="qdyVZd/+hkD2TYY80poyvEo9vewFZqf8RMXW7nZ9Xzk="
)

mkdir -p build opt results
for v in 10.5p1 10.6p1; do
  tarball="build/openssh-$v.tar.gz"
  [ -f "$tarball" ] || curl -fsSL -o "$tarball" "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$v.tar.gz"
  got=$(openssl dgst -sha256 -binary "$tarball" | base64)
  if [ "$got" != "${SUMS[$v]}" ]; then
    echo "checksum mismatch for $v: $got" >&2
    exit 1
  fi
  if [ ! -x "opt/$v/bin/ssh" ]; then
    rm -rf "build/openssh-$v"
    tar -xzf "$tarball" -C build
    (
      cd "build/openssh-$v"
      ./configure --prefix="$ROOT/opt/$v" \
        --sysconfdir="$ROOT/opt/$v/etc" \
        --with-privsep-path="$ROOT/opt/$v/var/empty" \
        --with-privsep-user="$(id -un)" \
        --with-zlib --without-pam >"$ROOT/build/configure-$v.log" 2>&1
      make -j4 >"$ROOT/build/make-$v.log" 2>&1
      make install-nokeys >>"$ROOT/build/make-$v.log" 2>&1
    )
  fi
  "opt/$v/bin/ssh" -V
done 2>&1 | tee results/01-build.txt
