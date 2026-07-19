#!/usr/bin/env sh
set -eu

# shellcheck source=phase1-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase1-common.sh"

require_env_file

compose up -d kafka loan-postgres governance-postgres audit-postgres opa minio kafka-ui
compose run --rm kafka-init
compose run --rm minio-init
compose up -d loan-service governance-service audit-replay-service

echo "Phase 1 core MSA stack started"
