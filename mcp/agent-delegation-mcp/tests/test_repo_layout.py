"""Lightweight checks for the skill-first repository layout (v1.2.0)."""
from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SKILL = REPO_ROOT / "skills" / "agent-delegation" / "SKILL.md"


def test_top_level_skill_exists() -> None:
    assert SKILL.is_file()


def test_skill_references_present() -> None:
    refs = REPO_ROOT / "skills" / "agent-delegation" / "references"
    for name in ("command-contract.md", "runtime-contract.md", "safety-rules.md", "examples.md"):
        assert (refs / name).is_file(), name


def test_skill_is_self_contained() -> None:
    text = SKILL.read_text()
    # lifecycle + the four runtimes + safety scope must be explained in the skill itself
    assert "spawn → uuid → status → read → send → kill" in text
    for runtime in ("shell", "claude", "codex", "pi"):
        assert runtime in text
    assert "no board" in text.lower()
    assert "cleanup_worktree" in text


def test_readme_is_skill_first() -> None:
    readme = (REPO_ROOT / "README.md").read_text()
    assert "skill-first" in readme.lower()
    assert "pip install -e mcp/agent-delegation-mcp" in readme  # backend install kept
    assert "SMOKE_OK" in readme  # smoke test kept


def test_compatibility_doc_covers_agents() -> None:
    compat = (REPO_ROOT / "docs" / "compatibility.md").read_text()
    for agent in ("Claude Code", "Codex", "Hermes", "Generic"):
        assert agent in compat, agent


def test_examples_for_each_agent() -> None:
    examples = REPO_ROOT / "examples"
    for name in (
        "skill-use-claude.md",
        "skill-use-codex.md",
        "skill-use-hermes.md",
        "skill-use-generic-agent.md",
    ):
        assert (examples / name).is_file(), name


def test_plugin_wrapper_has_no_unique_rules() -> None:
    wrapper = REPO_ROOT / "plugins" / "agent-delegation" / "skills" / "agent-delegation" / "SKILL.md"
    text = wrapper.read_text()
    # the wrapper must defer to the root skill, not carry its own rules
    assert "skills/agent-delegation/SKILL.md" in text
    assert "no unique delegation rules" in text.lower()


def test_changelog_has_v120() -> None:
    changelog = (REPO_ROOT / "CHANGELOG.md").read_text()
    assert "[1.2.0]" in changelog
