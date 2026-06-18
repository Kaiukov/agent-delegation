# agent-delegation

[![skills.sh](https://skills.sh/b/Kaiukov/agent-delegation)](https://skills.sh/Kaiukov/agent-delegation)

Minimal, local sub-agent delegation over `tmux`.

**agent-delegation is now skill-first.** The portable layer is the skill at
[`skills/agent-delegation/SKILL.md`](skills/agent-delegation/SKILL.md) — it is the
single source of truth and is usable by any coding agent, with or without Claude.
The CLI (`agent-delegate`) and the MCP server (`agent-delegation-mcp`) are local
execution backends. The Claude plugin wrapper under `plugins/agent-delegation/`
is optional compatibility.

```text
skills/agent-delegation/SKILL.md   ← portable instructions (source of truth)
        ↓
agent-delegate CLI  /  MCP tools   ← local execution backends
        ↓
tmux session
        ↓
shell / claude / codex / pi
```

## What it is

- lifecycle: `spawn → uuid → status → read → send → kill/list`
- runtimes: `shell`, `claude`, `codex`, `pi`
- `shell` runs the prompt directly; the others build a command line for the
  matching agent CLI
- optional worktree mode isolates a run in its own git worktree
- optional harnesses (trusted local shell commands) gate the final status
- optional timeout terminates a run's process group

## Requirements

- Python 3.11+
- `tmux`
- optional: `claude`, `codex`, and `pi` CLIs for those runtimes

## Install as a skill

```bash
npx skills add Kaiukov/agent-delegation
```

Installing the skill does **not** install the local Python backend. The skill is
the portable instruction layer only.

## Install the backend

```bash
pip install -e mcp/agent-delegation-mcp
pip install -e "mcp/agent-delegation-mcp[dev]"   # for tests
```

## Use as a skill (recommended)

The skill is portable. Point your agent at it:

- **Claude Code:** symlink it in —
  `ln -s "$PWD/skills/agent-delegation" ~/.claude/skills/agent-delegation`
- **Codex CLI:** reference `skills/agent-delegation/SKILL.md` in your project /
  prompt context.
- **Hermes / generic agents:** load `SKILL.md` as instructions and let the agent
  call the CLI or MCP tools.

See [`docs/compatibility.md`](docs/compatibility.md) and `examples/skill-use-*.md`
for per-agent walkthroughs.

## Use the CLI

```bash
agent-delegate spawn --runtime shell --cwd /tmp --prompt 'echo hello'
agent-delegate status <uuid>
agent-delegate read <uuid>
agent-delegate send <uuid> "follow up"
agent-delegate kill <uuid>
agent-delegate list
agent-delegate cleanup-worktree <uuid>
```

## Use the MCP server

Register it in an MCP client (Claude Code `.mcp.json` example):

```json
{
  "mcpServers": {
    "agent-delegation": {
      "command": "~/.agent-delegation-mcp/venv/bin/agent-delegation-mcp",
      "env": { "ADM_STATE_DIR": "~/.agent-delegation-mcp/state" }
    }
  }
}
```

Tools: `spawn_agent`, `get_agent_status`, `read_agent_output`,
`send_agent_message`, `kill_agent`, `list_agents`, `cleanup_worktree`. CLI and MCP
share one backend and state directory.

## Compatibility

| Agent         | Load the skill | Execute |
| ------------- | -------------- | ------- |
| Claude Code   | symlink into `.claude/skills/` | MCP tools or CLI |
| Codex CLI     | reference `SKILL.md` in context | CLI |
| Hermes        | load `SKILL.md` as instructions | CLI or MCP |
| Generic agent | read `SKILL.md` before delegating | CLI or MCP |

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

`pytest` includes optional `claude`, `codex`, and `pi` integration tests that skip
automatically when the matching CLI is not installed.

## Status lifecycle

| Status | Meaning |
| --- | --- |
| `running` | The tmux session is alive and the main command has not finished. |
| `done` | The main command completed successfully. |
| `failed` | The main command or a harness failed. |
| `timeout` | The process group exceeded `timeout_sec` and was terminated. |
| `killed` | The agent was stopped by an explicit kill. |
| `exited` | The session ended without an exit marker. |

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

## Scope: no board, no GitHub sync, no PR automation

This is a local delegation tool only. It does **not** include a board, GitHub
issue sync, labels, or PR/merge automation. Dispatch is prompt-based; agents
commit locally and humans own the merge.

## Known limitations

- Local-only delegation, with no remote or multi-machine coordination.
- No scheduler or remote issue workflow.
- `shell` is the only runtime that executes the prompt directly.
- `claude`, `codex`, and `pi` require their CLIs to be installed locally.

## Security notes

- Harnesses and prompts are trusted local shell input.
- The repository does not sandbox shell execution.
- Keep the workflow on your machine; do not expect remote execution support.
