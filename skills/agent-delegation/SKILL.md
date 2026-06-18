---
name: agent-delegation
description: Spawn, track, message, and kill local sub-agents over tmux via a small CLI or MCP server. Use when delegating an isolated unit of work to a shell, claude, codex, or pi runtime.
---

# agent-delegation

`agent-delegation` is a minimal, local tool for delegating a unit of work to a
sub-agent running in its own `tmux` session. This `SKILL.md` is the **single
source of truth** for how to use it. It is self-contained: you do not need the
Claude plugin, the MCP server, or any Claude-specific metadata to understand or
follow it. Any coding agent that can read this file and call a CLI or MCP tool
can use the system.

```text
Skill instructions (this file)
        ↓
agent-delegate CLI  /  MCP tools
        ↓
tmux session
        ↓
shell / claude / codex / pi
```

The skill is the portable layer. The CLI and the MCP server are interchangeable
**execution backends** for the same contract. The Claude plugin wrapper is
optional compatibility only.

## What it is

- A way to **spawn** a sub-agent into a detached `tmux` session and get back a
  `uuid`.
- A way to **track** that agent (`status`, `read`), **steer** it (`send`), and
  **stop** it (`kill`), plus **list** all known agents.
- Four runtimes: `shell`, `claude`, `codex`, `pi`.
- Optional **worktree mode** to isolate a run in its own git worktree.
- Optional **harnesses** (trusted local shell commands) that run after the main
  command and gate the final status.
- Optional **timeout** that terminates a run's whole process group.

## When to use it

- You want to hand an isolated, self-contained task to a sub-agent and keep
  working while it runs.
- You want the work isolated from your main checkout (use a worktree).
- You want a sub-agent to commit locally and leave the merge decision to a human.

## When NOT to use it

- You need remote, multi-machine, or scheduled execution — out of scope.
- You need a board, issue tracker, label routing, or PR/merge automation — out
  of scope (see Safety rules).
- The work is trivial enough to just do inline; delegation has overhead.

## Lifecycle

The only lifecycle is:

```text
spawn → uuid → status → read → send → kill / list
```

1. **spawn** — create the tmux session, launch the runtime, return a `uuid`.
2. **status `<uuid>`** — report the agent record + whether the session is alive.
3. **read `<uuid>`** — read the captured output log (last N lines).
4. **send `<uuid>` `<message>`** — type a message into a still-alive session.
5. **kill `<uuid>`** — stop the session and mark the record `killed`.
6. **list** — enumerate every known agent record.

Every operation after `spawn` is keyed by the `uuid`. Dispatch is **prompt-based
only** — there is no issue id, board id, task id, or label routing.

### Status values

| Status    | Meaning |
| --------- | ------- |
| `running` | tmux session alive, main command not finished. |
| `done`    | main command exited 0 (and all harnesses passed). |
| `failed`  | main command or a harness exited non-zero. |
| `timeout` | the process group exceeded `timeout_sec` and was terminated. |
| `killed`  | stopped by an explicit `kill`. |
| `exited`  | session ended without an exit marker (status could not be read). |

The record also carries `exit_code`, `completed_at`, `duration_sec`, and a
`reason` for terminal states.

## CLI usage

The CLI is `agent-delegate` (`plugins/agent-delegation/bin/agent-delegate`). It
prints JSON; `spawn` prints the `uuid` on the first line, then the full record.

```bash
agent-delegate spawn --runtime <shell|claude|codex|pi> --cwd <dir> \
  (--prompt '<text>' | --prompt-file <path>) \
  [--worktree] [--provider <p>] [--model <m>] [--thinking <t>] [--harness '<cmd>']...
agent-delegate status <uuid>
agent-delegate read   <uuid> [--lines <n>]
agent-delegate send   <uuid> "<message>"
agent-delegate kill   <uuid> [--reason "<text>"]
agent-delegate list
agent-delegate cleanup-worktree <uuid> [--force]
```

Minimal example:

```bash
uuid="$(agent-delegate spawn --runtime shell --cwd /tmp --prompt 'echo SMOKE_OK' | head -n1)"
agent-delegate status "$uuid"
agent-delegate read   "$uuid"
agent-delegate kill   "$uuid"
```

State lives under `ADM_STATE_DIR` (default `$HOME/.agent-delegation-mcp/state`).

## MCP usage

The MCP server (`agent-delegation-mcp`) exposes the same contract as tools:

