BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 55: IDE Cursor — настройки и команды' -Tag Item55 {
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'по умолчанию порт Cursor 9335, AgTarget=cursor принимается' {
    $d=Get-DefaultSettings -Root $TestDrive; $d.CursorCdpPort | Should -Be 9335
    $p=Join-Path $TestDrive 'rs55.json'; '{"AgTarget":"cursor"}' | Set-Content $p -Encoding UTF8
    (Merge-Settings -Defaults (Get-DefaultSettings -Root $TestDrive) -OverridePath $p).Cfg.AgTarget | Should -Be 'cursor'
  }
  It 'Parse-Command: ide cursor / иде курсор' {
    (Parse-Command 'ide cursor').v | Should -Be 'cursor'; (Parse-Command '/ide cursor').v | Should -Be 'cursor'; (Parse-Command 'иде курсор').v | Should -Be 'cursor'
    (Parse-Command 'ide dsharness').v | Should -Be 'dsharness'
  }
  It 'имена/порт: Cursor идёт CDP-путём Harness, но со своим именем и портом' {
    $Cfg.AgTarget='cursor'; Test-IsDsh | Should -BeTrue; Test-IsCursor | Should -BeTrue
    Get-IdeName | Should -Be 'Cursor'; Get-IdePort | Should -Be 9335; Get-DshPort | Should -Be 9335
    $Cfg.AgTarget='dsharness'; Test-IsCursor | Should -BeFalse; Get-IdeName | Should -Be 'DeepSeek Harness'; Get-DshPort | Should -Be ([int]$Cfg.DshCdpPort)
    $Cfg.AgTarget='antigravity'; Test-IsDsh | Should -BeFalse; Get-IdeName | Should -Be 'Antigravity'
  }
  It 'селекторы: для Cursor — свои (prompt-input, Stop generation), переопределяются CursorCdpSelectors' {
    $Cfg.AgTarget='cursor'; $s=Get-DshCdpSelectors
    $s.input | Should -Match 'ui-prompt-input-editor'; $s.busy | Should -Match 'Stop generation'; $s.send | Should -Match 'Send message'; $s.answer | Should -Match 'data-message-role="ai"'; $s.ctx | Should -Match 'Context '; $s.send | Should -Match 'button\[aria-label="Send message"\]'
    $Cfg.CursorCdpSelectors=@{ input='#x' }; (Get-DshCdpSelectors).input | Should -Be '#x'; $Cfg.CursorCdpSelectors=@{}
    $Cfg.AgTarget='dsharness'; (Get-DshCdpSelectors).input | Should -Match 'data-composer-input'
  }
  It 'автоподтверждение Cursor: Run/Allow — да; Skip/always/Allowlist — нет' {
    foreach($ok in 'Run','Allow'){ $ok | Should -Match $Cfg.CursorAllowOptionRx }
    foreach($no in 'Skip','Always allow','Add to allowlist','Run always','Reject'){ $no | Should -Not -Match $Cfg.CursorAllowOptionRx }
  }
  It 'JS: Skip/allowlist в стоп-списке, Keep all считается «принять все»' {
    $script:DshJs | Should -Match 'skip\|'; $script:DshJs | Should -Match 'allowlist'; $script:DshJs | Should -Match 'keep all'
  }
}
Describe 'Пункт 55: отправка/принятие через выбранную IDE Cursor' -Tag Item55 {
  BeforeEach { Mock Log {}; Mock Tg-Send { $true }; Mock Test-StopNow { $false }; $script:Paused=$false; $Cfg.GitCheckpointRepo=''; $Cfg.GitCheckpointRequired=$false }
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'cursor: Ag-SendCore → DshCdp-Send, UIA/AgCdp не трогаются' {
    $Cfg.AgTarget='cursor'; Mock DshCdp-Send {}; Mock AgUia-Send {}; Mock AgCdp-Send {}
    Ag-SendCore -Text 'Тест связи' -Label 't'
    Should -Invoke DshCdp-Send -Times 1; Should -Invoke AgUia-Send -Times 0; Should -Invoke AgCdp-Send -Times 0
  }
  It 'cursor: Assert-AgReady не ищет окно Antigravity' { $Cfg.AgTarget='cursor'; Mock Get-AgHealth { throw 'нельзя' }; (Assert-AgReady).ok | Should -BeTrue }
  It 'cursor: allowPrompt берёт CursorAllowOptionRx' {
    $Cfg.AgTarget='cursor'; Mock DshEval-Js { $Arg }; (DshCdp-AllowPrompt).opt | Should -Be $Cfg.CursorAllowOptionRx
    $Cfg.AgTarget='dsharness'; (DshCdp-AllowPrompt).opt | Should -Be $Cfg.DshAllowOptionRx
  }
  It 'cursor: Set-IdeTarget при паузе — переключает' {
    Mock Write-Status {}; Mock Save-SettingValue {}; Mock Register-TgCommands {}; $script:Paused=$true
    Set-IdeTarget 'cursor' 'pc'; $Cfg.AgTarget | Should -Be 'cursor'; Should -Invoke Save-SettingValue -ParameterFilter { $Value -eq 'cursor' }
    $script:Paused=$false
  }
}
Describe 'Пункт 55: панель и Telegram для Cursor' -Tag Item55 {
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'Get-IdeTexts cursor: все надписи про Cursor, порт 9335' {
    $x=Get-IdeTexts 'cursor' 9333 9334 9335
    $x.Fwd | Should -Be '📂 Ответ в Cursor'; $x.AgT | Should -Be '🛠 Cursor: текст'; $x.Cdp | Should -Be '🛠 Cursor с портом'; $x.Port | Should -Be 9335; $x.MenuHead | Should -Be 'CURSOR'
    foreach($k in @($x.Keys)){ if($k -ne 'TileTip'){ [string]$x[$k] | Should -Not -Match 'Antigravity|Harness' } }
    $x.TileTip | Should -Match 'Cursor'
  }
  It 'выбор IDE в панели содержит Cursor' { @(Get-IdeChoices).v | Should -Contain 'cursor' }
  It 'Telegram: клавиатура переименована в Cursor' {
    $Cfg.AgTarget='cursor'; $l=Get-TgReplyLabels; $l | Should -Contain '📂 Ответ в Cursor'; ($l -join '|') | Should -Not -Match 'Antigravity'
    (Parse-Command '🛠 Cursor: текст').k | Should -Be 'agwrite'; (Parse-Command '📂 Ответ в Cursor').k | Should -Be 'fwdans'
  }
  It 'лимиты на панели: Cursor — «квота не публикуется»' {
    Format-GuiLimits ([pscustomobject]@{ ide='cursor'; ideName='Cursor'; agH5=100 }) | Should -Match 'Cursor: квота не публикуется'
  }
  It 'Restart-CursorCdp: порт уже открыт — ничего не трогает' {
    Mock Test-PortUp { $true }; $k=0
    Restart-CursorCdp 9335 -Killer { $script:k55++ } | Should -Match 'уже с портом 9335'
  }
  It 'Restart-CursorCdp: закрывает процессы и запускает с --remote-debugging-port' {
    Mock Test-PortUp { $false }; Mock Get-CursorExe { 'C:\c\Cursor.exe' }; Mock Start-Sleep {}
    $script:procs=@([pscustomobject]@{ Id=1; MainWindowHandle=[IntPtr]::Zero }); $script:started=$null
    $r=Restart-CursorCdp 9335 -WaitSec 0 -GetProcs { $script:procs } -Killer { param($p) $script:procs=@() } -Starter { param($e,$a) $script:started=@($e)+$a }
    $r | Should -Match 'Перезапустил Cursor с портом 9335'; $script:started | Should -Contain '--remote-debugging-port=9335'
  }
}
Describe 'Пункт 55: первая строка журнала' -Tag Item55 {
  It 'строка запуска не пишет жёстко «Antigravity=»' {
    $src=Get-Content (Join-Path $PSScriptRoot '../GGskript.ps1') -Encoding UTF8 | Where-Object { $_ -match 'GGskript v2 запущен' }
    $src | Should -Not -Match 'Antigravity='; $src | Should -Match 'Get-IdeName'
  }
}
