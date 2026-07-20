# Phase 1 Runtime Verification Blocked

## Status

- Date: `2026-07-20`
- Repository: `dlsrnjs125/rippleguard-infra`
- Branch: `fix/phase-1-runtime-verification`
- Result: `BLOCKED`
- Blocking command: `make phase1-duplicate-check`
- Responsible repository for follow-up: `dlsrnjs125/rippleguard-governance-service`

## Environment

- OS: `macOS 26.5.1`
- Docker Server: `29.5.3`
- Java: `openjdk 17.0.19`

## Baselines Used

- Contracts: `29f6c348fd93633476438ee36b3f93a3d036e165`
- Loan Service: `e403c0a60ccb1cebf03380832d047f3fc01019e0`
- Governance Service: `45790ebd5de1c458f87a38b1a067b46c15a59134`
- Audit Replay Service: `83ca52edda2f608f90d10694428dff6dffee8a23`

## Completed Checks

- `make phase1-build-images`: PASS
- `make phase1-verify-images`: PASS
- `make phase1-up`: PASS
- `make phase1-check`: PASS
- `make phase1-e2e`: PASS
- `make phase1-duplicate-check`: FAIL
- `make phase1-down`: PASS

## Failure

`phase1-duplicate-check` creates a loan application twice with the same idempotency key, waits for the normal flow to finalize, then waits for the Audit timeline to become complete before replaying duplicate Kafka events.

The flow reached:

- Loan application `FINALIZED`
- Governance decision case `RESOLVED`
- Audit events persisted

The check failed while waiting for:

```text
http://audit-replay-service:8080/api/v1/cases/<caseId>/timeline
traceCompleteness == COMPLETE
len(events) == 6
```

Observed failing sample:

- `applicationId`: `014d7e22-d19e-419b-9253-525e5e50c451`
- `caseId`: `case-014d7e22-d19e-419b-9253-525e5e50c451`
- Timeline result: `traceCompleteness=PARTIAL`
- Timeline warnings: `EVENT_GAP_DETECTED`, `INVALID_REFERENCE`

## Audit DB Observation

The Audit DB contained all six expected event types for the application:

```text
loan.application.submitted.v1
governance.review.started.v1
agent.evaluation.requested.v1
agent.evaluation.completed.v1
loan.decision.commanded.v1
loan.decision.finalized.v1
```

The timeline remained partial because `loan.decision.commanded.v1` was ordered before its causation event `agent.evaluation.completed.v1`.

Observed order around the failure:

```text
loan.application.submitted.v1
loan.decision.commanded.v1
governance.review.started.v1
agent.evaluation.requested.v1
agent.evaluation.completed.v1
loan.decision.finalized.v1
```

`loan.decision.commanded.v1` referenced `agent.evaluation.completed.v1` as `causationId`, but the referenced event appeared later in the Audit timeline ordering. Audit therefore marked the command event as `INVALID_REFERENCE` and the trace as `PARTIAL`.

## Likely Cause

Governance Service emits multiple Phase 1 events with the same `occurredAt` value. Audit sorts timeline events by `occurredAt` and `ingestedAt`. When events share the same timestamp, ingestion order can place `loan.decision.commanded.v1` before `agent.evaluation.completed.v1`, breaking the causation chain.

This is not an Infra manifest, image provenance, Docker volume, or stale image issue.

## Required Follow-up

Fix the event ordering or timestamp semantics in `dlsrnjs125/rippleguard-governance-service` so that causation order is stable for:

```text
governance.review.started.v1
agent.evaluation.requested.v1
agent.evaluation.completed.v1
loan.decision.commanded.v1
```

After that service PR is merged:

1. Confirm the new Governance `main` commit.
2. Rebuild the Governance image from that commit with OCI labels.
3. Update `manifests/phase1-core-msa.json` in Infra with the new commit and image tag.
4. Re-run the full Phase 1 runtime verification sequence.

## Not Changed

- Infra validation conditions were not weakened.
- Label-less images were not retagged.
- Service code was not modified in this Infra branch.
- Raw logs and secrets were not committed.
