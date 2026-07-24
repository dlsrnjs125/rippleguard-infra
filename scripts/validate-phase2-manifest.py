#!/usr/bin/env python3
"""Validate the Phase 2 infra manifest against local baseline files."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "phase2-loan-decision.json"
CONTRACT_BASELINE = ROOT / "contracts" / "phase2-loan-decision-baseline.json"
TOPICS_FILE = ROOT / "kafka" / "topics" / "phase2-events.txt"

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
SHORT_SHA = re.compile(r"^[0-9a-f]{12}$")
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_artifact_path(path_text: str) -> Path:
    agent_runtime_repo = os.environ.get("RIPPLEGUARD_AGENT_RUNTIME_REPO")
    prefix = "../rippleguard-agent-runtime/"
    if agent_runtime_repo and path_text.startswith(prefix):
        return Path(agent_runtime_repo, path_text[len(prefix) :]).resolve()
    return (ROOT / path_text).resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-artifacts",
        action="store_true",
        help="Verify sibling Agent Runtime artifact files exist and match pinned digests.",
    )
    args = parser.parse_args()

    manifest = load_json(MANIFEST)
    baseline = load_json(CONTRACT_BASELINE)
    failures: list[str] = []

    contract_baseline = manifest.get("contractBaseline", {})
    baseline_commit = baseline.get("sourceCommit") or baseline.get("contractsMainCommitSha")
    if contract_baseline.get("sourceCommit") != baseline_commit:
        failures.append("contractBaseline.sourceCommit does not match contracts baseline")

    expected_topics = [
        line.strip()
        for line in TOPICS_FILE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    if manifest.get("topics") != expected_topics:
        failures.append("manifest topics must exactly match kafka/topics/phase2-events.txt")

    publication_status = manifest.get("publicationStatus")
    verification = manifest.get("verification", {})
    if publication_status == "BLOCKED":
        if verification.get("status") != "FAILED":
            failures.append("blocked Phase 2 manifest must record verification.status=FAILED")
        if verification.get("verifiedAt"):
            failures.append("blocked Phase 2 manifest must not carry verification.verifiedAt")
        if not manifest.get("knownBlockers"):
            failures.append("blocked Phase 2 manifest must list knownBlockers")
        if manifest.get("runtimeImageDigestKind") != "localImageId":
            failures.append("blocked local Phase 2 manifest must mark runtimeImageDigestKind=localImageId")
    elif publication_status == "PUBLISHED":
        if verification.get("status") != "PASS" or not verification.get("verifiedAt"):
            failures.append("published Phase 2 manifest must carry passing verification and verifiedAt")
        if manifest.get("knownBlockers"):
            failures.append("published Phase 2 manifest must not list knownBlockers")
        if manifest.get("runtimeImageDigestKind") != "registryDigest":
            failures.append("published Phase 2 manifest must use runtimeImageDigestKind=registryDigest")
    else:
        failures.append("publicationStatus must be BLOCKED or PUBLISHED")

    event_types = baseline.get("eventTypes", [])
    missing_topic_events = [event_type for event_type in event_types if event_type not in expected_topics]
    if missing_topic_events:
        failures.append(f"contract baseline eventTypes missing from topics file: {missing_topic_events}")

    for service in manifest.get("services", []):
        name = service.get("name", "<unknown>")
        commit = service.get("sourceCommit", "")
        image = service.get("image", "")
        if not FULL_SHA.fullmatch(commit):
            failures.append(f"{name}: sourceCommit must be a 40-character git sha")
            continue
        short = commit[:12]
        if not SHORT_SHA.fullmatch(service.get("immutableTag", "")):
            failures.append(f"{name}: immutableTag must be a 12-character commit prefix")
        if not image.endswith(":" + short):
            failures.append(f"{name}: image must be tagged with source commit prefix {short}")
        if image.endswith(":latest") or ":local" in image:
            failures.append(f"{name}: image tag must not use latest or local aliases")
        image_digest = service.get("imageDigest")
        image_digest_kind = service.get("imageDigestKind")
        if image_digest is None:
            if service.get("imageDigestStatus") != "blocked-unpublished-local-image":
                failures.append(f"{name}: imageDigest is required or must carry blocked-unpublished-local-image status")
        elif not SHA256.fullmatch(image_digest):
            failures.append(f"{name}: imageDigest must be a sha256 digest")
        if publication_status == "BLOCKED" and image_digest_kind != "localImageId":
            failures.append(f"{name}: blocked local manifest must mark imageDigestKind=localImageId")
        if publication_status == "PUBLISHED" and image_digest_kind != "registryDigest":
            failures.append(f"{name}: published manifest must mark imageDigestKind=registryDigest")
        labels = service.get("ociLabels", {})
        if labels.get("org.opencontainers.image.revision") != commit:
            failures.append(f"{name}: OCI revision label must match sourceCommit")
        if not labels.get("org.opencontainers.image.source", "").startswith("https://github.com/"):
            failures.append(f"{name}: OCI source label must point to GitHub source")

    model = manifest.get("modelBaseline", {})
    artifact_digest = model.get("modelArtifactDigest", "")
    artifact_sha = artifact_digest.removeprefix("sha256:")
    if artifact_digest != "sha256:" + artifact_sha:
        failures.append("modelArtifactDigest must match sha256 format")
    for key in ("modelArtifactDigest",):
        if not SHA256.fullmatch(model.get(key, "")):
            failures.append(f"{key} must be a sha256 digest")

    for key, digest_key in (
        ("modelManifestPath", "modelManifestDigest"),
        ("modelArtifactPath", "modelArtifactDigest"),
        ("thresholdManifestPath", "thresholdManifestDigest"),
    ):
        path_text = model.get(key, "")
        digest_text = model.get(digest_key, "")
        if not path_text:
            failures.append(f"{key} is required")
        if not SHA256.fullmatch(digest_text):
            failures.append(f"{digest_key} must be a sha256 digest")
        if args.check_artifacts:
            expected_digest = digest_text.removeprefix("sha256:")
            candidate = resolve_artifact_path(path_text)
            if not candidate.exists():
                failures.append(f"{key} does not exist: {path_text}")
                continue
            actual_digest = file_sha256(candidate)
            if actual_digest != expected_digest:
                failures.append(f"{key} digest mismatch: expected {expected_digest}, got {actual_digest}")

    excluded = manifest.get("excludedRuntimeDependencies", {})
    if excluded:
        if excluded.get("localLlm") is not True:
            failures.append("excludedRuntimeDependencies.localLlm must be true")
    elif "Local LLM" not in manifest.get("excluded", []):
        failures.append("manifest must explicitly exclude Local LLM")

    if failures:
        print("\n".join(failures))
        return 1

    print("Phase 2 manifest validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
