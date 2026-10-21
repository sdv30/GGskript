# ===== GGskript v2: Core — чистая логика без Windows-зависимостей (тестируется Pester) =====
# Совместимо с Windows PowerShell 5.1 и PowerShell 7. Файл в UTF-8 с BOM.

# ---------- Типизированные исключения ----------
if(-not ('GG.AgBlockedException' -as [type])){
  # -WarningAction: PS 5.1 предупреждает «в типе нет общих методов» — для классов-исключений это норма
  Add-Type -WarningAction SilentlyContinue -TypeDefinition @"
namespace GG {
  public class RelayException : System.Exception { public RelayException(string m) : base(m) {} }
  public class RelayStopException : RelayException { public RelayStopException() : base("STOP") {} public RelayStopException(string m) : base(m) {} }
  public class RelayLimitException : RelayException { public RelayLimitException(string m) : base(m) {} }
  public class RelayStaleException : RelayException { public RelayStaleException(string m) : base(m) {} }
  public class RelayNoCodeException : RelayException { public RelayNoCodeException(string m) : base(m) {} }
  public class RelayPausedException : RelayException { public RelayPausedException(string m) : base(m) {} }
  public class RelayNotSentException : RelayException { public RelayNotSentException(string m) : base(m) {} }
  // Antigravity не может принять ответ: hung | nowindow | foreign | unknown. Ответ НЕ отправлен (безопасно повторить).
  public class AgBlockedException : RelayNotSentException {
    public string Kind; public string Detail;
    public AgBlockedException(string kind, string m, string detail) : base(m) { Kind=kind; Detail=detail; }
  }
}
"@
}

