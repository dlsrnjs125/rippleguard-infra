# Phase 1 Core MSA Evidence Plan

## Baselines

- Contracts: `29f6c348fd93633476438ee36b3f93a3d036e165`
- Loan Service: `54ea344a682723d61d9beedf4ade56ee48029c0d`
- Governance Service: `29bafba34c47e003fdefafa455924992993721cf`
- Audit Replay Service: `e7d9d9f8afb106ecdec16235d79695d88c18b3cd`

Image and migration details are recorded in `manifests/phase1-core-msa.json`.

## Reproducible Commands

```bash
make phase1-up
make phase1-check
make phase1-e2e
make phase1-duplicate-check
make phase1-recovery-check
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
- Audit Timeline is queryable and does not expose raw financial snapshots, document text, prompts, secrets, or personal identifiers.

## Actual Results

Run `make phase1-e2e` to generate `docs/evidence/phase1-e2e-summary.md`.
