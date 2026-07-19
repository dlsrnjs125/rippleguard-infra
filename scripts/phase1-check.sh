#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
load_env

python3 "$ROOT_DIR/scripts/validate-phase1-manifest.py"
python3 "$ROOT_DIR/scripts/check-topic-contracts.py"
"$ROOT_DIR/scripts/check-secrets.sh"

python3 -c 'import json; [print(s["image"]) for s in json.load(open("manifests/phase1-core-msa.json"))["services"]]' |
while IFS= read -r image; do
  docker image inspect "$image" >/dev/null
done

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

psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select installed_rank from flyway_schema_history where version = '1' and success = true;" >/dev/null
psql_scalar governance-postgres "$governance_user" "$governance_password" "$governance_db" "select installed_rank from flyway_schema_history where version = '1' and success = true;" >/dev/null
psql_scalar audit-postgres "$audit_user" "$audit_password" "$audit_db" "select installed_rank from flyway_schema_history where version = '1' and success = true;" >/dev/null

loan_container_id="$(compose ps -q loan-postgres)"
governance_container_id="$(compose ps -q governance-postgres)"
audit_container_id="$(compose ps -q audit-postgres)"
if [ "$loan_container_id" = "$governance_container_id" ] || [ "$loan_container_id" = "$audit_container_id" ] || [ "$governance_container_id" = "$audit_container_id" ]; then
  echo "Phase 1 PostgreSQL containers are not isolated" >&2
  exit 1
fi

echo "Phase 1 core MSA stack verified"
