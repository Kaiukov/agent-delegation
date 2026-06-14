# Agent Completion Notifications

**Status:** HEADLESS — `worker-watch.sh` is the primary completion checker for `pi` workers.

## cmux primitives

| Primitive | Carries event? | Notes |
|-----------|---------------|-------|
| `cmux notify` | Yes — direct notification to the orchestrator pane. | Optional explicit signal; can carry structured payload (issue#, branch, success/failure). |
| `cmux hooks <agent> install --feed` | Yes — hook feed from agent pane. | Useful for richer lifecycle events (start, progress, done, error). |
| `cmux set-status` / `cmux set-progress` | Partial — updates cmux pane status bar. | Visible to orchestrator but not a dedicated event. |

## Default completion model

A headless worker is considered complete when all three are true:

1. worker process exits successfully,
2. `CTB-DONE` appears in the worker output,
3. the worker's branch commit exists.

Use `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` to enforce that contract.

## Backend matrix

| Backend | Setup | Completion / notification path | Feed path |
|---|---|---|---|
| Claude Code | Wrapper-managed; enabled through cmux settings | `cmux notify --title "CTB-DONE" --body "..." --surface <surface>` can be used as an explicit signal | Wrapper-injected `PermissionRequest` only; use `cmux feed tui` to approve from the sidebar when a request appears |
| Pi | `pi` binary on PATH | `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` watches the headless worker and its `CTB-DONE` output | `cmux hooks pi install` — Pi notifications surface through the Feed / notification flow |

Practical rule:

- Use `cmux notify` for one-way completion or alert messages.
- Use `cmux feed tui` when the agent is blocked on permission, plan-mode, or a question.
- Use `worker-watch.sh` when you need the canonical headless completion check.
