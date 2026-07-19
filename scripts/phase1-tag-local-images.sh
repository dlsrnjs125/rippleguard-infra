#!/usr/bin/env sh
set -eu

tag_if_missing() {
  source_image="$1"
  target_image="$2"
  expected_revision="$3"
  expected_source="$4"
  source_repo="${source_image%:*}"
  source_tag="${source_image##*:}"

  verify_labels() {
    image_ref="$1"
    actual_revision="$(docker image inspect "$image_ref" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' 2>/dev/null || true)"
    actual_source="$(docker image inspect "$image_ref" --format '{{ index .Config.Labels "org.opencontainers.image.source" }}' 2>/dev/null || true)"
    if [ "$actual_revision" != "$expected_revision" ] || [ "$actual_source" != "$expected_source" ]; then
      echo "OCI provenance label mismatch for $image_ref" >&2
      echo "revision expected=$expected_revision actual=$actual_revision" >&2
      echo "source expected=$expected_source actual=$actual_source" >&2
      return 1
    fi
  }

  if docker image inspect "$target_image" >/dev/null 2>&1; then
    verify_labels "$target_image"
    echo "$target_image already exists with verified provenance"
    return 0
  fi
  source_id="$(docker image ls --format '{{.Repository}} {{.Tag}} {{.ID}}' | awk -v repo="$source_repo" -v tag="$source_tag" '$1 == repo && $2 == tag {print $3; exit}')"
  if [ -z "$source_id" ]; then
    echo "Missing source image $source_image for $target_image" >&2
    exit 1
  fi
  if ! verify_labels "$source_id"; then
    echo "Refusing to retag $source_image: OCI provenance label mismatch" >&2
    exit 1
  fi
  docker tag "$source_id" "$target_image"
  echo "Tagged $target_image from $source_image"
}

tag_if_missing rippleguard-loan-service:phase1 rippleguard-loan-service:54ea344a6827 \
  54ea344a682723d61d9beedf4ade56ee48029c0d \
  https://github.com/dlsrnjs125/rippleguard-loan-service
tag_if_missing rippleguard-governance-service:local rippleguard-governance-service:29bafba34c47 \
  29bafba34c47e003fdefafa455924992993721cf \
  https://github.com/dlsrnjs125/rippleguard-governance-service
tag_if_missing rippleguard-audit-replay-service:local rippleguard-audit-replay-service:e7d9d9f8afb1 \
  e7d9d9f8afb106ecdec16235d79695d88c18b3cd \
  https://github.com/dlsrnjs125/rippleguard-audit-replay-service
