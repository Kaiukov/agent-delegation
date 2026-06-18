from __future__ import annotations

import shutil
import time
from pathlib import Path

import pytest

from agent_delegation_mcp.backend import AgentBackend


pytestmark = pytest.mark.skipif(shutil.which("pi") is None, reason="pi not installed")


def _poll_status(backend: AgentBackend, agent_uuid: str, deadline: float) -> dict:
    status = backend.get_agent_status(agent_uuid)
    while time.time() < deadline:
        if status.get("status") in {"done", "failed", "killed", "exited", "timeout"}:
            return status
        time.sleep(0.2)
        status = backend.get_agent_status(agent_uuid)
    return status


def test_pi_runtime_spawn_smoke(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")
    record = backend.spawn_agent(runtime="pi", prompt="echo smoke", cwd=str(tmp_path), timeout_sec=2)

    assert record["uuid"]
    assert record["session"]

    status = _poll_status(backend, record["uuid"], time.time() + 10)
    assert status["status"] in {"done", "failed", "exited", "timeout"}
