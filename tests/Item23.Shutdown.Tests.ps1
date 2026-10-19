BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:StubDef=(Get-Item function:Invoke-ShutdownExe).ScriptBlock.ToString()
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function Reset-Tg{
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100; $script:ShCalls=New-Object System.Collections.ArrayList
    $script:TgPrompts.Clear(); $script:TgAwait=$null; $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:PendingConfirm=$null; $script:Blk=@{key=$null}
  }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
  function Calls([string]$M){ ,@($script:TgCalls | Where-Object { $_.m -eq $M }) }
  function LastPrompt{ @($script:TgPrompts.Values)[-1] }
  function Press($p,[string]$choice,[string]$cb='cb1'){ Handle-Callback "p:$($p.id):$choice" $cb $p.msgId }
  function Restart-Sim{ $script:ShutPlan=$null; $script:ShutLoaded=$false }
}
Describe 'Пункт 23: выключение компьютера по команде из Telegram' -Tag Item23 {
  BeforeEach {
    Reset-Tg
    $Cfg.ShutdownEnabled=$true; $Cfg.ShutdownForce=$false; $Cfg.ShutdownConfirmMin=2; $Cfg.ShutdownNowDelaySec=60; $Cfg.ShutdownWarnSec=60; $Cfg.ShutdownLateMin=2
    $Cfg.ShutdownFile=(Join-Path $TestDrive 'relay_shutdown.json'); Remove-Item $Cfg.ShutdownFile -EA 0; Restart-Sim
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Invoke-ShutdownExe { [void]$script:ShCalls.Add(@($ArgList)); @{ code=$script:ShCode; out='' } }
    $script:ShCode=0
  }

  Context 'разбор команд' {
    It '«<T>» -> <K> <M>' -TestCases @(
      @{T='выключи компьютер';K='shutdown';M='now'},@{T='Выключи ПК';K='shutdown';M='now'},@{T='выключи компьютер сейчас';K='shutdown';M='now'},
      @{T='выключи компьютер в 14-00';K='shutdown';M='at'},@{T='выключи компьютер в 14:00';K='shutdown';M='at'},@{T='выключи компьютер в 14.00';K='shutdown';M='at'},
      @{T='выключи компьютер в 14';K='shutdown';M='at'},@{T='выключи пк в 9 часов';K='shutdown';M='at'},@{T='выключи компьютер через 30 минут';K='shutdown';M='in'},
      @{T='выключи компьютер через 2 часа';K='shutdown';M='in'},@{T='выключи пк через час';K='shutdown';M='in'},@{T='выключи пк через полчаса';K='shutdown';M='in'},
      @{T='выключи пк через 1 ч 30 мин';K='shutdown';M='in'},@{T='/shutdown';K='shutdown';M='now'},@{T='/shutdown 23:15';K='shutdown';M='at'},@{T='/shutdown в 23-15';K='shutdown';M='at'},
      @{T='/shutdown +45';K='shutdown';M='in'},@{T='/shutdown@ExampleBot +5';K='shutdown';M='in'},
      @{T='выключи компьютер завтра';K='shutdown';M='bad'},@{T='выключи компьютер в 25:00';K='shutdown';M='bad'},@{T='выключи компьютер в 14:75';K='shutdown';M='bad'},@{T='выключи компьютер через немного';K='shutdown';M='bad'},
      @{T='отмени выключение';K='shutdowncancel';M=''},@{T='не выключай';K='shutdowncancel';M=''},@{T='не выключай компьютер';K='shutdowncancel';M=''},@{T='/shutdown_cancel';K='shutdowncancel';M=''},@{T='/shutdown cancel';K='shutdowncancel';M=''},
      @{T='когда выключение';K='shutdownstatus';M=''},@{T='когда выключишь компьютер?';K='shutdownstatus';M=''},@{T='/shutdown_status';K='shutdownstatus';M=''}) {
      param($T,$K,$M)
      foreach($st in $true,$false){ $c=Parse-Command -Text $T -Strict $st; $c.k | Should -Be $K -Because "strict=$st"; if($M){ $c.spec.mode | Should -Be $M } }
    }
    It 'значения: 14-00 -> 14:00, через 2 часа -> 120 мин, 1 ч 30 мин -> 90, +45 -> 45' {
      (Parse-Command 'выключи компьютер в 14-00').spec.h | Should -Be 14; (Parse-Command 'выключи компьютер в 9.05').spec.m | Should -Be 5
      (Parse-Command 'выключи компьютер через 2 часа').spec.min | Should -Be 120
      (Parse-Command 'выключи пк через 1 ч 30 мин').spec.min | Should -Be 90
      (Parse-Command 'выключи пк через 2 часа и 15 минут').spec.min | Should -Be 135
      (Parse-Command '/shutdown +45').spec.min | Should -Be 45
    }
    It 'нет конфликта со «стоп»: «<T>» -> <K> (строгий и нестрогий)' -TestCases @(
      @{T='выключи';K='stop'},@{T='выключи скрипт';K='exit'},@{T='выключи реле';K='exit'},@{T='выключи бота';K='exit'},@{T='выключись';K='stop'},@{T='стоп';K='stop'},@{T='/stop';K='stop'},@{T='не выключайся';K='unknown'}) {
      param($T,$K)
      foreach($st in $true,$false){ (Parse-Command -Text $T -Strict $st).k | Should -Be $K -Because "strict=$st" }
    }
  }

  Context 'время: ближайшее, прошедшее -> завтра' {
    It 'в 14:00, сейчас 13:00 -> сегодня' { $r=Resolve-ShutdownTime @{mode='at';h=14;m=0} ([datetime]'2026-10-18 13:00'); $r.at | Should -Be ([datetime]'2026-10-18 14:00'); $r.tomorrow | Should -BeFalse }
    It 'в 14:00, сейчас 15:00 -> завтра' { $r=Resolve-ShutdownTime @{mode='at';h=14;m=0} ([datetime]'2026-10-18 15:00'); $r.at | Should -Be ([datetime]'2026-10-19 14:00'); $r.tomorrow | Should -BeTrue }
    It 'ровно сейчас -> завтра' { (Resolve-ShutdownTime @{mode='at';h=14;m=0} ([datetime]'2026-10-18 14:00')).at | Should -Be ([datetime]'2026-10-19 14:00') }
    It 'переход года' { (Resolve-ShutdownTime @{mode='at';h=0;m=10} ([datetime]'2026-12-31 23:30')).at | Should -Be ([datetime]'2027-01-01 00:10') }
    It 'через 30 мин и сейчас (+60 с)' {
      (Resolve-ShutdownTime @{mode='in';min=30} ([datetime]'2026-10-18 13:00')).at | Should -Be ([datetime]'2026-10-18 13:30')
      (Resolve-ShutdownTime @{mode='now'} ([datetime]'2026-10-18 13:00') 60).at | Should -Be ([datetime]'2026-10-18 13:01')
    }
    It 'Format-ShutWhen: сегодня/завтра/дата' {
      $n=[datetime]'2026-10-18 13:00'
      Format-ShutWhen ([datetime]'2026-10-18 14:00') $n | Should -Be 'сегодня в 14:00'
      Format-ShutWhen ([datetime]'2026-10-19 14:00') $n | Should -Be 'завтра (19.10) в 14:00'
      Format-ShutWhen ([datetime]'2026-10-25 14:00') $n | Should -Be '25.10.2026 в 14:00'
    }
    It 'вопрос сообщает, что сегодняшнее время прошло' {
      $h=(Get-Date).AddHours(-1); if($h.Date -ne (Get-Date).Date){ Set-ItResult -Skipped -Because 'около полуночи'; return }
      Handle-Command "выключи компьютер в $($h.ToString('HH:mm'))" 'tg'
      (Sent '*уже прошло — значит, завтра*').Count | Should -Be 1
    }
  }

  Context 'подтверждение' {
    It 'запрос — вопрос с inline Да/Нет, shutdown.exe не вызывается, плана нет' {
      Handle-Command 'выключи компьютер через 30 минут' 'tg'
      $p=LastPrompt; $p.kind | Should -Be 'shutdown'
      $s=(Sent '*Выключить компьютер*'); $s.Count | Should -Be 1
      $s[0].b.reply_markup.inline_keyboard[0][0].callback_data | Should -Be "p:$($p.id):yes"
      $s[0].b.text | Should -Match 'несохранённой работой могут помешать'
      $script:ShCalls.Count | Should -Be 0; Test-Path $Cfg.ShutdownFile | Should -BeFalse
      ($p.expires - $p.created).TotalMinutes | Should -BeLessOrEqual 2.01
    }
    It '«Да» кнопкой (без принуждения) — план сохранён, shutdown.exe не вызывается, точное время в ответе' {
      Handle-Command 'выключи компьютер через 30 минут' 'tg'; Press (LastPrompt) 'yes'
      $script:ShCalls.Count | Should -Be 0
      $pl=Get-ShutdownPlan; $pl | Should -Not -BeNullOrEmpty; $pl.force | Should -BeFalse
      ($pl.at-(Get-Date)).TotalMinutes | Should -BeGreaterThan 28
      (Sent '*запланировано*точное время*').Count | Should -Be 1
      (Calls 'answerCallbackQuery').Count | Should -Be 1
    }
    It 'ShutdownForce=true — shutdown /s /f /t <сек> /c …' {
      $Cfg.ShutdownForce=$true
      Handle-Command 'выключи компьютер через 30 минут' 'tg'; Press (LastPrompt) 'yes'
      $script:ShCalls.Count | Should -Be 1; $a=$script:ShCalls[0]
      $a[0..2] -join ' ' | Should -Be '/s /f /t'; [int]$a[3] | Should -BeGreaterThan 1700; [int]$a[3] | Should -BeLessOrEqual 1800; $a[4] | Should -Be '/c'
      (Get-ShutdownPlan).force | Should -BeTrue
    }
    It 'ShutdownForce=true, ошибка shutdown.exe — план не сохраняется' {
      $Cfg.ShutdownForce=$true; $script:ShCode=1190
      Handle-Command 'выключи компьютер' 'tg'; Press (LastPrompt) 'yes'
      Get-ShutdownPlan | Should -BeNullOrEmpty; (Sent '*вернул 1190*').Count | Should -Be 1
    }
    It 'текстом «да» — подтверждает' {
      Handle-Command 'выключи компьютер в 23-59' 'tg'; Handle-Command 'да' 'tg'
      Get-ShutdownPlan | Should -Not -BeNullOrEmpty
    }
    It '«Нет» / текстом «нет» — ничего не планируется' {
      Handle-Command 'выключи компьютер' 'tg'; Press (LastPrompt) 'no'
      Handle-Command 'выключи компьютер' 'tg'; Handle-Command 'нет' 'tg'
      Get-ShutdownPlan | Should -BeNullOrEmpty; $script:ShCalls.Count | Should -Be 0
      (Sent 'Ок, компьютер не выключаю.').Count | Should -Be 2
    }
    It 'таймаут — «НЕ запланировано», потом кнопка и «да» не действуют' {
      Handle-Command 'выключи компьютер' 'tg'; $p=LastPrompt; $p.expires=(Get-Date).AddSeconds(-1)
      Sweep-TgPrompts
      (Sent '*НЕ запланировано*').Count | Should -Be 1
      Press $p 'yes'; Handle-Command 'да' 'tg'
      Get-ShutdownPlan | Should -BeNullOrEmpty; $script:ShCalls.Count | Should -Be 0
    }
    It '«сейчас» — через 60 с, предупреждение уже дано' {
      Handle-Command 'выключи компьютер' 'tg'; Press (LastPrompt) 'yes'
      $pl=Get-ShutdownPlan; ($pl.at-(Get-Date)).TotalSeconds | Should -BeGreaterThan 50; $pl.warned | Should -BeTrue
    }
    It 'непонятное время — примеры, без вопроса' {
      Handle-Command 'выключи компьютер завтра' 'tg'
      $script:TgPrompts.Count | Should -Be 0; (Sent '*Не понял время выключения*').Count | Should -Be 1
    }
    It 'ShutdownEnabled=false — отказ' {
      $Cfg.ShutdownEnabled=$false; Handle-Command 'выключи компьютер' 'tg'
      $script:TgPrompts.Count | Should -Be 0; (Sent '*ShutdownEnabled=false*').Count | Should -Be 1
    }
    It 'с ПК (commands.txt) — только из Telegram' {
      Handle-Command 'выключи компьютер' 'pc'; $script:TgPrompts.Count | Should -Be 0; (Sent '*только командой из Telegram*').Count | Should -Be 1
    }
    It 'нажатие из чужого chat_id — не подтверждает' {
      Handle-Command 'выключи компьютер' 'tg'; $p=LastPrompt
      $script:StartUnix=0; $script:TgOffset=0
      $upd=@{ result=@(@{ update_id=9; callback_query=@{ id='cbE'; data="p:$($p.id):yes"; from=@{ id=666 }; message=@{ message_id=$p.msgId; chat=@{ id=666 } } } }) }
      Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query }); if($Method -eq 'getUpdates'){ $upd } else { @{ ok=$true; result=$true } } }
      Poll-Tg
      $p.done | Should -BeNullOrEmpty; Get-ShutdownPlan | Should -BeNullOrEmpty
    }
  }

  Context 'отмена, статус, сохранение плана' {
    It 'план переживает перезапуск; статус показывает время' {
      $at=(Get-Date).Date.AddDays(1).AddHours(14)
      Save-ShutdownPlan @{ at=$at; force=$false; warned=$false; created='x'; how='ggskript' }
      Restart-Sim
      (Get-ShutdownPlan).at | Should -Be $at
      Handle-Command 'когда выключение' 'tg'
      (Sent "*$($at.ToString('dd.MM.yyyy HH:mm'))*").Count | Should -Be 1
      $script:St=New-RelayState; Mock Get-ModelNow { 'Argon' }; Mock Ag-GetWindow { $null }; Mock Next-FileName { $null }; Mock Quota-Text { '-' }
      Get-StatusText | Should -Match 'Выключение компьютера: завтра'
    }
    It 'нет плана — «не запланировано»' { Handle-Command 'когда выключение' 'tg'; (Sent 'Выключение компьютера не запланировано.').Count | Should -Be 1 }
    It 'отмена плана GGskript — без shutdown /a, файл удалён' {
      Save-ShutdownPlan @{ at=(Get-Date).AddHours(1); force=$false }
      Handle-Command 'отмени выключение' 'tg'
      $script:ShCalls.Count | Should -Be 0; Test-Path $Cfg.ShutdownFile | Should -BeFalse; Restart-Sim; Get-ShutdownPlan | Should -BeNullOrEmpty
      (Sent '*Выключение отменено*').Count | Should -Be 1
    }
    It 'отмена таймера Windows — shutdown /a' {
      Save-ShutdownPlan @{ at=(Get-Date).AddHours(1); force=$true }
      Handle-Command '/shutdown_cancel' 'tg'
      $script:ShCalls.Count | Should -Be 1; $script:ShCalls[0] -join ' ' | Should -Be '/a'
    }
    It 'плана нет — всё равно shutdown /a; 1116 -> «отменять нечего»' {
      $script:ShCode=1116; Handle-Command 'не выключай' 'tg'
      $script:ShCalls[0] -join ' ' | Should -Be '/a'; (Sent '*отменять нечего*').Count | Should -Be 1
    }
    It 'замена прежнего таймера Windows: сначала /a, потом /s' {
      $Cfg.ShutdownForce=$true; Save-ShutdownPlan @{ at=(Get-Date).AddHours(1); force=$true }
      Handle-Command 'выключи компьютер через 10 минут' 'tg'; (Sent '*заменю*').Count | Should -Be 1; Press (LastPrompt) 'yes'
      ($script:ShCalls | ForEach-Object { $_[0] }) -join ',' | Should -Be '/a,/s'
    }
  }

  Context 'главный цикл: предупреждение, выключение, опоздание' {
    It 'за минуту — одно предупреждение с кнопкой отмены; кнопка отменяет' {
      $at=[datetime]'2026-10-18 14:00'; Save-ShutdownPlan @{ at=$at; force=$false; warned=$false }
      Check-Shutdown -Now $at.AddMinutes(-5); (Sent '*выключу компьютер*').Count | Should -Be 0
      Check-Shutdown -Now $at.AddSeconds(-50); Check-Shutdown -Now $at.AddSeconds(-40)
      (Sent '⚠️ Через*выключу компьютер*').Count | Should -Be 1
      Restart-Sim; (Get-ShutdownPlan).warned | Should -BeTrue
      $p=LastPrompt; $p.kind | Should -Be 'shutwarn'; Press $p 'abort'
      Get-ShutdownPlan | Should -BeNullOrEmpty
    }
    It 'время пришло (режим GGskript) — shutdown /s /t 0 без /f, план удалён до вызова' {
      $at=[datetime]'2026-10-18 14:00'; Save-ShutdownPlan @{ at=$at; force=$false; warned=$true }
      Mock Invoke-ShutdownExe { [void]$script:ShCalls.Add(@($ArgList)); $script:PlanAtCall=(Test-Path $Cfg.ShutdownFile); @{ code=0; out='' } }
      Check-Shutdown -Now $at.AddSeconds(5)
      $script:ShCalls.Count | Should -Be 1; $a=$script:ShCalls[0]
      ($a[0..2] -join ' ') | Should -Be '/s /t 0'; $a | Should -Not -Contain '/f'
      $script:PlanAtCall | Should -BeFalse
      Check-Shutdown -Now $at.AddSeconds(10); $script:ShCalls.Count | Should -Be 1
    }
    It 'GGskript не работал и опоздал > 2 мин — НЕ выключает, сообщает' {
      $at=[datetime]'2026-10-18 14:00'; Save-ShutdownPlan @{ at=$at; force=$false; warned=$false }
      Restart-Sim; Check-Shutdown -Now $at.AddMinutes(10)
      $script:ShCalls.Count | Should -Be 0; (Sent '*пропущено*НЕ выключаю*').Count | Should -Be 1; Get-ShutdownPlan | Should -BeNullOrEmpty
    }
    It 'таймер Windows — GGskript сам shutdown.exe не вызывает; после срока план удаляется' {
      $at=[datetime]'2026-10-18 14:00'; Save-ShutdownPlan @{ at=$at; force=$true; warned=$true }
      Check-Shutdown -Now $at.AddSeconds(5); $script:ShCalls.Count | Should -Be 0
      Check-Shutdown -Now $at.AddMinutes(5); Get-ShutdownPlan | Should -BeNullOrEmpty; $script:ShCalls.Count | Should -Be 0
    }
  }

  Context 'безопасность и помощь' {
    It 'предохранитель: без Mock Invoke-ShutdownExe бросает исключение' { $script:StubDef | Should -Match 'ПРЕДОХРАНИТЕЛЬ' }
    It 'shutdown.exe вызывается только из Platform.Win.ps1; Stop-Computer/Restart-Computer нигде' {
      foreach($f in Get-ChildItem (Join-Path $V2Root 'lib') -Filter *.ps1){ $src=Get-Content $f.FullName -Raw
        $src | Should -Not -Match 'Stop-Computer|Restart-Computer'
        if($f.Name -ne 'Platform.Win.ps1'){ $src | Should -Not -Match "System32\\\\shutdown\.exe'" } }
    }
    It 'в помощи есть команды выключения' { $HelpText | Should -Match 'выключи компьютер'; $HelpText | Should -Match '/shutdown_cancel'; $HelpText | Should -Match 'когда выключение' }
    It 'кнопки «Выключи ПК» в постоянной клавиатуре нет' { (Get-TgReplyLabels) -join '|' | Should -Not -Match '(?i)компьют|ПК' }
  }
}
