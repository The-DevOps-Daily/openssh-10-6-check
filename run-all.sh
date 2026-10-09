#!/usr/bin/env bash
# Build both versions, then run every stage. Each stage writes to results/ and can be rerun alone.
set -euo pipefail
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || { uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python -r requirements.txt; }
scripts/00-environment.sh
scripts/01-build.sh
scripts/02-setup.sh
scripts/03-usernames.sh
.venv/bin/python scripts/04-corpus.py | tee results/04-corpus.txt
scripts/05-compression.sh
scripts/06-weakcrypto.sh
scripts/07-app-compression.sh
scripts/08-shaped-link.sh   # needs sudo for tc
scripts/09-transcript.sh
