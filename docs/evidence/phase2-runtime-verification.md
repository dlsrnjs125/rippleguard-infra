# Phase 2 Runtime Verification Evidence

## Scope

Infra changes are limited to `rippleguard-infra`.

Pinned source commits:

- `rippleguard-contracts`: `f4012e8b5a0dcd5605b61652a5c39deacb14454b`
- `rippleguard-loan-service`: `e403c0a60ccb464545a6b68d761d0bf8c05f7435`
- `rippleguard-governance-service`: `6e5dee34a01429ac017774fcd7a238e2f1415481`
- `rippleguard-agent-runtime`: `35121627550e5999a084c123b610f47884aa01f7`
- `rippleguard-audit-replay-service`: `f3162d3bf3ea2bcfd8d40c929607a84d88054082`

## Current Validation Status

Static infra validation:

```bash
make validate-static
```

Phase 2 manifest validation:

```bash
python3 scripts/validate-phase2-manifest.py
```

Phase 2 image provenance validation:

```bash
make phase2-verify-images
```

Expected current blocker:

- `rippleguard-agent-runtime:35121627550e` cannot pass OCI label verification until the Agent Runtime Dockerfile emits `org.opencontainers.image.revision` and `org.opencontainers.image.source`.
- Phase 2 service images do not have pinned registry digests yet, so image verification must fail rather than skip immutable image identity verification.

Phase 2 E2E:

```bash
make phase2-e2e
```

Expected current result:

- `BLOCKED`

Reason:

- The current Loan event path does not publish the materialized Phase 2 feature payload required by Agent Runtime.
- Governance emits a contract-valid immutable snapshot reference, but Agent Runtime currently expects concrete feature input.
- Infra must not replace that production path with mock payloads, fixture-only shortcuts, local LLMs, fallback models, or synthetic success.

## Required Follow-Up

The Phase 2 happy path can be promoted from blocked to executable after one of these upstream changes lands:

- Loan/Governance provides a production feature snapshot provider for Phase 2.
- Agent Runtime resolves immutable snapshot references through an approved production data path.

After that, update `scripts/phase2-e2e.sh` to submit a real loan application, wait for Governance validation, and verify Audit Agent Run timeline projections.
