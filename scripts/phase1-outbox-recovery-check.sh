#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file

tmp_env="$(mktemp)"
payload="$(mktemp)"
trap 'rm -f "$tmp_env" "$payload"' EXIT INT TERM

awk 'BEGIN{seen=0} /^OUTBOX_PUBLISHER_DELAY_MS=/{print "OUTBOX_PUBLISHER_DELAY_MS=600000"; seen=1; next} {print} END{if(!seen) print "OUTBOX_PUBLISHER_DELAY_MS=600000"}' "$BASE_ENV_FILE" >"$tmp_env"
ENV_FILE="$tmp_env"

compose up -d kafka loan-postgres governance-postgres audit-postgres kafka-ui
compose run --rm kafka-init >/dev/null
compose up -d loan-service governance-service audit-replay-service

network="$(phase1_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
sleep 3

idem_key="phase1-outbox-recovery-$(date +%Y%m%d%H%M%S)"
cat >"$payload" <<EOF
{
  "schemaVersion": "1.0.0",
  "applicantReference": "synthetic:outbox-applicant",
  "requestedAmount": "2300000.00",
  "currency": "KRW",
  "incomeHistory": [
    {"period": "2026-01", "amount": "4300000.00", "sourceReference": "synthetic:outbox-income"}
  ],
  "debtSummary": {
    "totalOutstandingAmount": "100000.00",
    "monthlyPaymentAmount": "50000.00",
    "sourceReferences": ["synthetic:outbox-debt"]
  },
  "delinquencySummary": {
    "delinquencyCount": 0,
    "daysPastDueMaximum": 0,
    "sourceReferences": ["synthetic:outbox-delinquency"]
  },
  "platformSettlementSummary": {
    "period": "2026-Q1",
    "grossSettlementAmount": "9800000.00",
    "sourceReferences": ["synthetic:outbox-settlement"]
  },
  "riskSignalReferences": ["synthetic:outbox-risk"],
  "idempotencyKey": "$idem_key"
}
EOF

response="$(curl_file_from_network "$network" "$payload" -fsS -H 'Content-Type: application/json' --data-binary "@/payload.json" http://loan-service:8080/api/v1/loan-applications)"
application_id="$(printf '%s' "$response" | json_field applicationId)"

load_env
loan_db="${LOAN_POSTGRES_DB:-rippleguard_loan}"
loan_user="${LOAN_POSTGRES_USER:-rippleguard_loan}"
loan_password="${LOAN_POSTGRES_PASSWORD:?LOAN_POSTGRES_PASSWORD is required}"

pending_count="$(psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select count(*) from outbox_event where aggregate_id = '$application_id' and event_type = 'loan.application.submitted.v1' and published_at is null;")"
if [ "$pending_count" != "1" ]; then
  echo "Expected one unpublished loan.application.submitted.v1 outbox row, got $pending_count" >&2
  exit 1
fi

awk 'BEGIN{seen=0} /^OUTBOX_PUBLISHER_DELAY_MS=/{print "OUTBOX_PUBLISHER_DELAY_MS=1000"; seen=1; next} {print} END{if(!seen) print "OUTBOX_PUBLISHER_DELAY_MS=1000"}' "$BASE_ENV_FILE" >"$tmp_env"
compose up -d --force-recreate loan-service >/dev/null
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

wait_for_json_condition "$network" "http://loan-service:8080/api/v1/loan-applications/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'FINALIZED'" >/dev/null
published_count="$(psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select count(*) from outbox_event where aggregate_id = '$application_id' and event_type = 'loan.application.submitted.v1' and published_at is not null;")"
decision_count="$(psql_scalar loan-postgres "$loan_user" "$loan_password" "$loan_db" "select count(*) from loan_decision where application_id = '$application_id';")"
if [ "$published_count" != "1" ] || [ "$decision_count" != "1" ]; then
  echo "Outbox recovery failed published_count=$published_count decision_count=$decision_count" >&2
  exit 1
fi

echo "Phase 1 outbox recovery check passed for applicationId=$application_id"
