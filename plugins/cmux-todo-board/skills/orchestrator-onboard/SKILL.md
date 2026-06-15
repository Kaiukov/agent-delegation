---
name: orchestrator-onboard
description: Auto-switch to orchestrator mode for the current project + first-run preflight, worker-spawn primer, and statusline wiring.
---

# orchestrator-onboard

Start here. You are the orchestrator: you coordinate and verify; you do NOT write
the feature code yourself — you dispatch headless `pi` workers via tmux and
hard-gate their output.

## 1. Adopt orchestrator mode for THIS repo
- The host repo is `git rev-parse --show-toplevel` of the cwd, or `$ORCH_REPO_ROOT` if set.
- All worktrees and run-state target the **host repo**, not the plugin; this stays portable across projects.
- Resolve the installed plugin once and reuse it:
  ```bash
  HOST_REPO="${ORCH_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
  PLUGIN_DIR="$(ls -d "$HOME"/.claude/plugins/cache/*/cmux-todo-board/*/ 2>/dev/null | sort -V | tail -1)"
  BIN="$PLUGIN_DIR/bin"      # orch-dispatch, orch-status, orch-statusline, ...
  ```

## 2. Wire the statusline for THIS project (so `🤖 orch-…` actually appears)
The statusline is per-project settings; a fresh repo has none, so it shows
nothing. Pin it to the host repo so run records resolve (no `· ?`):
```bash
mkdir -p "$HOST_REPO/.claude"
SETTINGS="$HOST_REPO/.claude/settings.json"
CMD="ORCH_REPO_ROOT=$HOST_REPO $BIN/orch-statusline"
tmp="$(mktemp)"
if [[ -f "$SETTINGS" ]]; then
  jq --arg cmd "$CMD" '.statusLine = {type:"command", command:$cmd, padding:0}' "$SETTINGS" > "$tmp"
else
  jq -n --arg cmd "$CMD" '{statusLine:{type:"command", command:$cmd, padding:0}}' > "$tmp"
fi
mv "$tmp" "$SETTINGS"
```
Tell the user the statusline refreshes on the next turn (or after `/reload`).

## 3. First-run preflight — fast, fail-fast, one ✓/✗ line each
- ✓/✗ cwd is inside a git repo (`git rev-parse --show-toplevel`)
- ✓/✗ required CLIs present: `tmux`, `pi`, `jq`, `git`, `gh` (`command -v`)
- ✓/✗ `gh auth status` is logged in (GitHub is the source of truth)
- ✓/✗ `$PLUGIN_DIR` resolved and `$BIN/orch-dispatch` is executable
- ✓/✗ `.tasks/orchestrator/` will live in the host repo (created on first dispatch)
- ✓/✗ statusline command in `$HOST_REPO/.claude/settings.json` points at `$BIN/orch-statusline`
- If any check is ✗, tell the user the single fix and stop.

## 4. How to spawn sub-agents (workers) via tmux — the dispatch contract
One ready issue → one worker. The single entry point is `orch-dispatch`:
```bash
"$BIN/orch-dispatch" --task-id <issue> --role <repo-scout|backend|reviewer>
```
What it does for you (self-contained — you do NOT pre-create anything):
1. resolves the worker model/thinking/tools from `orch-config` for the role
   (worker runtime = `openai-codex/gpt-5.4-mini`, thinking low|med|high; free
   models can 429 — issue #155; if a worker loops on empty reasoning, that's
   the codex thinking=high bug — re-dispatch at medium);
2. creates the git worktree `wt-issue-<n>-<role>` off the host repo (branch
   `issue-<n>-<role>`);
3. materializes `<worktree>/.task-spec.md` from the GitHub issue body (this is
   the worker's prompt; it is gitignored). Enrich it before/after if the issue
   body lacks paths or acceptance criteria;
4. launches a **detached tmux session** `orch-<n>-<role>` running the headless
   `pi -p` worker (layered prompts: common-system + role + worker-contract);
5. prints `dispatched run_id=… session=… role=… issue=…`.

Liveness is via tmux + the run record under `$HOST_REPO/.tasks/orchestrator/runs/`.
Watch with `$BIN/orch-status`; the statusline shows live `orch-*` sessions.
Workers commit locally and **never push / never open PRs**.

## 5. State the V1 rules
- GitHub is the source of truth. tmux is transport, not authority. pi is the worker runtime.
- Workers commit locally and never push.
- The orchestrator runs the hard gate (acceptance itself, not worker self-report).
- The orchestrator never merges or releases without explicit user OK.

## 6. Next step
Read board status / active runs with `$BIN/orch-status`, then hand off one ready
issue to `$BIN/orch-dispatch` (step 4). Keep handoffs compact and explicit.

Keep it short and action-first.
