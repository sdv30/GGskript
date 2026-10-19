# GGskript v2 — карта кода

Что где лежит и за что отвечает. Пути — относительно папки проекта (в примерах `C:\Tools\GGskript`).
Все `.ps1` — UTF-8 с BOM (нужно Windows PowerShell 5.1 для кириллицы), `.bat` — без BOM, CRLF, `.vbs` — ASCII.

## Дерево

```
GGskript\
├─ GGskript.ps1                 воркер: загрузка, тестовые режимы, главный цикл
├─ GGskript_gui.ps1             панель управления (WinForms)
├─ GGskript_launch.vbs          скрытый запуск панели (цель ярлыка)
├─ GGskript.bat                 воркер в консоли (+ параметры, например -teststart)
├─ GGskript_cmd.bat             ввести команду с ПК → commands.txt
├─ GGskript_exit.bat            создать STOP (выключить воркер)
├─ Start-GeminiChrome.bat       отдельный Chrome для Gemini с портом 9222
├─ Start-GeminiBrowser.bat      запасной: Chrome по умолчанию, yandex / edge — аргументом
├─ Start-Antigravity-Debug.bat  Antigravity с портом 9333
├─ Set-TgToken.ps1              сохранить токен Telegram (DPAPI)
├─ Run-Tests.ps1                запуск тестов Pester
├─ GGskript.ico                 значок панели и ярлыка
├─ relay_settings.example.json  пример настроек
├─ relay_config.example.json    пример конфигурации Telegram
├─ README.md                    описание, установка, запуск, тесты
├─ LICENSE                      GNU GPL v3.0
├─ .gitignore, .gitattributes   что не попадает в git; концы строк (ps1 — LF, bat/vbs — CRLF)
├─ docs\                        ARCHITECTURE.md, CODE_MAP.md, DEPENDENCIES.md
│  ├─ images\gui.png            скриншот панели для README (личные данные размыты)
│  └─ history\PLAN.md           история: план доработок v2 (пункты 1–29)
├─ prompts\                     системные промпты: ARGON_SYSTEM_PROMPT.md, FLASH_SYSTEM_PROMPT.md
├─ lib\                         модули (dot-source)
├─ tests\                       Pester-тесты + fixtures\
├─ tools\                       Test-Syntax.ps1 (проверка синтаксиса и BOM)
└─ (рабочие файлы — см. «Рабочее состояние»)
```

## Точки входа

| Файл | Назначение | Ключевое |
|---|---|---|
| `GGskript.ps1` | Воркер. `$Root=$PSScriptRoot`; dot-source `lib\Core.ps1` и затем `State, Platform.Win, Uia, Telegram, Gemini.Uia, Gemini.Cdp, Gemini, Antigravity, Antigravity.Cdp, Relay, Chat, Shutdown`; `Merge-Settings` (дефолты + `relay_settings.json`); мьютекс; чтение состояния `relay_state.json` (первый запуск — существующие файлы считаются обработанными); тестовые режимы (`-testparse`, `-teststart`, `-check`, `-testqueue`, `-testquota`, `-teststatus`, `-testtg`, `-testmodel`, `-testplan`, `-testcopy`, `-testpaste`, `-testag`, `-testgemini`, `-testcdp`); параметр-имя файла — «начать с этого файла»; цикл `while((Invoke-MainStep) -ne 'stop')` | `-testparse` выходит до WinAPI |
| `GGskript_gui.ps1` | Панель. Единственный экземпляр (`GuiMutex`; повторный запуск снимает `PAUSE` и показывает окно). Запускает воркер скрыто (`Start-Worker`), раз в 800 мс читает `relay_log.txt` и `relay_status.json`. Кнопки пишут `PAUSE`/`STOP`/`commands.txt`. Закрытие окна — спросить: остановить или оставить в фоне | `Worker-Alive`, `Start-Worker`, `Send-Cmd`, `Load-LogTail`, `Update-Status` |
| `GGskript_launch.vbs` | `wscript` → `powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "<папка>\GGskript_gui.ps1"`; папка — `WScript.ScriptFullName` | |
| `GGskript.bat` | `chcp 65001`, `powershell … -File "%~dp0GGskript.ps1" %*`, `pause` | |
| `GGskript_cmd.bat` | Спрашивает строку, дописывает в `%~dp0commands.txt` (`echo(!CMD!` — спецсимволы не исполняются) | |
| `GGskript_exit.bat` | `type nul > "%~dp0STOP"` | |
| `Start-GeminiChrome.bat [port]` | Ищет только Google Chrome (Program Files / x86 / LocalAppData), проверяет, кем занят порт, запускает с `--remote-debugging-port`, `--remote-debugging-address=127.0.0.1`, `--user-data-dir=%LOCALAPPDATA%\GGskript\chrome-gemini-profile`, вкладки `gemini.google.com/app` и `/usage` | |
| `Start-GeminiBrowser.bat [port] [chrome\|yandex\|edge]` | Запасной вариант: без аргумента — Chrome (профиль `chrome-gemini-profile`), `yandex` — Яндекс Браузер (`gemini-profile`), `edge` — Microsoft Edge (`edge-gemini-profile`); всё в `%LOCALAPPDATA%\GGskript` | |
| `Start-Antigravity-Debug.bat [port]` | Antigravity (`%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe`) с `--remote-debugging-port=9333`; откажется, если Antigravity уже запущен | |
| `Set-TgToken.ps1 [-FromConfig] [-RemovePlain]` | Скрытый ввод токена → `tg_token.dpapi`, проверка расшифровки; перенос открытого токена из `relay_config.json` | `Protect-Secret`, `Write-AtomicText` |
| `Run-Tests.ps1 [-Tag] [-Safe] [-OutXml]` | Pester из `tools\Pester` (локальная копия, в git не входит) или установленный модуль 5.5–5.99; `-Safe` исключает `Integration`; на Windows исключает `LinuxOnly`, на Linux — `WindowsOnly` | |

