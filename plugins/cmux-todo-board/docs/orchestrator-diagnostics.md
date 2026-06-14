# Orchestrator Token-Efficiency Diagnostics & Secret-Safe Rules

**Status:** REFERENCE
**Applies to:** orchestrator sessions powered by Claude Code, Codex, or OpenCode agents.

---

## 1. Diagnostic Commands

| Command | What it shows | When to use |
|---------|--------------|-------------|
| `/usage` | Token count for the current conversation turn: prompt + completion, with a breakdown of cache creation, cache read, and input/output tokens per model. Also shows the total cost for the turn (in USD). | After every major milestone (dispatch, verify, merge) to track per-round token burn. Especially useful before and after an agent dispatch to measure the cost of the dispatch phase. |
| `/context` | Full context snapshot: loaded skills, file contents, tool-result excerpts, conversation-turn history, and the per-model token breakdown for the current point in the session. | Before dispatching a worker (to know how much context headroom you have) and whenever the model starts hallucinating or losing focus (context saturation indicator). |
| `/compact` | Rewrites preceding N turns into a condensed summary, reclaiming context window space. | When context is approaching the limit and you need to continue the same session instead of starting fresh. Use after a completed subtask or when switching to an unrelated goal within the same session. |
| `/clear` | Clears the conversation history entirely, freeing the full context window. Model persona, loaded skills, and tool definitions are retained; only the conversation turns are discarded. | When switching to a completely new task in the same session or after severe context corruption. Prefer `/compact` for light recovery — `/clear` is a hard reset that loses all in-session state. |
| `/config` | Lists all session-level configuration: active project, model provider, temperature, max tokens, output format flags, and any debug settings. | When you need to verify the current model, provider, or debug settings before a critical dispatch, or to confirm that a configuration change (.claude.json or project settings) has taken effect. |
| `claude --debug-file /tmp/claude-debug.log` | Captures every API request/response pair, tool invocation, and internal reasoning step to a structured JSON-lines log at the specified path. Not a session command — a CLI flag passed at session start. | During performance investigations or when filing a bug report about unexpected token usage, excessive tool calls, or context corruption. The debug log contains the raw data needed to reconstruct the exact sequence of events. |

### Quick-reference comparison

| Command | Scope | Recovery | Cost to run |
|---------|-------|----------|-------------|
| `/usage` | Current turn only | None (read-only) | 100–300 tokens |
| `/context` | Full session snapshot | None (read-only) | 200–800 tokens |
| `/compact` | Last N turns | Yes — reclaims context | 300–1,000 tokens |
| `/clear` | Entire conversation | Yes — full reset | ~50 tokens |
| `/config` | Session config | None (read-only) | 50–100 tokens |
| `--debug-file` | Entire session lifetime | None (external log) | 0 in-session tokens |

---

## 2. How to Identify Cost Sources

Diagnosing token waste starts with `/context` and `/usage` readings. The sections below list the common sources, what to look for, and how to confirm each.

### 2.1 Oversized skills

Skills loaded at session start contribute their full instruction text to every turn's prompt.

**Symptom:** `/context` shows one or more skills with several KB of instruction text that are not relevant to the current task.
**Check:** `wc -c skills/*/SKILL.md` and compare each file's size against its actual utility in the session. A lite variant may exist (e.g. `board-onboard-lite`).
**Remedy:** Replace full skills with lite variants. If no lite variant exists, consider whether the skill can be loaded on-demand.

### 2.2 Repeated hook output

Session-start hooks (e.g. `hooks/hooks.json`) run every session and append their output to context.

**Symptom:** `/context` shows identical hook-output blocks at the start of every conversation turn.
**Check:** Inspect `hooks/hooks.json` and measure the output of each hook execution.
**Remedy:** Suppress hook output that duplicates information the orchestrator will fetch explicitly (e.g. board status). Add a `--quiet` flag or gate noisy hooks behind a `DEBUG` env var.

### 2.3 Large MCP schemas / context

MCP (Model Context Protocol) tools send their full JSON schema with every turn, even when the tool is not called.

**Symptom:** `/context` shows tool definitions consuming several KB despite few or no tool calls in the session.
**Check:** Compare the total size of tool definitions in `/context` against the number of actual tool invocations.
**Remedy:** Disconnect unused MCP servers, or prefer lightweight alternatives with smaller schemas. Renegotiate the tool list at session start to include only the tools you need.

### 2.4 Large file / tool results

Reading a large file or running a command that produces voluminous output fills the context window.

**Symptom:** A single tool result in `/context` spans hundreds of lines or many KB. The conversation turn shows a high input-token count.
**Check:** Look for `read` calls on files >10 KB or `bash` commands with large stdout. `--debug-file` logs contain the exact byte counts.
**Remedy:** Read only the specific lines or sections you need (use `offset`/`limit` or `head`/`tail`). Avoid glob reads of directories with many files.

