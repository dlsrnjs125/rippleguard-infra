#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.platform.yml"

: "${LOAN_POSTGRES_DB:=rippleguard_loan}"
: "${LOAN_POSTGRES_USER:=rippleguard_loan}"
: "${LOAN_POSTGRES_PASSWORD:=change-me-loan-local}"
: "${GOVERNANCE_POSTGRES_DB:=rippleguard_governance}"
: "${GOVERNANCE_POSTGRES_USER:=rippleguard_governance}"
: "${GOVERNANCE_POSTGRES_PASSWORD:=change-me-governance-local}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not available" >&2
  exit 1
fi

docker compose -f "$COMPOSE_FILE" config >/dev/null

wait_for_service() {
  service="$1"
  expected="$2"
  attempts=30

  while [ "$attempts" -gt 0 ]; do
    container_id="$(docker compose -f "$COMPOSE_FILE" ps -q "$service")"
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
  docker compose -f "$COMPOSE_FILE" ps "$service" >&2
  return 1
}

wait_for_service kafka healthy
wait_for_service loan-postgres healthy
wait_for_service governance-postgres healthy
wait_for_service opa healthy
wait_for_service minio healthy
wait_for_service kafka-ui running

docker compose -f "$COMPOSE_FILE" exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null
docker compose -f "$COMPOSE_FILE" run --rm kafka-init /bin/sh /scripts/verify-topics.sh

docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$LOAN_POSTGRES_PASSWORD" loan-postgres \
  psql -U "$LOAN_POSTGRES_USER" -d "$LOAN_POSTGRES_DB" -c "select current_database(), current_user;" >/dev/null

docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$GOVERNANCE_POSTGRES_PASSWORD" governance-postgres \
  psql -U "$GOVERNANCE_POSTGRES_USER" -d "$GOVERNANCE_POSTGRES_DB" -c "select current_database(), current_user;" >/dev/null

if [ "$LOAN_POSTGRES_DB" = "$GOVERNANCE_POSTGRES_DB" ] || [ "$LOAN_POSTGRES_USER" = "$GOVERNANCE_POSTGRES_USER" ]; then
  echo "Loan and Governance database boundaries are not separated" >&2
  exit 1
fi

if docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$GOVERNANCE_POSTGRES_PASSWORD" loan-postgres \
  psql -h loan-postgres -U "$GOVERNANCE_POSTGRES_USER" -d "$GOVERNANCE_POSTGRES_DB" -c "select 1;" >/dev/null 2>&1; then
  echo "Governance credentials unexpectedly connected to Loan PostgreSQL" >&2
  exit 1
fi

docker run --rm --network rippleguard-local-platform curlimages/curl:8.11.1 -fsS http://opa:8181/health >/dev/null
docker run --rm --network rippleguard-local-platform curlimages/curl:8.11.1 -fsS http://minio:9000/minio/health/live >/dev/null

docker compose -f "$COMPOSE_FILE" run --rm --entrypoint /bin/sh minio-init /scripts/verify-buckets.sh

"$ROOT_DIR/scripts/check-topic-contracts.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "RippleGuard local platform verified"
