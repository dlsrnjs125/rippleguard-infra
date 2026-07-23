#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
PHASE1_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.phase1.yml"
PHASE2_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.phase2.yml"
OBSERVABILITY_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.observability.yml"
STATIC_ENV="$(mktemp "${TMPDIR:-/tmp}/rippleguard-infra-static-env.XXXXXX")"
PHASE2_COMPOSE_JSON="$(mktemp "${TMPDIR:-/tmp}/rippleguard-phase2-compose.XXXXXX")"
PYTHON_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rippleguard-infra-pycache.XXXXXX")"
export PYTHONPYCACHEPREFIX="$PYTHON_CACHE_DIR"
trap 'rm -f "$STATIC_ENV" "$PHASE2_COMPOSE_JSON"; rm -rf "$PYTHON_CACHE_DIR"' EXIT HUP INT TERM

static_compose() {
  env -i PATH="$PATH" HOME="${HOME:-}" TMPDIR="${TMPDIR:-/tmp}" docker compose --env-file "$STATIC_ENV" "$@"
}

cat >"$STATIC_ENV" <<'EOF'
COMPOSE_PROJECT_NAME=rippleguard-static
LOAN_POSTGRES_DB=rippleguard_loan
LOAN_POSTGRES_USER=rippleguard_loan
LOAN_POSTGRES_PASSWORD=x
LOAN_POSTGRES_PORT=5433
GOVERNANCE_POSTGRES_DB=rippleguard_governance
GOVERNANCE_POSTGRES_USER=rippleguard_governance
GOVERNANCE_POSTGRES_PASSWORD=x
GOVERNANCE_POSTGRES_PORT=5434
AUDIT_POSTGRES_DB=rippleguard_audit
AUDIT_POSTGRES_USER=rippleguard_audit
AUDIT_POSTGRES_PASSWORD=x
AUDIT_POSTGRES_PORT=5435
KAFKA_EXTERNAL_PORT=9094
KAFKA_TOPIC_PARTITIONS=3
KAFKA_TOPIC_REPLICATION_FACTOR=1
KAFKA_KRAFT_CLUSTER_ID=MkU3OEVBNTcwNTJENDM2Qk
OPA_PORT=8181
MINIO_ROOT_USER=rippleguard_static
MINIO_ROOT_PASSWORD=x
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_DOCUMENT_BUCKET=rippleguard-documents
RIPPLEGUARD_CONTRACTS_REPO=/tmp/rippleguard-contracts
RIPPLEGUARD_LOAN_REPO=/tmp/rippleguard-loan-service
RIPPLEGUARD_GOVERNANCE_REPO=/tmp/rippleguard-governance-service
RIPPLEGUARD_AGENT_RUNTIME_REPO=/tmp/rippleguard-agent-runtime
RIPPLEGUARD_AUDIT_REPO=/tmp/rippleguard-audit-replay-service
LOAN_SERVICE_IMAGE=rippleguard-loan-service:1f78f8c3358f
GOVERNANCE_SERVICE_IMAGE=rippleguard-governance-service:053206df5d11
AUDIT_SERVICE_IMAGE=rippleguard-audit-replay-service:e6baae0a1fef
AGENT_RUNTIME_IMAGE=rippleguard-agent-runtime:25e8c187ee80
LOAN_SERVICE_PORT=18081
GOVERNANCE_SERVICE_PORT=18082
AUDIT_SERVICE_PORT=18083
AGENT_RUNTIME_PORT=18084
OUTBOX_PUBLISHER_DELAY_MS=1000
INTERNAL_API_SERVICE_TOKEN=x
AGENT_RUNTIME_LOAN_DECISION_RUNS_PATH=/internal/v1/loan-decision-agent/runs
AGENT_RUNTIME_CONNECT_TIMEOUT=PT1S
AGENT_RUNTIME_RESPONSE_TIMEOUT=PT10S
AGENT_RUNTIME_MAX_ATTEMPTS=3
AGENT_RUNTIME_REQUEST_TIMEOUT=PT15S
AGENT_RUNTIME_RETRY_BACKOFF=PT1S
AGENT_RUNTIME_LEASE_DURATION=PT30S
AGENT_RUNTIME_RECOVERY_DELAY_MS=1000
AGENT_RUNTIME_MAX_RESPONSE_BYTES=1048576
AGENT_RUNTIME_LOG_LEVEL=INFO
PHASE2_EXECUTION_PLAN_VERSION=phase2-loan-decision-plan.v1.0.0
PHASE2_FEATURE_SCHEMA_VERSION=phase-2-loan-features.v1.0.0
PHASE2_PREPROCESSING_VERSION=preprocess.v1.0.0
PHASE2_MODEL_VERSION=loan-model.v1.0.0
PHASE2_MODEL_ARTIFACT_DIGEST=sha256:1780b376723b52ad04630a474c6bd2eeddab2e89caa13956e76b356595ed79df
PHASE2_THRESHOLD_VERSION=threshold.v1.0.0
EOF

static_compose -f "$COMPOSE_FILE" config >/dev/null
static_compose -f "$COMPOSE_FILE" -f "$PHASE1_COMPOSE_FILE" config >/dev/null
static_compose -f "$COMPOSE_FILE" -f "$PHASE2_COMPOSE_FILE" config >/dev/null
static_compose -f "$COMPOSE_FILE" -f "$PHASE2_COMPOSE_FILE" config --format json >"$PHASE2_COMPOSE_JSON"
python3 - "$PHASE2_COMPOSE_JSON" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {
    "agent-runtime": {
        "/app/contracts": "/tmp/rippleguard-contracts",
        "/app/artifacts/manifests": "/tmp/rippleguard-agent-runtime/artifacts/manifests",
        "/app/artifacts/models": "/tmp/rippleguard-agent-runtime/artifacts/models",
    },
    "governance-service": {
        "/app/contracts": "/tmp/rippleguard-contracts",
    },
}
failures = []
for service_name, targets in expected.items():
    service = config["services"].get(service_name, {})
    volumes = {volume["target"]: volume["source"] for volume in service.get("volumes", [])}
    for target, source in targets.items():
        if volumes.get(target) != source:
            failures.append(f"{service_name} mount {target} expected {source}, got {volumes.get(target)}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
PY
docker compose -f "$OBSERVABILITY_COMPOSE_FILE" config >/dev/null

for script in "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/kafka/scripts/*.sh "$ROOT_DIR"/minio/scripts/*.sh; do
  sh -n "$script"
done

python3 -m json.tool "$ROOT_DIR/contracts/phase0-baseline.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/contracts/phase1-core-baseline.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/contracts/phase2-loan-decision-baseline.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/manifests/phase1-core-msa.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/manifests/phase2-loan-decision.json" >/dev/null
python3 "$ROOT_DIR/scripts/check-topic-contracts.py"
python3 "$ROOT_DIR/scripts/validate-phase1-manifest.py"
python3 "$ROOT_DIR/scripts/validate-phase2-manifest.py"
python3 -m py_compile "$ROOT_DIR/scripts/verify-phase1-images.py" "$ROOT_DIR/scripts/verify-phase2-images.py" "$ROOT_DIR/scripts/validate-timeline-privacy.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "Static infra validation passed"
