BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function N([int]$i){ 'MyProject_2026-10-18_{0:D3}.md' -f $i }
  function New-Rep([int]$i,[datetime]$t){ $p=Join-Path $Cfg.Downloads (N $i); [IO.File]::WriteAllText($p,"отчёт $i"); $gi=Get-Item $p; $gi.CreationTime=$t; $gi.LastWriteTime=$t; $p }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
  function Press($p,[string]$choice){ Handle-Callback "p:$($p.id):$choice" 'cb' $p.msgId }
  function PromptOf([string]$k){ @($script:TgPrompts.Values | Where-Object kind -eq $k) | Select-Object -Last 1 }
  function StartText{ $s=Sent '*процедура запуска*'; if($s.Count){ [string]$s[-1].b.text } else { '' } }
  function Set-Files{
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $script:St=New-RelayState; $t0=[datetime]'2026-10-18 09:00'
    foreach($i in 1..7){ [void](New-Rep $i $t0.AddMinutes(30*$i)) }
    foreach($i in 1,2){ [void](Set-FileStage -State $script:St -Name (N $i) -Stage 'relayed' -Force) }
  }
  function Use-Base{
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100
    $script:TgPrompts.Clear(); $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:Held=@{}; $script:Adopted=@{}
    $script:TriageNeeded=$true; $script:PausedSince=$null; $script:LastStartReport=''; $script:StopAnnounced=$false; $script:AbortOnStop=$false
    $script:NeedStart=$true; $script:StopReq=$false; $script:LimitStop=$false; $script:QStopG=$false; $script:QStopA=$false; $script:Q=$null; $script:AutoPlan=$null
    $Cfg.StartupNewestOnly=$true; $Cfg.StartupAskNewest=$true; $Cfg.StartupTriagePauseMin=0; $Cfg.QuotaEveryMin=0; $Cfg.IgnoreBefore=''; $Cfg.TgReplyKeyboard=$true
    $Cfg.AutoSwitchModel=$true; $Cfg.CodeBlockLang='Markdown'; $Cfg.CodeBlockPick='last'; $Cfg.CodeFromWholeFallback=$false
    $Cfg.StateJson=(Join-Path $TestDrive 'relay_state.json'); $Cfg.PauseFile=(Join-Path $TestDrive 'PAUSE'); $Cfg.StopFile=(Join-Path $TestDrive 'STOP'); $Cfg.CmdFile=(Join-Path $TestDrive 'commands.txt')
    Remove-Item $Cfg.PauseFile,$Cfg.StopFile -EA 0
    $script:GemSent=New-Object System.Collections.ArrayList; $script:AgSent=New-Object System.Collections.ArrayList
    $script:LP=$null; $script:PK=$null; $script:InAg=$false; $script:Model='Argon Ultra'
  }
}

