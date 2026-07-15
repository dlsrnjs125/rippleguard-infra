#!/usr/bin/env python3
"""Ensure infra Kafka topics match the pinned contracts baseline."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "contracts" / "phase0-baseline.json"
TOPICS = ROOT / "kafka" / "topics" / "phase1-events.txt"


def read_topics() -> list[str]:
    topics: list[str] = []
    for line in TOPICS.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            topics.append(stripped)
    return topics


def main() -> int:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    baseline_topics = baseline["eventTypes"]
    infra_topics = read_topics()

    if baseline_topics != infra_topics:
        print("Contracts baseline eventTypes and Kafka topic list differ")
        print(f"baseline={baseline_topics}")
        print(f"topics={infra_topics}")
        return 1

    print("Contracts baseline topics match infra Kafka topics")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
