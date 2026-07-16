#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BASELINE="$ROOT_DIR/contracts/phase0-baseline.json"
EXPECTED_CONTRACTS_REPO="dlsrnjs125/rippleguard-contracts"
CONTRACTS_REPO="$(python3 -c 'import json; print(json.load(open("'"$BASELINE"'"))["contractsRepository"])')"
CONTRACTS_SHA="$(python3 -c 'import json; print(json.load(open("'"$BASELINE"'"))["contractsMainMergeCommitSha"])')"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rippleguard-contracts-baseline.XXXXXX")"

trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

if [ "$CONTRACTS_REPO" != "$EXPECTED_CONTRACTS_REPO" ]; then
  echo "Unexpected contracts repository: $CONTRACTS_REPO" >&2
  exit 1
fi

git clone --filter=blob:none "https://github.com/$CONTRACTS_REPO.git" "$WORK_DIR"
git -C "$WORK_DIR" fetch origin main
if ! git -C "$WORK_DIR" merge-base --is-ancestor "$CONTRACTS_SHA" origin/main; then
  echo "Pinned contracts commit is not contained in origin/main: $CONTRACTS_SHA" >&2
  exit 1
fi
git -C "$WORK_DIR" checkout "$CONTRACTS_SHA"
python3 "$ROOT_DIR/scripts/check-topic-contracts.py" --contracts-dir "$WORK_DIR"
