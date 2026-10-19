BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function D([string]$s){ [datetime]::ParseExact($s,'yyyy-MM-dd HH:mm',[Globalization.CultureInfo]::InvariantCulture) }
  function GQ($cur,$curAt,$wk=10,$wkAt=$null,[string]$curTxt='',[string]$wkTxt=''){ @{ time='18:20'; gweb=@{ cur=$cur; curReset=$curTxt; curResetAt=$curAt; wk=$wk; wkReset=$wkTxt; wkResetAt=$wkAt } } }
}

Describe 'Пункт 19: разбор времени сброса лимита (ConvertFrom-ResetText)' -Tag Item19 {
  It '<t> -> <e>' -TestCases @(
    @{t='Лимит обновится в 22:25';                 n='2026-10-18 18:20'; e='2026-10-18 22:25'}
    @{t='Лимит обновится в 12:25';                 n='2026-10-18 18:20'; e='2026-10-19 12:25'}   # время прошло — завтра
    @{t='Лимит обновится в 18:20';                 n='2026-10-18 18:20'; e='2026-10-18 18:20'}
    @{t='Лимит обновится 20 окт. в 15:25';         n='2026-10-18 18:20'; e='2026-10-20 15:25'}
    @{t='Лимит обновится 3 ноября в 9:05';         n='2026-10-18 18:20'; e='2026-11-03 09:05'}
    @{t='Лимит обновится завтра в 03:10';          n='2026-10-18 18:20'; e='2026-10-19 03:10'}
    @{t='Лимит обновится сегодня в 23:59';         n='2026-10-18 18:20'; e='2026-10-18 23:59'}
    @{t='Лимит обновится через 2 ч 15 мин';        n='2026-10-18 18:20'; e='2026-10-18 20:35'}
    @{t='через 40 мин';                            n='2026-10-18 18:20'; e='2026-10-18 19:00'}
    @{t='Лимит обновится в 00:10';                 n='2026-10-18 23:50'; e='2026-10-19 00:10'}   # через полночь
    @{t='Лимит обновится 2 янв. в 00:10';          n='2026-12-31 23:00'; e='2027-01-02 00:10'}   # через год
    @{t='Лимит обновится 31 дек. в 23:30';         n='2026-12-31 23:00'; e='2026-12-31 23:30'}
    @{t='Лимит обновится 31 дек. в 23:59';         n='2027-01-01 00:30'; e='2026-12-31 23:59'}   # старый текст не уезжает на год
    @{t='Resets at 3:25 PM';                       n='2026-10-18 18:20'; e='2026-10-19 15:25'}
    @{t='Resets at 11:05 PM';                      n='2026-10-18 18:20'; e='2026-10-18 23:05'}
    @{t='Resets Oct 20 at 3:25 PM';                n='2026-10-18 18:20'; e='2026-10-20 15:25'}
    @{t='Resets 20 Oct, 15:25';                    n='2026-10-18 18:20'; e='2026-10-20 15:25'}
    @{t='Resets tomorrow at 12:05 AM';             n='2026-10-18 18:20'; e='2026-10-19 00:05'}
    @{t='Resets at 12:30 PM';                      n='2026-10-18 08:00'; e='2026-10-18 12:30'}
    @{t='Limit resets in 45 min';                  n='2026-10-18 18:20'; e='2026-10-18 19:05'}
    @{t='Resets in 3 hours';                       n='2026-10-18 18:20'; e='2026-10-18 21:20'}
    @{t='18.10 23:03';                             n='2026-10-18 18:20'; e='2026-10-18 23:03'}   # формат Antigravity
    @{t="Лимит обновится 20$([char]0x00A0)окт. в$([char]0x202F)15:25"; n='2026-10-18 18:20'; e='2026-10-20 15:25'}
  ) { (ConvertFrom-ResetText $t (D $n)) | Should -Be (D $e) }
  It 'мусор -> $null: «<t>»' -TestCases @(
    @{t=''},@{t='мусор'},@{t='Лимит обновится скоро'},@{t='25:99'},@{t='в 12:75'},@{t='30 фев. в 10:00'},@{t='13:00 PM'},@{t='Использовано 47%'},@{t='через полчаса'}
  ) { ConvertFrom-ResetText $t (D '2026-10-18 18:20') | Should -BeNullOrEmpty }
}

