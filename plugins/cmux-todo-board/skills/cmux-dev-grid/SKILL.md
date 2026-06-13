---
name: cmux-dev-grid
description: Initialize and manage a 3×3 cmux development cockpit with a dedicated orchestrator pane and 8 reusable worker slots. Use for cockpit setup and status checks.
---

# cmux-dev-grid — 3×3 cmux cockpit

Initializes a **3×3 cmux development cockpit** with a dedicated orchestrator
pane in the center and eight reusable worker slots around it.

```
┌──────────┬──────────┬──────────┐
│ worker-1 │ worker-2 │ worker-3 │
├──────────┼──────────┼──────────┤
│ worker-4 │   ORCH   │ worker-5 │
├──────────┼──────────┼──────────┤
│ worker-6 │ worker-7 │ worker-8 │
└──────────┴──────────┴──────────┘
```

## Quick start

```bash
# Initialize the cockpit (idempotent — safe to re-run)
cmux-dev-grid init

# Show current slot mapping
cmux-dev-grid status

# Verify cockpit.json matches live cmux tree
cmux-dev-grid verify
```

## Cockpit-aware agent spawning

Once the cockpit is initialized, spawn agents directly into named slots
instead of creating new panes:

```bash
# Spawn into a specific slot
agent-spawn.sh --slot worker-3 /path/to/worktree --profile backend 113

# Auto-pick the first available empty slot
agent-spawn.sh --slot auto /path/to/worktree --profile backend 113
```

Without `--slot`, agent-spawn.sh behaves as before (creates a new pane via
balanced-grid split).

## How it works

1. **`init`** — inspects the cmux tree, identifies the orchestrator pane
   (surface titled "Orchestrator"), maps the remaining panes to `worker-1`
   through `worker-8` by pane creation order, renames tabs, and persists the
   mapping to `.tasks/cockpit.json`.

2. **`status`** — reads `.tasks/cockpit.json` and prints the grid layout
   with surface refs.

3. **`verify`** — checks that every slot in cockpit.json still has a live
   surface in the cmux tree. Exits non-zero on mismatch.

The orchestrator pane is detected by its title ("Orchestrator") in the
current workspace. It is excluded from worker slots and never used as a
spawn target.

## Slot lifecycle

- Slots are **reusable** — kill a finished agent, then spawn a new one
  into the same slot.
- Slots are **stable** — surface refs persist across `cmux-dev-grid init`
  re-runs for the same workspace.
- Slots are **named** — tab titles are set to `worker-1` through `worker-8`
  for easy identification.

## Files

- `.tasks/cockpit.json` — slot→surface mapping (runtime artifact, gitignored)
- `bin/cmux-dev-grid` — the init/status/verify script
