# Пункт 46: лимит Gemini / не-Argon блокирует только отправку В Gemini; дописанный блок Argon передаётся в Antigravity. Лимит Antigravity — только передачу В Antigravity.
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Blk="[ARGON>FLASH] [Arena] [S010] [2026-10-21]`nСделай шаг 10: доработай арену.`n[[END S010]]"
}
Describe 'Пункт 46: лимит одной стороны' -Tag Item46 {
  BeforeEach {
    Mock Log {}; Mock Tg-Send { 1 }; Mock Save-State {}; Mock Play-Sound {}; Mock New-TgPrompt { 1 }
    $script:St=New-RelayState; $script:Held=@{}; $script:Paused=$false; $script:LimitStop=$false; $script:QStopG=$false; $script:QStopA=$false; $script:AgBlock=$null
    $script:LastMirror=$null; $script:MirrorSeen=$null; $Cfg.MirrorRelay=$true; $Cfg.MaxReportAgeHours=12
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $p=Join-Path $Cfg.Downloads 'Arena_2026-10-21_009.md'; [IO.File]::WriteAllText($p,'отчёт 9')
    $script:St.files['Arena_2026-10-21_009.md']=[ordered]@{ stage='resend'; time=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); hash=''; attempts=0; note='' }
    Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { @{ answered=$true; md=$true; code=$script:Blk; labels=@('Markdown') } }
    Mock Gem-CopyCode { $script:Blk }; Mock Ag-HasText { $false }; Mock Assert-AgReady { @{ ok=$true } }; Mock Get-AnswerRefNow { $null }
    $script:AgSent=0; Mock Ag-Send { $script:AgSent++ }
  }
  It 'инцидент 21.10: Argon дописал S010, модель переключилась на Flash-Lite (LimitStop) — блок всё равно уходит в Antigravity один раз' {
    Mock Get-ModelNow { 'Flash-Lite' }; $script:LimitStop=$true; $script:LimitModel='Flash-Lite'
    [void](Invoke-MirrorGemini -Force); Invoke-MirrorGemini -Force | Should -BeTrue
    $script:AgSent | Should -Be 1
    (Get-Stage 'Arena_2026-10-21_009.md') | Should -Be 'relayed'
    1..3 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:AgSent | Should -Be 1
  }
  It 'лимит Gemini (сайт, QStopG) — блок тоже передаётся' {
    Mock Get-ModelNow { 'Argon' }; $script:QStopG=$true
    [void](Invoke-MirrorGemini -Force); Invoke-MirrorGemini -Force | Should -BeTrue; $script:AgSent | Should -Be 1
  }
  It 'Flash-Lite и метки не сходятся ([[END S009]]) — не передаю' {
    $script:Blk="[ARGON>FLASH] [Arena] [S010] [2026-10-21]`nтекст`n[[END S009]]"; Mock Get-ModelNow { 'Flash-Lite' }; $script:LimitStop=$true
    1..3 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:AgSent | Should -Be 0
  }
  It 'Flash-Lite, блок без меток — разрешено, с пояснением для лога' {
    $r=Test-BlockFromArgon -Code 'Просто задание без заголовка' -ArgonNow $false -Gate (Get-BlockGate 'Просто задание без заголовка')
    $r.ok | Should -BeTrue; $r.why | Should -Match 'меток нет'
  }
  It 'лимит Antigravity — в Antigravity не передаю' {
    Mock Get-ModelNow { 'Argon' }; $script:QStopA=$true
    1..3 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:AgSent | Should -Be 0
  }
  It 'Relay-ToAg при лимите Antigravity бросает лимит, ничего не вставляет' {
    $script:QStopA=$true
    { Relay-ToAg 'Arena_2026-10-21_009.md' $script:Blk 'h' 'Argon' } | Should -Throw
    $script:AgSent | Should -Be 0
  }
  It 'Test-BlockFromArgon' {
    (Test-BlockFromArgon -Code 'x' -ArgonNow $true -Gate $null).ok | Should -BeTrue
    (Test-BlockFromArgon -Code $script:Blk -ArgonNow $false -Gate @{ tagged=$true; ok=$true }).ok | Should -BeTrue
    (Test-BlockFromArgon -Code $script:Blk -ArgonNow $false -Gate @{ tagged=$true; ok=$false; reason='r' }).ok | Should -BeFalse
    (Test-BlockFromArgon -Code 'abc' -ArgonNow $false -Gate @{ tagged=$false; ok=$true }).ok | Should -BeTrue
  }
  It 'индикатор: лимит Gemini и блок ждёт — «Ход Antigravity»; лимит Antigravity и новый отчёт — «Ход Gemini»; иначе limit' {
    Get-RelayTurn -Kind 'limit' -LimitSide 'gemini' -Decision 'antigravity' | Should -Be 'antigravity'
    Get-RelayTurn -Kind 'limit' -LimitSide 'antigravity' -NextFile 'Arena_2026-10-21_010.md' | Should -Be 'gemini'
    Get-RelayTurn -Kind 'limit' -LimitSide 'gemini' | Should -Be 'limit'
    Get-RelayTurn -Kind 'limit' -Stages @('sent') | Should -Be 'limit'
  }
}