Describe 'Пункт 19: время сброса в разборе лимитов' -Tag Item19 {
  It 'страница лимитов Gemini: curResetAt/wkResetAt' {
    $u=ConvertFrom-UsageText "Текущее использование | Использовано 95% | Лимит обновится в 22:25 | Недельный лимит | Использовано 47% | Лимит обновится 20 окт. в 15:25" (D '2026-10-18 18:20')
    $u.cur | Should -Be 95; $u.curResetAt | Should -Be (D '2026-10-18 22:25'); $u.wkResetAt | Should -Be (D '2026-10-20 15:25')
  }
  It 'страница «лимит исчерпан» без процентов — время сброса всё равно берётся' {
    $u=ConvertFrom-UsageText 'Вы достигли лимита. Лимит обновится в 22:25' (D '2026-10-18 18:20')
    $u.cur | Should -Be 100; $u.curResetAt | Should -Be (D '2026-10-18 22:25')
  }
  It 'Antigravity: resetAt — локальное время сброса' {
    $r=@{ response=@{ groups=@(@{ displayName='Gemini Models'; buckets=@(@{ window='5h'; remainingFraction=0.05; resetTime='2030-10-18T14:03:00Z' },@{ window='week'; remainingFraction=0.5; resetTime='2030-10-24T00:00:00Z' }) }) } }
    $q=ConvertFrom-AgQuota -Response $r -Group 'Gemini Models'
    $q.h5.rem | Should -Be 5
    $q.h5.resetAt | Should -Be ([DateTimeOffset]::Parse('2030-10-18T14:03:00Z').UtcDateTime.ToLocalTime())
  }
}

Describe 'Пункт 19: планирование (Get-AutoResumePlan)' -Tag Item19 {
  BeforeEach { $Cfg.AutoResumeMarginMin=2; $Cfg.AutoResumeRetryMin=10; $Cfg.AutoResumeMaxRetryMin=60; $script:N=D '2026-10-18 18:20' }
  It 'ничего не заблокировано — плана нет' { Get-AutoResumePlan -Q (GQ 10 $null) -LimitStop $false -QStopG $false -QStopA $false -Now $N | Should -BeNullOrEmpty }
  It 'модель не та, а лимит Gemini не исчерпан (текущий случай «Flash Высокая») — попытка сразу' {
    $p=Get-AutoResumePlan -Q (GQ 0 (D '2026-10-18 22:25')) -LimitStop $true -QStopG $false -QStopA $false -Now $N
    $p.at | Should -Be $N; $p.why | Should -Match 'не исчерпан'
  }
  It 'модель не та и лимит исчерпан — время сброса + запас' {
    $p=Get-AutoResumePlan -Q (GQ 100 (D '2026-10-18 22:25')) -LimitStop $true -QStopG $false -QStopA $false -Now $N
    $p.at | Should -Be (D '2026-10-18 22:27'); $p.why | Should -Match 'сброс в 22:25'
  }
  It 'исчерпаны оба лимита Gemini — ждём более поздний сброс' {
    $p=Get-AutoResumePlan -Q (GQ 95 (D '2026-10-18 22:25') 99 (D '2026-10-20 15:25')) -LimitStop $false -QStopG $true -QStopA $false -Now $N
    $p.at | Should -Be (D '2026-10-20 15:27'); $p.why | Should -Match '20\.10 15:25'
  }
  It 'resetAt нет — разбирается текст «Лимит обновится в 22:25»' {
    $p=Get-AutoResumePlan -Q (GQ 95 $null 10 $null 'Лимит обновится в 22:25') -LimitStop $false -QStopG $true -QStopA $false -Now $N
    $p.at | Should -Be (D '2026-10-18 22:27')
  }
  It 'время сброса не прочитано — повтор через AutoResumeRetryMin' {
    $p=Get-AutoResumePlan -Q (GQ 95 $null 10 $null 'непонятно') -LimitStop $false -QStopG $true -QStopA $false -Now $N
    $p.at | Should -Be $N.AddMinutes(10); $p.why | Should -Match 'не прочитано'
  }
  It 'время сброса уже прошло, а лимит ещё не обновился — сейчас + запас' {
    $p=Get-AutoResumePlan -Q (GQ 95 (D '2026-10-18 18:00')) -LimitStop $false -QStopG $true -QStopA $false -Now $N
    $p.at | Should -Be $N.AddMinutes(2)
  }
  It 'лимит Antigravity (5 ч) — его resetAt + запас' {
    $q=@{ ag=@{ h5=@{ rem=5; reset='18.10 23:03'; resetAt=(D '2026-10-18 23:03') }; wk=@{ rem=56; reset='24.10 07:00'; resetAt=(D '2026-10-24 07:00') } } }
    $p=Get-AutoResumePlan -Q $q -LimitStop $false -QStopG $false -QStopA $true -Now $N
    $p.at | Should -Be (D '2026-10-18 23:05'); $p.why | Should -Match 'Antigravity \(5 ч\)'
  }
  It 'лимит Antigravity без resetAt — разбирается строка «18.10 23:03»' {
    $q=@{ ag=@{ h5=@{ rem=0; reset='18.10 23:03'; resetAt=$null } } }
    (Get-AutoResumePlan -Q $q -LimitStop $false -QStopG $false -QStopA $true -Now $N).at | Should -Be (D '2026-10-18 23:05')
  }
  It 'не чаще раза в интервал повтора после прошлой попытки' {
    $p=Get-AutoResumePlan -Q (GQ 0 $null) -LimitStop $true -QStopG $false -QStopA $false -Now $N -LastAttempt $N.AddMinutes(-3)
    $p.at | Should -Be $N.AddMinutes(7)
  }
  It 'после неудач интервал растёт x2 и упирается в AutoResumeMaxRetryMin' {
    Get-AutoResumeRetryMin 0 | Should -Be 10; Get-AutoResumeRetryMin 1 | Should -Be 10; Get-AutoResumeRetryMin 2 | Should -Be 20; Get-AutoResumeRetryMin 3 | Should -Be 40; Get-AutoResumeRetryMin 9 | Should -Be 60
  }
}

