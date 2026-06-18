# Using the skill with Claude Code

1. Make the skill discoverable:
   ```bash
   ln -s "$PWD/skills/agent-delegation" ~/.claude/skills/agent-delegation
   ```
2. (Optional) register the MCP server in `.mcp.json`:
   ```json
   {
     "mcpServers": {
       "agent-delegation": {
         "command": "~/.agent-delegation-mcp/venv/bin/agent-delegation-mcp",
         "env": { "ADM_STATE_DIR": "~/.agent-delegation-mcp/state" }
       }
     }
   }
   ```
3. Delegate from within Claude Code (MCP tools):
   ```text
   spawn_agent(runtime="shell", prompt="echo SMOKE_OK", cwd="/tmp")
   get_agent_status(uuid="…")
   read_agent_output(uuid="…")
   kill_agent(uuid="…")
   ```

Claude reads `SKILL.md` for the lifecycle and safety rules; the MCP tools (or the
`agent-delegate` CLI) run the work. No board, no GitHub sync, no PR automation.
