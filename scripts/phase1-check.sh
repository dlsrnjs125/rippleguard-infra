#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
load_env

python3 "$ROOT_DIR/scripts/validate-phase1-manifest.py"
python3 "$ROOT_DIR/scripts/verify-phase1-images.py"
python3 "$ROOT_DIR/scripts/check-topic-contracts.py"
"$ROOT_DIR/scripts/check-secrets.sh"

compose config >/dev/null

wait_for_container_state kafka healthy
wait_for_container_state loan-postgres healthy
wait_for_container_state governance-postgres healthy
wait_for_container_state audit-postgres healthy
wait_for_container_state loan-service running
wait_for_container_state governance-service running
wait_for_container_state audit-replay-service running
wait_for_container_state kafka-ui running

network="$(phase1_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

compose run --rm kafka-init /bin/sh /scripts/verify-topics.sh

loan_db="${LOAN_POSTGRES_DB:-rippleguard_loan}"
loan_user="${LOAN_POSTGRES_USER:-rippleguard_loan}"
loan_password="${LOAN_POSTGRES_PASSWORD:?LOAN_POSTGRES_PASSWORD is required}"
governance_db="${GOVERNANCE_POSTGRES_DB:-rippleguard_governance}"
governance_user="${GOVERNANCE_POSTGRES_USER:-rippleguard_governance}"
governance_password="${GOVERNANCE_POSTGRES_PASSWORD:?GOVERNANCE_POSTGRES_PASSWORD is required}"
audit_db="${AUDIT_POSTGRES_DB:-rippleguard_audit}"
audit_user="${AUDIT_POSTGRES_USER:-rippleguard_audit}"
audit_password="${AUDIT_POSTGRES_PASSWORD:?AUDIT_POSTGRES_PASSWORD is required}"

verify_migration() {
  service="$1"
  postgres="$2"
  user="$3"
  password="$4"
  database="$5"
  expected="$(python3 -c 'import json,sys; data=json.load(open("manifests/phase1-core-msa.json")); svc=next(s for s in data["services"] if s["name"] == sys.argv[1]); m=svc["migration"]; print("|".join([m["version"], m["description"], m["script"], "" if m["checksum"] is None else str(m["checksum"])]))' "$service")"
  actual="$(psql_scalar "$postgres" "$user" "$password" "$database" "select version || '|' || description || '|' || script || '|' || coalesce(checksum::text, '') from flyway_schema_history where version = '1' and success = true;")"
  expected_checksum="${expected##*|}"
  if [ -z "$expected_checksum" ]; then
    expected_without_checksum="${expected%|*}"
    actual_without_checksum="${actual%|*}"
    if [ "$actual_without_checksum" != "$expected_without_checksum" ]; then
      echo "$service migration mismatch expected=$expected actual=$actual" >&2
      exit 1
    fi
    echo "$service migration verified with runtime checksum ${actual##*|}"
    return 0
  fi
  if [ "$actual" != "$expected" ]; then
    echo "$service migration mismatch expected=$expected actual=$actual" >&2
    exit 1
  fi
  echo "$service migration verified with pinned checksum $expected_checksum"
}

verify_migration loan-service loan-postgres "$loan_user" "$loan_password" "$loan_db"
verify_migration governance-service governance-postgres "$governance_user" "$governance_password" "$governance_db"
verify_migration audit-replay-service audit-postgres "$audit_user" "$audit_password" "$audit_db"

loan_container_id="$(compose ps -q loan-postgres)"
governance_container_id="$(compose ps -q governance-postgres)"
audit_container_id="$(compose ps -q audit-postgres)"
if [ "$loan_container_id" = "$governance_container_id" ] || [ "$loan_container_id" = "$audit_container_id" ] || [ "$governance_container_id" = "$audit_container_id" ]; then
  echo "Phase 1 PostgreSQL containers are not isolated" >&2
  exit 1
fi

echo "Phase 1 core MSA stack verified"
