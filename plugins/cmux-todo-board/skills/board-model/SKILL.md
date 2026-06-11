---
name: board-model
description: Manage project-level provider/model registry and tier assignments (asign, add, edit, delete).
---

# board-model

Manage the project's model registry and delegation-tier assignments, stored in `.tasks/config.json`.

The model registry holds named provider/model configurations. Tiers (`flash`, `pro`, `review`, `simple`, `top`) can be assigned to registry entries via `asign`. At dispatch time, `board-config --get-model <tier>` resolves the tier through the registry to obtain the model ID, backend/provider, and optional reasoning effort.

## Commands

```
board-model add <name> --model <model-id> [--provider <opencode|codex>] [--effort <low|medium|high>]
```
Add a provider/model entry to the registry. `--provider` is auto-detected from the model pattern if omitted (`gpt-*`, `o1-*`, `o3-*`, `o4-*`, `codex*`, `chatgpt-*` → codex; anything with `/` → opencode). `--effort` is optional (codex reasoning effort). Rejects duplicate names.

```
board-model edit <name> [--model <model-id>] [--provider <opencode|codex>] [--effort <low|medium|high>] [--rename <new-name>]
```
Edit an existing registry entry. At least one change flag is required. When renaming, all tier assignments follow the new name.

```
board-model delete <name> [--force]
```
Delete a registry entry. Refuses if the entry is still assigned to any tier, unless `--force` is used (which also clears the assignments).

```
board-model asign <name> --tier <tier>
```
Assign a registry entry to a delegation tier (`flash|pro|review|simple|top`). The entry must exist in the registry.

```
board-model list
```
List all registry entries and current tier assignments (with default fallbacks shown for unconfigured tiers).

## Validation rules

- **Name**: Non-empty, alphanumeric + hyphens/underscores, unique in registry.
- **Model**: Non-empty identifier.
- **Provider**: `opencode` or `codex`.
- **Effort**: `low`, `medium`, or `high` (codex only).
- **Tier**: One of `flash`, `pro`, `review`, `simple`, `top`.
- **Delete safety**: Blocked when the entry is assigned to any tier. Use `--force` to override.
- **Rename safety**: Target name must not collide with an existing registry entry.

## Resolution

`board-config --get-model <tier>` resolves the tier through the model registry:

1. Look up `.models.<tier>` in `.tasks/config.json`.
2. If the value matches a `model-registry` key, resolve to the entry's `model`, `provider`, and `reasoning_effort`.
3. If the value is a bare model ID (no registry match), use it directly with auto-detected provider.
4. Fall back to built-in defaults when not configured.

Additional `board-config` flags:
- `--get-model <tier> --provider` → print provider name
- `--get-model <tier> --effort` → print reasoning effort (or empty)
- `--get-model <tier> --json` → print full `{model, provider, reasoning_effort}`

## Agent dispatch integration

When `agent-spawn.sh` receives a tier name (`flash|pro|review|simple|top`) it calls `board-config --get-model $TIER` to resolve it. The resolved model ID and provider flow into the agent launch command. Codex entries with `reasoning_effort` should be dispatched with `-c model_reasoning_effort=<effort>`.

## Examples

### Configure PRO tier for heavy implementation

```bash
board-model add my-pro --model gpt-5.5 --provider codex --effort high
board-model asign my-pro --tier pro
board-config --get-model pro              # → gpt-5.5
board-config --get-model pro --provider   # → codex
board-config --get-model pro --effort     # → high
```

### Configure simple tier for low-effort documentation

```bash
board-model add cheap-gpt --model gpt-5.4-mini --provider codex --effort low
board-model asign cheap-gpt --tier simple
board-config --get-model simple --json    # → {"model":"gpt-5.4-mini","provider":"codex","reasoning_effort":"low"}
```

### Batch non-interactive setup

```bash
board-model add pro-ai --model gpt-5.5 --provider codex --effort medium
board-model asign pro-ai --tier pro
board-model eddit pro-ai --effort high     # adjust effort later
board-model list                           # review all registry + assignments
```

## Backward compatibility

Existing configurations with bare model IDs in `.models` (e.g., `"pro": "opencode-go/deepseek-v4-pro"`) continue to work. When a model ID does not match any `model-registry` key, `board-config` treats it as a direct model identifier with auto-detected provider — identical to previous behavior.
