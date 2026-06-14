---
name: board-onboard-lite
description: Default orchestrator bootstrap — loads a compact role summary, key commands, and delegation cycle for routine sessions. For advanced scenarios (backend internals, hook installation, codex trust, live-deploy traps, detailed troubleshooting), use board-onboard.
---

# board-onboard-lite

Compact orchestrator bootstrap. Loads the essentials in minimal tokens.
For the full first-time onboard, use `board-onboard` instead.

## Your role: ORCHESTRATOR

Coordinate, do not implement. Delegate coding to headless `pi -p` workers.
Never hand-edit CHANGELOG.md (agents do it via their task spec).
Only exception: the user explicitly asks you to write code.

Key docs: `docs/ORCHESTRATOR.md` (full rules), `docs/delegation-policy.md` (model profiles).

## State model

- GitHub Issue labels = source of truth for STATUS.
- `.tasks/board.json` = local cache.
- `TODO.md` = read-only render.
- Claude built-in task list = ephemeral, discarded at round end.

Canonical status order:
`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

## Key commands

| Command | Effect |
|---------|--------|
| `board-pull --repo owner/repo` | Fetch issues → `.tasks/board.json` |
| `gh` | Manually write status back to GitHub labels when needed |
| `board-release --bump patch` | SemVer release helper |
| `board-plan` | Mirror ready tasks into task list |
| `board-run-ready` | Dispatch ready tasks to headless `pi` workers (cap: 2; parked 3×3 dashboard optional) |

## Delegation cycle (compact)

Scripts live in `skills/cmux-agent-workflows/scripts/`.

1. `wt-new.sh <branch> <dir>` → create worktree (off `origin/main`)
2. Write the task as `<worktree>/.task-spec.md` (never `/tmp` — external-dir prompts)
3. `worker-spawn.sh <worktree> --profile <name>` → launches a headless `pi -p`
   background worker, **prints its PID** (the handle). Raw model:
   `worker-spawn.sh <worktree> <provider/model> [label]`.
4. `worker-watch.sh --pid <PID> --out <worktree>/out.json --worktree <worktree>`
   → standby; watches PID + session heartbeat, prints `STATUS=DONE|CRASHED|KILLED_STALLED|KILLED_TIMEOUT`. No active polling, no panes.
5. `verify.sh` → hard gate (run yourself; never merge on self-report)
6. `pr-finish.sh` → merge (only with the user's explicit per-PR permission)

Kill a stuck worker with `kill <PID>`. The parked 3×3 cmux dashboard is optional, for watch/intervene only.

## On invocation

1. Detect repo (BOARD_REPO or ask).
2. If absent, run `board-pull`.
3. Run `board-status --json --ready-tasks 5` to get counts and ready tasks
   (compact JSON call instead of reading full `board.json`).
4. Run `board-plan` to mirror ready.
5. Report and await user confirmation before dispatching.
