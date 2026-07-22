#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

"$ROOT_DIR/scripts/phase2-scaffold-check.sh"

python3 "$ROOT_DIR/scripts/verify-phase2-images.py"

echo "Phase 2 preflight passed"
