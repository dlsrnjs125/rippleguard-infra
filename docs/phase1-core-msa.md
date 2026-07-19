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

If local `phase1` or `local` service images were produced by service repository verification, run `make phase1-tag-local-images` to copy them to the commit-based tags used by this compose stack.
