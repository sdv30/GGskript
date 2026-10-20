BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  if(-not (Get-Command Tg-Send -EA 0)){ function Tg-Send($t){} }
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function New-Report($name,$text='отчёт'){ $p=Join-Path $Cfg.Downloads $name; [IO.File]::WriteAllText($p,$text); Get-Item $p }
  function Reset-Fake{
    $script:Field=''; $script:Value=''; $script:Clip=''; $script:Enter=0; $script:Cleared=0; $script:Pastes=0; $script:Focus=0
    $script:Hung=$false; $script:Ping=$true; $script:Resp=$true; $script:Ghost=$false; $script:NoWin=$false
    $script:FakePid=3288; $script:Hwnd=202; $script:InputFound=$true; $script:PasteWorks=$true; $script:SendWorks=$true; $script:SlowMs=0
    $script:Typing=$false; $script:TypeN=0
  }
}
Describe 'Пункт 20: зависание Antigravity и чужой текст' -Tag Item20 {
  BeforeEach {
    Reset-Fake
    $Cfg.AgCoordFallback=$false; $Cfg.AgVerifyPaste='strict'; $Cfg.AgTransport='uia'; $Cfg.AgAutoRestartMin=0; $Cfg.AgBlockRemindMin=30
    $script:AgBlock=$null; $script:AgPending=$null
    Mock Log {}; Mock Tg-Send { $true }; Mock Start-Sleep {}
    Mock Get-TopWindows {
      $w=@([pscustomobject]@{h=101;title='chrome';class='Chrome_WidgetWin_1';pid=1;proc='chrome'})
      if(-not $script:NoWin){ $w+=[pscustomobject]@{h=$script:Hwnd;title='proj - Antigravity IDE';class='Chrome_WidgetWin_1';pid=$script:FakePid;proc='Antigravity'} }
      if($script:Ghost){ $w+=[pscustomobject]@{h=909;title='proj - Antigravity IDE (Не отвечает)';class='Ghost';pid=77;proc='dwm'} }
      $w }
    Mock Test-WindowHung { $script:Hung }
    Mock Test-WindowPing { $script:Ping }
    Mock Test-ProcessResponding { $script:Resp }
    Mock Invoke-WithFocus { $script:Focus++; & $Body }
    Mock AgUia-FindInput { if($script:SlowMs){ $script:Sw=$script:SlowMs }; if($script:InputFound){ "INPUT@$h" } else { $null } }
    Mock Uia-Focus { $true }; Mock Uia-ClickEl { $true }; Mock Uia-IsFocused { $true }
    Mock Uia-Name { 'Message input' }
    Mock Uia-GetValue { $script:Value }
    Mock Uia-GetText { if($script:Typing){ $script:TypeN++; "печатаю$($script:TypeN)" } elseif($script:Field){ $script:Field } else { 'Message input' } }
    Mock Use-TempClipboard { & $Body }
    Mock Set-ClipText { $script:Clip=$Text }
    Mock Paste { $script:Pastes++; if($script:PasteWorks){ $script:Field+=$script:Clip } }
    Mock ClearField { $script:Field=''; $script:Cleared++ }
    Mock PressEnter { $script:Enter++; if($script:SendWorks){ $script:Field='' } }
    Mock ClickRel {}
  }

  Context 'чтение поля и плейсхолдер (причина ложной тревоги 18:35)' {
    It 'пустое поле: Value='''' и TextPattern=''Message input'' — это плейсхолдер, текст пустой' {
      $f=AgUia-ReadField 'INPUT'
      $f.text | Should -Be ''; $f.placeholder | Should -BeTrue; $f.raw | Should -Be 'Message input'
    }
    It 'плейсхолдер по AgPlaceholderRx, даже если имя поля другое' {
      Mock Uia-Name { 'chat' }; Mock Uia-GetText { 'Ask anything (Ctrl+L)' }
      (AgUia-ReadField 'INPUT').text | Should -Be ''
    }
    It 'непустой Value важнее TextPattern' {
      $script:Value='черновик'
      (AgUia-ReadField 'INPUT').text | Should -Be 'черновик'
    }
    It 'пустое поле с плейсхолдером: AgUia-Send вставляет и отправляет (ложной тревоги нет)' {
      AgUia-Send -Text "## Задача`nсделай X" -Label 'ответ на A_003'
      $script:Enter | Should -Be 1; $script:Pastes | Should -Be 1
    }
  }

  Context 'признаки зависания' {
    It 'IsHungAppWindow — hung, к окну не обращается (без фокуса, вставки, Enter)' {
      $script:Hung=$true
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.GetType().FullName | Should -Be 'GG.AgBlockedException'; $_.Exception.Kind | Should -Be 'hung' }
      $script:Focus | Should -Be 0; $script:Pastes | Should -Be 0; $script:Enter | Should -Be 0
    }
    It 'WM_NULL не обработан за таймаут — hung' {
      $script:Ping=$false; $h=Get-AgHealth
      $h.kind | Should -Be 'hung'; ($h.reasons -join ';') | Should -BeLike '*WM_NULL*'
    }
    It 'окно-призрак «(Не отвечает)» — hung, даже если основное окно не видно' {
      $script:Ghost=$true; $script:NoWin=$true
      (Get-AgHealth).kind | Should -Be 'hung'
    }
    It 'Process.Responding=false — hung' { $script:Resp=$false; (Get-AgHealth).kind | Should -Be 'hung' }
    It 'нет окна и призрака — nowindow' { $script:NoWin=$true; (Get-AgHealth).kind | Should -Be 'nowindow' }
    It 'всё в порядке — ok, без ложных признаков' { $h=Get-AgHealth; $h.ok | Should -BeTrue; $h.pid | Should -Be 3288 }
    It 'таймаут UIA: поиск поля дольше AgUiaSlowMs и поле не найдено — hung' {
      $Cfg.AgUiaSlowMs=0; $script:InputFound=$false
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'hung'; $_.Exception.Message | Should -BeLike '*UIA*' }
      $Cfg.AgUiaSlowMs=5000
    }
    It 'вставка не принята (поле не изменилось) — hung «не принимает ввод», Enter не нажат' {
      $script:PasteWorks=$false
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'hung'; $_.Exception.Message | Should -BeLike '*не принимает ввод*' }
      $script:Enter | Should -Be 0
    }
    It 'после вставки окно перестало отвечать — hung с причиной' {
      $script:PasteWorks=$false; Mock Paste { $script:Ping=$false }
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'hung'; $_.Exception.Message | Should -BeLike '*после вставки*' }
    }
    It 'вставка изменила поле, но маркера нет — unknown с диагностикой' {
      Mock Paste { $script:Field='что-то другое' }
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'unknown'; $_.Exception.Detail | Should -BeLike '*симв.*' }
      $script:Enter | Should -Be 0
    }
  }

  Context 'настоящий чужой текст' {
    It 'чужой текст — foreign, первые 40 символов, поле не тронуто, вставки нет' {
      $script:Field='Мой длинный черновик для агента, который я ещё не дописал до конца'
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'foreign'; $_.Exception.Detail | Should -Be 'Мой длинный черновик для агента, который…' }
      $script:Pastes | Should -Be 0; $script:Cleared | Should -Be 0; $script:Field | Should -BeLike 'Мой длинный*'
    }
    It 'текст меняется между чтениями (пользователь печатает) — foreign, не трогает' {
      $script:Typing=$true
      try{ AgUia-Send -Text '## Задача'; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'foreign'; $_.Exception.Message | Should -BeLike '*печатает*' }
      $script:Pastes | Should -Be 0
    }
  }

  Context 'одно сообщение в Telegram на состояние' {
    It 'повтор того же состояния — одно сообщение; напоминание только через AgBlockRemindMin' {
      $e=[GG.AgBlockedException]::new('hung','Antigravity не отвечает','IsHungAppWindow=true')
      Report-AgBlock $e 'A_003.md'; Report-AgBlock $e 'A_003.md'; Report-AgBlock $e 'A_003.md'
      Should -Invoke Tg-Send -Times 1 -Exactly
      Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '⏸ Antigravity не отвечает (зависло) — жду*сохранён*' }
      $script:AgBlock.notifiedAt=(Get-Date).AddMinutes(-31)
      Report-AgBlock $e 'A_003.md'
      Should -Invoke Tg-Send -Times 2 -Exactly
      Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '🔔 Напоминание*' }
    }
    It 'AgBlockRemindMin=0 — без напоминаний' {
      $Cfg.AgBlockRemindMin=0; $e=[GG.AgBlockedException]::new('hung','x','y')
      Report-AgBlock $e 'A'; $script:AgBlock.notifiedAt=(Get-Date).AddHours(-5); Report-AgBlock $e 'A'
      Should -Invoke Tg-Send -Times 1 -Exactly
    }
    It 'смена состояния (hung → foreign) — новое сообщение с первыми 40 символами' {
      Report-AgBlock ([GG.AgBlockedException]::new('hung','x','y')) 'A'
      Report-AgBlock ([GG.AgBlockedException]::new('foreign','x','черновик')) 'A'
      Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like "*в поле чата Antigravity чужой текст: 'черновик'*" }
      Should -Invoke Tg-Send -Times 2 -Exactly
    }
    It 'неясный случай — отдельное сообщение с диагностикой' {
      Report-AgBlock ([GG.AgBlockedException]::new('unknown','Текст не появился','после вставки: text: 3 симв.')) 'A'
      Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '*причина не ясна*Диагностика: после вставки*' }
    }
    It 'автоперезапуск выключен по умолчанию — Antigravity не трогается' {
      (Get-DefaultSettings -Root $TestDrive).AgAutoRestartMin | Should -Be 0
      Mock Restart-Antigravity { 'x' }
      $e=[GG.AgBlockedException]::new('hung','x','y'); Report-AgBlock $e 'A'; $script:AgBlock.since=(Get-Date).AddHours(-3); Report-AgBlock $e 'A'
      Should -Invoke Restart-Antigravity -Times 0
    }
    It 'автоперезапуск включён (AgAutoRestartMin=5) — один раз после 5 мин зависания' {
      $Cfg.AgAutoRestartMin=5; Mock Restart-Antigravity { 'C:\AG\Antigravity.exe' }
      $e=[GG.AgBlockedException]::new('hung','x','y'); Report-AgBlock $e 'A'
      Should -Invoke Restart-Antigravity -Times 0
      $script:AgBlock.since=(Get-Date).AddMinutes(-6); Report-AgBlock $e 'A'; Report-AgBlock $e 'A'
      Should -Invoke Restart-Antigravity -Times 1 -Exactly
    }
  }

  Context 'главный цикл: без «❌ ОШИБКА» каждые 60 сек' {
    BeforeEach {
      $Cfg.QuotaEveryMin=0; $Cfg.AgQueueCheckSec=0; $Cfg.AcceptAllEverySec=0
      $script:NeedStart=$false; $script:LimitStop=$false; $script:Paused=$false; $script:Queue.Clear(); $script:Busy=$false
      Mock Pump {}; Mock Nap {}; Mock Check-Blocking {}; Mock Quota-Blocked { $null }; Mock Write-Host {}; Mock Notify {}
      Mock Next-File { [pscustomobject]@{ Name='A_003.md' } }
      Mock Process-File { throw [GG.AgBlockedException]::new('hung','Antigravity не отвечает: IsHungAppWindow=true','IsHungAppWindow=true') }
      Remove-Item $Cfg.StopFile -EA 0
    }
    It '5 шагов в зависании — 1 сообщение, Notify «❌ ОШИБКА» не вызывается, состояние «жду Antigravity»' {
      1..5 | ForEach-Object { Invoke-MainStep | Should -Be 'ok' }
      Should -Invoke Tg-Send -Times 1 -Exactly
      Should -Invoke Notify -Times 0
      $script:State | Should -BeLike '⏸ жду Antigravity (hung)*'
      Should -Invoke Nap -Times 5 -Exactly -ParameterFilter { $Sec -eq $Cfg.AgBlockRetrySec -or $args[0] -eq $Cfg.AgBlockRetrySec }
    }
    It 'Accept all и очередь Antigravity не проверяются, пока окно зависло' {
      $Cfg.AgQueueCheckSec=1; $Cfg.AcceptAllEverySec=1; $script:LastQueueCheck=(Get-Date).AddHours(-1); $script:LastAccept=(Get-Date).AddHours(-1)
      Mock Process-File {}; Mock Check-AgQueue {}; Mock Try-AcceptAll {}
      $script:AgBlock=@{ kind='hung'; since=(Get-Date); notifiedAt=(Get-Date) }
      Invoke-MainStep | Out-Null
      Should -Invoke Check-AgQueue -Times 0; Should -Invoke Try-AcceptAll -Times 0
    }
    It 'вложенное AgBlockedException распознаётся как agblock' {
      try{ & { throw [GG.AgBlockedException]::new('hung','x','y') } }catch{ $o=New-Object System.Exception('обёртка',$_.Exception) }
      Get-ErrorKind $o | Should -Be 'agblock'
    }
  }

  Context 'доставка ровно один раз, перезапуск Antigravity' {
    BeforeEach {
      $script:St=New-RelayState; $script:QStopG=$false; $script:QStopA=$false; $script:StaleNotified=@{}; $script:LastModel='Argon Ultra'
      $script:answer="## Задача`nсделай X"; $script:agSent=@()
      Mock Save-State {}; Mock Wait-FileStable {}
      Mock Gem-GetModel { 'Argon Ultra' }; Mock Gem-SendFile { @{ before=1; pBefore=1; via='uia' } }; Mock Gem-WaitAnswer { 1 }
      Mock Gem-CountPrompts { 2 }; Mock Gem-LastReportPrompt { $null }; Mock Gem-CopyCode { $script:answer }
      Mock Ag-HasText { $false }
      Get-ChildItem $Cfg.Downloads | Remove-Item -Force
      Remove-Item $Cfg.AnswerDir -Recurse -Force -EA 0
    }
    It 'зависание при передаче → ответ сохранён; после перезапуска (новый pid/hwnd) передан ровно один раз без повторного копирования из Gemini' {
      $f=New-Report 'A_2026-10-18_003.md'
      $script:Hung=$true
      { Process-File $f } | Should -Throw -ExceptionType ([GG.AgBlockedException])
      Get-Stage $f.Name | Should -Be 'answered'
      Test-Path (Get-AnswerCachePath $f.Name) | Should -BeTrue
      Report-AgBlock ([GG.AgBlockedException]::new('hung','x','y')) $f.Name
      # повторы, пока висит: Gemini не трогается, Antigravity не фокусируется
      { Process-File $f } | Should -Throw -ExceptionType ([GG.AgBlockedException])
      Should -Invoke Gem-CopyCode -Times 1 -Exactly; $script:Focus | Should -Be 0
      # пользователь перезапустил Antigravity: новое окно и pid
      $script:Hung=$false; $script:FakePid=5555; $script:Hwnd=777
      Process-File $f
      Should -Invoke AgUia-FindInput -Times 1 -Exactly -ParameterFilter { $h -eq 777 }
      $script:Enter | Should -Be 1; $script:Pastes | Should -Be 1
      Should -Invoke Gem-CopyCode -Times 1 -Exactly
      Get-Stage $f.Name | Should -Be 'relayed'; Is-Done $f.Name | Should -BeTrue
      Test-Path (Get-AnswerCachePath $f.Name) | Should -BeFalse
      Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '✅ Antigravity снова отвечает, ответ передан.*' }
      $script:AgBlock | Should -BeNullOrEmpty
      # ещё один проход — повторной отправки нет
      (Next-File) | Should -BeNullOrEmpty
    }
    It 'Enter прошёл, но проверка упала — повторно не вставляет (ответ уже в Antigravity)' {
      $f=New-Report 'A_2026-10-18_008.md'
      $script:SendWorks=$false   # текст «остался» → unknown
      { Process-File $f } | Should -Throw -ExceptionType ([GG.AgBlockedException])
      $script:Enter | Should -Be 1
      Mock Ag-HasText { $true }
      Process-File $f
      $script:Enter | Should -Be 1; Get-Stage $f.Name | Should -Be 'relayed'
    }
    It 'кэш с чужим хэшем не используется — ответ берётся из Gemini с проверкой хэша' {
      $f=New-Report 'A_2026-10-18_009.md'
      [void](Set-FileStage $script:St $f.Name 'sent'); [void](Set-FileStage $script:St $f.Name 'answered' -Hash (Get-Hash8 $script:answer))
      Save-AnswerCache $f.Name 'подменённый текст'
      Process-File $f
      Should -Invoke Gem-CopyCode -Times 1 -Exactly
      $script:Clip | Should -Be $script:answer
    }
    It 'нет окна (Antigravity перезапускается) — nowindow, Gemini не трогается' {
      $f=New-Report 'A_2026-10-18_010.md'
      [void](Set-FileStage $script:St $f.Name 'sent'); [void](Set-FileStage $script:St $f.Name 'answered' -Hash (Get-Hash8 $script:answer))
      $script:NoWin=$true
      try{ Process-File $f; throw 'не бросило' }catch{ $_.Exception.Kind | Should -Be 'nowindow' }
      Should -Invoke Gem-CopyCode -Times 0; Should -Invoke Gem-GetModel -Times 0
    }
  }

  Context '-testag: только чтение' {
    It 'Get-AgDiag не ставит фокус, не кликает, не вставляет' {
      $d=Get-AgDiag
      $d.verdict | Should -BeLike 'поле пустое*'
      $script:Focus | Should -Be 0; Should -Invoke Uia-ClickEl -Times 0; Should -Invoke Uia-Focus -Times 0; $script:Pastes | Should -Be 0
    }
    It 'Get-AgDiag: чужой текст и зависание распознаются' {
      $script:Field='abc'; (Get-AgDiag).verdict | Should -Be "чужой текст: 'abc'"
      $script:Hung=$true; (Get-AgDiag).verdict | Should -BeLike 'зависло*'
    }
  }
}
