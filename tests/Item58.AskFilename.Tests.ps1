BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {}
  function Rep([string]$Name,[datetime]$T){ $p=Join-Path $Cfg.Downloads $Name; [IO.File]::WriteAllText($p,"report $Name"); $i=Get-Item $p; $i.CreationTime=$T; $i.LastWriteTime=$T; $i }
}
Describe 'Пункт 58: ход по имени отчёта в блоке Gemini (без [Sxxx])' -Tag Item58 {
  BeforeEach { Get-ChildItem $Cfg.Downloads -EA 0 | Remove-Item -Force; $script:St=New-RelayState; Mock Save-State {}; $Cfg.MaxReportAgeHours=48 }
  It 'Get-AskedReportFromText: любой префикс *_YYYY-MM-DD_NNN.md, берёт наибольший номер' {
    $a=Get-AskedReportFromText "Пришлите Eskalator_2026-10-23_005.md и затем Eskalator_2026-10-23_006.md" $Cfg.Pattern
    $a.project | Should -Be 'Eskalator'; $a.step | Should -Be 6; $a.from | Should -Be 'filename'
    Get-AskedReportFromText 'нет имени' $Cfg.Pattern | Should -BeNullOrEmpty
  }
  It 'Get-BlockAsk: заголовок [S006] важнее имени файла; без заголовка — имя' {
    $h=Get-BlockAsk "[ARGON>FLASH] [Eskalator] [S006] [2026-10-23]`nнужен Eskalator_2026-10-23_005.md" $Cfg.Pattern
    $h.step | Should -Be 6; $h.from | Should -Be 'header'
    $a=Get-BlockAsk "Нужен отчёт Eskalator_2026-10-23_006.md для следующего шага." $Cfg.Pattern
    $a.project | Should -Be 'Eskalator'; $a.step | Should -Be 6; $a.from | Should -Be 'filename'
  }
  It 'Gemini просит 006, в Downloads есть 005 → ход IDE (передать блок)' {
    $now=Get-Date; $f=Rep 'Eskalator_2026-10-23_005.md' $now.AddMinutes(-10)
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Eskalator' -Pattern $Cfg.Pattern)[-1]
    $code="Ответ на: Eskalator_2026-10-23_005.md`n`nНужен следующий отчёт Eskalator_2026-10-23_006.md.`n`n``````markdown`nx`n``````"
    $hdr=Get-BlockAsk $code $Cfg.Pattern
    $d=Get-TurnDecision -Header $hdr -BlockHash 'b6' -Report $c -State $script:St
    $d.turn | Should -Be 'antigravity'; $d.action | Should -Be 'relay-block'; $d.step | Should -Be 6
  }
  It 'в Downloads есть 006, блок уже передан (просит 006) → ход Gemini (прикрепить/ждать)' {
    $now=Get-Date; $f=Rep 'Eskalator_2026-10-23_006.md' $now
    $c=@(Get-ReportCandidates -Files @(Get-Item $f.FullName) -Project 'Eskalator' -Pattern $Cfg.Pattern)[-1]
    $hdr=Get-BlockAsk 'Нужен Eskalator_2026-10-23_006.md' $Cfg.Pattern
    Add-SentRecord $script:St 'ag' 'Eskalator' 6 'b6'
    $d=Get-TurnDecision -Header $hdr -BlockHash 'b6' -Report $c -ReportHash 'r6' -State $script:St -LastAgAt $now.AddMinutes(-20)
    $d.turn | Should -Be 'gemini'; $d.action | Should -Be 'send-report'
  }
  It 'lastBlock.step=-1 не считается заголовком (не ломает ход)' {
    $script:St.activeProject='Eskalator'; $script:St.lastBlock=[ordered]@{ project='Eskalator'; step=-1; hash='x'; at='2026-10-24 11:00:00'; rework=$false }
    $now=Get-Date; [void](Rep 'Eskalator_2026-10-23_005.md' $now.AddMinutes(-5))
    $d=Get-TurnDecisionNow ''; $d.step | Should -BeLessThan 1   # без валидного заголовка не подставляем -1
  }
  It 'Register-BlockRelayed сохраняет шаг из имени файла' {
    Mock Get-ActiveProjectNow { 'Eskalator' }
    Register-BlockRelayed "нужен Eskalator_2026-10-23_006.md" 'abcd1234'
    $script:St.lastBlock.step | Should -Be 6; $script:St.lastBlock.project | Should -Be 'Eskalator'
    (Test-SentRecord $script:St 'ag' 'Eskalator' 6 'abcd1234') | Should -BeTrue
  }
}