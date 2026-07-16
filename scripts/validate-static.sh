#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
OBSERVABILITY_COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.observability.yml"
ENV_EXAMPLE="$ROOT_DIR/.env.example"

docker compose --env-file "$ENV_EXAMPLE" -f "$COMPOSE_FILE" config >/dev/null
docker compose -f "$OBSERVABILITY_COMPOSE_FILE" config >/dev/null

for script in "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/kafka/scripts/*.sh "$ROOT_DIR"/minio/scripts/*.sh; do
  sh -n "$script"
done

python3 -m json.tool "$ROOT_DIR/contracts/phase0-baseline.json" >/dev/null
python3 "$ROOT_DIR/scripts/check-topic-contracts.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "Static infra validation passed"
