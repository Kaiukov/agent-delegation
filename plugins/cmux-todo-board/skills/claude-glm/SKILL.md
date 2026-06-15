---
name: claude-glm
description: How to run Claude Code in tmux against the zai provider (api.z.ai) with the glm-5.2 model, via ~/.claude/settings-glm.json and --dangerously-skip-permissions. Use when the user wants to launch/attach/headless-run claude on GLM, pick a glm model, or parallelize several claude agents in tmux panes.
---

# claude-glm — Claude Code на zai/glm-5.2 в tmux

Запуск `claude` (Claude Code) с провайдером **zai** (`api.z.ai/api/anthropic`)
и моделью **glm-5.2** (1M-контекст, суффикс `[1m]`), в сессии **tmux** без запросов
разрешений. Transport = tmux, runtime = `claude`, auth + endpoint + модели
прописаны в `~/.claude/settings-glm.json`.

## Что лежит в `~/.claude/settings-glm.json`

> Этот файл **не входит в плагин** — его создаёт сам пользователь на своей машине
> со своим ключом zai. Ниже его ожидаемая структура.

Один файл задаёт весь контракт с провайдером zai:

| Ключ | Значение | Что делает |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `https://api.z.ai/api/anthropic` | endpoint провайдера **zai** (Anthropic-compatible) |
| `ANTHROPIC_AUTH_TOKEN` | `<ваш ключ zai>` | авторизация на zai |
| `API_TIMEOUT_MS` | `3000000` | таймаут запроса 3000 c (GLM бывает долгим) |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `glm-4.5-air` | tier haiku → быстрая/дешёвая модель |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `glm-4.7` | tier sonnet → рабочая модель |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `glm-5.2[1m]` | tier opus → **glm-5.2, контекст 1M токенов** |
| `language` | `Russian` | язык интерфейса claude |

`--settings <файл>` грузит эти env-переменные поверх дефолтов. Модель **glm-5.2[1m]**
получает дефолтный tier claude — **без `--model` запуск уже идёт на glm-5.2[1m]**.

## Канонический запуск (интерактив, в tmux)

```bash
# создать отсоединённую сессию glm и запустить claude в репозитории
tmux new -s glm -d "cd \"$(pwd)\" && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json"

# подключиться к ней
tmux attach -t glm
```

`claude` наследует cwd, поэтому запускать нужно из корня целевого репозитория
(или `cd` внутрь команды, как выше). `[1m]` берётся в кавычки, потому что `[]` —
glob в шелле.

## Выбор модели (все три формы равнозначны)

| Хочу модель | Флаг `--model` |
|---|---|
| **glm-5.2** (1M, по умолчанию) | не указывать, **или** `--model opus`, **или** `--model "glm-5.2[1m]"` |
| glm-4.7 | `--model sonnet`, **или** `--model glm-4.7` |
| glm-4.5-air (быстрая) | `--model haiku`, **или** `--model glm-4.5-air` |

Алиасы `opus`/`sonnet`/`haiku` резолвятся через `ANTHROPIC_DEFAULT_*_MODEL` из
settings; явный id модели передаётся в zai как есть. Все формы проверены живым
запуском — отвечают `OK`, exit 0.

## Параллельные агенты (несколько claude в tmux)

Несколько независимых сессий — каждая со своим cwd/моделью:

```bash
tmux new -d -s glm-a "cd ~/repo && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json"
tmux new -d -s glm-b "cd ~/repo && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json --model glm-4.7"
tmux ls                       # glm-a, glm-b
tmux attach -t glm-a          # Ctrl-b d — отключиться обратно
```

Или окна внутри одной сессии (один attach, переключение `Ctrl-b <число>`):

```bash
tmux new -d -s glm "cd ~/repo && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json"
tmux new-window -t glm -n fast "cd ~/repo && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json --model glm-4.5-air"
tmux split-window -t glm -h "cd ~/repo && claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json"
tmux attach -t glm
```

## Headless / скриптовый запуск (без TUI)

`-p`/`--print` — один промпт, ответ в stdout, выход. Для пайпов и CI:

```bash
claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json \
  -p "Объясни, что делает этот файл" < src/foo.py
```

## Управление tmux-сессией

| Действие | Команда |
|---|---|
| Отключиться не убивая | `Ctrl-b d` (внутри сессии) |
| Список сессий | `tmux ls` |
| Подключиться | `tmux attach -t glm` |
| Убить сессию | `tmux kill-session -t glm` |
| Убить все | `tmux kill-server` |

## Smoke-тест (проверить, что zai+glm-5.2 отвечает)

```bash
claude --dangerously-skip-permissions --settings ~/.claude/settings-glm.json \
  -p "Reply with exactly the two characters: OK"
# ждём "OK", exit 0
```

## ⚠️ Caveats

1. **`--dangerously-skip-permissions` означает именно это.** Все permission-чеки
   сняты — `claude` выполнит `rm`, `git push`, `gh pr merge`, `curl | sh` и т.п.
   **без единого подтверждения**. Запускать только в каталоге, которому доверяешь
   полностью; для экспериментов — в worktree/песочнице. Никогда не цель в `$HOME`
   или репо с секретами, которых агент не должен трогать.
2. **`[1m]` = контекст 1 000 000 токенов.** У варианта без суффикса (`glm-5.2`)
   контекст меньше — суффикс даёт длинное окно ценой расхода/латентности.
3. **3000 c таймаут** (`API_TIMEOUT_MS`) — GLM на 1M-контексте бывает долгим; это
   нормально, не путать с зависанием.
4. **`--settings` суммируется, не заменяет.** User/project `settings.json` всё
   равно применяются; env из `settings-glm.json` грузится поверх. Если нужен
   «чистый» запуск без дефолтных настроек — проверяй, что не перехватывается.
5. **Язык интерфейса = Russian** (из settings) — ответы claude будут на русском
   согласно глобальной инструкции.
