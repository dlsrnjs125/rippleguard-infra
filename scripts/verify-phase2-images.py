#!/usr/bin/env python3
"""Verify local Phase 2 service image provenance against the manifest."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "phase2-loan-decision.json"


def inspect_image(image: str) -> dict:
    result = subprocess.run(
        ["docker", "image", "inspect", image],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"image not found or not inspectable: {image}")
    return json.loads(result.stdout)[0]


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    failures: list[str] = []

    for service in manifest["services"]:
        image = service["image"]
        expected_labels = service["ociLabels"]
        expected_digest = service.get("imageDigest")
        try:
            inspected = inspect_image(image)
        except RuntimeError as exc:
            failures.append(str(exc))
            continue

        labels = inspected.get("Config", {}).get("Labels") or {}
        for key, expected in expected_labels.items():
            actual = labels.get(key)
            if actual != expected:
                failures.append(f"{image}: label {key} expected {expected}, got {actual!r}")

        if not expected_digest:
            failures.append(f"{image}: imageDigest is required")
            continue

        repo_digests = inspected.get("RepoDigests") or []
        image_id = inspected.get("Id")
        if image_id != expected_digest and not any(
            digest.endswith("@" + expected_digest) or digest == expected_digest for digest in repo_digests
        ):
            failures.append(
                f"{image}: digest {expected_digest} does not match image Id {image_id} or RepoDigests {repo_digests}"
            )

    if failures:
        print("\n".join(failures))
        return 1

    print("Phase 2 service image provenance verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
