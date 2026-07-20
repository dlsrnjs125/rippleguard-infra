#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/manifests/phase1-core-msa.json"

default_repo_path() {
  service="$1"
  case "$service" in
    loan-service) printf '%s\n' "$ROOT_DIR/../rippleguard-loan-service" ;;
    governance-service) printf '%s\n' "$ROOT_DIR/../rippleguard-governance-service" ;;
    audit-replay-service) printf '%s\n' "$ROOT_DIR/../rippleguard-audit-replay-service" ;;
    *) echo "Unknown service: $service" >&2; exit 1 ;;
  esac
}

repo_path() {
  service="$1"
  case "$service" in
    loan-service) printf '%s\n' "${RIPPLEGUARD_LOAN_REPO:-$(default_repo_path "$service")}" ;;
    governance-service) printf '%s\n' "${RIPPLEGUARD_GOVERNANCE_REPO:-$(default_repo_path "$service")}" ;;
    audit-replay-service) printf '%s\n' "${RIPPLEGUARD_AUDIT_REPO:-$(default_repo_path "$service")}" ;;
    *) echo "Unknown service: $service" >&2; exit 1 ;;
  esac
}

manifest_field() {
  service="$1"
  field="$2"
  python3 - "$MANIFEST" "$service" "$field" <<'PY'
import json
import sys

manifest, service_name, field = sys.argv[1:]
data = json.load(open(manifest, encoding="utf-8"))
service = next(item for item in data["services"] if item["name"] == service_name)
if field.startswith("ociLabels."):
    value = service["ociLabels"][field[len("ociLabels."):]]
else:
    value = service
    for key in field.split("."):
        value = value[key]
print(value)
PY
}

verify_checkout() {
  repo="$1"
  service="$2"
  expected_commit="$3"

  if [ ! -d "$repo/.git" ]; then
    echo "$service checkout not found: $repo" >&2
    exit 1
  fi

  actual_commit="$(git -C "$repo" rev-parse HEAD)"
  if [ "$actual_commit" != "$expected_commit" ]; then
    echo "$service checkout HEAD mismatch" >&2
    echo "expected=$expected_commit" >&2
    echo "actual=$actual_commit" >&2
    echo "repo=$repo" >&2
    exit 1
  fi

  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
    echo "$service checkout has tracked local changes; refusing immutable image build" >&2
    git -C "$repo" status --short --untracked-files=no >&2
    exit 1
  fi
}

build_service() {
  service="$1"
  repo="$(repo_path "$service")"
  expected_commit="$(manifest_field "$service" sourceCommit)"
  image="$(manifest_field "$service" image)"
  source_url="$(manifest_field "$service" sourceUrl)"
  expected_revision="$(manifest_field "$service" ociLabels.org.opencontainers.image.revision)"
  expected_source="$(manifest_field "$service" ociLabels.org.opencontainers.image.source)"

  if [ "$expected_revision" != "$expected_commit" ]; then
    echo "$service manifest revision label does not match sourceCommit" >&2
    exit 1
  fi
  if [ "$expected_source" != "$source_url" ]; then
    echo "$service manifest source label does not match sourceUrl" >&2
    exit 1
  fi

  verify_checkout "$repo" "$service" "$expected_commit"

  echo "Packaging $service from $repo"
  (cd "$repo" && ./mvnw package)

  echo "Building $image"
  docker build \
    --build-arg "OCI_REVISION=$expected_commit" \
    --build-arg "OCI_SOURCE=$source_url" \
    -t "$image" \
    "$repo"

  actual_revision="$(docker image inspect "$image" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"
  actual_source="$(docker image inspect "$image" --format '{{ index .Config.Labels "org.opencontainers.image.source" }}')"

  if [ "$actual_revision" != "$expected_commit" ]; then
    echo "$image revision label mismatch expected=$expected_commit actual=$actual_revision" >&2
    exit 1
  fi
  if [ "$actual_source" != "$source_url" ]; then
    echo "$image source label mismatch expected=$source_url actual=$actual_source" >&2
    exit 1
  fi

  echo "$image provenance verified"
}

build_service loan-service
build_service governance-service
build_service audit-replay-service

python3 "$ROOT_DIR/scripts/verify-phase1-images.py"
