BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 6: атомарная запись' -Tag Item06 {
  It 'пишет UTF-8 с BOM по умолчанию и без BOM по -NoBom; .tmp не остаётся' {
    $p=Join-Path $TestDrive 'a.json'
    Write-AtomicText -Path $p -Text 'привет'
    $b=[IO.File]::ReadAllBytes($p); $b[0..2] | Should -Be @(0xEF,0xBB,0xBF)
    Write-AtomicText -Path $p -Text 'ещё' -NoBom
    ([IO.File]::ReadAllBytes($p))[0] | Should -Not -Be 0xEF
    Test-Path "$p.tmp" | Should -BeFalse
  }
  It 'при замене существующего файла сохраняет предыдущую версию в .bak' {
    $p=Join-Path $TestDrive 'b.json'
    Write-AtomicText -Path $p -Text 'v1'; Write-AtomicText -Path $p -Text 'v2'
    [IO.File]::ReadAllText($p) | Should -Be 'v2'; [IO.File]::ReadAllText("$p.bak") | Should -Be 'v1'
  }
  It '-NoBackup не создаёт .bak' {
    $p=Join-Path $TestDrive 'c.json'; Write-AtomicText -Path $p -Text 'v1' -NoBackup; Write-AtomicText -Path $p -Text 'v2' -NoBackup
    Test-Path "$p.bak" | Should -BeFalse
  }
  It 'читающий процесс никогда не видит пустой/частичный файл (100 перезаписей, проверка после каждой)' {
    $p=Join-Path $TestDrive 'd.json'
    for($i=0;$i -lt 100;$i++){ Write-AtomicText -Path $p -Text (@{n=$i; pad=('x'*2000)} | ConvertTo-Json); ((Get-Content $p -Raw | ConvertFrom-Json).n) | Should -Be $i }
  }
  It 'Read-JsonWithBackup: битый основной файл — читает .bak' {
    $p=Join-Path $TestDrive 'e.json'
    Write-AtomicText -Path $p -Text '{"x":1}'; Write-AtomicText -Path $p -Text '{"x":2}'
    [IO.File]::WriteAllText($p,'{"x": 3,,,')
    $r=Read-JsonWithBackup $p
    $r.Source | Should -Be 'bak'; $r.Data.x | Should -Be 1
  }
  It 'Read-JsonWithBackup: нет файлов — Source none' { (Read-JsonWithBackup (Join-Path $TestDrive 'none.json')).Source | Should -Be 'none' }
}
Describe 'Пункт 6: машина состояний' -Tag Item06 {
  It 'допустимые переходы проходят: <f> -> <t>' -TestCases @(
    @{f='';t='sent'},@{f='sent';t='answered'},@{f='answered';t='relayed'},@{f='sent';t='resend'},@{f='resend';t='sent'},
    @{f='sent';t='nocode'},@{f='sent';t='stale'},@{f='stale';t='relayed'},@{f='stale';t='resend'},@{f='answered';t='resend'},@{f='sent';t='relayed'}
  ) { Test-StageTransition $f $t | Should -BeTrue }
  It 'недопустимые отвергаются: <f> -> <t>' -TestCases @(
    @{f='relayed';t='sent'},@{f='done';t='sent'},@{f='';t='answered'},@{f='';t='relayed'},@{f='nocode';t='relayed'},@{f='answered';t='sent'}
  ) { Test-StageTransition $f $t | Should -BeFalse }
  It 'Set-FileStage бросает на недопустимом переходе, -Force разрешает; считает попытки отправки' {
    $s=New-RelayState
    Set-FileStage $s 'A_2026-10-18_001.md' 'sent' | Should -BeTrue
    { Set-FileStage $s 'A_2026-10-18_001.md' 'done2' } | Should -Throw '*Недопустимый*'
    Set-FileStage $s 'A_2026-10-18_001.md' 'resend' | Out-Null; Set-FileStage $s 'A_2026-10-18_001.md' 'sent' | Out-Null
    $s.files['A_2026-10-18_001.md'].attempts | Should -Be 2
    Set-FileStage $s 'A_2026-10-18_001.md' 'answered' -Hash 'abcd1234' | Out-Null
    Set-FileStage $s 'A_2026-10-18_001.md' 'relayed' | Out-Null
    $s.files['A_2026-10-18_001.md'].hash | Should -Be 'abcd1234'
    { Set-FileStage $s 'A_2026-10-18_001.md' 'sent' } | Should -Throw
    Set-FileStage $s 'A_2026-10-18_001.md' 'sent' -Force | Should -BeTrue
  }
  It 'повторная установка того же этапа — без изменений ($false)' { $s=New-RelayState; Set-FileStage $s 'X' 'sent' | Out-Null; Set-FileStage $s 'X' 'sent' | Should -BeFalse }
  It 'Test-FileDone: relayed/nocode/done/abandoned — завершены; stale/sent — нет' {
    $s=New-RelayState
    foreach($p in @(@('a','relayed'),@('b','nocode'),@('c','done'),@('d','abandoned'),@('e','stale'),@('f','sent'))){ $s.files[$p[0]]=[ordered]@{stage=$p[1]} }
    @('a','b','c','d') | ForEach-Object { Test-FileDone $s $_ | Should -BeTrue }
    @('e','f','zzz') | ForEach-Object { Test-FileDone $s $_ | Should -BeFalse }
  }
  It 'сохранение/чтение relay_state.json — без потерь' {
    $s=New-RelayState; Set-FileStage $s 'Кириллица_2026-10-18_001.md' 'sent' | Out-Null; Add-RelayHash $s 'deadbeef'
    $p=Join-Path $TestDrive 'relay_state.json'; Save-RelayState $s $p
    $r=Read-RelayState $p
    $r.Source | Should -Be 'main'; (Get-FileStage $r.State 'Кириллица_2026-10-18_001.md') | Should -Be 'sent'; $r.State.hashes | Should -Be @('deadbeef')
  }
  It 'битый relay_state.json — восстановление из .bak, а не пустое состояние (раньше: повторная отправка)' {
    $p=Join-Path $TestDrive 'rs2.json'
    $s=New-RelayState; Set-FileStage $s 'A_2026-10-18_001.md' 'sent' | Out-Null; Save-RelayState $s $p
    Set-FileStage $s 'A_2026-10-18_002.md' 'sent' | Out-Null; Save-RelayState $s $p
    [IO.File]::WriteAllText($p,'{"files": {')
    $r=Read-RelayState $p
    $r.Source | Should -Be 'bak'; Get-FileStage $r.State 'A_2026-10-18_001.md' | Should -Be 'sent'
  }
}
Describe 'Пункт 6: хэши и чистка' -Tag Item06 {
  It 'Add-RelayHash: без дублей, последние N' {
    $s=New-RelayState; 1..5 | ForEach-Object { Add-RelayHash $s ('{0:x8}' -f $_) -Keep 3 }
    $s.hashes | Should -Be @('00000003','00000004','00000005')
    Add-RelayHash $s '00000003' -Keep 3; $s.hashes | Should -Be @('00000004','00000005','00000003')
    Test-RelayHash $s '00000004' | Should -BeTrue; Test-RelayHash $s '00000001' | Should -BeFalse
  }
  It 'Compress-RelayState не трогает файлы, которые есть в Downloads, и незавершённые' {
    $s=New-RelayState
    1..10 | ForEach-Object { $s.files[('A_2026-10-01_{0:D3}.md' -f $_)]=[ordered]@{stage='relayed'} }
    $s.files['A_2026-10-01_011.md']=[ordered]@{stage='sent'}
    $n=Compress-RelayState $s -ExistingNames @('A_2026-10-01_001.md') -Keep 3 -Pattern $Cfg.Pattern
    $n | Should -Be 6
    $s.files.Contains('A_2026-10-01_001.md') | Should -BeTrue -Because 'файл ещё лежит в Downloads — иначе он считался бы новым'
    $s.files.Contains('A_2026-10-01_011.md') | Should -BeTrue
    $s.files.Contains('A_2026-10-01_010.md') | Should -BeTrue; $s.files.Contains('A_2026-10-01_002.md') | Should -BeFalse
  }
}
