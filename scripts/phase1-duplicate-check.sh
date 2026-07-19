#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
load_env
network="$(phase1_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

idem_key="phase1-duplicate-$(date +%Y%m%d%H%M%S)"
payload="$(mktemp)"
cat >"$payload" <<EOF
{
  "schemaVersion": "1.0.0",
  "applicantReference": "synthetic:duplicate-applicant",
  "requestedAmount": "1800000.00",
  "currency": "KRW",
  "incomeHistory": [
    {"period": "2026-01", "amount": "3900000.00", "sourceReference": "synthetic:dup-income"}
  ],
  "debtSummary": {
    "totalOutstandingAmount": "0.00",
    "monthlyPaymentAmount": "0.00",
    "sourceReferences": ["synthetic:dup-debt"]
  },
  "delinquencySummary": {
    "delinquencyCount": 0,
    "daysPastDueMaximum": 0,
    "sourceReferences": ["synthetic:dup-delinquency"]
  },
  "platformSettlementSummary": {
    "period": "2026-Q1",
    "grossSettlementAmount": "9000000.00",
    "sourceReferences": ["synthetic:dup-settlement"]
  },
  "riskSignalReferences": ["synthetic:dup-risk"],
  "idempotencyKey": "$idem_key"
}
EOF

first="$(curl_file_from_network "$network" "$payload" -fsS -H 'Content-Type: application/json' --data-binary "@/payload.json" http://loan-service:8080/api/v1/loan-applications)"
second="$(curl_file_from_network "$network" "$payload" -fsS -H 'Content-Type: application/json' --data-binary "@/payload.json" http://loan-service:8080/api/v1/loan-applications)"
application_id="$(printf '%s' "$first" | json_field applicationId)"
second_application_id="$(printf '%s' "$second" | json_field applicationId)"
if [ "$application_id" != "$second_application_id" ]; then
  echo "Duplicate idempotency key created different application ids" >&2
  exit 1
fi

wait_for_json_condition "$network" "http://loan-service:8080/api/v1/loan-applications/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'FINALIZED'" >/dev/null
case_response="$(wait_for_json_condition "$network" "http://governance-service:8080/api/v1/decision-cases/by-application/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'RESOLVED'")"
case_id="$(printf '%s' "$case_response" | json_field caseId)"

loan_db="${LOAN_POSTGRES_DB:-rippleguard_loan}"
loan_user="${LOAN_POSTGRES_USER:-rippleguard_loan}"
loan_password="${LOAN_POSTGRES_PASSWORD:?LOAN_POSTGRES_PASSWORD is required}"
governance_db="${GOVERNANCE_POSTGRES_DB:-rippleguard_governance}"
governance_user="${GOVERNANCE_POSTGRES_USER:-rippleguard_governance}"
governance_password="${GOVERNANCE_POSTGRES_PASSWORD:?GOVERNANCE_POSTGRES_PASSWORD is required}"

submitted_payload="$(psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select payload from outbox_event where event_type = 'loan.application.submitted.v1' and aggregate_id = '$application_id' limit 1;")"
printf '%s\n' "$submitted_payload" | compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic loan.application.submitted.v1 >/dev/null

commanded_payload="$(psql_scalar governance-postgres "$governance_user" "$governance_password" "$governance_db" "select payload from outbox_event where event_type = 'loan.decision.commanded.v1' and aggregate_id = '$application_id' limit 1;")"
printf '%s\n' "$commanded_payload" | compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic loan.decision.commanded.v1 >/dev/null

sleep 5
decision_count="$(psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select count(*) from loan_decision where application_id = '$application_id';")"
case_count="$(psql_scalar governance-postgres "$governance_user" "$governance_password" "$governance_db" "select count(*) from decision_case where application_id = '$application_id';")"
if [ "$decision_count" != "1" ] || [ "$case_count" != "1" ]; then
  echo "Duplicate event handling failed decision_count=$decision_count case_count=$case_count" >&2
  exit 1
fi

timeline="$(curl_from_network "$network" -fsS "http://audit-replay-service:8080/api/v1/cases/$case_id/timeline")"
printf '%s' "$timeline" | python3 -c "import json,sys; data=json.load(sys.stdin); assert data['traceCompleteness'] in ('COMPLETE','PARTIAL'); assert len({e['eventId'] for e in data['events']}) == len(data['events'])"

echo "Phase 1 duplicate checks passed for applicationId=$application_id caseId=$case_id"
