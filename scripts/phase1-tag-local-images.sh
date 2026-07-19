#!/usr/bin/env sh
set -eu

tag_if_missing() {
  source_image="$1"
  target_image="$2"
  source_repo="${source_image%:*}"
  source_tag="${source_image##*:}"

  if docker image inspect "$target_image" >/dev/null 2>&1; then
    echo "$target_image already exists"
    return 0
  fi
  source_id="$(docker image ls --format '{{.Repository}} {{.Tag}} {{.ID}}' | awk -v repo="$source_repo" -v tag="$source_tag" '$1 == repo && $2 == tag {print $3; exit}')"
  if [ -z "$source_id" ]; then
    echo "Missing source image $source_image for $target_image" >&2
    exit 1
  fi
  docker tag "$source_id" "$target_image"
  echo "Tagged $target_image from $source_image"
}

tag_if_missing rippleguard-loan-service:phase1 rippleguard-loan-service:54ea344a6827
tag_if_missing rippleguard-governance-service:local rippleguard-governance-service:29bafba34c47
tag_if_missing rippleguard-audit-replay-service:local rippleguard-audit-replay-service:e7d9d9f8afb1
