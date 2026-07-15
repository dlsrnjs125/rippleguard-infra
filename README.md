# RippleGuard Infra

RippleGuard Phase 1 개발을 위한 공통 로컬 플랫폼 구성입니다. 이 저장소는 Kafka, PostgreSQL, OPA, MinIO 같은 shared dependency만 관리하며, 실제 서비스 이미지와 업무 테이블은 각 서비스 저장소가 소유합니다.

## Phase 0 Scope

Included:

- Kafka in KRaft mode
- Kafka UI
- Loan Service PostgreSQL
- Governance Service PostgreSQL
- OPA server with a minimal health policy mount
- MinIO with a document bucket
- Shared Docker network and local verification scripts

Not included in this phase:

- Kubernetes or service mesh
- Redis cluster
- Schema Registry server
- Production TLS PKI
- Real service images
- Prometheus dashboards
- FDS simulator implementation

## Contracts Baseline

This infra baseline is pinned to the merged Phase 0 contracts PR.

- Contracts repository: `dlsrnjs125/rippleguard-contracts`
- Contracts PR: `#2`
- Contracts head commit: `39b22e40ae10a9ec3678cfac509a7fe6b747eaa4`
- Contracts merge commit on `main`: `a44f39d819fff5fe79db27e236a42e2a861a8b5e`
- Verified date: `2026-07-15`
- Event schema baseline: see `contracts/phase0-baseline.json`

The Kafka topic list is derived from the Phase 1 Event `eventType` values in that contracts baseline. Topic names intentionally match event names.

## Kafka Topics

Local topics are created explicitly by `kafka/scripts/create-topics.sh`; the platform does not rely on Kafka automatic topic creation.

Default local settings:

- Partitions: `3`
- Replication factor: `1`

The replication factor is `1` because Phase 0 runs a single local broker. Three partitions are enough to exercise consumer group behavior locally without adding cluster complexity.

## PostgreSQL Boundaries

The platform runs two independent PostgreSQL containers:

- `loan-postgres`
- `governance-postgres`

Each service has its own database, user, password variable, volume, health check, and port. Infra only verifies database creation and connectivity. Service-owned migrations must live in the service repositories.

## Commands

Copy `.env.example` to `.env` only when you need to override local defaults. Do not commit `.env`.

```bash
make platform-up
make platform-check
make platform-down
make platform-clean
```

`make platform-clean` removes Docker volumes and deletes local platform data.

## Local Ports

- Kafka broker external listener: `localhost:9094`
- Kafka UI: `http://localhost:8080`
- Loan PostgreSQL: `localhost:5433`
- Governance PostgreSQL: `localhost:5434`
- OPA: `http://localhost:8181`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## Validation

`make platform-check` verifies:

- Docker Compose config
- required container status or health
- Kafka broker connectivity
- expected Kafka topics
- Loan PostgreSQL connectivity
- Governance PostgreSQL connectivity
- DB account and storage boundary separation
- OPA health endpoint
- MinIO health endpoint
- document bucket existence
- basic secret pattern checks
- contracts baseline topic consistency

If Docker is not installed or the Docker daemon is unavailable, `make platform-check` fails instead of reporting success.