Describe 'Пункт 25A: протокол запуска' -Tag Item25,Item25A {
  BeforeEach {
    Use-Base; Set-Files
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Gem-IsReady { $true }; Mock Ag-GetWindow { [IntPtr]1 }; Mock AgUia-FindInput { $true }
    Mock Get-ModelNow { $script:LastModel=$script:Model; $script:Model }
    Mock Switch-ToArgon { $script:Model='Argon Ultra'; 'Argon Ultra' }
    Mock Check-Quotas { $script:Q=@{ time='08:50' }; 'ok' }; Mock Quota-Text { 'в норме' }; Mock Update-AutoPlan {}
    Mock Gem-IsGenerating { $false }; Mock Get-AgHealth { @{ ok=$true; kind='ok'; reasons=@() } }; Mock Find-QueuedItems { @() }
    Mock Gem-LastReportPrompt { $script:LP }; Mock Gem-PeekAnswer { $script:PK }; Mock Ag-HasText { $script:InAg }
    Mock Gem-Send { [void]$script:GemSent.Add($Text); @{ pBefore=1 } }; Mock Gem-SendFile { [void]$script:GemSent.Add($Name); @{ pBefore=1 } }; Mock Ag-Send { [void]$script:AgSent.Add($Text) }
  }
  It 'нет окна Gemini — дальше шага 1 не иду: ни лимитов, ни модели, ни чатов; повтор не дублирует сообщение' {
    Mock Gem-IsReady { $false }
    Start-Procedure | Should -BeFalse; Start-Procedure | Should -BeFalse; Start-Procedure | Should -BeFalse
    Should -Invoke Get-ModelNow -Times 0; Should -Invoke Check-Quotas -Times 0; Should -Invoke Gem-PeekAnswer -Times 0; Should -Invoke Gem-LastReportPrompt -Times 0
    (Sent '*процедура запуска*').Count | Should -Be 2 -Because 'первый — со списком пропущенных, второй — без него, третий такой же — не шлётся'
    StartText | Should -Match 'НЕ проверяю'; StartText | Should -Match '👉 Ход: ничей'
    $script:GemSent.Count | Should -Be 0
  }
  It 'изменился отчёт (окно появилось) — новое сообщение уходит' {
    Mock Gem-IsReady { $false }; Start-Procedure | Out-Null
    Mock Gem-IsReady { $true }; $script:LP=(N 7); Start-Procedure | Out-Null
    (Sent '*процедура запуска*').Count | Should -Be 2
  }
  It 'шаги строго по порядку 1)..5) и итог «Ход»; 007 в чате, ответ с Markdown, в Antigravity его нет -> GGskript передаст' {
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Python','Markdown'); md=$true; code="## Задача`nсделай" }
    Start-Procedure | Should -BeTrue
    $t=StartText
    $t | Should -Match '(?s)1\) Окна.*2\) Лимиты.*3\) Модель Gemini: Argon Ultra.*4\) Файлы.*5\) Сверка чатов.*👉 Ход: GGskript — заберу ответ на MyProject_2026-10-18_007\.md'
    $t | Should -Match "блоки: 'Python', 'Markdown'"
    $t | Should -Match 'в чате Antigravity — нет'
    Get-Stage (N 7) | Should -Be 'sent'; $script:Adopted.ContainsKey((N 7)) | Should -BeTrue
    foreach($i in 3..6){ Get-Stage (N $i) | Should -Be 'skipped' }
    $script:GemSent.Count | Should -Be 0
  }
  It 'ответ уже в Antigravity — ход Antigravity, ничего не вставляю' {
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Markdown'); md=$true; code="## Задача`nсделай" }; $script:InAg=$true
    Start-Procedure | Out-Null
    StartText | Should -Match '👉 Ход: Antigravity — ответ на MyProject_2026-10-18_007\.md уже вставлен'
    $script:AgSent.Count | Should -Be 0
  }
  It 'ответа Gemini ещё нет — ход Gemini' {
    $script:LP=(N 7); $script:PK=@{ answered=$false; labels=@(); md=$false; code=$null }
    Start-Procedure | Out-Null; StartText | Should -Match '👉 Ход: Gemini — ответа на MyProject_2026-10-18_007\.md ещё нет'
  }
  It 'ответ без блока Markdown (только Python) — ход ваш, другие блоки не беру' {
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Python'); md=$false; code=$null }
    Start-Procedure | Out-Null
    StartText | Should -Match "блока 'Markdown' НЕТ"; StartText | Should -Match "👉 Ход: ваш — в ответе на .* нет блока Markdown \(блоки: 'Python'\)"
  }
  It 'самого нового нет в чате Gemini — вопрос в Telegram, ход ваш, в Gemini ничего' {
    $script:LP=(N 4)
    Start-Procedure | Out-Null
    StartText | Should -Match '👉 Ход: ваш — ответьте в Telegram'
    PromptOf 'newest' | Should -Not -BeNullOrEmpty; $script:GemSent.Count | Should -Be 0; Next-File | Should -BeNullOrEmpty
  }
  It 'противоречие: в Gemini отчёт новее самого нового в Downloads — спрашиваю, ничего не делаю сам' {
    $script:LP='MyProject_2026-10-18_009.md'
    Start-Procedure | Out-Null
    StartText | Should -Match '⚠️ противоречие'
    (PromptOf 'newest').text | Should -Match 'последний отчёт — MyProject_2026-10-18_009\.md'
    $script:Held.ContainsKey((N 7)) | Should -BeTrue; Next-File | Should -BeNullOrEmpty; $script:GemSent.Count | Should -Be 0
  }
  It 'по учёту передан, но в Antigravity ответа не видно — вопрос «Передать ответ»; «Передать» -> заберу и передам' {
    [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'relayed' -Force)
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Markdown'); md=$true; code="## Задача`nсделай" }; $script:InAg=$false
    Start-Procedure | Out-Null
    $p=PromptOf 'proto'; $p | Should -Not -BeNullOrEmpty
    Press $p 'relay'
    Get-Stage (N 7) | Should -Be 'sent'; $script:Adopted.ContainsKey((N 7)) | Should -BeTrue
  }
  It 'лимит исчерпан — шаг 2 останавливает протокол: модель не читаю, ничего не отправляю' {
    Mock Check-Quotas { $script:QStopG=$true; $script:Q=@{ time='08:50' }; 'x' }
    Start-Procedure | Should -BeTrue
    Should -Invoke Get-ModelNow -Times 0; StartText | Should -Match '⛔ исчерпан: лимит Gemini'; StartText | Should -Match '👉 Ход: ничей — жду сброса'
    Get-Stage (N 3) | Should -Be '' -Because 'до шага 4 не дошли'
  }
  It 'модель не Argon, AutoSwitchModel — переключаю и продолжаю' {
    $script:Model='Flash'; $script:LP=(N 7)
    Start-Procedure | Should -BeTrue
    Should -Invoke Switch-ToArgon -Times 1; StartText | Should -Match 'была «Flash» — переключил'
  }
  It 'модель не Argon, AutoSwitchModel=false — остановка по модели, дальше не иду' {
    $Cfg.AutoSwitchModel=$false; $script:Model='Flash'
    Start-Procedure | Should -BeTrue
    $script:LimitStop | Should -BeTrue; StartText | Should -Match '👉 Ход: ничей — жду нужную модель'; Should -Invoke Gem-PeekAnswer -Times 0
  }
  It 'Gemini генерирует — жду (повтор), файлы не трогаю' {
    Mock Gem-IsGenerating { $true }
    Start-Procedure | Should -BeFalse; StartText | Should -Match '👉 Ход: Gemini — генерирует'; Get-Stage (N 3) | Should -Be ''
  }
  It 'Antigravity не отвечает — жду (повтор)' {
    Mock Get-AgHealth { @{ ok=$false; kind='hung'; reasons=@('не отвечает 30 с') } }
    Start-Procedure | Should -BeFalse; StartText | Should -Match 'Antigravity не отвечает'
  }
  It 'пробный прогон (-DryRun) — ничего не меняет и не пишет в Telegram' {
    $script:LP=(N 4); Start-Procedure -DryRun | Out-Null
    $script:TgCalls.Count | Should -Be 0; foreach($i in 3..7){ Get-Stage (N $i) | Should -Be '' }; Should -Invoke Switch-ToArgon -Times 0
  }
}

