# Using the skill with Hermes

1. Load `skills/agent-delegation/SKILL.md` as the agent's instruction/context so
   Hermes knows the lifecycle (`spawn → uuid → status → read → send → kill/list`)
   and the safety rules.
2. Allow Hermes to run the CLI or call the MCP tools.

CLI path:

```bash
uuid="$(agent-delegate spawn --runtime shell --cwd "$PWD" \
  --prompt 'echo SMOKE_OK' | head -n1)"
agent-delegate read "$uuid"
agent-delegate kill "$uuid"
```

MCP path: register `agent-delegation-mcp` with the client and call `spawn_agent`,
`get_agent_status`, `read_agent_output`, `send_agent_message`, `kill_agent`,
`list_agents`, `cleanup_worktree`.

No custom adapter is needed — Hermes only needs to read the skill and execute a
shell command or an MCP tool. No board, no GitHub sync, no PR automation.
