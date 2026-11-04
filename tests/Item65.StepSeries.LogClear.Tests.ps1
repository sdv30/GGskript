BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Gui=Get-Content -Raw -Encoding UTF8 (Join-Path $script:V2Root 'GGskript_gui.ps1')
  $script:Rel=Get-Content -Raw -Encoding UTF8 (Join-Path $script:V2Root 'lib/Relay.ps1')
  $script:Wrk=Get-Content -Raw -Encoding UTF8 (Join-Path $script:V2Root 'GGskript.ps1')
  function New-OldSeries{
    $s=New-RelayState
    foreach($i in 1..9){ Add-SentRecord $s 'ag' 'AccessLab' $i ("a{0:D7}" -f $i); if($i -lt 9){ Add-SentRecord $s 'gem' 'AccessLab' $i ("g{0:D7}" -f $i) } }
    $s.lastBlock=[ordered]@{ project='AccessLab'; step=9; hash='a0000009'; at='2026-10-29 16:14:14'; rework=$false }
    $s.lastAgAt='2026-10-29 16:14:14'; $s
  }
}
Describe '02.11 stepseries: новая серия шагов без привязки к дате' -Tag Item65 {
  It 'смена дня: блок S1 с новым содержимым после S9 — новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -Step 1 -BlockHash 'ffff0001' | Should -Not -BeNullOrEmpty
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -Step 2 -BlockHash 'ffff0002' | Should -Not -BeNullOrEmpty
  }
  It 'тот же блок (хэш уже передавался) — не новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -Step 3 -BlockHash 'a0000003' | Should -BeNullOrEmpty
  }
  It 'тот же шаг или следующий — не новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -Step 9 -BlockHash 'ffff0009' | Should -BeNullOrEmpty
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -Step 10 -BlockHash 'ffff0010' | Should -BeNullOrEmpty
  }
  It 'другой проект — не трогаю' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'Eskalator' -Step 1 -BlockHash 'ffff0001' | Should -BeNullOrEmpty
  }
  It 'устаревший учёт: отчёт №1 записан позже передачи S9 — новая серия (любая дата в имени)' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -ReportNum 1 -ReportTime ([datetime]'2026-11-02 21:08:29') | Should -Not -BeNullOrEmpty
  }
  It 'старый отчёт №5 (раньше передачи S9) и перезаписанный №5 (позже) — не новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -ReportNum 5 -ReportTime ([datetime]'2026-11-02 21:08:29') | Should -BeNullOrEmpty
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -ReportNum 5 -ReportTime ([datetime]'2026-10-29 11:14:12') | Should -BeNullOrEmpty
  }
  It 'Reset-StepSeries: старые S1..S9 не совпадают ни по номеру, ни по хэшу; чужой проект цел' {
    $s=New-OldSeries; Add-SentRecord $s 'ag' 'Eskalator' 1 'e0000001'
    Reset-StepSeries $s 'AccessLab' | Should -Be 17
    Test-SentRecord $s 'ag' 'AccessLab' 1 | Should -BeFalse
    Test-SentRecord $s 'gem' 'AccessLab' 1 | Should -BeFalse
    Test-SentRecord $s 'ag' '' -1 'a0000002' | Should -BeFalse
    Test-SentRecord $s 'ag' 'Eskalator' 1 | Should -BeTrue
    $s.lastBlock | Should -BeNullOrEmpty
  }
  It 'после сброса: S1 нового дня — передать блок, а не «противоречие»' {
    $s=New-OldSeries
    $h=@{ project='AccessLab'; step=1; rework=$false }
    (Get-TurnDecision -Header $h -BlockHash 'ffff0001' -Report $null -State $s).contradiction | Should -Not -BeNullOrEmpty   # прежнее поведение (баг 02.11 20:44)
    [void](Reset-StepSeries $s 'AccessLab')
    $d=Get-TurnDecision -Header $h -BlockHash 'ffff0001' -Report $null -State $s
    $d.action | Should -Be 'relay-block'; $d.contradiction | Should -BeNullOrEmpty
  }
  It 'после сброса: отчёт №1 нового дня — отправить в Gemini, а не «уже в Gemini»' {
    $s=New-OldSeries; Add-SentRecord $s 'gem' 'AccessLab' 1 'g0000001'
    $rep=[pscustomobject]@{ Name='AccessLab_2026-11-02_001.md'; FullName='x'; Time=[datetime]'2026-11-02 21:08:29'; Num=1; Project='AccessLab' }
    $h=@{ project='AccessLab'; step=1; rework=$false }
    $last=[datetime]'2026-11-02 20:45:00'
    (Get-TurnDecision -Header $h -BlockHash '' -Report $rep -ReportHash 'nnnn0001' -State $s -LastAgAt $last).action | Should -Be 'wait-answer'   # баг: «отчёт №1 уже в Gemini»
    [void](Reset-StepSeries $s 'AccessLab')
    (Get-TurnDecision -Header $h -BlockHash '' -Report $rep -ReportHash 'nnnn0001' -State $s -LastAgAt $last).action | Should -Be 'send-report'
  }
  It 'Relay: проверка серии вызывается до решения хода и до шлюза «меньше шага»' {
    $script:Rel | Should -Match 'function Invoke-StepSeriesCheck'
    $script:Rel | Should -Match 'Invoke-StepSeriesCheck \$hdr \$bh \$rep'
    $i1=$script:Rel.IndexOf('Invoke-StepSeriesCheck $null'); $i2=$script:Rel.IndexOf('меньше шага S'); $i1 | Should -BeGreaterThan 0; $i1 | Should -BeLessThan $i2
  }
}
Describe '02.11 logclear: чистый журнал при запуске и ссылка «очистить журнал»' -Tag Item65 {
  It 'Invoke-LogArchive переносит журнал в logs\ и оставляет последних N' {
    $d=Join-Path $TestDrive 'lc'; New-Item -ItemType Directory $d | Out-Null; $p=Join-Path $d 'relay_log.txt'; $ld=Join-Path $d 'logs'
    foreach($i in 1..12){ [IO.File]::WriteAllText($p,"line $i`n"); $r=Invoke-LogArchive -Path $p -Dir $ld -Keep 10 -Now ([datetime]'2026-11-02 21:00:00').AddMinutes($i); $r | Should -Not -BeNullOrEmpty; Test-Path $p | Should -BeFalse; (Get-Item $r).LastWriteTime=([datetime]'2026-11-02 21:00:00').AddMinutes($i) }
    @(Get-ChildItem $ld -Filter 'relay_log_*.txt').Count | Should -Be 10
    Test-Path (Join-Path $ld 'relay_log_20261102_210100.txt') | Should -BeFalse
    Test-Path (Join-Path $ld 'relay_log_20261102_211200.txt') | Should -BeTrue
  }
  It 'пустой или отсутствующий журнал — ничего не делаю' {
    $d=Join-Path $TestDrive 'lc2'; New-Item -ItemType Directory $d | Out-Null; $p=Join-Path $d 'relay_log.txt'
    Invoke-LogArchive -Path $p -Dir (Join-Path $d 'logs') | Should -BeNullOrEmpty
    [IO.File]::WriteAllText($p,''); Invoke-LogArchive -Path $p -Dir (Join-Path $d 'logs') | Should -BeNullOrEmpty
  }
  It 'одинаковое время — второе имя с суффиксом, не затирает' {
    $d=Join-Path $TestDrive 'lc3'; New-Item -ItemType Directory $d | Out-Null; $p=Join-Path $d 'relay_log.txt'; $now=[datetime]'2026-11-02 21:30:00'
    [IO.File]::WriteAllText($p,'a'); $a=Invoke-LogArchive -Path $p -Dir (Join-Path $d 'logs') -Now $now
    [IO.File]::WriteAllText($p,'b'); $b=Invoke-LogArchive -Path $p -Dir (Join-Path $d 'logs') -Now $now -Suffix ''
    $a | Should -Not -Be $b; (Get-Content $a -Raw) | Should -Be 'a'; (Get-Content $b -Raw) | Should -Be 'b'
  }
  It 'после переноса Log пишет в новый файл (как воркер)' {
    $d=Join-Path $TestDrive 'lc4'; New-Item -ItemType Directory $d | Out-Null; $p=Join-Path $d 'relay_log.txt'
    [IO.File]::AppendAllText($p,"old`n"); [void](Invoke-LogArchive -Path $p -Dir (Join-Path $d 'logs'))
    [IO.File]::AppendAllText($p,"new`n"); (Get-Content $p) | Should -Be 'new'
  }
  It 'воркер архивирует журнал при запуске; панель — ссылка, очистка и чистое окно' {
    $script:Wrk | Should -Match 'Invoke-LogArchive -Path \$Cfg\.LogFile'
    $script:Gui | Should -Match 'LinkLabel'
    $script:Gui | Should -Match "очистить журнал"
    $script:Gui | Should -Match 'function Clear-PanelLog'
    $script:Gui | Should -Match '_cleared'
    $script:Gui | Should -Match 'lnkClear\.Add_LinkClicked'
  }
}
Describe '02.11 stepseries2: живое состояние 22:18 (только №002 новее, S9 от 29.10)' -Tag Item65 {
  It 'отчёт AccessLab_2026-11-02_002.md (21:29:51) после S9 от 29.10 16:14 — новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -ReportNum 2 -ReportTime ([datetime]'2026-11-02 21:29:51') -ReportName 'AccessLab_2026-11-02_002.md' | Should -Not -BeNullOrEmpty
  }
  It 'тот же день в имени, перезапись №5 после S9 — не новая серия' {
    $s=New-OldSeries
    Test-StepSeriesRestart -State $s -Project 'AccessLab' -ReportNum 5 -ReportTime ([datetime]'2026-10-29 17:00:00') -ReportName 'AccessLab_2026-10-29_005.md' | Should -BeNullOrEmpty
  }
  It 'после сброса шлюз «меньше шага» не держит №002 (lastBlock очищен)' {
    $s=New-OldSeries; [void](Reset-StepSeries $s 'AccessLab'); $s.lastBlock | Should -BeNullOrEmpty
    Test-SentRecord $s 'gem' 'AccessLab' 2 | Should -BeFalse
  }
  It 'Next-File передаёт в проверку имя и время файла' {
    $script:Rel | Should -Match 'Name=\[string\]\$nw\.Name; Project=\(ProjOf \$nw\.Name\)'
    $script:Rel | Should -Match '-ReportName \(\[string\]\$Rep\.Name\)'
  }
}
Describe '02.11 stepseries2: остатки прошлой серии после S3 (живое состояние 22:22)' -Tag Item65 {
  It 'S4..S9 от 29.10 после сегодняшнего S3 убираются; S4 сегодня — передать блок' {
    $s=New-OldSeries; Add-SentRecord $s 'ag' 'AccessLab' 3 '4598ec21'
    $s.lastBlock=[ordered]@{ project='AccessLab'; step=3; hash='4598ec21'; at='2026-11-02 22:22:09'; rework=$false }
    $h=@{ project='AccessLab'; step=4; rework=$false }
    (Get-TurnDecision -Header $h -BlockHash 'ffff0004' -State $s).contradiction | Should -Not -BeNullOrEmpty   # без чистки: «S4 уже передавался»
    Clear-StaleStepRecords $s | Should -Be 11
    $d=Get-TurnDecision -Header $h -BlockHash 'ffff0004' -State $s; $d.action | Should -Be 'relay-block'; $d.contradiction | Should -BeNullOrEmpty
    Test-SentRecord $s 'ag' 'AccessLab' 3 | Should -BeTrue
  }
  It 'обычная серия без хвоста — ничего не трогаю' {
    $s=New-OldSeries; Clear-StaleStepRecords $s | Should -Be 0
  }
}