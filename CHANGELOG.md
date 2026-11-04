# CHANGELOG — GGskript v2

Формат: дата — что изменилось (папка бэкапа до правок в `_backup\`, тесты). Пункты 1–47 — [docs/history/PLAN.md](docs/history/PLAN.md).

## [Не опубликовано] 2026-11-04 — подготовка публикации
- Кнопка «❓ Помощь» открывает `docs\HELP.txt` в Блокноте (запасной вариант — `README.md`) и, как раньше, шлёт список команд в Telegram (`Get-HelpDocPath`, тест Item66).
- Документация: `docs\HELP.txt`, пошаговый запуск, раздел «Что должно быть в ответах моделей», лимиты и аккаунты, защиты, Telegram-команды, этот CHANGELOG.
- Очистка для публикации: `.gitignore` расширен (журналы, `logs\`, `answers\`, `_backup*`, `.cursor\`, временные файлы).

## 2026-11-02 — новая серия шагов, чистый журнал (stepseries_logclear, stepseries2)
- Учёт `sent`/`lastBlock` хранит только проект+номер; новый день/чат с `_001` упирался в «S1 уже передавался» / «№1 меньше S9». Добавлены `Test-StepSeriesRestart`, `Reset-StepSeries`, `Invoke-StepSeriesCheck`, `Clear-StaleStepRecords`.
- Журнал: при каждом запуске `relay_log.txt` уходит в `logs\relay_log_<дата>_<время>.txt` (хранятся последние 10); ссылка «очистить журнал» на панели.
- Тесты: Item65.

## 2026-10-27 — sendfix, colors/acct
- Файл прикреплялся, но «Отправить» не нажималось: Gemini обрезает длинное имя чипа по центру — сверка по началу и концу (`Test-ChipMatchesName`). Чипы только из поля ввода; проверка, что запрос с файлом ушёл.
- Панель: одна строка состояния с переносом (`Format-ShortState`), минимальный размер 760×700; цветной журнал (`Get-LogLevel`/`Get-LogColor`).
- Кнопка «🔄 Сменил аккаунт»; проверка аккаунта раз в минуту на остановке по лимиту (`AccountWatch`).
- Тесты: Item63, Item64.

## 2026-10-25 — tabfix, acceptbusy
- Несколько вкладок Gemini (`/u/N`): выбор по фокусу, видимости, Argon и отчётам проекта; лимиты того же аккаунта.
- Проекты с пробелом в имени; миграция учёта (`Repair-StateProjectNames`).
- Ход по факту: пока агент работает — ход IDE.
- Защита от чужого/нового чата Gemini (`ForeignChatGuard`).
- Accept all — сразу при обнаружении, и во время работы агента, с антидребезгом.
- Тесты: Item62.

## 2026-10-24 — любой проект, NoFocus, промпты v2–v4
- Любой префикс проекта в имени отчёта (Item56); NoFocus по умолчанию — `AllowWindowMode=$false`, `GeminiCdpFallback=$false` (Item57).
- Номер шага из имени отчёта в тексте Gemini (Item58); сверка чипа/тела вложения (Item59, Item60); маркеры Argon v2 — step id, «конец задания» (Item61).
- Промпты ARGON v4 и FLASH согласованы.

## 2026-10-22/23 — имена IDE, Cursor
- Имена IDE во всех подписях, журнале и Telegram (`Get-IdeName`), «занят» вместо ошибки — Item54.
- Cursor как третья IDE: CDP 9335, кнопка «🛠 Cursor с портом», селекторы `CursorCdpSelDefault`, автоподтверждение Run/Allow (Item55).

## 2026-10-22 — DeepSeek Harness, выбор IDE (опубликовано, коммит `570d3a5`)
- DeepSeek Harness как вторая IDE (`AgTarget`, `lib\DsHarness.Cdp.ps1`, CDP 9334) — Item51.
- Правая плитка индикатора хода — выпадающий список IDE (только при Стоп) — Item52; протокол запуска по выбранной IDE — Item53.

## 2026-10-21 и раньше
- Лимиты (стоп Antigravity при 1%, Gemini при 100%), Accept all через CDP, индикатор хода, автоподтверждение и др. — см. [docs/history/PLAN.md](docs/history/PLAN.md).
