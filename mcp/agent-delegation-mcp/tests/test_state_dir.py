from __future__ import annotations

import importlib
from pathlib import Path

def test_server_and_cli_share_default_state_dir(monkeypatch):
    monkeypatch.delenv("ADM_STATE_DIR", raising=False)

    server = importlib.import_module("agent_delegation_mcp.server")
    server = importlib.reload(server)
    expected = Path.home() / ".agent-delegation-mcp" / "state"

    assert server._state_dir == expected

    bin_path = Path(__file__).resolve().parents[3] / "plugins/agent-delegation/bin/agent-delegate"
    assert 'ADM_STATE_DIR:-$HOME/.agent-delegation-mcp/state' in bin_path.read_text()
