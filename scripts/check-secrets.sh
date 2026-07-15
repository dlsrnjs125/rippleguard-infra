#!/usr/bin/env sh
set -eu

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo ".env must not be tracked" >&2
  exit 1
fi

if git grep -nE 'AKIA[0-9A-Z]{16}|-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----' -- . ':!scripts/check-secrets.sh'; then
  echo "Potential committed secret detected" >&2
  exit 1
fi

echo "Secret pattern check passed"
