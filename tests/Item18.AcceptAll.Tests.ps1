BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function New-Repo{ $r=Join-Path $TestDrive ('repo_'+[guid]::NewGuid().ToString('N').Substring(0,8)); New-Item $r -ItemType Directory | Out-Null
    & git -C $r init -q 2>$null; & git -C $r -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>$null; $r }
  function Get-CommitCount($r){ [int](& git -C $r rev-list --count HEAD) }
}
Describe 'Пункт 18: git-чекпоинт перед Accept all (настоящий git)' -Tag Item18 {
  BeforeEach { Mock Log {} }
  It 'не настроен — $true, git не вызывается' { $Cfg.GitCheckpointRepo=''; Mock Invoke-Git {}; Invoke-GitCheckpoint | Should -BeTrue; Should -Invoke Invoke-Git -Times 0 }
  It 'есть изменения — коммит всех файлов (включая новые), сообщение с датой' {
    $r=New-Repo; $Cfg.GitCheckpointRepo=$r; [IO.File]::WriteAllText((Join-Path $r 'a.txt'),'код')
    Invoke-GitCheckpoint | Should -BeTrue
    Get-CommitCount $r | Should -Be 2
    (& git -C $r log -1 --format=%s) | Should -Match '^GGskript checkpoint before Accept all \d{4}-\d\d-\d\d'
    (& git -C $r status --porcelain) | Should -BeNullOrEmpty
  }
  It 'нет изменений — новый коммит не создаётся' { $r=New-Repo; $Cfg.GitCheckpointRepo=$r; Invoke-GitCheckpoint | Should -BeTrue; Get-CommitCount $r | Should -Be 1 }
  It 'не репозиторий — $false и запись в лог' { $Cfg.GitCheckpointRepo=(Join-Path $TestDrive 'nogit'); New-Item $Cfg.GitCheckpointRepo -ItemType Directory -Force | Out-Null; Invoke-GitCheckpoint | Should -BeFalse; Should -Invoke Log -ParameterFilter { $m -like '*не удался*' } }
}
Describe 'Пункт 18: Try-AcceptAll' -Tag Item18 {
  BeforeEach {
    $script:Paused=$false; $Cfg.GitCheckpointRepo=''; $Cfg.GitCheckpointRequired=$false
    Mock Log {}; Mock Tg-Send { $true }; Mock Ag-GetWindow { 42 }; Mock Find-AcceptAll { 'BTN' }; Mock Uia-ClickEl { $true }
    Mock Invoke-WithFocus { & $Body }
  }
  It 'нажимает, если кнопка есть' { Try-AcceptAll | Should -BeTrue; Should -Invoke Uia-ClickEl -Times 1 }
  It 'нет кнопки — ничего не делает (и чекпоинт не нужен)' { Mock Find-AcceptAll { $null }; Mock Invoke-GitCheckpoint { $true }; Try-AcceptAll | Should -BeFalse; Should -Invoke Invoke-GitCheckpoint -Times 0 }
  It 'на паузе — не нажимает' { $script:Paused=$true; Try-AcceptAll | Should -BeFalse; Should -Invoke Uia-ClickEl -Times 0 }
  It 'чекпоинт не удался + GitCheckpointRequired — НЕ нажимает, сообщает в Telegram' {
    $Cfg.GitCheckpointRequired=$true; Mock Invoke-GitCheckpoint { $false }
    Try-AcceptAll | Should -BeFalse; Should -Invoke Uia-ClickEl -Times 0; Should -Invoke Tg-Send -ParameterFilter { $Text -like '⛔ Accept all НЕ нажат*' }
  }
  It 'чекпоинт не удался, но не обязателен — нажимает (прежнее поведение)' { Mock Invoke-GitCheckpoint { $false }; Try-AcceptAll | Should -BeTrue }
  It 'чекпоинт делается ДО нажатия' {
    $script:order=@(); Mock Invoke-GitCheckpoint { $script:order+='git'; $true }; Mock Uia-ClickEl { $script:order+='click'; $true }
    Try-AcceptAll | Out-Null; $script:order | Should -Be @('git','click')
  }
}
Describe 'Пункт 18: AcceptAllDuringWait' -Tag Item18 {
  BeforeEach { $Cfg.AcceptAllDuringWait=$true; $Cfg.AcceptAllEverySec=12; $script:Busy=$true; $script:Paused=$false; $script:InAux=$false; $script:FocusDepth=0; $script:LastAuxDuringWait=(Get-Date).AddMinutes(-1); Mock Try-AcceptAll { $true }; Mock Log {} }
  It 'во время ожидания (Busy) — нажимает не чаще AcceptAllEverySec' { Invoke-AuxDuringWait; Invoke-AuxDuringWait; Should -Invoke Try-AcceptAll -Times 1 -Exactly }
  It 'по умолчанию выключено (как раньше)' { $Cfg.AcceptAllDuringWait=$false; Invoke-AuxDuringWait; Should -Invoke Try-AcceptAll -Times 0 }
  It 'не во время операции с фокусом/буфером' { $script:FocusDepth=1; Invoke-AuxDuringWait; Should -Invoke Try-AcceptAll -Times 0 }
  It 'не на паузе и не вне рабочего шага' { $script:Paused=$true; Invoke-AuxDuringWait; $script:Paused=$false; $script:Busy=$false; Invoke-AuxDuringWait; Should -Invoke Try-AcceptAll -Times 0 }
  It 'без повторного входа (Try-AcceptAll → Nap → Pump → снова)' {
    Mock Try-AcceptAll { $script:LastAuxDuringWait=(Get-Date).AddMinutes(-1); Invoke-AuxDuringWait; $true }
    Invoke-AuxDuringWait; Should -Invoke Try-AcceptAll -Times 1 -Exactly
  }
  It 'ошибка Accept all не прерывает ожидание ответа' { Mock Try-AcceptAll { throw 'UIA упал' }; { Invoke-AuxDuringWait } | Should -Not -Throw; $script:InAux | Should -BeFalse }
  It 'Invoke-WithFocus поднимает и опускает FocusDepth (даже при исключении)' {
    Mock Wait-UserIdle {}; Mock Get-ForegroundHandle { 0 }; Mock Activate-Window {}
    $script:seen=-1; Invoke-WithFocus 1 { $script:seen=$script:FocusDepth }
    $script:seen | Should -Be 1; $script:FocusDepth | Should -Be 0
    { Invoke-WithFocus 1 { throw 'x' } } | Should -Throw; $script:FocusDepth | Should -Be 0
  }
}
