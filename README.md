# RippleGuard Infra

RippleGuard 로컬 개발용 공통 인프라 구성을 관리하는 저장소입니다.

## 구성

- Kafka, Kafka UI
- Loan Service PostgreSQL
- Governance Service PostgreSQL
- OPA
- MinIO
- 공통 Docker network

애플리케이션 서비스 이미지와 업무 테이블 마이그레이션은 각 서비스 저장소에서 관리합니다.

## 실행

처음 실행할 때는 `.env.example`을 참고해 `.env`를 생성합니다.

```bash
make platform-up
make platform-check
make platform-down
```

로컬 데이터를 포함한 Docker volume까지 삭제하려면 다음 명령을 사용합니다.

```bash
make platform-clean
```

`platform-clean`은 로컬 인프라 데이터를 삭제합니다.

## 설정

로컬 credential은 `.env`에서만 읽습니다. `.env.example`에는 예시값만 둡니다.

`.env` 파일은 커밋하지 않습니다.

## 기준 계약

Kafka topic과 이벤트 기준은 `contracts/phase0-baseline.json`에 기록된 contracts commit을 따릅니다.

`make platform-check`는 실행 중인 로컬 플랫폼과 내부 topic manifest를 검증합니다. GitHub의 pinned contracts commit까지 확인하려면 네트워크가 필요한 `make validate-contract-baseline`을 실행합니다.
