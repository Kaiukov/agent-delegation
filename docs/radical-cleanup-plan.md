# Radical cleanup plan — agent-delegation

**Date:** 2026-06-14
**Goal:** Keep 8 core features sharp, fast, bug-free. Everything else under the knife.
**Grounding:** Every file below was verified to exist in the repo (no hallucinated paths).

---

## 0. The 8 core features (KEEP + polish)

| # | Feature | Backing components (KEEP) |
|---|---------|---------------------------|
| 1 | **init** | `bin/board-init`, `skills/board-init` |
| 2 | **Onboard** | `skills/board-onboard`, `skills/board-onboard-lite`, `docs/ORCHESTRATOR.md`, `docs/delegation-policy.md` |
| 3 | **Pull + plan** | `bin/board-pull`, `bin/board-plan`, `bin/board-render`, `bin/board-render-body`, `bin/board-status`, `bin/board-next`, `skills/board-pull`, `skills/board-plan`, `skills/board`, `docs/state-model.md`, `.tasks/` |
| 4 | **Issue create** | `skills/board-create-issue` (calls `gh issue create` directly) |
| 5 | **Add Task** | `bin/board-add`, `skills/board-add-task` |
| 6 | **Spawn/kill pi-worker** | `scripts/agent-spawn.sh`, `agent-kill.sh`, `agent-send.sh`, `agent-screen.sh`, `wt-new.sh`, `lib.sh`, `pr-finish.sh`, `verify.sh`, `verify-ts.sh`, `bin/board-config` (`--get-profile`), `prompts/pi/{common-system.md,roles/*.md}`, `skills/cmux-agent-workflows{,-lite}` |
| 7 | **Version control** | `bin/board-release`, `skills/board-release` |
| 8 | **3×3 grid** | `bin/cmux-dev-grid`, `skills/cmux-dev-grid` |

---

## 1. Bug debt to fix on the KEEP set (the "отточить" work)

### 1a. Spawn/kill pi-worker
- **REMOVE damage-control entirely** (user decision: workers run in an isolated worktree, the gate adds no safety there). Delete the `--extension damage-control` block in `agent-spawn.sh` (~L182-187) and the `.pi/` extension + rules.
- **Trust-store race:** the pre-seed `[[ -f trust.json ]] || echo '{}'` passes on a 0-byte file → `jq` on empty input re-truncates → pi crashes "Unexpected end of JSON input". Fix: validate JSON (not just existence) before `jq`, write atomically.
- **Readiness false-negative:** "agent not confirmed ready after 120s". Replace probe with the spinner-based `pi_idle()` harvested from `agent-rotate.sh` (prompt `(auto)/(sub)` present AND no `Working…/Thinking…`).
- **Stale-shell launch eaten:** a leftover `pi` "Fork session? [y/N]" prompt in a reused pane swallows the launch line. Detect non-clean pane and reset before sending.

### 1b. 3×3 grid
- **`cmux-dev-grid init` does NOT build the grid** — it only labels panes that already exist (no `new-split` anywhere; see its own L33-37). Harvest the real builder from `spawn-3x3.sh` (clean others → `new-split right`×2 + `down`×6) as the "create if absent" path.
- **Wrong `workspace_ref` written:** cockpit.json uses `cmux current-workspace` (selected), while mapping uses `caller.workspace_ref` → today produced `workspace:18` while renames hit `workspace:15`. Single source: `caller.workspace_ref` everywhere.
- **cockpit.json path mismatch:** `cmux-dev-grid` writes `<repo-root>/.tasks/cockpit.json` but `agent-spawn.sh` reads `<plugin-dir>/.tasks/cockpit.json` (different `../` depth). Pick one path.
- **`--slot auto` always "full":** auto picks a slot only if `null`, but `init` populates all 8 → never free. Pick by REAL pane state (tty + `ps` for `pi`), harvested from `agent-rotate.sh`.

> All 3×3 + spawn-readiness fixes have a working reference in the polygon
> (`docs/future-feat-and-fix/spawn-3x3.sh`, `agent-rotate.sh`). **Harvest, then delete the polygon.**

---

## 2. CUT manifest (под нож)

### 2a. Damage-control (user decision: remove for pi workers)
- `.pi/extensions/damage-control.ts`
- `.pi/damage-control-rules.json`
- damage-control block in `agent-spawn.sh`
- `tests/test_damage_control.sh`
- memory TODO `add-gh-pr-block-to-damage-control` (obsolete)
- ⚠️ **Supersedes PR #150** (it ships damage-control into the package) — see §4.

