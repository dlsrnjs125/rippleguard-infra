#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cleanup() {
  if [ -f "$ROOT_DIR/.env" ]; then
    "$ROOT_DIR/scripts/phase2-down.sh"
  fi
}

trap cleanup EXIT HUP INT TERM

"$ROOT_DIR/scripts/validate-static.sh"
"$ROOT_DIR/scripts/phase2-up.sh"
"$ROOT_DIR/scripts/phase2-check.sh"
"$ROOT_DIR/scripts/phase2-local-llm-absent-check.sh"
"$ROOT_DIR/scripts/phase2-e2e.sh"
