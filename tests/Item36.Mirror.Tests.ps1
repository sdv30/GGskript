BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Ans="[ARGON>FLASH] [Arena] [S004] [REWORK S003] [2026-10-20]`nСделай следующее: переработай модуль арены и добавь проверки.`n[[END S004]]"  # пункт 44: метка конца обязательна при заголовке [ARGON>FLASH]
}
Describe 'Пункт 36: наблюдатель-зеркало Gemini -> Antigravity' -Tag Item36 {
  BeforeEach {
    Mock Log {}; Mock Tg-Send { 1 }; Mock Save-State {}; Mock Play-Sound {}
    $script:St=New-RelayState; $script:Held=@{}; $script:Paused=$false; $script:LimitStop=$false; $script:QStopG=$false; $script:QStopA=$false; $script:AgBlock=$null
    $script:LastMirror=$null; $script:MirrorSeen=$null; $Cfg.MirrorRelay=$true
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $p=Join-Path $Cfg.Downloads 'Arena_2026-10-20_003.md'; [IO.File]::WriteAllText($p,'отчёт')
    $script:St.files['Arena_2026-10-20_003.md']=[ordered]@{ stage='skipped'; time='2026-10-20 22:57:28'; hash=''; attempts=0; note='авторешение' }
    Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { @{ answered=$true; md=$true; code=$script:Ans; labels=@('Markdown') } }
    Mock Get-ModelNow { 'Argon' }; Mock Gem-CopyCode { $script:Ans }; Mock Ag-HasText { $false }; Mock Assert-AgReady { @{ ok=$true } }
    $script:AgSent=0; Mock Ag-Send { $script:AgSent++ }
  }
  It 'по умолчанию включён' { (Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive).MirrorRelay | Should -BeTrue }
  It 'ручная отправка 003 (этап skipped): новый блок передаётся после двух одинаковых чтений, 003 -> relayed' {
    Invoke-MirrorGemini -Force | Should -BeFalse; $script:AgSent | Should -Be 0
    Invoke-MirrorGemini -Force | Should -BeTrue; $script:AgSent | Should -Be 1
    Get-Stage 'Arena_2026-10-20_003.md' | Should -Be 'relayed'; Test-RelayHash $script:St (Get-Hash8 $script:Ans) | Should -BeTrue
  }
  It 'уже переданный блок (хэш) — не дублирует' {
    Add-RelayHash $script:St (Get-Hash8 $script:Ans); 1..3 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:AgSent | Should -Be 0
  }
  It 'блок уже вставлен в Antigravity вручную — не вставляет, отмечает' {
    Mock Ag-HasText { $true }; 1..2 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }
    $script:AgSent | Should -Be 0; Test-RelayHash $script:St (Get-Hash8 $script:Ans) | Should -BeTrue
  }
  It 'Gemini генерирует / нет блока / СТОП / не Argon — ничего не делает' {
    Mock Gem-IsGenerating { $true }; 1..2 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }
    Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { @{ answered=$true; md=$false; code=''; labels=@('python') } }; 1..2 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }
    Mock Gem-PeekAnswer { @{ answered=$true; md=$true; code=$script:Ans; labels=@('Markdown') } }
    $script:Paused=$true; 1..2 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:Paused=$false
    Mock Get-ModelNow { 'Flash-Lite' }; 1..2 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }
    $script:AgSent | Should -Be 0
  }
  It 'ответ дописывается (меняется между чтениями) — ждёт стабильности' {
    $script:i=0; Mock Gem-PeekAnswer { $script:i++; @{ answered=$true; md=$true; code="$($script:Ans) $($script:i)"; labels=@('Markdown') } }
    1..3 | ForEach-Object { [void](Invoke-MirrorGemini -Force) }; $script:AgSent | Should -Be 0
  }
  It 'без -Force соблюдает интервал MirrorEverySec' {
    $Cfg.MirrorEverySec=15; [void](Invoke-MirrorGemini); Invoke-MirrorGemini | Should -BeFalse; Should -Invoke Gem-PeekAnswer -Times 1 -Exactly
  }
  It 'Test-AnswerRefersTo: по REWORK S003 / имени файла; чужой номер — нет' {
    Test-AnswerRefersTo $script:Ans 'Arena_2026-10-20_003.md' | Should -BeTrue
    Test-AnswerRefersTo "отчёт Arena_2026-10-20_007.md принят" 'Arena_2026-10-20_007.md' | Should -BeTrue
    Test-AnswerRefersTo "[S010] next" 'Arena_2026-10-20_003.md' | Should -BeFalse
  }
  It 'противоречие по имени между разными проектами не считается' {
    (ProjOf 'DeepNTRskript_2026-10-20_006.md') -eq (ProjOf 'Arena_2026-10-20_003.md') | Should -BeFalse
  }
}
