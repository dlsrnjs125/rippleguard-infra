#!/usr/bin/env python3
"""Phase 2 E2E runner and evidence writer."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
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
LLM_IMPORT_MODULES = (
    "openai",
    "anthropic",
    "ollama",
    "litellm",
    "google_generativeai",
    "google_genai",
    "vertexai",
    "cohere",
    "mistralai",
    "groq",
    "boto3",
    "azure_ai_inference",
)
LLM_DEPENDENCY_NAMES = (
    "openai",
    "anthropic",
    "ollama",
    "litellm",
    "google-generativeai",
    "google-genai",
    "vertexai",
    "cohere",
    "mistralai",
    "groq",
    "boto3",
    "azure-ai-inference",
)
LLM_CONFIG_KEYS = (
    "OPENAI_API_KEY",
    "OPENAI_API_BASE",
    "OPENAI_BASE_URL",
    "OPENAI_MODEL",
    "AZURE_OPENAI_API_KEY",
    "AZURE_OPENAI_ENDPOINT",
    "AZURE_OPENAI_API_BASE",
    "AZURE_OPENAI_BASE_URL",
    "AZURE_OPENAI_MODEL",
    "AZURE_OPENAI_DEPLOYMENT",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_MODEL",
    "OLLAMA_HOST",
    "OLLAMA_BASE_URL",
    "OLLAMA_MODEL",
    "LITELLM_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_GENAI_API_KEY",
    "VERTEXAI_PROJECT",
    "COHERE_API_KEY",
    "MISTRAL_API_KEY",
    "GROQ_API_KEY",
    "AWS_BEDROCK_RUNTIME_ENDPOINT",
    "BEDROCK_MODEL_ID",
    "AZURE_AI_INFERENCE_ENDPOINT",
    "LOCAL_LLM",
    "LLM_ENDPOINT",
    "LLM_BASE_URL",
    "LLM_PROVIDER",
)
LLM_URL_TOKENS = (
    "ollama",
    "openai",
    "anthropic",
    "generativelanguage.googleapis.com",
    "aiplatform.googleapis.com",
    "cohere",
    "mistral",
    "groq",
    "bedrock-runtime",
)


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


def run_text(command: list[str], *, check: bool = True) -> str:
    return run(command, check=check).stdout


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
        inspected = json.loads(run(["docker", "inspect", service["image"]]).stdout)[0]
        labels = inspected.get("Config", {}).get("Labels") or {}
        baseline.append(
            {
                "name": service["name"],
                "repository": service["repository"],
                "sourceCommit": service["sourceCommit"],
                "image": service["image"],
                "imageDigest": service["imageDigest"],
                "imageDigestKind": service["imageDigestKind"],
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


def manifest_baseline_context() -> dict[str, Any]:
    manifest = load_manifest()
    return {
        "contractBaseline": manifest["contractBaseline"],
        "modelBaseline": manifest["modelBaseline"],
        "runtimeImageDigest": manifest["runtimeImageDigest"],
        "services": [
            {
                "name": service["name"],
                "repository": service["repository"],
                "sourceCommit": service["sourceCommit"],
                "image": service["image"],
                "imageDigest": service["imageDigest"],
                "imageDigestKind": service["imageDigestKind"],
                "ociLabels": service["ociLabels"],
            }
            for service in manifest["services"]
        ],
    }


def forbidden_config_hits(text: str) -> list[str]:
    key_pattern = "|".join(re.escape(key) for key in LLM_CONFIG_KEYS)
    url_pattern = "|".join(re.escape(token) for token in LLM_URL_TOKENS)
    patterns = [
        re.compile(rf"\b(?:{key_pattern})\b"),
        re.compile(rf"https?://[^\"'\s]*(?:{url_pattern})", re.IGNORECASE),
        re.compile(r"/v1/chat/completions", re.IGNORECASE),
    ]
    return pattern_hits(text, patterns)


def forbidden_runtime_hits(text: str) -> list[str]:
    provider_pattern = "|".join(re.escape(provider) for provider in LLM_DEPENDENCY_NAMES)
    url_pattern = "|".join(re.escape(token) for token in LLM_URL_TOKENS)
    patterns = [
        re.compile(rf"(?:{provider_pattern})\s+(?:client|request|connection|provider)\s+(?:initialized|started|created)", re.IGNORECASE),
        re.compile(rf"(?:calling|requesting|connected to)\s+(?:{provider_pattern})", re.IGNORECASE),
        re.compile(rf"https?://[^\"'\s]*(?:{url_pattern})", re.IGNORECASE),
        re.compile(r"/v1/chat/completions", re.IGNORECASE),
    ]
    return pattern_hits(text, patterns)


def repository_llm_patterns() -> list[re.Pattern[str]]:
    import_pattern = "|".join(re.escape(module) for module in LLM_IMPORT_MODULES)
    dependency_pattern = "|".join(
        re.escape(name).replace(r"\-", r"[_-]") + r"(?:[_-][a-z0-9]+)*"
        if name == "langchain"
        else re.escape(name).replace(r"\-", r"[_-]")
        for name in (*LLM_DEPENDENCY_NAMES, "langchain")
    )
    key_pattern = "|".join(re.escape(key) for key in LLM_CONFIG_KEYS)
    url_pattern = "|".join(re.escape(token) for token in LLM_URL_TOKENS)
    return [
        re.compile(rf"^\s*(from|import)\s+(?:{import_pattern}|langchain(?:_[a-z0-9]+)*)\b"),
        re.compile(rf"^\s*(?:{dependency_pattern})(\[.*\])?\s*(?:[=<>!~]|@\s*)", re.IGNORECASE),
        re.compile(rf"^\s*[\"'](?:{dependency_pattern})(?:\[.*\])?\s*(?:(?:[<>=!~].*)|(?:@\s*[^\s\"']+))?[\"']\s*,?\s*$", re.IGNORECASE),
        re.compile(rf"\b(?:{key_pattern})\b"),
        re.compile(rf"https?://[^\"']*(?:{url_pattern})", re.IGNORECASE),
        re.compile(r"/v1/chat/completions", re.IGNORECASE),
    ]


def pattern_hits(text: str, patterns: list[re.Pattern[str]]) -> list[str]:
    hits: list[str] = []
    for line in text.splitlines():
        if any(pattern.search(line) for pattern in patterns):
            hits.append(line[:240])
    return hits


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


def fail_report(name: str, command: str, failure: str, details: dict[str, Any] | None = None) -> None:
    payload = {"failure": failure, **(details or {})}
    write_report(name, "FAIL", command, payload)


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
    def proposal_ready() -> dict[str, Any] | None:
        item = http_json("GET", f"{governance_url}/api/v1/decision-cases/by-application/{application_id}")
        if item["status"] == "PROPOSAL_READY":
            return item
        if item["status"] in {"BLOCKED", "VALIDATION_REQUIRED", "VERIFICATION_REQUIRED", "NON_RETRYABLE"}:
            raise RuntimeError(
                "Governance reached terminal non-ready status "
                f"status={item['status']} reasonCode={item.get('reasonCode')}"
            )
        return None

    case = wait_for("Governance PROPOSAL_READY", proposal_ready)
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
    governance_commanded_count = int(
        psql(
            "governance-postgres",
            env("GOVERNANCE_POSTGRES_USER", "rippleguard_governance"),
            env("GOVERNANCE_POSTGRES_DB", "rippleguard_governance"),
            "select count(*) from outbox_event "
            "where event_type = 'loan.decision.commanded.v1' "
            f"and aggregate_id = '{application_id}'",
        )[0][0]
    )
    loan_finalized_count = int(
        psql(
            "loan-postgres",
            env("LOAN_POSTGRES_USER", "rippleguard_loan"),
            env("LOAN_POSTGRES_DB", "rippleguard_loan"),
            "select count(*) from outbox_event "
            "where event_type = 'loan.decision.finalized.v1' "
            f"and aggregate_id = '{application_id}'",
        )[0][0]
    )
    request_event = next(event for event in timeline["events"] if event["eventType"] == "agent.evaluation.requested.v1")
    validation_event = next(
        event for event in timeline["events"] if event["eventType"] == "governance.agent-result.validated.v1"
    )
    assert validation_event["causationId"] == request_event["eventId"] == request_event_id, (
        "validation causation must point to persisted request event"
    )
    assert validation_event["causationId"] != agent_run_id, "validation causation must not use agentRunId"
    assert governance_commanded_count == 0, "Governance must not publish loan.decision.commanded for Phase 2 proposal"
    assert loan_finalized_count == 0, "Loan must not publish loan.decision.finalized for Phase 2 proposal"
    assert loan_final["status"] in {"SUBMITTED", "UNDER_GOVERNANCE_REVIEW"}, (
        "Loan must remain non-final after Phase 2 proposal"
    )

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
        "loanFinalState": {
            "status": loan_final["status"],
            "governanceCommandedEventsForApplication": governance_commanded_count,
            "loanFinalizedEventsForApplication": loan_finalized_count,
        },
    }


def static_gate(name: str, command: str, failure_classification: str, extra: dict[str, Any] | None = None) -> None:
    details = {"failureClassification": failure_classification, **(extra or {}), "baseline": manifest_baseline_context()}
    write_report(name, "PASS", command, details)


def local_llm_absent_checks(command: str) -> None:
    manifest = load_manifest()
    excluded = manifest.get("excludedRuntimeDependencies", {})
    if excluded.get("localLlm") is not True or excluded.get("remoteLlm") is not True or excluded.get("fallbackModel") is not True:
        raise RuntimeError("Phase 2 manifest must explicitly exclude local LLM, remote LLM, and fallback model")

    compose_config = run_text(compose_args() + ["config", "--format", "json"])
    compose_hits = forbidden_config_hits(compose_config)
    if compose_hits:
        raise RuntimeError("Phase 2 compose config contains LLM wiring: " + "; ".join(compose_hits[:5]))

    container_id = run_text(compose_args() + ["ps", "-q", "agent-runtime"]).strip()
    if not container_id:
        raise RuntimeError("agent-runtime container must be running for local LLM absence verification")

    env_lines = run_text(["docker", "inspect", "--format", "{{range .Config.Env}}{{println .}}{{end}}", container_id])
    env_hits = forbidden_config_hits(env_lines)
    if env_hits:
        raise RuntimeError("Agent Runtime container environment contains LLM wiring: " + "; ".join(env_hits[:5]))

    ollama_probe = run(compose_args() + ["exec", "-T", "agent-runtime", "sh", "-c", "command -v ollama"], check=False)
    if ollama_probe.returncode == 0:
        raise RuntimeError("Agent Runtime container has ollama installed at " + ollama_probe.stdout.strip())

    process_probe = run(
        compose_args() + ["exec", "-T", "agent-runtime", "sh", "-c", "ps -eo comm,args 2>/dev/null || true"],
        check=False,
    )
    process_hits = forbidden_runtime_hits(process_probe.stdout)
    if process_hits:
        raise RuntimeError("Agent Runtime process list contains LLM process/config: " + "; ".join(process_hits[:5]))

    logs = run_text(compose_args() + ["logs", "--no-color", "--tail=200", "agent-runtime"], check=False)
    log_hits = forbidden_runtime_hits(logs)
    if log_hits:
        raise RuntimeError("Agent Runtime logs contain LLM call/config evidence: " + "; ".join(log_hits[:5]))

    runtime_repo = Path(env("RIPPLEGUARD_AGENT_RUNTIME_REPO", str(ROOT / "../rippleguard-agent-runtime")))
    if not runtime_repo.exists():
        raise RuntimeError("Agent Runtime repository not found for LLM fallback scan: " + str(runtime_repo))
    repo_probe = subprocess.run(
        [
            "rg",
            "-n",
            "|".join(pattern.pattern for pattern in repository_llm_patterns()),
            "src",
            "tests",
            "pyproject.toml",
        ],
        cwd=runtime_repo,
        check=False,
        capture_output=True,
        text=True,
    )
    if repo_probe.returncode not in (0, 1):
        raise RuntimeError("Agent Runtime repository LLM scan failed: " + repo_probe.stderr.strip())
    repo_hits = [line[:240] for line in repo_probe.stdout.splitlines() if line.strip()]
    if repo_hits:
        raise RuntimeError("Agent Runtime repository contains fallback/LLM wiring: " + "; ".join(repo_hits[:5]))

    write_report(
        "local-llm-absent",
        "PASS",
        command,
        {
            "composeConfigForbiddenHits": 0,
            "containerEnvForbiddenHits": 0,
            "ollamaBinaryPresent": False,
            "processForbiddenHits": 0,
            "logForbiddenHits": 0,
            "repositoryForbiddenHits": 0,
            "agentRuntimeContainerId": container_id,
            "baseline": manifest_baseline_context(),
        },
    )


def blocked_drill(name: str, command: str, failure_classification: str) -> None:
    write_report(
        name,
        "BLOCKED",
        command,
        {
            "failureClassification": failure_classification,
            "reason": "REAL_FAILURE_INJECTION_NOT_IMPLEMENTED",
            "required": (
                "This drill must exercise real service/API/container/artifact behavior. "
                "Static PASS evidence is intentionally rejected."
            ),
            "baseline": manifest_baseline_context(),
        },
    )


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
    try:
        if args.check == "phase2-e2e":
            write_report("happy-path", "PASS", command, happy_path(command))
            return 0
        if args.check == "phase2-reproducibility-check":
            artifact_checks(command)
            return 0
        if args.check == "phase2-local-llm-absent-check":
            local_llm_absent_checks(command)
            return 0

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
        blocked_drill(report_name, command, classification)
        return 2
    except Exception as exc:
        report_name = "happy-path" if args.check == "phase2-e2e" else args.check.replace("phase2-", "").replace("-check", "")
        fail_report(report_name, command, str(exc), {"baseline": baseline_context()})
        raise


if __name__ == "__main__":
    sys.exit(main())
