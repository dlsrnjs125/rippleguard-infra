#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
network="$(phase1_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health

idem_key="phase1-e2e-$(date +%Y%m%d%H%M%S)"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT INT TERM
cat >"$payload" <<EOF
{
  "schemaVersion": "1.0.0",
  "applicantReference": "synthetic:phase1-applicant",
  "requestedAmount": "2500000.00",
  "currency": "KRW",
  "incomeHistory": [
    {"period": "2026-01", "amount": "4500000.00", "sourceReference": "synthetic:income-2026-01"},
    {"period": "2026-02", "amount": "4550000.00", "sourceReference": "synthetic:income-2026-02"}
  ],
  "debtSummary": {
    "totalOutstandingAmount": "1000000.00",
    "monthlyPaymentAmount": "200000.00",
    "sourceReferences": ["synthetic:debt-summary"]
  },
  "delinquencySummary": {
    "delinquencyCount": 0,
    "daysPastDueMaximum": 0,
    "sourceReferences": ["synthetic:delinquency-summary"]
  },
  "platformSettlementSummary": {
    "period": "2026-Q1",
    "grossSettlementAmount": "12000000.00",
    "sourceReferences": ["synthetic:settlement-summary"]
  },
  "riskSignalReferences": ["synthetic:risk-signal"],
  "idempotencyKey": "$idem_key"
}
EOF

response="$(curl_file_from_network "$network" "$payload" -fsS -H 'Content-Type: application/json' --data-binary "@/payload.json" http://loan-service:8080/api/v1/loan-applications)"
application_id="$(printf '%s' "$response" | json_field applicationId)"
echo "Created applicationId=$application_id"

loan_response="$(wait_for_json_condition "$network" "http://loan-service:8080/api/v1/loan-applications/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'FINALIZED'")"
case_response="$(wait_for_json_condition "$network" "http://governance-service:8080/api/v1/decision-cases/by-application/$application_id" "import json,sys; assert json.load(sys.stdin)['status'] == 'RESOLVED'")"
case_id="$(printf '%s' "$case_response" | json_field caseId)"
timeline_response="$(wait_for_json_condition "$network" "http://audit-replay-service:8080/api/v1/cases/$case_id/timeline" "import json,sys; data=json.load(sys.stdin); assert data['traceCompleteness'] == 'COMPLETE'; assert len(data['events']) == 6; assert all(e['caseId'] == data['caseId'] for e in data['events'])")"

printf '%s' "$timeline_response" | python3 "$ROOT_DIR/scripts/validate-timeline-privacy.py"

run_id="$(date +%Y%m%dT%H%M%S)"
artifact_dir="$ROOT_DIR/artifacts/phase1/$run_id"
mkdir -p "$artifact_dir"
cat >"$artifact_dir/e2e-summary.json" <<EOF
{
  "command": "make phase1-e2e",
  "applicationId": "$application_id",
  "loanStatus": "$(printf '%s' "$loan_response" | json_field status)",
  "caseId": "$case_id",
  "governanceStatus": "$(printf '%s' "$case_response" | json_field status)",
  "timelineCompleteness": "$(printf '%s' "$timeline_response" | json_field traceCompleteness)",
  "privacyValidation": "passed"
}
EOF

echo "Phase 1 E2E passed; evidence written to artifacts/phase1/$run_id/e2e-summary.json"
