COMPOSE_FILE := compose/docker-compose.platform.yml

.PHONY: platform-up platform-check platform-down platform-clean validate-static

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
