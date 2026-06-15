---
name: orchestrator-status
description: One compact V1 snapshot of live runs, worker health, and board sync.
---

# orchestrator-status

Show exactly ONE compact operational snapshot.

```bash
"$BIN/orch-status"                 # active runs + worker state
"$BIN/board-status" 2>/dev/null    # inbox/ready/in-progress/done counts
tmux ls 2>/dev/null | grep '^orch-'  # live transport sessions
```

Report, in a few lines:
- **Active runs** — issue, role, model, status (`running`/`done`/`killed_*`/`crashed`),
  and the tmux session. Cross-check: a run-file `running` with no live tmux
  session or dead pid = a stale record (the runner died before updating it) —
  flag it, don't report it as healthy.
- **Worker health** — if `running`, is it making progress? A quick
  `git -C <wt> diff --stat` + out.json tool-call count tells stall from work
  (see orchestrator-standby).
- **Board sync** — `in-progress` issues with no active run, or `ready` issues
  already implemented in uncommitted code, are drift; call them out.
- **Next action** — the single most useful next step, if obvious.

Keep it compact. Don't trawl logs without a specific reason. The statusline is a
turn-boundary snapshot, not a live monitor — if unclear, refresh `orch-status`
once.
