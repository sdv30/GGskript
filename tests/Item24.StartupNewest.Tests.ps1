BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function N([int]$i){ 'MyProject_2026-10-18_{0:D3}.md' -f $i }
  function New-Rep([int]$i,[datetime]$t){ $p=Join-Path $Cfg.Downloads (N $i); [IO.File]::WriteAllText($p,"отчёт $i"); (Get-Item $p).LastWriteTime=$t; $p }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
  function LastPrompt{ @($script:TgPrompts.Values)[-1] }
  function Press($p,[string]$choice){ Handle-Callback "p:$($p.id):$choice" 'cb' $p.msgId }
  function Set-Incident{
    # как в инциденте 18.10: учёт остановился на 002 (10:23), в Downloads 003..007, пользователь вручную дошёл до 007
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $script:St=New-RelayState
    $t0=[datetime]'2026-10-18 09:00'
    foreach($i in 1..7){ [void](New-Rep $i $t0.AddMinutes(30*$i)) }
    foreach($i in 1,2){ [void](Set-FileStage -State $script:St -Name (N $i) -Stage 'relayed' -Force) }
  }
}
Describe 'Пункт 24: запуск без «хвоста» — только самый новый файл' -Tag Item24 {
  BeforeEach { Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { $script:PK }; Mock Get-AgHealth { @{ ok=$true; kind="ok"; reasons=@() } }; Mock Find-QueuedItems { @() }; $script:PK=$null; $script:LastStartReport=""; $script:StopAnnounced=$false;
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100
    $script:TgPrompts.Clear(); $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:Held=@{}; $script:Adopted=@{}; $script:TriageNeeded=$true; $script:PausedSince=$null
    $Cfg.StartupNewestOnly=$true; $Cfg.StartupAskNewest=$true; $Cfg.StartupTriagePauseMin=10; $Cfg.QuotaEveryMin=0; $Cfg.IgnoreBefore=''; $Cfg.TgReplyKeyboard=$true
    $Cfg.StateJson=(Join-Path $TestDrive 'relay_state.json'); $Cfg.PauseFile=(Join-Path $TestDrive 'PAUSE')
    $script:GemSent=New-Object System.Collections.ArrayList; $script:AgSent=New-Object System.Collections.ArrayList
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Gem-IsReady { $true }; Mock Ag-GetWindow { [IntPtr]1 }; Mock AgUia-FindInput { $true }; Mock Get-ModelNow { 'Argon Ultra' }
    Mock Gem-LastReportPrompt { $script:LP }
    Mock Gem-SendFile { [void]$script:GemSent.Add($Name); @{ pBefore=1 } }
    Mock Ag-Send { [void]$script:AgSent.Add($Text) }
    Mock Wait-FileStable {}; Mock Assert-CanSendGemini { 'Argon Ultra' }; Mock Gem-WaitAnswer {}; Mock Check-OurPrompt {}
    Mock Gem-CopyCode { "``````markdown`nответ для агента $(Get-Random)`n``````" }
    Mock Ag-HasText { $false }; Mock Assert-AgReady { $true }
    Set-Incident; $script:LP=$null
  }

  Context 'инцидент: учёт на 002, в папке 003..007' {
    It '007 виден в чате Gemini — 003..006 пропущены, 007 «отправлен», в Gemini ничего не уходит' {
      $script:LP=(N 7)
      Start-Procedure | Out-Null
      foreach($i in 3..6){ Get-Stage (N $i) | Should -Be 'skipped' }
      Get-Stage (N 7) | Should -Be 'sent'
      $script:GemSent.Count | Should -Be 0
      (Sent '*процедура запуска*пропущены*003*004*005*006*').Count | Should -Be 1
      (Sent '*процедура запуска*').Count | Should -Be 1
      (Next-File).Name | Should -Be (N 7)
    }
    It '007 виден, ответ уже вставлен вручную — Process-File не отправляет в Gemini и не вставляет повторно' {
      $script:LP=(N 7); Start-Procedure | Out-Null
      Mock Ag-HasText { $true }
      Process-File (Next-File)
      $script:GemSent.Count | Should -Be 0; $script:AgSent.Count | Should -Be 0
      Get-Stage (N 7) | Should -Be 'relayed'; (Sent '*уже есть в Antigravity (вставлен вручную)*').Count | Should -Be 1
      Next-File | Should -BeNullOrEmpty
    }
    It '007 виден, ответа в Antigravity нет — ответ передаётся один раз, Gemini не трогается' {
      $script:LP=(N 7); Start-Procedure | Out-Null
      Process-File (Next-File)
      $script:GemSent.Count | Should -Be 0; $script:AgSent.Count | Should -Be 1; Get-Stage (N 7) | Should -Be 'relayed'
    }
    It '007 НЕ виден (в чате 004) — вопрос с кнопками, ничего не отправляется, Next-File пуст' {
      $script:LP=(N 4)
      Start-Procedure | Out-Null
      foreach($i in 3..6){ Get-Stage (N $i) | Should -Be 'skipped' }
      Get-Stage (N 7) | Should -Be ''
      $p=LastPrompt; $p.kind | Should -Be 'newest'; $p.data.name | Should -Be (N 7)
      $s=(Sent '*самый новый отчёт*'); $s.Count | Should -Be 1
      ($s[0].b.reply_markup.inline_keyboard | ForEach-Object { $_ } | ForEach-Object { $_.text }) -join '|' | Should -Be "Отправить $(N 7) в Gemini|Не отправлять, ждать новый"
      Next-File | Should -BeNullOrEmpty; $script:GemSent.Count | Should -Be 0
    }
    It '«Отправить» — 007 уходит в Gemini (один раз), старые — нет' {
      $script:LP=(N 4); Start-Procedure | Out-Null; Press (LastPrompt) 'send'
      $f=Next-File; $f.Name | Should -Be (N 7); Process-File $f
      $script:GemSent.Count | Should -Be 1; $script:GemSent[0] | Should -Match ([regex]::Escape((N 7)))
      Next-File | Should -BeNullOrEmpty
    }
    It '«Не отправлять» и «да/нет» текстом; время вышло — 007 skipped, ничего не отправлено' {
      $script:LP=(N 4); Start-Procedure | Out-Null; Press (LastPrompt) 'wait'
      Get-Stage (N 7) | Should -Be 'skipped'; Next-File | Should -BeNullOrEmpty
      Set-Incident; $script:Held=@{}; $script:TriageNeeded=$true; Start-Procedure | Out-Null; Handle-Command 'нет' 'tg'
      Get-Stage (N 7) | Should -Be 'skipped'
      Set-Incident; $script:Held=@{}; $script:TriageNeeded=$true; Start-Procedure | Out-Null; $p=LastPrompt; $p.expires=(Get-Date).AddSeconds(-1); Sweep-TgPrompts
      Get-Stage (N 7) | Should -Be 'skipped'; (Sent '*не отправляю (ответа не было)*').Count | Should -Be 1
      $script:GemSent.Count | Should -Be 0
    }
    It 'новый файл после запуска (008) — обрабатывается как обычно, даже пока 007 ждёт ответа' {
      $script:LP=(N 4); Start-Procedure | Out-Null
      [void](New-Rep 8 ([datetime]'2026-10-18 23:40'))
      $f=Next-File; $f.Name | Should -Be (N 8); Process-File $f
      $script:GemSent.Count | Should -Be 1; $script:GemSent[0] | Should -Match '_008\.md'
    }
    It 'StartupAskNewest=false — 007 отправляется без вопроса, 003..006 нет' {
      $Cfg.StartupAskNewest=$false; $script:LP=(N 4); Start-Procedure | Out-Null
      $script:TgPrompts.Count | Should -Be 0
      $f=Next-File; $f.Name | Should -Be (N 7); Process-File $f
      $script:GemSent.Count | Should -Be 1; $script:GemSent[0] | Should -Match '_007\.md'
    }
    It '007 был «отправлен» в прошлый раз, но в чате его нет, StartupAskNewest=false — повторная отправка (resend)' {
      $Cfg.StartupAskNewest=$false; [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'sent' -Force); $script:LP=(N 4)
      Start-Procedure | Out-Null; Get-Stage (N 7) | Should -Be 'resend'
    }
    It 'старые в работе (sent/answered) тоже пропускаются' {
      [void](Set-FileStage -State $script:St -Name (N 3) -Stage 'sent' -Force); [void](Set-FileStage -State $script:St -Name (N 4) -Stage 'answered' -Force)
      $script:LP=(N 7); Start-Procedure | Out-Null
      Get-Stage (N 3) | Should -Be 'skipped'; Get-Stage (N 4) | Should -Be 'skipped'
    }
    It 'пробный прогон (-DryRun) ничего не меняет' {
      $script:LP=(N 4); Start-Procedure -DryRun | Out-Null
      Get-Stage (N 3) | Should -Be ''; $script:TgPrompts.Count | Should -Be 0; $script:Held.Count | Should -Be 0; (Sent '*').Count | Should -Be 0
    }
    It 'StartupNewestOnly=false — прежнее поведение (первым идёт 003)' {
      $Cfg.StartupNewestOnly=$false; Start-Procedure | Out-Null
      (Next-File).Name | Should -Be (N 3)
    }
    It 'этапы сохраняются в relay_state.json (переживают перезапуск)' {
      $script:LP=(N 7); Start-Procedure | Out-Null
      $r=Read-RelayState $Cfg.StateJson; Get-FileStage $r.State (N 5) | Should -Be 'skipped'
    }
  }

  Context 'самый новый — по времени файла, при равенстве — по номеру' {
    It 'время важнее номера: 005 изменён позже всех — он самый новый, 006 и 007 пропущены' {
      (Get-Item (Join-Path $Cfg.Downloads (N 5))).LastWriteTime=[datetime]'2026-10-18 23:00'
      $script:LP=(N 5); Start-Procedure | Out-Null
      Get-Stage (N 5) | Should -Be 'sent'; Get-Stage (N 6) | Should -Be 'skipped'; Get-Stage (N 7) | Should -Be 'skipped'
    }
    It 'одинаковое время — больший номер' {
      $t=[datetime]'2026-10-18 22:00'; foreach($i in 3..7){ (Get-Item (Join-Path $Cfg.Downloads (N $i))).LastWriteTime=$t }
      (Get-NewestFile (Get-Files)).Name | Should -Be (N 7)
    }
  }

  Context 'в работе: файл старее уже обработанного не отправляется' {
    It 'появился файл с временем раньше переданного — skipped, Gemini не трогается' {
      $script:LP=(N 7); Start-Procedure | Out-Null; Process-File (Next-File)
      [void](New-Rep 9 ([datetime]'2026-10-18 10:00'))   # номер больше, но файл старее 007
      $f=Next-File; $f.Name | Should -Be (N 9); $script:GemSent.Clear(); Process-File $f
      $script:GemSent.Count | Should -Be 0; Get-Stage (N 9) | Should -Be 'skipped'; (Sent '*старее уже обработанного*').Count | Should -Be 1
    }
    It '«отправь заново» (resend) — явная команда, охрана не мешает' {
      [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'relayed' -Force); [void](Set-FileStage -State $script:St -Name (N 3) -Stage 'resend' -Force)
      Process-File ((Get-Files) | Where-Object Name -eq (N 3)); $script:GemSent.Count | Should -Be 1
    }
  }

  Context 'окно Gemini не найдено при запуске + ПАУЗА (как 18.10 23:48)' {
    It 'старые пропускаются сразу, самый новый не берётся и не спрашивается, ничего не отправлено' {
      Mock Gem-IsReady { $false }; $script:Paused=$true; $script:LP=$null
      (Start-Procedure) | Should -BeFalse
      foreach($i in 3..6){ Get-Stage (N $i) | Should -Be 'skipped' }
      Get-Stage (N 7) | Should -Be ''; Next-File | Should -BeNullOrEmpty
      $script:TgPrompts.Count | Should -Be 0; $script:GemSent.Count | Should -Be 0
      $script:TriageNeeded | Should -BeTrue
      $s=(Sent '*процедура запуска*'); $s.Count | Should -Be 1
      $s[0].b.text | Should -Match 'пропущены'; $s[0].b.text | Should -Match 'окно Gemini не найдено — НЕ отправляю'
      $s[0].b.text | Should -Not -Match 'будет отправлен в Gemini'
      $s[0].b.text | Should -Match 'Модель Gemini: не проверена'
    }
    It '«Продолжай» до появления окна — 005-подобные старые не уходят (процедура запуска не пройдена)' {
      Mock Gem-IsReady { $false }; $script:Paused=$true; $script:NeedStart=$true
      Start-Procedure | Out-Null
      Set-Pause $false 'тест'; $script:Paused | Should -BeFalse
      Start-Procedure | Out-Null
      Next-File | Should -BeNullOrEmpty; $script:GemSent.Count | Should -Be 0
      (Sent '*⏭ пропущены*').Count | Should -Be 1 -Because 'список пропущенных — один раз'
    }
    It 'окно появилось, самый новый в чате — «отправлен», разбор закончен' {
      Mock Gem-IsReady { $false }; Start-Procedure | Out-Null
      Mock Gem-IsReady { $true }; $script:LP=(N 7); Start-Procedure | Out-Null
      Get-Stage (N 7) | Should -Be 'sent'; $script:TriageNeeded | Should -BeFalse; (Next-File).Name | Should -Be (N 7)
      $script:GemSent.Count | Should -Be 0
    }
    It 'окно появилось, самого нового в чате нет — один вопрос; повторные попытки не спрашивают снова' {
      Mock Gem-IsReady { $false }; Start-Procedure | Out-Null
      Mock Gem-IsReady { $true }; $script:LP=(N 4); Start-Procedure | Out-Null; Start-Procedure | Out-Null
      @($script:TgPrompts.Values | Where-Object kind -eq 'newest').Count | Should -Be 1
      Next-File | Should -BeNullOrEmpty; $script:GemSent.Count | Should -Be 0
    }
    It 'по умолчанию (StartupTriagePauseMin=0) разбор повторяется после любой паузы' {
      (Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive).StartupTriagePauseMin | Should -Be 0
      $Cfg.StartupTriagePauseMin=0; $script:TriageNeeded=$false
      Set-Pause $true 'тест'; Set-Pause $false 'тест'; $script:TriageNeeded | Should -BeTrue
    }
  }

  Context 'пауза' {
    It 'долгая пауза (≥ 10 мин) — после «старт» снова только самый новый; короткая — нет' {
      $script:TriageNeeded=$false
      Set-Pause $true 'тест'; $script:PausedSince=(Get-Date).AddMinutes(-3); Set-Pause $false 'тест'; $script:TriageNeeded | Should -BeFalse
      Set-Pause $true 'тест'; $script:PausedSince=(Get-Date).AddMinutes(-15); Set-Pause $false 'тест'; $script:TriageNeeded | Should -BeTrue
    }
    It 'повторная процедура запуска без нужды разбора не трогает файлы' {
      $script:TriageNeeded=$false; Start-Procedure | Out-Null; Get-Stage (N 3) | Should -Be ''
    }
  }
}
