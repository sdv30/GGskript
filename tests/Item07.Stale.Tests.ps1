BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function New-Report($name,$text='отчёт'){ $p=Join-Path $Cfg.Downloads $name; [IO.File]::WriteAllText($p,$text); Get-Item $p }
}
Describe 'Пункт 7: stale вместо бесконечного повтора' -Tag Item07 {
  BeforeEach {
    $script:St=New-RelayState; $script:Paused=$false; $script:QStopG=$false; $script:QStopA=$false; $script:LimitStop=$false; $script:StaleNotified=@{}
    $script:answer="## Задача`nсделай X"; $script:agSent=@()
    Mock Log {}; Mock Tg-Send { $true }; Mock Save-State {}
    Mock Wait-FileStable {}
    Mock Gem-GetModel { 'Argon Ultra' }
    Mock Gem-SendFile { @{ before=1; pBefore=1; via='uia' } }
    Mock Gem-WaitAnswer { 1 }
    Mock Gem-CountPrompts { 2 }
    Mock Gem-LastReportPrompt { $null }
    Mock Gem-CopyCode { $script:answer }
    Mock Ag-Send { $script:agSent+=$Text }
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
  }
  It 'обычный ответ: передан, этап relayed, хэш запомнен' {
    $f=New-Report 'A_2026-10-18_001.md'
    Process-File $f
    Get-Stage 'A_2026-10-18_001.md' | Should -Be 'relayed'
    $script:agSent.Count | Should -Be 1
    Test-RelayHash $script:St (Get-Hash8 $script:answer) | Should -BeTrue
  }
  It 'повторный ответ: этап stale, в Antigravity не идёт, одно уведомление, повторный проход НЕ опрашивает Gemini' {
    Add-RelayHash $script:St (Get-Hash8 $script:answer)
    $f=New-Report 'A_2026-10-18_002.md'
    Process-File $f
    Get-Stage 'A_2026-10-18_002.md' | Should -Be 'stale'
    $script:agSent.Count | Should -Be 0
    Should -Invoke Tg-Send -Times 1 -ParameterFilter { $Text -like '*передай всё равно*' }
    Process-File $f; Process-File $f
    Should -Invoke Gem-WaitAnswer -Times 1 -Exactly
    Should -Invoke Gem-CopyCode -Times 1 -Exactly
    Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '*передай всё равно*' }
  }
  It '«передай всё равно»: передаёт stale-файл без проверки свежести, этап relayed' {
    Add-RelayHash $script:St (Get-Hash8 $script:answer)
    $f=New-Report 'A_2026-10-18_003.md'; Process-File $f
    Handle-Command 'передай всё равно' 'tg'
    $script:Queue.Count | Should -Be 1
    Run-Action ($script:Queue.Dequeue())
    Get-Stage 'A_2026-10-18_003.md' | Should -Be 'relayed'
    $script:agSent.Count | Should -Be 1
  }
  It '«отправь заново»: stale -> resend, следующий проход отправляет отчёт в Gemini снова' {
    Add-RelayHash $script:St (Get-Hash8 $script:answer)
    $f=New-Report 'A_2026-10-18_004.md'; Process-File $f
    Run-Action @{k='resendstale'}
    Get-Stage 'A_2026-10-18_004.md' | Should -Be 'resend'
    $script:answer="## Задача`nновое"
    Process-File $f
    Should -Invoke Gem-SendFile -Times 2 -Exactly
    Get-Stage 'A_2026-10-18_004.md' | Should -Be 'relayed'
  }
  It 'stale блокирует очередь (следующие файлы не обгоняют), Next-File указывает на stale-файл' {
    Add-RelayHash $script:St (Get-Hash8 $script:answer)
    $f=New-Report 'A_2026-10-18_005.md'; Process-File $f
    New-Report 'A_2026-10-18_006.md' | Out-Null
    (Next-File).Name | Should -Be 'A_2026-10-18_005.md'
  }
  It '«передай ответ» с повторным хэшем — понятная ошибка stale (а не молчаливый повтор)' {
    Add-RelayHash $script:St (Get-Hash8 $script:answer)
    { Run-Action @{k='relay'; whole=$false} } | Should -Throw -ExceptionType ([GG.RelayStaleException])
  }
  It 'Finish-Answered: ответ уже в Antigravity — не вставляет повторно' {
    $f=New-Report 'A_2026-10-18_007.md'
    [void](Set-FileStage $script:St $f.Name 'sent'); [void](Set-FileStage $script:St $f.Name 'answered' -Hash (Get-Hash8 $script:answer))
    Mock Ag-HasText { $true }
    Mock Assert-AgReady { @{ ok=$true; kind='ok' } }
    Process-File $f
    $script:agSent.Count | Should -Be 0; Get-Stage $f.Name | Should -Be 'relayed'
  }
}
