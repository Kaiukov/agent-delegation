---
name: orchestrator-dispatch
description: Dispatch one ready issue to a headless pi worker — profile, worktree, sharp .task-spec.md brief, and stall-safe thinking level.
---

# orchestrator-dispatch

Dispatch ONE `ready` issue to one headless `pi` worker. `$BIN` = the plugin's
`bin/` (resolved in orchestrator-onboard).

## 0. Pre-flight (don't dispatch blind)
- `gh issue view <n>` — read the full body; the issue IS the brief seed.
- Check the work isn't already done in uncommitted code:
  `git -C <host> status --short` + `git -C <host> diff --stat`. A `ready` issue
  often turns out already implemented in a working-tree batch — commit/close it
  instead of dispatching (see orchestrator-onboard board-sync).
- Pick the **narrowest** role: `repo-scout` (read-only recon), `backend`
  (implement), `reviewer` (read-only review). `orch-config` resolves the role's
  model/thinking/tools.

## 1. The one-liner (self-contained since v0.9.2)
```bash
"$BIN/orch-dispatch" --task-id <n> --role <repo-scout|backend|reviewer>
```
This now does everything: resolves the profile, **creates the worktree**
`wt-issue-<n>-<role>` (branch `issue-<n>-<role>`), **materializes
`<worktree>/.task-spec.md` from the GitHub issue body**, launches a detached
tmux session `orch-<n>-<role>` running `pi -p`, prints
`dispatched run_id=… session=… role=… issue=…`. You do NOT pre-create anything
for a trivial task.

## 2. For anything non-trivial: write a SHARP brief FIRST
The auto-generated `.task-spec.md` is only as good as the issue body. A thin
brief is how a worker goes **off-brief** (real failure: a worker read "convert
`<script>` to next/script" literally and broke JSON-LD on 16 pages). Because the
spec/worktree writes are **idempotent** (a pre-existing file is reused, never
clobbered), pre-seed them:
```bash
WT="$(dirname <host>)/wt-issue-<n>-backend"
"$BIN/../skills/cmux-agent-workflows/scripts/wt-new.sh" issue-<n>-backend "wt-issue-<n>-backend" <host>  # or: git -C <host> worktree add -b issue-<n>-backend "$WT" HEAD
# write $WT/.task-spec.md, THEN orch-dispatch (it reuses the worktree+spec)
```
A good `.task-spec.md` has: **exact files to touch** + **out-of-scope / do-NOT-touch**
+ **acceptance commands** (tsc/test/grep) + anti-rules (no push, no PR, no merge)
+ the line **"act, don't overthink — make the edits, then verify"**.

## 3. Pick a stall-safe thinking level
`orch-config`'s `backend` role is `openai-codex/gpt-5.4-mini` at **thinking=high**
— and high + a small model = analysis paralysis (0 tool calls → no heartbeat →
`killed_stalled` at the 120s watchdog; out.json balloons with empty
`thinking_delta`). `orch-dispatch` cannot override thinking, so for
implementation work dispatch via the lower layer at **medium**:
```bash
"$BIN/orch-tmux-spawn" --issue <n> --worktree "$WT" --repo-root <host> \
  --model openai-codex/gpt-5.4-mini --thinking medium \
  --tools read,bash,edit,write,grep,find,ls --role backend --session orch-<n>-backend
```
Rule of thumb (see the model→stall-risk table in `cmux-agent-workflows`):
high + small model = stall; use **medium**, or a larger model for nuanced work.

## 4. After dispatch
Go to **orchestrator-standby** immediately — verify the tmux session is live and
the worker is emitting tool calls (not just thinking), and watch the diff so you
can kill an off-brief worker before it commits. One issue, one worker, one
branch, one PR. Workers commit locally and **never push / never open PRs**.
