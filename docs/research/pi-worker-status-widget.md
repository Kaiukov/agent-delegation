# Pi Worker-Status In-Pane Widget — Research & Design (#95)

> **Status:** RESEARCH — design doc only. No extension is installed or configured by this document.
>
> **Constraint:** Self-status only. No sub-agent pool, no completion routing, no sub-agent spawning.

## 1. Exact API: `ctx.ui.setWidget`

### Source verification

API shape confirmed from three independent sources:

| Source | Evidence |
|--------|----------|
| Pi docs (`docs/extensions.md`, Pattern 5) | Simple string-array form, theme-factory form, placement option, clear with `undefined` |
| Disler `subagent-widget.ts` (live OSS reference) | Full factory form returning `{ render, invalidate }`; re-calls `setWidget` on a timer to update elapsed time |
| `cmux-session.ts` (installed on this machine) | Confirms hook names, `ctx` shape, import paths that actually resolve |

### Signature

```typescript
// Set / update a widget
ctx.ui.setWidget(key: string, renderSpec: WidgetContent, options?: WidgetOptions): void;

// Clear a widget
ctx.ui.setWidget(key: string, undefined): void;
```

Where:

```typescript
type WidgetContent =
  | string[]                                          // simple lines
  | ((tui: TuiHandle, theme: Theme) => WidgetComponent);  // factory

interface WidgetOptions {
  placement?: "aboveEditor" | "belowEditor";  // default: "aboveEditor"
}

interface WidgetComponent {
  render(width: number): string[];  // one string per line; each ≤ width
  invalidate(): void;               // clear render cache
}

interface TuiHandle {
  requestRender(): void;            // trigger a re-render of the widget
}

interface Theme {
  fg(color: ThemeColor, text: string): string;  // apply foreground color
  bg(color: ThemeBgColor, text: string): string; // apply background color
  bold(text: string): string;
}
```

**Theme colors** (verified subset, from `docs/tui.md`):

| Category | Foreground (`fg`) | Background (`bg`) |
|----------|-------------------|-------------------|
| Status | `success`, `error`, `warning` | — |
| General | `text`, `accent`, `muted`, `dim` | — |
| Tool | `toolTitle`, `toolOutput` | `toolPendingBg`, `toolSuccessBg`, `toolErrorBg` |
| Border | `border`, `borderAccent`, `borderMuted` | — |
| Selection | — | `selectedBg` |

### Available TUI components

Import from `@earendil-works/pi-tui` (or `@mariozechner/pi-tui` — see §7):

| Component | Purpose |
|-----------|---------|
| `Container` | Groups children vertically; `addChild()`, `removeChild()` |
| `Text(text, padX?, padY?, bgFn?)` | Multi-line text with optional padding and background |
| `DynamicBorder(bgFn?)` | A single-line themed border |
| `Box(padX?, padY?, bgFn?)` | Container with padding and background color |
| `Spacer(lines)` | Empty vertical space |
| `Markdown(text, padX?, padY?, theme?)` | Rendered markdown |

All components implement `render(width: number): string[]` and `invalidate(): void`.

### How a widget is removed/cleared

```typescript
ctx.ui.setWidget("worker-status", undefined);
```

### Notes on re-render mechanics

When you call `setWidget` with a factory, the TUI framework **renders the widget inline in the pane on every frame** — it calls `render(width)` on each terminal repaint. This means:
- **For static data**, one `setWidget` call at `session_start` is enough.
- **For dynamic data** (elapsed time, tool count), you need to trigger re-renders. Two approaches are proven:

  1. **Re-register on timer** (used by `subagent-widget.ts`): store the `ctx`, run `setInterval`, and re-call `ctx.ui.setWidget(key, factory)` each tick. The fresh closure captures the latest state.
  2. **Capture `tui` and call `tui.requestRender()`**: store the `tui` handle from the factory callback, mutate shared state, then call `tui.requestRender()`. The existing component's `render()` reads the latest state.

  The skeleton below uses approach #1 (periodic re-registration) because it is battle-tested in the reference implementation and requires no stored `tui` reference.

