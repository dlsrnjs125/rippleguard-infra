#!/usr/bin/env sh
set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cleanup() {
  if [ -f "$ROOT_DIR/.env" ]; then
    "$ROOT_DIR/scripts/phase2-down.sh"
  fi
}

trap cleanup EXIT HUP INT TERM

failures=0
summary=""

run_gate() {
  name="$1"
  shift
  if "$@"; then
    summary="${summary}${name}: PASS
"
  else
    status="$?"
    failures=$((failures + 1))
    summary="${summary}${name}: FAIL (${status})
"
  fi
}

run_gate validate-static "$ROOT_DIR/scripts/validate-static.sh"
run_gate phase2-up "$ROOT_DIR/scripts/phase2-up.sh"
run_gate phase2-check "$ROOT_DIR/scripts/phase2-check.sh"
run_gate phase2-local-llm-absent-check "$ROOT_DIR/scripts/phase2-local-llm-absent-check.sh"
run_gate phase2-e2e "$ROOT_DIR/scripts/phase2-e2e.sh"
run_gate phase2-retry-check "$ROOT_DIR/scripts/phase2-retry-check.sh"
run_gate phase2-timeout-check "$ROOT_DIR/scripts/phase2-timeout-check.sh"
run_gate phase2-duplicate-request-check "$ROOT_DIR/scripts/phase2-duplicate-request-check.sh"
run_gate phase2-duplicate-result-check "$ROOT_DIR/scripts/phase2-duplicate-result-check.sh"
run_gate phase2-conflict-check "$ROOT_DIR/scripts/phase2-conflict-check.sh"
run_gate phase2-artifact-digest-failure-check "$ROOT_DIR/scripts/phase2-artifact-digest-failure-check.sh"
run_gate phase2-missing-artifact-check "$ROOT_DIR/scripts/phase2-missing-artifact-check.sh"
run_gate phase2-contract-mismatch-check "$ROOT_DIR/scripts/phase2-contract-mismatch-check.sh"
run_gate phase2-snapshot-mismatch-check "$ROOT_DIR/scripts/phase2-snapshot-mismatch-check.sh"
run_gate phase2-recovery-check "$ROOT_DIR/scripts/phase2-recovery-check.sh"
run_gate phase2-reproducibility-check "$ROOT_DIR/scripts/phase2-reproducibility-check.sh"

printf '%s\n' "Phase 2 verification summary:"
printf '%s' "$summary"

if [ "$failures" -ne 0 ]; then
  echo "Phase 2 verification failed: $failures gate(s) failed" >&2
  exit 1
fi
