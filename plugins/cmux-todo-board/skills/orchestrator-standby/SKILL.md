---
name: orchestrator-standby
description: Watch a dispatched worker — confirm liveness, detect stall/off-brief from out.json + diff, wake on git progress.
---

# orchestrator-standby

Enter watcher mode after dispatch. Passive, but NOT blind — a worker can stall
or go off-brief, and you must catch both before it wastes the round. `$WT` = the
worker's worktree, `$RF` = its run-file under
`<host>/.tasks/orchestrator/runs/`.

## 1. Confirm it actually started (first 30–60s)
```bash
tmux has-session -t orch-<n>-<role> && echo live
ps -p "$(jq -r .pid "$RF")" -o pid,stat,etime,command | tail -1
```
- No tmux session / dead pid right away → it crashed; read `$WT/out.json` head
  and `<host>/.tasks/orchestrator/logs/<run>.log`.

## 2. Watch for the two failure modes
**A) Stall (`killed_stalled`).** `worker-watch.sh` kills a worker whose
heartbeat is older than the stall threshold (~120s). The classic cause is
`thinking=high` on a small model: pure reasoning, **zero tool calls**, no
heartbeat. Tell-tale:
```bash
ls -lh "$WT/out.json"                                   # ballooning (tens of MB)
grep -c '"type":"thinking"' "$WT/out.json"              # huge
grep -cE '"toolcall_start"|"text_delta"' "$WT/out.json" # ~0
```
→ kill it and re-dispatch at `--thinking medium` (see orchestrator-dispatch §3).
Do NOT wait out a 0-tool-call worker.

**B) Off-brief.** The worker is busy but editing the WRONG files. Watch the diff,
not just the status:
```bash
git -C "$WT" diff --stat
```
If the changed files aren't the ones the brief named (e.g. it's rewriting 16
pages instead of `next.config.js`), **kill before it commits**:
`tmux kill-session -t orch-<n>-<role>; kill <pid>; git -C "$WT" checkout -- .`
Then sharpen `.task-spec.md` (exact files + do-NOT-touch) and re-dispatch.

## 3. Wake on real progress, not sentinels
- Completion = a **new commit on the branch** (`git -C "$WT" log --oneline origin/<base>..HEAD`)
  or the worker process exiting — never a printed "done".
- Use `bin/orch-watch` / the run-file `status` field (`running` →
  `done`/`killed_stalled`/`killed_timeout`/`crashed`). The statusline is a
  turn-boundary snapshot, not a live monitor.
- Don't noisily poll the tmux pane; check git + out.json activity periodically.

A healthy worker shows steady tool calls and a diff that matches the brief. When
it finishes, go to **orchestrator-verify**.
