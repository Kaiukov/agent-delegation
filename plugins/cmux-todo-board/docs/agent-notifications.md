# Agent Completion Notifications

**Status:** IMPLEMENTED — event-driven `poll-wait.sh` (PRIMARY) + `poll-push.sh` fallback.

## cmux primitives

| Primitive | Carries event? | Notes |
|-----------|---------------|-------|
| `cmux notify` | Yes — direct notification to the orchestrator pane. | Lightest path; can carry structured payload (issue#, branch, success/failure). |
| `cmux hooks <agent> install --feed` | Yes — hook feed from agent pane. | Good for richer lifecycle events (start, progress, done, error). |
| `cmux set-status` / `cmux set-progress` | Partial — updates cmux pane status bar. | Visible to orchestrator but not a dedicated event; best combined with `notify`. |

## Per-backend reliability

### codex (OpenAI Codex CLI)
Native `PreToolUse` / `PermissionRequest` hooks are the most reliable
completion signal. The agent can emit a hook before its final tool use
or on session close. No polling needed if hooks are configured.

### opencode
No native completion event. Fallback: poll the pane for terminal output
or use `cmux notify` from the agent's final command. Screen-scraping
the pane is possible but fragile; prefer `cmux notify` as the
application-level signal with polling as backup.

### claude (Anthropic Claude Code)
No native completion event. Same fallback pattern: `cmux notify` as the
primary application-level signal, with pane-output polling as the
backstop. The `--feed` hook mechanism can be used if hooks are
installed in the agent session.

## Recommended flow

```
Agent finishes  →  cmux notify orchestrator (explicit CTB-DONE, structured flags)
                               ↓
                    cmux-session.js emits agent.hook.Stop (automatic lifecycle)
                               ↓
                    poll-wait.sh detects either signal via cmux events stream
                               ↓
                    orchestrator marks task complete
                               ↓
               if no event within timeout → poll-push.sh fallback (git polling)
```

The fallback window should be generous enough to avoid false timeouts
but short enough that no task is stranded indefinitely.

## Backend matrix

| Backend | Setup | Completion / notification path | Feed path |
|---|---|---|---|
| Claude Code | Wrapper-managed; enabled through cmux settings | `cmux notify --title "CTB-DONE" --body "..." --surface <surface>` from the agent's final step, then observe `cmux events --category notification` / `--category agent` | Wrapper-injected `PermissionRequest` only; use `cmux feed tui` to approve from the sidebar when a request appears |
| Codex | `cmux hooks codex install` | Same `cmux notify` completion signal; `poll-wait.sh` listens for `CTB-DONE` and agent idle events | `cmux hooks feed --source codex` is the bridge behind `cmux hooks codex install`; Codex approvals surface through the Feed / notification flow |
| OpenCode | `cmux hooks opencode install` and optionally `--feed` or `--project` | Same `cmux notify` completion signal; `poll-wait.sh` listens for `CTB-DONE` and agent lifecycle events | `cmux hooks opencode install --feed` writes the feed plugin and exposes approvals / questions in the Feed sidebar |

Practical rule:

- Use `cmux notify` for one-way completion or alert messages.
- Use `cmux feed tui` when the agent is blocked on permission, plan-mode, or a question.
- Use `cmux events --category notification --category agent --category feed` when you want to automate against the stream instead of reading the UI.
