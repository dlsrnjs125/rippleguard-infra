# Phase 2 Runtime Verification Evidence

## Scope

Infra changes are limited to `rippleguard-infra`.

Pinned source commits:

- `rippleguard-contracts`: `751f43c88c1bef860c76398eed24b3d60225b931`
- `rippleguard-loan-service`: `948e1039b249558683ed1a0276d054f4c56ccafe`
- `rippleguard-governance-service`: `053206df5d114b723bc6135642cbfcddeb54b2ba`
- `rippleguard-agent-runtime`: `25e8c187ee807f3a89055a5db2dbc18cb595a63e`
- `rippleguard-audit-replay-service`: `e6baae0a1fefcbb32ccc2dbd02cae2da8b360581`

## Image Baseline

- `loan-service`: `rippleguard-loan-service:948e1039b249`, local image ID `sha256:6b2f0f337eb613185e5b2968bad9bd8e400d2262becc0d25158f1e0f286d1d0a`
- `governance-service`: `rippleguard-governance-service:053206df5d11`, local image ID `sha256:1d06b97a48411e0df2dc126e7a4edc167c2e4982e54caa5ecf2951d0a363ea55`
- `agent-runtime`: `rippleguard-agent-runtime:25e8c187ee80`, local image ID `sha256:fcc4ae3a47ebd6d0d2c7c769f4f792c4c8999dcf35938ca9429e40d1c40c3733`
- `audit-replay-service`: `rippleguard-audit-replay-service:e6baae0a1fef`, local image ID `sha256:2e76510aeeff820b44769cbf922bebf511b71f46633556184daf7ce435fce4cf`

These are local Docker Compose verification image IDs, not production registry digests.

## Validation Status

Static and preflight gates validate:

- sibling checkout source commits
- clean sibling source trees before image build
- contract and model artifact digests
- read-only contract and model artifact mounts
- commit-based image tags
- OCI source and revision labels
- local image IDs

Runtime gates validate:

- service health and HTTP readiness
- absence of local or remote LLM wiring in compose, container environment, process list, logs, and Agent Runtime source/dependency wiring
- happy path through Loan, Governance, Agent Runtime, Audit, Kafka, and PostgreSQL
- request-to-validation event causation where `validation.causationId == request.eventId`
- `validation.causationId != agentRunId`
- reproducibility baseline digests

## Publication Status

The Phase 2 release manifest remains `BLOCKED`.

Reason:

- The happy path can be exercised with the current service baseline.
- The required failure drills still need real runtime failure injection. Static `BLOCKED` reports are intentionally not accepted as release evidence.

The manifest may be promoted to `PUBLISHED` only after every required failure drill passes with real service/API/container/artifact evidence.