Describe 'Пункт 19: Update-AutoPlan — сообщение о запланированной проверке' -Tag Item19 {
  BeforeEach {
    $Cfg.AutoResume=$true; $Cfg.AutoSwitchModel=$true; $script:AutoPlan=$null; $script:AutoPlanKey=''; $script:AutoFails=0; $script:AutoLastAttempt=$null
    $script:LimitStop=$true; $script:QStopG=$false; $script:QStopA=$false
    $script:Q=GQ 100 ((Get-Date).Date.AddDays(1).AddHours(3))
    Mock Tg-Send { $true }; Mock Log {}
  }
  It 'одно сообщение в Telegram «жду сброса… проверю в HH:MM … верну Argon», повтор того же плана — без сообщения' {
    Update-AutoPlan; Update-AutoPlan
    Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '⏰ Жду сброса лимита: проверю в *верну модель Argon*' }
    $script:AutoPlan.at | Should -Be ((Get-Date).Date.AddDays(1).AddHours(3).AddMinutes(2))
  }
  It 'AutoResume=false — плана нет, сообщений нет' { $Cfg.AutoResume=$false; Update-AutoPlan; $script:AutoPlan | Should -BeNullOrEmpty; Should -Invoke Tg-Send -Times 0 }
  It 'ничего не заблокировано — план сбрасывается' { $script:LimitStop=$false; $script:AutoPlan=@{ at=(Get-Date) }; Update-AutoPlan; $script:AutoPlan | Should -BeNullOrEmpty }
  It 'статус для панели: resumeAt и текст состояния' {
    Update-AutoPlan
    Mock Next-FileName { $null }; Mock Write-AtomicText { $script:StatusJson=$Text }
    $script:St=New-RelayState; Write-Status -Force
    ($script:StatusJson | ConvertFrom-Json).resumeAt | Should -Be ((Get-Date).Date.AddDays(1).AddHours(3).AddMinutes(2).ToString('dd.MM HH:mm'))
    (Get-GuiStateView ($script:StatusJson | ConvertFrom-Json)).Model | Should -Match 'жду сброса в'
  }
}

