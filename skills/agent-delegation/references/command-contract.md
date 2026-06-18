# Command contract

The CLI (`agent-delegate`) and the MCP server (`agent-delegation-mcp`) expose the
same operations over one shared backend and one shared state directory.

## CLI

```text
agent-delegate spawn --runtime <runtime> --cwd <dir>
                     (--prompt <text> | --prompt-file <path>)
                     [--worktree]
                     [--provider <p>] [--model <m>] [--thinking <t>]
                     [--harness <cmd>]...
agent-delegate status <uuid>
agent-delegate read   <uuid> [--lines <n>]
agent-delegate send   <uuid> <message>
agent-delegate kill   <uuid> [--reason <text>]
agent-delegate list
agent-delegate cleanup-worktree <uuid> [--force]
```

- `spawn` requires exactly one of `--prompt` / `--prompt-file`.
- `spawn` prints the `uuid` on line 1, then the full record as pretty JSON.
- All other commands print pretty JSON.
- State dir resolves from `ADM_STATE_DIR`, default
  `$HOME/.agent-delegation-mcp/state`.

## MCP tools

| Tool | Arguments | Returns |
| ---- | --------- | ------- |
| `spawn_agent` | `runtime, prompt, cwd, worktree=false, provider=None, model=None, thinking=None, harnesses=None, env=None, timeout_sec=0` | agent record dict |
| `get_agent_status` | `uuid` | record + `alive: bool` |
| `read_agent_output` | `uuid, lines=80` | `{uuid, output}` |
| `send_agent_message` | `uuid, message` | `{uuid, sent, reason?}` |
| `kill_agent` | `uuid, reason=None` | finalized record |
| `list_agents` | — | `{agents: [...]}` |
| `cleanup_worktree` | `uuid, force=false` | `{uuid, cleaned, reason?/worktree?}` |

## Agent record shape

```json
{
  "uuid": "…hex…",
  "runtime": "shell",
  "prompt": "…",
  "cwd": "/path",
  "session": "adm-<uuid[:8]>",
  "log_file": "$ADM_STATE_DIR/logs/<uuid>.log",
  "worktree": null,
  "status": "running",
  "created_at": 0.0,
  "completed_at": null,
  "duration_sec": null,
  "pid": null,
  "command": "bash -lc '…'",
  "exit_code": null,
  "reason": null
}
```

## Notes

- `send_agent_message` only works while the tmux session is alive; otherwise it
  returns `{sent:false, reason:"session not found"}`. `shell` runs usually exit
  once the command finishes, so `send` is mainly for interactive
  `claude`/`codex`/`pi` runs.
- The CLI does not expose `--timeout` or `--env`; use the MCP `spawn_agent`
  arguments (`timeout_sec`, `env`) when you need them.