Describe 'Пункт 25B: в режиме СТОП — никаких проверок и окон' -Tag Item25,Item25B {
  BeforeEach {
    Use-Base; Set-Files
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Poll-Tg {}; Mock Sweep-TgPrompts {}; Mock Read-CmdFile {}; Mock Check-LocalControl {}; Mock Write-Status {}; Mock Check-Shutdown {}; Mock Nap {}
    Mock Check-Quotas { 'x' }; Mock Get-ModelNow { 'Argon' }; Mock Check-Blocking {}; Mock Try-AcceptAll { $false }; Mock Check-AgQueue {}; Mock Start-Procedure { $true }
    Mock Process-File {}; Mock Gem-IsReady { $true }; Mock Gem-CopyCode { 'x' }; Mock Ag-Send {}; Mock Gem-Send {}; Mock Gem-SendFile {}; Mock Invoke-AutoResume { $true }; Mock Send-Screenshot {}
    $script:Paused=$true
  }
  It 'шаг главного цикла на СТОП: лимиты, модель, окна, Accept all, очередь, протокол — ни одного вызова; таймер выключения работает' {
    $script:LimitStop=$true; $script:LastLimitCheck=(Get-Date).AddHours(-1); $Cfg.QuotaEveryMin=1; $script:LastQuota=(Get-Date).AddHours(-1)
    $Cfg.AcceptAllEverySec=1; $Cfg.AgQueueCheckSec=1; $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }
    1..3 | ForEach-Object { Invoke-MainStep | Should -Be 'ok' }
    foreach($f in 'Check-Quotas','Get-ModelNow','Check-Blocking','Try-AcceptAll','Check-AgQueue','Start-Procedure','Process-File','Gem-IsReady','Invoke-AutoResume'){ Should -Invoke $f -Times 0 -Because $f }
    Should -Invoke Check-Shutdown -Times 3
  }
  It 'запуск в режиме СТОП — одно сообщение «запущен в режиме СТОП» с клавиатурой, протокол не выполняется' {
    Invoke-MainStep | Out-Null; Invoke-MainStep | Out-Null
    $s=Sent '*в режиме СТОП*'; $s.Count | Should -Be 1; $s[0].b.reply_markup | Should -Not -BeNullOrEmpty
    $script:NeedStart | Should -BeTrue; Should -Invoke Start-Procedure -Times 0
  }
  It 'команды, которым нужны окна, на СТОП отклоняются: «<T>»' -TestCases @(@{T='лимиты'},@{T='передай ответ'},@{T='прими'},@{T='что ответил джемини'},@{T='/ag текст'},@{T='передай всё равно'}) {
    param($T)
    Handle-Command $T 'tg'
    (Sent '⏹ Сейчас СТОП*').Count | Should -Be 1; $script:Queue.Count | Should -Be 0; Should -Invoke Check-Quotas -Times 0
  }
  It '«статус», «скрин», «помощь» на СТОП работают' {
    Handle-Command 'статус' 'tg'; (Sent '*Остановлен — ничего не делаю*').Count | Should -Be 1
    Handle-Command 'скрин' 'tg'; Should -Invoke Send-Screenshot -Times 1
    Handle-Command 'помощь' 'tg'; (Sent '*команды*').Count | Should -Be 1
  }
  It 'команда из очереди (поставлена до стопа) на СТОП не выполняется' {
    $script:Queue.Enqueue(@{ k='relay'; src='tg' }); Mock Run-Action {}
    Invoke-MainStep | Out-Null
    Should -Invoke Run-Action -Times 0; (Sent '⏹ Сейчас СТОП*').Count | Should -Be 1; $script:Queue.Count | Should -Be 0
  }
  It '«Старт» после стопа — протокол запуска заново (с разбором файлов), PAUSE снят' {
    New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null; $script:NeedStart=$false; $script:TriageNeeded=$false; $script:LastStartReport='старый'
    Handle-Command 'Старт' 'tg'
    $script:Paused | Should -BeFalse; Test-Path $Cfg.PauseFile | Should -BeFalse
    $script:NeedStart | Should -BeTrue; $script:TriageNeeded | Should -BeTrue; $script:LastStartReport | Should -Be ''
    (Sent '*протокол запуска*').Count | Should -Be 1
  }
  It 'статус для панели: СТОП важнее остановки по лимиту' {
    $script:LimitStop=$true; Mock Write-AtomicText { $script:StatusJson=$Text }
    $null=& (Get-Command Write-Status -CommandType Function).ScriptBlock -Force
    ($script:StatusJson | ConvertFrom-Json).kind | Should -Be 'paused'
    (Get-GuiStateView ([pscustomobject]@{ kind='paused'; state='x' })).State | Should -Match 'Остановлен'
  }
}

