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


def test_shell_command_times_out(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="sleep 30",
        cwd=str(tmp_path),
        timeout_sec=1,
    )
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "timeout"
    assert "timeout" in (status.get("reason") or "").lower()


def test_fast_shell_command_does_not_timeout(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="echo hi",
        cwd=str(tmp_path),
        timeout_sec=5,
    )
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "done"
    assert "timeout" not in (status.get("reason") or "").lower()
