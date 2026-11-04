BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 57: воркер не перехватывает фокус/клавиатуру/мышь/буфер' -Tag Item57 {
  BeforeEach { Mock Log {}; Mock Tg-Send { $true }; $script:GGWorker=$true; $script:Paused=$false; $Cfg.PauseFile=Join-Path $TestDrive 'NOPAUSE'; $Cfg.AllowWindowMode=$false; $Cfg.WindowModeIdleMin=0; $script:WindowModeSaid=$null }
  AfterEach { $script:GGWorker=$false; $Cfg.AllowWindowMode=$false; $Cfg.WindowModeIdleMin=0 }
  It 'по умолчанию: оконный режим и откат Gemini на UIA выключены' {
    $d=Get-DefaultSettings -Root $TestDrive; $d.AllowWindowMode | Should -BeFalse; $d.GeminiCdpFallback | Should -BeFalse; $d.WindowModeIdleMin | Should -Be 0
  }
  It 'Activate-Window / KeyDown / ClickAt / Set-ClipText — бросают «не отправлено», ничего не делая' {
    { Activate-Window ([IntPtr]1) } | Should -Throw '*оконный режим запрещён*'
    { KeyDown 0x41 } | Should -Throw '*оконный режим запрещён*'
    { ClickAt 10 10 } | Should -Throw '*оконный режим запрещён*'
    (Get-Content (Join-Path $PSScriptRoot '../lib/Platform.Win.ps1') -Raw -Encoding UTF8) | Should -Match "Assert-WindowMode 'запись в буфер обмена'"
  }
  It 'исключение — RelayNotSentException (реле не считает отправленным)' {
    try{ KeyDown 0x41 }catch{ $_.Exception.GetType().Name | Should -Be 'RelayNotSentException' }
  }
  It 'Telegram-уведомление один раз, а не каждую минуту' {
    1..3 | ForEach-Object { try{ KeyDown 0x41 }catch{} }; Should -Invoke Tg-Send -Times 1 -Exactly
  }
  It 'AllowWindowMode + простой N мин: пользователь активен — запрещено, простаивает — разрешено' {
    $Cfg.AllowWindowMode=$true; $Cfg.WindowModeIdleMin=5
    Mock Get-IdleMs { 1000 }; Test-WindowModeAllowed | Should -BeFalse
    Mock Get-IdleMs { 6*60000 }; Test-WindowModeAllowed | Should -BeTrue
  }
  It 'не воркер (панель) — ограничение не действует' { $script:GGWorker=$false; Test-WindowModeAllowed | Should -BeTrue }
  It 'Gemini: CDP недоступен и откат выключен — UIA не вызывается, ошибка наружу + одно уведомление' {
    $Cfg.GeminiTransport='cdp'; $Cfg.GeminiCdpFallback=$false; $script:CdpDownSaid=$false; $script:CdpDownUntil=$null
    Mock Test-CdpUnreachable { $true }; $script:uia=0
    { Use-GemTransport 'тест' { $script:uia++ } { throw [GG.RelayNotSentException]::new('порт не отвечает') } -Send } | Should -Throw
    $script:uia | Should -Be 0; Should -Invoke Tg-Send -Times 1
  }
}
Describe 'Пункт 57: кнопка «⛔ Выключить скрипт» на панели' -Tag Item57 {
  It 'кнопка есть на главной панели, красная, и в меню тоже' {
    $g=Get-Content (Join-Path $PSScriptRoot '../GGskript_gui.ps1') -Raw -Encoding UTF8
    $g | Should -Match "\`$btnExit=New-Btn '⛔ Выключить скрипт'"; $g | Should -Match '\$btnExit\.ForeColor=\[System\.Drawing\.Color\]::Red'
    $g | Should -Match "Add-BtnRow '[^']*' @\(\`$btnExit\)"; $g | Should -Match '\$btnExit\.Add_Click\(\$script:doExit\)'; $g | Should -Match '\$miExit\.Add_Click\(\$script:doExit\)'
    $g | Should -Match 'Stop-Process -Id \$p -Force'
  }
  It 'Get-WorkerPids: только воркер, не панель' {
    $pr={ @([pscustomobject]@{ProcessId=11;CommandLine='powershell -File "..\x\GGskript.ps1"'},[pscustomobject]@{ProcessId=12;CommandLine='powershell -File "..\x\GGskript_gui.ps1"'},[pscustomobject]@{ProcessId=13;CommandLine='powershell'}) }
    @(Get-WorkerPids -GetProcs $pr) | Should -Be @(11)
  }
}
