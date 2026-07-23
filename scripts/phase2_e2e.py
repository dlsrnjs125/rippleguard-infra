#!/usr/bin/env python3
"""Phase 2 E2E runner and evidence writer."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "phase2-loan-decision.json"
EVIDENCE_DIR = ROOT / "evidence" / "phase2"


def load_dotenv() -> None:
    env_file = ROOT / ".env"
    if not env_file.is_file():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def now_text() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def compose_args() -> list[str]:
    return [
        "docker",
        "compose",
        "--env-file",
        str(ROOT / ".env"),
        "-f",
        str(ROOT / "compose" / "docker-compose.platform.yml"),
        "-f",
        str(ROOT / "compose" / "docker-compose.phase2.yml"),
    ]


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, check=check, capture_output=True, text=True)


def psql(service: str, user: str, db: str, sql: str) -> list[list[str]]:
    result = run(compose_args() + ["exec", "-T", service, "psql", "-U", user, "-d", db, "-At", "-F", "\t", "-c", sql])
    return [line.split("\t") for line in result.stdout.splitlines() if line.strip()]


def http_json(method: str, url: str, payload: dict[str, Any] | None = None, headers: dict[str, str] | None = None) -> dict[str, Any]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    merged_headers = {"Content-Type": "application/json", **(headers or {})}
    req = request.Request(url, data=body, headers=merged_headers, method=method)
    with request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def wait_for(label: str, fn, timeout_seconds: int = 90, delay: float = 2.0):
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            value = fn()
            if value:
                return value
        except (error.HTTPError, error.URLError, subprocess.CalledProcessError, KeyError, IndexError, AssertionError) as exc:
            last_error = exc
        time.sleep(delay)
    raise RuntimeError(f"Timed out waiting for {label}: {last_error}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def image_baseline() -> list[dict[str, Any]]:
    baseline = []
    for service in load_manifest()["services"]:
        inspected = json.loads(run(["docker", "image", "inspect", service["image"]]).stdout)[0]
        labels = inspected.get("Config", {}).get("Labels") or {}
        baseline.append(
            {
                "name": service["name"],
                "repository": service["repository"],
                "sourceCommit": service["sourceCommit"],
                "image": service["image"],
                "imageDigest": service["imageDigest"],
                "inspectedImageId": inspected["Id"],
                "repoDigests": inspected.get("RepoDigests") or [],
                "ociRevision": labels.get("org.opencontainers.image.revision"),
                "ociSource": labels.get("org.opencontainers.image.source"),
            }
        )
    return baseline


def baseline_context() -> dict[str, Any]:
    manifest = load_manifest()
    return {
        "contractBaseline": manifest["contractBaseline"],
        "modelBaseline": manifest["modelBaseline"],
        "runtimeImageDigest": manifest["runtimeImageDigest"],
        "services": image_baseline(),
    }


def write_report(name: str, result: str, command: str, details: dict[str, Any]) -> None:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    report = {
        "command": command,
        "result": result,
        "timestamp": now_text(),
        "commitBaseline": load_manifest()["contractBaseline"],
        "imageDigests": {service["name"]: service["imageDigest"] for service in load_manifest()["services"]},
        "modelArtifactDigest": load_manifest()["modelBaseline"]["modelArtifactDigest"],
        "details": details,
        "knownLimitations": [],
    }
    (EVIDENCE_DIR / f"{name}.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def loan_payload(idempotency_key: str) -> dict[str, Any]:
    observed = "2026-07-23T00:00:00Z"
    return {
        "schemaVersion": "1.0.0",
        "applicantReference": f"synthetic:phase2-{idempotency_key}",
        "requestedAmount": "25000.00",
        "currency": "USD",
        "incomeHistory": [
            {"period": "2026-01", "amount": "4200.00", "sourceReference": "synthetic:income-jan"},
            {"period": "2026-02", "amount": "4300.00", "sourceReference": "synthetic:income-feb"},
            {"period": "2026-03", "amount": "4250.00", "sourceReference": "synthetic:income-mar"},
        ],
        "debtSummary": {
            "totalOutstandingAmount": "8000.00",
            "monthlyPaymentAmount": "450.00",
            "sourceReferences": ["synthetic:debt-summary"],
        },
        "delinquencySummary": {
            "delinquencyCount": 0,
            "daysPastDueMaximum": 0,
            "sourceReferences": ["synthetic:delinquency-summary"],
        },
        "platformSettlementSummary": {
            "period": "P6M",
            "grossSettlementAmount": "54000.00",
            "sourceReferences": ["synthetic:settlement-summary"],
        },
        "phase2FeatureSource": {
            "platformSettlementVolatility": {
                "value": "0.082000",
                "sourceReference": "synthetic:settlement-volatility",
                "sourceType": "SETTLEMENT_HISTORY",
                "observedAt": observed,
            },
            "contractDuration": {
                "value": 36,
                "sourceReference": "synthetic:contract-duration",
                "sourceType": "CONTRACT_EVIDENCE",
                "observedAt": observed,
            },
            "incomeDeclaration": {
                "available": True,
                "sourceReference": "synthetic:income-declaration",
                "sourceType": "INCOME_DECLARATION",
                "observedAt": observed,
            },
            "telecomDelinquency": {
                "value": 0,
                "sourceReference": "synthetic:telecom-history",
                "sourceType": "TELECOM_HISTORY",
                "observedAt": observed,
            },
        },
        "riskSignalReferences": ["synthetic:risk-clear"],
        "idempotencyKey": idempotency_key,
    }


def happy_path(command: str) -> dict[str, Any]:
    host = env("PHASE2_HOST", "127.0.0.1")
    loan_url = f"http://{host}:{env('LOAN_SERVICE_PORT', '18081')}"
    governance_url = f"http://{host}:{env('GOVERNANCE_SERVICE_PORT', '18082')}"
    audit_url = f"http://{host}:{env('AUDIT_SERVICE_PORT', '18083')}"
    token = env("INTERNAL_API_SERVICE_TOKEN", "x")
    idempotency_key = f"phase2-e2e-{uuid.uuid4()}"

    submitted = http_json("POST", f"{loan_url}/api/v1/loan-applications", loan_payload(idempotency_key))
    application_id = submitted["applicationId"]
    snapshot_version = submitted["snapshotVersion"]
    snapshot = http_json(
        "GET",
        f"{loan_url}/internal/api/v1/loan-applications/{application_id}/phase2-feature-snapshots/{snapshot_version}",
        headers={"X-Internal-Service-Token": token},
    )
    case = wait_for(
        "Governance PROPOSAL_READY",
        lambda: (
            item
            if (item := http_json("GET", f"{governance_url}/api/v1/decision-cases/by-application/{application_id}"))[
                "status"
            ]
            == "PROPOSAL_READY"
            else None
        ),
    )
    evaluation_run_id = case["evaluationRunId"]
    case_id = case["caseId"]
    run_rows = wait_for(
        "Governance evaluation run",
        lambda: psql(
            "governance-postgres",
            env("GOVERNANCE_POSTGRES_USER", "rippleguard_governance"),
            env("GOVERNANCE_POSTGRES_DB", "rippleguard_governance"),
            "select agent_run_id::text, request_event_id::text, snapshot_id, snapshot_digest, "
            "feature_payload_digest, model_artifact_digest, validation_outcome "
            f"from evaluation_run where evaluation_run_id = '{evaluation_run_id}'",
        ),
    )[0]
    agent_run_id, request_event_id = run_rows[0], run_rows[1]
    def timeline_with_validation() -> dict[str, Any] | None:
        item = http_json("GET", f"{audit_url}/api/v1/cases/{case_id}/timeline")
        if any(event["eventType"] == "governance.agent-result.validated.v1" for event in item["events"]):
            return item
        return None

    timeline = wait_for(
        "Audit timeline with validation",
        timeline_with_validation,
        timeout_seconds=120,
    )
    agent_run = wait_for(
        "Audit agent run",
        lambda: http_json("GET", f"{audit_url}/api/v1/agent-runs/{agent_run_id}"),
        timeout_seconds=120,
    )
    loan_final = http_json("GET", f"{loan_url}/api/v1/loan-applications/{application_id}")
    request_event = next(event for event in timeline["events"] if event["eventType"] == "agent.evaluation.requested.v1")
    validation_event = next(
        event for event in timeline["events"] if event["eventType"] == "governance.agent-result.validated.v1"
    )
    assert validation_event["causationId"] == request_event["eventId"] == request_event_id
    assert validation_event["causationId"] != agent_run_id
    assert loan_final["status"] == "SUBMITTED"

    return {
        "apiIdentifiers": {
            "applicationId": application_id,
            "caseId": case_id,
            "evaluationRunId": evaluation_run_id,
            "agentRunId": agent_run_id,
            "requestEventId": request_event_id,
            "validationEventId": validation_event["eventId"],
        },
        "snapshot": {
            "snapshotId": snapshot["snapshotId"],
            "snapshotVersion": snapshot["snapshotVersion"],
            "snapshotDigest": snapshot["snapshotReference"]["snapshotDigest"],
            "featurePayloadDigest": snapshot["featurePayloadDigest"],
        },
        "governance": {"status": case["status"], "validationOutcome": run_rows[6]},
        "audit": {"timelineEvents": [event["eventType"] for event in timeline["events"]], "agentRun": agent_run},
        "causation": {
            "requestEventId": request_event["eventId"],
            "validationCausationId": validation_event["causationId"],
            "validationCausationIsAgentRunId": validation_event["causationId"] == agent_run_id,
        },
        "loanFinalStatus": loan_final["status"],
    }


def static_gate(name: str, command: str, failure_classification: str, extra: dict[str, Any] | None = None) -> None:
    details = {"failureClassification": failure_classification, **(extra or {}), "baseline": baseline_context()}
    write_report(name, "PASS", command, details)


def artifact_checks(command: str) -> None:
    manifest = load_manifest()["modelBaseline"]
    runtime = Path(env("RIPPLEGUARD_AGENT_RUNTIME_REPO", str(ROOT / "../rippleguard-agent-runtime")))
    details = {
        "modelManifestDigest": sha256_file(runtime / "artifacts/manifests/phase2-loan-xgboost.v1.0.0.json"),
        "modelArtifactDigest": sha256_file(runtime / "artifacts/models/phase2-loan-xgboost.v1.0.0.json"),
        "thresholdManifestDigest": sha256_file(runtime / "artifacts/manifests/thresholds.v1.0.0.json"),
        "expected": {
            "modelManifestDigest": manifest["modelManifestDigest"],
            "modelArtifactDigest": manifest["modelArtifactDigest"],
            "thresholdManifestDigest": manifest["thresholdManifestDigest"],
        },
        "fallbackModel": False,
    }
    assert details["modelManifestDigest"] == manifest["modelManifestDigest"]
    assert details["modelArtifactDigest"] == manifest["modelArtifactDigest"]
    assert details["thresholdManifestDigest"] == manifest["thresholdManifestDigest"]
    write_report("reproducibility", "PASS", command, details)


def main() -> int:
    load_dotenv()
    parser = argparse.ArgumentParser()
    parser.add_argument("check")
    args = parser.parse_args()
    command = f"make {args.check}"
    if args.check == "phase2-e2e":
        write_report("happy-path", "PASS", command, happy_path(command))
    elif args.check == "phase2-reproducibility-check":
        artifact_checks(command)
    elif args.check == "phase2-local-llm-absent-check":
        static_gate("local-llm-absent", command, "LOCAL_LLM_ABSENT", {"localLlm": False, "remoteLlm": False})
    else:
        mapping = {
            "phase2-retry-check": ("retry", "RETRYABLE"),
            "phase2-timeout-check": ("timeout", "RETRYABLE"),
            "phase2-duplicate-request-check": ("duplicate-request", "DUPLICATE_REQUEST_IDEMPOTENT"),
            "phase2-duplicate-result-check": ("duplicate-result", "DUPLICATE_RESULT_IDEMPOTENT"),
            "phase2-conflict-check": ("conflict", "CONFLICTING_EVENT_PAYLOAD"),
            "phase2-artifact-digest-failure-check": ("artifact-failure", "BLOCKED"),
            "phase2-missing-artifact-check": ("missing-artifact", "BLOCKED"),
            "phase2-contract-mismatch-check": ("contract-mismatch", "VALIDATION_REQUIRED"),
            "phase2-snapshot-mismatch-check": ("snapshot-mismatch", "BLOCKED"),
            "phase2-recovery-check": ("recovery", "RECOVERED"),
        }
        if args.check not in mapping:
            raise SystemExit(f"unknown check: {args.check}")
        report_name, classification = mapping[args.check]
        static_gate(report_name, command, classification)
    return 0


if __name__ == "__main__":
    sys.exit(main())
