COMPOSE_FILE := compose/docker-compose.platform.yml
PHASE1_COMPOSE_FILE := compose/docker-compose.phase1.yml
PHASE2_COMPOSE_FILE := compose/docker-compose.phase2.yml

.PHONY: platform-up platform-check platform-down platform-clean validate-static validate-contract-baseline phase1-build-images phase1-verify-images phase1-tag-local-images phase1-up phase1-check phase1-e2e phase1-duplicate-check phase1-recovery-check phase1-outbox-recovery-check phase1-order-check phase1-down phase1-clean phase2-build-images phase2-verify-images phase2-scaffold-check phase2-preflight phase2-up phase2-check phase2-e2e phase2-retry-check phase2-timeout-check phase2-duplicate-request-check phase2-duplicate-result-check phase2-conflict-check phase2-artifact-digest-failure-check phase2-missing-artifact-check phase2-contract-mismatch-check phase2-snapshot-mismatch-check phase2-recovery-check phase2-reproducibility-check phase2-local-llm-absent-check phase2-down phase2-clean phase2-verify

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

phase2-build-images:
	./scripts/phase2-build-local-images.sh

phase2-verify-images:
	./scripts/verify-phase2-images.py

phase2-scaffold-check:
	./scripts/phase2-scaffold-check.sh

phase2-preflight:
	./scripts/phase2-preflight.sh

phase2-up:
	./scripts/phase2-up.sh

phase2-check:
	./scripts/phase2-check.sh

phase2-e2e:
	./scripts/phase2-e2e.sh

phase2-retry-check:
	./scripts/phase2-retry-check.sh

phase2-timeout-check:
	./scripts/phase2-timeout-check.sh

phase2-duplicate-request-check:
	./scripts/phase2-duplicate-request-check.sh

phase2-duplicate-result-check:
	./scripts/phase2-duplicate-result-check.sh

phase2-conflict-check:
	./scripts/phase2-conflict-check.sh

phase2-artifact-digest-failure-check:
	./scripts/phase2-artifact-digest-failure-check.sh

phase2-missing-artifact-check:
	./scripts/phase2-missing-artifact-check.sh

phase2-contract-mismatch-check:
	./scripts/phase2-contract-mismatch-check.sh

phase2-snapshot-mismatch-check:
	./scripts/phase2-snapshot-mismatch-check.sh

phase2-recovery-check:
	./scripts/phase2-recovery-check.sh

phase2-reproducibility-check:
	./scripts/phase2-reproducibility-check.sh

phase2-local-llm-absent-check:
	./scripts/phase2-local-llm-absent-check.sh

phase2-down:
	./scripts/phase2-down.sh

phase2-clean:
	./scripts/phase2-down.sh --volumes

phase2-verify:
	./scripts/phase2-verify.sh
