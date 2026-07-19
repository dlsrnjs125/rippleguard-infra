#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
EXPECTED_CONTRACTS_REPO="dlsrnjs125/rippleguard-contracts"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rippleguard-contracts-baseline.XXXXXX")"

trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

git clone --filter=blob:none "https://github.com/$EXPECTED_CONTRACTS_REPO.git" "$WORK_DIR"
git -C "$WORK_DIR" fetch origin main

validate_baseline() {
  baseline="$1"
  topics="$2"
  event_types_key="$3"
  commit_key="$4"

  contracts_repo="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["contractsRepository"])' "$baseline")"
  contracts_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$baseline" "$commit_key")"

  if [ "$contracts_repo" != "$EXPECTED_CONTRACTS_REPO" ]; then
    echo "Unexpected contracts repository: $contracts_repo" >&2
    exit 1
  fi
  if ! git -C "$WORK_DIR" merge-base --is-ancestor "$contracts_sha" origin/main; then
    echo "Pinned contracts commit is not contained in origin/main: $contracts_sha" >&2
    exit 1
  fi

  git -C "$WORK_DIR" checkout -q "$contracts_sha"
  python3 "$ROOT_DIR/scripts/check-topic-contracts.py" \
    --contracts-dir "$WORK_DIR" \
    --baseline "$baseline" \
    --topics "$topics" \
    --event-types-key "$event_types_key"
}

validate_baseline "$ROOT_DIR/contracts/phase0-baseline.json" "$ROOT_DIR/kafka/topics/phase1-events.txt" eventTypes contractsMainMergeCommitSha
validate_baseline "$ROOT_DIR/contracts/phase1-core-baseline.json" "$ROOT_DIR/kafka/topics/phase1-events.txt" eventTypes contractsMainCommitSha
python3 "$ROOT_DIR/scripts/validate-phase1-manifest.py"
