# Compatibility

`agent-delegation` is **skill-first**. The portable layer is
`skills/agent-delegation/SKILL.md`; the CLI (`agent-delegate`) and the MCP server
(`agent-delegation-mcp`) are local execution backends. Any coding agent that can
read the skill and call the CLI or MCP tools can use the system.

Install the backend once (see the README), then wire the skill into your agent of
choice.

## Claude Code

- Copy or symlink the skill into your skills directory:
  ```bash
  ln -s "$PWD/skills/agent-delegation" ~/.claude/skills/agent-delegation
  ```
  (or per-project: `.claude/skills/agent-delegation`).
- Optionally register the MCP server in `.mcp.json`:
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
- The optional Claude plugin under `plugins/agent-delegation/` is just a wrapper;
  its skill points to the same instructions.

## Codex CLI

- Include `skills/agent-delegation/SKILL.md` in your project instructions or
  prompt context (e.g. reference it from `AGENTS.md`).
- The agent calls the `agent-delegate` CLI directly. No adapter needed.

## Hermes

- Load `SKILL.md` as the agent's instruction/context.
- Allow the agent to call `agent-delegate` or the MCP tools.

## Generic agents

- Any agent that can read markdown and run a shell command: have it read
  `SKILL.md` before delegating, then call `agent-delegate`.
- Any agent that speaks MCP: register `agent-delegation-mcp` and call its tools.

## Compatibility table

| Agent        | How to load the skill | How to execute |
| ------------ | --------------------- | -------------- |
| Claude Code  | symlink into `.claude/skills/` | MCP tools or `agent-delegate` CLI |
| Codex CLI    | reference `SKILL.md` in project/prompt context | `agent-delegate` CLI |
| Hermes       | load `SKILL.md` as instructions | `agent-delegate` CLI or MCP |
| Generic agent| read `SKILL.md` before delegating | `agent-delegate` CLI or MCP |

No custom adapters are required for any agent.
