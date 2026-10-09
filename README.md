# openssh-10-6-check

```bash
./run-all.sh
```

This repo builds OpenSSH 10.5p1 and 10.6p1 side by side and measures three changes in 10.6 (released 2026-10-06):

1. `ssh` refuses usernames with `\` or `$` given on the command line, so `ssh 'CORP\alice@host'` now fails before it connects.
2. `ssh -C` compression no longer uses LZ77 back-references (only Huffman coding), so text compresses about 1.5x instead of 5x to 9x.
3. `sshd` logs a warning by default when a client uses a key exchange that is not post-quantum.

Write-up: https://devops-daily.com/posts/openssh-10-6-domain-usernames-and-compression

Nothing is installed system-wide. Each sshd runs as your own user on `127.0.0.1`, ports 18022 to 18025. Only `08-shaped-link.sh` needs `sudo`, for a `tc` rule on the loopback device that matches port 18025 and is removed on exit.

## Requirements

Tested on Debian 12 (aarch64). You need `build-essential`, `libssl-dev`, `zlib1g-dev`, `zstd`, `rsync`, `git`, `bc`, [uv](https://docs.astral.sh/uv/), Go 1.27 (for the Go client), and curl built with libssh2. Versions used: paramiko 5.0.0, asyncssh 2.24.1, ansible-core 2.21.5, golang.org/x/crypto v0.58.0, libssh2 1.10.0.

## Stages

| Script | What it does | Output |
| --- | --- | --- |
| `01-build.sh` | Downloads both releases, checks the SHA256 sums from the release notes, builds into `opt/` | `results/01-build.txt` |
| `02-setup.sh` | Host key, client key, a client config and a bare git repo in `work/` | |
| `03-usernames.sh` | 4 usernames x 12 ways of passing them (ssh, scp, sftp, rsync, git, Ansible, ssh_config) x both clients, against one 10.6 sshd. The sshd log shows which names arrived | `results/03-usernames.*` |
| `04-corpus.py` | Seeded test files: an access log, NDJSON events, the OpenSSH source tar, random bytes | `results/04-corpus.txt` |
| `05-compression.sh` | Every client/server pair moves every file up and down with `-C`, 3 runs. Byte counts come from `ssh -v` | `results/05-compression.*` |
| `06-weakcrypto.sh` | 8 clients against a 10.5 and a 10.6 sshd: which key exchange they pick and whether sshd logs the new warning | `results/06-weakcrypto.*` |
| `07-app-compression.sh` | gzip and zstd on the same files, plus plain zlib with `Z_HUFFMAN_ONLY` as a cross-check | `results/07-app-compression.*` |
| `08-shaped-link.sh` | Times a 32 MiB download over a 20 Mbit/s `tc` link, 5 runs | `results/08-shaped-link.*` |

## Results

Usernames: of the 24 cases with `CORP\alice` or `svc-backup$`, 20 reached the server with 10.5 and were refused by 10.6 before it connected. The 4 that still work put the name in a literal `User` line in ssh_config. A `User ${VAR}` line is checked after expansion and is refused. `alice@corp.example.com` works everywhere except inside an `ssh://` URI, where both versions reject it.

Compression (wire bytes, set by the side that sends the data):

| File | Raw | Sender 10.5p1 | Sender 10.6p1 |
| --- | ---: | ---: | ---: |
| access.log | 32.0 MiB | 3.71 MiB (8.62x) | 21.09 MiB (1.52x) |
| events.ndjson | 32.0 MiB | 6.00 MiB (5.34x) | 20.09 MiB (1.59x) |
| openssh-src.tar | 11.2 MiB | 2.25 MiB (4.99x) | 6.93 MiB (1.62x) |
| random.bin | 16.0 MiB | 16.01 MiB (1.00x) | 16.01 MiB (1.00x) |

Warnings from a default 10.6 sshd: OpenSSH 10.5p1, 10.6p1 and 9.2p1, asyncssh 2.24.1 and Go x/crypto v0.58.0 picked a post-quantum key exchange and caused no warning. paramiko 5.0.0, libssh2 1.10.0 and an OpenSSH client limited to `curve25519-sha256` did. sshd 10.5p1 logged no warning for any client.

The timings in `08-shaped-link.txt` vary between runs because the test machine was doing other work. The byte counts are exact and do not depend on load.

## License

MIT