Describe 'Пункт 19: Invoke-AutoResume — возобновление и невозобновление' -Tag Item19 {
  BeforeEach {
    $Cfg.AutoResume=$true; $Cfg.AutoSwitchModel=$true; $Cfg.GeminiWebCheck=$true
    $script:AutoPlan=@{ at=(Get-Date); why='тест' }; $script:AutoPlanKey=''; $script:AutoFails=0; $script:AutoLastAttempt=$null
    $script:LimitStop=$true; $script:LimitModel='Flash Высокая'; $script:LimitSince=Get-Date; $script:QStopG=$false; $script:QStopA=$false; $script:Paused=$false
    $script:FakeQ=GQ 0 (D '2026-10-18 22:25'); $script:FakeQb=''; $script:Model='Flash Высокая'
    Mock Check-Quotas { $script:Q=$script:FakeQ; 'ok' }
    Mock Quota-Blocked { $script:FakeQb }
    Mock Get-ModelNow { $script:LastModel=$script:Model; $script:Model }
    Mock Gem-SelectModel { $script:Model='Argon Высокая'; $script:Model }
    Mock Next-FileName { 'MyProject_2026-10-18_003.md' }
    Mock Start-Sleep {}; Mock Tg-Send { $true }; Mock Log {}
  }
  It 'лимит обновился, модель Flash — переключает на Argon и снимает остановку (сообщение в Telegram)' {
    Invoke-AutoResume | Should -BeTrue
    Should -Invoke Gem-SelectModel -Times 1 -ParameterFilter { $Want -eq 'Argon' }
    $script:LimitStop | Should -BeFalse; $script:AutoPlan | Should -BeNullOrEmpty; $script:AutoFails | Should -Be 0
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '▶️ Работа возобновлена (автоматически после сброса лимита). Модель: Argon Высокая*MyProject_2026-10-18_003.md*' }
  }
  It 'модель уже Argon — без переключения, остановка снята' {
    $script:Model='Argon Средний'; Invoke-AutoResume | Should -BeTrue; Should -Invoke Gem-SelectModel -Times 0; $script:LimitStop | Should -BeFalse
  }
  It 'лимит Gemini ещё не обновился — модель не трогает, остаётся стоять, сообщает время следующей попытки' {
    $script:FakeQ=GQ 95 ((Get-Date).AddHours(3))
    Invoke-AutoResume | Should -BeFalse
    Should -Invoke Gem-SelectModel -Times 0; $script:LimitStop | Should -BeTrue; $script:AutoFails | Should -Be 1
    $script:AutoPlan.at | Should -BeGreaterThan (Get-Date).AddHours(2)
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '⏳ Автовозобновление не удалось: лимит Gemini ещё не обновился*следующая попытка в*' }
  }
  It 'остановка по порогу лимитов не снялась (Quota-Blocked) — остаётся стоять' {
    $script:LimitStop=$false; $script:QStopA=$true; $script:FakeQb='лимит Antigravity'
    Invoke-AutoResume | Should -BeFalse; Should -Invoke Gem-SelectModel -Times 0
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '*лимит ещё не обновился (лимит Antigravity)*' }
  }
  It 'страница лимитов не прочитана — не переключает' {
    $script:FakeQ=@{ time='x'; gwebErr='окно Gemini не найдено' }
    Invoke-AutoResume | Should -BeFalse; Should -Invoke Gem-SelectModel -Times 0
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '*страница лимитов Gemini не прочитана (окно Gemini не найдено)*' }
  }
  It 'сбой переключения — сообщение в Telegram с причиной, остаёмся стоять' {
    Mock Gem-SelectModel { throw 'пункт «4 Argon Сложные задачи» недоступен (лимит ещё не обновился?)' }
    Invoke-AutoResume | Should -BeFalse
    $script:LimitStop | Should -BeTrue
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '⏳ Автовозобновление не удалось: не удалось переключить модель на Argon: пункт «4 Argon Сложные задачи» недоступен*Остаюсь на остановке*' }
    Should -Invoke Tg-Send -Times 0 -ParameterFilter { $Text -like '▶️*' }
  }
  It 'переключили, но Gemini оставил другую модель — сбой, остаёмся стоять' {
    Mock Gem-SelectModel { 'Flash Высокая' }
    Invoke-AutoResume | Should -BeFalse; $script:LimitStop | Should -BeTrue
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '*после переключения выбрана «Flash Высокая»*' }
  }
  It 'остановка только по порогу, лимит снят, а модель не Argon и переключение не удалось — встаём в остановку по модели' {
    $script:LimitStop=$false; Mock Gem-SelectModel { throw 'меню моделей не открылось' }
    Invoke-AutoResume | Should -BeFalse; $script:LimitStop | Should -BeTrue
  }
  It 'AutoSwitchModel=false — модель не переключает, просит выбрать вручную' {
    $Cfg.AutoSwitchModel=$false
    Invoke-AutoResume | Should -BeFalse; Should -Invoke Gem-SelectModel -Times 0; $script:LimitStop | Should -BeTrue
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '*AutoSwitchModel=false*' }
  }
  It 'ручная пауза пользователя не снимается автовозобновлением' {
    $script:Paused=$true
    Invoke-AutoResume | Should -BeTrue; $script:LimitStop | Should -BeFalse; $script:Paused | Should -BeTrue
  }
}