| Tool                  | Lifecycle step | Key arguments |
| --------------------- | -------------- | ------------- |
| `spawn_agent`         | spawn  | `runtime`, `prompt`, `cwd`, `worktree`, `provider`, `model`, `thinking`, `harnesses`, `env`, `timeout_sec` |
| `get_agent_status`    | status | `uuid` |
| `read_agent_output`   | read   | `uuid`, `lines` |
| `send_agent_message`  | send   | `uuid`, `message` |
| `kill_agent`          | kill   | `uuid`, `reason` |
| `list_agents`         | list   | — |
| `cleanup_worktree`    | cleanup | `uuid`, `force` |

Register it in an MCP client (e.g. Claude Code `.mcp.json`):

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

CLI and MCP are equivalent — they share one backend and one state directory, so
an agent spawned via the CLI is visible to the MCP `list_agents`, and vice versa.

## Runtime choices: shell, claude, codex, pi

Pick the **narrowest** runtime that can do the job.

- **`shell`** — runs the prompt directly as `bash -lc <prompt>`. No external
  agent CLI required. Use for deterministic commands: builds, tests, file
  generation, git operations, smoke checks. This is the only runtime that
  executes the prompt as a literal command.
- **`claude`** — runs `claude -p <prompt>` (appends `--model` when given). Use
  when you want the Claude Code agent to reason and edit. Requires the `claude`
  CLI.
- **`codex`** — runs `codex exec <prompt>` (appends `--model` when given). Use
  for OpenAI Codex CLI delegation. Requires the `codex` CLI.
- **`pi`** — runs `pi -p <prompt>` (appends `--provider`, `--model`,
  `--thinking` when given). Use for the `pi` coding agent. Requires the `pi` CLI.

`provider`, `model`, and `thinking` are only meaningful for the runtimes that
accept them (see the table). An unknown runtime is rejected.

## Worktree mode

Set `--worktree` (CLI) or `worktree=true` (MCP) to isolate the run:

- The backend requires `cwd` to be inside a git repository, otherwise spawn
  fails.
- It creates a dedicated branch `adm-<uuid[:8]>` and a worktree under
  `$ADM_STATE_DIR/worktrees/<uuid[:8]>`, and runs the agent from there.
- The agent commits **locally** on that branch. The human owns the merge.
- Worktrees are **not** auto-removed — clean them up explicitly (see below).

Use a worktree whenever the delegated change should not touch your main checkout.

## Harnesses

Harnesses are extra shell commands that run **after** the main command, in
order. They are **trusted local shell commands only** — they are `eval`-ed in the
session's shell with no sandboxing, so only pass commands you would run yourself.

- Each harness is echoed before it runs.
- If any harness exits non-zero, the agent's final status becomes `failed` and
  the failing harness is shown in the output.
- Typical use: post-run acceptance gates (`npm test`, `bash -n script.sh`, a
  `grep` that must be empty).

## Timeout

`timeout_sec` defaults to `0`, which **disables** the timeout. When
`timeout_sec > 0`:

- The backend runs the main command in its own process group.
- If the run is still alive after `timeout_sec`, it sends `TERM` to the whole
  group, waits ~2s, then `KILL`.
- The final status becomes `timeout`, with `reason` set to `timeout after <n>s`.

Use a timeout to bound runaway agents. (The MCP `spawn_agent` exposes
`timeout_sec`; the CLI launches without a timeout by default.)

## cleanup_worktree

Worktrees persist after a run so you can inspect commits. Remove one explicitly
when done:

```bash
agent-delegate cleanup-worktree <uuid> [--force]
```

or the `cleanup_worktree` MCP tool. It runs `git worktree remove` (never a blind
`rm -rf`). It returns `{cleaned:false, reason:"no worktree"}` for non-worktree
agents and `{cleaned:false, reason:"worktree path missing"}` if already gone. Use
`--force` only when the worktree has changes you intend to discard.

## Safety rules

- **No board, no GitHub sync, no PR automation.** This tool does not read or
  write issues, labels, projects, or boards, and never opens, reviews, or merges
  pull requests. Dispatch is prompt-based only.
- **Agents commit locally; humans merge.** Worktree agents may commit on their
  branch. Pushing and merging are explicit human actions, not automated here.
- **Harnesses and prompts are trusted local input.** There is no sandbox. Only
  pass commands you would run yourself.
- **Local only.** No remote, multi-machine, scheduled, or queued execution.
- Keep prompts explicit and short; prefer the minimal runtime and the minimal
  backend that can do the job.

## References

- `references/command-contract.md` — exact CLI/MCP surface and JSON shapes.
- `references/runtime-contract.md` — argv each runtime builds; naming and state.
- `references/safety-rules.md` — the binding safety/scope rules in full.
- `references/examples.md` — copy-paste lifecycle examples per runtime.
