#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file
network="$(phase1_network)"
wait_for_http "$network" http://audit-replay-service:8080/actuator/health
compose stop loan-service governance-service >/dev/null

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

python3 - <<'PY' "$tmpdir/events.jsonl" "$tmpdir/meta"
import json
import sys
import uuid

out = sys.argv[1]
meta = sys.argv[2]
app = str(uuid.uuid4())
case = f"case-{app}"
run = str(uuid.uuid4())
ids = [str(uuid.uuid4()) for _ in range(6)]
types = [
    "loan.application.submitted.v1",
    "governance.review.started.v1",
    "agent.evaluation.requested.v1",
    "agent.evaluation.completed.v1",
    "loan.decision.commanded.v1",
    "loan.decision.finalized.v1",
]
times = [
    "2026-01-01T00:00:00Z",
    "2026-01-01T00:01:00Z",
    "2026-01-01T00:02:00Z",
    "2026-01-01T00:03:00Z",
    "2026-01-01T00:04:00Z",
    "2026-01-01T00:05:00Z",
]
producers = ["loan-service", "governance-service", "governance-service", "governance-service", "governance-service", "loan-service"]
payloads = [
    {"applicationId": app, "inputSnapshotVersion": "snapshot-v1", "applicantId": "synthetic:order-applicant"},
    {"decisionCaseId": case, "applicationId": app, "reviewStartedAt": times[1]},
    {"evaluationRunId": run, "decisionCaseId": case, "inputSnapshotVersion": "snapshot-v1", "executionPlanVersion": "mock-v1", "evaluationMode": "MOCK"},
    {"evaluationRunId": run, "decisionCaseId": case, "evaluationMode": "MOCK", "evaluatorId": "mock-evaluator"},
    {"commandId": str(uuid.uuid4()), "decisionCaseId": case, "applicationId": app, "evaluationRunId": run, "finalDecision": "APPROVE", "assuranceResult": "PASS", "reasonCodes": ["MOCK"], "issuedAt": times[4]},
    {"commandId": str(uuid.uuid4()), "decisionCaseId": case, "applicationId": app, "decisionId": str(uuid.uuid4()), "evaluationRunId": run, "finalDecision": "APPROVE", "finalizedAt": times[5]},
]
events = []
for i, event_type in enumerate(types):
    events.append({
        "eventId": ids[i],
        "eventType": event_type,
        "schemaVersion": "1.1.0",
        "occurredAt": times[i],
        "producer": producers[i],
        "applicationId": app,
        "caseId": app if i == 0 else case,
        "evaluationRunId": None if i < 2 else run,
        "correlationId": app,
        "causationId": None if i == 0 else ids[i - 1],
        "payload": payloads[i],
    })
with open(out, "w", encoding="utf-8") as handle:
    for index in [5, 4, 3, 0, 1, 2]:
        handle.write(json.dumps(events[index], separators=(",", ":")) + "\n")
with open(meta, "w", encoding="utf-8") as handle:
    handle.write(f"{app}\n{case}\n")
PY

application_id="$(sed -n '1p' "$tmpdir/meta")"
case_id="$(sed -n '2p' "$tmpdir/meta")"

event_type_for_line() {
  line="$1"
  sed -n "${line}p" "$tmpdir/events.jsonl" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["eventType"])'
}

produce_event() {
  line="$1"
  topic="$2"
  event_type="$(event_type_for_line "$line")"

  if [ "$event_type" != "$topic" ]; then
    echo "Refusing to publish event line $line: eventType=$event_type topic=$topic" >&2
    return 1
  fi

  sed -n "${line}p" "$tmpdir/events.jsonl" |
    compose exec -T kafka \
      /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server kafka:9092 \
      --topic "$topic" >/dev/null
}

produce_event 1 loan.decision.finalized.v1
produce_event 2 loan.decision.commanded.v1
produce_event 3 agent.evaluation.completed.v1
partial="$(wait_for_json_condition "$network" "http://audit-replay-service:8080/api/v1/cases/$case_id/timeline" "import json,sys; data=json.load(sys.stdin); assert data['traceCompleteness'] == 'PARTIAL'; assert len(data['events']) == 3")"
printf '%s' "$partial" | python3 "$ROOT_DIR/scripts/validate-timeline-privacy.py" >/dev/null

produce_event 4 loan.application.submitted.v1
produce_event 5 governance.review.started.v1
produce_event 6 agent.evaluation.requested.v1

complete="$(wait_for_json_condition "$network" "http://audit-replay-service:8080/api/v1/cases/$case_id/timeline" "import json,sys; data=json.load(sys.stdin); assert data['traceCompleteness'] == 'COMPLETE'; assert len(data['events']) == 6; assert [e['occurredAt'] for e in data['events']] == sorted(e['occurredAt'] for e in data['events']); assert len({e['eventId'] for e in data['events']}) == 6")"
printf '%s' "$complete" | python3 "$ROOT_DIR/scripts/validate-timeline-privacy.py" >/dev/null

echo "Phase 1 out-of-order timeline check passed for applicationId=$application_id caseId=$case_id"
