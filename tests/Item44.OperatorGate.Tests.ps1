# Пункт 44: «СТОП — РЕШЕНИЕ ОПЕРАТОРА», «Ответ на: <отчёт>.md», проверка меток шага [S<N>] / [[END S<N>]] перед вставкой в Antigravity.
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1'); $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {}
  function Rep([string]$Name,[datetime]$T){ $p=Join-Path $Cfg.Downloads $Name; [IO.File]::WriteAllText($p,"report $Name"); $i=Get-Item $p; $i.CreationTime=$T; $i.LastWriteTime=$T; $i }
  function Reset-Env{ Get-ChildItem $Cfg.Downloads | Remove-Item -Force; $script:St=New-RelayState; $script:Held=@{}; $script:StaleNotified=@{}; $script:GateSaid=''; $script:GateHold=''; $script:OperatorWait=''; Mock Save-State {} }
  function Blk([string]$S,[string]$End='',[switch]$Rework,[string]$Proj='Arena'){ if(-not $End){ $End=$S }; "[ARGON&gt;FLASH] [$Proj] [S$S] [2026-10-21]$(if($Rework){" [REWORK S$S]"})`n<role>x</role>`n<task>y</task>`n[[END S$End]]" }
}
Describe 'Item44 Оператор и метки шага' -Tag 'Item44' {
  BeforeEach { Reset-Env }
  It 'СТОП — РЕШЕНИЕ ОПЕРАТОРА: первой строкой или после «Ответ на: …md»' {
    Test-OperatorStop "СТОП — РЕШЕНИЕ ОПЕРАТОРА`nНужно выбрать вариант" | Should -BeTrue
    Test-OperatorStop "Ответ на: Arena_2026-10-21_007.md`n`n**СТОП - РЕШЕНИЕ ОПЕРАТОРА**`nтекст" | Should -BeTrue
    Test-OperatorStop "Ответ на: Arena_2026-10-21_007.md`nОбычное объяснение. СТОП — РЕШЕНИЕ ОПЕРАТОРА" | Should -BeFalse
    Test-OperatorStop "Просто ответ без блока" | Should -BeFalse
  }
  It '«Ответ на: <имя>.md» — только первая непустая строка' {
    Get-AnswerReportRef "`nОтвет на: Arena_2026-10-21_007.md`n~~~markdown" | Should -Be 'Arena_2026-10-21_007.md'
    Get-AnswerReportRef "**Ответ на:** Arena_2026-10-21_007.md" | Should -Be 'Arena_2026-10-21_007.md'
    Get-AnswerReportRef "Текст`nОтвет на: Arena_2026-10-21_007.md" | Should -BeNullOrEmpty
  }
  It 'метки: S = последний отчёт + 1 и начало = конец — ок' {
    $g=Test-BlockStepTags (Blk '008') 7; $g.tagged | Should -BeTrue; $g.ok | Should -BeTrue; $g.expect | Should -Be 8
  }
  It 'метки: неверный номер, разные начало/конец, нет конца — не ок' {
    (Test-BlockStepTags (Blk '009') 7).ok | Should -BeFalse
    $g=Test-BlockStepTags (Blk '008' '007') 7; $g.ok | Should -BeFalse; $g.reason | Should -Match 'END S007'
    (Test-BlockStepTags ("[ARGON>FLASH] [Arena] [S008] [2026-10-21]`n<role>x</role>") 7).reason | Should -Match 'нет метки конца'
  }
  It '[S<N>] [REWORK S<K>] (реальный формат): N = отчёт + 1, K = последний отчёт' {
    $b="[ARGON>FLASH] [Arena] [S008] [REWORK S007] [2026-10-21]`n<task>x</task>`n[[END S008]]"
    (Test-BlockStepTags $b 7).ok | Should -BeTrue
    (Get-PromptHeader $b).reworkOf | Should -Be 7; (Get-PromptHeader $b).step | Should -Be 8; (Get-PromptHeader $b).rework | Should -BeFalse
    $g=Test-BlockStepTags ($b -replace 'REWORK S007','REWORK S005') 7; $g.ok | Should -BeFalse; $g.reason | Should -Match 'REWORK S005'
  }
  It '[REWORK S<N>] вместо шага: N = последний отчёт' {
    $b="[ARGON>FLASH] [Arena] [REWORK S007] [2026-10-21]`n<task>x</task>`n[[END S007]]"
    (Get-PromptHeader $b).rework | Should -BeTrue
    (Test-BlockStepTags $b 7).ok | Should -BeTrue
    (Test-BlockStepTags $b 6).ok | Should -BeFalse
  }
  It 'без меток [ARGON>FLASH] — прежнее поведение' {
    $g=Test-BlockStepTags "Просто блок`nтекст" 7; $g.tagged | Should -BeFalse; $g.ok | Should -BeTrue
  }
  It 'REWORK в очереди: блок передать, потом ждать новый отчёт №N' {
    $now=Get-Date; $f=Rep 'Arena_2026-10-21_007.md' $now.AddMinutes(-30)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Arena' -Pattern $Cfg.Pattern)[-1]
    Add-SentRecord $script:St 'ag' 'Arena' 7 'b7'; Add-SentRecord $script:St 'gem' 'Arena' 7 'r7'
    $h=Get-PromptHeader "[ARGON>FLASH] [Arena] [REWORK S007] [2026-10-21]`nx`n[[END S007]]"
    $d=Get-TurnDecision -Header $h -BlockHash 'rw7' -Report $c -ReportHash 'r7' -State $script:St -LastAgAt $now.AddMinutes(-20)
    $d.action | Should -Be 'relay-block'
    Add-SentRecord $script:St 'ag' 'Arena' 7 'rw7'
    $d=Get-TurnDecision -Header $h -BlockHash 'rw7' -Report $c -ReportHash 'r7' -State $script:St -LastAgAt $now.AddMinutes(-20)
    $d.turn | Should -Be 'antigravity'; $d.action | Should -Be 'wait-report'
    $c.Time=$now
    (Get-TurnDecision -Header $h -BlockHash 'rw7' -Report $c -ReportHash 'r7new' -State $script:St -LastAgAt $now.AddMinutes(-20)).action | Should -Be 'send-report'
  }
  It 'Relay-ToAg: несовпадение меток — НЕ вставляет, этап «ждёт решения», одна заметка с кнопками' {
    [void](Rep 'Arena_2026-10-21_007.md' (Get-Date)); $script:St.activeProject='Arena'
    Mock Ag-Send { throw 'не должен вставлять' }; Mock New-TgPrompt { @{ id='x' } }
    [void](Set-FileStage -State $script:St -Name 'Arena_2026-10-21_007.md' -Stage 'answered' -Force)
    Relay-ToAg 'Arena_2026-10-21_007.md' (Blk '009') 'h9' 'Argon'
    Get-FileStage $script:St 'Arena_2026-10-21_007.md' | Should -Be 'stale'
    Relay-ToAg 'Arena_2026-10-21_007.md' (Blk '009') 'h9' 'Argon'
    Should -Invoke New-TgPrompt -Times 1 -Exactly -ParameterFilter { $Kind -eq 'gate' -and $Buttons -match 'Передай всё равно' -and $Buttons -match 'Отправь заново' }
    Should -Invoke Ag-Send -Times 0
  }
  It 'Relay-ToAg: верные метки — вставляет; -NoGate («передай всё равно») — вставляет всегда' {
    [void](Rep 'Arena_2026-10-21_007.md' (Get-Date)); $script:St.activeProject='Arena'
    Mock Ag-Send {}; Mock Play-Sound {}; Mock Remove-AnswerCache {}
    Relay-ToAg 'Arena_2026-10-21_007.md' (Blk '008') 'h8' 'Argon'
    Get-FileStage $script:St 'Arena_2026-10-21_007.md' | Should -Be 'relayed'
    Relay-ToAg 'Arena_2026-10-21_007.md' (Blk '009') 'h9' 'Argon' -NoGate
    Should -Invoke Ag-Send -Times 2 -Exactly
  }
  It 'Enter-OperatorWait: этап operator (не nocode), текст и кнопки «Напиши»/«Отправь заново», индикатор «Ждём оператора»' {
    Mock Save-FullAnswer { 'x' }; Mock Play-Sound {}; Mock New-TgPrompt { @{ id='o' } }; Mock Tg-SendDocument {}
    [void](Set-FileStage -State $script:St -Name 'Arena_2026-10-21_007.md' -Stage 'sent' -Force)
    Enter-OperatorWait 'Arena_2026-10-21_007.md' "Ответ на: Arena_2026-10-21_007.md`nСТОП — РЕШЕНИЕ ОПЕРАТОРА`nвыбор" 'Argon'
    Get-FileStage $script:St 'Arena_2026-10-21_007.md' | Should -Be 'operator'
    Test-FileDone $script:St 'Arena_2026-10-21_007.md' | Should -BeTrue
    Should -Invoke New-TgPrompt -Times 1 -ParameterFilter { $Kind -eq 'operator' -and $Buttons -match 'Напиши' -and $Buttons -match 'Отправь заново' }
    Should -Invoke Tg-Send -ParameterFilter { $Text -match 'СТОП' }
    Get-RelayTurn -Kind 'operator' | Should -Be 'operator'
    (Get-TurnView 'operator' $true).Caption | Should -Match 'Ждём оператора'
    Test-StageTransition 'operator' 'resend' | Should -BeTrue
    $script:OperatorWait | Should -Be 'Arena_2026-10-21_007.md'
  }
  It 'длинный текст остановки — файлом' {
    Mock Tg-SendDocument {}; $Cfg.AnswerDir=(Join-Path $TestDrive 'answers')
    Send-OperatorAnswer (((1..30) | ForEach-Object { 'абзац ' + ('x'*1500) }) -join "`n`n") 'Arena_2026-10-21_007.md'
    Should -Invoke Tg-SendDocument -Times 1
  }
  It 'Get-StaleFile находит и «ждёт оператора», «отправь заново» переводит в resend' {
    [void](Rep 'Arena_2026-10-21_007.md' (Get-Date)); $script:St.activeProject='Arena'
    [void](Set-FileStage -State $script:St -Name 'Arena_2026-10-21_007.md' -Stage 'operator' -Force)
    (Get-StaleFile).Name | Should -Be 'Arena_2026-10-21_007.md'
    Run-ActionCore @{ k='resendstale' }
    Get-FileStage $script:St 'Arena_2026-10-21_007.md' | Should -Be 'resend'
  }
}
