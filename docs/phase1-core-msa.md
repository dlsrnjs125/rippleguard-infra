# Phase 1 Core MSA Integration

This repository composes the Phase 1 Loan, Governance, and Audit services with Kafka and isolated PostgreSQL databases.

Infra owns platform wiring only. Service migrations remain owned by each service image.

## Services

- `loan-service`
- `governance-service`
- `audit-replay-service`
- `loan-postgres`
- `governance-postgres`
- `audit-postgres`
- `kafka`
- `kafka-ui`

OPA and MinIO remain available from the Phase 0 platform, but the Phase 1 core E2E flow does not force them into the decision path.

## Core Flow

`POST /api/v1/loan-applications` creates a Loan Application and emits `loan.application.submitted.v1`.

Governance consumes the submitted event, creates a Decision Case and Evaluation Run, performs deterministic mock evaluation and mock assurance, then emits:

- `governance.review.started.v1`
- `agent.evaluation.requested.v1`
- `agent.evaluation.completed.v1`
- `loan.decision.commanded.v1`

Loan consumes the decision command, finalizes the application, and emits `loan.decision.finalized.v1`.

Audit consumes the six core events and exposes:

`GET /api/v1/cases/{caseId}/timeline`

## Image Policy

`latest` is not allowed. Phase 1 service images use commit-based tags recorded in `manifests/phase1-core-msa.json`.

For local testing, the images must exist before `make phase1-up` runs.

Run `make phase1-build-images` from this repository to package the service checkouts and build commit-tagged images with the OCI build arguments recorded in the manifest. The helper refuses to build if a service checkout HEAD does not match the manifest `sourceCommit`.

`make phase1-verify-images` verifies each local image exposes:

- `org.opencontainers.image.revision`: full 40-character source commit
- `org.opencontainers.image.source`: canonical GitHub repository URL

`make phase1-check` verifies those labels against `manifests/phase1-core-msa.json`.

## Known Limitations

- Service images are verified using immutable commit tags and OCI source/revision labels.
- Registry digest pinning is deferred until images are published to GHCR.
- Flyway script/version/description are verified; committed checksum baselines are deferred until release images are finalized.
