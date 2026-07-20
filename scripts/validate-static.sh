#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
PHASE1_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.phase1.yml"
OBSERVABILITY_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.observability.yml"
STATIC_ENV="$(mktemp "${TMPDIR:-/tmp}/rippleguard-infra-static-env.XXXXXX")"
trap 'rm -f "$STATIC_ENV"' EXIT HUP INT TERM

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
LOAN_SERVICE_IMAGE=rippleguard-loan-service:e403c0a60ccb
GOVERNANCE_SERVICE_IMAGE=rippleguard-governance-service:4e06e672affd
AUDIT_SERVICE_IMAGE=rippleguard-audit-replay-service:83ca52edda2f
LOAN_SERVICE_PORT=18081
GOVERNANCE_SERVICE_PORT=18082
AUDIT_SERVICE_PORT=18083
OUTBOX_PUBLISHER_DELAY_MS=1000
INTERNAL_API_SERVICE_TOKEN=x
EOF

docker compose --env-file "$STATIC_ENV" -f "$COMPOSE_FILE" config >/dev/null
docker compose --env-file "$STATIC_ENV" -f "$COMPOSE_FILE" -f "$PHASE1_COMPOSE_FILE" config >/dev/null
docker compose -f "$OBSERVABILITY_COMPOSE_FILE" config >/dev/null

for script in "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/kafka/scripts/*.sh "$ROOT_DIR"/minio/scripts/*.sh; do
  sh -n "$script"
done

python3 -m json.tool "$ROOT_DIR/contracts/phase0-baseline.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/contracts/phase1-core-baseline.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/manifests/phase1-core-msa.json" >/dev/null
python3 "$ROOT_DIR/scripts/check-topic-contracts.py"
python3 "$ROOT_DIR/scripts/validate-phase1-manifest.py"
python3 -m py_compile "$ROOT_DIR/scripts/verify-phase1-images.py" "$ROOT_DIR/scripts/validate-timeline-privacy.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "Static infra validation passed"