Describe 'Пункт 25B: «Стоп» прерывает ожидание ответа Gemini' -Tag Item25,Item25B {
  BeforeEach {
    Use-Base; Set-Files; Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Poll-Tg {}; Mock Sweep-TgPrompts {}; Mock Read-CmdFile {}; Mock Check-LocalControl {}; Mock Write-Status {}; Mock Check-Shutdown {}
    Mock Gem-CopyCode { 'x' }; Mock Ag-Send {}; Mock Relay-ToAg {}; Mock Get-ModelNow { 'Argon' }; Mock Check-OurPrompt {}
  }
  It '«Стоп» во время ожидания ответа Gemini — ожидание прерывается, ответ не копируется и не вставляется' {
    $script:Paused=$false; $script:NeedStart=$false
    [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'sent' -Force)
    Mock Gem-WaitAnswer { Set-Pause $true 'тест'; Pump; 'не должно дойти' }
    Mock Gem-LastReportPrompt { (N 7) }
    { Process-File ((Get-Files) | Where-Object Name -eq (N 7)) } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    Should -Invoke Gem-CopyCode -Times 0; Should -Invoke Ag-Send -Times 0
    Get-Stage (N 7) | Should -Be 'sent'; $script:AbortOnStop | Should -BeFalse
    (Sent '*Текущее действие прервал*').Count | Should -Be 1
  }
}

