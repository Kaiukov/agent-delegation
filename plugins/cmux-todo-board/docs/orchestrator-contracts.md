# Orchestrator Contracts

## Naming contract
Use these fixed names:

- branch: `issue-<n>-<role>`
- worktree: `../wt-issue-<n>-<role>`
- tmux session: `orch-<n>-<role>`
- run id: `<n>-<role>-<ts>`
- run state: `.tasks/orchestrator/runs/<run-id>.json`
- log: `.tasks/orchestrator/logs/<run-id>.log`

## Portability contract
There are two roots: plugin assets stay resolved relative to the plugin install dir, while work and run state live in the TARGET/host repo. The orchestrator is portable across a portfolio: run it in any git project and it operates on that repo, not the plugin.

- TARGET repo resolution precedence: `ORCH_REPO_ROOT`, `--repo <path>` / `--repo-root <path>`, `git -C "$PWD" rev-parse --show-toplevel`.
- Worktrees are siblings of the TARGET repo: `<dirname TARGET>/wt-issue-<n>-<role>`.
- Run/log state lives in the TARGET repo: `<TARGET>/.tasks/orchestrator/{runs,logs}`.

## Run contract
Each run record must include:
- `run_id`
- `issue`
- `role`
- `worktree`
- `branch`
- `session`
- `started_at`
- `profile`

## Watcher contract
Watcher signals in V1:
- local `HEAD` change
- remote ref change/appearance
- worker process death

Statuses:
- `running`
- `progressed`
- `ready-for-verify`
- `failed`

Default timing:
- poll: `15s`
- stalled: `20m`
- timeout: `60m`

`stalled` means the session/process is alive, but neither local `HEAD` nor remote ref changed for 20 minutes.

## Completion contract
Progress means:
- a new local commit, or
- a push to the remote branch

Process exit is auxiliary. A process dying without git progress is a failure signal, not the main completion signal.

There is no printed sentinel in V1.

## Verify contract
The orchestrator verifies the result itself.
It must run the repo-level verify recipe and not trust worker self-report.

Verify only proceeds after a meaningful git result is observed.
Merge is out of scope for automation and only happens with explicit user confirmation.

## MCP delegation-layer contract
The `agent-delegation-mcp` server (`mcp/agent-delegation-mcp/`, package
`agent_delegation_mcp`) is the minimal MCP transport for delegating tasks to
sub-agents in tmux. It is intentionally boards/GitHub/PR-free — lifecycle only.

Tool surface (stdio MCP, all backed by `AgentBackend`):
- `spawn_agent` → returns a record containing `uuid` (creates one tmux session)
- `get_agent_status` → never raises for a killed/finished agent; reports `alive`
- `read_agent_output` → last-N lines from the per-agent log; never raises after kill
- `send_agent_message` → `send-keys` into the session
- `list_agents` → all persisted records
- `kill_agent` → kills the session, sets status `killed`, stores `reason`

Naming/state:
- tmux session: `adm-<uuid[:8]>` (tmux-safe charset only)
- state dir: `$ADM_STATE_DIR` (default `~/.agent-delegation-mcp`)
- per-agent state: `<state>/agents/<uuid>.json`; logs: `<state>/logs/<uuid>.log`
- worktree mode: `git worktree add -b adm-<uuid[:8]> <state>/worktrees/<uuid[:8]> HEAD`;
  errors clearly if `cwd` is not a git repo and never clobbers an existing dir

Runtime contract (`runtime.build_command` returns argv, never a shell string):
- `shell` is first-class and always works (no external CLI)
- `pi` / `codex` / `claude` only generate a command; an unknown runtime raises `ValueError`

Status values: `running` → `exited` (session gone) / `killed` (explicit kill).
