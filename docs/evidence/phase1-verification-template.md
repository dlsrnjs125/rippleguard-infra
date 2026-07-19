# Phase 1 Verification Evidence Template

Actual command results are written to `artifacts/phase1/<run-id>/` and are not committed.

Each run should capture:

- command
- timestamp
- infra commit
- contracts commit
- service commits
- image references and provenance verification result
- migration version, description, script, and checksum as reported by Flyway
- E2E pass/fail
- duplicate pass/fail
- recovery pass/fail
- out-of-order timeline pass/fail
- privacy validation pass/fail
- troubleshooting notes without raw logs or sensitive payloads
