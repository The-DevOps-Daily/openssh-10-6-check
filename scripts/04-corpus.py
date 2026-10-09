#!/usr/bin/env python3
"""Write the files that 05-compression.sh sends over SSH.

Seeded, so every run produces the same bytes. The access log uses only the
documentation IP ranges (RFC 5737), so no real address ends up in the corpus.
"""
import gzip
import hashlib
import json
import random
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "work" / "corpus"
MIB = 1024 * 1024


def access_log(path: Path, size: int, rng: random.Random) -> None:
    nets = ["192.0.2.", "198.51.100.", "203.0.113."]
    paths = ["/", "/api/v1/orders", "/api/v1/orders/{id}", "/api/v1/users/{id}",
             "/static/app.{h}.js", "/static/app.{h}.css", "/healthz", "/login",
             "/api/v1/search?q={q}", "/images/{id}.webp"]
    agents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15",
        "Mozilla/5.0 (X11; Linux x86_64; rv:143.0) Gecko/20100101 Firefox/143.0",
        "kube-probe/1.37", "curl/8.16.0", "Go-http-client/2.0",
    ]
    words = ["deploy", "nginx", "postgres", "billing", "invoice", "redis", "queue", "retry"]
    t = datetime(2026, 10, 1, tzinfo=timezone.utc)
    written = 0
    with path.open("w") as f:
        while written < size:
            t += timedelta(milliseconds=rng.randint(1, 400))
            p = rng.choice(paths).format(id=rng.randint(1, 99999), h=f"{rng.getrandbits(32):08x}",
                                         q=rng.choice(words))
            status = rng.choices([200, 201, 204, 301, 304, 404, 500, 502], [70, 5, 5, 3, 8, 6, 2, 1])[0]
            line = (f'{rng.choice(nets)}{rng.randint(1, 254)} - - [{t:%d/%b/%Y:%H:%M:%S +0000}] '
                    f'"{rng.choice(["GET"] * 8 + ["POST", "PUT"])} {p} HTTP/1.1" {status} '
                    f'{rng.randint(0, 48000)} "-" "{rng.choice(agents)}" rt={rng.random():.3f}\n')
            f.write(line)
            written += len(line)


def events(path: Path, size: int, rng: random.Random) -> None:
    services = ["checkout", "inventory", "payments", "auth", "search", "mailer"]
    levels = ["info"] * 12 + ["warn"] * 3 + ["error"]
    t = datetime(2026, 10, 1, tzinfo=timezone.utc)
    written = 0
    with path.open("w") as f:
        while written < size:
            t += timedelta(milliseconds=rng.randint(1, 200))
            ev = {
                "ts": t.isoformat(timespec="milliseconds"),
                "level": rng.choice(levels),
                "service": rng.choice(services),
                "trace_id": f"{rng.getrandbits(128):032x}",
                "span_id": f"{rng.getrandbits(64):016x}",
                "msg": rng.choice(["request completed", "cache miss", "retrying upstream call",
                                   "payment authorised", "user signed in", "queue lag above threshold"]),
                "duration_ms": round(rng.expovariate(1 / 40), 2),
                "http": {"method": rng.choice(["GET", "POST"]), "status": rng.choice([200, 200, 200, 404, 500]),
                         "route": rng.choice(["/orders/:id", "/cart", "/search", "/login"])},
            }
            line = json.dumps(ev, separators=(",", ":")) + "\n"
            f.write(line)
            written += len(line)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    access_log(OUT / "access.log", 32 * MIB, random.Random(1))
    events(OUT / "events.ndjson", 32 * MIB, random.Random(2))
    # Real text: the OpenSSH 10.6p1 source tree, as the uncompressed tar from the release.
    with gzip.open(ROOT / "build" / "openssh-10.6p1.tar.gz", "rb") as src, (OUT / "openssh-src.tar").open("wb") as dst:
        shutil.copyfileobj(src, dst)
    (OUT / "random.bin").write_bytes(random.Random(3).randbytes(16 * MIB))
    for p in sorted(OUT.iterdir()):
        digest = hashlib.sha256(p.read_bytes()).hexdigest()[:16]
        print(f"{p.name:<18}{p.stat().st_size:>12} bytes  sha256 {digest}")


if __name__ == "__main__":
    main()