# ---------- Настройки ----------
function Get-DefaultSettings{
  param([Parameter(Mandatory)][string]$Root,[string]$UserProfile=$env:USERPROFILE)
  if(-not $UserProfile){ $UserProfile=$HOME }
  [ordered]@{
    # ---- как в исходном GGskript.ps1 (значения пользователя сохранены) ----
    Downloads        = (Join-Path $UserProfile 'Downloads')
    Pattern          = '^(?<project>[^\\/:*?"<>|]+?)_(?<date>\d{4}-\d{2}-\d{2})_(?<n>\d{3,})\.md$'
    IgnoreBefore     = '2026-10-18 00:00'
    LogFile          = (Join-Path $Root 'relay_log.txt')
    PollSec          = 3
    StableSec        = 3
    GeminiTitle      = 'Gemini'
    GeminiBrowsers   = @('chrome','browser','msedge')   # пункт 25E: процессы Chromium-браузеров (browser = Яндекс Браузер), порядок не важен — берётся верхнее окно
    GeminiBrowserClassRx = '^Chrome(_Yandex)?_WidgetWin_1$'
    AddressBarClassRx = '(?i)omnibox|smartbox|addressbar|locationbar'   # класс поля адреса: Chrome/Edge OmniboxViewViews, Яндекс SmartboxEditField
    GeminiInputX     = 0.75
    GeminiInputY     = 0.86
    GeminiTimeoutSec = 900
    GeminiQuietSec   = 8
    WaitAfterLastPrompt = $true      # файл в чате без нашей отправки — ждать законченный ответ ПОСЛЕ последнего запроса
    DupAnswerWaitSec = 600         # ответ совпал с уже переданным — ждать НОВЫЙ ответ на отчёт до N сек, потом спросить (0 — спрашивать сразу)
    AgProcess        = @('Antigravity IDE','Antigravity')
    AgInputX         = 0.38
    AgInputY         = 0.93
    RetrySec         = 60
    CodeBlockLang    = 'Markdown,XML'   # подписи подходящих блоков через запятую; Argon иногда подписывает задание из XML-тегов как XML
    CodeBlockPick    = 'last'
    ModelMustContain = 'Argon'
    ModelRecheckSec  = 60
    AcceptAllEverySec= 12
    AgQueueWaitSec   = 30
    AgQueueCheckSec  = 10
    AgQueueMaxTries  = 3
    AgSendNowName    = '^(Send Now|Send now|Отправить сейчас)$'
    AcceptAllName    = '^(Accept all|Принять все)$'
    AutoAllowPrompts = $false       # автоподтверждение запросов разрешения Antigravity («Allow running …?» → «Yes, allow this time» + Submit); флажок в панели / «автоподтверждение вкл|выкл»
    AutoAcceptAll    = $true        # сам нажимать «Accept all» внизу панели агента, когда агент закончил (флажок в панели / «автопринятие вкл|выкл»); «Reject all» — никогда
    AutoAllowEverySec= 3            # как часто проверять запрос разрешения (сек)
    AutoAllowOptionRx= '^\s*(1[\s.)]*)?(Yes,\s*allow this time|Да,\s*разрешить\s+(в этот раз|один раз|сейчас))\s*$'   # ТОЛЬКО разовое разрешение; «always»/«No» отсекаются жёстко в коде
    AutoAllowSubmitRx= '^\s*(Submit|Подтвердить)\s*(\u21B5|\(Enter\))?\s*$'   # в Antigravity кнопка «Submit ↵» (data-testid=interaction-continue-button)
    TgOffsetFile     = (Join-Path $Root 'relay_tg_offset.txt')
    QuotaEveryMin        = 10
    GeminiWebCheck       = $true
    GeminiUsageUrl       = 'https://gemini.google.com/usage'
    UsageTabTitle        = '^(Использование|Лимиты|Usage|Новая вкладка|New Tab|Табло)'
    # Пункт 26: страницу лимитов НЕ открываю новой вкладкой (Ctrl+T) — ищу уже открытую вкладку gemini.google.com/usage в полосе вкладок.
    UsageOpenNewTab      = $false      # $true — прежний способ (Ctrl+T + адрес); только если явно включить
    UsageExistingTabRx   = '(?i)^(Использование|Лимиты|Usage)\b|gemini\.google\.com/usage'
    UsageReloadMin       = 5           # F5 на вкладке лимитов, если с прошлой перезагрузки прошло больше N мин (0 — всегда, -1 — никогда)
    ModelButtonWaitSec   = 3           # ждать кнопку «Выбор режима» после вывода окна на передний план
    # Пункт 27D: перезагрузка вкладки лимитов — кнопкой браузера «Обновить эту страницу» через UIA Invoke (без клавиш);
    # F5 — только запасной путь, если кнопки нет, и только при проверенном переднем окне и вкладке.
    ReloadButtonRx       = '(?i)^(Обновить эту страницу|Перезагрузить( эту страницу)?|Reload( this page)?|Refresh)$'   # точное имя: «Обновить тариф» на странице не подходит
    UsageNoFocus         = $true       # сначала читать лимиты без вывода окна на передний план (UIA Select/Invoke); не вышло — прежний путь с фокусом
    # Пункт 27D: звуки. important — только: остановка по лимиту/модели (1 длинный низкий), ответ без Markdown (2 коротких),
    # ошибка, нужна помощь (3 коротких); off — без звуков; all — ещё 1 короткий высокий после передачи ответа в Antigravity.
    Sounds               = 'important'
    SoundRepeatMin       = 10          # один и тот же звук — не чаще раза в N мин
    GeminiWebThreshold   = 100         # стоп только при полном исчерпании (100% использовано)
    GeminiWebThresholdIs = 'used'
    AgCheck              = $true
    AgGroup              = 'Gemini Models'
    AgThreshold          = 1           # стоп когда осталось 1% или меньше
    AgThresholdIs        = 'remaining'
    QuotaReWarnStep      = 5
    AutoResume           = $true    # после сброса лимита (время со страницы лимитов / Antigravity) перепроверить, вернуть модель ModelMustContain и продолжить
    AutoResumeMarginMin  = 2        # запас после времени сброса, мин
    AutoResumeRetryMin   = 10       # повтор, если время сброса неизвестно или лимит ещё не обновился (растёт x2 после каждой неудачи)
    AutoResumeMaxRetryMin= 60       # потолок интервала повторов
    AutoSwitchModel      = $true    # переключать модель Gemini на ModelMustContain через переключатель модели
    ConfigFile       = (Join-Path $Root 'relay_config.json')
    PauseFile        = (Join-Path $Root 'PAUSE')
    StopFile         = (Join-Path $Root 'STOP')
    StartRetrySec    = 60
    CmdFile          = (Join-Path $Root 'commands.txt')
    StatusFile       = (Join-Path $Root 'relay_status.json')
    # ---- регэкспы UI Gemini (раньше были вне $Cfg) ----
    UploadBtnRx      = '(?i)^(Open upload file menu|Upload file|Add files|Добавить файлы|Открыть меню загрузки( файлов)?|Загрузить файл|Меню загрузки)'   # кнопка «+» у поля Gemini
    UploadItemRx     = '(?i)^(Upload files?|Загрузить файл(ы)?|Файлы|Files)\b'      # пункт меню «+» — файл с компьютера
    RxSend           = '^(Send message|Отправить сообщение|Отправить)$'
    AttachTimeoutSec = 60          # ждать, пока чип файла появится и загрузка закончится
    RxPrompt   = '^(Copy prompt|Скопировать запрос|Копировать запрос)$'
    RxCode     = '^(Copy code|Скопировать код|Копировать код)$'
    RxCopy     = '^(Copy|Копировать|Скопировать)$'
    RxStop     = '^(Stop response|Stop generating|Остановить|Прервать)'
    RxModel    = '^Open mode picker|mode picker|Выбор режима|Выбрать режим'
    ModelMenuSkipRx = '^(Уровень рассуждений|Thinking level|Reasoning level)'   # пункты меню моделей, которые не являются моделями
    ModelSelectedRx = '^(Выбрано|Selected)\s+'
    GeminiInputClassRx = 'ql-editor'
    GeminiInputNameRx  = 'Enter a prompt|Введите запрос|Спросите'
    AgInputName        = 'Message input'
    # ---- новое в v2 ----
    StateJson          = (Join-Path $Root 'relay_state.json')     # единое состояние: этапы + хэши
    TokenFile          = (Join-Path $Root 'tg_token.dpapi')       # токен Telegram, зашифрованный DPAPI
    SettingsFile       = (Join-Path $Root 'relay_settings.json')  # пользовательские переопределения
    WorkerMutex        = 'Local\GGskript_Worker'
    GuiMutex           = 'Local\GGskript_GUI'
    HashKeep           = 200
    StateKeepTerminal  = 500
    LogMaxMB           = 5
    LogKeep            = 5
    LogTextMax         = 300
    StrictCommands     = $true      # опасные команды (стоп/прими/старт) — только точной формой
    TgConfirmAg        = $false     # подтверждать «/ag» и «джемини:» из Telegram ответом «да»
    SafeBtnRx          = '^(ОК|OK|Закрыть|Close|Продолжить|Continue)$'
    AutoCloseProcRx    = ''         # если задано — автозакрытие только для процессов, совпадающих с этим регэкспом
    ScreenshotMode     = 'dialog'   # 'dialog' — только область блокирующего диалога; 'full' — как раньше; 'off'
    AgTransport        = 'uia'      # 'uia' (как раньше, с проверками), 'cdp' (пункт 27B: без фокуса, нужен Start-Antigravity-Debug.bat) или 'mailbox'
    AgCdpPort          = 9333       # порт DevTools Antigravity (Start-Antigravity-Debug.bat)
    AgCdpFallback      = $true      # CDP Antigravity недоступен — отправка через UIA (с фокусом) и одно сообщение в Telegram
    AgCdpSelectors     = @{}        # переопределение селекторов чата Antigravity (см. lib/Antigravity.Cdp.ps1)
    AgInvokeNoFocus    = $true      # пункт 27B: «Accept all» сначала нажимать через UIA Invoke без вывода окна на передний план
    AgCoordFallback    = $false     # клик по координатам, если поле чата не найдено (раньше всегда)
    AgHangTimeoutMs    = 2000       # окно Antigravity не ответило на WM_NULL за столько мс — «зависло»
    AgUiaSlowMs        = 5000       # поиск поля чата через UIA дольше — признак зависания
    AgFieldReads       = 3          # сколько раз читать поле перед вставкой (текст меняется — кто-то печатает)
    AgPlaceholderRx    = '^(Message input|Ask anything.*|Спросите.*)$'   # плейсхолдер/имя поля — не текст
    AgBlockRetrySec    = 30         # повтор доставки, пока Antigravity завис/нет окна (только проверка, без фокуса)
    AgForeignRetrySec  = 120        # повтор, когда в поле чужой текст (каждая попытка ставит фокус в Antigravity)
    AgBlockRemindMin   = 30         # повторное напоминание в Telegram о том же состоянии (0 — не напоминать)
    AgAutoRestartMin   = 0          # >0 — перезапустить зависший Antigravity через N минут (по умолчанию ВЫКЛ)
    AnswerDir          = (Join-Path $Root 'answers')   # сохранённые ответы Gemini до подтверждённой доставки
    # ---- пункт 21: кнопки Telegram, пересылка, свободный текст ----
    TgPromptTimeoutMin = 30         # сколько минут действуют кнопки вопроса (потом «время вышло»)
    TgAwaitTextMin     = 10         # «напиши»: сколько ждать текст
    AgReplyWaitMin     = 30         # «Antigravity: текст»: сколько ждать новый отчёт агента
    TgOfferForward     = $true      # на текст-не-команду спросить «Переслать этот текст? Gemini / Antigravity / Нет»
    TgMaxLen           = 4096       # лимит длины сообщения Telegram
    # ---- пункт 24: запуск без «хвоста» ----
    StartupNewestOnly  = $true      # при запуске (и после паузы ≥ StartupTriagePauseMin) брать только самый новый файл; старые необработанные — этап skipped
    StartupAskNewest   = $true      # самый новый не виден в чате Gemini — спросить в Telegram (Отправить / Не отправлять); $false — отправить сам
    MaxReportAgeHours  = 12         # пункт 43: отчёты старше N часов (по max(LastWriteTime,CreationTime)) автоматически не берутся; 0 — без ограничения
    MirrorRelay        = $true      # постоянный наблюдатель: новый (не передававшийся) блок Markdown в последнем ответе Gemini -> в Antigravity, кто бы ни отправил запрос
    MirrorEverySec     = 15
    AutoDecide         = $true      # автоматический поток решает сам по правилу времени: никаких вопросов в Telegram/панели (только уведомления)
    AutoSendGraceSec   = 60         # перед авто-отправкой отчёта после запуска подождать N сек и перепроверить чат Gemini (вдруг отправлен вручную)
    StartupTriagePauseMin = 0       # после «старт» из паузы не короче N мин — снова только самый новый файл (0 — после любой паузы)
    # ---- пункт 23: выключение компьютера по команде из Telegram ----
    ShutdownEnabled    = $true      # команды «выключи компьютер …» / /shutdown (всегда с подтверждением)
    ShutdownForce      = $false     # $false — выключает сам GGskript в назначенное время (shutdown /s /t 0, без /f: несохранённая работа может помешать);
                                    # $true — таймер Windows shutdown /s /f /t N (сработает и без GGskript, программы закрываются принудительно)
    ShutdownFile       = (Join-Path $Root 'relay_shutdown.json')   # запланированное выключение (переживает перезапуск GGskript)
    ShutdownConfirmMin = 2          # сколько минут ждать «да» на вопрос о выключении (потом — отменено)
    ShutdownNowDelaySec= 60         # «выключи компьютер» без времени — через столько секунд (успеть отменить)
    ShutdownWarnSec    = 60         # предупреждение в Telegram за столько секунд до выключения
    ShutdownLateMin    = 2          # GGskript не работал в назначенное время и опоздал больше — не выключаю, сообщаю
    TgReplyKeyboard    = $true      # пункт 22: постоянная клавиатура с русскими кнопками под полем ввода (стартовое сообщение и «помощь»)
    TgCopyFileAfterParts = 3        # копия ответа длиннее N частей — ещё и файлом .md
    TgCopyMaxMessages  = 10         # не больше N сообщений на одну копию (остальное — в файле)
    WholeCdpFallback   = $true      # весь ответ: кнопка копирования, а если не вышло — текст из DOM через CDP (только чтение)
    AnswerKeep         = 50         # сколько сохранённых полных ответов хранить в answers\
    AgVerifyPaste      = 'strict'   # 'strict' — без подтверждения вставки не отправлять; 'lenient' — если текст поля не читается UIA, отправить как раньше
    InboxDir           = (Join-Path $Root 'inbox')
    MailboxAckSec      = 120
    GeminiTransport    = 'uia'      # 'uia' (как раньше) или 'cdp'
    GeminiCdpFallback  = $true      # пункт 27A: откат на UIA ТОЛЬКО если CDP недоступен (браузер без порта/нет вкладки), с сообщением в Telegram
    CdpPort            = 9222
    CdpRecheckSec      = 300        # CDP недоступен — повторная проверка порта не чаще раза в N с (между ними сразу UIA, без строк в логе)
    CdpUrlLike         = 'gemini.google.com'
    CdpSelectors       = @{}         # переопределение CSS-селекторов страницы Gemini для CDP (см. lib/Gemini.Cdp.ps1, $CdpSelDefault)
    MatchByContent     = $true      # пункт 27C: файл считается уже отправленным в Gemini и по содержимому (вручную отправленные)
    ContentKeyChars    = 120        # сколько букв/цифр с начала файла сравнивать
    ContentKeyMin      = 40         # файл короче — по содержимому не сравниваю
    GeminiSelectTab    = $true      # если вкладка Gemini неактивна — переключиться на неё (UIA)
    IdleSec            = 3          # ждать N сек без ввода пользователя перед перехватом фокуса (0 = выкл.)
    IdleMaxWaitSec     = 60
    RestoreFocus       = $true
    ActivateKey        = 0xE8       # клавиша для разблокировки SetForegroundWindow (0x12 = Alt как раньше, 0 = не жать)
    RestoreClipboard   = $true
    ClipExcludeHistory = $true
    CodeFromWholeFallback = $false  # если нет кнопки «Копировать код» — искать блок в тексте всего ответа
    StableTimeoutSec   = 120
    GitCheckpointRepo  = ''         # путь к git-репозиторию проекта: коммит перед «Accept all»
    GitCheckpointRequired = $false  # $true — не жать Accept all, если коммит не удался
    AcceptAllDuringWait= $false     # жать Accept all / Send Now и во время ожидания ответа Gemini
    UiaPerfAnd         = $true
  }
}

function ConvertTo-PlainHashtable{
  param($InputObject)
  if($null -eq $InputObject){ return $null }
  if($InputObject -is [string] -or $InputObject -is [ValueType]){ return $InputObject }
  if($InputObject -is [System.Collections.IDictionary]){ $h=[ordered]@{}; foreach($k in $InputObject.Keys){ $h[$k]=ConvertTo-PlainHashtable $InputObject[$k] }; return $h }
  if($InputObject -is [System.Management.Automation.PSCustomObject]){ $h=[ordered]@{}; foreach($p in $InputObject.PSObject.Properties){ $h[$p.Name]=ConvertTo-PlainHashtable $p.Value }; return $h }
  if(($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])){ return ,@($InputObject | ForEach-Object { ConvertTo-PlainHashtable $_ }) }
  $InputObject
}