Describe 'Пункт 25C: «стоп» и «выключи скрипт»' -Tag Item25,Item25C {
  BeforeEach {
    Use-Base; Set-Files; Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
  }
  It '«<T>» -> <K> (строгий и нестрогий)' -TestCases @(
    @{T='стоп';K='stop'},@{T='Стоп';K='stop'},@{T='/stop';K='stop'},@{T='пауза';K='pause'},@{T='Старт';K='resume'},@{T='продолжай';K='resume'},
    @{T='выключи скрипт';K='exit'},@{T='Выключи скрипт';K='exit'},@{T='выключи бота';K='exit'},@{T='заверши работу';K='exit'},@{T='/exit';K='exit'},
    @{T='не выключай скрипт';K='unknown'},@{T='выключи компьютер';K='shutdown'},@{T='отмени выключение';K='shutdowncancel'}) {
    param($T,$K) foreach($s in $true,$false){ (Parse-Command -Text $T -Strict $s).k | Should -Be $K -Because "strict=$s" }
  }
  It '«стоп» — процесс жив (StopReq нет), PAUSE создан; повтор — «Уже СТОП»' {
    Handle-Command 'стоп' 'tg'
    $script:Paused | Should -BeTrue; $script:StopReq | Should -BeFalse; Test-Path $Cfg.PauseFile | Should -BeTrue
    (Sent '⏸ GGskript: Остановлен*').Count | Should -Be 1
    Handle-Command 'пауза' 'tg'; (Sent '⏹ Уже СТОП*').Count | Should -Be 1
  }
  It '«выключи скрипт» из Telegram — только после подтверждения; «Нет» — не выключаю' {
    Handle-Command 'выключи скрипт' 'tg'
    $script:StopReq | Should -BeFalse; $p=PromptOf 'exit'; $p | Should -Not -BeNullOrEmpty; $p.text | Should -Match 'НЕЛЬЗЯ'
    Press $p 'no'; $script:StopReq | Should -BeFalse; (Sent 'Ок, GGskript не выключаю*').Count | Should -Be 1
  }
  It '«выключи скрипт» -> «Да» кнопкой или «да» текстом — процесс завершится' {
    Handle-Command 'выключи скрипт' 'tg'; Press (PromptOf 'exit') 'yes'; $script:StopReq | Should -BeTrue
    $script:StopReq=$false; Handle-Command 'выключи скрипт' 'tg'; Handle-Command 'да' 'tg'; $script:StopReq | Should -BeTrue
  }
  It '«выключи скрипт» с ПК (commands.txt/панель) — без вопроса' { Handle-Command 'выключи скрипт' 'pc'; $script:StopReq | Should -BeTrue; $script:TgPrompts.Count | Should -Be 0 }
  It 'кнопка «Стоп» на СТОП и выход из процесса — главный цикл не завершается сам' {
    Mock Poll-Tg {}; Mock Sweep-TgPrompts {}; Mock Read-CmdFile {}; Mock Check-LocalControl {}; Mock Write-Status {}; Mock Check-Shutdown {}; Mock Nap {}
    $script:Paused=$true; Invoke-MainStep | Should -Be 'ok'
    New-Item -ItemType File $Cfg.StopFile | Out-Null; Invoke-MainStep | Should -Be 'stop'
  }
  It 'помощь: стоп/старт/выключи скрипт и «передай весь ответ»' {
    $HelpText | Should -Match '<b>Стоп</b>'; $HelpText | Should -Match '/exit — выключить скрипт'
    $HelpText | Should -Match 'только блок «Markdown»'; $HelpText | Should -Match '/toag'
  }
  It 'клавиатура: Статус|Стоп|Старт подряд, «Выключи скрипт» только в меню, «Пауза» и «Продолжай» убраны' {
    $l=Get-TgReplyLabels; ($l -join '|') | Should -Match 'ℹ️ Статус\|⏸ Стоп\|▶️ Старт'; $l | Should -Not -Contain 'Выключи скрипт'; (Get-TgMenuCommands).command | Should -Contain 'exit'; $l | Should -Not -Contain 'Пауза'; $l | Should -Not -Contain 'Продолжай'
  }
  It 'ярлыки: GGskript_exit.bat -> STOP (выход); панель: Стоп / Выключить скрипт' {
    $r=Split-Path $PSScriptRoot -Parent
    [IO.File]::ReadAllText((Join-Path $r 'GGskript_exit.bat')) | Should -Match 'STOP'
    $g=[IO.File]::ReadAllText((Join-Path $r 'GGskript_gui.ps1'),[Text.Encoding]::UTF8)
    $g | Should -Match "btnPause=New-Btn '⏸ Стоп'"; $g | Should -Match "miExit=Add-Mi '⛔ Выключить скрипт'"
    foreach($n in 'GGskript_pause.bat','GGskript_start.bat','GGskript_stop.bat'){ Test-Path (Join-Path $r $n) | Should -BeFalse }
  }
}

