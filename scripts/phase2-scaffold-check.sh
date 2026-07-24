#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

require_env_file
load_env
require_command docker
require_command git
require_command python3

python3 "$ROOT_DIR/scripts/validate-phase2-manifest.py" --check-artifacts

python3 - "$PHASE2_MANIFEST" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
env_by_name = {
    "contracts": ("RIPPLEGUARD_CONTRACTS_REPO", manifest["contractBaseline"]["sourceCommit"]),
}
for service in manifest["services"]:
    env_name = {
        "loan-service": "RIPPLEGUARD_LOAN_REPO",
        "governance-service": "RIPPLEGUARD_GOVERNANCE_REPO",
        "agent-runtime": "RIPPLEGUARD_AGENT_RUNTIME_REPO",
        "audit-replay-service": "RIPPLEGUARD_AUDIT_REPO",
    }[service["name"]]
    env_by_name[service["name"]] = (env_name, service["sourceCommit"])

failures = []
for name, (env_name, expected_commit) in env_by_name.items():
    raw_path = os.environ.get(env_name, "")
    if not raw_path:
        failures.append(f"{env_name} is required")
        continue
    repo = Path(raw_path)
    if not repo.is_absolute():
        failures.append(f"{env_name} must be an absolute path: {raw_path}")
        continue
    if not (repo / ".git").is_dir():
        failures.append(f"{name}: checkout not found at {repo}")
        continue
    actual_commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    branch = subprocess.check_output(["git", "-C", str(repo), "symbolic-ref", "--short", "HEAD"], text=True).strip()
    origin_main = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "origin/main"], text=True).strip()
    if branch != "main":
        failures.append(f"{name}: checkout must be on main, actual={branch}")
    if actual_commit != origin_main:
        failures.append(f"{name}: HEAD must match origin/main expected={origin_main} actual={actual_commit}")
    if actual_commit != expected_commit:
        failures.append(f"{name}: HEAD mismatch expected={expected_commit} actual={actual_commit}")
    status = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True)
    if status.strip():
        failures.append(f"{name}: checkout is dirty")

if failures:
    print("\n".join(failures))
    sys.exit(1)

print("Phase 2 source checkout scaffold check passed")
PY

COMPOSE_CONFIG_JSON="$(mktemp "${TMPDIR:-/tmp}/rippleguard-phase2-compose.XXXXXX")"
trap 'rm -f "$COMPOSE_CONFIG_JSON"' EXIT HUP INT TERM
compose config --format json >"$COMPOSE_CONFIG_JSON"
python3 - "$COMPOSE_CONFIG_JSON" "$RIPPLEGUARD_CONTRACTS_REPO" "$RIPPLEGUARD_AGENT_RUNTIME_REPO" <<'PY'
import json
import sys
from pathlib import Path

config = json.load(open(sys.argv[1], encoding="utf-8"))
contracts = str(Path(sys.argv[2]).resolve())
agent_runtime = str(Path(sys.argv[3]).resolve())
expected = {
    "agent-runtime": {
        "/app/contracts": contracts,
        "/app/artifacts/manifests": str(Path(agent_runtime, "artifacts", "manifests").resolve()),
        "/app/artifacts/models": str(Path(agent_runtime, "artifacts", "models").resolve()),
    },
    "governance-service": {
        "/app/contracts": contracts,
    },
}
failures = []
for service_name, targets in expected.items():
    service = config["services"].get(service_name, {})
    volumes = {volume["target"]: volume["source"] for volume in service.get("volumes", [])}
    for target, source in targets.items():
        actual = str(Path(volumes.get(target, "")).resolve())
        if actual != source:
            failures.append(f"{service_name} mount {target} expected {source}, got {actual}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Phase 2 compose mount sources verified")
PY

echo "Phase 2 scaffolding verified"
