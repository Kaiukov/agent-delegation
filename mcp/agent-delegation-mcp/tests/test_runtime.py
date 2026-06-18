import pytest

from agent_delegation_mcp.runtime import build_command


def test_shell_command():
    argv = build_command("shell", "echo hi && echo done")
    assert argv == ["bash", "-lc", "echo hi && echo done"]
    assert argv[2] == "echo hi && echo done"


def test_pi_command_optional_flags():
    argv = build_command("pi", "do work", provider="anthropic", model="sonnet", thinking="on")
    assert argv == ["pi", "-p", "do work", "--provider", "anthropic", "--model", "sonnet", "--thinking", "on"]


def test_pi_command_without_optional_flags():
    argv = build_command("pi", "do work")
    assert argv == ["pi", "-p", "do work"]


def test_codex_command_optional_model():
    argv = build_command("codex", "do work", model="gpt-5")
    assert argv == ["codex", "exec", "do work", "--model", "gpt-5"]


def test_claude_command_optional_model():
    argv = build_command("claude", "do work", model="sonnet")
    assert argv == ["claude", "-p", "do work", "--model", "sonnet"]


def test_unknown_runtime():
    with pytest.raises(ValueError, match="unknown runtime: nope"):
        build_command("nope", "do work")


def test_prompt_stays_single_argv_element():
    prompt = "echo one && echo two"
    argv = build_command("codex", prompt)
    assert argv[2] == prompt
    assert len(argv) == 3
