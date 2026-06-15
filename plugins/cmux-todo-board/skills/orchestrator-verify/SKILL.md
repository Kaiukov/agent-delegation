---
name: orchestrator-verify
description: Hard-gate a finished worker — review the diff against the brief, run the real acceptance recipe, never trust self-report.
---

# orchestrator-verify

You run the hard gate yourself. The worker's "done" and its own summary are
NOT proof. `$WT` = the worker's worktree.

## 1. Review what actually changed
```bash
git -C "$WT" log --oneline origin/<base>..HEAD     # the worker's commit(s)
git -C "$WT" diff --stat origin/<base>..HEAD        # scope
git -C "$WT" diff origin/<base>..HEAD               # read it
```
- Do the changed files match the `.task-spec.md` scope? Flag anything off-brief
  or touching out-of-scope / core code.
- Look for the things workers fake: stubs, `TODO`, deleted/skipped tests,
  env-gated branches that only pass on a test path. Grep for the real behavior,
  don't trust green output alone.

## 2. Run the real acceptance recipe
- `bin/orch-verify` and/or `scripts/verify.sh "$WT"` (project-agnostic: `bash -n`
  on changed shell + `bun test`/`npm test` if present).
- Plus the issue's own acceptance commands (e.g. `npx tsc --noEmit`, a specific
  test, a `grep` that must be empty). Run them in `$WT`, from a clean cwd.
- For anything live (deploy / KV / DB), the orchestrator runs the real command
  itself — workers test on mocks (see `cmux-agent-workflows` live-deploy traps).

## 3. Report pass/fail with evidence
- PASS: name the commands run + their results (e.g. "tsc exit 0, 12/12 tests,
  grep empty"). State it plainly.
- FAIL: quote the failing output, say what's wrong, and stop — re-dispatch with a
  sharpened brief or fix scope. Never relax the gate to get green.

Verification is the orchestrator's job and cannot be delegated to the worker.
