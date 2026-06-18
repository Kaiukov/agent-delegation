# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-06-18

### Changed
- Unified the MCP and CLI default state directory at `~/.agent-delegation-mcp/state`.
- Shell runtime now records real terminal completion as `done` and non-zero exits as `failed` via exit-code markers.
- Implemented the shell harnesses needed by the delegation flow.
- Kept `timeout_sec` defaulted to `0`, disabling timeouts unless explicitly requested.
- Pinned the MCP dependency to `mcp>=1.27,<2`.
- Synced package and plugin versions to `1.0.1`.

## [1.0.0] - 2026-06-18

### Changed (BREAKING)
- Refactored the repository from the `cmux-todo-board` GitHub-Issues board plugin
  into a minimal **agent-delegation** system. The plugin was renamed
  `cmux-todo-board` → `agent-delegation`.

### Added
- `mcp/agent-delegation-mcp/` — a stdio MCP server for delegating tasks to
  sub-agents in tmux: `spawn_agent`, `get_agent_status`, `read_agent_output`,
  `send_agent_message`, `list_agents`, `kill_agent`. Runtime `shell` is
  first-class; `pi`/`codex`/`claude` are command-generation runtimes.
- `plugins/agent-delegation/bin/agent-delegate` — a prompt/uuid CLI over the same
  backend (`spawn → uuid → status → read → send → kill/list`).
- `skills/agent-delegation/SKILL.md` and `docs/delegation-contract.md`.

### Removed
- The entire GitHub-Issues board system: all `board-*` scripts/skills/tests,
  `board.json`/`TODO.md` rendering, canonical label management, and the
  one-directional issue → board flow.
- The orchestrator dispatch/finish/status pipeline, the `orch-statusline`, the
  `SessionStart` board-summary hook, the OpenCode/Codex plugin variants, and the
  `legacy-reference/` tree.

[1.0.0]: https://github.com/Kaiukov/claude-code-cmux-todo-plugin/releases/tag/v1.0.0
