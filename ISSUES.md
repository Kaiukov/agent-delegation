# cmux-task-board plugin — Issue Backlog

Source design note: `~/Obsidian/myVault/claude-code-cmux-todo-plugin.md`

Канонические лейблы статуса (используются и в issue этого бэклога, и как контракт самого плагина):
`inbox`, `ready`, `in-progress`, `needs-review`, `blocked`, `needs-info`, `done`.

Приоритеты: **P0** блокер архитектуры · **P1** нужно для MVP · **P2** после MVP · **P3** nice-to-have.

---

## EPIC A — Модель состояния и контракты (фундамент, делать первым)

### #1 — Определить таблицу состояний: Claude todo ↔ board.json ↔ GitHub label  `P0` `design`
**Проблема.** Цикл `pending → in_progress → completed` живёт внутри сессии Claude и стирается в конце раунда. Значит источник истины по статусу — лейблы issue, а не todo. Сейчас соответствие нигде не зафиксировано.

**Acceptance criteria.**
- [ ] Документ `docs/state-model.md` с таблицей соответствия трёх представлений.
- [ ] Явно указан единственный источник истины: **GitHub labels — статус**, **`board.json` — локальный кэш**, **`TODO.md` — read-only рендер**, **Claude todo — эфемерный план раунда**.
- [ ] Описано, что происходит со статусом при потере сессии (восстановление из labels на следующем `board-pull`).
- [ ] Канонический enum статусов зафиксирован (свести `done`/`completed`, добавить `needs-info`).

---

### #2 — Зафиксировать роли board.json / issues.json / TODO.md  `P0` `design`
**Проблема.** Создаются три артефакта (`.tasks/issues.json`, `.tasks/board.json`, `TODO.md`), но не определено, какой из них редактируемый, а какой производный.

**Acceptance criteria.**
- [ ] `issues.json` = сырой кэш ответа GitHub API (только запись из `board-pull`).
- [ ] `board.json` = единственный локальный источник истины (derived из issues + локальные пометки).
- [ ] `TODO.md` = read-only рендер из `board.json` (генерится `board-render.py`, человек руками не правит).
- [ ] Решение задокументировано; в `TODO.md` добавляется header-предупреждение «generated, do not edit».

---

## EPIC B — Phase 1: pull → render (однонаправленный MVP)

### #3 — `board-pull.sh`: тянуть GitHub Issues в issues.json  `P1` `feature`
**Acceptance criteria.**
- [ ] Скрипт через `gh` API забирает issues и пишет `.tasks/issues.json`.
- [ ] **Фильтр скоупа** обязателен: repo + (assignee / label / milestone) — настраивается, чтобы не затащить чужие issue.
- [ ] Обработка **rate limit** (проверка `gh api rate_limit`, бэкофф/понятная ошибка).
- [ ] Пагинация (issues > 100).
- [ ] Идемпотентность: повторный запуск перезаписывает кэш без дублей.

---

### #4 — `board-render.py`: board.json + TODO.md из issues.json  `P1` `feature`
**Acceptance criteria.**
- [ ] Маппит issues → `board.json` по модели состояния из #1.
- [ ] Генерит `TODO.md`, сгруппированный по лейблам статуса.
- [ ] Детерминированный вывод (стабильная сортировка), чтобы diff был чистым.
- [ ] Сохраняет локальные пометки board.json, которых нет в GitHub (если такие вводятся).

---

### #5 — Skill `board` (SKILL.md)  `P1` `feature`
**Acceptance criteria.**
- [ ] `skills/board/SKILL.md` с frontmatter (`name`, `description`).
- [ ] Прописаны правила: todo Claude не хранилище; не стартовать `blocked`/`needs-info`; один `in_progress` для плана оркестратора.
- [ ] Описан флоу pull → read board → select `ready` → внутренний todo.

---

### #6 — Команда `/board-pull`  `P1` `feature`
**Acceptance criteria.**
- [ ] `commands/board-pull.md` вызывает `board-pull.sh` + `board-render.py`.
- [ ] По завершении печатает summary (сколько ready / blocked / total).

---

