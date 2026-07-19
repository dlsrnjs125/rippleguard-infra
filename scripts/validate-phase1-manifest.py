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
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


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
        source_url = service["sourceUrl"]
        labels = service["ociLabels"]
        migration = service["migration"]
        if not SHA.fullmatch(source_commit):
            failures.append(f"{service['name']} sourceCommit must be a full SHA")
        if service["repository"].split("/", 1)[1] not in source_url:
            failures.append(f"{service['name']} sourceUrl does not match repository")
        if tag in {"latest", "local", "phase1"} or not IMMUTABLE_TAG.fullmatch(tag):
            failures.append(f"{service['name']} immutableTag must be a 12-char commit tag")
        if image.endswith(":latest") or image.endswith(":local") or image.endswith(":phase1"):
            failures.append(f"{service['name']} image must not use latest/local/phase1")
        if not image.endswith(":" + tag):
            failures.append(f"{service['name']} image tag must equal immutableTag")
        image_digest = service.get("imageDigest")
        if image_digest is not None and not DIGEST.fullmatch(image_digest):
            failures.append(f"{service['name']} imageDigest must be null or sha256:<64 hex>")
        if labels.get("org.opencontainers.image.revision") != source_commit:
            failures.append(f"{service['name']} OCI revision label must equal sourceCommit")
        if labels.get("org.opencontainers.image.source") != source_url:
            failures.append(f"{service['name']} OCI source label must equal sourceUrl")
        if service["contractCommit"] != contract_commit:
            failures.append(f"{service['name']} contractCommit mismatch")
        if migration.get("version") != "1":
            failures.append(f"{service['name']} migration.version must be 1")
        if not migration.get("script", "").startswith("V1__"):
            failures.append(f"{service['name']} migration.script must record service-owned V1 migration")
        if migration.get("checksum") is not None and not isinstance(migration["checksum"], int):
            failures.append(f"{service['name']} migration.checksum must be null or integer")

    produced = {event for service in manifest["services"] for event in service["produces"]}
    consumed = {event for service in manifest["services"] for event in service["consumes"]}
    core_topic_set = set(core_topics)
    if produced - set(all_topics):
        failures.append(f"produced topics are not in all topic manifest: {sorted(produced - set(all_topics))}")
    if consumed - set(all_topics):
        failures.append(f"consumed topics are not in all topic manifest: {sorted(consumed - set(all_topics))}")
    if not core_topic_set.issubset(produced | consumed):
        failures.append(f"core topics missing from service capabilities: {sorted(core_topic_set - (produced | consumed))}")

    if failures:
        print("\n".join(failures))
        return 1

    print("Phase 1 core MSA manifest is valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
