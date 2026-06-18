---
name: agent-delegation
description: Minimal delegation rules for spawning, tracking, messaging, and killing sub-agents.
---

# agent-delegation

Use this skill when delegating work to a sub-agent in this repo.

## Rules

- The only lifecycle is `spawn → uuid → status → read → send → kill/list`.
- Dispatch is prompt-based. Do not route work by issue id, board id, task id, or label.
- Every `spawn` returns a uuid. `status`, `read`, `send`, `kill`, and `list` all operate by uuid.
- There are two backends:
  - the MCP server in `mcp/agent-delegation-mcp`, with tools `spawn_agent`, `get_agent_status`, `read_agent_output`, `send_agent_message`, `list_agents`, and `kill_agent`
  - the shell CLI at `bin/agent-delegate`
- `shell` is first-class and runs directly, without an external CLI wrapper.
- `pi`, `codex`, and `claude` are command-generation runtimes that build argv for delegated execution.
- Worktree mode isolates the agent in its own git worktree.
- Agents commit locally. The human owns the merge. Never push or automate a PR.
- No board, no GitHub labels, and no automated terminal UI integration.

## Operating posture

- Keep prompts explicit and short.
- Use `worktree` when the delegated change should be isolated from the main checkout.
- Prefer the minimal backend that can do the job.
