#!/usr/bin/env python3
"""Validate infra Kafka topics against the pinned contracts baseline."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "contracts" / "phase0-baseline.json"
TOPICS = ROOT / "kafka" / "topics" / "phase1-events.txt"
SCHEMA_NAME = re.compile(
    r"^(?P<event>.+\.v(?P<major>[1-9][0-9]*))\.(?P<minor>[0-9]+)\.(?P<patch>[0-9]+)\.schema\.json$"
)


def read_topics() -> list[str]:
    topics: list[str] = []
    for line in TOPICS.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            topics.append(stripped)
    return topics


def property_consts(value: Any, property_name: str) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        candidate = value.get("properties", {}).get(property_name)
        if isinstance(candidate, dict) and isinstance(candidate.get("const"), str):
            found.add(candidate["const"])
        for child in value.values():
            found.update(property_consts(child, property_name))
    elif isinstance(value, list):
        for child in value:
            found.update(property_consts(child, property_name))
    return found


def contracts_event_versions(contracts_dir: Path) -> dict[str, set[str]]:
    schemas_dir = contracts_dir / "schemas" / "events"
    versions: dict[str, set[str]] = {}
    failures: list[str] = []

    for schema_path in sorted(schemas_dir.glob("*.schema.json")):
        match = SCHEMA_NAME.fullmatch(schema_path.name)
        if not match:
            failures.append(f"unexpected event schema filename: {schema_path}")
            continue

        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        event_types = property_consts(schema, "eventType")
        schema_versions = property_consts(schema, "schemaVersion")

        expected_event_type = match.group("event")
        expected_schema_version = f"{match.group('major')}.{match.group('minor')}.{match.group('patch')}"
        if event_types != {expected_event_type}:
            failures.append(
                f"{schema_path.name}: eventType const {sorted(event_types)} "
                f"does not match filename {expected_event_type}"
            )
        if schema_versions != {expected_schema_version}:
            failures.append(
                f"{schema_path.name}: schemaVersion const {sorted(schema_versions)} "
                f"does not match filename {expected_schema_version}"
            )

        versions.setdefault(expected_event_type, set()).add(expected_schema_version)

    if failures:
        raise ValueError("\n".join(failures))
    return versions


def compare_lists(label_a: str, values_a: list[str], label_b: str, values_b: list[str]) -> list[str]:
    if values_a == values_b:
        return []
    return [
        f"{label_a} and {label_b} differ",
        f"{label_a}={values_a}",
        f"{label_b}={values_b}",
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contracts-dir",
        type=Path,
        help="Checked-out rippleguard-contracts repository at the pinned commit.",
    )
    args = parser.parse_args()

    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    manifest_topics = baseline["eventTypes"]
    manifest_versions = baseline["eventSchemaVersions"]
    infra_topics = read_topics()
    failures: list[str] = []

    failures.extend(compare_lists("manifest eventTypes", manifest_topics, "infra topics", infra_topics))

    if set(manifest_versions) != set(manifest_topics):
        failures.append("manifest eventSchemaVersions keys do not match eventTypes")
        failures.append(f"eventTypes={manifest_topics}")
        failures.append(f"eventSchemaVersions={sorted(manifest_versions)}")

    if args.contracts_dir:
        contract_versions = contracts_event_versions(args.contracts_dir)
        contract_topics = sorted(contract_versions)

        failures.extend(
            compare_lists("contracts eventTypes", contract_topics, "manifest eventTypes", sorted(manifest_topics))
        )
        failures.extend(compare_lists("contracts eventTypes", contract_topics, "infra topics", sorted(infra_topics)))

        for event_type, expected_version in sorted(manifest_versions.items()):
            actual_versions = contract_versions.get(event_type, set())
            if expected_version not in actual_versions:
                failures.append(
                    f"manifest version {event_type}={expected_version} does not exist in contracts schemas; "
                    f"available={sorted(actual_versions)}"
                )

    if failures:
        print("\n".join(failures))
        return 1

    if args.contracts_dir:
        print("Contracts schemas, baseline manifest, and infra Kafka topics match")
    else:
        print("Contracts baseline manifest and infra Kafka topics match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
