#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"

if [ "${1:-}" = "--volumes" ]; then
  docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
else
  docker compose -f "$COMPOSE_FILE" down --remove-orphans
fi
