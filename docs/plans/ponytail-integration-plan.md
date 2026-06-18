# План внедрения Ponytail в `agent-delegation` (минимальная поверхность)

**Дата:** 2026-06-17  
**Цель:** добавить Ponytail как лёгкий слой правил и ревью поверх существующего плагина `agent-delegation`, не создавая вторую систему конфигов, хук-рантайма или матрицу host-adapters.

## Почему здесь нужен именно минимальный импорт

По результатам разбора репозитория Ponytail:

- ядро поведения живёт в `skills/ponytail/SKILL.md`;
- дополнительные навыки — `ponytail-review`, `ponytail-audit`, `ponytail-debt`, `ponytail-help`;
- всё остальное — это адаптеры под конкретные хосты: `AGENTS.md`, `.claude-plugin`, `.codex-plugin`, `hooks/`, `commands/`, `pi-extension/`, `.cursor/`, `.windsurf/`, `.clinerules/`, `.github/*`, `.kiro/`, `.openclaw/` и т. д.;
- `hooks/ponytail-activate.js`, `ponytail-mode-tracker.js`, `ponytail-config.js`, `ponytail-runtime.js` и statusline-скрипты нужны только для always-on режима и кросс-хостовой синхронизации состояния.

Для этого репозитория это означает:

1. **Берём только то, что реально снижает поверхностную сложность.**
2. **Не переносим portability-матрицу целиком.**
3. **Не добавляем новый runtime, если достаточно текста правила и одного review-skill.**

---

## Что импортировать, что адаптировать, что оставить вне scope

| Категория | Брать из Ponytail | Как адаптировать под этот репозиторий | Что оставить вне scope |
|---|---|---|---|
| **Core rule** | `skills/ponytail/SKILL.md` | Переписать примеры под shell/board/orchestrator-код, оставить лестницу `YAGNI → stdlib → native → one line → minimum` и правило про `ponytail:`-комментарии | Хост-матрицу, install-инструкции, marketing/benchmark-подачу |
| **Review helper** | `skills/ponytail-review/SKILL.md` | Использовать как краткий review-режим для диффов в `plugins/agent-delegation/**` | `ponytail-audit` и `ponytail-debt` до появления реальных потребностей |
| **Help helper** | `skills/ponytail-help/SKILL.md` | Только если нужен короткий справочник для команды/README | Полный набор команд и mode switching |
| **Always-on fallback** | `AGENTS.md` | Только как короткий repo-local policy file, если нужен режим без skill-capable host | Дублирование всей документации Ponytail |
| **Stateful hooks** | — | Не добавлять на первом проходе | `ponytail-activate.js`, `ponytail-mode-tracker.js`, `ponytail-runtime.js`, `ponytail-config.js`, statusline |
| **Command matrix** | — | Не добавлять, пока не появится реальный user-facing need | `commands/*.toml`, `.opencode/command/*.md`, pi-extension/gemini/copilot adapters |

### Важная привязка к текущей архитектуре

У `agent-delegation` уже есть plugin-surface, который грузит содержимое из `skills/` и использует `hooks/` там, где это нужно. Поэтому самый дешёвый путь — **положить Ponytail внутрь существующего `plugins/agent-delegation/skills/` и не трогать manifests без необходимости**.

---

## Фаза 0 — принять границу внедрения

**Задача:** решить, какой уровень интеграции нужен прямо сейчас:

- **Вариант A, рекомендуемый:** `skills/` + `ponytail-review` + при необходимости `AGENTS.md`.
- **Вариант B:** дополнительно `ponytail-help`.
- **Вариант C:** всё stateful/always-on (hooks, mode persistence, statusline) — только если появится конкретный сценарий, который не закрывается текстовыми правилами.

**Выход фазы:** короткое решение на 1–2 предложения и список целевых файлов.

**Проверка:**

- `claude plugin validate plugins/agent-delegation`
- базовый прогон существующих тестов без изменений в коде:
  - `bash plugins/agent-delegation/tests/test_sessionstart_hook.sh`
  - `bash plugins/agent-delegation/tests/test_pi_prompt_assets.sh`
  - `bash plugins/agent-delegation/tests/test_board_render.sh`

---

## Фаза 1 — импорт ядра Ponytail как skill-only слоя

**Цель:** получить Ponytail без нового рантайма и без дополнительной магии.

### Импортировать

- `skills/ponytail/SKILL.md`
- при необходимости `skills/ponytail-review/SKILL.md`

### Адаптировать

- заменить примеры из Ponytail на этот репозиторий:
  - shell-скрипты, `jq`, `gh`, `python3`, `tmux`, текущие `board-*` и `orch-*` команды;
  - формулировки должны упираться в текущую архитектуру: `skills/`, `hooks/`, `bin/`, `docs/`, `.tasks/`, `TODO.md`.
- сохранить минималистичную рамку:
  - не добавлять новую абстракцию, если достаточно существующего скрипта;
  - не вводить новый конфиг-файл ради одного значения;
  - не расширять матрицу host-адаптеров.
- оставить `ponytail:`-комментарии как легковесный debt marker только для реально принятых упрощений.

### Оставить вне scope

- hooks и mode persistence;
- `commands/*.toml` и другие command adapters;
- `benchmarks/`, `assets/`, release/marketing-массу;
- cross-host файлы (`.cursor`, `.windsurf`, `.clinerules`, `.kiro`, `.github/plugin`, `.openclaw`, `pi-extension/`).

### Проверка