### 2.5 Recap overhead

Every turn the model re-reads its own previous reasoning to maintain coherence. This grows linearly with conversation length.

**Symptom:** Token count per turn increases steadily even when the input (new user message) stays the same size.
**Check:** Compare `/usage` for the first few turns vs. after 10+ turns.
**Remedy:** Compact or clear periodically. Use `/compact` after completing a subtask. For very long sessions, consider starting a fresh session and passing only the essential state via task spec.

### 2.6 Session-history growth

Every conversation turn accumulates in the context window, consuming tokens from the available limit.

**Symptom:** `/context` shows a long turn history with diminishing relevance to the current goal.
**Check:** Count the number of turns since last `/compact` or `/clear`.
**Remedy:** Establish a discipline: `/compact` after every completed agent round, `/clear` at session start for a new major task.

### 2.7 Subagent / worker contribution

Each agent dispatch produces a response that enters the orchestrator's context when read back from the headless worker exit/status output.

**Symptom:** After dispatching an agent, the orchestrator reads a multi-KB agent report that adds to the turn's token count.
**Check:** Compare `/usage` before and after the agent's final report is read.
**Remedy:** Read only the agent's structured summary (e.g. `status=`, `branch=`, `test_count=`) instead of the full terminal output. Limit screen reads to ≤40 lines.

### 2.8 Hook failures

A failing hook can produce repetitive error output that accumulates across turns.

**Symptom:** The same error message appears in `/context` at the start of every turn.
**Check:** Inspect the hook output in `/context` or the debug log. Look for repeated stderr lines.
**Remedy:** Fix or disable the failing hook. Add a concurrency guard or rate-limit if the failure is intermittent.

### Cost-source detection quick reference

| Source | Detection method | Typical waste | Remediation priority |
|--------|-----------------|---------------|---------------------|
| Oversized skills | `/context` skills section | 2–10 KB per turn | High |
| Repeated hook output | `/context` hook blocks | 0.1–0.5 KB per turn | Low |
| Large MCP schemas | `/context` tool defs | 1–5 KB per turn | Medium |
| Large file/tool results | `/usage` input spike | 5–200+ KB per turn | High |
| Recap overhead | `/usage` trend across turns | Linear growth per turn | Medium |
| Session-history growth | `/context` turn list | Linear growth per turn | Medium |
| Subagent/worker report | `/usage` before/after dispatch | 2–50 KB per dispatch | Medium |
| Hook failures | Repeated error in `/context` | 0.5–2 KB per turn | Low |

---

## 3. Secret-Safe Rules

These rules prevent sensitive credentials from leaking into model context, documentation, test fixtures, or version control.

### 3.1 Core rules

1. **Never print full auth files or API keys** in task specs, issues, test output, documentation, or command output. A masked form (`sk-…abc123`) is acceptable only in ephemeral debugging contexts that are never persisted or shared.

2. **Mask all credential values** when they must appear in logs or diagnostics. Replace the middle portion with `…` (e.g. `ghp_…wxyz`). Never include the full plaintext value.

3. **Prefer provider/account metadata only.** Reference credentials by alias or environment variable name rather than their value. Example: use `$GITHUB_TOKEN` or `secrets.GITHUB_TOKEN` instead of the literal token.

4. **Any key pasted into a model conversation must be revoked and rotated immediately.** Assume the key is compromised the moment it enters model context. The revocation must happen before the session continues.

5. **Tests and fixtures use obvious fake values only.** Never use real-looking credentials even in test comments or example output. Use strings like `sk-test-invalid-key` or `ghp_fake_test_token_do_not_use`.

### 3.2 Masking example (fake values only)

```bash
# GOOD — masked or env-var reference
export GITHUB_TOKEN="ghp_…wxyz"
echo "Using token from \$GITHUB_TOKEN (masked)"

# GOOD — fake value in test fixture
export GITHUB_TOKEN="ghp_fake_test_token_do_not_use"

# BAD — full plaintext key
export GITHUB_TOKEN="ghp_abc123def456ghi789jkl012"

# BAD — real-looking value in a doc example
anthropic_api_key: "sk-ant-api03-xxxxxxxxxxxx"

# ACCEPTABLE (ephemeral debug only, never committed)
echo "Token suffix: …abc123"
```

### 3.3 Verification checklist

Before committing any file that touches credentials:

- [ ] No full plaintext API keys, auth tokens, or passwords.
- [ ] All credential examples use obvious fake values or `…` masking.
- [ ] Test fixtures use strings like `fake-token` or `sk-test-invalid`.
- [ ] Session output with real credentials has been cleared from context before commit.
- [ ] Any leaked key has been revoked and rotated.
