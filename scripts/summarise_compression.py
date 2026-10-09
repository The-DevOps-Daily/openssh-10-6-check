"""Collapse results/05-compression.tsv into one row per file, direction and version pair.

Wire bytes move by a byte or two between runs, because where SSH cuts the
stream into packets changes where deflate flushes. The table shows the median
and the spread; seconds are the median of the runs.
"""
import csv
import statistics
import sys

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
groups = {}
for r in rows:
    groups.setdefault((r["file"], r["direction"], r["client"], r["server"]), []).append(r)

print(f'{"file":<17}{"direction":<10}{"client":<8}{"server":<8}{"raw MiB":>9}{"wire MiB":>10}'
      f'{"ratio":>8}{"spread B":>10}{"median s":>10}')
for (f, d, c, s), rs in sorted(groups.items()):
    raw = statistics.median(int(r["raw_bytes"]) for r in rs)
    wires = [int(r["wire_bytes"]) for r in rs]
    wire = statistics.median(wires)
    secs = statistics.median(float(r["seconds"]) for r in rs)
    print(f"{f:<17}{d:<10}{c:<8}{s:<8}{raw/2**20:>9.1f}{wire/2**20:>10.2f}{raw/wire:>8.2f}"
          f"{max(wires)-min(wires):>10}{secs:>10.2f}")
