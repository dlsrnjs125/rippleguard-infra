#!/usr/bin/env sh
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"
require_env_file
load_env
python3 "$ROOT_DIR/scripts/phase2_e2e.py" phase2-duplicate-request-check
