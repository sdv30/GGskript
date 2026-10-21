# Пункт 41: индикатор «чей ход» — воркер пишет turn в relay_status.json, панель рисует плитки.
BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1'); $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {} }
Describe 'Item41 Чей ход' -Tag 'Item41' {
  It 'стоп и лимит важнее всего' {
    Get-RelayTurn -Kind 'paused' -Stages @('sent') | Should -Be 'stopped'
    Get-RelayTurn -Kind 'stopped' | Should -Be 'stopped'
    Get-RelayTurn -Kind 'limit' -Stages @('sent') | Should -Be 'limit'
  }
  It 'отчёт в Gemini (sent/resend/stale) — ход Gemini' {
    foreach($s in 'sent','resend','stale'){ Get-RelayTurn -Kind 'running' -Stages @('relayed',$s) -LastSide 'antigravity' | Should -Be 'gemini' }
  }
  It 'ответ получен и идёт в Antigravity — ход Antigravity' { Get-RelayTurn -Kind 'running' -Stages @('answered') | Should -Be 'antigravity' }
  It 'новый отчёт ждёт отправки — ход Gemini' { Get-RelayTurn -Kind 'running' -Stages @('relayed') -NextFile 'Arena_2026-10-20_007.md' -LastSide 'antigravity' | Should -Be 'gemini' }
  It 'после передачи блока ждём отчёт — ход Antigravity; иначе простой' {
    Get-RelayTurn -Kind 'running' -Stages @('relayed','done') -LastSide 'antigravity' | Should -Be 'antigravity'
    Get-RelayTurn -Kind 'running' -AgWatch $true | Should -Be 'antigravity'
    Get-RelayTurn -Kind 'running' | Should -Be 'idle'
  }
  It 'сторона по этапу' {
    Get-TurnSideOfStage 'sent' '' | Should -Be 'gemini'; Get-TurnSideOfStage 'relayed' 'gemini' | Should -Be 'antigravity'
    Get-TurnSideOfStage 'nocode' 'gemini' | Should -Be 'gemini'
  }
  It 'Set-Stage запоминает сторону' {
    $script:St=New-RelayState; $script:TurnSide=''; Mock Save-State {}
    Set-Stage 'Arena_2026-10-20_007.md' 'sent'; $script:TurnSide | Should -Be 'gemini'
    Set-Stage 'Arena_2026-10-20_007.md' 'relayed' 'h1'; $script:TurnSide | Should -Be 'antigravity'
  }
  It 'вид индикатора: подсветка, подписи, анимация' {
    $v=Get-TurnView 'gemini'; $v.G | Should -Be 'active'; $v.A | Should -Be 'wait'; $v.Caption | Should -Be 'Ход Gemini'; $v.Anim | Should -BeTrue
    $v=Get-TurnView 'antigravity'; $v.A | Should -Be 'active'; $v.Caption | Should -Be 'Ход Antigravity'
    $v=Get-TurnView 'stopped'; $v.Anim | Should -BeFalse; $v.G | Should -Be 'off'; $v.A | Should -Be 'off'
    (Get-TurnView 'limit').G | Should -Be 'limit'; (Get-TurnView 'gemini' $false).Caption | Should -Be 'Скрипт не запущен'
    Get-TurnTileSub 'wait' | Should -Be 'ожидание'
  }
  It 'панель: двойная буферизация, таймер анимации 150–300 мс, эмодзи Segoe UI Emoji' {
    $src=Get-Content (Join-Path $script:V2Root 'GGskript_gui.ps1') -Raw -Encoding UTF8
    $src | Should -Match 'OptimizedDoubleBuffer'; $src | Should -Match "Segoe UI Emoji"
    [int]([regex]::Match($src,'turnTimer\.Interval=(\d+)').Groups[1].Value) | Should -BeIn (150..300)
    $src | Should -Match 'Controls\.Add\(\$pnlTurn\)'
  }
}
