# Examples

Copy-paste lifecycle examples. Replace `<uuid>` with the value `spawn` prints.

## shell (direct command)

```bash
uuid="$(agent-delegate spawn --runtime shell --cwd /tmp --prompt 'echo SMOKE_OK' | head -n1)"
agent-delegate status "$uuid"
agent-delegate read   "$uuid"
agent-delegate kill   "$uuid"
```

## shell with a harness gate

```bash
agent-delegate spawn --runtime shell --cwd "$PWD" \
  --prompt 'python build.py' \
  --harness 'pytest -q' \
  --harness 'bash -n scripts/deploy.sh'
# final status becomes `failed` if any harness exits non-zero
```

## codex in an isolated worktree

```bash
uuid="$(agent-delegate spawn --runtime codex --cwd "$PWD" --worktree \
  --model gpt-5.4-mini \
  --prompt 'Implement the change described in .task-spec.md. Commit locally only; do not push or open a PR.' | head -n1)"
agent-delegate read "$uuid" --lines 120
# when done, inspect the branch adm-<uuid[:8]>, then:
agent-delegate cleanup-worktree "$uuid"
```

## claude

```bash
agent-delegate spawn --runtime claude --cwd "$PWD" \
  --prompt 'Refactor src/util.py for clarity; commit locally only.'
```

## pi

```bash
agent-delegate spawn --runtime pi --cwd "$PWD" \
  --provider zai --model glm-4.7 --thinking medium \
  --prompt 'Add docstrings to the public functions in module X. Commit locally only.'
```

## MCP (any client)

```text
spawn_agent(runtime="shell", prompt="echo SMOKE_OK", cwd="/tmp")
get_agent_status(uuid="…")
read_agent_output(uuid="…", lines=80)
send_agent_message(uuid="…", message="continue")   # only while session alive
kill_agent(uuid="…", reason="done")
list_agents()
cleanup_worktree(uuid="…")
```

## bounded run (MCP timeout)

```text
spawn_agent(runtime="shell", prompt="long_task.sh", cwd="/work", timeout_sec=600)
# status becomes "timeout" if it overruns 600s
```
