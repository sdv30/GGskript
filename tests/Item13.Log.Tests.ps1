BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 13: ротация лога и рост файлов' -Tag Item13 {
  BeforeEach { $script:lp=Join-Path $TestDrive ('log_{0}.txt' -f [guid]::NewGuid().ToString('N')) }
  It 'меньше лимита — не трогает' { [IO.File]::WriteAllText($script:lp,'x'); Invoke-LogRotate -Path $script:lp -MaxMB 1 -Keep 3 | Should -BeFalse; Test-Path "$($script:lp).1" | Should -BeFalse }
  It 'нет файла — без ошибки' { Invoke-LogRotate -Path $script:lp -MaxMB 1 | Should -BeFalse }
  It 'больше лимита — .1, сдвиг архивов, не более Keep архивов' {
    for($i=1;$i -le 6;$i++){ [IO.File]::WriteAllText($script:lp,("gen$i "+('z'*2000))); Invoke-LogRotate -Path $script:lp -MaxMB 0.001 -Keep 3 | Should -BeTrue }
    Test-Path $script:lp | Should -BeFalse
    @(Get-ChildItem "$($script:lp).*").Count | Should -Be 3
    (Get-Content "$($script:lp).1" -Raw) | Should -Match '^gen6'
    (Get-Content "$($script:lp).3" -Raw) | Should -Match '^gen4'
  }
  It 'Log: пишет UTF-8 без BOM, кириллица читается, вызывает ротацию' {
    $Cfg.LogFile=$script:lp; $Cfg.LogMaxMB=0.001; $Cfg.LogKeep=2; $script:LogLines=0; Mock Write-Host {}
    [IO.File]::WriteAllText($script:lp,('y'*3000))
    Log 'Привет, лог'
    Test-Path "$($script:lp).1" | Should -BeTrue
    $b=[IO.File]::ReadAllBytes($script:lp); ($b[0] -eq 0xEF) | Should -BeFalse
    [Text.Encoding]::UTF8.GetString($b) | Should -Match 'Привет, лог'
  }
  It 'Log без настроек (до загрузки Cfg) не падает' { Mock Write-Host {}; $saved=$Cfg; $Cfg=$null; { Log 'x' } | Should -Not -Throw; $Cfg=$saved }
  It 'Format-Short: короткий — как есть, длинный — обрезка + длина + хэш' {
    Format-Short 'abc' 10 | Should -Be 'abc'
    $t='я'*500; $r=Format-Short $t 300
    $r | Should -Match '^я{300}… \[500 симв\., хэш [0-9a-f]{8}\]$'
  }
  It 'хэши ответов ограничены HashKeep (последние N, без дублей)' {
    $s=New-RelayState; 1..250 | ForEach-Object { Add-RelayHash $s ("h$_") 200 }; Add-RelayHash $s 'h250' 200
    $s.hashes.Count | Should -Be 200; $s.hashes[0] | Should -Be 'h51'; $s.hashes[-1] | Should -Be 'h250'
  }
  It 'учёт файлов: старые завершённые записи без файла удаляются сверх StateKeepTerminal, активные — никогда' {
    $s=New-RelayState
    1..30 | ForEach-Object { [void](Set-FileStage $s ('A_2026-01-01_{0:000}.md' -f $_) 'done' -Force) }
    [void](Set-FileStage $s 'A_2026-01-01_000.md' 'sent')
    Compress-RelayState $s -ExistingNames @('A_2026-01-01_001.md') -Keep 10 -Pattern $Cfg.Pattern | Should -Be 19
    $s.files.Contains('A_2026-01-01_000.md') | Should -BeTrue
    $s.files.Contains('A_2026-01-01_001.md') | Should -BeTrue
    $s.files.Contains('A_2026-01-01_030.md') | Should -BeTrue
    $s.files.Contains('A_2026-01-01_002.md') | Should -BeFalse
  }
  It 'длинная команда из Telegram пишется в лог укороченной' {
    $script:TgToken='t'; $script:TgChat='7'; $script:TgOffset=0; $script:TgBackoffUntil=$null; $script:StartUnix=0
    Mock Handle-Command {}; Mock Log {}
    Mock Invoke-Tg { [pscustomobject]@{ result=@([pscustomobject]@{ update_id=1; message=[pscustomobject]@{ text=('x'*5000); date=10; chat=[pscustomobject]@{id=7}; from=[pscustomobject]@{id=7} } }) } }
    Poll-Tg
    Should -Invoke Log -ParameterFilter { $m -like 'Telegram команда:*' -and $m.Length -lt 400 }
  }
}
