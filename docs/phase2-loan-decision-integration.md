# Phase 2 Loan Decision Integration

This repository composes the Phase 2 Loan, Governance, Agent Runtime, and Audit services with Kafka and isolated PostgreSQL databases.

Infra owns runtime composition, release evidence, and verification gates only. Service migrations, business behavior, contracts, and model runtime code remain owned by their source repositories.

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

OPA and MinIO remain available from the base platform. This Phase 2 overlay mounts contracts and model artifacts from sibling repositories as read-only bind mounts. Phase 2 agent evaluation does not use a local LLM, remote LLM, fallback model, mock model, or training path.

## Runtime Flow

The executable Phase 2 flow is:

1. Loan accepts a real application submission and materializes an immutable Phase 2 Feature Snapshot.
2. Loan publishes `loan.application.submitted.v1` with the snapshot reference.
3. Governance starts an Evaluation Run, resolves the immutable snapshot through Loan's internal API, and verifies identity and digests.
4. Governance persists `agent.evaluation.requested.v1`, stores that event ID, and calls Agent Runtime.
5. Agent Runtime evaluates the pinned model artifact and returns the deterministic decision result.
6. Governance validates the result, transitions the case to `PROPOSAL_READY`, and publishes `governance.agent-result.validated.v1`.
7. The validation event uses the persisted request event ID as `causationId`; it does not use `agentRunId` as causation.
8. Audit projects the request and validation events into timeline and Agent Run APIs, using bounded pending causation reconciliation for cross-topic delivery.

## Image Policy

`latest`, `local`, fallback, and mutable alias tags are not allowed for Phase 2 service images.

The Phase 2 manifest pins service source commits and local image IDs:

- `loan-service`: `rippleguard-loan-service:948e1039b249`
- `governance-service`: `rippleguard-governance-service:053206df5d11`
- `agent-runtime`: `rippleguard-agent-runtime:25e8c187ee80`
- `audit-replay-service`: `rippleguard-audit-replay-service:e6baae0a1fef`

`make phase2-verify-images` requires each image to expose:

- `org.opencontainers.image.revision`
- `org.opencontainers.image.source`

The current manifest is a local Docker Compose verification baseline and uses `imageDigestKind: localImageId`. It must not be treated as a pullable production registry baseline until registry digests and immutable image references are recorded.

## Model Artifact Policy

The Agent Runtime container mounts contract and model artifacts read-only:

- Contracts: `${RIPPLEGUARD_CONTRACTS_REPO}:/app/contracts:ro`
- Model manifests: `${RIPPLEGUARD_AGENT_RUNTIME_REPO}/artifacts/manifests:/app/artifacts/manifests:ro`
- Model artifacts: `${RIPPLEGUARD_AGENT_RUNTIME_REPO}/artifacts/models:/app/artifacts/models:ro`

The pinned model baseline is recorded in `manifests/phase2-loan-decision.json` and validated by `scripts/validate-phase2-manifest.py`.

## Commands

```bash
make validate-static
make phase2-build-images
make phase2-verify-images
make phase2-scaffold-check
make phase2-preflight
make phase2-up
make phase2-check
make phase2-local-llm-absent-check
make phase2-e2e
make phase2-reproducibility-check
make phase2-verify
make phase2-down
```

Command intent is intentionally split:

- `make phase2-scaffold-check`: source, manifest, artifact digest, mount, and compose structure validation.
- `make phase2-preflight`: scaffold check plus image digest and OCI provenance verification.
- `make phase2-e2e`: real runtime happy path through Loan, Governance, Agent Runtime, Audit, Kafka, and PostgreSQL.
- `make phase2-verify`: full runtime verification including failure drills.

## Current Status

Resolved upstream blockers:

- Loan Service provides the immutable Phase 2 Feature Snapshot API.
- Loan Service normalizes snapshot `createdAt` and `snapshotReference.snapshotCreatedAt` to the same persisted microsecond identity.
- Governance resolves materialized Feature Payload through Loan's Snapshot API.
- Agent Runtime images expose OCI source and revision labels.
- Service images are pinned to commit-based tags and local image IDs.
- Governance validation causation uses the persisted request event ID, not `agentRunId`.
- Audit supports cross-topic out-of-order causation through bounded pending reconciliation.

Remaining release blocker:

- Retry, timeout, duplicate, conflict, artifact, contract, snapshot, and recovery drills still require real failure injection implementations before this manifest can be promoted to `PUBLISHED`.

The release manifest must stay `BLOCKED` until every required drill produces real runtime evidence with exit code 0.
