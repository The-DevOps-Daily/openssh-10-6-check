#!/usr/bin/env bash
# How much does `ssh -C` still compress after 10.6, and which side decides?
# Every client/server pair moves each corpus file up and down with -C.
# The client's -v output reports raw and compressed bytes for both directions:
#   outgoing = compressed by the client (upload), incoming = compressed by the server (download).
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CORPUS=$WORK/corpus
[ -d "$CORPUS" ] || { echo "run 04-corpus.py first" >&2; exit 1; }
OUT=$RESULTS/05-compression.tsv
RUNS=${RUNS:-3}
PORT=18023

summarise() {
  "$ROOT/.venv/bin/python" "$ROOT/scripts/summarise_compression.py" "$OUT" >"$RESULTS/05-compression.txt"
  cat "$RESULTS/05-compression.txt"
}
# SUMMARY_ONLY=1 rebuilds the table from an existing TSV without sending anything.
if [ "${SUMMARY_ONLY:-0}" = 1 ]; then summarise; exit; fi

printf 'server\tclient\tdirection\tfile\trun\traw_bytes\twire_bytes\tfactor\tseconds\n' >"$OUT"

measure() {
  local server=$1 client=$2 dir=$3 file=$4 run=$5 ssh dbg t0 t1 line
  ssh=$(ssh_bin "$client" ssh)
  dbg=$WORK/compress-debug.txt
  t0=$(date +%s.%N)
  if [ "$dir" = upload ]; then
    "$ssh" -F "$WORK/base_config" -p "$PORT" -C -v 127.0.0.1 'cat >/dev/null' <"$CORPUS/$file" 2>"$dbg"
    line=$(grep 'compress outgoing' "$dbg")
  else
    "$ssh" -F "$WORK/base_config" -p "$PORT" -C -v 127.0.0.1 "cat $CORPUS/$file" 2>"$dbg" >/dev/null
    line=$(grep 'compress incoming' "$dbg")
  fi
  t1=$(date +%s.%N)
  # debug1: compress outgoing: raw data 33558016, compressed 21005531, factor 0.63
  local raw wire factor
  raw=$(sed -nE 's/.*raw data ([0-9]+).*/\1/p' <<<"$line")
  wire=$(sed -nE 's/.*compressed ([0-9]+).*/\1/p' <<<"$line")
  factor=$(sed -nE 's/.*factor ([0-9.]+).*/\1/p' <<<"$line")
  [ -n "$raw" ] || { echo "no compression line for $server/$client/$dir/$file" >&2; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.3f\n' "$server" "$client" "$dir" "$file" "$run" \
    "$raw" "$wire" "$factor" "$(echo "$t1 - $t0" | bc)" >>"$OUT"
}

for server in "${VERSIONS[@]}"; do
  start_sshd "$server" "$PORT" "$WORK/compress-sshd-$server.log" || exit 1
  for client in "${VERSIONS[@]}"; do
    for file in access.log events.ndjson openssh-src.tar random.bin; do
      for dir in upload download; do
        for run in $(seq 1 "$RUNS"); do
          measure "$server" "$client" "$dir" "$file" "$run" || exit 1
        done
      done
    done
  done
  stop_sshd "$server" "$PORT"
done

summarise
