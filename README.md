# agent-delegation

Minimal sub-agent delegation over `tmux`, exposed through both an MCP server and a small shell CLI.

## What it is

`agent-delegation` keeps the control surface intentionally small:

- `spawn → uuid → status → read → send → kill/list`
- prompt-based dispatch only
- `shell` is first-class
- `pi`, `codex`, and `claude` are command-generation runtimes
- worktree mode isolates an agent in its own git worktree
- agents commit locally; the human owns merge, never push or PR automation

## Requirements

- Python 3.11+
- `tmux`

## Install

```bash
pip install -e mcp/agent-delegation-mcp
```

## MCP server

```bash
agent-delegation-mcp
```

Claude Code MCP config:

```json
{
  "mcpServers": {
    "agent-delegation-mcp": {
      "command": "agent-delegation-mcp"
    }
  }
}
```

## Claude Code plugin

The plugin metadata lives in `.claude-plugin/marketplace.json` and points at `./plugins/agent-delegation`.

## Bin CLI

```bash
plugins/agent-delegation/bin/agent-delegate spawn \
  --runtime shell \
  --cwd /tmp \
  --prompt 'echo hello'

plugins/agent-delegation/bin/agent-delegate status <uuid>
plugins/agent-delegation/bin/agent-delegate read <uuid>
plugins/agent-delegation/bin/agent-delegate send <uuid> "follow up"
plugins/agent-delegation/bin/agent-delegate kill <uuid>
plugins/agent-delegation/bin/agent-delegate list
```

## Shell smoke test

```bash
uuid="$(
  plugins/agent-delegation/bin/agent-delegate spawn \
    --runtime shell \
    --cwd /tmp \
    --prompt 'echo SMOKE_OK && sleep 1' | head -n1
)"

plugins/agent-delegation/bin/agent-delegate status "$uuid"
plugins/agent-delegation/bin/agent-delegate read "$uuid"
plugins/agent-delegation/bin/agent-delegate list
plugins/agent-delegation/bin/agent-delegate kill "$uuid"
```

## Lifecycle

1. `spawn` creates a delegated agent and returns a uuid.
2. `status <uuid>` reports the current record and tmux liveness.
3. `read <uuid>` shows captured output.
4. `send <uuid> "<message>"` sends follow-up input.
5. `kill <uuid>` stops the session.
6. `list` shows every known agent record.

## Limitations

- This repo does not implement label-driven flows or automated terminal UI integration.
- The MCP backend and CLI only coordinate sub-agents.
- `shell` is for direct command execution; the other runtimes only build argv.
