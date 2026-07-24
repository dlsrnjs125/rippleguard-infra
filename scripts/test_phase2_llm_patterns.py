#!/usr/bin/env python3
"""Unit checks for Phase 2 E2E helper pattern matching."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "phase2_e2e.py"
SPEC = importlib.util.spec_from_file_location("phase2_e2e", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
phase2_e2e = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(phase2_e2e)


class Phase2LlmPatternTest(unittest.TestCase):
    def test_readme_absence_statement_passes(self) -> None:
        text = "It does not use Local LLM/Ollama."
        self.assertEqual(phase2_e2e.forbidden_config_hits(text), [])
        self.assertEqual(phase2_e2e.forbidden_runtime_hits(text), [])

    def test_import_openai_fails(self) -> None:
        text = "import openai\n"
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(hits, ["import openai"])

    def test_pyproject_dependency_fails(self) -> None:
        text = 'openai = "^1.0.0"\n'
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(hits, ['openai = "^1.0.0"'])

    def test_pep621_dependency_array_fails(self) -> None:
        text = '  "openai>=1.0,<2",\n'
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(hits, ['  "openai>=1.0,<2",'])

    def test_direct_url_dependency_fails(self) -> None:
        text = '"openai @ https://example.com/openai.whl"\n"langchain-openai @ git+https://github.com/example/pkg.git"\n'
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(
            hits,
            [
                '"openai @ https://example.com/openai.whl"',
                '"langchain-openai @ git+https://github.com/example/pkg.git"',
            ],
        )

    def test_langchain_provider_imports_fail(self) -> None:
        text = "import langchain_core\nfrom langchain_openai import ChatOpenAI\n"
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(hits, ["import langchain_core", "from langchain_openai import ChatOpenAI"])

    def test_remote_provider_dependencies_fail(self) -> None:
        text = '"google-generativeai>=0.8"\n"mistralai>=1"\n"azure-ai-inference>=1"\n'
        hits = phase2_e2e.pattern_hits(text, phase2_e2e.repository_llm_patterns())
        self.assertEqual(hits, ['"google-generativeai>=0.8"', '"mistralai>=1"', '"azure-ai-inference>=1"'])

    def test_compose_openai_env_fails(self) -> None:
        text = "OPENAI_API_KEY=${OPENAI_API_KEY}\n"
        hits = phase2_e2e.forbidden_config_hits(text)
        self.assertEqual(hits, ["OPENAI_API_KEY=${OPENAI_API_KEY}"])

    def test_azure_openai_env_fails(self) -> None:
        text = "AZURE_OPENAI_ENDPOINT=https://example.openai.azure.com\n"
        hits = phase2_e2e.forbidden_config_hits(text)
        self.assertEqual(hits, ["AZURE_OPENAI_ENDPOINT=https://example.openai.azure.com"])

    def test_remote_provider_env_fails(self) -> None:
        text = "COHERE_API_KEY=secret\nBEDROCK_MODEL_ID=anthropic.claude\n"
        hits = phase2_e2e.forbidden_config_hits(text)
        self.assertEqual(hits, ["COHERE_API_KEY=secret", "BEDROCK_MODEL_ID=anthropic.claude"])

    def test_disabled_log_statement_passes(self) -> None:
        text = "local LLM disabled; integration not configured\n"
        self.assertEqual(phase2_e2e.forbidden_runtime_hits(text), [])


class Phase2TimestampParserTest(unittest.TestCase):
    def test_nanosecond_z_timestamp_truncates_to_microseconds(self) -> None:
        self.assertEqual(
            phase2_e2e.instant_text("2026-07-24T04:35:31.961738875Z"),
            "2026-07-24T04:35:31.961738Z",
        )

    def test_positive_offset_timestamp_normalizes_to_utc(self) -> None:
        self.assertEqual(
            phase2_e2e.instant_text("2026-07-24 13:35:31.961738+09:00"),
            "2026-07-24T04:35:31.961738Z",
        )

    def test_fractionless_z_timestamp_uses_microsecond_precision(self) -> None:
        self.assertEqual(
            phase2_e2e.instant_text("2026-07-24T04:35:31Z"),
            "2026-07-24T04:35:31.000000Z",
        )

    def test_negative_offset_timestamp_normalizes_to_utc(self) -> None:
        self.assertEqual(
            phase2_e2e.instant_text("2026-07-23T23:35:31.961738-05:00"),
            "2026-07-24T04:35:31.961738Z",
        )

    def test_naive_timestamp_is_treated_as_utc(self) -> None:
        self.assertEqual(
            phase2_e2e.instant_text("2026-07-24T04:35:31.961738"),
            "2026-07-24T04:35:31.961738Z",
        )


if __name__ == "__main__":
    unittest.main()
