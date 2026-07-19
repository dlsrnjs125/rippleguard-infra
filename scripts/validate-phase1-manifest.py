#!/usr/bin/env python3
"""Validate the Phase 1 core MSA image and contract manifest."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "phase1-core-msa.json"
BASELINE = ROOT / "contracts" / "phase1-core-baseline.json"
CORE_TOPICS = ROOT / "kafka" / "topics" / "phase1-core-events.txt"
ALL_TOPICS = ROOT / "kafka" / "topics" / "phase1-events.txt"

SHA = re.compile(r"^[0-9a-f]{40}$")
IMMUTABLE_TAG = re.compile(r"^[0-9a-f]{12}$")


def topics(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    failures: list[str] = []

    contract_commit = manifest["contractBaseline"]["sourceCommit"]
    if contract_commit != baseline["contractsMainCommitSha"]:
        failures.append("manifest contract commit does not match phase1 baseline")
    if not SHA.fullmatch(contract_commit):
        failures.append("contract commit must be a full SHA")

    core_topics = topics(CORE_TOPICS)
    all_topics = topics(ALL_TOPICS)
    if core_topics != manifest["coreTopics"]:
        failures.append("phase1-core-events.txt does not match manifest coreTopics")
    if sorted(core_topics) != sorted(baseline["coreEventTypes"]):
        failures.append("phase1 core topics do not match contract baseline coreEventTypes")
    missing_from_all = sorted(set(core_topics) - set(all_topics))
    if missing_from_all:
        failures.append(f"core topics missing from kafka/topics/phase1-events.txt: {missing_from_all}")

    versions = baseline["eventSchemaVersions"]
    for topic in core_topics:
        if versions.get(topic) != "1.1.0":
            failures.append(f"{topic} must use schemaVersion 1.1.0")

    for service in manifest["services"]:
        source_commit = service["sourceCommit"]
        image = service["image"]
        tag = service["immutableTag"]
        if not SHA.fullmatch(source_commit):
            failures.append(f"{service['name']} sourceCommit must be a full SHA")
        if tag in {"latest", "local", "phase1"} or not IMMUTABLE_TAG.fullmatch(tag):
            failures.append(f"{service['name']} immutableTag must be a 12-char commit tag")
        if image.endswith(":latest") or image.endswith(":local") or image.endswith(":phase1"):
            failures.append(f"{service['name']} image must not use latest/local/phase1")
        if not image.endswith(":" + tag):
            failures.append(f"{service['name']} image tag must equal immutableTag")
        if service["contractCommit"] != contract_commit:
            failures.append(f"{service['name']} contractCommit mismatch")
        if not service["migrationVersion"].startswith("V1__"):
            failures.append(f"{service['name']} migrationVersion must record service-owned V1 migration")

    if failures:
        print("\n".join(failures))
        return 1

    print("Phase 1 core MSA manifest is valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
