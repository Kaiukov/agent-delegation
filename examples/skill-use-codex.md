# Using the skill with Codex CLI

1. Reference the skill in your project context (e.g. from `AGENTS.md`):
   ```text
   Before delegating work, read skills/agent-delegation/SKILL.md and follow it.
   ```
2. Let Codex call the CLI directly:
   ```bash
   uuid="$(agent-delegate spawn --runtime shell --cwd "$PWD" \
     --prompt 'pytest -q' | head -n1)"
   agent-delegate status "$uuid"
   agent-delegate read   "$uuid"
   ```
3. To delegate to a Codex sub-agent in an isolated worktree:
   ```bash
   agent-delegate spawn --runtime codex --cwd "$PWD" --worktree \
     --model gpt-5.4-mini \
     --prompt 'Implement .task-spec.md. Commit locally only; never push or open a PR.'
   ```

The skill is the contract; the CLI is the backend. No adapter required.
