#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

require_env_file
load_env

python3 "$ROOT_DIR/scripts/validate-phase2-manifest.py"
python3 "$ROOT_DIR/scripts/verify-phase2-images.py"
compose config >/dev/null

wait_for_container_state kafka healthy
wait_for_container_state loan-postgres healthy
wait_for_container_state governance-postgres healthy
wait_for_container_state audit-postgres healthy
wait_for_container_state agent-runtime healthy
wait_for_container_state loan-service running
wait_for_container_state governance-service running
wait_for_container_state audit-replay-service running
wait_for_container_state kafka-ui running

network="$(phase2_network)"
wait_for_http "$network" http://loan-service:8080/actuator/health
wait_for_http "$network" http://governance-service:8080/actuator/health
wait_for_http "$network" http://audit-replay-service:8080/actuator/health
wait_for_http "$network" http://agent-runtime:8080/ready

compose run --rm kafka-init /bin/sh /scripts/verify-topics.sh

echo "Phase 2 runtime wiring verified"
