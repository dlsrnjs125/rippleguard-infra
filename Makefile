COMPOSE_FILE := compose/docker-compose.platform.yml
PHASE1_COMPOSE_FILE := compose/docker-compose.phase1.yml

.PHONY: platform-up platform-check platform-down platform-clean validate-static validate-contract-baseline phase1-build-images phase1-verify-images phase1-tag-local-images phase1-up phase1-check phase1-e2e phase1-duplicate-check phase1-recovery-check phase1-outbox-recovery-check phase1-order-check phase1-down phase1-clean

platform-up:
	./scripts/platform-up.sh

platform-check:
	./scripts/verify-platform.sh

platform-down:
	./scripts/platform-down.sh

platform-clean:
	./scripts/platform-down.sh --volumes

validate-static:
	./scripts/validate-static.sh

validate-contract-baseline:
	./scripts/validate-contract-baseline.sh

phase1-build-images:
	./scripts/phase1-build-local-images.sh

phase1-verify-images:
	./scripts/verify-phase1-images.py

phase1-tag-local-images:
	./scripts/phase1-tag-local-images.sh

phase1-up:
	./scripts/phase1-up.sh

phase1-check:
	./scripts/phase1-check.sh

phase1-e2e:
	./scripts/phase1-e2e.sh

phase1-duplicate-check:
	./scripts/phase1-duplicate-check.sh

phase1-recovery-check:
	./scripts/phase1-recovery-check.sh

phase1-outbox-recovery-check:
	./scripts/phase1-outbox-recovery-check.sh

phase1-order-check:
	./scripts/phase1-order-check.sh

phase1-down:
	./scripts/phase1-down.sh

phase1-clean:
	./scripts/phase1-down.sh --volumes
