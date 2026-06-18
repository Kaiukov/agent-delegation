# agent-delegation

Minimal MCP + CLI sub-agent delegation over `tmux`.

## What it is

`agent-delegation` keeps the control surface intentionally small:

- lifecycle: `spawn → uuid → status → read → send → kill/list`
- runtimes: `shell`, `pi`, `codex`, `claude`
- `shell` is the direct command runner
- the other runtimes generate a command line for the launched session
- worktree mode isolates a run in its own git worktree

## Requirements

- Python 3.11+
- `tmux`
- optional: `pi`, `codex`, and `claude` CLIs for those runtimes

## Install

```bash
pip install -e mcp/agent-delegation-mcp
pip install -e "mcp/agent-delegation-mcp[dev]"
```

## MCP config

Claude Code `.mcp.json` example:

```json
{
  "mcpServers": {
    "agent-delegation-mcp": {
      "command": "~/.agent-delegation-mcp/venv/bin/agent-delegation-mcp",
      "env": {
        "ADM_STATE_DIR": "~/.agent-delegation-mcp/state"
      }
    }
  }
}
```

## CLI usage

```bash
agent-delegate spawn --runtime shell --cwd /tmp --prompt 'echo hello'
agent-delegate status <uuid>
agent-delegate read <uuid>
agent-delegate send <uuid> "follow up"
agent-delegate kill <uuid>
agent-delegate list
agent-delegate cleanup-worktree <uuid>
```

## Shell smoke test

```bash
uuid="$(
  agent-delegate spawn \
    --runtime shell \
    --cwd /tmp \
    --prompt 'echo SMOKE_OK' | head -n1
)"

agent-delegate status "$uuid"
agent-delegate read "$uuid"
agent-delegate kill "$uuid"
```

## Optional real runtime tests

`pytest` includes optional `claude`, `codex`, and `pi` integration tests that skip
automatically when the matching CLI is not installed.

## Status lifecycle

| Status | Meaning |
| --- | --- |
| `running` | The tmux session is alive and the main command has not finished. |
| `done` | The main command completed successfully. |
| `failed` | The main command or a harness failed. |
| `timeout` | The process group exceeded `timeout_sec` and was terminated. |
| `killed` | The session was stopped explicitly. |
| `exited` | The tmux session ended without a normal agent completion record. |

Related fields:

- `exit_code` records the main command exit status when available.
- `completed_at` stores the completion timestamp.
- `duration_sec` stores the elapsed runtime in seconds.
- `reason` explains why a terminal status was chosen.

## Harnesses

Harnesses run after the main command. Any harness failure marks the agent as
`failed` and the failing harness is shown in the output. Harnesses are trusted
local shell commands only.

## Timeout behavior

`timeout_sec` defaults to `0`, which disables timeouts. When `timeout_sec > 0`,
the backend terminates the whole process group with `TERM` first and then `KILL`
if needed, and the final status becomes `timeout`.

## Worktree mode

`worktree=True` creates a unique git worktree for the agent run. It fails if the
current working directory is not a git repository. Worktrees are not auto-cleaned;
use `cleanup_worktree` or `agent-delegate cleanup-worktree` to remove them. Cleanup
uses `git worktree remove`, never a blind `rm -rf`.

## send_agent_message

`send_agent_message` only works while the tmux session is still alive. That is
mainly useful for interactive `claude`, `codex`, and `pi` runs. If the session is
gone, it returns `{sent:false, reason:"session not found"}`. `shell` runs usually
exit after the command finishes.

## Known limitations

- Local-only delegation, with no remote or multi-machine coordination.
- No scheduler or remote issue workflow.
- `shell` is the only runtime that executes the prompt directly.
- `pi`, `codex`, and `claude` require their CLIs to be installed locally.

## Security notes

- Harnesses and prompts are trusted local shell input.
- The repository does not sandbox shell execution.
- Keep the workflow on your machine; do not expect remote execution support.