## lib\ — модули

| Файл | За что отвечает | Ключевые функции |
|---|---|---|
| `Core.ps1` | Чистая логика без Windows (тестируется на Linux): типизированные исключения `GG.*`; **все настройки по умолчанию** и их слияние; разбор команд; парсеры лимитов и времени сброса; выбор блока кода «Markdown»; ключи содержимого для узнавания вручную отправленных отчётов; выбор окон/вкладок; звуки; время выключения; `PSModulePath` для PS 5.1 | `Get-DefaultSettings`, `Merge-Settings`, `Get-ErrorKind`, `Parse-Command`, `Get-SortKey`, `ConvertFrom-UsageText`, `ConvertFrom-ResetText`, `ConvertFrom-AgQuota`, `Select-CodeBlockIndex`, `Test-CodeLangMatch`, `Find-FileInTexts`, `Get-LastReportFromPrompts`, `Select-GeminiWindow`, `Get-SoundPattern`, `Test-SoundAllowed`, `Resolve-ShutdownTime`, `Repair-PSModulePath` |
| `State.ps1` | Атомарная запись (tmp → `File.Replace` с `.bak`), чтение JSON с откатом на `.bak`, этапы файлов и допустимые переходы, хэши ответов, сжатие учёта, журнал с ротацией | `Write-AtomicText`, `Read-JsonWithBackup`, `Set-FileStage`, `Test-StageTransition`, `Read-RelayState`, `Save-RelayState`, `Compress-RelayState`, `Log`, `Invoke-LogRotate` |
| `Platform.Win.ps1` | WinAPI через `Add-Type` (`GG.Native`): DPI (Per-Monitor V2), окна в Z-порядке, активность пользователя, фокус с возвратом, клавиатура/мышь, зависание окна (WM_NULL), буфер обмена с сохранением всех форматов, мьютексы, DPAPI, QuickEdit, скриншот JPEG, `shutdown.exe` | `Initialize-Platform`, `Get-TopWindows`, `Invoke-WithFocus`, `Wait-UserIdle`, `Use-TempClipboard`, `Test-WindowHung`, `Enter-SingleInstance`, `Protect-Secret`/`Unprotect-Secret`, `Save-ScreenshotJpeg`, `Invoke-ShutdownExe` |
| `Uia.ps1` | Обёртки System.Windows.Automation: поиск, имя/класс/тип, фокус, Invoke, Select, Expand/Collapse, Value | `Initialize-Uia`, `Uia-FindAll`, `Uia-FindFirst`, `Uia-Invoke`, `Uia-GetText` |
| `Telegram.ps1` | Токен (DPAPI или открытый с предупреждением), `chat_id` (сам находит по `telegram_username`), единая точка API, опрос с backoff, дедуп уведомлений, inline-кнопки и постоянная русская клавиатура, длинные тексты частями, файлы, скриншот | `Get-TgToken`, `Invoke-Tg`, `Init-Tg`, `Poll-Tg`, `Tg-Send`, `Notify`, `New-TgKeyboard`, `New-TgReplyKeyboard`, `Tg-SendMsg`, `Tg-SendDocument`, `Send-Screenshot` |
| `Chat.ps1` | Диалоги в Telegram: вопросы с кнопками и таймаутом, текстовые «да/нет», пересылка ответа/отчёта, «напиши», ручной текст в Gemini, сохранение полных ответов в `answers\` | `New-TgPrompt`, `Handle-Callback`, `Resolve-TextAnswer`, `Send-NoCodePrompt`, `Ask-WhereToSend`, `Send-GeminiManual`, `Save-FullAnswer`, `Invoke-ChatAction` |
| `Gemini.ps1` | Фасад `Gem-*` над двумя транспортами; откат CDP→UIA только при недоступном CDP | `Use-GemTransport`, `Gem-Send`, `Gem-WaitAnswer`, `Gem-CopyCode`, `Gem-GetModel`, `Gem-LastReportPrompt`, `Gem-GetUsageText`, `Gem-SelectModel` |
| `Gemini.Uia.ps1` | Gemini через окно браузера: поиск окна/вкладки, поле ввода, генерация, модель, кнопка «Копировать код» только у блока с шапкой «Markdown» в последнем ответе, тексты чата, вкладка лимитов (уже открытая, без Ctrl+T), переключатель модели | `Find-GeminiWindow`, `GemUia-Send`, `GemUia-WaitAnswer`, `GemUia-CopyCode`, `GemUia-PeekAnswer`, `GemUia-LastReportPrompt`, `GemUia-GetUsageText`, `GemUia-SelectModel` |
| `Gemini.Cdp.ps1` | Gemini через DevTools: HTTP `/json`, WebSocket, `Runtime.evaluate` с одним JS-помощником, `Input.insertText`, фоновая вкладка `/usage`, меню моделей. Селекторы переопределяются `CdpSelectors` | `Find-CdpTarget`, `Connect-Cdp`, `Eval-Js`, `GemCdp-Send`, `GemCdp-WaitAnswer`, `GemCdp-GetCode`, `GemCdp-PromptTexts`, `GemCdp-GetUsageText`, `Test-CdpUnreachable` |
| `Antigravity.ps1` | Окно Antigravity, здоровье (hung/nowindow), безопасная вставка UIA (поле пустое, текст не меняется, проверка вставки), диагностика, перезапуск (выключен по умолчанию), почтовый ящик, единая точка `Ag-Send` | `Ag-GetWindow`, `Get-AgHealth`, `Assert-AgReady`, `AgUia-Send`, `Get-AgDiag`, `AgMailbox-Send`, `Check-MailboxAcks`, `Ag-Send` |
| `Antigravity.Cdp.ps1` | Antigravity через DevTools (порт 9333): поле `Message input`, кнопка `send-button`, признак занятости (кнопка Cancel), никогда не жмёт Cancel/Stop | `Connect-AgCdp`, `AgCdp-IsBusy`, `AgCdp-Send`, `AgCdp-ClickText`, `Get-AgCdpDiag` |
| `Relay.ps1` | Сердце: учёт этапов, файлы Downloads, протокол запуска, обработка файла, модель/лимиты, звуки, свежесть ответа, передача в Antigravity, кэш ответов, текст помощи `$HelpText`, команды, Accept all и git-чекпоинт, Pump/Nap, пауза, `commands.txt`, статус для панели, лимиты Antigravity (RPC), автовозобновление, блокирующие окна, недоступность Antigravity, шаг цикла | `Get-Files`, `Next-File`, `Invoke-StartupTriage`, `Test-FileInGemini`, `Process-File`, `Relay-ToAg`, `Handle-Command`, `Run-Action`, `Try-AcceptAll`, `Pump`, `Set-Pause`, `Read-CmdFile`, `Write-Status`, `Start-Procedure`, `Ag-Rpc`, `Get-AgQuota`, `Check-Quotas`, `Invoke-AutoResume`, `Check-Blocking`, `Invoke-MainStep` |
| `Shutdown.ps1` | Выключение ПК по команде: вопрос, подтверждение, план в `relay_shutdown.json`, предупреждение, выполнение/опоздание, отмена | `Request-Shutdown`, `Confirm-Shutdown`, `Cancel-Shutdown`, `Check-Shutdown` |
| `Gui.Core.ps1` | Логика панели без WinForms: хвост журнала, «воркер жив?», запись команды, вид состояния | `Read-LogTail`, `Test-WorkerAlive`, `Send-GuiCmd`, `Get-GuiStateView`, `Get-CloseAction` |

## tests\

| Файл | Что проверяет |
|---|---|
| `_Load.ps1` | Общая загрузка: dot-source всех `lib\*.ps1`, `New-TestCfg`, `GG_NO_BEEP=1`, «предохранители» на буфер, скриншоты, Telegram, DPAPI, `shutdown.exe` (без Mock — исключение) |
| `Item01.*` | Настройки по умолчанию и слияние; синтаксис и BOM всех `.ps1` |
| `Item02`–`Item07` | Antigravity (UIA), фокус, буфер, поиск окон, атомарное состояние, stale |
| `Item08`–`Item10` | Разбор команд, Telegram/DPAPI, классификация ошибок и главный цикл |
| `Item11`–`Item16` | Стабильность файла, лимиты, журнал, панель и мьютексы, запускаторы `.bat/.vbs`, DPI |
| `Item17`–`Item20` | Транспорты и откат CDP, Accept all + git, автовозобновление, зависание Antigravity |
| `Item21`–`Item24` | Telegram-диалоги, русские кнопки, выключение ПК, запуск «только самый новый» |
| `Item25`–`Item28` | Браузеры (Яндекс/Chrome/Edge), протокол запуска, вкладка лимитов, работа без фокуса и узнавание вручную отправленных отчётов, вложения в чате Gemini |
| `Item29.Paths.Tests.ps1` | Нет жёстко прописанного пути проекта; все рабочие файлы — от корня; копия проекта в другой папке запускается (`-testparse`) |
| `fixtures\*.html` | Сохранённые страницы Gemini/Antigravity/usage для тестов CDP-JS и парсеров |

Теги: `ItemNN`, `WindowsOnly`, `LinuxOnly`, `Integration` (исключается `-Safe`).

## prompts\

| Файл | Назначение |
|---|---|
| `ARGON_SYSTEM_PROMPT.md` | Регламент старшей модели Argon: вставляется первым сообщением в чат Gemini. Задаёт аудит отчётов, один шаг плана на промпт и задание для Flash одним блоком Markdown без обратных кавычек |
| `FLASH_SYSTEM_PROMPT.md` | Регламент младшей модели Flash: вставляется первым сообщением в чат агента Antigravity. Задаёт короткий ответ в чат, полный английский отчёт в `Downloads\<Project>_<YYYY-MM-DD>_<NNN>.md`, экономию токенов и запрет выдумывать данные |

Код GGskript эти файлы не читает: их вставляют в модели вручную. Но имя файла отчёта и блок Markdown, которых требуют промпты, это ровно то, что ищет GGskript.

## tools\

| Файл | Назначение |
|---|---|
| `Pester\` | Необязательная локальная копия Pester 5.9.1 (в `.gitignore`; обычно ставится `Install-Module Pester -RequiredVersion 5.9.1 -Scope CurrentUser`) |
| `Test-Syntax.ps1` | Парсер PowerShell + проверка BOM всех `.ps1` (кроме Pester) |

## Рабочее состояние (создаётся и меняется во время работы)

Все — в корне проекта (кроме Downloads и профилей браузера). В git не попадают (`.gitignore`). При переносе папки копировать вместе с кодом.

| Файл / папка | Что это | Пишет |
|---|---|---|
| `relay_settings.json` | Пользовательские настройки (переопределения) | человек |
| `relay_config.json` (+`.bak`) | `telegram_username`, `chat_id`, `blocking_allowlist` (иногда устаревший `telegram_token`) | человек, `Save-TgCfg` |
| `tg_token.dpapi` | Токен бота, зашифрован DPAPI (этот пользователь Windows, этот ПК) | `Set-TgToken.ps1` |
| `relay_state.json` (+`.bak`) | Этапы файлов и хэши переданных ответов | воркер |
| `relay_status.json` | Снимок состояния для панели | воркер |
| `relay_tg_offset.txt` | Offset `getUpdates` Telegram | воркер |
| `relay_log.txt` (+`.1`…`.5`) | Журнал, ротация по `LogMaxMB` | воркер |
| `relay_shutdown.json` | Запланированное выключение ПК | воркер |
| `answers\` | Ответы Gemini до подтверждённой доставки и полные ответы `*.full.md` (до `AnswerKeep`=50) | воркер |
| `inbox\` | Задания режима `AgTransport=mailbox` | воркер, агент |
| `PAUSE` | Флаг «Стоп» (есть — стоит) | панель, воркер, человек |
| `STOP` | Запрос на выход воркера (удаляется при выходе) | панель, `GGskript_exit.bat` |
| `commands.txt` (`.proc`) | Команды с ПК | `GGskript_cmd.bat`, панель |
| `%LOCALAPPDATA%\GGskript\chrome-gemini-profile` | Профиль отдельного Chrome для Gemini (вход в Google) | Chrome |
| `%LOCALAPPDATA%\GGskript\gemini-profile`, `edge-gemini-profile` | Профили отдельного Яндекс Браузера / Edge (если запускать `Start-GeminiBrowser.bat yandex` / `edge`) | браузер |
| `%TEMP%\relay_screen_*.jpg` | Временный скриншот (удаляется после отправки) | воркер |