Describe 'Пункт 19: главный цикл' -Tag Item19 {
  BeforeEach {
    $Cfg.QuotaEveryMin=0; $Cfg.AgQueueCheckSec=0; $Cfg.AcceptAllEverySec=0; $Cfg.AutoResume=$true; $Cfg.ModelRecheckSec=60
    $script:NeedStart=$false; $script:LimitStop=$true; $script:LimitModel='Flash Высокая'; $script:Paused=$false; $script:Queue.Clear(); $script:Busy=$false
    $script:LastLimitCheck=Get-Date; $script:AutoPlanKey=''
    Mock Pump {}; Mock Nap {}; Mock Check-Blocking {}; Mock Quota-Blocked { $null }; Mock Write-Host {}; Mock Log {}; Mock Notify {}; Mock Tg-Send { $true }
    Mock Next-File { $null }; Mock Process-File {}; Mock Invoke-AutoResume { $true }; Mock Update-AutoPlan {}
    Remove-Item $Cfg.StopFile -EA 0
  }
  It 'время пришло — попытка автовозобновления' { $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }; Invoke-MainStep | Should -Be 'continue'; Should -Invoke Invoke-AutoResume -Times 1 }
  It 'время не пришло — ждёт, в состоянии «жду сброса, проверю в HH:MM»' {
    $at=(Get-Date).AddHours(2); $script:AutoPlan=@{ at=$at; why='x' }
    Invoke-MainStep | Should -Be 'ok'; Should -Invoke Invoke-AutoResume -Times 0
    $script:State | Should -BeLike "*жду сброса, проверю в $(Format-PlanTime $at)*"
  }
  It 'плана нет — строится (Update-AutoPlan)' { $script:AutoPlan=$null; Invoke-MainStep | Out-Null; Should -Invoke Update-AutoPlan -Times 1 }
  It 'на ручной паузе — не возобновляет' { $script:Paused=$true; $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }; Invoke-MainStep | Out-Null; Should -Invoke Invoke-AutoResume -Times 0 }
  It 'AutoResume=false — не возобновляет' { $Cfg.AutoResume=$false; $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }; Invoke-MainStep | Out-Null; Should -Invoke Invoke-AutoResume -Times 0 }
  It 'остановка по порогу лимитов — тоже по плану' { $script:LimitStop=$false; Mock Quota-Blocked { 'лимит Antigravity' }; $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }; Invoke-MainStep | Should -Be 'continue'; Should -Invoke Invoke-AutoResume -Times 1 }
  It 'файл STOP важнее автовозобновления' { New-Item $Cfg.StopFile -ItemType File | Out-Null; $script:AutoPlan=@{ at=(Get-Date).AddMinutes(-1); why='x' }; Invoke-MainStep | Should -Be 'stop'; Should -Invoke Invoke-AutoResume -Times 0 }
  It 'Enter-LimitStop сбрасывает план и сообщает про автовозобновление' {
    $script:LimitStop=$false; $script:AutoPlan=@{ at=(Get-Date) }; Enter-LimitStop 'Flash Высокая' $null
    $script:AutoPlan | Should -BeNullOrEmpty
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '*После сброса лимита сам проверю страницу лимитов, верну Argon и продолжу.*' }
  }
}

