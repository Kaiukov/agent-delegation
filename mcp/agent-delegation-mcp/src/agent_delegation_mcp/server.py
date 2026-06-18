from __future__ import annotations

import os
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .backend import AgentBackend


mcp = FastMCP("agent-delegation-mcp")
_state_dir = Path(os.environ.get("ADM_STATE_DIR", Path.home() / ".agent-delegation-mcp"))
_backend = AgentBackend(_state_dir)


@mcp.tool()
def spawn_agent(
    runtime: str,
    prompt: str,
    cwd: str,
    worktree: bool = False,
    provider: str | None = None,
    model: str | None = None,
    thinking: str | None = None,
    harnesses: list[str] | None = None,
    env: dict[str, str] | None = None,
    timeout_sec: int = 30,
) -> dict:
    return _backend.spawn_agent(
        runtime,
        prompt,
        cwd,
        worktree=worktree,
        provider=provider,
        model=model,
        thinking=thinking,
        harnesses=harnesses,
        env=env,
        timeout_sec=timeout_sec,
    )


@mcp.tool()
def get_agent_status(uuid: str) -> dict:
    return _backend.get_agent_status(uuid)


@mcp.tool()
def read_agent_output(uuid: str, lines: int = 80) -> dict:
    return _backend.read_agent_output(uuid, lines=lines)


@mcp.tool()
def send_agent_message(uuid: str, message: str) -> dict:
    return _backend.send_agent_message(uuid, message)


@mcp.tool()
def list_agents() -> dict:
    return _backend.list_agents()


@mcp.tool()
def kill_agent(uuid: str, reason: str | None = None) -> dict:
    return _backend.kill_agent(uuid, reason=reason)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
