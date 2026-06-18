# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-06-18

### Changed
- **Skill-first packaging.** The portable `skills/agent-delegation/SKILL.md` is now
  the single source of truth, usable by any agent without Claude plugin metadata.
- Added `skills/agent-delegation/references/` (command-contract, runtime-contract,
  safety-rules, examples).
- Added `docs/compatibility.md` covering Claude Code, Codex CLI, Hermes, and
  generic agents.
- README rewritten as skill-first (skill is portable; CLI/MCP are local backends;
  Claude plugin is optional), keeping backend install + smoke test, a compatibility
  table, and the explicit no-board / no-GitHub-sync / no-PR-automation scope.
- Claude plugin wrapper skill now points to the root skill and holds no unique
  delegation rules.
- Added skill-usage examples for Claude, Codex, Hermes, and generic agents.
- No backend, runtime, or tmux changes; existing tests unchanged.

## [1.1.0] - 2026-06-18

### Changed
- process-group timeout with TERM→KILL escalation; new `timeout` status
- status lifecycle now `running|done|failed|timeout|killed|exited`
- `AgentRecord` gains `completed_at` and `duration_sec`
- harnesses documented as trusted local shell; harness failure → `failed`; failing harness shown in output
- `cleanup_worktree(uuid, force=False)` added in the backend, MCP tool, and CLI `cleanup-worktree`; uses `git worktree remove`, never `rm -rf`
- optional `claude`/`codex`/`pi` integration tests skip when the CLI is missing
- `examples/` added
