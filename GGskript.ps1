# ===== GGskript v2: Antigravity (младшая модель) <-> Gemini в браузере Chrome / Яндекс / Edge (старшая модель) =====
# Остановка: Ctrl+C в этом окне, файл STOP рядом со скриптом, кнопка «Стоп» в GUI или «стоп» в Telegram.
# Настройки: значения по умолчанию — lib/Core.ps1 (Get-DefaultSettings); свои изменения — relay_settings.json (см. relay_settings.example.json).
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
. (Join-Path $Root 'lib\Core.ps1'); Repair-PSModulePath
foreach($f in 'State','Platform.Win','Uia','Telegram','Gemini.Uia','Gemini.Cdp','Gemini','Antigravity','Antigravity.Cdp','Relay','Chat','Shutdown'){ . (Join-Path $Root "lib\$f.ps1") }
$ms=Merge-Settings -Defaults (Get-DefaultSettings -Root $Root) -OverridePath (Join-Path $Root 'relay_settings.json')
$Cfg=$ms.Cfg
# -testparse — только разбор команд: без WinAPI, без чтения Downloads и состояния
if($args -contains '-testparse'){
  @('статус','Что происходит?','пауза','остановись на время','продолжай','стоп','выключи реле','прими','нажми принять','напиши джемини: привет','Гемини, как дела','/gemini тест','напиши антигравити: запусти тесты','/ag тест','передай ответ','передай весь ответ','передай всё равно','отправь заново','что ответил джемини','скрин','покажи экран','помощь','/start','абракадабра','принял, спасибо','джемини завершил?','продолжай, не стоп','Режим вывода команд на экран (ECHO) отключен.') |
    ForEach-Object { $c=Parse-Command -Text $_ -Strict ([bool]$Cfg.StrictCommands); Write-Host ("  {0,-46} -> {1} {2}" -f $_,$c.k,$(if($c.arg){"['$($c.arg)']"}elseif($c.whole){'[весь]'})) }
  exit
}
try{ [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }catch{}
Initialize-Platform
$script:DpiMode=Initialize-Dpi
Initialize-Uia
try{ [Console]::TreatControlCAsInput=$false }catch{}
foreach($w in $ms.Warnings){ Log "Настройки: $w" }

$isTest=[bool]($args | Where-Object { $_ -like '-*' })
$script:WorkerMutexObj=$null
if(-not $isTest){
  $script:WorkerMutexObj=Enter-SingleInstance $Cfg.WorkerMutex
  if(-not $script:WorkerMutexObj){
    if(Test-Path -LiteralPath $Cfg.PauseFile){ Remove-Item -LiteralPath $Cfg.PauseFile -EA 0; Write-Host 'GGskript уже запущен — снял с паузы (СТАРТ). Это окно можно закрыть.' }
    else { Write-Host 'GGskript уже запущен и работает. Это окно можно закрыть.' }
    Start-Sleep 4; exit
  }
  if(Disable-QuickEdit){ Log 'Режим выделения мышью в консоли отключён (клик в окне больше не ставит скрипт на паузу).' }
}
$script:Paused=Test-Path -LiteralPath $Cfg.PauseFile
Update-Title
try{ $script:TgOffset=[int64]([IO.File]::ReadAllText($Cfg.TgOffsetFile).Trim()) }catch{}

# ---- Состояние: relay_state.json ----
$rs=Read-RelayState $Cfg.StateJson
if($rs.State){ $script:St=$rs.State; if($rs.Source -eq 'bak'){ Log "⚠️ relay_state.json повреждён — восстановил из relay_state.json.bak ($($rs.Error))" } }
else{
  $script:St=New-RelayState
  if(-not $rs.Error){ foreach($f in @(Get-Files)){ [void](Set-FileStage $script:St $f.Name 'done' -Force) }; Log 'Первый запуск: существующие файлы считаю обработанными.' }
  else { Log "⚠️ Состояние не прочитано ($($rs.Error)) и .bak нет — начинаю с пустого учёта" }
}
$start=$args | Where-Object { $_ -notlike '-*' } | Select-Object -First 1
if($start){
  $sk=Get-SortKey $start $Cfg.Pattern
  foreach($f in @(Get-Files -All)){ if((Get-SortKey $f.Name $Cfg.Pattern) -lt $sk){ [void](Set-FileStage $script:St $f.Name 'done' -Force) } else { Remove-FileStage $script:St $f.Name } }
  Log "Старт с файла $start"
}
try{ $dropped=Compress-RelayState $script:St -ExistingNames @(Get-Files -All | ForEach-Object { $_.Name }) -Keep $Cfg.StateKeepTerminal -Pattern $Cfg.Pattern; if($dropped){ Log "Учёт: удалено старых записей $dropped" } }catch{}
if(-not $isTest){ Save-State }
try{ $script:LastDone=Get-LastDoneName }catch{}

# ---- Тестовые режимы (без изменения состояния) ----
if($args -contains '-teststart'){ Init-Tg; Start-Procedure -DryRun | Out-Null; exit }
if($args -contains '-check'){
  Log "Проверка: Gemini готов=$(try{Gem-IsReady}catch{$false}) Antigravity=$([bool](Ag-GetWindow)) файлов=$(@(Get-Files).Count) DPI=$script:DpiMode транспорт Gemini=$($Cfg.GeminiTransport) AG=$($Cfg.AgTransport)"
  $cand=@(Get-Files | ForEach-Object { $_.Name })
  Write-Host "  Шаблон: $($Cfg.Pattern)  IgnoreBefore: $($Cfg.IgnoreBefore)"
  Get-Files -All | ForEach-Object { $lbl= if(Is-Done $_.Name){'обработан'} elseif($cand -notcontains $_.Name){'старый (раньше IgnoreBefore) — не беру'} else {'БУДЕТ ОБРАБОТАН'}; Write-Host ("  {0,-40} проект={1,-18} {2} [{3}]" -f $_.Name,(ProjOf $_.Name),$lbl,(Get-StageRu (Get-Stage $_.Name))) }
  exit
}
if($args -contains '-testqueue'){ $h=Ag-GetWindow; $it=@(Find-QueuedItems $h); Log "В очереди Antigravity: $($it.Count) (не нажимаю)"; $it | ForEach-Object { Log "  [$(Uia-Name $_.btn)] «$($_.key)»" }; Log "Поле '$($Cfg.AgInputName)' найдено: $([bool](AgUia-FindInput $h))"; exit }
if($args -contains '-testquota'){
  try{ $a=Get-AgQuota; Log "Antigravity ($($Cfg.AgGroup)): 5 ч осталось $($a.h5.rem)%$($a.h5.note), сброс $($a.h5.reset); неделя осталось $($a.wk.rem)%$($a.wk.note), сброс $($a.wk.reset)" }catch{ Log "Antigravity: ОШИБКА $($_.Exception.Message)" }
  if($args -contains '-web'){ try{ $w=Get-GeminiWebUsage; Log "Gemini (сайт): текущее использовано $($w.cur)% ($($w.curReset)); неделя использовано $($w.wk)% ($($w.wkReset))" }catch{ Log "Gemini (сайт): ОШИБКА $($_.Exception.Message)" } }
  exit
}
if($args -contains '-teststatus'){ Write-Host (Get-StatusText); exit }
if($args -contains '-testtg'){ Init-Tg; Log "Telegram: токен=$([bool]$script:TgToken) chat_id=$([bool]$script:TgChat)"; if($args -contains '-send' -and $script:TgChat){ Notify 'тестовое уведомление' -Force; Log 'Тестовое сообщение отправлено' }; exit }
# -testmodel — текущая модель и пункты меню моделей (меню открывается и закрывается, ничего не выбирается);
# -testmodel -switch — переключить на ModelMustContain и проверить. В чат ничего не пишется.
if($args -contains '-testmodel'){
  Log "Модель Gemini: '$(Get-ModelNow)' (нужна: $($Cfg.ModelMustContain), Argon=$(Is-Argon $script:LastModel))"
  if($args -contains '-switch'){ try{ $m=Switch-ToArgon; Log "Переключение: OK, выбрана «$m»" }catch{ Log "Переключение: ОШИБКА $($_.Exception.Message)" } }
  else{
    try{ $l=Gem-ListModels; Log "Меню моделей: $(@($l.items).Count) пунктов"; foreach($i in @($l.items)){ Log ("  {0}{1}{2}" -f $i.name,$(if($i.selected){' [выбрана]'}),$(if(-not $i.enabled){' [недоступна]'})) } }catch{ Log "Меню моделей: ОШИБКА $($_.Exception.Message)" }
    $h=Ag-GetWindow; Log "Кнопка 'Accept all' в Antigravity: $([bool]($h -and (Find-AcceptAll $h))) (не нажимаю)"
  }
  exit
}
# -testplan [-limit] — прочитать лимиты (Antigravity + страница лимитов Gemini) и показать план автовозобновления
# (-limit — как будто модель Gemini не та). Ничего не переключает и не возобновляет.
if($args -contains '-testplan'){
  try{ Check-Quotas | Out-Null }catch{ Log "Лимиты: $($_.Exception.Message)" }
  $g= if($script:Q){ $script:Q.gweb } else { $null }
  if($g){ Log "Сброс Gemini: текущий '$($g.curReset)' → $($g.curResetAt); неделя '$($g.wkReset)' → $($g.wkResetAt)" }
  if($script:Q -and $script:Q.ag){ foreach($k in 'h5','wk'){ if($script:Q.ag[$k]){ Log "Сброс Antigravity $($k): $($script:Q.ag[$k].reset) → $($script:Q.ag[$k].resetAt)" } } }
  $p=Get-AutoResumePlan -Q $script:Q -LimitStop ($args -contains '-limit') -QStopG ([bool]$script:QStopG) -QStopA ([bool]$script:QStopA)
  if($p){ Log "План: попытка в $(Format-PlanTime $p.at) — $($p.why)" } else { Log 'План: ничего не заблокировано — автовозобновление не нужно' }
  exit
}
if($args -contains '-testcopy'){ $t=Gem-CopyCode; if(!$t){ Log 'Блок кода не найден' } else { Log "Скопировано $($t.Length) симв. Первые строки:"; ($t -split "`n" | Select-Object -First 6) | ForEach-Object { Write-Host "    $_" } }; exit }
if($args -contains '-testpaste'){
  $m='ТЕСТ РЕЛЕ - не отправлять'; $h=Find-GeminiWindow; Log "1. Окно Gemini: $([bool]$h)"; if(!$h){ exit 1 }
  Invoke-WithFocus $h {
    Log "2. Фокус в поле: $(GemUia-FocusInput $h)"
    Use-TempClipboard { Set-ClipText $m; Paste }; Start-Sleep 1.5
    $t=Uia-GetText (GemUia-FindInput $h); Log "3. Текст в поле (UIA): '$t'"
    Log "4. РЕЗУЛЬТАТ: $(if($t -like "*$m*"){'УСПЕХ'}else{'НЕУДАЧА'})"
    if($t -like "*$m*" -and (GemUia-FocusInput $h)){ ClearField; Start-Sleep 1; Log "5. После очистки: '$(Uia-GetText (GemUia-FindInput $h))'" }
  }
  exit
}
# -testallow — только чтение: что UIA видит в окне Antigravity из запроса разрешения (Submit/Skip/allow/always). Ничего не нажимает.
if($args -contains '-testallow'){
  $h=Ag-GetWindow; Log "Antigravity: окно=$([bool]$h) «$(if($h){Uia-Name (Uia-Root $h)})»"
  if($h){ $all=@(Uia-FindAll -Root $h -NameRx '(?i)allow|разреш|submit|skip|подтверд'); Log "  элементов: $($all.Count)"
    foreach($e in $all | Select-Object -First 40){ Log "  [$(Uia-CtlType $e)] «$(Format-Short (Uia-Name $e) 80)» скрыт=$(Uia-IsOffscreen $e) вариант=$(Test-AutoAllowOption (Uia-Name $e)) кнопка=$(Test-AutoAllowSubmit (Uia-Name $e))" } }
  exit
}
# -testag — только чтение: отвечает ли окно Antigravity и что в поле чата (без фокуса, кликов и буфера)
if($args -contains '-testag'){
  $d=Get-AgDiag; $hl=$d.health
  Log "Antigravity: окно=$([bool]$hl.h) pid=$($hl.pid) «$($hl.title)» состояние=$($hl.kind)$(if($hl.reasons){' ('+($hl.reasons -join '; ')+')'})"
  if($null -ne $d.findMs){ Log "  Поле '$($Cfg.AgInputName)': найдено=$($d.found) за $($d.findMs) мс" }
  $i=0; foreach($r in $d.reads){ $i++; Log "  Чтение $($i): $(Format-FieldDiag $r)" }
  Log "  Вывод: $($d.verdict)"
  exit
}
# -testgemini — только чтение (пункт 25E): в каком браузере окно Gemini, модель, последний отчёт, подписи блоков последнего ответа. Без кликов и буфера.
if($args -contains '-testgemini'){
  $h=Find-GeminiWindow; Log "Проверка Gemini: окно=$([bool]$h), браузер=$(Get-GeminiBrowserName)"
  if($h){
    Log "  вкладка: «$(Remove-BrowserSuffix (Uia-Name (Uia-Root $h)))»; поле ввода: $([bool](GemUia-FindInput $h)); модель: «$(GemUia-GetModel $h)»; генерирует: $(GemUia-IsGenerating $h)"
    Log "  запросов в чате: $(GemUia-CountPrompts $h); последний отчёт: $(GemUia-LastReportPrompt $h)"
    $r=GemUia-FindCodeCopyButtonOnce $h; Log "  кнопка «Копировать код» блока '$($Cfg.CodeBlockLang)' в последнем ответе: $(if($r.btn){'найдена'}else{'НЕТ'})"
    $pk=GemUia-PeekAnswer $h; Log "  ответ после последнего запроса: $($pk.answered); блоки: $(Format-Langs $pk.labels); Markdown: $($pk.md); текст блока без копирования: $(if($pk.code){"$($pk.code.Length) симв., «$(Get-FirstLine $pk.code)»"}else{'не прочитан'})"
  }
  exit
}
# -testcdp — только чтение (пункт 27): вкладки CDP-браузера Gemini, модель, последний отчёт, подписи блоков; цели CDP Antigravity. Без ввода и кликов.
if($args -contains '-testcdp'){
  Log "Gemini CDP (порт $($Cfg.CdpPort)):"
  try{
    foreach($tcT in @(GemCdp-Targets)){ Log "  вкладка: «$(Format-Short $tcT.title 60)» — $($tcT.url)" }
    $tcChat=Find-CdpTarget; $tcUsage=Find-CdpUsageTarget
    Log "  чат: $(if($tcChat){$tcChat.url}else{'НЕТ'}); лимиты: $(if($tcUsage){$tcUsage.url}else{'нет вкладки /usage'})"
    if($tcChat){
      Log "  готов=$(GemCdp-IsReady) модель='$(GemCdp-GetModel)' запросов=$(GemCdp-CountPrompts) последний отчёт='$(GemCdp-LastReportPrompt)' генерирует=$([bool](Eval-Js 'state').gen)"
      $tcPk=GemCdp-PeekAnswer; Log "  последний ответ: есть=$($tcPk.answered); блоки: $(Format-Langs $tcPk.labels); Markdown: $($tcPk.md)$(if($tcPk.code){"; «$(Get-FirstLine $tcPk.code)»"})"
      $tcPt=@(GemCdp-PromptTexts); if($tcPt.Count){ Log "  последний запрос: $(Format-Short (($tcPt[-1]) -replace '\s+',' ') 100)" }
    }
  }catch{ Log "  ОШИБКА: $($_.Exception.Message)" }
  $tcD=Get-AgCdpDiag
  Log "Antigravity CDP (порт $($tcD.port)): $(if($tcD.err){"ОШИБКА: $($tcD.err)"}else{"чат найден в «$($tcD.chat)»; поле: $(([string]$tcD.field).Length) симв.; занят: $($tcD.busy); Accept all: $($tcD.accept)"})"
  foreach($tcT in @($tcD.targets)){ Log "  цель: $tcT" }
  exit
}

# ---- Работа ----
Log "GGskript v2 запущен (pid $PID). Папка: $($Cfg.Downloads). Транспорт: Gemini=$($Cfg.GeminiTransport), Antigravity=$($Cfg.AgTransport). DPI=$script:DpiMode.$(if($script:Paused){' Сейчас СТОП (файл PAUSE): жду «Старт».'})"
Init-Tg; if($script:TgChat){ Log 'Telegram: принимаю команды (напишите боту «помощь»)' }
Write-Status -Force
try{
  while((Invoke-MainStep) -ne 'stop'){ }
} finally {
  Log 'GGskript остановлен.'; try{ Notify 'остановлен.' -Force }catch{}
  try{ $script:Stopped=$true; $script:State='остановлен'; Write-Status -Force }catch{}
  Exit-SingleInstance $script:WorkerMutexObj
}