# Сливает пользовательские переопределения (JSON) поверх дефолтов. Неизвестные ключи — в Warnings, не применяются.
function Merge-Settings{
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Defaults,[string]$OverridePath,[System.Collections.IDictionary]$Override)
  $cfg=[ordered]@{}; foreach($k in $Defaults.Keys){ $cfg[$k]=$Defaults[$k] }
  $warn=New-Object System.Collections.Generic.List[string]
  $src=$Override
  if(-not $src -and $OverridePath -and (Test-Path -LiteralPath $OverridePath)){
    try{ $src=ConvertTo-PlainHashtable (Get-Content -LiteralPath $OverridePath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch{ $warn.Add("Не удалось прочитать $($OverridePath): $($_.Exception.Message) — использую настройки по умолчанию") }
  }
  if($src){
    foreach($k in $src.Keys){
      if($k -like '_*'){ continue }   # комментарии вида "_comment"
      if(-not $cfg.Contains($k)){ $warn.Add("Неизвестная настройка '$k' — пропущена"); continue }
      $dv=$Defaults[$k]; $nv=$src[$k]
      if($dv -is [bool] -and -not ($nv -is [bool])){ $warn.Add("Настройка '$k' должна быть true/false — пропущена"); continue }
      if(($dv -is [int] -or $dv -is [double]) -and -not ($nv -is [int] -or $nv -is [long] -or $nv -is [double] -or $nv -is [decimal])){ $warn.Add("Настройка '$k' должна быть числом — пропущена"); continue }
      if($dv -is [array] -and -not ($nv -is [array])){ $nv=@($nv) }
      $cfg[$k]=$nv
    }
  }
  foreach($rx in 'Pattern','RxPrompt','RxCode','RxCopy','RxStop','RxModel','ModelMenuSkipRx','ModelSelectedRx','AgPlaceholderRx','AgSendNowName','AcceptAllName','AutoAllowOptionRx','AutoAllowSubmitRx','UsageTabTitle','UsageExistingTabRx','SafeBtnRx'){
    try{ [void][regex]::new([string]$cfg[$rx]) }catch{ $warn.Add("Настройка '$rx' — некорректный регэксп, верну значение по умолчанию"); $cfg[$rx]=$Defaults[$rx] }
  }
  if($cfg.Pattern -notmatch '\?<project>' -or $cfg.Pattern -notmatch '\?<date>' -or $cfg.Pattern -notmatch '\?<n>'){ $warn.Add("В Pattern нет групп project/date/n — верну значение по умолчанию"); $cfg.Pattern=$Defaults.Pattern }
  foreach($e in @(@('AgVerifyPaste','strict','lenient'),@('AgTransport','uia','cdp','mailbox'),@('GeminiTransport','uia','cdp'),@('CodeBlockPick','last','first'),@('ScreenshotMode','dialog','full','off'),@('Sounds','important','off','all'))){
    if(@($e[1..($e.Count-1)]) -notcontains [string]$cfg[$e[0]]){ $warn.Add("Настройка '$($e[0])'='$($cfg[$e[0]])' не поддерживается — верну '$($Defaults[$e[0]])'"); $cfg[$e[0]]=$Defaults[$e[0]] }
  }
  [pscustomobject]@{ Cfg=$cfg; Warnings=$warn.ToArray() }
}

# Классификация ошибки: stop | limit | stale | nocode | paused | notsent | error
function Get-ErrorKind{
  param($ErrorObject)
  $ex= if($ErrorObject -is [System.Management.Automation.ErrorRecord]){ $ErrorObject.Exception } else { $ErrorObject }
  $seen=0
  while($ex -and $seen -lt 10){
    $seen++
    switch -regex ($ex.GetType().FullName){
      '^GG\.RelayStopException$'    { return 'stop' }
      '^GG\.RelayLimitException$'   { return 'limit' }
      '^GG\.RelayStaleException$'   { return 'stale' }
      '^GG\.RelayNoCodeException$'  { return 'nocode' }
      '^GG\.RelayPausedException$'  { return 'paused' }
      '^GG\.RelayNotSentException$' { return 'notsent' }
      '^GG\.AgBlockedException$'    { return 'agblock' }
    }
    switch([string]$ex.Message){ 'STOP'{ return 'stop' } 'LIMIT'{ return 'limit' } 'OLDANSWER'{ return 'stale' } 'NOCODE'{ return 'nocode' } }
    if($ex -is [System.Management.Automation.RuntimeException] -and $ex.ErrorRecord -and $ex.ErrorRecord.Exception -ne $ex -and $ex.InnerException -eq $null){ $ex=$ex.ErrorRecord.Exception; continue }
    $ex=$ex.InnerException
  }
  'error'
}

# ---------- Текстовые утилиты ----------
function Get-SortKey([string]$Name,[string]$Pattern){
  $m=[regex]::Match($Name,$Pattern); if(-not $m.Success){ return "~$Name" }
  '{0}|{1:D6}|{2}' -f $m.Groups['date'].Value,[int]$m.Groups['n'].Value,$m.Groups['project'].Value
}
function Get-ProjectOf([string]$Name,[string]$Pattern){ $m=[regex]::Match($Name,$Pattern); if($m.Success){ $m.Groups['project'].Value } else { '' } }
function Get-Hash8([string]$Text){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{ (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(([string]$Text).Trim())) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}
function Get-FirstLine([string]$Text,[int]$Max=60){
  $l=(([string]$Text) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1); if(!$l){ return '' }
  $l=$l.Trim(); if($l.Length -gt $Max){ $l=$l.Substring(0,$Max)+'…' }; $l
}
# Пункт 28: есть ли текст (первые $N букв/цифр) в тексте страницы. $null — текст слишком короткий, не сужу.
function Test-TextInBody([string]$Text,[string]$Body,[int]$N=120){
  $k=Get-ContentKey $Text $N; if($k.Length -lt 20){ return $null }
  (Get-ContentKey $Body).Contains($k)
}
function Get-NormKey([string]$Text,[int]$Len=80){ $k=(([string]$Text) -replace '\s+',' ').Trim(); if($k.Length -gt $Len){ $k=$k.Substring(0,$Len) }; $k }
function Get-Marker([string]$Text,[int]$Len=40){
  $l=(([string]$Text) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1); if(!$l){ return '' }
  $l=$l.Trim(); if($l.Length -gt $Len){ $l=$l.Substring(0,$Len) }; $l
}
# Короткая форма длинного текста для лога: первые $Max символов + длина и хэш.
function Format-Short([string]$Text,[int]$Max=300){
  $t=[string]$Text; if($t.Length -le $Max){ return $t }
  "{0}… [{1} симв., хэш {2}]" -f $t.Substring(0,$Max),$t.Length,(Get-Hash8 $t)
}
# Разбиение длинного сообщения Telegram (лимит 4096) на части по строкам; не более $MaxParts частей.
function Split-TgText([string]$Text,[int]$Size=4000,[int]$MaxParts=10){
  $s=[string]$Text; $parts=New-Object System.Collections.Generic.List[string]
  while($s.Length -gt $Size -and $parts.Count -lt ($MaxParts-1)){ $cut=$s.LastIndexOf("`n",$Size); if($cut -lt [int]($Size/4)){ $cut=$Size }; $parts.Add($s.Substring(0,$cut)); $s=$s.Substring($cut).TrimStart("`n") }
  if($s.Length -gt $Size){ $s=$s.Substring(0,$Size-10)+"`n[…обрезано]" }
  $parts.Add($s); ,$parts.ToArray()
}

# ---------- Браузер с Gemini (пункт 25E) ----------
function Get-BrowserName([string]$Proc){
  switch -regex ([string]$Proc){ '^chrome$'{ 'Google Chrome' } '^browser$'{ 'Яндекс Браузер' } '^msedge$'{ 'Microsoft Edge' } '^chromium$'{ 'Chromium' } default{ if($Proc){ $Proc } else { 'браузер' } } }
}
# Заголовок окна без хвоста браузера: « - Google Chrome», « — Яндекс Браузер», « - Yandex Browser», « - Microsoft Edge», а также «, группа X» (группы вкладок).
function Remove-BrowserSuffix([string]$Title){
  $t=[string]$Title
  # Chrome с подсказкой о памяти: «Вкладка "X" использует 350 МБ памяти» / «X - Memory usage - 350 MB»
  $m=[regex]::Match($t,'^\s*(?:Вкладка|Tab)\s+["«“](.+)["»”]\s+(?:использует|is using|uses)\b.*$')
  if($m.Success){ $t=$m.Groups[1].Value }
  $t=$t -replace '\s+[-—–]\s+(?:Использование памяти|Memory usage)\s+[-—–]\s+[\d.,]+\s*\S+\s*$',''
  $t=$t -replace '\s+[-—–]\s+(Google Chrome|Chromium|Яндекс[\s.]?Браузер|Yandex[\s.]?Browser|Яндекс|Yandex|Microsoft\W*Edge|Edge)\s*$',''
  $t=$t -replace ',\s+(группа|group)\s+[^,]*$',''
  $t=$t -replace '\s+(и ещё|and)\s+\d+\s+(страниц\w*|pages?)\s*$',''
  $t.Trim()
}
# ---------- Пункт 27C: узнать файл в чате Gemini по имени или по содержимому (чистая логика) ----------
# Ключ: только буквы и цифры в нижнем регистре (разметка, пробелы, переносы не важны), без строки «Файл отчёта: …».
function Get-ContentKey([string]$Text,[int]$N=0){
  $t=[string]$Text -replace '(?m)^\s*Файл отчёта:\s*\S+\s*$',''
  $k=($t.ToLowerInvariant() -replace '[^\p{L}\p{N}]','')
  if($N -gt 0 -and $k.Length -gt $N){ $k=$k.Substring(0,$N) }
  $k
}
# Пункт 28: имена отчётов в тексте запроса — все «Файл отчёта: имя.md» и строки, равные имени файла (вложение-«чип», с .md или без).
function Get-ReportNamesInText([string]$Text,[string]$Pattern){
  $o=New-Object 'System.Collections.Generic.List[string]'
  foreach($m in [regex]::Matches([string]$Text,'Файл отчёта:\s*(\S+\.md)')){ $v=$m.Groups[1].Value; if(-not $o.Contains($v)){ $o.Add($v) } }
  if($Pattern){ foreach($l in ([string]$Text -split "`r?`n")){ $x=$l.Trim(); if(-not $x){ continue }
      $v= if($x -match $Pattern){ $x } elseif(($x+'.md') -match $Pattern){ $x+'.md' } else { $null }
      if($v -and -not $o.Contains($v)){ $o.Add($v) } } }
  $o.ToArray()
}
# Пункт 28: последний отчёт в чате — из ПОСЛЕДНЕГО по порядку запроса, где он есть; в запросе несколько — самый новый по ключу (дата|номер).
function Get-LastReportFromPrompts([string[]]$Texts,[string]$Pattern){
  $T=@($Texts | ForEach-Object { [string]$_ })
  for($i=$T.Count-1;$i -ge 0;$i--){
    $n=@(Get-ReportNamesInText $T[$i] $Pattern)
    if($n.Count){ return (@($n | Sort-Object { Get-SortKey $_ $Pattern }) | Select-Object -Last 1) }
  }
  $null
}
# $Texts — тексты чата по порядку: для CDP — целые запросы пользователя (-Whole), для UIA — все Text-элементы окна.
# -> $null или @{ how='name'|'content'; index; last } ; last — это последний запрос (CDP) / после него нет других «Файл отчёта: …» (UIA).
function Find-FileInTexts{
  param([string]$Name,[string]$Content,[string[]]$Texts,[switch]$Whole)
  $T=@($Texts | ForEach-Object { [string]$_ }); if(-not $T.Count){ return $null }
  $hdr='Файл отчёта:\s*(\S+\.md)'
  $idx=-1; $how=''
  # по имени: строка «Файл отчёта: <имя>» (так шлёт GGskript) или элемент, равный имени файла (вложение-«чип»). Упоминание имени в ответе Gemini — не в счёт.
  if($Name){
    $base=$Name -replace '\.md$',''
    for($i=$T.Count-1;$i -ge 0;$i--){
      $x=$T[$i].Trim()
      # пункт 28: все заголовки и строки-«чипы» запроса (в одном запросе может быть несколько вложений)
      # (UIA: элементы — и ответы Gemini тоже, поэтому там строки-«чипы» внутри текста не считаю, только заголовки и точное равенство)
      $nm=@(Get-ReportNamesInText $x $(if($Whole){ $Cfg.Pattern } else { '' }))
      if($x -ieq $Name -or $x -ieq $base -or ($nm -contains $Name)){ $idx=$i; $how='name'; break }
    }
  }
  if($idx -lt 0 -and $Content -and $Cfg.MatchByContent){
    $key=Get-ContentKey $Content ([int]$Cfg.ContentKeyChars)
    if($key.Length -ge [int]$Cfg.ContentKeyMin){
      if($Whole){ for($i=$T.Count-1;$i -ge 0;$i--){ if((Get-ContentKey $T[$i]).Contains($key)){ $idx=$i; $how='content'; break } } }
      else{
        # UIA: текст запроса разбит на много элементов — склеиваю ключи и нахожу, в каком элементе начинается совпадение
        $sb=New-Object Text.StringBuilder; $starts=New-Object 'System.Collections.Generic.List[int]'
        foreach($x in $T){ $starts.Add($sb.Length); [void]$sb.Append((Get-ContentKey $x)) }
        $pos=$sb.ToString().LastIndexOf($key,[StringComparison]::Ordinal)
        if($pos -ge 0){ for($i=$starts.Count-1;$i -ge 0;$i--){ if($starts[$i] -le $pos){ $idx=$i; break } }; $how='content' }
      }
    }
  }
  if($idx -lt 0){ return $null }
  $last=$true
  if($Whole){ $last=($idx -eq $T.Count-1) }
  else{ for($i=$idx+1;$i -lt $T.Count;$i++){ $mm=[regex]::Match($T[$i],$hdr); if($mm.Success -and $mm.Groups[1].Value -ne $Name){ $last=$false; break } } }
  @{ how=$how; index=$idx; last=[bool]$last }
}
# ---------- Пункт 26: вкладки лимитов/чата (чистая логика над списком @{name;el}) ----------
function Test-UsageTabName([string]$Name){ $n=Remove-BrowserSuffix $Name; [bool]($n -and $Cfg.UsageExistingTabRx -and $n -match $Cfg.UsageExistingTabRx) }
function Select-UsageTab([object[]]$Tabs){ @($Tabs | Where-Object { $_ -and (Test-UsageTabName ([string]$_.name)) }) | Select-Object -First 1 }
function Select-ChatTab([object[]]$Tabs,[string]$ChatName){
  $c=@($Tabs | Where-Object { $_ -and -not (Test-UsageTabName ([string]$_.name)) })
  $x=@($c | Where-Object { $ChatName -and (Remove-BrowserSuffix ([string]$_.name)) -eq $ChatName }) | Select-Object -First 1
  if($x){ return $x }
  @($c | Where-Object { (Remove-BrowserSuffix ([string]$_.name)) -like "*$($Cfg.GeminiTitle)*" }) | Select-Object -First 1
}
# Нужна ли перезагрузка (F5) вкладки лимитов: данные не прочитаны или с прошлой F5 прошло UsageReloadMin мин.
function Test-UsageStale([string]$Text,$LastReload,[datetime]$Now=(Get-Date)){
  $min=[double]$Cfg.UsageReloadMin
  if($min -lt 0){ return $false }
  if(-not (Test-UsageTextReady $Text)){ return $true }
  if(-not $LastReload){ return $true }
  (($Now-[datetime]$LastReload).TotalMinutes -ge $min)
}
# Пункт 27D: звуковые сигналы (чистые функции — тестируются без динамика)
# Шаблон — строка «частота:мс» через запятую; Get-SoundTones разбирает её в список @{f;ms}.
function Get-SoundPattern([string]$Kind){
  switch($Kind){
    'limit'  { '392:900' }                     # 1 длинный низкий
    'nocode' { '880:160,880:160' }             # 2 коротких
    'error'  { '988:120,988:120,988:120' }     # 3 коротких
    'info'   { '1320:90' }                     # 1 короткий высокий (только Sounds=all)
    default  { '' }
  }
}
function Get-SoundTones([string]$Kind){
  @(([string](Get-SoundPattern $Kind)) -split ',' | Where-Object { $_ } | ForEach-Object { $p=$_ -split ':'; @{ f=[int]$p[0]; ms=[int]$p[1] } })
}
function Test-SoundAllowed([string]$Kind,[string]$Mode,$LastAt,[datetime]$Now=(Get-Date),[double]$RepeatMin=10){
  $m=([string]$Mode).ToLower(); if(-not $m){ $m='important' }
  if($m -eq 'off'){ return $false }
  if($Kind -notin @('limit','nocode','error','info')){ return $false }
  if($Kind -eq 'info' -and $m -ne 'all'){ return $false }
  if($LastAt -and $RepeatMin -gt 0 -and (($Now-[datetime]$LastAt).TotalMinutes -lt $RepeatMin)){ return $false }
  $true
}
function Test-UsageTextReady([string]$Text){ [bool]($Text -match '(Недельный лимит|Weekly limit).*?(Использовано|Used)\s*\d+') }
function Get-GeminiBrowsers{ @(@($Cfg.GeminiBrowsers) | ForEach-Object { ([string]$_ -split '[,;\s]+') } | Where-Object { $_ } | ForEach-Object { $_ -replace '\.exe$','' }) }
# Окно браузера, в котором АКТИВНА вкладка Gemini (верхнее по Z-порядку из всех разрешённых браузеров). -> объект окна или $null
function Select-GeminiWindow([object[]]$Windows){
  $br=@(Get-GeminiBrowsers)
  foreach($w in @($Windows)){
    if(-not $w -or -not $w.h){ continue }
    if($br.Count -and ($br -notcontains [string]$w.proc)){ continue }
    if([string]$w.class -notmatch $Cfg.GeminiBrowserClassRx){ continue }
    $t=Remove-BrowserSuffix $w.title
    if(-not $t -or $t -notlike "*$($Cfg.GeminiTitle)*"){ continue }
    if($Cfg.UsageTabTitle -and $t -match $Cfg.UsageTabTitle){ continue }
    return $w
  }
  $null
}
# Окна разрешённых браузеров с непустым заголовком (кандидаты, где искать вкладку Gemini)
function Get-BrowserWindows([object[]]$Windows){ $br=@(Get-GeminiBrowsers); @($Windows | Where-Object { $_ -and $_.h -and (-not $br.Count -or $br -contains [string]$_.proc) -and [string]$_.class -match $Cfg.GeminiBrowserClassRx -and ([string]$_.title).Trim() }) }

# ---------- Выбор окна (чистая логика над списком окон) ----------
# $Windows — объекты @{h;title;class;proc} в Z-порядке (первое — верхнее).
function Select-TopWindow{
  param([object[]]$Windows,[string[]]$ProcessNames,[string]$TitleLike,[string]$ClassRx,[string]$ExcludeTitleRx)
  foreach($w in @($Windows)){
    if(-not $w -or -not $w.h){ continue }
    if($ProcessNames -and (@($ProcessNames) -notcontains [string]$w.proc)){ continue }
    if($ClassRx -and ([string]$w.class -notmatch $ClassRx)){ continue }
    if($TitleLike -and ([string]$w.title -notlike $TitleLike)){ continue }
    if($ExcludeTitleRx -and ([string]$w.title -match $ExcludeTitleRx)){ continue }
    if(-not ([string]$w.title).Trim()){ continue }
    return $w
  }
  $null
}

# ---------- Блоки кода ----------
# Индекс нужного блока по списку языков: $Lang='' — любой; $Pick 'last'|'first'. -1 — нет.
# Пункт 25D: подпись блока -> первая непустая строка, пробелы схлопнуты; слишком длинная (это уже код, а не подпись) -> ''.
function Normalize-CodeLang([string]$Label){
  if(-not $Label){ return '' }
  $l=@(($Label -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Select-Object -First 1
  if(-not $l){ return '' }; $l=([string]$l -replace '\s+',' ').Trim()
  if($l.Length -gt 40){ return '' }; $l
}
# Блок подходит, только если подпись (без учёта регистра и пробелов по краям) равна одной из нужных (список через запятую). Пустая/нечитаемая подпись — НЕ Markdown.
# Пустой $Lang в настройках НЕ означает «любой блок»: всегда Markdown.
function Test-CodeLangMatch([string]$Label,[string]$Lang){
  $want=@(([string]$Lang) -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); if(-not $want.Count){ $want=@('Markdown') }
  $l=Normalize-CodeLang $Label; if(-not $l){ return $false }
  foreach($w in $want){ if($l -ieq $w){ return $true } }; $false
}
function Select-CodeBlockIndex([string[]]$Langs,[string]$Lang,[string]$Pick='last'){
  $idx=@(); for($i=0;$i -lt @($Langs).Count;$i++){ if(Test-CodeLangMatch ([string]$Langs[$i]) $Lang){ $idx+=$i } }
  if(-not $idx.Count){ return -1 }
  if($Pick -eq 'first'){ $idx[0] } else { $idx[-1] }
}
# Блоки ```lang … ``` (и ~~~) из Markdown-текста: массив @{lang;code}. Закрывающий забор — тот же символ, длина не меньше.
function Get-FencedBlocks([string]$Text){
  $res=New-Object System.Collections.Generic.List[object]; $open=$null; $buf=$null; $lang=''
  foreach($line in ([string]$Text -split "`r?`n")){
    if($null -eq $open){
      $m=[regex]::Match($line,'^\s{0,3}(`{3,}|~{3,})\s*([^\s`]*)')
      if($m.Success){ $open=$m.Groups[1].Value; $lang=$m.Groups[2].Value; $buf=New-Object System.Collections.Generic.List[string] }
    } else {
      $m=[regex]::Match($line,'^\s{0,3}(`{3,}|~{3,})\s*$')
      if($m.Success -and $m.Groups[1].Value[0] -eq $open[0] -and $m.Groups[1].Value.Length -ge $open.Length){ $res.Add([pscustomobject]@{ lang=$lang; code=($buf -join "`n") }); $open=$null }
      else { $buf.Add($line) }
    }
  }
  ,$res.ToArray()
}
function Get-MarkdownBlock([string]$Text,[string]$Lang='Markdown',[string]$Pick='last'){
  $b=@(Get-FencedBlocks $Text | ForEach-Object { $_ }); if(-not $b.Count){ return $null }   # пункт 25D: раньше @(,массив) давал один элемент — при 2+ блоках ничего не находилось
  $i=Select-CodeBlockIndex -Langs @($b | ForEach-Object { $_.lang }) -Lang $Lang -Pick $Pick
  if($i -lt 0){ return $null }; $b[$i].code
}
function Test-GeminiErrorText([string]$Text){
  [bool]($Text -match '(?i)(something went wrong|что-то пошло не так|произошла ошибка|попробуйте (ещё|еще) раз|try again later|network error|ошибка сети|i''m having a hard time|не удалось (получить|сгенерировать) ответ|an error occurred)')
}

# ---------- Команды (Telegram / ПК) ----------
function Test-EchoNoise([string]$Line){ [bool]($Line.Trim() -match '^(ECHO is (on|off)\.?|Режим вывода команд на экран \(ECHO\) (включен|отключен)\.?)$') }
# Разбор команды. $HasDialog — есть активное блокирующее окно. $Strict — опасные команды только точной формой.
# Возвращает @{ k=...; arg; whole; idx; button }.
# Разбиение для Telegram: части ≤ Max (UTF-16 единиц) по абзацам, затем по строкам, затем по пробелу; суррогатная пара
# не рвётся. Ничего не обрезается (в отличие от Split-TgText).
function Split-TgParagraphs([string]$Text,[int]$Max=4096){
  $s=([string]$Text) -replace "`r`n","`n"; $parts=New-Object System.Collections.Generic.List[string]
  if($Max -lt 16){ $Max=16 }
  $O=[StringComparison]::Ordinal; $min=[int]($Max/4)
  while($s.Length -gt $Max){
    $cut=$s.LastIndexOf("`n`n",$Max-1,$O); $skip=2
    if($cut -lt $min){ $cut=$s.LastIndexOf("`n",$Max-1,$O); $skip=1 }
    if($cut -lt $min){ $cut=$s.LastIndexOf(' ',$Max-1,$O); $skip=1 }
    if($cut -lt $min){ $cut=$Max; $skip=0; if([char]::IsHighSurrogate($s[$cut-1])){ $cut-- } }
    $parts.Add($s.Substring(0,$cut)); $s=$s.Substring($cut+$skip)
    if($skip){ $s=$s.TrimStart("`n") }
  }
  if($s.Length -or -not $parts.Count){ $parts.Add($s) }
  $parts.ToArray()   # вызывать как @(Split-TgParagraphs ...)
}
# ---- Пункт 23: время выключения (чистые функции) ----
# Хвост команды после «выключи компьютер» -> @{mode='now'|'at'|'in'|'bad'; h; m; min}
# «» / «сейчас» -> now; «в 14-00» «в 14:00» «в 14.00» «в 14» «14:00» «в 9 часов» -> at; «через 30 минут» «через 2 часа» «через час» «через полчаса» «через 1 ч 30 мин» «+15» -> in.
function ConvertFrom-ShutdownTail([string]$Tail){
  $t=((([string]$Tail).ToLower() -replace 'ё','е') -replace '\s+',' ').Trim().TrimEnd('.','!')
  if(-not $t -or $t -match '^(сейчас|прямо сейчас|немедленно|now)$'){ return @{mode='now'} }
  if($t -match '^(?:(?:в|на|at)\s*)?(\d{1,2})(?:\s*[:\-.]\s*(\d{2}))?(?:\s*(?:час\w*|ч\.?))?$'){
    $h=[int]$matches[1]; $m= if($matches[2]){ [int]$matches[2] } else { 0 }
    if($h -gt 23 -or $m -gt 59 -or ($t -notmatch '^(в|на|at)' -and -not $matches[2])){ return @{mode='bad'; raw=$Tail} }   # «14» без «в» — непонятно
    return @{mode='at'; h=$h; m=$m}
  }
  $d=$null
  if($t -match '^\+\s*(\d+)$'){ $d=[double]$matches[1] }
  elseif($t -match '^(?:через|in)\s+(.+)$'){
    $r=$matches[1].Trim(); $d=0; $ok=$false
    if($r -match '^пол\s*часа$'){ $d=30; $ok=$true }
    elseif($r -match '^час(а|ов)?$'){ $d=60; $ok=$true }
    elseif($r -match '^(\d+)$'){ $d=[double]$matches[1]; $ok=$true }
    else{
      $hm=[regex]::Match($r,'(\d+(?:[.,]\d+)?)\s*(?:час\w*|ч\.?|h)'); $mm=[regex]::Match($r,'(\d+)\s*(?:минут\w*|мин\w*|м\.?|m)')
      $rest=$r
      if($hm.Success){ $d+=60*[double]($hm.Groups[1].Value -replace ',','.'); $ok=$true; $rest=$rest.Remove($hm.Index,$hm.Length).Insert($hm.Index,' ') }
      if($mm.Success){ $i=$rest.IndexOf($mm.Value); if($i -ge 0){ $d+=[double]$mm.Groups[1].Value; $ok=$true; $rest=$rest.Remove($i,$mm.Length) } }
      if((($rest -replace '(^|\s)(и|and)(?=\s|$)',' ') -replace '[\s,]','')){ $ok=$false }   # лишние слова/цифры — не угадываю
    }
    if(-not $ok){ return @{mode='bad'; raw=$Tail} }
  }
  if($null -ne $d){ if($d -lt 1 -or $d -gt 5256000){ return @{mode='bad'; raw=$Tail} }; return @{mode='in'; min=[math]::Round($d)} }   # ≤ 10 лет (предел shutdown /t)
  @{mode='bad'; raw=$Tail}
}
# Спецификация -> @{at; tomorrow}. «в HH:MM» — ближайшее такое время: уже прошло сегодня -> завтра.
function Resolve-ShutdownTime($Spec,[datetime]$Now=(Get-Date),[int]$NowDelaySec=60){
  switch($Spec.mode){
    'now' { return @{ at=$Now.AddSeconds($NowDelaySec); tomorrow=$false } }
    'in'  { return @{ at=$Now.AddMinutes([double]$Spec.min); tomorrow=($Now.AddMinutes([double]$Spec.min).Date -gt $Now.Date) } }
    'at'  { $at=$Now.Date.AddHours($Spec.h).AddMinutes($Spec.m); $tm=$false; if($at -le $Now){ $at=$at.AddDays(1); $tm=$true }; return @{ at=$at; tomorrow=$tm } }
  }
  $null
}
function Format-ShutWhen([datetime]$At,[datetime]$Now=(Get-Date)){
  $hm=$At.ToString('HH:mm')
  if($At.Date -eq $Now.Date){ "сегодня в $hm" } elseif($At.Date -eq $Now.Date.AddDays(1)){ "завтра ($($At.ToString('dd.MM'))) в $hm" } else { "$($At.ToString('dd.MM.yyyy')) в $hm" }
}
function Format-ShutLeft([datetime]$At,[datetime]$Now=(Get-Date)){
  $s=[math]::Max(0,[math]::Round(($At-$Now).TotalSeconds)); if($s -lt 90){ return "$s сек" }
  $m=[math]::Round($s/60); if($m -lt 60){ return "$m мин" }; $h=[math]::Floor($m/60); "$h ч $($m-60*$h) мин"
}
function Parse-Command{
  param([string]$Text,[bool]$HasDialog=$false,[bool]$Strict=$true)
  $t=([string]$Text).Trim()
  if(-not $t -or (Test-EchoNoise $t)){ return @{k='unknown'} }
  $t=($t -replace '^(?:[^\p{L}\p{N}/!]|\u2139)+','').Trim()   # эмодзи кнопки («📂 », «✨ »…) не важны
  if(-not $t){ return @{k='unknown'} }
  $n=($t.ToLower() -replace 'ё','е')
  $gem='(?:дж?[еиы]м[еиы]н[иы]\w*|г[еи]м[еи]н[иы]\w*|gemini\w*|аргон\w*|старш\w*)'
  $ag='(?:анти\s*-?\s*гр\w*|antigravity\w*|младш\w*)'
  $verb='(?:напиши|написать|отправь|отправить|скажи|спроси|передай|пошли)'
  $end='\s*[.!]*\s*$'
  # кнопки «Gemini: текст» / «Antigravity: текст» и /gemini, /ag без текста — бот попросит текст
  if($t -match '^/gemini(?:@\S+)?\s*$' -or $n -match "^\s*$gem\s*:\s*текст$end"){ return @{k='gemwrite'} }
  if($t -match '^/ag(?:@\S+)?\s*$' -or $n -match "^\s*$ag\s*:\s*текст$end"){ return @{k='agwrite'} }
  if($n -match "^\s*отч[еe]т\s+(?:снова\s+)?в\s+$gem$end"){ return @{k='fwdrep'} }
  if($n -match "^\s*(?:весь\s+)?ответ\s+(?:gemini\s+)?в\s+$ag$end"){ return @{k='fwdans'} }
  if($n -match "^\s*ответ\s+$gem$end"){ return @{k='lastanswer'} }
  if($t -match '(?s)^/gemini(?:@\S+)?\s+(.+)$'){ return @{k='gemini';arg=$matches[1].Trim()} }
  if($t -match '(?s)^/ag(?:@\S+)?\s+(.+)$'){ return @{k='ag';arg=$matches[1].Trim()} }
  if($t -match '^!asknocode\s+(\S+)\s*$'){ return @{k='asknocode'; arg=$matches[1]} }   # служебная (только с ПК, commands.txt)
  # ---- пункт 23: выключение компьютера (раньше правил «стоп»/«выключи» и отрицаний «не выключ…») ----
  $pcw='(?:компьютер\w*|комп\w*|пк|pc|ноутбук\w*)'
  if($t -match '^/shutdown_cancel(?:@\S+)?\s*$' -or $n -match "^\s*(?:отмени(?:ть)?|отменяй|отмена|стоп)\s+выключени\w*(?:\s+$pcw)?$end" -or $n -match "^\s*не\s+(?:выключай|выключать|выключи)(?:\s+$pcw)?$end"){ return @{k='shutdowncancel'} }
  if($t -match '^/shutdown_status(?:@\S+)?\s*$' -or $n -match "^\s*когда\s+(?:будет\s+)?(?:выключени\w*|выключ\w*\s+$pcw)\s*[.!?]*\s*$" -or $n -match "^\s*(?:статус|план)\s+выключени\w*\s*[.!?]*\s*$"){ return @{k='shutdownstatus'} }
  if($t -match '^/shutdown(?:@\S+)?(?:\s+(.*))?$'){ $tl=([string]$matches[1]).Trim().ToLower()
    if($tl -match '^(cancel|отмена|abort)$'){ return @{k='shutdowncancel'} }; if($tl -match '^(status|статус)$'){ return @{k='shutdownstatus'} }
    return @{k='shutdown'; spec=(ConvertFrom-ShutdownTail $tl)} }
  if($n -match "^\s*(?:пожалуйста,?\s+)?(?:выключи(?:ть)?|выруби(?:ть)?|отключи(?:ть)?)\s+$pcw(?:\s+(.*?))?\s*[.!]*\s*$"){ return @{k='shutdown'; spec=(ConvertFrom-ShutdownTail ([string]$matches[1]))} }
  # автопринятие «Accept all»: «автопринятие вкл|выкл», /autoaccept on|off
  if($t -match '^/autoaccept(?:@\S+)?(?:\s+(\S+))?\s*$' -or $n -match "^\s*авто\s*-?\s*приняти\w*(?:\s+(\S+))?$end"){
    $a=[string]$matches[1]
    if($a -match '^(вкл\w*|on|да|1)$'){ return @{k='autoaccept'; on=$true} }
    if($a -match '^(выкл\w*|откл\w*|off|нет|0)$'){ return @{k='autoaccept'; on=$false} }
    return @{k='autoaccept'; on=$null}
  }
  # автоподтверждение запросов разрешения Antigravity: «автоподтверждение вкл|выкл», /autoallow on|off; без аргумента — состояние
  if($t -match '^/autoallow(?:@\S+)?(?:\s+(\S+))?\s*$' -or $n -match "^\s*авто\s*-?\s*подтвержд\w*(?:\s+(\S+))?$end"){
    $a=([string]$matches[1]).ToLower() -replace 'ё','е'
    if(-not $a){ return @{k='autoallow'; on=$null} }
    if($a -match '^(вкл\w*|on|да|1)$'){ return @{k='autoallow'; on=$true} }
    if($a -match '^(выкл\w*|откл\w*|off|нет|0)$'){ return @{k='autoallow'; on=$false} }
    return @{k='autoallow'; on=$null}
  }
  if($n -match '^\s*(да|yes|подтверждаю|ок,?\s*отправляй)\s*[.!]*\s*$'){ return @{k='confirm'} }
  if($n -match '^\s*(нет|no|отмена|cancel|/cancel)\s*[.!]*\s*$'){ return @{k='cancel'} }
  $fw='(?:перешли|переслать|пересылай)'
  if($t -match '^/toag(?:@\S+)?\s*$' -or $n -match "^\s*$fw\s+(?:последний\s+)?ответ\s+(?:в\s+)?$ag$end"){ return @{k='fwdans'} }
  if($t -match '^/togemini(?:@\S+)?\s*$' -or $n -match "^\s*$fw\s+(?:последний\s+)?(?:ответ|отч[еe]т)\s+(?:в\s+)?$gem$end"){ return @{k='fwdrep'} }
  if($n -match "^\s*(?:$fw|передай|отправь)\s+(?:последний\s+)?(?:файл|отч[еe]т)(?:\s+отч[еe]та)?\s+(?:в\s+)?$gem$end"){ return @{k='fwdrep'} }
  if($t -match '(?s)^/send(?:@\S+)?\s+(.+)$'){ return @{k='write'; arg=$matches[1].Trim()} }
  if($t -match '^/send(?:@\S+)?\s*$' -or $n -match "^\s*напиши$end"){ return @{k='write'} }
  if($n -match '^\s*список\s+окон|^/windows'){ return @{k='dlglist'} }
  if($n -match 'убери\s+из\s+списк\w*\s+(\d+)'){ return @{k='dlgremove'; idx=[int]$matches[1]} }
  if($HasDialog){
    if($n -match 'разрешай\s+так\w*|разреши\s+так\w*'){ return @{k='allowdlg'} }
    if($n -match 'добав\w*\s+в\s+список\s+(.+)$'){ return @{k='allowdlg'; button=$t.Substring($t.Length-$matches[1].Length).Trim()} }
    if($n -match '^\s*нажм\w+\s+(.+)$' -and ($matches[1].Trim() -notmatch '^(принять|accept|все|всё|всех)')){ return @{k='clickdlg'; button=$t.Substring($t.Length-$matches[1].Length).Trim()} }
  }
  if($n -match 'что\s+(?:он\s+|там\s+)?(?:ответил|сказал|написал|пишет)|последний\s+ответ|/answer'){ return @{k='lastanswer'} }
  if($t -match "(?s)^\s*(?:$verb\s+)?(?:в\s+|для\s+)?$gem\s*[:,\-—]\s*(.+)$" -or $t -match "(?s)^\s*$verb\s+(?:в\s+|для\s+)?$gem\s+(.+)$"){ return @{k='gemini';arg=$matches[1].Trim()} }
  if($t -match "(?s)^\s*(?:$verb\s+)?(?:в\s+|для\s+)?$ag\s*[:,\-—]\s*(.+)$" -or $t -match "(?s)^\s*$verb\s+(?:в\s+|для\s+)?$ag\s+(.+)$"){ return @{k='ag';arg=$matches[1].Trim()} }
  if($n -match '^\s*(передай\s+(вс[её]\s+равно|принудительно)|/force)\b'){ return @{k='force'} }
  if($n -match '^\s*(отправь\s+заново|/resend)\s*[.!]*\s*$'){ return @{k='resendstale'} }
  if($n -match 'перед[ао]\w*.*ответ|/relay'){ return @{k='relay';whole=[bool]($n -match 'вес[ьй]|целиком|полност|/relay\s+all')} }
  if($Strict){
    if($n -match '^\s*(скрин\w*|скриншот\w*|/shot|покажи\s+экран|сделай\s+(скрин\w*|снимок\s+экрана))\s*[.!?]*\s*$'){ return @{k='shot'} }
  } elseif($n -match 'скрин|экран|screen|/shot'){ return @{k='shot'} }
  if($n -match '^/start|^/help|помощ|помоги|help|что\s+умеешь|команды'){ return @{k='help'} }
  if($n -match 'лимит|квот|/limits'){ return @{k='limits'} }
  $neg='(^|[\s,])не\s+(стоп|останав|выключ|пауз|прими|принима|продолж|старт)'
  if($n -match $neg){ return @{k='unknown'} }
  if($n -match 'пауз|на\s+время|подожди|приостан|/pause'){ return @{k='pause'} }
  if($Strict){
    # пункт 25C: «выключи скрипт» — завершить процесс (с подтверждением); «стоп» — остановиться, но слушать Telegram
    if($n -match "^\s*(/exit|(выключи|заверши|закрой)\s+(скрипт|реле|ggskript|бота)(\s+совсем)?|заверши\s+работу(\s+скрипта)?)$end"){ return @{k='exit'} }
    if($n -match "^\s*(/stop|стоп|выключи(сь)?|выключайся|остановись|останови\s+(скрипт|реле|ggskript|работу))$end"){ return @{k='stop'} }
    if($n -match "^\s*(/resume|продолжа\w*|продолжи|старт|возобнови\w*|поехали|запускай(ся)?)$end"){ return @{k='resume'} }
    if($n -match "^\s*(/accept|прими(\s+вс[её])?|нажми\s+(принять|accept)(\s+(вс[её]|all))?|accept(\s+all)?)$end"){ return @{k='accept'} }
  } else {
    if($n -match '(выключи|заверши|закрой)\s+(скрипт|реле|ggskript|бота)|заверши\s+работу|/exit'){ return @{k='exit'} }
    if($n -match 'стоп|выключ|останов|заверш|/stop'){ return @{k='stop'} }
    if($n -match 'продолж|старт|возобнов|запусти|поехали|/resume'){ return @{k='resume'} }
    if($n -match 'прими|принять|прин[яе]л|accept|/accept'){ return @{k='accept'} }
  }
  if($n -match 'статус|происход|что\s+сейчас|как\s+дела|как\s+ты|состояни|/status'){ return @{k='status'} }
  @{k='unknown'}
}
# Байты commands.txt -> строки команд: строгий UTF-8 (с BOM или без), иначе cp866 (cmd без chcp 65001); шум ECHO отбрасывается.
function Get-Cp866{ try{ [Text.Encoding]::GetEncoding(866) }catch{ [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance); [Text.Encoding]::GetEncoding(866) } }
function ConvertFrom-CommandBytes([byte[]]$Bytes){
  if(-not $Bytes -or $Bytes.Length -eq 0){ return }
  $strict=New-Object System.Text.UTF8Encoding($false,$true)
  try{ $s=$strict.GetString($Bytes) }catch{ $s=(Get-Cp866).GetString($Bytes) }
  $s=$s.TrimStart([char]0xFEFF)
  # Возвращает строки по одной в конвейер (вызывающий собирает @(...))
  $s -split "`r?`n" | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } | Where-Object { $_ -and -not (Test-EchoNoise $_) }
}
# ---------- Диалоги ----------
function Test-ButtonMatch([string]$Name,[string]$Wanted){ ($Name.Trim() -ieq $Wanted.Trim()) -and $Wanted.Trim() }
function Select-SafeButton([string[]]$Buttons,[string]$SafeRx){ @($Buttons | Where-Object { $_ -match $SafeRx }) | Select-Object -First 1 }
function Test-ForbiddenWindow($Info){
  if(-not ([string]$Info.title).Trim()){ return $true }
  if([string]$Info.proc -match '^(consent|CredentialUIBroker|LogonUI|CredentialEnrollmentManager|CredDialogHost|UserAccountControlSettings|SecHealthUI)$'){ return $true }
  if([string]$Info.class -match 'Credential|Secure Desktop'){ return $true }
  $false
}
# Похоже ли окно на диалог (а не на рабочее окно пользователя): класс #32770 или небольшое окно с 1–6 кнопками.
function Test-LooksLikeDialog($Info){
  if([string]$Info.class -eq '#32770'){ return $true }
  $nb=@($Info.buttons).Count
  ($nb -ge 1 -and $nb -le 6 -and $null -ne $Info.area -and [double]$Info.area -lt 0.35)
}
# ---------- Лимиты: чистые парсеры ----------
function Test-QuotaOver($Used,[double]$Pct,[string]$Mode){ if($null -eq $Used){ return $false }; if($Mode -eq 'remaining'){ (100-[double]$Used) -le $Pct } else { [double]$Used -ge $Pct } }
# Текст страницы gemini.google.com/usage (RU/EN; строки или ' | ') -> @{cur;curReset;wk;wkReset;exhausted}. Ошибка — исключение.
# Время сброса лимита из текста: «Лимит обновится в 12:25», «… 20 окт. в 15:25», «завтра в 03:10», «через 2 ч 15 мин»,
# «Resets at 3:25 PM», «Resets Oct 20 at 15:25», «Resets tomorrow at 1:00 AM», «in 45 min», «18.10 23:03». Не распознано — $null.
$script:ResetMonths=@{ 'янв'=1;'фев'=2;'мар'=3;'апр'=4;'мая'=5;'май'=5;'июн'=6;'июл'=7;'авг'=8;'сен'=9;'окт'=10;'ноя'=11;'дек'=12
  'jan'=1;'feb'=2;'mar'=3;'apr'=4;'may'=5;'jun'=6;'jul'=7;'aug'=8;'sep'=9;'oct'=10;'nov'=11;'dec'=12 }
function ConvertFrom-ResetText{
  param([string]$Text,[datetime]$Now=(Get-Date))
  $t=((([string]$Text) -replace '[\u00A0\u202F\u2009]',' ') -replace '\s+',' ').Trim().ToLowerInvariant()
  if(-not $t){ return $null }
  $now0=$Now.Date.AddHours($Now.Hour).AddMinutes($Now.Minute)
  $rel=[regex]::Match($t,'(?:^|\s)(?:через|in)\s+(?:(\d+)\s*(?:ч|час\w*|h|hr|hrs|hours?)\.?)?\s*(?:(\d+)\s*(?:мин\w*|m|min|mins|minutes?)\.?)?')
  if($rel.Success -and ($rel.Groups[1].Success -or $rel.Groups[2].Success)){
    $hh= if($rel.Groups[1].Success){ [int]$rel.Groups[1].Value } else { 0 }; $mm= if($rel.Groups[2].Success){ [int]$rel.Groups[2].Value } else { 0 }
    return $now0.AddHours($hh).AddMinutes($mm)
  }
  $tm=[regex]::Match($t,'(?<![\d.:])(\d{1,2}):(\d{2})(?!\d)(?:\s*([ap])\.?\s?m\.?(?![a-z]))?')
  if(-not $tm.Success){ return $null }
  $h=[int]$tm.Groups[1].Value; $mi=[int]$tm.Groups[2].Value
  if($tm.Groups[3].Success){ if($h -lt 1 -or $h -gt 12){ return $null }; if($tm.Groups[3].Value -eq 'p' -and $h -lt 12){ $h+=12 } elseif($tm.Groups[3].Value -eq 'a' -and $h -eq 12){ $h=0 } }
  if($h -gt 23 -or $mi -gt 59){ return $null }
  $rest=$t.Remove($tm.Index,$tm.Length)
  $mon='(янв|фев|мар|апр|ма[йя]|июн|июл|авг|сен|окт|ноя|дек|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-zа-яё]*\.?'
  $d=$null; $mo=$null
  $m1=[regex]::Match($rest,"(?<!\d)(\d{1,2})\s+$mon"); $m2=[regex]::Match($rest,"$mon\s+(\d{1,2})(?!\d)"); $m3=[regex]::Match($rest,'(?<![\d.])(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?(?![\d.]*\d)')
  if($m1.Success){ $d=[int]$m1.Groups[1].Value; $mo=$script:ResetMonths[$m1.Groups[2].Value.Substring(0,3)] }
  elseif($m2.Success){ $d=[int]$m2.Groups[2].Value; $mo=$script:ResetMonths[$m2.Groups[1].Value.Substring(0,3)] }
  elseif($m3.Success){ $d=[int]$m3.Groups[1].Value; $mo=[int]$m3.Groups[2].Value }
  if($null -ne $d){
    if($mo -lt 1 -or $mo -gt 12 -or $d -lt 1 -or $d -gt 31){ return $null }
    $y=$Now.Year
    try{ $dt=(New-Object DateTime $y,$mo,$d,$h,$mi,0) }catch{ return $null }
    if($dt -lt $Now.AddDays(-2)){ try{ $dt=(New-Object DateTime ($y+1),$mo,$d,$h,$mi,0) }catch{ return $null } }   # 31 дек -> «2 янв»
    elseif($dt -gt $Now.AddDays(300)){ try{ $dt=(New-Object DateTime ($y-1),$mo,$d,$h,$mi,0) }catch{ return $null } }   # 1 янв, текст «31 дек.» — прошлый год
    return $dt
  }
  $base=$Now.Date.AddHours($h).AddMinutes($mi)
  if($rest -match 'завтра|tomorrow'){ return $base.AddDays(1) }
  if($rest -match 'сегодня|today'){ return $base }
  if($base -lt $now0.AddMinutes(-1)){ $base=$base.AddDays(1) }   # время уже прошло — значит, завтра (переход через полночь)
  $base
}
function ConvertFrom-UsageText([string]$Text,[datetime]$Now=(Get-Date)){
  $txt=(([string]$Text) -replace "`r?`n",' | ') -replace '\s+',' '
  # Разбиваем на секции, чтобы процент недельного лимита не попал в «текущее» (и наоборот)
  $curHdr='(?:Текущее использование|Current usage)'; $wkHdr='(?:Недельный лимит|Weekly limit)'
  $curSec=[regex]::Match($txt,"$curHdr(.*?)(?=$wkHdr|$)").Groups[1].Value
  $wkSec=[regex]::Match($txt,"$wkHdr(.*?)(?=$curHdr|$)").Groups[1].Value
  $hasCur=$txt -match $curHdr; $hasWk=$txt -match $wkHdr
  $pctRx='(?:Использовано|Used)\s*(\d+)\s*%'; $rstRx='((?:Лимит обновится|Resets|Limit resets)[^|]*)'
  $exhRx='(?i)(исчерпан|достигл\w* лимит|достигнут\w* лимит|лимит\w* (достигнут|исчерпан)|reached your|limit reached|out of your|превыш\w* лимит)'
  $cur=[regex]::Match($curSec,$pctRx); $wk=[regex]::Match($wkSec,$pctRx)
  $exh=[bool]($txt -match $exhRx); $curExh= if($hasCur){ [bool]($curSec -match $exhRx) } else { $exh }
  if(-not $cur.Success -and -not $wk.Success){
    if($exh){ $rs=[regex]::Match($txt,$rstRx).Groups[1].Value.Trim(); return @{ cur=100; curReset=$rs; curResetAt=(ConvertFrom-ResetText $rs $Now); wk=$null; wkReset=''; wkResetAt=$null; exhausted=$true } }
    throw 'не удалось прочитать страницу лимитов Gemini'
  }
  @{ cur=$(if($cur.Success){ [int]$cur.Groups[1].Value } elseif($curExh){ 100 } else { $null }); curReset=[regex]::Match($curSec,$rstRx).Groups[1].Value.Trim()
     wk=$(if($wk.Success){ [int]$wk.Groups[1].Value } else { $null }); wkReset=[regex]::Match($wkSec,$rstRx).Groups[1].Value.Trim(); exhausted=$exh } |
    ForEach-Object { $_.curResetAt=(ConvertFrom-ResetText $_.curReset $Now); $_.wkResetAt=(ConvertFrom-ResetText $_.wkReset $Now); $_ }
}
function ConvertTo-UtcDate($x){ if($x -is [datetime]){ return $x.ToUniversalTime() }; [DateTimeOffset]::Parse([string]$x,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
function Format-LocalTime($x){ try{ (ConvertTo-UtcDate $x).ToLocalTime().ToString('dd.MM HH:mm') }catch{ [string]$x } }
# Ответ RetrieveUserQuotaSummary -> @{h5=@{rem;reset;note}; wk=...}. $Refine — скриптблок, возвращающий GetUserStatus (вызывается, если сброс уже прошёл).
function ConvertFrom-AgQuota{
  param($Response,[string]$Group,[datetime]$NowUtc=[DateTime]::UtcNow,[scriptblock]$Refine)
  $grp=@($Response.response.groups) | Where-Object { $_.displayName -eq $Group } | Select-Object -First 1
  if(!$grp){ throw "в ответе нет группы '$Group'" }
  $out=@{}
  foreach($b in @($grp.buckets)){
    $k= if($b.window -match '5h|hour'){ 'h5' } elseif($b.window -match 'week'){ 'wk' } else { $null }; if(!$k){ continue }
    $rem=[math]::Round([double]$b.remainingFraction*100); $reset=$b.resetTime; $note=''
    $past=$false; try{ $past=(ConvertTo-UtcDate $reset) -lt $NowUtc }catch{}
    if($past){
      $note=' (уточнено)'; $rem=100
      if($Refine){ try{ $st=& $Refine
        $ms=@($st.userStatus.cascadeModelConfigData.clientModelConfigs) | Where-Object { $_.label -match 'Gemini' -and $_.quotaInfo -and -not ((ConvertTo-UtcDate $_.quotaInfo.resetTime) -lt $NowUtc) }
        if($ms -and $k -eq 'h5'){ $min=($ms | Sort-Object { [double]$_.quotaInfo.remainingFraction } | Select-Object -First 1); $rem=[math]::Round([double]$min.quotaInfo.remainingFraction*100); $reset=$min.quotaInfo.resetTime } }catch{} }
    }
    $at=$null; try{ $at=(ConvertTo-UtcDate $reset).ToLocalTime() }catch{}
    $out[$k]=@{ rem=$rem; reset=(Format-LocalTime $reset); resetAt=$at; note=$note }
  }
  $out
}

# Windows PowerShell 5.1, запущенный из pwsh 7 через cmd/wscript, наследует PSModulePath с модулями PS7 —
# тогда автозагрузка Microsoft.PowerShell.Security (ConvertTo-SecureString, DPAPI) падает. Убираем пути PS6+/7 и
# возвращаем системный путь модулей Windows PowerShell. Порядок остальных путей сохраняется.
function Get-RepairedPSModulePath([string]$Path,[string]$PSHomeDir){
  $keep=New-Object System.Collections.Generic.List[string]
  foreach($p in @(([string]$Path) -split ';')){
    $t=$p.Trim(); if(-not $t){ continue }
    if($t -match '(^|\\)PowerShell\\(\d[^\\]*\\)?Modules\\?$'){ continue }
    if(-not ($keep | Where-Object { $_.TrimEnd('\') -ieq $t.TrimEnd('\') })){ $keep.Add($t) }
  }
  if($PSHomeDir){ $sys=$PSHomeDir.TrimEnd('\','/')+'\Modules'; if(-not ($keep | Where-Object { $_.TrimEnd('\') -ieq $sys.TrimEnd('\') })){ $keep.Add($sys) } }
  $keep -join ';'
}
function Repair-PSModulePath{ if($PSVersionTable.PSEdition -ne 'Core'){ $env:PSModulePath=Get-RepairedPSModulePath $env:PSModulePath $PSHOME } }

# ---------- Автоподтверждение запросов разрешения Antigravity (чистая логика, тестируется без окон) ----------
# Жёсткий запрет: «always», «No», «Skip», «Cancel», «Reject», «Stop» никогда не выбираются и не нажимаются — даже если шаблон в настройках шире.
$script:AutoAllowDenyRx='(?i)always|всегда|\bno\b|^\s*\d?[\s.)]*нет\b|skip|пропуст|deny|reject|отклон|cancel|отмен|stop|останов|abort|ctrl\+d'
function Test-AutoAllowOption([string]$Text){ $t=(([string]$Text) -replace '\s+',' ').Trim(); [bool]($t -and $t.Length -le 120 -and $t -match $Cfg.AutoAllowOptionRx -and $t -notmatch $script:AutoAllowDenyRx) }
function Test-AutoAllowSubmit([string]$Text){ $t=(([string]$Text) -replace '\s+',' ').Trim(); [bool]($t -and $t -match $Cfg.AutoAllowSubmitRx -and $t -notmatch $script:AutoAllowDenyRx) }
# Из кандидатов @{el;rect} выбирает кнопку, ближайшую к варианту (ниже или на уровне него); $null — нет подходящей.
function Select-NearestBelow($OptRect,$Cands){
  $best=$null; $bd=[double]::MaxValue
  foreach($c in @($Cands)){ if(-not $c -or -not $c.rect){ continue }
    if($OptRect){ $dy=[double]$c.rect.T-[double]$OptRect.T; if($dy -lt -5){ continue } } else { $dy=0 }
    if($dy -lt $bd){ $bd=$dy; $best=$c } }
  $best
}
# Сохраняет одну настройку в relay_settings.json, не трогая остальные (атомарно). Нужна State.ps1 (Write-AtomicText).
function Save-SettingValue([string]$Path,[string]$Key,$Value){
  $h=[ordered]@{}
  if(Test-Path -LiteralPath $Path){ $raw=[IO.File]::ReadAllText([IO.Path]::GetFullPath($Path),[Text.Encoding]::UTF8); if($raw.Trim()){ $h=ConvertTo-PlainHashtable ($raw | ConvertFrom-Json) } }
  $h[$Key]=$Value
  Write-AtomicText -Path $Path -Text ($h | ConvertTo-Json -Depth 10) -NoBackup
}
