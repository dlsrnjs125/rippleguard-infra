#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
network="$(phase1_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

compose stop governance-service audit-replay-service >/dev/null

idem_key="phase1-recovery-$(date +%Y%m%d%H%M%S)"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT INT TERM
cat >"$payload" <<EOF
{
  "schemaVersion": "1.0.0",
  "applicantReference": "synthetic:recovery-applicant",
  "requestedAmount": "2100000.00",
  "currency": "KRW",
  "incomeHistory": [
    {"period": "2026-01", "amount": "4200000.00", "sourceReference": "synthetic:recovery-income"}
  ],
  "debtSummary": {
    "totalOutstandingAmount": "100000.00",
    "monthlyPaymentAmount": "50000.00",
    "sourceReferences": ["synthetic:recovery-debt"]
  },
  "delinquencySummary": {
    "delinquencyCount": 0,
    "daysPastDueMaximum": 0,
    "sourceReferences": ["synthetic:recovery-delinquency"]
  },
  "platformSettlementSummary": {
    "period": "2026-Q1",
    "grossSettlementAmount": "9800000.00",
    "sourceReferences": ["synthetic:recovery-settlement"]
  },
  "riskSignalReferences": ["synthetic:recovery-risk"],
  "idempotencyKey": "$idem_key"
}
EOF

response="$(curl_file_from_network "$network" "$payload" -fsS -H 'Content-Type: application/json' --data-binary "@/payload.json" http://loan-service:8080/api/v1/loan-applications)"
application_id="$(printf '%s' "$response" | json_field applicationId)"

compose start governance-service audit-replay-service >/dev/null
wait_for_container_state governance-service running
wait_for_container_state audit-replay-service running
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

wait_for_json_condition "$network" "http://loan-service:8080/api/v1/loan-applications/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'FINALIZED'" >/dev/null
case_response="$(wait_for_json_condition "$network" "http://governance-service:8080/api/v1/decision-cases/by-application/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'RESOLVED'")"
case_id="$(printf '%s' "$case_response" | json_field caseId)"
wait_for_json_condition "$network" "http://audit-replay-service:8080/api/v1/cases/$case_id/timeline" "import json,sys; data=json.load(sys.stdin); assert len(data['events']) >= 6" >/dev/null

echo "Phase 1 recovery checks passed for applicationId=$application_id caseId=$case_id"
