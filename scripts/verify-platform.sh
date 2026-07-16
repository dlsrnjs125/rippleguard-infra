#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Create .env from .env.example before checking the platform" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not available" >&2
  exit 1
fi

compose_config="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --format json)"

read_compose_env() {
  service="$1"
  key="$2"
  printf '%s' "$compose_config" | python3 "$ROOT_DIR/scripts/read-compose-env.py" "$service" "$key"
}

LOAN_POSTGRES_DB="$(read_compose_env loan-postgres POSTGRES_DB)"
LOAN_POSTGRES_USER="$(read_compose_env loan-postgres POSTGRES_USER)"
LOAN_POSTGRES_PASSWORD="$(read_compose_env loan-postgres POSTGRES_PASSWORD)"
GOVERNANCE_POSTGRES_DB="$(read_compose_env governance-postgres POSTGRES_DB)"
GOVERNANCE_POSTGRES_USER="$(read_compose_env governance-postgres POSTGRES_USER)"
GOVERNANCE_POSTGRES_PASSWORD="$(read_compose_env governance-postgres POSTGRES_PASSWORD)"

wait_for_service() {
  service="$1"
  expected="$2"
  attempts=30

  while [ "$attempts" -gt 0 ]; do
    container_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q "$service")"
    if [ -n "$container_id" ]; then
      state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
      if [ "$state" = "$expected" ]; then
        echo "$service is $state"
        return 0
      fi
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  echo "$service did not reach $expected" >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps "$service" >&2
  return 1
}

wait_for_service kafka healthy
wait_for_service loan-postgres healthy
wait_for_service governance-postgres healthy
wait_for_service opa healthy
wait_for_service minio healthy
wait_for_service kafka-ui running

kafka_container_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q kafka)"
platform_network="$(docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$kafka_container_id" | sed -n '1p')"
if [ -z "$platform_network" ]; then
  echo "Could not determine platform Docker network" >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm kafka-init /bin/sh /scripts/verify-topics.sh

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$LOAN_POSTGRES_PASSWORD" loan-postgres \
  psql -U "$LOAN_POSTGRES_USER" -d "$LOAN_POSTGRES_DB" -c "select current_database(), current_user;" >/dev/null

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$GOVERNANCE_POSTGRES_PASSWORD" governance-postgres \
  psql -U "$GOVERNANCE_POSTGRES_USER" -d "$GOVERNANCE_POSTGRES_DB" -c "select current_database(), current_user;" >/dev/null

loan_container_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q loan-postgres)"
governance_container_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q governance-postgres)"
if [ "$loan_container_id" = "$governance_container_id" ]; then
  echo "Loan and Governance PostgreSQL containers are not separated" >&2
  exit 1
fi

loan_volume_source="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' "$loan_container_id")"
governance_volume_source="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' "$governance_container_id")"
if [ "$loan_volume_source" = "$governance_volume_source" ]; then
  echo "Loan and Governance PostgreSQL volumes are not separated" >&2
  exit 1
fi

loan_hostname="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T loan-postgres hostname)"
governance_hostname="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T governance-postgres hostname)"
if [ "$loan_hostname" = "$governance_hostname" ]; then
  echo "Loan and Governance PostgreSQL hostnames are not separated" >&2
  exit 1
fi

loan_system_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$LOAN_POSTGRES_PASSWORD" loan-postgres \
  psql -U "$LOAN_POSTGRES_USER" -d "$LOAN_POSTGRES_DB" -Atc "select system_identifier from pg_control_system();")"
governance_system_id="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$GOVERNANCE_POSTGRES_PASSWORD" governance-postgres \
  psql -U "$GOVERNANCE_POSTGRES_USER" -d "$GOVERNANCE_POSTGRES_DB" -Atc "select system_identifier from pg_control_system();")"
if [ "$loan_system_id" = "$governance_system_id" ]; then
  echo "Loan and Governance PostgreSQL clusters share a system identifier" >&2
  exit 1
fi

if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$GOVERNANCE_POSTGRES_PASSWORD" loan-postgres \
  psql -h loan-postgres -U "$GOVERNANCE_POSTGRES_USER" -d "$LOAN_POSTGRES_DB" -c "select 1;" >/dev/null 2>&1; then
  echo "Governance credentials unexpectedly connected to Loan PostgreSQL" >&2
  exit 1
fi

if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$LOAN_POSTGRES_PASSWORD" governance-postgres \
  psql -h governance-postgres -U "$LOAN_POSTGRES_USER" -d "$GOVERNANCE_POSTGRES_DB" -c "select 1;" >/dev/null 2>&1; then
  echo "Loan credentials unexpectedly connected to Governance PostgreSQL" >&2
  exit 1
fi

docker run --rm --network "$platform_network" curlimages/curl:8.11.1 -fsS http://opa:8181/health >/dev/null
docker run --rm --network "$platform_network" curlimages/curl:8.11.1 -fsS http://minio:9000/minio/health/live >/dev/null
docker run --rm --network "$platform_network" curlimages/curl:8.11.1 -fsS http://kafka-ui:8080/actuator/health >/dev/null

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm --entrypoint /bin/sh minio-init /scripts/verify-buckets.sh

"$ROOT_DIR/scripts/check-topic-contracts.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "RippleGuard local platform verified"
