from __future__ import annotations

import shutil
import time
from pathlib import Path

import pytest

from agent_delegation_mcp.backend import AgentBackend


pytestmark = pytest.mark.skipif(shutil.which("tmux") is None, reason="needs tmux")


def test_shell_runtime_full_lifecycle(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(
        runtime="shell",
        prompt="echo hi && sleep 1 && echo done",
        cwd=str(tmp_path),
    )
    agent_uuid = record["uuid"]
    assert agent_uuid

    status = backend.get_agent_status(agent_uuid)
    assert status["uuid"] == agent_uuid
    assert "alive" in status

    output = ""
    deadline = time.time() + 5
    while time.time() < deadline:
        output = backend.read_agent_output(agent_uuid)["output"]
        if "hi" in output:
            break
        time.sleep(0.2)
    assert "hi" in output

    agents = backend.list_agents()["agents"]
    assert any(agent["uuid"] == agent_uuid for agent in agents)

    killed = backend.kill_agent(agent_uuid, reason="test complete")
    assert killed["status"] == "killed"
    assert killed["reason"] == "test complete"

    status_after_kill = backend.get_agent_status(agent_uuid)
    assert status_after_kill["uuid"] == agent_uuid