Describe 'Пункт 19: переключение модели через UIA (моки)' -Tag Item19 {
  BeforeEach {
    $script:Model='Flash Высокая'; $script:MenuOpen=$false; $script:ExpandOk=$true; $script:Esc=0; $script:Invoked=@(); $script:ArgonEnabled=$true; $script:MenuWorks=$true; $script:Gen=$false
    $script:Btn=[pscustomobject]@{ name='Выбор режима, сейчас используется Flash Высокая'; kind='btn' }
    Mock Uia-FindAll {
      if($ControlType -eq 'Button'){ return @($script:Btn) }
      if($ControlType -eq 'MenuItem'){ if(-not $script:MenuOpen){ return @() }
        return @([pscustomobject]@{name='3.5 Flash-Lite Самые быстрые ответы';enabled=$true},[pscustomobject]@{name='Выбрано 3.8 Flash All-around help';enabled=$true},
                 [pscustomobject]@{name='3.1 Pro Расширенные возможности рассуждения';enabled=$true},[pscustomobject]@{name='4 Argon Сложные задачи';enabled=$script:ArgonEnabled},
                 [pscustomobject]@{name='Уровень рассуждений';enabled=$true}) }
      @()
    }
    Mock Uia-Name { [string]$el.name }; Mock Uia-IsOffscreen { $false }; Mock Uia-IsEnabled { if($null -ne $el.enabled){ [bool]$el.enabled } else { $true } }
    Mock Uia-ExpandState { if($script:MenuOpen){ 'Expanded' } else { 'Collapsed' } }
    Mock Uia-Expand { if($script:MenuWorks){ $script:MenuOpen=$true }; $script:ExpandOk }
    Mock Uia-Collapse { $script:MenuOpen=$false; $true }
    Mock Uia-ClickEl { if($script:MenuWorks){ $script:MenuOpen=$true }; $true }
    Mock Uia-Invoke { $script:Invoked+=$el.name; if($el.name -match 'Argon'){ $script:Model='Argon Высокая' }; $script:MenuOpen=$false; $true }
    Mock PressEsc { $script:Esc++; $script:MenuOpen=$false }
    Mock GemUia-GetModel { $script:Model }; Mock GemUia-IsGenerating { $script:Gen }
    Mock Invoke-WithFocus { & $Body }; Mock Start-Sleep {}; Mock Log {}
  }
  It 'выбирает «4 Argon Сложные задачи» (не выбранный Flash и не «Уровень рассуждений»), меню закрыто' {
    GemUia-SelectModel 1 'Argon' | Should -Be 'Argon Высокая'
    $script:Invoked | Should -Be @('4 Argon Сложные задачи'); $script:MenuOpen | Should -BeFalse
  }
  It 'Argon уже выбран — меню не открывается' { $script:Model='Argon Средний'; GemUia-SelectModel 1 'Argon' | Should -Be 'Argon Средний'; Should -Invoke Uia-Expand -Times 0 }
  It 'пункт Argon недоступен — исключение, ничего не нажато, меню закрыто' {
    $script:ArgonEnabled=$false
    { GemUia-SelectModel 1 'Argon' } | Should -Throw '*«4 Argon Сложные задачи» недоступен*'
    $script:Invoked.Count | Should -Be 0; $script:MenuOpen | Should -BeFalse
  }
  It 'нет пункта — исключение со списком пунктов (без префикса «Выбрано», без «Уровень рассуждений»)' {
    try{ GemUia-SelectModel 1 'Ultra'; throw 'нет исключения' }catch{ $m=$_.Exception.Message }
    $m | Should -BeLike '*нет пункта «Ultra»*3.8 Flash All-around help*'; $m | Should -Not -BeLike '*Выбрано*'; $m | Should -Not -BeLike '*Уровень*'
    $script:MenuOpen | Should -BeFalse
  }
  It 'меню не открылось — исключение' { $script:MenuWorks=$false; { GemUia-SelectModel 1 'Argon' } | Should -Throw '*меню моделей не открылось*' }
  It 'Expand не поддерживается — открывает кликом' { $script:ExpandOk=$false; $script:MenuWorks=$true; Mock Uia-Expand { $false }; GemUia-SelectModel 1 'Argon' | Should -Be 'Argon Высокая'; Should -Invoke Uia-ClickEl -Times 1 }
  It 'Gemini отвечает — не переключает' { $script:Gen=$true; { GemUia-SelectModel 1 'Argon' } | Should -Throw '*не переключаю*'; Should -Invoke Uia-Expand -Times 0 }
  It 'меню не закрылось по Collapse — Esc' { Mock Uia-Collapse { $false }; Mock Get-ForegroundHandle { 1 }; Mock Uia-Invoke { $script:Invoked+=$el.name; $script:Model='Argon Высокая'; $true }; GemUia-SelectModel 1 'Argon' | Out-Null; $script:Esc | Should -Be 1; $script:MenuOpen | Should -BeFalse }
  It 'GemUia-ListModels: пункты с отметкой выбранной, меню закрывается, ничего не выбрано' {
    $l=GemUia-ListModels 1
    $l.current | Should -Be 'Flash Высокая'
    @($l.items).Count | Should -Be 4
    (@($l.items) | Where-Object { $_.selected }).name | Should -Be '3.8 Flash All-around help'
    $script:Invoked.Count | Should -Be 0; $script:MenuOpen | Should -BeFalse
  }
  It 'Switch-ToArgon через общий интерфейс (UIA) — проверяет результат' {
    Mock Gem-UiaWindow { 1 }; Mock Gem-GetModel { $script:Model }
    Switch-ToArgon | Should -Be 'Argon Высокая'
  }
}