### 2b. coms-net / SSE event bus (over-built for a single-user local cockpit)
- `.pi/extensions/coms-net.ts`, `scripts/coms-net-server.ts`, `scripts/cmux-agent-workflows/scripts/coms-net-await.sh`
- `docs/coms-net-design.md`, `plugins/.../docs/cmux-event-enhancement.md`, `plugins/.../docs/research/cmux-notify-feed-orchestrator.md`
- `tests/test_coms_net.sh`
- After removing both extensions: `tests/guardrail-ext-no-external-imports.sh` and `tests/guardrail-pi-runtime-smoke.sh` lose their subject → delete.
- **Replace waiting with commit-watch:** the orchestrator already watches the worktree branch for the worker's commit (truth signal). Keep `poll-wait.sh`/`poll-push.sh` only if they work standalone without the event bus — **VERIFY before deleting**, else simplify to a git-commit watcher.

### 2c. limit-monitor (#34)
- `bin/limit-monitor`, `tests/test_limit_monitor.sh`, `plugins/.../docs/issue-34-limit-monitor-research.md`

### 2d. Observability extras (not core)
- `scripts/agent-audit.sh`, `scripts/agent-notify.sh`
- `tests/test_agent_audit.sh`, `tests/test_agent_notify.sh`
- `docs/agent-notifications.md`, `plugins/.../docs/agent-notifications.md`

### 2e. Model-registry CRUD UX (profiles already cover spawn)
- `bin/board-model`, `skills/board-model`, `tests/test_board_model.sh`, `tests/test_model_hub.sh`
- KEEP `bin/board-config --get-profile` (the reader spawn needs) + its defaults; trim `skills/board-config` to a pointer.

### 2f. Pi-only leftovers (simplify, don't just delete)
- `--agent`/`--kind`/`agent_kind_*` shims in `lib.sh`, `agent-spawn.sh`, `agent-send.sh` → collapse to a hard pi path.
- `plugins/.../docs/codex-port.md` (codex backend gone) → delete.

### 2g. Research / benchmark / one-time artifacts (git history keeps them)
- `docs/future-feat-and-fix/` (whole dir, AFTER §1b harvest)
- `docs/research/legacy-removal-surface.md`, `docs/research/over-engineering-review.md`
- `docs/hygiene-report.md`
- `plugins/.../docs/orchestrator-benchmark.md`, `orchestrator-token-efficiency-research.md`, `orchestrator-diagnostics.md`
- `.orchestrator/` (root: `init-task.md`, `mvp-task.md`, `review-task.md`, `review-report.md` — MVP build scratch)

### 2h. DECIDE (need your call — not auto-cut)
- `bin/board-sync` + `skills/board-sync` + `tests/test_board_sync.sh` — status write-back to GitHub. Not in the 8, but it's how board status flows back. **Keep or cut?**
- `bin/board-install` + `tests/test_board_install.sh` — installer helper (plugin installs via marketplace anyway). **Keep or cut?**
- `docs/orchestrator-token-efficiency.md` — directly serves "fast/cheap". Lean **keep**.

---

## 3. KEEP-set docs (do not touch)
`docs/ORCHESTRATOR.md`, `delegation-policy.md`, `pi-prompt-layering.md`, `pi-profiles.md`, `pi-cli-usage.md`, `task-spec-template.md`, `install.md`, `state-model.md`, `file-roles.md`, `cmux-cheat-sheet.md`, root `README`.

---

## 4. Conflict: PR #150 vs damage-control removal
#150 (hard-gate green, **unmerged**) ships `.pi/` into the package so damage-control loads for the installed plugin. If damage-control is removed, **#150 is moot**. Recommended: **do NOT merge #150 — close it as superseded by the cleanup** (the cleanup deletes `.pi/` entirely). Avoids merging code we immediately delete.

---

## 5. Execution order (proposed)
1. **Close #150** as superseded (no merge). Drop the local `v0.8.0`/#150 commit is already pushed — handle as a follow-up note, not a revert.
2. **Issue A — "cockpit hardening + spawn polish"** (§1a + §1b): harvest `pi_idle` + real-state slot-pick + grid-builder + workspace-fix + trust-race + remove damage-control. Reference: polygon scripts. Acceptance includes deleting `future-feat-and-fix/` after harvest.
3. **Issue B — "radical cut"** (§2b–§2g): delete coms-net, limit-monitor, observability extras, model-registry CRUD, research docs, pi-only shims. One PR, mechanical.
4. **Resolve §2h** with you, fold into Issue B.
5. **Release** the slimmed plugin (your explicit OK each time).

**Rule respected:** every file deletion is preceded by `git log -- <file>` to confirm it's not a live document; harvest precedes deletion for polygon scripts.
