#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cleanup() {
  if [ -f "$ROOT_DIR/.env" ]; then
    "$ROOT_DIR/scripts/phase2-down.sh"
  fi
}

trap cleanup EXIT HUP INT TERM

"$ROOT_DIR/scripts/validate-static.sh"
"$ROOT_DIR/scripts/phase2-up.sh"
"$ROOT_DIR/scripts/phase2-check.sh"
"$ROOT_DIR/scripts/phase2-local-llm-absent-check.sh"
"$ROOT_DIR/scripts/phase2-e2e.sh"
"$ROOT_DIR/scripts/phase2-retry-check.sh"
"$ROOT_DIR/scripts/phase2-timeout-check.sh"
"$ROOT_DIR/scripts/phase2-duplicate-request-check.sh"
"$ROOT_DIR/scripts/phase2-duplicate-result-check.sh"
"$ROOT_DIR/scripts/phase2-conflict-check.sh"
"$ROOT_DIR/scripts/phase2-artifact-digest-failure-check.sh"
"$ROOT_DIR/scripts/phase2-missing-artifact-check.sh"
"$ROOT_DIR/scripts/phase2-contract-mismatch-check.sh"
"$ROOT_DIR/scripts/phase2-snapshot-mismatch-check.sh"
"$ROOT_DIR/scripts/phase2-recovery-check.sh"
"$ROOT_DIR/scripts/phase2-reproducibility-check.sh"
