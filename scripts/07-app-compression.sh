#!/usr/bin/env bash
# The release notes say to compress at the application level instead of relying on ssh -C.
# What does that buy on the same files, and at what CPU cost on this machine?
# Also a cross-check: plain zlib with Z_HUFFMAN_ONLY should land where ssh -C on 10.6 landed.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CORPUS=$WORK/corpus
OUT=$RESULTS/07-app-compression.tsv

printf 'file\tmethod\traw_bytes\tout_bytes\tratio\tcpu_seconds\n' >"$OUT"
for f in access.log events.ndjson openssh-src.tar random.bin; do
  raw=$(stat -c %s "$CORPUS/$f")
  for m in "gzip -1" "gzip -6" "zstd -1" "zstd -3"; do
    # User + system CPU seconds of the pipeline (the compressor, plus wc, which is noise).
    TIMEFORMAT='%U %S'
    { time $m -c <"$CORPUS/$f" | wc -c >"$WORK/size.txt"; } 2>"$WORK/time.txt"
    out=$(cat "$WORK/size.txt")
    cpu=$(awk '{printf "%.2f", $1 + $2}' "$WORK/time.txt")
    printf '%s\t%s\t%s\t%s\t%.2f\t%s\n' "$f" "$m" "$raw" "$out" "$(echo "$raw / $out" | bc -l)" "$cpu" >>"$OUT"
  done
  "$ROOT/.venv/bin/python" - "$CORPUS/$f" "$f" "$raw" >>"$OUT" <<'PY'
import resource, sys, zlib
path, name, raw = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = open(path, "rb").read()
for label, level, strategy in [("zlib level 6 (ssh -C before 10.6)", 6, zlib.Z_DEFAULT_STRATEGY),
                               ("zlib Huffman only (ssh -C in 10.6)", 1, zlib.Z_HUFFMAN_ONLY)]:
    t0 = resource.getrusage(resource.RUSAGE_SELF)
    c = zlib.compressobj(level, zlib.DEFLATED, 15, 8, strategy)
    n = len(c.compress(data)) + len(c.flush())
    t1 = resource.getrusage(resource.RUSAGE_SELF)
    cpu = (t1.ru_utime - t0.ru_utime) + (t1.ru_stime - t0.ru_stime)
    print(f"{name}\t{label}\t{raw}\t{n}\t{raw / n:.2f}\t{cpu:.2f}")
PY
done
column -t -s $'\t' "$OUT" | tee "$RESULTS/07-app-compression.txt"