Describe 'Пункт 25D: передаётся только блок с подписью Markdown' -Tag Item25,Item25D {
  BeforeEach {
    Use-Base; Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
  }
  Context 'выбор по подписям (общая логика UIA/CDP/текст)' {
    It '<D>' -TestCases @(
      @{D='Plaintext+Markdown+Python -> Markdown';L=@('Plaintext','Markdown','Python');P='last';R=1},
      @{D='только Python -> ничего';L=@('Python');P='last';R=-1},
      @{D='Python+Bash+Plaintext -> ничего';L=@('Python','Bash','Plaintext');P='last';R=-1},
      @{D='markdown строчными';L=@('Python','markdown');P='last';R=1},
      @{D='MARKDOWN заглавными';L=@('MARKDOWN');P='last';R=0},
      @{D="'markdown ' с пробелами";L=@('markdown ','Python');P='last';R=0},
      @{D='подпись пустая -> не Markdown';L=@('','Python');P='last';R=-1},
      @{D='подпись — код («Markdown» + перевод строки + текст) -> первая строка';L=@("Markdown`ncontent_copy");P='last';R=0},
      @{D='два Markdown, Pick=last -> второй';L=@('Markdown','Python','Markdown');P='last';R=2},
      @{D='два Markdown, Pick=first -> первый';L=@('Markdown','Python','Markdown');P='first';R=0},
      @{D='похожие подписи (Markdown2, md) — не Markdown';L=@('Markdown2','md','Markdown code');P='last';R=-1}) {
      param($D,$L,$P,$R) Select-CodeBlockIndex -Langs $L -Lang 'Markdown' -Pick $P | Should -Be $R
    }
    It 'список подписей: Markdown и XML подходят, Python нет' { Select-CodeBlockIndex -Langs @('Python','XML','Bash') -Lang 'Markdown,XML' | Should -Be 1; Select-CodeBlockIndex -Langs @('Python','Bash') -Lang 'Markdown,XML' | Should -Be -1; Test-CodeLangMatch 'xml' 'Markdown, XML' | Should -BeTrue; Test-CodeLangMatch 'Plaintext' 'Markdown,XML' | Should -BeFalse }
    It 'пустая настройка CodeBlockLang НЕ означает «любой блок»' { Select-CodeBlockIndex -Langs @('Python','Plaintext') -Lang '' | Should -Be -1; Select-CodeBlockIndex -Langs @('Python','Markdown') -Lang '' | Should -Be 1 }
    It 'длинная «подпись» (это уже текст) — пустая' { Normalize-CodeLang ('x'*41) | Should -Be ''; Normalize-CodeLang '  Mark   down ' | Should -Be 'Mark down' }
  }
  Context 'текстовый путь (CodeFromWholeFallback / Get-MarkdownBlock)' {
    It 'Plaintext+Markdown+Python — берётся только Markdown' {
      $t="Вступление`n``````plaintext`nP`n```````n``````markdown`n## M`nтекст`n```````n``````python`nprint(1)`n```````n"
      Get-MarkdownBlock $t 'Markdown' 'last' | Should -Be "## M`nтекст"
    }
    It 'только Python/без подписи — ничего' {
      Get-MarkdownBlock "``````python`nx`n``````" | Should -BeNullOrEmpty
      Get-MarkdownBlock "``````n## без подписи`n``````" | Should -BeNullOrEmpty
    }
    It 'MARKDOWN заглавными, два блока: last/first' {
      $t="``````MARKDOWN`nA`n```````n``````markdown`nB`n``````"
      Get-MarkdownBlock $t 'Markdown' 'last' | Should -Be 'B'; Get-MarkdownBlock $t 'Markdown' 'first' | Should -Be 'A'
    }
    It 'Gem-CopyCode: блока Markdown нет, во всём ответе только Python — fallback ничего не берёт' {
      $Cfg.CodeFromWholeFallback=$true; Mock Gem-UiaWindow { 1 }; Mock GemUia-CopyCode { $null }; Mock Gem-CopyWhole { "``````python`nprint(1)`n``````" }
      Gem-CopyCode | Should -BeNullOrEmpty
      Mock Gem-CopyWhole { "``````python`np`n```````n``````Markdown`n## ok`n``````" }; Gem-CopyCode | Should -Be '## ok'
    }
  }
  Context 'CDP (Eval-Js замокан)' {
    BeforeEach { $Cfg.GeminiTransport='cdp' }
    AfterEach { $Cfg.GeminiTransport='uia' }
    It 'Plaintext+Markdown+Python -> Markdown; подписи в $LastCodeLangs' {
      Mock Eval-Js { @([pscustomobject]@{lang='Plaintext';code='P'},[pscustomobject]@{lang='Markdown';code='M'},[pscustomobject]@{lang='Python';code='Y'}) }
      GemCdp-GetCode | Should -Be 'M'; $script:LastCodeLangs -join ',' | Should -Be 'Plaintext,Markdown,Python'
    }
    It 'только Python, пустая подпись -> ничего' {
      Mock Eval-Js { @([pscustomobject]@{lang='Python';code='Y'},[pscustomobject]@{lang='';code='Markdown'}) }; GemCdp-GetCode | Should -BeNullOrEmpty
    }
    It "'markdown ' с пробелами и подпись с хвостом иконки" {
      Mock Eval-Js { @([pscustomobject]@{lang=' markdown ';code='M1'}) }; GemCdp-GetCode | Should -Be 'M1'
      Mock Eval-Js { @([pscustomobject]@{lang="Markdown`ncontent_copy";code='M2'}) }; GemCdp-GetCode | Should -Be 'M2'
    }
    It 'два Markdown — last/first' {
      Mock Eval-Js { @([pscustomobject]@{lang='Markdown';code='A'},[pscustomobject]@{lang='Python';code='p'},[pscustomobject]@{lang='Markdown';code='B'}) }
      GemCdp-GetCode | Should -Be 'B'; $Cfg.CodeBlockPick='first'; GemCdp-GetCode | Should -Be 'A'
    }
  }
  Context 'UIA: повторная проверка подписи сразу после копирования' {
    BeforeEach {
      Mock GemUia-FindCodeCopyButton { 'BTN' }; Mock Invoke-WithFocus { & $Body }; Mock Use-TempClipboard { & $Body }
      Mock Set-ClipText {}; Mock Uia-ScrollIntoView {}; Mock Start-Sleep {}; Mock Uia-ClickEl { $true }; Mock Get-IdleMs { 999999 }
      $script:seq=0; Mock Get-ClipSeq { $script:seq++; $script:seq }; Mock Get-ClipText { "## код задачи`nстрока" }
    }
    It 'подпись нажатого блока — Markdown: текст возвращается' { $script:Lbl='Markdown'; Mock GemUia-CodeBlockLang { $script:Lbl }; GemUia-CopyCode 1 | Should -Be "## код задачи`nстрока" }
    It 'подпись после копирования — Python: скопированное отброшено, лог + Telegram' {
      Mock GemUia-CodeBlockLang { 'Python' }
      GemUia-CopyCode 1 | Should -BeNullOrEmpty
      (Sent '⛔ блок кода: после копирования подпись блока — «Python»*').Count | Should -Be 1
      Should -Invoke Log -ParameterFilter { $m -like '*НЕ передаю*' }
    }
    It 'подпись после копирования не читается — тоже отброшено' { Mock GemUia-CodeBlockLang { '' }; GemUia-CopyCode 1 | Should -BeNullOrEmpty }
  }
  Context 'поток: другие блоки без Markdown -> вопрос пункта 21, в Antigravity ничего' {
    BeforeEach {
      Set-Files; [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'sent' -Force)
      Mock Gem-WaitAnswer {}; Mock Get-ModelNow { 'Argon Ultra' }; Mock Check-OurPrompt {}; Mock Gem-LastReportPrompt { (N 7) }
      Mock Gem-CopyCode { $script:LastCodeLangs=@('Python','Plaintext'); $null }; Mock Get-WholeAnswer { @{ text='весь ответ'; via='uia' } }
      Mock Ag-Send {}; Mock Relay-ToAg {}
    }
    It 'Process-File: этап nocode, в вопросе перечислены Python, Plaintext, Ag-Send не вызывался' {
      Process-File ((Get-Files) | Where-Object Name -eq (N 7))
      Get-Stage (N 7) | Should -Be 'nocode'; Should -Invoke Ag-Send -Times 0; Should -Invoke Relay-ToAg -Times 0
      (PromptOf 'nocode').text | Should -Match 'Другие блоки в ответе \(их НЕ передаю — беру только «Markdown»\): Python, Plaintext'
    }
    It '«передай ответ» — без Markdown ничего не передаёт; «передай весь ответ» из Telegram — с подтверждением' {
      Mock Assert-Quota {}; Mock Assert-Argon { 'Argon Ultra' }
      Run-Action @{ k='relay'; whole=$false; src='tg' }
      Should -Invoke Ag-Send -Times 0; (Sent 'В последнем ответе Gemini нет блока Markdown*').Count | Should -Be 1
      Handle-Command 'передай весь ответ' 'tg'; @($script:Queue.ToArray() | Where-Object { $_.k -eq 'fwdans-prep' }).Count | Should -Be 1
    }
  }
}

