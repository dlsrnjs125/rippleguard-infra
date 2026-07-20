# Phase 1 Core MSA Evidence Plan

## Baselines

- Contracts: `29f6c348fd93633476438ee36b3f93a3d036e165`
- Loan Service: `e403c0a60ccb1cebf03380832d047f3fc01019e0`
- Governance Service: `45790ebd5de1c458f87a38b1a067b46c15a59134`
- Audit Replay Service: `83ca52edda2f608f90d10694428dff6dffee8a23`

Image and migration details are recorded in `manifests/phase1-core-msa.json`.

## Reproducible Commands

```bash
make phase1-build-images
make phase1-verify-images
make phase1-up
make phase1-check
make phase1-e2e
make phase1-duplicate-check
make phase1-recovery-check
make phase1-outbox-recovery-check
make phase1-order-check
make phase1-down
```

## Expected Results

- All containers reach running or healthy state.
- Loan, Governance, and Audit each use an isolated PostgreSQL container.
- All Phase 1 contract topics exist in Kafka.
- A normal application reaches Loan `FINALIZED`.
- Governance creates one resolved Decision Case and Evaluation Run.
- Duplicate application requests return the same `applicationId`.
- Replayed `loan.application.submitted.v1` and `loan.decision.commanded.v1` events do not create duplicate final state.
- Governance and Audit consumer restart recovery preserves the core flow.
- Loan outbox unpublished event recovery publishes the stored event after publisher restart.
- Audit Timeline handles delayed or out-of-order event arrival without exposing duplicate canonical events.
- Audit Timeline is queryable and does not expose raw financial snapshots, document text, prompts, secrets, or personal identifiers.

## Actual Results

Run commands generate sanitized per-run summaries under `artifacts/phase1/<run-id>/`. The `artifacts/` directory is ignored so raw run output is not committed.

Current runtime verification is blocked at `make phase1-duplicate-check`.
See `docs/evidence/phase-1-runtime-verification-blocked.md` for the failure summary, responsible repository, and required follow-up.