---

## 2. Lifecycle Hook → Widget Update Mapping

Confirmed from Pi docs (`docs/extensions.md`, Lifecycle Overview) and `cmux-session.ts`:

| Hook | When fired | Widget action |
|------|-----------|---------------|
| `session_start` | Pi starts, `/new`, `/resume`, `/fork`, `/reload` | Initialize widget, read role/task from env/files, show **"idle"** status |
| `before_agent_start` | After user prompt, before agent loop | Capture prompt text as `currentTask`, show **"working"** status, start elapsed timer |
| `tool_execution_start` | Before each tool runs (`event.toolName`, `event.toolCallId`) | Increment tool counter; set `lastAction` to tool name |
| `agent_end` | Agent loop finishes (`event.messages`) | Stop timer, show **"done"** status, freeze final stats |
| `session_shutdown` | Cleanup before teardown | Clear widget (`setWidget(key, undefined)`), stop timer |

**Key event payloads** (verified from docs):

```typescript
// before_agent_start
event.prompt        // string — the user's prompt text

// tool_execution_start
event.toolName      // string — e.g. "bash", "read", "edit", "write"
event.toolCallId    // string
event.args          // the tool arguments

// agent_end
event.messages      // all messages from this prompt
```

---

## 3. What to Display

A **minimal one-line or two-line** widget, rendered above the editor (default placement):

```
● worker (task #95) · working · 12s · 4 tools · last: read
```

| Field | Source | Example |
|-------|--------|---------|
| Status icon | `●` working, `✓` done, `✗` error | `●` |
| Role | Env var `CMUX_WORKER_ROLE` (fallback: `"worker"`) | `researcher` |
| Task ID | Env var `CMUX_TASK_ID` (fallback: `"?"`) | `95` |
| Status label | Derived from hook | `working` / `done` / `idle` |
| Elapsed time | `Date.now() - startTime`, formatted | `12s` |
| Tool count | Incremented on `tool_execution_start` | `4 tools` |
| Last action | `event.toolName` from most recent `tool_execution_start` | `last: read` |

**Color scheme:**

| Element | Theme color |
|---------|-------------|
| Status icon + "working" | `theme.fg("accent", …)` |
| Status icon + "done" | `theme.fg("success", …)` |
| Role, task ID | `theme.fg("dim", …)` |
| Elapsed, tool count, last action | `theme.fg("muted", …)` |
| Border | `theme.fg("dim", …)` via `DynamicBorder` |

**Two-line variant** (optional, for narrow terminals):

```
┌ worker-status ──────────────────────────────────────────┐
│ ● working · task #95 · 12s · 4 tools · last: read       │
└──────────────────────────────────────────────────────────┘
```

---

## 4. Where Task and Role Come From

### Recommended: environment variables (set by the orchestrator)

The orchestrator (cmux or a dispatch script) sets env vars when spawning the worker Pi process:

```bash
CMUX_WORKER_ROLE=researcher \
CMUX_TASK_ID=95 \
CMUX_WORKER_LABEL="task-95" \
pi --session "wt-research-95" ...
```

| Env var | Purpose | Example |
|---------|---------|---------|
| `CMUX_WORKER_ROLE` | Human-readable role name | `researcher`, `implementer`, `reviewer` |
| `CMUX_TASK_ID` | Task/issues identifier | `95`, `94`, `l10-task-spec` |
| `CMUX_WORKER_LABEL` | Optional short display label | `task-95` |

### Alternative: parse `.task-spec.md`

Read the YAML frontmatter or first heading from the worktree's `.task-spec.md`. This is more fragile (depends on file format, requires fs operations) and is **not recommended** as the primary source. It could serve as a **fallback** if env vars are not set.

### Skeleton approach

