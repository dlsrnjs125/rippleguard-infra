#!/usr/bin/env sh
set -eu

# shellcheck source=phase2-common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/phase2-common.sh"

require_env_file

config="$(compose config)"
if printf '%s\n' "$config" | grep -Ei 'ollama|openai|anthropic|llm|chatgpt|langchain' >/dev/null; then
  echo "Phase 2 compose config contains local or external LLM wiring" >&2
  exit 1
fi

python3 - "$PHASE2_MANIFEST" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
excluded = manifest.get("excludedRuntimeDependencies", {})
if excluded.get("localLlm") is not True or excluded.get("fallbackModel") is not True:
    print("Phase 2 manifest must explicitly exclude local LLM and fallback model dependencies")
    sys.exit(1)
print("Phase 2 local LLM absence verified")
PY

load_env
python3 "$ROOT_DIR/scripts/phase2_e2e.py" phase2-local-llm-absent-check
