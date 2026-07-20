# Phase 1 Runtime Verification

## Status

- Date: `2026-07-20 15:26:52 KST`
- Repository: `dlsrnjs125/rippleguard-infra`
- Branch: `fix/phase-1-runtime-verification`
- Result: `PASS`

## Environment

- OS: `macOS 26.5.1`
- Docker Server: `29.5.3`
- Java: `openjdk 17.0.19`

## Baselines

- Contracts: `29f6c348fd93633476438ee36b3f93a3d036e165`
- Loan Service: `e403c0a60ccb1cebf03380832d047f3fc01019e0`
- Governance Service: `4e06e672affddc02d7e6662f3022d00de86bb3b9`
- Audit Replay Service: `83ca52edda2f608f90d10694428dff6dffee8a23`

## Images

| Service | Image | Revision Label | Source Label |
| --- | --- | --- | --- |
| Loan Service | `rippleguard-loan-service:e403c0a60ccb` | `e403c0a60ccb1cebf03380832d047f3fc01019e0` | `https://github.com/dlsrnjs125/rippleguard-loan-service` |
| Governance Service | `rippleguard-governance-service:4e06e672affd` | `4e06e672affddc02d7e6662f3022d00de86bb3b9` | `https://github.com/dlsrnjs125/rippleguard-governance-service` |
| Audit Replay Service | `rippleguard-audit-replay-service:83ca52edda2f` | `83ca52edda2f608f90d10694428dff6dffee8a23` | `https://github.com/dlsrnjs125/rippleguard-audit-replay-service` |

Phase 1 local baseline uses commit-based image tags and OCI labels. `imageDigest` remains `null`; registry digest pinning is deferred.

## Commands

| Command | Result |
| --- | --- |
| `make validate-static` | PASS |
| `make validate-contract-baseline` | PASS |
| `make phase1-build-images` | PASS |
| `make phase1-verify-images` | PASS |
| `make phase1-up` | PASS |
| `make phase1-check` | PASS |
| `make phase1-e2e` | PASS |
| `make phase1-duplicate-check` | PASS |
| `make phase1-recovery-check` | PASS |
| `make phase1-outbox-recovery-check` | PASS |
| `make phase1-order-check` | PASS |
| `make phase1-down` | PASS |

## Runtime Evidence

- E2E summary: `artifacts/phase1/20260720T152310/e2e-summary.json`
- Duplicate idempotency verified for application `9a5b5fad-0587-4263-931c-f371f84ccd3d`
- Recovery verified for application `ca84415d-6b9a-44c2-ba9d-a2f7415ef5e8`
- Outbox recovery verified for application `b20dff71-9fd9-4af6-a16f-4b27e4b0d769`
- Out-of-order timeline verified for application `eca0a744-b460-453c-be1a-cfeaa8f692ab`

## Migration Evidence

| Service | Version | Description | Script | Runtime Checksum |
| --- | --- | --- | --- | --- |
| Loan Service | `1` | `loan core` | `V1__loan_core.sql` | `981324118` |
| Governance Service | `1` | `governance core` | `V1__governance_core.sql` | `-1338716243` |
| Audit Replay Service | `1` | `audit foundation` | `V1__audit_foundation.sql` | `51402219` |

Runtime checksums are read from `flyway_schema_history`. Manifest migration checksums remain `null`.

## Residual Risks

- GHCR push and registry digest pinning are deferred.
- SBOM and SLSA provenance are deferred.
- OPA policy integration, replay, hash chain, version diff, execution graph, and graph UI remain deferred Phase 1 exclusions.
- Raw logs and secrets are not committed.
