# Runtime contract

## argv each runtime builds

| Runtime | Command | Optional flags appended |
| ------- | ------- | ----------------------- |
| `shell` | `bash -lc <prompt>` | — (runs the prompt directly) |
| `pi`    | `pi -p <prompt>` | `--provider`, `--model`, `--thinking` |
| `codex` | `codex exec <prompt>` | `--model` |
| `claude`| `claude -p <prompt>` | `--model` |

Any other runtime value is rejected with `unknown runtime: <name>`.

`provider`/`model`/`thinking` are passed through only when supplied and only for
the runtimes that accept them. `shell` ignores all three.

## Naming and state

- `ADM_STATE_DIR` defaults to `$HOME/.agent-delegation-mcp/state`.
- tmux session name: `adm-<uuid[:8]>`.
- record:   `$ADM_STATE_DIR/agents/<uuid>.json`
- log:      `$ADM_STATE_DIR/logs/<uuid>.log`
- launcher: `$ADM_STATE_DIR/launchers/<uuid>.sh`
- exit/timeout markers: `$ADM_STATE_DIR/exits/<uuid>.exit` / `.timeout`
- worktree (if enabled): `$ADM_STATE_DIR/worktrees/<uuid[:8]>`, branch
  `adm-<uuid[:8]>`.

## Execution model

1. `spawn` writes a bash launcher script that runs the runtime command, applies
   the timeout (process-group `TERM` then `KILL`), then runs harnesses in order,
   then writes the exit marker.
2. tmux starts a detached session, pipes the pane to the log file, and execs the
   launcher.
3. `status` derives terminal state from the markers: `.timeout` → `timeout`;
   `.exit` 0 → `done`, non-zero → `failed`; no marker but session gone →
   `exited`.

## Worktree rules

- Requires `cwd` inside a git repo, else spawn fails.
- Dedicated branch + isolated worktree path; agent runs there.
- Local commits expected; human keeps merge control.
- Cleanup is explicit via `cleanup_worktree` / `agent-delegate cleanup-worktree`
  and uses `git worktree remove`, never `rm -rf`.
