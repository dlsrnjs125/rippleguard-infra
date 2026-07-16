#!/usr/bin/env python3
"""Read one service environment value from `docker compose config --format json`."""

from __future__ import annotations

import json
import sys
from typing import Any


def environment_value(environment: Any, key: str) -> str:
    if isinstance(environment, dict):
        value = environment.get(key)
    elif isinstance(environment, list):
        prefix = f"{key}="
        value = next((item[len(prefix):] for item in environment if isinstance(item, str) and item.startswith(prefix)), None)
    else:
        value = None

    if value is None:
        raise KeyError(key)
    return str(value)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: read-compose-env.py <service> <environment-key>", file=sys.stderr)
        return 2

    service, key = sys.argv[1:]
    config = json.load(sys.stdin)
    print(environment_value(config["services"][service].get("environment", {}), key))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
