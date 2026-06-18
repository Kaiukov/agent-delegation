---
name: agent-delegation
description: Spawn, track, message, and kill local sub-agents over tmux via a small CLI or MCP server. Use when delegating an isolated unit of work to a shell, claude, codex, or pi runtime.
---

# agent-delegation (Claude plugin wrapper)

This is the optional Claude plugin wrapper. It contains no unique delegation rules.
The single source of truth is the portable skill at the repository root:

> `skills/agent-delegation/SKILL.md`

Read that file for everything: what agent-delegation is, when to use / not use it,
the `spawn → uuid → status → read → send → kill/list` lifecycle, CLI usage, MCP
usage, runtime choices (`shell` / `claude` / `codex` / `pi`), worktree mode,
harnesses, timeout, `cleanup_worktree`, and the safety rules
(no board, no GitHub sync, no PR automation).

References live alongside it under `skills/agent-delegation/references/`.