```typescript
function readWorkerInfo(): { role: string; taskId: string; label: string } {
  return {
    role:    process.env.CMUX_WORKER_ROLE  || "worker",
    taskId:  process.env.CMUX_TASK_ID      || "?",
    label:   process.env.CMUX_WORKER_LABEL || `task-${process.env.CMUX_TASK_ID || "?"}`,
  };
}
```

---

## 5. Skeleton: `worker-status.ts`

A self-contained ~60-line skeleton wiring the hook→update mapping. **No sub-agent spawning, no sub-agent pool, no completion routing.**

```typescript
/**
 * worker-status.ts — Pi extension: renders the worker's OWN status as a live
 * in-pane widget above the editor. Self-status only. No sub-agents.
 *
 * Install: ~/.pi/agent/extensions/worker-status.ts
 * Env vars: CMUX_WORKER_ROLE, CMUX_TASK_ID, CMUX_WORKER_LABEL
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { DynamicBorder } from "@mariozechner/pi-coding-agent";
import { Container, Text } from "@mariozechner/pi-tui";

// ── State ────────────────────────────────────────────────────────────────────

interface WorkerState {
  status: "idle" | "working" | "done" | "error";
  role: string;
  taskId: string;
  label: string;
  currentTask: string;
  toolCount: number;
  lastAction: string;
  startTime: number | null;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function readWorkerInfo(): Pick<WorkerState, "role" | "taskId" | "label"> {
  return {
    role:   process.env.CMUX_WORKER_ROLE  || "worker",
    taskId: process.env.CMUX_TASK_ID      || "?",
    label:  process.env.CMUX_WORKER_LABEL || `task-${process.env.CMUX_TASK_ID || "?"}`,
  };
}

function formatElapsed(startTime: number | null): string {
  if (startTime === null) return "0s";
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  if (elapsed < 60) return `${elapsed}s`;
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  return `${m}m${s}s`;
}

// ── Widget rendering ─────────────────────────────────────────────────────────

function renderWidget(ctx: any, state: WorkerState): void {
  ctx.ui.setWidget("worker-status", (_tui: any, theme: any) => {
    const container = new Container();

    container.addChild(new DynamicBorder((s: string) => theme.fg("dim", s)));

    const content = new Text("", 1, 0);
    container.addChild(content);

    container.addChild(new DynamicBorder((s: string) => theme.fg("dim", s)));

    return {
      render(width: number): string[] {
        const statusColor =
          state.status === "working" ? "accent" :
          state.status === "done"    ? "success" :
          state.status === "error"   ? "error"   : "muted";
        const icon =
          state.status === "working" ? "●" :
          state.status === "done"    ? "✓" :
          state.status === "error"   ? "✗" : "○";

        const line =
          theme.fg(statusColor, `${icon} ${state.status}`) +
          theme.fg("dim", ` · ${state.role} (#${state.taskId})`) +
          theme.fg("muted", ` · ${formatElapsed(state.startTime)}`) +
          theme.fg("muted", ` · ${state.toolCount} tools`) +
          (state.lastAction
            ? theme.fg("muted", ` · last: ${state.lastAction}`)
            : "");

        content.setText(line);
        return container.render(width);
      },
      invalidate(): void {
        container.invalidate();
      },
    };
  });
}

