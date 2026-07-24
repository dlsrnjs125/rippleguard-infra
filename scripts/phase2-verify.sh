#!/usr/bin/env sh
set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SUMMARY_JSONL="$(mktemp "${TMPDIR:-/tmp}/rippleguard-phase2-verify.XXXXXX")"

cleanup() {
  rm -f "$SUMMARY_JSONL"
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
    python3 - "$SUMMARY_JSONL" "$name" "PASS" "0" <<'PY'
import json
import sys

path, name, result, exit_code = sys.argv[1:]
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({"name": name, "result": result, "exitCode": int(exit_code)}) + "\n")
PY
  else
    status="$?"
    failures=$((failures + 1))
    summary="${summary}${name}: FAIL (${status})
"
    python3 - "$SUMMARY_JSONL" "$name" "FAIL" "$status" <<'PY'
import json
import sys

path, name, result, exit_code = sys.argv[1:]
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({"name": name, "result": result, "exitCode": int(exit_code)}) + "\n")
PY
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

python3 - "$ROOT_DIR" "$SUMMARY_JSONL" "$failures" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
failures = int(sys.argv[3])
manifest = json.loads((root / "manifests/phase2-loan-decision.json").read_text(encoding="utf-8"))
gates = [
    json.loads(line)
    for line in summary_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
report = {
    "command": "make phase2-verify",
    "result": "PASS" if failures == 0 else "FAIL",
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "commitBaseline": manifest["contractBaseline"],
    "imageDigests": {service["name"]: service["imageDigest"] for service in manifest["services"]},
    "modelArtifactDigest": manifest["modelBaseline"]["modelArtifactDigest"],
    "details": {
        "gates": gates,
        "failedGateCount": failures,
        "releaseManifestStatus": manifest["publicationStatus"],
    },
    "knownLimitations": [
        blocker["reason"]
        for blocker in manifest.get("knownBlockers", [])
    ],
}
target = root / "evidence" / "phase2" / "final-verification.json"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [ "$failures" -ne 0 ]; then
  echo "Phase 2 verification failed: $failures gate(s) failed" >&2
  exit 1
fi
