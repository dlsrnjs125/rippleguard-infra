#!/usr/bin/env python3
"""Validate that a case timeline response exposes only allowed fields and no obvious PII."""

from __future__ import annotations

import json
import re
import sys

TOP_LEVEL = {"schemaVersion", "caseId", "applicationId", "events", "traceCompleteness", "warnings"}
EVENT_FIELDS = {
    "eventId",
    "eventType",
    "caseId",
    "occurredAt",
    "producer",
    "evaluationRunId",
    "correlationId",
    "causationId",
    "status",
    "summary",
}
FORBIDDEN = re.compile(
    r"("
    r"\b\d{6}-\d{7}\b|"
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|"
    r"\b01[016789]-?\d{3,4}-?\d{4}\b|"
    r"\b\d{2,6}-\d{2,6}-\d{2,8}\b|"
    r"password|secret|token|authorization|"
    r"incomeHistory|debtSummary|documentText|financialSnapshot|prompt|model input|"
    r"requestedAmount|grossSettlementAmount|totalOutstandingAmount|monthlyPaymentAmount|"
    r"applicantReference|riskSignalReferences|sourceReferences"
    r")",
    re.IGNORECASE,
)


def main() -> int:
    data = json.load(sys.stdin)
    failures: list[str] = []

    extra_top = set(data) - TOP_LEVEL
    if extra_top:
        failures.append(f"unexpected top-level timeline fields: {sorted(extra_top)}")

    for index, event in enumerate(data.get("events", [])):
        extra_event = set(event) - EVENT_FIELDS
        if extra_event:
            failures.append(f"event[{index}] unexpected fields: {sorted(extra_event)}")

    serialized = json.dumps(data, ensure_ascii=False)
    if FORBIDDEN.search(serialized):
        failures.append("timeline contains a forbidden PII or sensitive-data pattern")

    if failures:
        print("\n".join(failures))
        return 1

    print("Timeline privacy validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
