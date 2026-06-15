---
name: orchestrator-finish
description: Close a verified run locally (never auto-merge), then clean up worktrees and orphan processes.
---

# orchestrator-finish

Close out a VERIFIED run. Local-only by default — the merge is the human's call.

## 1. Local finish (default — no merge)
```bash
"$BIN/orch-finish" <pr-or-run> [worktree]
```
Since v0.9.1 this is a LOCAL finish: it cleans the worktree/run state and exits
without `gh pr merge`. Summarize the outcome and hand back.

- Do NOT auto-merge. `gh pr merge` only runs behind the explicit `--merge` flag,
  and only after the user explicitly OKs THIS merge. Opening a PR is allowed when
  asked; merging/releasing is not, without per-item permission.
- Do NOT deploy in V1.

## 2. Post-round hygiene (prevent orphan buildup)
Stale worktrees and orphaned keep-alive processes accumulate across sessions
(`git worktree list` showing 4+ `wt-issue-*`; `sleep`/`pi` procs with ppid=1
referencing deleted worktrees). After a round:
```bash
git worktree list                                   # inventory
ps -eo pid,ppid,etime,command | grep -E 'wt-issue|sleep 3600|[p]i ' | grep -v grep
```
- Identify the ACTIVE worker(s) first (current run-files / live tmux sessions) and
  never touch those.
- Kill orphan processes that reference worktrees that no longer exist.
- `git worktree remove <wt> --force` for finished/empty worktrees; `git branch -D`
  the merged/abandoned branch. **Never** silently delete a worktree with
  uncommitted work you didn't create — surface it and ask.

## 3. Sync the board
After a real merge/close, reflect it on GitHub (the source of truth): close the
issue, drop the `in-progress` label. A `done` issue still marked `in-progress`
with no active run is a stale board — fix it.

Finish locally, clean up, then hand control back to the user.