Describe 'Пункт 19: переключение модели через CDP (подменённый Eval-Js)' -Tag Item19 {
  BeforeEach {
    $script:Model='Flash Высокая'; $script:Open=$false; $script:Closed=0; $script:PickArg=$null; $script:PickRes=@{ ok=$true; name='4 Argon Сложные задачи' }
    Mock Eval-Js {
      switch($Op){
        'model' { $script:Model }
        'state' { @{ gen=$false } }
        'modelOpen' { $script:Open=$true; $true }
        'modelItems' { if($script:Open){ @(@{name='Выбрано 3.8 Flash All-around help';enabled=$true;selected=$true},@{name='4 Argon Сложные задачи';enabled=$true;selected=$false},@{name='Уровень рассуждений';enabled=$true;selected=$false}) } else { @() } }
        'modelPick' { $script:PickArg=$Arg; if($script:PickRes.ok){ $script:Model='Argon Высокая' }; $script:PickRes }
        'modelClose' { $script:Closed++; $script:Open=$false; $true }
      }
    }
    Mock Start-Sleep {}
  }
  It 'выбирает Argon, передаёт ModelMenuSkipRx, закрывает меню' {
    GemCdp-SelectModel 'Argon' | Should -Be 'Argon Высокая'
    $script:PickArg.want | Should -Be 'Argon'; $script:PickArg.skip | Should -Be $Cfg.ModelMenuSkipRx; $script:Closed | Should -Be 1
  }
  It 'пункт недоступен — исключение, меню закрыто' { $script:PickRes=@{ ok=$false; err='disabled'; name='4 Argon Сложные задачи' }; { GemCdp-SelectModel 'Argon' } | Should -Throw '*недоступен*'; $script:Closed | Should -Be 1 }
  It 'список моделей: выбранная отмечена, «Уровень рассуждений» пропущен' { $l=GemCdp-ListModels; @($l.items).Count | Should -Be 2; (@($l.items) | Where-Object selected).name | Should -Be '3.8 Flash All-around help' }
  It 'Gem-SelectModel с GeminiTransport=cdp идёт через CDP' { $Cfg.GeminiTransport='cdp'; try{ Gem-SelectModel 'Argon' | Should -Be 'Argon Высокая' } finally { $Cfg.GeminiTransport='uia' } }
}

