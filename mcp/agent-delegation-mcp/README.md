# agent-delegation-mcp

Minimal MCP server for delegating work to sub-agents running in `tmux`.

## What it is

This package exposes a small MCP surface for spawning, tracking, messaging, and killing delegated agents.
It is intentionally narrow: no issue tracker sync, no scheduler, and no PR automation.

## Requirements

- Python 3.11+
- `tmux`

## Install

```bash
pip install -e .
```

## Run server

```bash
agent-delegation-mcp
```

## Claude Code MCP config

```json
{
  "mcpServers": {
    "agent-delegation-mcp": {
      "command": "agent-delegation-mcp"
    }
  }
}
```

## Shell runtime smoke test

```bash
python - <<'PY'
from pathlib import Path
from agent_delegation_mcp.backend import AgentBackend

backend = AgentBackend(Path("./.adm-state"))
record = backend.spawn_agent(
    runtime="shell",
    prompt="echo hi && sleep 1 && echo done",
    cwd=str(Path.cwd()),
)
print(record["uuid"])
print(backend.get_agent_status(record["uuid"]))
print(backend.read_agent_output(record["uuid"]))
print(backend.kill_agent(record["uuid"]))
PY
```

## Known limitations

- StdIO only.
- `shell` is the first-class runtime.
- `pi`, `codex`, and `claude` only generate command argv; they are not executed in tests.

## Next steps

- Add richer status inspection if you need process metadata beyond tmux session liveness.
- Add higher-level orchestration only if the minimal lifecycle stops being enough.
