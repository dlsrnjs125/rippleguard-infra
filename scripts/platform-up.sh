#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Create .env from .env.example before starting the platform" >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d kafka loan-postgres governance-postgres opa minio kafka-ui
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm kafka-init
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm minio-init