### #7 — Команда `/board-plan`  `P1` `feature`
**Acceptance criteria.**
- [ ] Читает `board.json`, выбирает только `ready`.
- [ ] Создаёт встроенный todo/task list Claude (Task tools, см. #12).
- [ ] Не трогает `blocked` / `needs-info`.

---

## EPIC C — Phase 4: sync-back (двунаправленная синхронизация — самая рискованная часть)

### #8 — Контракт sync-back: конфликты + идемпотентность  `P1` `design`
**Проблема.** Самое слабое место дизайна описано в одну строку. Без стратегии конфликтов теряются данные.

**Acceptance criteria.**
- [ ] Стратегия конфликтов выбрана и задокументирована (предложение: статус — last-write-wins от агента; тело issue — не перезаписывать, только добавлять комментарий).
- [ ] **Идемпотентность**: маркер «уже синхронизировано» (хэш состояния в скрытом комментарии issue или поле board.json).
- [ ] Поведение при **частичном сбое**: повторный запуск дозавершает, не дублирует.
- [ ] Обнаружение «issue изменили на GitHub пока агент работал» (сравнение `updatedAt`).

---

### #9 — `board-sync-back.sh`: запись результата обратно в GitHub  `P2` `feature`
**Зависит от #8.**
**Acceptance criteria.**
- [ ] Обновляет лейблы статуса по модели #1.
- [ ] Пишет итоговый комментарий в issue (результат/ссылка на PR).
- [ ] Реализует идемпотентность и конфликт-стратегию из #8.
- [ ] Rate limit / бэкофф.

---

### #10 — Команда `/board-sync-back`  `P2` `feature`
**Acceptance criteria.**
- [ ] `commands/board-sync-back.md` вызывает `board-sync-back.sh`.
- [ ] Dry-run режим (показать, что будет записано, без записи).

---

## EPIC D — Исполнение и оркестрация

### #11 — Команда `/board-run-ready` + разрешить конфликт параллелизма  `P2` `feature`
**Проблема.** Дизайн говорит «один `in_progress`», но смысл cmux — параллельные сабагенты.

**Acceptance criteria.**
- [ ] Зафиксировано: один `in_progress` — это план **оркестратора**; реальный параллелизм трекается статусом панелей/`board.json`, не встроенным todo.
- [ ] `/board-run-ready` идёт по `ready`, для каждой задачи: план → назначить агента/cmux workspace → прогресс.
- [ ] Соблюдается лимит параллельных агентов.

---

### #12 — Перейти на Task tools (TaskCreate/Update/Get/List), не TodoWrite  `P2` `tech-debt`
**Проблема.** Дизайн ссылается на переезд `TodoWrite → Task tools` с конкретной версией «v2.1.142» — версию НЕ цитировать без сверки.

**Acceptance criteria.**
- [ ] Перепроверить актуальную доку Claude Code по Task tools перед привязкой API.
- [ ] Использовать Task tools; `TodoWrite` — только fallback для совместимости.
- [ ] Убрать из дизайн-доки непроверенный номер версии или подтвердить его.

---

## EPIC E — Хуки и упаковка

### #13 — hooks.json (SessionStart / Stop / PostToolUse)  `P3` `feature`
**Acceptance criteria.**
- [ ] `SessionStart` → показать board summary.
- [ ] `Stop` → напомнить про sync-back.
- [ ] `PostToolUse` → обновить progress/log.
- [ ] **Убрать** хрупкий `UserPromptSubmit`-триггер по подстроке «run ready» — это делает slash-команда `/board-run-ready`.

---

### #14 — Упаковка плагина (plugin manifest)  `P2` `feature`
**Acceptance criteria.**
- [ ] Структура `skills/`, `commands/`, `scripts/`, `hooks/` собрана в installable-плагин.
- [ ] Манифест плагина валиден; skills/commands обнаруживаются после установки.
- [ ] README с установкой и базовым флоу.

---

## Рекомендованный порядок

1. **#1, #2** (фундамент, P0) — без них всё остальное переделывать.
2. **MVP однонаправленный**: #3 → #4 → #5 → #6 → #7.
3. **#11, #12** — исполнение.
4. **sync-back**: #8 (дизайн) → #9 → #10 — только после проверки базового цикла на реальных issue.
5. **#13, #14** — хуки и упаковка в конце.
