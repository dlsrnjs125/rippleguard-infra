#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

if [ -f "$ENV_FILE" ]; then
  if [ "${1:-}" = "--volumes" ]; then
    compose down --volumes --remove-orphans
  else
    compose down --remove-orphans
  fi
else
  echo "Warning: .env missing; using Compose defaults only to resolve configuration" >&2
  if [ "${1:-}" = "--volumes" ]; then
    docker compose -f "$ROOT_DIR/compose/docker-compose.platform.yml" -f "$ROOT_DIR/compose/docker-compose.phase1.yml" down --volumes --remove-orphans
  else
    docker compose -f "$ROOT_DIR/compose/docker-compose.platform.yml" -f "$ROOT_DIR/compose/docker-compose.phase1.yml" down --remove-orphans
  fi
fi
