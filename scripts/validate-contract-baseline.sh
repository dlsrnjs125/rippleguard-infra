#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BASELINE="$ROOT_DIR/contracts/phase0-baseline.json"
CONTRACTS_REPO="$(python3 -c 'import json; print(json.load(open("'"$BASELINE"'"))["contractsRepository"])')"
CONTRACTS_SHA="$(python3 -c 'import json; print(json.load(open("'"$BASELINE"'"))["contractsMainMergeCommitSha"])')"
WORK_DIR="${TMPDIR:-/tmp}/rippleguard-contracts-baseline"

rm -rf "$WORK_DIR"
git clone --filter=blob:none "https://github.com/$CONTRACTS_REPO.git" "$WORK_DIR"
git -C "$WORK_DIR" checkout "$CONTRACTS_SHA"
python3 "$ROOT_DIR/scripts/check-topic-contracts.py" --contracts-dir "$WORK_DIR"
