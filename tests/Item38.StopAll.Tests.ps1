# Пункт 38: «Стоп» останавливает всё сразу; пункт 39: режим без мыши (порты).
BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1'); $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {} }
Describe 'Item38 Стоп — полная остановка' -Tag 'Item38' {
  BeforeEach { $script:Paused=$false; $script:Busy=$false; $script:AbortOnStop=$false; $script:GGWorker=$false }
  AfterEach { $script:Paused=$false; $script:Busy=$false }
  It 'Assert-Running бросает paused на стопе' {
    $script:Paused=$true
    { Assert-Running 'x' } | Should -Throw -ExceptionType ([GG.RelayPausedException])
  }
  It 'в воркере файл PAUSE останавливает сразу, ещё до Pump' {
    $f=Join-Path ([IO.Path]::GetTempPath()) "ggpause_$PID"; $old=$Cfg.PauseFile; $Cfg.PauseFile=$f
    try{ New-Item -ItemType File $f -Force | Out-Null; $script:GGWorker=$true; Test-StopNow | Should -BeTrue; $script:GGWorker=$false; Test-StopNow | Should -BeFalse }
    finally{ Remove-Item $f -EA 0; $Cfg.PauseFile=$old; $script:GGWorker=$false }
  }
  It 'клавиши, клик, буфер, UIA и CDP на стопе не выполняются' {
    $script:Paused=$true
    { KeyDown 0x41 } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    { ClickAt 1 1 } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    { Uia-Invoke 'el' } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    { Uia-ClickEl 'el' } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    { Invoke-Cdp -Method 'Runtime.evaluate' -Conn @{nextId=0} } | Should -Throw -ExceptionType ([GG.RelayPausedException])
    { Wait-Until { $false } 1 } | Should -Throw -ExceptionType ([GG.RelayPausedException])
  }
  It 'Pump на стопе прерывает текущее действие' {
    Mock Poll-Tg {}; Mock Sweep-TgPrompts {}; Mock Check-Shutdown {}; Mock Read-CmdFile {}; Mock Check-LocalControl {}; Mock Write-Status {}
    $script:Paused=$true; $script:Busy=$true
    { Pump } | Should -Throw -ExceptionType ([GG.RelayPausedException])
  }
  It 'Pump на стопе в простое: ни автоподтверждения, ни Accept all, ни ответа Antigravity' {
    Mock Poll-Tg {}; Mock Sweep-TgPrompts {}; Mock Check-Shutdown {}; Mock Read-CmdFile {}; Mock Check-LocalControl {}; Mock Write-Status {}
    Mock Invoke-AutoAllowTick {}; Mock Invoke-AuxDuringWait {}; Mock Check-AgWatch {}
    $script:Paused=$true; Pump
    Should -Invoke Invoke-AutoAllowTick -Times 0; Should -Invoke Invoke-AuxDuringWait -Times 0; Should -Invoke Check-AgWatch -Times 0
  }
  It 'автоподтверждение, звук и ответ Antigravity сами проверяют стоп' {
    $Cfg.AutoAllowPrompts=$true; Mock Try-AutoAllow { $true }; Mock Invoke-Beep {}
    $script:Paused=$true; Invoke-AutoAllowTick; Should -Invoke Try-AutoAllow -Times 0
    Play-Sound 'info' | Should -BeFalse; Should -Invoke Invoke-Beep -Times 0
    $script:AgWatch=@{ since=(Get-Date); until=(Get-Date).AddMinutes(1); known=@() }; Mock Get-Files { throw 'не должно вызываться' }
    { Check-AgWatch } | Should -Not -Throw; $script:AgWatch=$null
  }
  It 'основной шаг на стопе не трогает лимиты, наблюдатель, файлы' {
    Mock Pump {}; Mock Invoke-StoppedStep {}; Mock Check-Quotas {}; Mock Invoke-MirrorGemini {}; Mock Next-File {}; Mock Check-Blocking {}
    $script:Paused=$true; Invoke-MainStep | Should -Be 'ok'
    Should -Invoke Check-Quotas -Times 0; Should -Invoke Invoke-MirrorGemini -Times 0; Should -Invoke Next-File -Times 0; Should -Invoke Check-Blocking -Times 0
  }
  It 'панель показывает «Остановлен — ничего не делаю»' { (Get-GuiStateView @{ kind='paused'; state='x' }).State | Should -Match 'Остановлен — ничего не делаю' }
}
Describe 'Item39 Режим без мыши' -Tag 'Item39' {
  It 'закрытый порт — серый, открытый — зелёный' {
    Test-PortUp 1 100 | Should -BeFalse
    (Get-PortView $false 'Gemini' 9222).Color | Should -Be 'Gray'; (Get-PortView $true 'Gemini' 9222).Color | Should -Be 'ForestGreen'
  }
  It 'аргументы Chrome: порт, отдельный профиль, Gemini' {
    $a=Get-GeminiChromeArgs 9222 'C:\p'; ($a -join ' ') | Should -Match '--remote-debugging-port=9222'; ($a -join ' ') | Should -Match 'user-data-dir="C:\\p"'; $a | Should -Contain 'https://gemini.google.com/app'
  }
  It 'аргументы Antigravity: порт 9333' { (Get-AgDebugArgs 9333) | Should -Contain '--remote-debugging-port=9333' }
  It 'Antigravity не закрылся — не запускаю второй' {
    Mock Get-AgExe { 'ag.exe' }; Mock Test-PortUp { $false }; $script:started=$false
    $r=Restart-AgCdp -Port 9333 -WaitSec 1 -GetProcs { @([pscustomobject]@{ MainWindowHandle=[IntPtr]::Zero }) } -Starter { $script:started=$true }
    $r | Should -Match 'не закрылся'; $script:started | Should -BeFalse
  }
  It 'Antigravity закрыт — запускаю с портом' {
    Mock Get-AgExe { 'ag.exe' }; Mock Test-PortUp { $false }; $script:sa=$null
    $r=Restart-AgCdp -Port 9333 -WaitSec 1 -GetProcs { @() } -Starter { param($e,$a) $script:sa=$a }
    $script:sa | Should -Contain '--remote-debugging-port=9333'; $r | Should -Match 'Open in current window'
  }
  It 'кнопка панели сбрасывает ожидание CDP' {
    $script:CdpDownUntil=(Get-Date).AddMinutes(5); $script:AgCdpDownUntil=(Get-Date).AddMinutes(5)
    Invoke-PcButton 'cdpcheck' ''; $script:CdpDownUntil | Should -BeNullOrEmpty; $script:AgCdpDownUntil | Should -BeNullOrEmpty
  }
}