- файл(ы) существуют в `plugins/agent-delegation/skills/` и не пустые;
- `claude plugin validate plugins/agent-delegation`;
- ручной smoke в Claude Code: skill вызывает именно ponytail-правила, а не board/orchestrator инструкции;
- если добавлен только `skills/`, а не `hooks/`, существующие тесты должны остаться зелёными:
  - `bash plugins/agent-delegation/tests/test_sessionstart_hook.sh`
  - `bash plugins/agent-delegation/tests/test_pi_prompt_assets.sh`
  - `bash plugins/agent-delegation/tests/test_repo_hygiene.sh`

---

## Фаза 2 — добавить repo-local policy adapter только при необходимости

**Цель:** если нужен always-on слой для агентов, работающих именно в этом репозитории, добавить его без повторения всей документации Ponytail.

### Импортировать

- либо `AGENTS.md` из Ponytail как шаблон,
- либо короткий новый `AGENTS.md` в корне этого репозитория, написанный заново на основе Ponytail-ядра.

### Адаптировать

- сократить до 25–40 строк;
- оставить только:
  - `YAGNI`-лестницу;
  - правило «используй существующие board/orchestrator utilities»;
  - правило «не добавляй новый host adapter / config surface / worker mode без реальной причины»;
  - напоминание про `ponytail:`-комментарии.
- сделать файл repo-specific: упоминать `plugins/agent-delegation/`, `skills/`, `hooks/`, `docs/`, `.tasks/`.

### Оставить вне scope

- полную матрицу install-инструкций Ponytail;
- mode switch / statusline / persistence;
- любые дубли текста из `skills/ponytail/SKILL.md`.

### Проверка

- если `AGENTS.md` создан, добавить мини-проверку на дрейф: файл должен оставаться кратким и не содержать host matrix;
- повторно прогнать:
  - `claude plugin validate plugins/agent-delegation`
  - `bash plugins/agent-delegation/tests/test_sessionstart_hook.sh`
  - `bash plugins/agent-delegation/tests/test_board_render.sh`

---

## Фаза 3 — встроить Ponytail в review workflow репозитория

**Цель:** сделать Ponytail полезным в обычном цикле изменения кода, а не только как статичный текст.

### Импортировать

- `skills/ponytail-review/SKILL.md`
- при реальной необходимости позже — `skills/ponytail-audit/SKILL.md`
- `skills/ponytail-debt/SKILL.md` только после того, как в коде появится достаточно `ponytail:`-комментариев

### Адаптировать

- применить `ponytail-review` к изменениям в:
  - `plugins/agent-delegation/skills/**`
  - `plugins/agent-delegation/hooks/**`
  - `plugins/agent-delegation/bin/**`
  - `plugins/agent-delegation/docs/**`
- держать формат вывода таким, чтобы он оставался механическим:
  - одна находка = одна строка;
  - location + что удалить/заменить;
  - без эссе и без «feature tour».
- если нужен короткий справочник, добавить `ponytail-help`, но только как ссылка на существующие правила.

### Оставить вне scope

- полноценный audit/debt pipeline прямо сейчас;
- массовое подключение всех hosts;
- отдельный benchmark harness.

### Проверка

- прогнать `ponytail-review` на реальном diff и убедиться, что он выдаёт только cut-list;
- после любого принятого сокращения прогнать существующие проверки:
  - `bash plugins/agent-delegation/tests/test_board_render.sh`
  - `bash plugins/agent-delegation/tests/test_board_pull_union.sh`
  - `bash plugins/agent-delegation/tests/test_orch_verify.sh`
  - `claude plugin validate plugins/agent-delegation`

---

## Фаза 4 — расширять только при доказанной пользе

**Цель:** не превращать Ponytail в новую тяжёлую подсистему.

### Что можно добавить позже, но только если появится явный спрос

- `ponytail-audit` как регулярный repo-wide audit;
- `ponytail-debt` как ledger для `ponytail:`-комментариев;
- `commands/*.toml` и host adapters для других CLI, если появится реальный потребитель вне Claude Code/Codex;
- hooks/statusline/persistence, если нужен always-on режим со сменой уровней.

### Что не делать даже здесь

- не копировать весь Ponytail portability matrix в этот репозиторий;
- не добавлять второй runtime-конфиг ради одного правила;
- не внедрять все host-адаптеры «на будущее».

### Проверка

- каждое расширение идёт отдельным PR/коммитом;
- у каждого расширения есть один конкретный smoke test;
- если появляется новый adapter file, на него есть file-existence check;
- существующий набор тестов остаётся зелёным.

---

## Критерии готовности

Внедрение можно считать успешным, если выполняется следующее:

1. Ponytail core доступен в `plugins/agent-delegation/skills/`.
2. При необходимости есть короткий repo-local instruction file (`AGENTS.md`), но без дублирования portability-матрицы.
3. `ponytail-review` используется для реальных диффов, а не просто лежит в дереве.
4. В репозиторий не были затащены hooks/statusline/config-подсистема Ponytail без явной причины.
5. `claude plugin validate plugins/agent-delegation` и ключевые shell-тесты продолжают проходить.

---

## Рекомендация по порядку работ

Если цель — **минимальная поверхность**, останавливайся после **Фазы 1**.  
Если нужен **always-on policy layer**, добавляй **Фазу 2**.  
Если нужен **регулярный anti-bloat review**, добавляй **Фазу 3**.  
**Фаза 4** — только по факту накопившейся пользы.
