#!/usr/bin/env sh

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PHASE2_MANIFEST="$ROOT_DIR/manifests/phase2-loan-decision.json"
PHASE2_COMPOSE_FILES="-f $ROOT_DIR/compose/docker-compose.platform.yml -f $ROOT_DIR/compose/docker-compose.phase2.yml"
ENV_FILE="$ROOT_DIR/.env"

require_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "Create .env from .env.example before running Phase 2 commands" >&2
    exit 1
  fi
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/compose/docker-compose.platform.yml" -f "$ROOT_DIR/compose/docker-compose.phase2.yml" "$@"
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

wait_for_container_state() {
  service="$1"
  expected="$2"
  attempts="${3:-60}"

  while [ "$attempts" -gt 0 ]; do
    container_id="$(compose ps -q "$service")"
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
  compose ps "$service" >&2
  return 1
}

phase2_network() {
  kafka_container_id="$(compose ps -q kafka)"
  docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$kafka_container_id" | sed -n '1p'
}

curl_from_network() {
  network="$1"
  shift
  docker run --rm --network "$network" curlimages/curl:8.11.1 "$@"
}

wait_for_http() {
  network="$1"
  url="$2"
  attempts="${3:-60}"

  while [ "$attempts" -gt 0 ]; do
    if curl_from_network "$network" -fsS "$url" >/dev/null 2>&1; then
      echo "$url is reachable"
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  echo "$url did not become reachable" >&2
  return 1
}
