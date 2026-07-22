#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

require_env_file

"$ROOT_DIR/scripts/phase2-preflight.sh"

compose up -d kafka loan-postgres governance-postgres audit-postgres kafka-ui
compose run --rm kafka-init
compose up -d agent-runtime
wait_for_container_state agent-runtime healthy
compose up -d loan-service audit-replay-service governance-service

echo "Phase 2 loan decision integration stack started"
