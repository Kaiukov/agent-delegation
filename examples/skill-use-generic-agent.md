# Using the skill with a generic agent

Any agent that can read markdown and run a shell command (or speak MCP) can use
agent-delegation. There are no custom adapters.

1. Read `skills/agent-delegation/SKILL.md` before delegating. It is
   self-contained — it does not depend on any Claude-specific metadata.
2. Delegate via the CLI:
   ```bash
   uuid="$(agent-delegate spawn --runtime shell --cwd "$PWD" \
     --prompt 'echo hello' | head -n1)"
   agent-delegate status "$uuid"
   agent-delegate read   "$uuid"
   agent-delegate kill   "$uuid"
   ```
3. Or, if the agent speaks MCP, register `agent-delegation-mcp` and call the same
   operations as tools.

Pick the narrowest runtime (`shell`, `claude`, `codex`, `pi`), use `--worktree`
to isolate changes, gate with `--harness`, bound with `timeout_sec`, and clean up
with `cleanup-worktree`. Agents commit locally; humans merge. No board, no GitHub
sync, no PR automation.
