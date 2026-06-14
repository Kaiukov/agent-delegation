# cmux Cheat Sheet — Notify / Feed / Events

## Primitives

| Command | Flags | Purpose |
|---|---|---|
| `cmux notify` | `--title <t> [--subtitle <s>] [--body <b>] [--surface\|--workspace\|--window <ref>]` | Send a notification to a pane or workspace; appears in the cmux UI and event stream |
| `cmux hooks <agent> install` | `cmux hooks opencode install [--feed] [--project]`, `cmux hooks codex install` | Install lifecycle (`cmux-session.js`) and feed (`cmux-feed.js`) hook plugins for the given agent backend. Idempotent; run once per machine |
| `cmux feed` | `cmux feed tui [--opentui\|--legacy]`, `cmux feed clear [-y]` | Interactive feed TUI for approvals/questions. No programmatic output — use `cmux events --category feed` to consume in scripts |
| `cmux events` | `--category agent\|notification\|feed [--no-heartbeat] [--cursor-file <path>]` | Stream NDJSON events from cmux. Key categories: `agent` (lifecycle), `notification` (notify payloads), `feed` (approvals) |

### Other useful primitives

| Command | Purpose |
|---|---|
| `cmux list-notifications` | List queued notifications |
| `cmux dismiss-notification --id <uuid> \| --all-read` | Dismiss notifications |
| `cmux mark-notification-read --id <uuid> \| --workspace \| --all` | Mark notifications as read |
| `cmux set-status <key> <value> [--workspace] [--surface]` | Update surface status bar |
| `cmux set-progress <0.0-1.0> [--label <t>] [--workspace]` | Workspace progress bar |
| `cmux wait-for [-S] <name> [--timeout <s>]` | tmux-compat named sync barrier |
| `cmux log [--level] [--source] <msg>` | Emit structured log entry |

## Per-Backend Setup

| Backend | Install | Completion Signal |
|---|---|---|
| Claude Code | Wrapper-managed; enabled via cmux settings | `cmux notify --title CTB-DONE --body "task=… surface=… status=… branch=…" --surface <ref>` |
| Codex | `cmux hooks codex install` | `CTB-DONE` notify (explicit) or `cmux events --category notification` (stream) |
| OpenCode | `cmux hooks opencode install` (add `--feed` for approvals) | `agent.hook.idle` lifecycle (automatic, via `cmux-session.js`) or `CTB-DONE` notify (explicit) |

## Agent Completion Signal

```bash
cmux notify --title "CTB-DONE" \
  --body "task=82 surface=surface:172 status=success branch=docs/82-cmux-cheat-sheet" \
  --surface "surface:172"
```

The worker's final step is to emit `CTB-DONE` in its final output (structured payload optional).

## Orchestrator Wait Flow

For headless `pi` workers, dispatch with `worker-spawn.sh` and then wait with `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>`. The watcher follows the worker PID plus the session heartbeat; no screen polling or dashboard typing is needed.

- `worker-watch.sh` is the canonical standby path for the default flow.
- If the worker is stuck, stop it with `kill <PID>`.

## See Also

- [Orchestrator Rules](ORCHESTRATOR.md) — delegation cycle & standby-after-dispatch rule
- [cmux-agent-workflows](skills/cmux-agent-workflows/SKILL.md) — headless worker launch + watch helpers
- [Codex Port](codex-port.md) — backend routing & completion loop
