# Phase 2 Loan Decision Integration

This repository wires the Phase 2 Loan, Governance, Agent Runtime, and Audit services with Kafka and isolated PostgreSQL databases.

Infra owns runtime composition and verification only. Service migrations, business code, contracts, and model runtime code remain owned by their source repositories.

## Services

- `loan-service`
- `governance-service`
- `agent-runtime`
- `audit-replay-service`
- `loan-postgres`
- `governance-postgres`
- `audit-postgres`
- `kafka`
- `kafka-ui`
- `minio`

OPA remains available from the base platform, but Phase 2 agent evaluation does not use a local LLM, remote LLM, fallback model, mock model, or training path.

## Runtime Flow

The intended production flow is:

1. Loan publishes `loan.application.submitted.v1`.
2. Governance starts the Phase 2 review and calls Agent Runtime at `/internal/v1/loan-decision-agent/runs`.
3. Agent Runtime returns the deterministic model decision from the pinned model artifact.
4. Governance publishes `governance.agent-result.validated.v1`.
5. Audit projects the Governance validation event into the Agent Run timeline APIs.

The current service boundary blocks a real end-to-end happy path from infra alone. Loan publishes the Phase 1 submitted event without a materialized Phase 2 feature payload. Governance currently passes a contract-valid immutable reference, while Agent Runtime requires executable feature input. `make phase2-e2e` exits with `BLOCKED` until the upstream snapshot/feature-provider gap is closed.

## Image Policy

`latest`, `local`, fallback, and mutable alias tags are not allowed for Phase 2 service images.

The Phase 2 manifest pins service source commits and expected image tags:

- `loan-service`: `rippleguard-loan-service:e403c0a60ccb`
- `governance-service`: `rippleguard-governance-service:6e5dee34a014`
- `agent-runtime`: `rippleguard-agent-runtime:35121627550e`
- `audit-replay-service`: `rippleguard-audit-replay-service:f3162d3bf3ea`

`make phase2-verify-images` requires each image to expose:

- `org.opencontainers.image.revision`
- `org.opencontainers.image.source`

The current Agent Runtime Dockerfile does not expose those OCI labels, so image provenance verification is expected to fail until that upstream Dockerfile is updated.

## Model Artifact Policy

The Agent Runtime container mounts contract and model artifacts read-only:

- Contracts: `../rippleguard-contracts:/app/contracts:ro`
- Model manifests: `../rippleguard-agent-runtime/artifacts/manifests:/app/artifacts/manifests:ro`
- Model artifacts: `../rippleguard-agent-runtime/artifacts/models:/app/artifacts/models:ro`

The pinned model baseline is recorded in `manifests/phase2-loan-decision.json` and validated by `scripts/validate-phase2-manifest.py`.

## Commands

```bash
make phase2-build-images
make phase2-verify-images
make phase2-preflight
make phase2-up
make phase2-check
make phase2-local-llm-absent-check
make phase2-e2e
make phase2-down
```

`make phase2-verify` chains the static validation, preflight, stack startup, runtime checks, local LLM absence check, and E2E check. It should remain non-green while the known upstream blockers exist.

## Known Blockers

- Loan does not yet provide the materialized Phase 2 feature payload required by Agent Runtime.
- Agent Runtime image provenance cannot be verified until its Dockerfile supports the OCI labels required by the manifest.
- Contracts documentation and runtime behavior still need a single explicit policy for Phase 2 Governance causation: `causationId = agentRunId`.
