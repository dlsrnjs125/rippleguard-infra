#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

require_env_file
require_command docker
require_command git
require_command python3

python3 "$ROOT_DIR/scripts/validate-phase2-manifest.py" --check-artifacts

python3 - "$PHASE2_MANIFEST" "$ROOT_DIR" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
root = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
repo_by_service = {
    "loan-service": root.parent / "rippleguard-loan-service",
    "governance-service": root.parent / "rippleguard-governance-service",
    "agent-runtime": root.parent / "rippleguard-agent-runtime",
    "audit-replay-service": root.parent / "rippleguard-audit-replay-service",
}
failures = []

contracts_repo = root.parent / "rippleguard-contracts"
contract_commit = manifest["contractBaseline"]["sourceCommit"]
repo_by_name = {"contracts": (contracts_repo, contract_commit)}
for service in manifest["services"]:
    repo_by_name[service["name"]] = (repo_by_service[service["name"]], service["sourceCommit"])

for name, (repo, expected_commit) in repo_by_name.items():
    if not (repo / ".git").is_dir():
        failures.append(f"{name}: checkout not found at {repo}")
        continue
    actual_commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if actual_commit != expected_commit:
        failures.append(f"{name}: HEAD mismatch expected={expected_commit} actual={actual_commit}")
    status = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True)
    if status.strip():
        failures.append(f"{name}: checkout is dirty")

if failures:
    print("\n".join(failures))
    sys.exit(1)

print("Phase 2 source checkout preflight passed")
PY

python3 "$ROOT_DIR/scripts/verify-phase2-images.py"
compose config >/dev/null

echo "Phase 2 preflight passed"
