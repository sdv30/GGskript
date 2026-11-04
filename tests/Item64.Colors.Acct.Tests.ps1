BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Gui=Get-Content -Raw -Encoding UTF8 (Join-Path $script:V2Root 'GGskript_gui.ps1')
  $script:Rel=Get-Content -Raw -Encoding UTF8 (Join-Path $script:V2Root 'lib/Relay.ps1')
  function Get-Lum([int[]]$c){ $f={ param($v) $x=$v/255.0; if($x -le 0.03928){ $x/12.92 } else { [Math]::Pow(($x+0.055)/1.055,2.4) } }; 0.2126*(& $f $c[0])+0.7152*(& $f $c[1])+0.0722*(& $f $c[2]) }
}
Describe '27.10 цвета журнала: Get-LogLevel / Get-LogLevels / Get-LogColor' -Tag Item64 {
  It 'красный: ⛔ ❌ «не удалось» ОШИБКА Exception' {
    foreach($s in '12:00:01  ⛔ лимит Argon закончен','12:00:01  ❌ [Eskalator] файл не отправлен','12:00:01  Модель: не удалось переключить','12:00:01  ОШИБКА: что-то','12:00:01  System.Exception: boom','12:00:01  ⏳ Автовозобновление не удалось: лимит'){ Get-LogLevel $s | Should -Be 'error' }
  }
  It 'жёлтый: ⚠ ⏳ ⏭ ⚖ ожидание / лимиты / повтор' {
    foreach($s in '12:00:01  ⚠️ Лимиты:','12:00:01  ⏳ агент ещё работает — жду','12:00:01  ⏭ пропускаю файл','12:00:01  ⚖ Очередь: файл','12:00:01  Gemini сейчас генерирует ответ — жду','12:00:01  Автовозобновление: проверяю лимиты (x)','12:00:01  Повтор после ошибки'){ Get-LogLevel $s | Should -Be 'warn' }
  }
  It 'зелёный: ✅ «отправлено» «передан» «нажат» ▶️ возобновлена' {
    foreach($s in '12:00:01  ✅ Accept all нажат (1 files)','12:00:01  Отправлено в Antigravity через CDP','12:00:01  Этап: a.md → ответ передан в Antigravity','12:00:01  ▶️ Лимиты в норме, работа возобновлена','12:00:01  ✅ Аккаунт сменён, Argon доступен — продолжаю'){ Get-LogLevel $s | Should -Be 'ok' }
  }
  It 'голубой: обычная работа (этап, новый файл, ход) и строки ▸ панели' {
    foreach($s in '12:00:01  Новый файл: A_2026-10-27_004.md','12:00:01  Этап: A_2026-10-27_004.md → отправлен в Gemini, ждёт ответа','12:00:01  👉 Ход: Gemini — генерирует','▸ 12:00:01  Модель Gemini: Argon | лимит: Gemini 90%'){ Get-LogLevel $s | Should -Be 'info' }
  }
  It 'серый: служебное (модель всё ещё, Лимиты: проверено, Команда с ПК, эхо «> », строка аккаунта)' {
    foreach($s in '12:00:01  Лимит: модель всё ещё «Flash-Lite»','12:00:01  Лимиты: проверено в 17:04; Gemini 92% | ⛔ Остановлено по лимиту','12:00:01  Команда с ПК: /pc_acct','12:00:01  > ⏸ GGskript: Остановлен (ПК)','12:00:01  Аккаунт: u1|Аккаунт Google: Имя; модель «Flash-Lite»; Argon: недоступен'){ Get-LogLevel $s | Should -Be 'dim' }
    Get-LogLevel '12:00:01  Аккаунт: вкладку Gemini выбрать не удалось (x)' | Should -Be 'error'   # серое только для строки состояния «Аккаунт: u…»
  }
  It 'продолжение записи (без времени) наследует уровень; явные значки в продолжении — свой' {
    Get-LogLevel '• Gemini (сайт), текущее: использовано 92%' | Should -Be ''
    (Get-LogLevels @('12:00:01  ⚠️ Лимиты:','• Gemini (сайт): 92%','⛔ Передачу останавливаю','просто текст') 'info') -join ',' | Should -Be 'warn,warn,error,error'
    (Get-LogLevels @('без времени') 'ok') | Should -Be @('ok')
    (Get-LogLevels @('без времени') '') | Should -Be @('info')
    (Get-LogLevels @() 'info').Count | Should -Be 0
  }
  It 'цвета читаются на тёмном фоне (24,24,28): контраст ≥ 4.5:1, все уровни разные' {
    $bg=Get-Lum @(24,24,28); $seen=@{}
    foreach($lv in 'error','warn','ok','info','dim',''){ $c=@(Get-LogColor $lv); $c.Count | Should -Be 3; $L=Get-Lum $c; (($L+0.05)/($bg+0.05)) | Should -BeGreaterThan 4.5; $seen["$($c -join ',')"]=1 }
    $seen.Count | Should -Be 6
  }
  It 'ограничение длины: с головы убирается целое число строк, хвост цел' {
    Get-LogTrimCount ('x'*100) 250000 150000 | Should -Be 0
    $t=((1..5000|%{ "строка номер $_" }) -join "`n")+"`n"
    $n=Get-LogTrimCount $t 20000 10000
    $n | Should -BeGreaterThan 0; $t.Substring($n-1,1) | Should -Be "`n"; ($t.Length-$n) | Should -BeLessThan 10200; ($t.Length-$n) | Should -BeGreaterThan 9000
  }
  It 'GUI: журнал красится построчно, дописываются только новые строки, длина ограничена' {
    $script:Gui | Should -Match 'function Add-LogLines'
    $script:Gui | Should -Match 'Get-LogLevels \$lines \$script:logPrevLevel'
    $script:Gui | Should -Match 'Get-LogTrimCount'
    $script:Gui | Should -Not -Match '\$txtLog\.AppendText\(\$r\.Text\)'
    $script:Gui | Should -Match 'ReadOnly=\$false; try\{ \$txtLog\.Select\(0,\$cut\)'
    $script:Gui | Should -Match 'function Write-PanelLog\(\[string\]\$m\)\{ Add-LogLines'
    $script:Gui | Should -Match 'function Add-InfoLog[\s\S]{0,200}Add-LogLines'
  }
}
Describe '27.10 аккаунт: решение раз в минуту (Get-AccountWatchAction)' -Tag Item64 {
  BeforeAll { $script:t0=[datetime]'2026-10-27 18:00:00' }
  It 'первое наблюдение — только запомнить' { (Get-AccountWatchAction '' 'u0|a' $false $true $false $null $t0 5).act | Should -Be 'baseline' }
  It 'аккаунт сменён + Argon выбран/доступен в меню -> resume (changed)' {
    $d=Get-AccountWatchAction 'u0|a' 'u1|b' $true $null $false $null $t0 5; $d.act | Should -Be 'resume'; $d.changed | Should -BeTrue
    $d=Get-AccountWatchAction 'u0|a' 'u1|b' $false $true $false $null $t0 5; $d.act | Should -Be 'resume'; $d.changed | Should -BeTrue
  }
  It 'аккаунт сменён, но Argon недоступен -> ждать (не пытаться)' { $d=Get-AccountWatchAction 'u0|a' 'u1|b' $false $false $false $null $t0 5; $d.act | Should -Be 'none'; $d.changed | Should -BeTrue }
  It 'без смены: Argon появился в меню (край) -> resume; дальше — не чаще раза в RetryMin; Argon недоступен -> none' {
    (Get-AccountWatchAction 'u0|a' 'u0|a' $false $true $false $null $t0 5).act | Should -Be 'resume'
    (Get-AccountWatchAction 'u0|a' 'u0|a' $false $true $true $t0.AddMinutes(-2) $t0 5).act | Should -Be 'none'
    (Get-AccountWatchAction 'u0|a' 'u0|a' $false $true $true $t0.AddMinutes(-6) $t0 5).act | Should -Be 'resume'
    (Get-AccountWatchAction 'u0|a' 'u0|a' $false $false $false $null $t0 5).act | Should -Be 'none'
  }
  It 'Argon уже выбран, аккаунт тот же — без повторных попыток каждую минуту' { (Get-AccountWatchAction 'u0|a' 'u0|a' $true $null $true $t0.AddMinutes(-60) $t0 5).act | Should -Be 'none' }
}
Describe '27.10 аккаунт: Invoke-AccountWatch и «Сменил аккаунт» на заглушках' -Tag Item64 {
  BeforeEach {
    $script:logged=New-Object System.Collections.ArrayList
    Mock Log { [void]$script:logged.Add([string]$m) }
    Mock Select-GeminiTabNow { @{ changed=$false; url='https://gemini.google.com/u/1/app/x' } }
    Mock Get-GemAccountKey { $script:acct }
    Mock Get-ModelNow { $script:model }
    Mock Test-ArgonInMenu { $script:menu }
    Mock Invoke-AutoResume { $true }
    $Cfg.GeminiTransport='cdp'; $Cfg.AccountWatch=$true; $Cfg.AutoResume=$true; $Cfg.AccountMenuProbeMin=5; $Cfg.AccountRetryMin=10; $Cfg.ModelMustContain='Argon'
    $script:acct='u0|Аккаунт A'; $script:model='Flash-Lite'; $script:menu=$false
    $script:AcctKey=''; $script:AcctSum=''; $script:AcctPrevAvail=$false; $script:AcctMenuAvail=$false; $script:AcctMenuAt=[datetime]::MinValue; $script:AutoLastAttempt=$null; $script:AcctErrSaid=''
  }
  It 'Test-AccountWatchOn: только CDP, AccountWatch и AutoResume' {
    Test-AccountWatchOn | Should -BeTrue
    $Cfg.AccountWatch=$false; Test-AccountWatchOn | Should -BeFalse; $Cfg.AccountWatch=$true
    $Cfg.GeminiTransport='uia'; Test-AccountWatchOn | Should -BeFalse
  }
  It 'минута 1: запоминает, не возобновляет; серая строка один раз, повтор без изменений не пишет' {
    Invoke-AccountWatch | Should -BeFalse
    Invoke-AccountWatch | Should -BeFalse; Invoke-AccountWatch | Should -BeFalse
    Should -Invoke Invoke-AutoResume -Times 0 -Exactly
    @($script:logged | Where-Object { $_ -like 'Аккаунт: u0*' }).Count | Should -Be 1
    $script:AcctKey | Should -Be 'u0|Аккаунт A'
  }
  It 'сменили аккаунт, Argon доступен в меню -> зелёная строка и Invoke-AutoResume' {
    [void](Invoke-AccountWatch)
    $script:acct='u1|Аккаунт B'; $script:menu=$true
    Invoke-AccountWatch | Should -BeTrue
    Should -Invoke Invoke-AutoResume -Times 1 -Exactly
    @($script:logged | Where-Object { $_ -eq '✅ Аккаунт сменён, Argon доступен — продолжаю' }).Count | Should -Be 1
    (Get-LogLevel ('12:00:00  '+'✅ Аккаунт сменён, Argon доступен — продолжаю')) | Should -Be 'ok'
  }
  It 'сменили аккаунт, Argon всё ещё недоступен -> не пытается, ждёт' {
    [void](Invoke-AccountWatch)
    $script:acct='u1|Аккаунт B'; $script:menu=$false
    Invoke-AccountWatch | Should -BeFalse
    Should -Invoke Invoke-AutoResume -Times 0 -Exactly
    $script:AcctKey | Should -Be 'u1|Аккаунт B'
  }
  It 'Argon уже выбран после смены аккаунта -> возобновляет без открытия меню' {
    [void](Invoke-AccountWatch)
    $script:acct='u1|Аккаунт B'; $script:model='ArgonВысокий'
    Invoke-AccountWatch | Should -BeTrue
    Should -Invoke Test-ArgonInMenu -Times 1 -Exactly   # только baseline-вызов; после смены аккаунта меню не открывали
  }
  It 'меню открывается не чаще раза в AccountMenuProbeMin; Argon появился в меню без смены аккаунта -> resume' {
    [void](Invoke-AccountWatch); [void](Invoke-AccountWatch)
    Should -Invoke Test-ArgonInMenu -Times 1 -Exactly
    $script:menu=$true; $script:AcctMenuAt=(Get-Date).AddMinutes(-6)
    Invoke-AccountWatch | Should -BeTrue
    Should -Invoke Test-ArgonInMenu -Times 2 -Exactly; Should -Invoke Invoke-AutoResume -Times 1 -Exactly
    @($script:logged | Where-Object { $_ -eq '✅ Argon доступен — продолжаю' }).Count | Should -Be 1
  }
  It 'вкладку выбрать не удалось -> одна строка, не возобновляет, не падает' {
    Mock Select-GeminiTabNow { throw 'CDP не отвечает' }
    Invoke-AccountWatch | Should -BeFalse; Invoke-AccountWatch | Should -BeFalse
    @($script:logged | Where-Object { $_ -like '*вкладку Gemini выбрать не удалось*' }).Count | Should -Be 1
  }
  It 'кнопка: лимит ещё не в норме -> остаётся на остановке, причина в журнал, Resume-Work не вызван' {
    Mock Check-Quotas { 'x' }; Mock Quota-Blocked { 'лимит Gemini (сайт)' }; Mock Resume-Work {}; Mock Switch-ToArgon { 'Argon' }
    $script:LimitStop=$true
    Invoke-AccountSwitched | Should -BeFalse
    Should -Invoke Resume-Work -Times 0 -Exactly
    @($script:logged | Where-Object { $_ -like '*лимит ещё не в норме*' }).Count | Should -Be 1
    Should -Invoke Select-GeminiTabNow -Times 1 -Exactly -ParameterFilter { $Force }
  }
  It 'кнопка: лимит в норме, модель Flash-Lite -> Argon выбран, работа продолжена' {
    Mock Check-Quotas { 'x' }; Mock Quota-Blocked { '' }; Mock Resume-Work {}; Mock Switch-ToArgon { 'ArgonВысокий' }
    $script:LimitStop=$true; $Cfg.AutoSwitchModel=$true
    Invoke-AccountSwitched | Should -BeTrue
    Should -Invoke Switch-ToArgon -Times 1 -Exactly; Should -Invoke Resume-Work -Times 1 -Exactly
  }
  It 'кнопка: Argon не переключился -> ⚠ в журнал, работа не продолжена' {
    Mock Check-Quotas { 'x' }; Mock Quota-Blocked { '' }; Mock Resume-Work {}; Mock Switch-ToArgon { throw 'пункт Argon недоступен' }
    $script:LimitStop=$true; $Cfg.AutoSwitchModel=$true
    Invoke-AccountSwitched | Should -BeFalse
    Should -Invoke Resume-Work -Times 0 -Exactly
    @($script:logged | Where-Object { $_ -like '⚠*Argon недоступен*' }).Count | Should -Be 1
  }
  It 'кнопка: лимит в норме, Argon уже выбран -> без переключения, Resume-Work' {
    Mock Check-Quotas { 'x' }; Mock Quota-Blocked { '' }; Mock Resume-Work {}; Mock Switch-ToArgon { 'Argon' }
    $script:LimitStop=$true; $script:model='ArgonВысокий'
    Invoke-AccountSwitched | Should -BeTrue
    Should -Invoke Switch-ToArgon -Times 0 -Exactly; Should -Invoke Resume-Work -Times 1 -Exactly
  }
}
Describe '27.10 кнопка «Сменил аккаунт»: панель -> /pc_acct -> очередь -> действие' -Tag Item64 {
  BeforeEach { Mock Log {}; $script:Queue=New-Object System.Collections.Queue; $script:Paused=$false }
  It 'Invoke-PcButton acct ставит одну команду; повторное нажатие не дублирует' {
    Invoke-PcButton 'acct' ''; Invoke-PcButton 'acct' ''
    $script:Queue.Count | Should -Be 1; $script:Queue.Peek().k | Should -Be 'acctchanged'
  }
  It 'остановлен (Стоп) — кнопка ничего не ставит' { $script:Paused=$true; Invoke-PcButton 'acct' ''; $script:Queue.Count | Should -Be 0 }
  It '/pc_acct через Handle-Command доходит до очереди' {
    Handle-Command '/pc_acct' 'pc'; $script:Queue.Count | Should -Be 1
  }
  It 'Run-ActionCore acctchanged вызывает Invoke-AccountSwitched; при СТОП — нет' {
    Mock Invoke-AccountSwitched { $true }
    Run-ActionCore @{ k='acctchanged'; src='pc' }; Should -Invoke Invoke-AccountSwitched -Times 1 -Exactly
    $script:Paused=$true; { Run-ActionCore @{ k='acctchanged'; src='pc' } } | Should -Throw; $script:Paused=$false
    'acctchanged' | Should -BeIn $script:WindowKinds
  }
  It 'GUI: кнопка в строке «АККАУНТ», шлёт /pc_acct, защита от двойного клика, не дублирует другие кнопки' {
    $script:Gui | Should -Match "Add-BtnRow 'АККАУНТ' @\(\`$btnAcct\)"
    $script:Gui | Should -Match "\`$btnAcct\.Add_Click\(\{\s*Send-Cmd '/pc_acct'"
    $script:Gui | Should -Match '\$btnAcct\.Enabled=\$false'
    ([regex]::Matches($script:Gui,'New-Btn ''🔄 Сменил аккаунт''')).Count | Should -Be 1
    ([regex]::Matches($script:Gui,'Add-BtnRow ''[^'']*'' @\([^)]*btnAcct')).Count | Should -Be 1
  }
  It 'главный цикл: минутная проверка на остановке по лимиту; «Лимит: модель всё ещё» — только при смене модели' {
    $script:Rel | Should -Match 'Test-AccountWatchOn\)\)\{'
    $script:Rel | Should -Match 'Invoke-AccountWatch\)\{ return ''continue'' \}'
    $script:Rel | Should -Match 'LastLimitModelLog -ne \$m'
  }
  It 'настройки по умолчанию: AccountWatch включён, период 60 с' {
    $d=Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive
    $d.AccountWatch | Should -BeTrue; $d.AccountWatchSec | Should -Be 60; $d.AccountMenuProbeMin | Should -BeGreaterThan 0
  }
}