Describe 'Пункт 25D: настоящий Chromium (headless) и страница с блоками разных подписей' -Tag Item25,Item25D,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $Cfg.CdpPort=9341; $Cfg.CdpUrlLike='fake_gemini_blocks'; $script:CdpConn=$null
      $prof=Join-Path $TestDrive 'chrome_prof25'; $fx=Join-Path $PSScriptRoot 'fixtures'
      $script:proc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run','--allow-file-access-from-files',"--remote-debugging-port=$($Cfg.CdpPort)","--user-data-dir=$prof",('file://'+(Join-Path $fx 'fake_gemini_blocks.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'chrome25.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*fake_gemini_blocks*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    function Scn([string]$k){ [void](Invoke-Cdp 'Runtime.evaluate' @{ expression="setScenario('$k')"; returnByValue=$true }) }
  }
  AfterAll { if($script:CdpConn){ Cdp-Close $script:CdpConn; $script:CdpConn=$null }; if($script:proc){ try{ Get-Process -Id $script:proc.Id -EA 0 | Stop-Process -Force }catch{} } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {}; $Cfg.CodeBlockLang='Markdown'; $Cfg.CodeBlockPick='last' }
  It '<K>: код=<R>, подписи=<L>' -TestCases @(
    @{K='mixed';R="## MD mixed`nтекст";L='Plaintext,Markdown,Python'},
    @{K='pyonly';R=$null;L='Python,Bash'},
    @{K='lower';R='## MD lower';L='Python,markdown'},
    @{K='upper';R='## MD upper';L='MARKDOWN'},
    @{K='nolabel';R=$null;L=''},
    @{K='nodeco';R=$null;L=''},
    @{K='iconfirst';R='## icon first';L='Markdown'},
    @{K='twomd';R='## B';L='Markdown,Python,Markdown'}) {
    param($K,$R,$L)
    Scn $K
    $c=GemCdp-GetCode; if($null -eq $R){ $c | Should -BeNullOrEmpty } else { $c | Should -Be $R }
    $script:LastCodeLangs -join ',' | Should -Be $L
    $pk=GemCdp-PeekAnswer; $pk.answered | Should -BeTrue; $pk.md | Should -Be ($null -ne $R)
  }
  It 'twomd, Pick=first -> «## A»' { Scn 'twomd'; $Cfg.CodeBlockPick='first'; GemCdp-GetCode | Should -Be '## A' }
  It 'весь ответ: заборы с подписями в нижнем регистре; Get-MarkdownBlock по нему берёт тот же Markdown' {
    Scn 'mixed'; $w=GemCdp-GetWhole
    $w | Should -Match '```plaintext'; $w | Should -Match '```markdown'; $w | Should -Not -Match 'content_copy'
    Get-MarkdownBlock $w | Should -Be "## MD mixed`nтекст"
  }
}
