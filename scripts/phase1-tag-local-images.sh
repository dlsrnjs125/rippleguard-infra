#!/usr/bin/env sh
set -eu

echo "phase1-tag-local-images is deprecated." >&2
echo "Use make phase1-build-images to build commit-tagged images from service main commits." >&2
echo "Verifying existing manifest images instead." >&2

"$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/verify-phase1-images.py"
