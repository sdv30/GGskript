BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 11: Wait-FileStable (настоящие файлы)' -Tag Item11 {
  BeforeEach { Mock Pump {}; $script:p=Join-Path $TestDrive ("r_{0}.md" -f [guid]::NewGuid().ToString('N')) }
  It 'готовый файл — возвращается после одного интервала' {
    [IO.File]::WriteAllText($script:p,'отчёт'); Mock Nap {}
    { Wait-FileStable $script:p 1 5 } | Should -Not -Throw
    Should -Invoke Nap -Times 1 -Exactly
  }
  It 'файл ещё растёт — ждёт, пока размер перестанет меняться' {
    [IO.File]::WriteAllText($script:p,'a'); $script:grow=3
    Mock Nap { if($script:grow -gt 0){ [IO.File]::AppendAllText($script:p,'bbbb'); $script:grow-- } }
    Wait-FileStable $script:p 1 30
    Should -Invoke Nap -Times 4 -Exactly
    (Get-Item $script:p).Length | Should -Be 13
  }
  It 'меняется только время записи (тот же размер) — тоже ждёт' {
    [IO.File]::WriteAllText($script:p,'abc'); $script:touch=2
    Mock Nap { if($script:touch -gt 0){ [IO.File]::SetLastWriteTimeUtc($script:p,(Get-Date).ToUniversalTime().AddSeconds(-100*$script:touch)); $script:touch-- } }
    Wait-FileStable $script:p 1 30
    Should -Invoke Nap -Times 3 -Exactly
  }
  It 'пустой файл (ещё не записан) — по таймауту исключение, не отправляется' {
    [IO.File]::WriteAllText($script:p,''); Mock Nap { Start-Sleep -Milliseconds 400 }
    { Wait-FileStable $script:p 1 1 } | Should -Throw '*не стабилизировался*'
  }
  It 'файл занят другим процессом (открыт без общего доступа) — ждёт; освобождён — продолжает' {
    [IO.File]::WriteAllText($script:p,'отчёт')
    $fs=[IO.File]::Open($script:p,'Open','ReadWrite','None')
    try{
      Mock Nap { Start-Sleep -Milliseconds 400 }
      { Wait-FileStable $script:p 1 1 } | Should -Throw '*занят*'
    } finally { $fs.Dispose() }
    { Wait-FileStable $script:p 1 5 } | Should -Not -Throw
  }
  It 'файл исчез (браузер переименовал .crdownload) — исключение, а не зависание' {
    Mock Nap {}; { Wait-FileStable (Join-Path $TestDrive 'нет.md') 1 5 } | Should -Throw
  }
}
Describe 'Пункт 11: Get-Files и Process-File' -Tag Item11 {
  BeforeEach { $script:St=New-RelayState; Get-ChildItem $Cfg.Downloads | Remove-Item -Force; Mock Log {}; Mock Save-State {} }
  It 'берёт только *.md по шаблону; .crdownload/.tmp игнорирует; сортирует по ключу' {
    foreach($n in 'P_2026-10-18_010.md','P_2026-10-18_002.md','P_2026-10-18_003.md.crdownload','P_2026-10-18_004.tmp','заметка.md'){ [IO.File]::WriteAllText((Join-Path $Cfg.Downloads $n),'x') }
    @(Get-Files -All | ForEach-Object Name) | Should -Be @('P_2026-10-18_002.md','P_2026-10-18_010.md')
  }
  It 'файл не стабилизировался — в Gemini не отправляется, этап не меняется' {
    [IO.File]::WriteAllText((Join-Path $Cfg.Downloads 'P_2026-10-18_005.md'),'x')
    Mock Wait-FileStable { throw 'Файл не стабилизировался' }; Mock Gem-Send {}; Mock Assert-CanSendGemini { 'Argon' }; Mock Gem-GetModel { 'Argon' }
    { Process-File (Get-Item (Join-Path $Cfg.Downloads 'P_2026-10-18_005.md')) } | Should -Throw
    Should -Invoke Gem-Send -Times 0; Get-Stage 'P_2026-10-18_005.md' | Should -Be ''
  }
}
