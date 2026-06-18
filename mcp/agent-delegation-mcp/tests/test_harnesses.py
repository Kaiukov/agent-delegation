from __future__ import annotations

import shutil
import time
from pathlib import Path

import pytest

from agent_delegation_mcp.backend import AgentBackend


pytestmark = pytest.mark.skipif(shutil.which("tmux") is None, reason="needs tmux")


def _poll_status(backend: AgentBackend, agent_uuid: str, deadline: float) -> dict:
    status = backend.get_agent_status(agent_uuid)
    while time.time() < deadline:
        if status.get("status") in {"done", "failed", "killed", "exited", "timeout"}:
            return status
        time.sleep(0.2)
        status = backend.get_agent_status(agent_uuid)
    return status


def test_shell_command_with_passing_harnesses_becomes_done(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="echo ok",
        cwd=str(tmp_path),
        harnesses=["true"],
    )
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "done"
    assert status["exit_code"] == 0


def test_shell_command_with_failing_harness_becomes_failed(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="echo ok",
        cwd=str(tmp_path),
        harnesses=["false"],
    )
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "failed"
    assert status["exit_code"] != 0


def test_failed_shell_command_stays_failed_with_passing_harness(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="exit 5",
        cwd=str(tmp_path),
        harnesses=["true"],
    )
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "failed"
    assert status["exit_code"] == 5
