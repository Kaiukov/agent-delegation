---
name: board-config
description: Manage board runtime configuration (language, model resolution) stored in .tasks/config.json.
---

# board-config

Manage the board's runtime configuration, stored in `.tasks/config.json`.

## Commands

```
board-config --get
```
Print the current configured language. Defaults to **EN** if no config file
or `language` key is set.

```
board-config --set-language <code>
```
Write or update the language code in `.tasks/config.json`, preserving any
other keys already in the file. The code is normalized (uppercased, trimmed).
Rejects empty or whitespace-only input.

```
board-config --get-model <tier> [--provider] [--effort] [--json]
```
Resolve the model for a delegation tier (`flash|pro|review|simple|top`).
Reads overrides from `.tasks/config.json`, resolves through the `model-registry`
if the tier is assigned to a registry entry, and falls back to built-in defaults.

- `--provider` — print the provider/backend (`opencode` or `codex`).
- `--effort`   — print the reasoning effort (`low`, `medium`, `high`) or empty.
- `--json`     — print full resolution as `{"model":"...","provider":"...","reasoning_effort":"..."}`.

## Model resolution

The `--get-model` resolution chain:

1. Look up `.models.<tier>` in `.tasks/config.json`.
2. If the value matches a key in `model-registry`, resolve to that entry's
   `model`, `provider`, and `reasoning_effort`.
3. If the value is a bare model ID (no registry match), use it directly with
   auto-detected provider.
4. Fall back to built-in defaults when the tier is not configured.

This preserves backward compatibility: existing configurations with bare model
IDs in `.models` continue to work unchanged.

## Default language rule

The board's default working language is **English (EN)**. All generated text
(GitHub issue titles/bodies, documentation) is produced in EN unless the user
explicitly overrides it with `board-config --set-language <code>`.

## See also

- `board-model` — manage the project-level model registry and tier assignments.