Describe 'Пункт 19: CDP-переключатель модели на настоящем Chromium (headless)' -Tag Item19,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $Cfg.CdpPort=9341; $Cfg.CdpUrlLike='fake_gemini_models'
      $fx=Join-Path $PSScriptRoot 'fixtures'; $prof=Join-Path $TestDrive 'chrome_prof19'
      $script:proc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.CdpPort)","--user-data-dir=$prof",('file://'+(Join-Path $fx 'fake_gemini_models.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'chrome19.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*fake_gemini_models*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:CdpConn=$null
  }
  AfterAll { if($script:CdpConn){ Cdp-Close $script:CdpConn; $script:CdpConn=$null }; if($script:proc){ try{ Get-Process -Id $script:proc.Id -EA 0 | Stop-Process -Force }catch{}; Get-Process chrom* -EA 0 | Where-Object { $_.Parent.Id -eq $script:proc.Id } | Stop-Process -Force -EA 0 } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {} }
  It 'список моделей: 4 пункта, выбрана Flash, меню закрыто после чтения' {
    GemCdp-GetModel | Should -Be 'Flash Высокая'
    $l=GemCdp-ListModels; @($l.items).Count | Should -Be 4; (@($l.items) | Where-Object selected).name | Should -Be '3.8 Flash All-around help'
    (Invoke-Cdp 'Runtime.evaluate' @{ expression="document.getElementById('menu').classList.contains('open')"; returnByValue=$true }).result.value | Should -BeFalse
  }
  It 'Argon недоступен (aria-disabled) — исключение, модель не изменилась, меню закрыто' {
    [void](Invoke-Cdp 'Runtime.evaluate' @{ expression="document.getElementById('argon').setAttribute('aria-disabled','true')"; returnByValue=$true })
    { GemCdp-SelectModel 'Argon' } | Should -Throw '*недоступен*'
    GemCdp-GetModel | Should -Be 'Flash Высокая'
    (Invoke-Cdp 'Runtime.evaluate' @{ expression="document.getElementById('menu').classList.contains('open')"; returnByValue=$true }).result.value | Should -BeFalse
    [void](Invoke-Cdp 'Runtime.evaluate' @{ expression="document.getElementById('argon').removeAttribute('aria-disabled')"; returnByValue=$true })
  }
  It 'выбор Argon: нажат именно пункт Argon, модель «Argon Высокая»' {
    GemCdp-SelectModel 'Argon' | Should -Be 'Argon Высокая'
    (Invoke-Cdp 'Runtime.evaluate' @{ expression="JSON.stringify(window.__picked)"; returnByValue=$true }).result.value | Should -Be '["4 Argon Сложные задачи"]'
  }
}

Describe 'Пункт 19 (найдено вживую): Check-OurPrompt в длинном чате' -Tag Item19 {
  BeforeEach { Mock Log {} }
  It 'число запросов уменьшилось, но последний отчёт — наш файл: ответ берётся' { Mock Gem-CountPrompts { 9 }; Mock Gem-LastReportPrompt { 'A_2026-10-18_003.md' }; { Check-OurPrompt 10 'A_2026-10-18_003.md' } | Should -Not -Throw }
  It 'число запросов не выросло и последний отчёт чужой — исключение' { Mock Gem-CountPrompts { 10 }; Mock Gem-LastReportPrompt { 'A_2026-10-18_002.md' }; { Check-OurPrompt 10 'A_2026-10-18_003.md' } | Should -Throw '*Не вижу нашего сообщения*' }
  It 'без имени файла (сообщение «/gemini») — прежняя строгая проверка' { Mock Gem-CountPrompts { 9 }; Mock Gem-LastReportPrompt { 'x' }; { Check-OurPrompt 10 } | Should -Throw '*Не вижу*' }
  It 'число выросло — без проверки отчёта' { Mock Gem-CountPrompts { 11 }; Mock Gem-LastReportPrompt { throw 'не должно' }; { Check-OurPrompt 10 'A.md' } | Should -Not -Throw }
}
