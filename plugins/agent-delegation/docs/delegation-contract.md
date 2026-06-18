# Delegation Contract

This document defines the naming, state, runtime, and lifecycle contract for the
delegation layer.

## Naming

- Every delegated agent has a uuid.
- The tmux session name is `adm-<uuid[:8]>`.
- The persisted record lives at `$ADM_STATE_DIR/agents/<uuid>.json`.
- The output log lives at `$ADM_STATE_DIR/logs/<uuid>.log`.
- If worktree mode is enabled, the worktree path is under
  `$ADM_STATE_DIR/worktrees/<uuid[:8]>`.

## State

- `ADM_STATE_DIR` defaults to `$HOME/.agent-delegation-mcp/state`.
- State files are owned by the delegation backend only.
- Agent record status transitions are:
  - `running`
  - `exited`
  - `killed`

## Runtime argv contract

- `shell` runs `bash -lc <prompt>`.
- `pi` runs `pi -p <prompt>` and appends `--provider`, `--model`, and
  `--thinking` when supplied.
- `codex` runs `codex exec <prompt>` and appends `--model` when supplied.
- `claude` runs `claude -p <prompt>` and appends `--model` when supplied.
- Unknown runtimes are rejected.

## Worktree rules

- Worktree mode requires the working directory to be a git repository.
- The backend creates a dedicated branch named `adm-<uuid[:8]>`.
- The delegated agent runs from the isolated worktree path.
- Local commits are allowed and expected.
- The human keeps merge control.

## Lifecycle

1. `spawn` creates the tmux session, writes the record, and returns the uuid.
2. `status <uuid>` reads the record and reports tmux liveness.
3. `read <uuid>` reads the captured log output.
4. `send <uuid>` forwards a message to the agent session.
5. `kill <uuid>` stops the session and marks the record killed.
6. `list` enumerates all known agent records.
