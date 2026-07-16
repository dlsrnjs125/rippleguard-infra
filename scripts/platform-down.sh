#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
ENV_FILE="$ROOT_DIR/.env"
FALLBACK_ENV_FILE="$ROOT_DIR/.env.example"

if [ -f "$ENV_FILE" ]; then
  if [ "${1:-}" = "--volumes" ]; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down --volumes --remove-orphans
  else
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down --remove-orphans
  fi
else
  echo "Warning: .env missing; using .env.example only to resolve Compose configuration" >&2
  if [ "${1:-}" = "--volumes" ]; then
    docker compose --env-file "$FALLBACK_ENV_FILE" -f "$COMPOSE_FILE" down --volumes --remove-orphans
  else
    docker compose --env-file "$FALLBACK_ENV_FILE" -f "$COMPOSE_FILE" down --remove-orphans
  fi
fi
