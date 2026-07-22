#!/usr/bin/env sh
set -eu

cat >&2 <<'EOF'
BLOCKED: Phase 2 production E2E is not executable from infra alone.

Observed runtime boundary:
- Loan currently publishes loan.application.submitted.v1 without the materialized Phase 2 feature payload required by Agent Runtime.
- Governance produces a contract-valid immutable reference, but Agent Runtime expects executable feature input.
- Infra must not fabricate fixtures, mocks, local LLM fallbacks, or synthetic success to bypass this gap.

Required upstream follow-up:
- Add a Loan snapshot/feature provider integration for Phase 2, or
- Add Agent Runtime support for resolving immutable snapshot references through the production data path.
EOF

exit 2
