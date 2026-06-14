# Codex Port

This repo already ships the shared cmux runtime. The Codex adapter is a thin
plugin-facing layer: manifest + marketplace entry + docs + prompt template.
Do not duplicate the worker runtime or board logic.

## Format Parity

| Surface | Claude Code path | Codex path | OpenCode path | Notes |
|---|---|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` | `.opencode/opencode.json` | Same plugin identity and metadata; only the manifest entry point changes. |
| Marketplace file | `.claude-plugin/marketplace.json` | `.agents/plugins/marketplace.json` | — | Codex uses a repo-scoped marketplace catalog; the plugin source stays local to this repo. |
| OpenCode plugin | — | — | `.opencode/plugins/cmux-board.mjs` | First-class OpenCode plugin exposing `board_status`/`board_next`/`board_sync` custom tools + `shell.env`/`session.idle` hooks. |
| Skills | `skills/*/SKILL.md` | `skills/*/SKILL.md` | `skills/*/SKILL.md` | Shared verbatim. |
| Hooks | `hooks/hooks.json` | `hooks/hooks.json` | `hooks/hooks.json` | Shared verbatim (Claude/Codex); OpenCode uses native plugin hooks. |
| Worker scripts | `skills/cmux-agent-workflows/scripts/*` | `skills/cmux-agent-workflows/scripts/*` | `skills/cmux-agent-workflows/scripts/*` | Shared headless dispatch and standby helpers. |
| Board cache | `.tasks/*` | `.tasks/*` | `.tasks/*` | Shared cache and state model. |
| Board logic | `bin/board-*` | `bin/board-*` | `bin/board-*` | Shared commands and label/state flow. |

The only plugin-packaging split is the manifest and marketplace entry point.
Everything else is reused as-is.

## Install And Run

1. Add the marketplace to Codex:

   ```bash
   codex plugin marketplace add Kaiukov/claude-code-cmux-todo-plugin
   ```

2. Install the board plugin from that marketplace:

   ```bash
   codex plugin add cmux-todo-board@kaiukov-tools
   ```

3. Start a clean Codex session and load the same board onboarding flow used by
   Claude Code. Do not fork `board-onboard`; the orchestrator identity changes,
   not the board/runtime.

   ```text
   /board-onboard
   ```

4. From the repo, pull and plan:

   ```bash
   /board-pull --repo owner/repo
   /board-plan
   ```

5. Dispatch ready work:

   ```bash
   /board-run-ready
   ```

## Backend Routing

Worker backend selection is config-driven. New scripts must not hardcode model
IDs.

- `bin/board-config --get-profile <name>` resolves a profile to a model id.
- `worker-spawn.sh <worktree> --profile <name> [label]` launches the headless
  pi backend for that profile and echoes the PID.
- Raw model launches use `worker-spawn.sh <worktree> <provider/model> [label]`.

## Completion Loop

Workers end with the shared completion contract:

- worker process exit code is 0,
- `CTB-DONE` appears in the worker output,
- the worker's branch commit exists.

Use `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` as the
bounded standby check for headless workers.

## Orchestrator Standby

After dispatching, the orchestrator waits on the headless worker via
`worker-watch.sh` and does not type into a live pane.
The canonical standby rule lives in `docs/ORCHESTRATOR.md`.

## Worker Prompt Template

The bounded worker final-report format lives at
`skills/cmux-agent-workflows/templates/worker-prompt.md`. It is backend-agnostic
and should be used for pi workers.

Required final-report fields:

- `STATUS`
- `ISSUE`
- `BACKEND`
- `BRANCH`
- `FILES_CHANGED`
- `TESTS`
- `SUMMARY`
- `BLOCKERS`
- `NEXT_ACTION`

Keep the report to 20 lines or fewer.

## GPT-As-Orchestrator Note

If GPT is acting as the orchestrator, keep the same board workflow and
cmux runtime. The worker backend is always `pi`.

## Manual Smoke Test

1. Run `/board-pull --repo owner/repo`.
2. Mark one issue `ready` in GitHub if none are ready yet.
3. Run `/board-plan`.
4. Run `/board-run-ready` and confirm a headless worker launches.
5. Wait for the worker's final report and `CTB-DONE` output.
6. Run the hard gate yourself: full tests plus `claude plugin validate .`.
7. Merge only after the hard gate passes.
