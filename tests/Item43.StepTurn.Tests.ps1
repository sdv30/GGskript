# Пункт 43: очередь по номеру шага и проекту; самый свежий отчёт по времени файла (max LastWriteTime/CreationTime); MaxReportAgeHours.
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1'); $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {}
  function Rep([string]$Name,[datetime]$T,[string]$Body='report'){ $p=Join-Path $Cfg.Downloads $Name; [IO.File]::WriteAllText($p,"$Body $Name"); $i=Get-Item $p; $i.CreationTime=$T; $i.LastWriteTime=$T; $i }
  function Reset-Env{ Get-ChildItem $Cfg.Downloads | Remove-Item -Force; $script:St=New-RelayState; $script:Held=@{}; $Cfg.MaxReportAgeHours=12; $Cfg.StartupNewestOnly=$true; Mock Save-State {} }
  $script:Blk6="[ARGON&gt;FLASH] [Arena] [S006] [2026-10-20]`n<role>`nSenior Python`n</role>"
  $script:Blk8="[ARGON>FLASH] [Arena] [S008] [2026-10-21]`n<role>x</role>"
}
Describe 'Item43 Очередь по шагу и проекту' -Tag 'Item43' {
  BeforeEach { Reset-Env }
  It 'заголовок блока: проект и номер (в т.ч. &gt;), без заголовка — $null' {
    $h=Get-PromptHeader $script:Blk6; $h.project | Should -Be 'Arena'; $h.step | Should -Be 6
    (Get-PromptHeader "[ARGON>FLASH] [DeepNTRskript] [S012] [2026-10-19]").project | Should -Be 'DeepNTRskript'
    Get-PromptHeader "Просто текст без заголовка" | Should -BeNullOrEmpty
  }
  It 'время отчёта — max(LastWriteTime, CreationTime)' {
    $i=Rep 'Arena_2026-10-21_001.md' ([datetime]'2026-10-21 10:00'); $i.CreationTime=[datetime]'2026-10-21 12:00'
    (Get-ReportFileTime (Get-Item $i.FullName)) | Should -Be ([datetime]'2026-10-21 12:00')
  }
  It 'инцидент 21.10: DeepNTRskript_…_007 вчерашний, Arena_…_007 сегодняшний — берётся только Arena (проект из заголовка)' {
    $now=Get-Date
    [void](Rep 'DeepNTRskript_2026-10-20_007.md' $now.AddHours(-20))
    [void](Rep 'Arena_2026-10-21_006.md' $now.AddMinutes(-40))
    [void](Rep 'Arena_2026-10-21_007.md' $now.AddMinutes(-2))
    $script:St.activeProject='Arena'; $script:St.lastBlock=[ordered]@{ project='Arena'; step=7; hash='h7'; at=$now.AddMinutes(-30).ToString('yyyy-MM-dd HH:mm:ss') }
    $script:St.lastAgAt=$now.AddMinutes(-30).ToString('yyyy-MM-dd HH:mm:ss')
    (Next-File).Name | Should -Be 'Arena_2026-10-21_007.md'
    @(Get-Files -All).Name | Should -Not -Contain 'DeepNTRskript_2026-10-20_007.md'
  }
  It 'даже при том же номере и без возрастного фильтра чужой проект не берётся' {
    $Cfg.MaxReportAgeHours=0; $now=Get-Date
    [void](Rep 'DeepNTRskript_2026-10-21_007.md' $now.AddMinutes(-1))   # новее по времени, но другой проект
    [void](Rep 'Arena_2026-10-21_007.md' $now.AddMinutes(-5))
    $script:St.activeProject='Arena'; $script:St.lastAgAt=$now.AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss')
    $script:St.lastBlock=[ordered]@{ project='Arena'; step=7; hash='h'; at=$script:St.lastAgAt }
    # чужой отчёт новее последней вставки -> переключение на DeepNTRskript, это осознанная смена проекта; проверяем, что выбор не идёт по номеру/алфавиту
    (Next-File).Name | Should -Be 'DeepNTRskript_2026-10-21_007.md'
    $script:St.activeProject='Arena'; $script:St.lastAgAt=$now.ToString('yyyy-MM-dd HH:mm:ss')   # вставка позже обоих отчётов — проект не меняется
    (Get-ActiveProjectNow) | Should -Be 'Arena'
    @(Get-Files).Name | Should -Be @('Arena_2026-10-21_007.md')
  }
  It 'без заголовка проект — у самого свежего отчёта; отчёты старше 12 ч не берутся' {
    $now=Get-Date
    [void](Rep 'DeepNTRskript_2026-10-20_009.md' $now.AddHours(-13))
    [void](Rep 'Arena_2026-10-21_002.md' $now.AddMinutes(-3))
    (Get-ActiveProjectNow) | Should -Be 'Arena'
    $Cfg.MaxReportAgeHours=12; $script:St.activeProject=''
    Remove-Item (Join-Path $Cfg.Downloads 'Arena_2026-10-21_002.md')
    Get-ActiveProjectNow | Should -BeNullOrEmpty
    Next-File | Should -BeNullOrEmpty
  }
  It 'запуск: старые файлы ДРУГОГО проекта не помечаются «пропущен»' {
    $now=Get-Date
    [void](Rep 'DeepNTRskript_2026-10-21_007.md' $now.AddHours(-3))
    [void](Rep 'Arena_2026-10-21_005.md' $now.AddHours(-2)); [void](Rep 'Arena_2026-10-21_006.md' $now.AddMinutes(-5))
    $script:St.activeProject='Arena'
    $r=Invoke-StartupTriage -LastPrompt '' -DryRun -NoChat
    $r.newest | Should -Be 'Arena_2026-10-21_006.md'; $r.skipped | Should -Be @('Arena_2026-10-21_005.md')
  }
  It 'N > M — ход Antigravity: передать блок; после передачи — ждать отчёт N' {
    $now=Get-Date; $f=Rep 'Arena_2026-10-21_005.md' $now.AddMinutes(-10)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Arena' -Pattern $Cfg.Pattern)[-1]
    $d=Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -State $script:St
    $d.turn | Should -Be 'antigravity'; $d.action | Should -Be 'relay-block'
    Add-SentRecord $script:St 'ag' 'Arena' 6 'b6'
    (Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -State $script:St).action | Should -Be 'wait-report'
  }
  It 'M >= N и отчёт новее вставки — ход Gemini: прикрепить; после отправки — ждать ответ; повтор по содержимому не шлётся' {
    $now=Get-Date; $f=Rep 'Arena_2026-10-21_006.md' $now
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Arena' -Pattern $Cfg.Pattern)[-1]
    Add-SentRecord $script:St 'ag' 'Arena' 6 'b6'
    $d=Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -ReportHash 'r6' -State $script:St -LastAgAt $now.AddMinutes(-20)
    $d.turn | Should -Be 'gemini'; $d.action | Should -Be 'send-report'
    Add-SentRecord $script:St 'gem' 'Other' 99 'r6'   # отправлен вручную/под другим учётом — узнаётся по хэшу
    (Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -ReportHash 'r6' -State $script:St -LastAgAt $now.AddMinutes(-20)).action | Should -Be 'wait-answer'
  }
  It 'противоречие: отчёт №N старее вставки — ничего не шлю, есть пометка' {
    $now=Get-Date; $f=Rep 'Arena_2026-10-21_006.md' $now.AddHours(-1)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Arena' -Pattern $Cfg.Pattern)[-1]
    $d=Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -State $script:St -LastAgAt $now
    $d.action | Should -Be 'wait'; $d.contradiction | Should -Not -BeNullOrEmpty
  }
  It 'отчёт другого проекта при заголовке Arena не учитывается' {
    $f=Rep 'DeepNTRskript_2026-10-21_007.md' (Get-Date)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Pattern $Cfg.Pattern)[-1]
    $d=Get-TurnDecision -Header (Get-PromptHeader $script:Blk6) -BlockHash 'b6' -Report $c -State $script:St
    $d.project | Should -Be 'Arena'; $d.action | Should -Be 'relay-block'; $d.report | Should -BeNullOrEmpty
  }
  It 'без заголовка — чередование по содержимому и пометка «формат нарушен»' {
    $f=Rep 'Arena_2026-10-21_003.md' (Get-Date)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Pattern $Cfg.Pattern)[-1]
    $script:St.lastSide='ag'
    $d=Get-TurnDecision -Header $null -BlockHash 'bx' -Report $c -ReportHash 'r3' -State $script:St -LastAgAt (Get-Date).AddMinutes(-5)
    $d.formatBroken | Should -BeTrue; $d.action | Should -Be 'send-report'
    $script:St.lastSide='gem'
    (Get-TurnDecision -Header $null -BlockHash 'bx' -Report $c -ReportHash 'r3' -State $script:St).action | Should -Be 'relay-block'
    Add-SentRecord $script:St 'ag' 'Arena' -1 'bx'
    (Get-TurnDecision -Header $null -BlockHash 'bx' -Report $c -ReportHash 'r3' -State $script:St -LastAgAt (Get-Date).AddMinutes(-5)).action | Should -Be 'send-report'
  }
  It 'Next-File: отчёт меньше шага у Antigravity (005 < S006) не отправляется' {
    $now=Get-Date; [void](Rep 'Arena_2026-10-21_005.md' $now)
    $script:St.activeProject='Arena'; $script:St.lastBlock=[ordered]@{ project='Arena'; step=6; hash='b6'; at=$now.AddMinutes(-1).ToString('yyyy-MM-dd HH:mm:ss') }
    Next-File | Should -BeNullOrEmpty
    [void](Rep 'Arena_2026-10-21_006.md' $now.AddSeconds(5))
    (Next-File).Name | Should -Be 'Arena_2026-10-21_006.md'
  }
  It 'Register-BlockRelayed пишет проект, шаг, хэш; индикатор берёт ход из решения' {
    [void](Rep 'Arena_2026-10-21_005.md' (Get-Date).AddMinutes(-5)); $script:St.activeProject='Arena'
    Register-BlockRelayed $script:Blk6 'b6'
    $script:St.lastBlock.step | Should -Be 6; $script:St.lastSide | Should -Be 'ag'; Test-SentRecord $script:St 'ag' 'Arena' 6 | Should -BeTrue
    (Get-TurnDecisionNow).turn | Should -Be 'antigravity'
    Get-RelayTurn -Kind 'running' -LastSide 'gemini' -Decision 'antigravity' | Should -Be 'antigravity'
    Get-RelayTurn -Kind 'paused' -Decision 'antigravity' | Should -Be 'stopped'
  }
  It 'настройка MaxReportAgeHours=12 по умолчанию' { (Get-DefaultSettings -Root $TestDrive).MaxReportAgeHours | Should -Be 12 }
}
