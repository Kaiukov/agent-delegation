# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-06-18

### Changed
- process-group timeout with TERM→KILL escalation; new `timeout` status
- status lifecycle now `running|done|failed|timeout|killed|exited`
- `AgentRecord` gains `completed_at` and `duration_sec`
- harnesses documented as trusted local shell; harness failure → `failed`; failing harness shown in output
- `cleanup_worktree(uuid, force=False)` added in the backend, MCP tool, and CLI `cleanup-worktree`; uses `git worktree remove`, never `rm -rf`
- optional `claude`/`codex`/`pi` integration tests skip when the CLI is missing
- `examples/` added