// ── Extension entry point ────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  const state: WorkerState = {
    status: "idle",
    ...readWorkerInfo(),
    currentTask: "",
    toolCount: 0,
    lastAction: "",
    startTime: null,
  };

  let tickInterval: ReturnType<typeof setInterval> | null = null;
  let widgetCtx: any = null;

  function startTicking(ctx: any): void {
    if (tickInterval) return;
    tickInterval = setInterval(() => renderWidget(ctx, state), 1000);
  }

  function stopTicking(): void {
    if (tickInterval) { clearInterval(tickInterval); tickInterval = null; }
  }

  // ── Hook: session_start ─────────────────────────────────────────────────

  pi.on("session_start", async (_event, ctx) => {
    widgetCtx = ctx;
    Object.assign(state, readWorkerInfo());
    state.status = "idle";
    state.currentTask = "";
    state.toolCount = 0;
    state.lastAction = "";
    state.startTime = null;
    renderWidget(ctx, state);
  });

  // ── Hook: before_agent_start ────────────────────────────────────────────

  pi.on("before_agent_start", async (event, ctx) => {
    widgetCtx = ctx;
    state.status = "working";
    state.currentTask = event.prompt || "";
    state.toolCount = 0;
    state.lastAction = "";
    state.startTime = Date.now();
    startTicking(ctx);
    renderWidget(ctx, state);
  });

  // ── Hook: tool_execution_start ──────────────────────────────────────────

  pi.on("tool_execution_start", async (event, ctx) => {
    widgetCtx = ctx;
    state.toolCount++;
    state.lastAction = event.toolName;
    renderWidget(ctx, state);
  });

  // ── Hook: agent_end ─────────────────────────────────────────────────────

  pi.on("agent_end", async (_event, ctx) => {
    widgetCtx = ctx;
    stopTicking();
    state.status = "done";
    state.lastAction = "";
    renderWidget(ctx, state);
  });

  // ── Hook: session_shutdown ──────────────────────────────────────────────

  pi.on("session_shutdown", async (_event, ctx) => {
    stopTicking();
    ctx.ui.setWidget("worker-status", undefined);
  });
}
```

---

## 6. Integration Plan

### Installation

Drop the file into Pi's global extensions directory:

```bash
cp worker-status.ts ~/.pi/agent/extensions/worker-status.ts
```

Pi auto-discovers `~/.pi/agent/extensions/*.ts` at startup — no config changes needed.

### Coexistence with `cmux-session.ts`

Both extensions live in the same directory and are loaded side-by-side. No conflict:

| Concern | Resolution |
|---------|------------|
| **Widget key collision** | `cmux-session.ts` does not use `setWidget` at all — it only calls `spawnSync("cmux", …)` in hooks. No key conflict. |
| **Hook overlap** | Both listen to `session_start`, `before_agent_start`, and `agent_end`. Pi calls all handlers for each event. No mutual exclusion needed. |
| **Performance** | The widget's 1-second tick timer is cheap; ~1 setWidget call / sec. `cmux-session.ts` does synchronous `spawnSync` with 5s timeout. No measurable interference. |
| **Load order** | Both are loaded via Pi's auto-discovery. Load order is alphabetical: `cmux-session.ts` loads before `worker-status.ts`. This is irrelevant — neither depends on the other. |

### Orchestrator setup (for cmux/dispatch)

When the orchestrator spawns a worker Pi session, it sets:

```bash
cmux surface new \
  --env CMUX_WORKER_ROLE=researcher \
  --env CMUX_TASK_ID=95 \
  --cwd /path/to/wt-research-95 \
  -- pi
```

Or in a dispatch script:

```bash
export CMUX_WORKER_ROLE="$ROLE"
export CMUX_TASK_ID="$TASK_ID"
pi --session "wt-$TASK_ID" --cwd "$WORKTREE"
```

### What the orchestrator sees

Inside each worker pane, the widget renders above the editor:

```
┌──────────────────────────────────────────────────────────┐
│ ● working · researcher (#95) · 12s · 4 tools · last: read│
├──────────────────────────────────────────────────────────┤
│ (editor / conversation)                                  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

When the worker finishes (`agent_end`), the widget flips to:

```
┌──────────────────────────────────────────────────────────┐
│ ✓ done · researcher (#95) · 47s · 12 tools               │
├──────────────────────────────────────────────────────────┤
```

This gives the orchestrator (and human) at-a-glance observability into each worker pane without screen-scraping or sub-agent management.

---

## 7. Risks, Unknowns, and Unverified Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | **Package import name** | ⚠️ RESOLVED (with caveat) | The installed `cmux-session.ts` imports from `@mariozechner/pi-coding-agent` and `@mariozechner/pi-tui`. Official Pi docs use `@earendil-works/pi-coding-agent` and `@earendil-works/pi-tui`. On this machine, `@earendil-works/pi-coding-agent` resolves; `@mariozechner/pi-coding-agent` also exists via `node_modules` aliasing. **Recommendation:** use the same package name as `cmux-session.ts` for consistency (`@mariozechner/…`). If that fails, switch to `@earendil-works/…`. |
| 2 | **`DynamicBorder` import path** | ⚠️ RESOLVED | `subagent-widget.ts` imports `DynamicBorder` from `@mariozechner/pi-coding-agent` (not `pi-tui`). This is confirmed working — it's re-exported by the main package. |
| 3 | **Re-render on timer vs `tui.requestRender()`** | ⚠️ UNVERIFIED | The skeleton uses the "re-register on timer" approach (battle-tested in `subagent-widget.ts`). The alternative — capturing `tui` and calling `tui.requestRender()` — is plausible per the TUI component docs but was **not tested** in the context of `setWidget`. The timer approach is safe and proven. |
| 4 | **`agent_end` → status "done" reliability** | ⚠️ UNVERIFIED | If the agent fails (tool error, model error), does `agent_end` still fire? The docs don't explicitly state error-semantics for `agent_end`. If `agent_end` fires on both success and failure, the widget won't distinguish them. **Mitigation:** could add `tool_execution_end` with `event.isError` checks to set status to `"error"` on tool failure. |
| 5 | **Widget survives `/new` and `/resume`** | ⚠️ UNVERIFIED | When the user types `/new`, Pi emits `session_shutdown` (widget clears), then reloads extensions and emits `session_start`. The `session_start` handler re-initializes the widget. This should work, but was not tested live. |
| 6 | **Widget key uniqueness** | ✅ VERIFIED | Using `"worker-status"` as the key. `cmux-session.ts` does not register any widget. No collision expected. |
| 7 | **`setWidget` placement option** | ✅ VERIFIED | `{ placement: "belowEditor" }` is documented. Default (above editor) is appropriate for status display. |
| 8 | **Minimum Pi version** | ⚠️ UNVERIFIED | The `ctx.ui.setWidget` API exists in Pi 0.79.1 (current installed version). It may not exist in older versions. No version guard implemented in the skeleton. |
| 9 | **TUI vs non-TUI modes** | ⚠️ UNVERIFIED | `ctx.ui.setWidget` is a no-op in RPC mode (per docs: "In RPC mode, some TUI-specific methods are no-ops"). The widget only renders when `ctx.mode === "tui"`. This is the correct behavior for in-pane widgets; workers in JSON/print mode don't have a pane. |

---

## Appendix A: Hook Event Reference (condensed)

From Pi docs, for quick reference:

```
session_start        → { reason: "startup"|"reload"|"new"|"resume"|"fork", previousSessionFile? }
before_agent_start   → { prompt: string, systemPrompt: string, ... }
tool_execution_start → { toolCallId: string, toolName: string, args: unknown }
tool_execution_end   → { toolCallId: string, toolName: string, result, isError: boolean }
agent_end            → { messages: Message[] }
session_shutdown     → { reason: "quit"|"reload"|"new"|"resume"|"fork" }
```

## Appendix B: cmux-session.ts Hook Usage (reference)

The installed `~/.pi/agent/extensions/cmux-session.ts` subscribes to exactly three hooks:

```typescript
pi.on("session_start",       async (_event, ctx) => { sendHook("session-start", ctx); });
pi.on("before_agent_start",  async (event, ctx)  => { sendHook("prompt-submit", ctx, { prompt: event.prompt }); });
pi.on("agent_end",           async (event, ctx)  => { sendHook("stop", ctx, { last_assistant_message: lastAssistantMessage(event) }); });
```

Our worker-status widget listens to the same three hooks, plus `tool_execution_start` and `session_shutdown`. No overlap in side effects — `cmux-session` sends IPC; our widget renders UI. Safe coexistence.
