#!/usr/bin/env sh
set -eu

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${MINIO_DOCUMENT_BUCKET:=rippleguard-documents}"

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc ls "local/$MINIO_DOCUMENT_BUCKET" >/dev/null
echo "MinIO bucket verified: $MINIO_DOCUMENT_BUCKET"
