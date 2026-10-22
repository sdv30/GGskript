BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 51: настройка AgTarget и команда ide' -Tag Item51 {
  It 'по умолчанию antigravity, порт Harness 9334' { $d=Get-DefaultSettings -Root $TestDrive; $d.AgTarget | Should -Be 'antigravity'; $d.DshCdpPort | Should -Be 9334 }
  It 'неизвестное значение — откат на antigravity' {
    $p=Join-Path $TestDrive 'rs.json'; '{"AgTarget":"vscode"}' | Set-Content $p -Encoding UTF8
    $m=Merge-Settings -Defaults (Get-DefaultSettings -Root $TestDrive) -OverridePath $p; $m.Cfg.AgTarget | Should -Be 'antigravity'
    '{"AgTarget":"dsharness"}' | Set-Content $p -Encoding UTF8
    (Merge-Settings -Defaults (Get-DefaultSettings -Root $TestDrive) -OverridePath $p).Cfg.AgTarget | Should -Be 'dsharness'
  }
  It 'Parse-Command: ide …' {
    (Parse-Command 'ide dsharness').v | Should -Be 'dsharness'; (Parse-Command '/ide antigravity').v | Should -Be 'antigravity'
    (Parse-Command 'иде харнес').v | Should -Be 'dsharness'; $c=Parse-Command 'ide'; $c.k | Should -Be 'ide'; $c.v | Should -BeNullOrEmpty
  }
  It 'автоподтверждение Harness: «один раз» да, «всегда»/«запретить» нет' {
    'Разрешить' | Should -Match $Cfg.DshAllowOptionRx; 'Allow once' | Should -Match $Cfg.DshAllowOptionRx
    'Разрешить всегда' | Should -Not -Match $Cfg.DshAllowOptionRx; 'Always allow' | Should -Not -Match $Cfg.DshAllowOptionRx; 'Запретить' | Should -Not -Match $Cfg.DshAllowOptionRx
  }
}
Describe 'Пункт 51: Set-IdeTarget — только при Стоп' -Tag Item51 {
  BeforeEach { Mock Log {}; Mock Tg-Send { $true }; Mock Write-Status {}; Mock Save-SettingValue {}; $Cfg.AgTarget='antigravity' }
  AfterAll { $Cfg.AgTarget='antigravity'; $script:Paused=$false }
  It 'не на паузе — не меняет' { $script:Paused=$false; Set-IdeTarget 'dsharness' 'pc'; $Cfg.AgTarget | Should -Be 'antigravity'; Should -Invoke Save-SettingValue -Times 0 }
  It 'на паузе — меняет и сохраняет' { $script:Paused=$true; Set-IdeTarget 'dsharness' 'pc'; $Cfg.AgTarget | Should -Be 'dsharness'; Should -Invoke Save-SettingValue -ParameterFilter { $Key -eq 'AgTarget' -and $Value -eq 'dsharness' } }
}
Describe 'Пункт 51: маршрутизация через выбранную IDE' -Tag Item51 {
  BeforeEach { Mock Log {}; Mock Tg-Send { $true }; Mock Test-StopNow { $false }; $script:Paused=$false; $Cfg.GitCheckpointRepo=''; $Cfg.GitCheckpointRequired=$false }
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'dsharness: Ag-SendCore → DshCdp-Send, UIA/AgCdp не трогает' {
    $Cfg.AgTarget='dsharness'; Mock DshCdp-Send {}; Mock AgUia-Send {}; Mock AgCdp-Send {}
    Ag-SendCore -Text 'привет агенту' -Label 't'
    Should -Invoke DshCdp-Send -Times 1; Should -Invoke AgUia-Send -Times 0; Should -Invoke AgCdp-Send -Times 0
  }
  It 'antigravity: прежний путь (UIA), Harness не трогает' {
    $Cfg.AgTarget='antigravity'; $Cfg.AgTransport='uia'; Mock DshCdp-Send {}; Mock AgUia-Send {}
    Ag-SendCore -Text 'привет' -Label 't'; Should -Invoke AgUia-Send -Times 1; Should -Invoke DshCdp-Send -Times 0
  }
  It 'dsharness: Assert-AgReady не ищет окно Antigravity' { $Cfg.AgTarget='dsharness'; Mock Get-AgHealth { throw 'нельзя' }; (Assert-AgReady).ok | Should -BeTrue }
  It 'dsharness: Get-AgQuota — 100% (квота не публикуется), без RPC Antigravity' {
    $Cfg.AgTarget='dsharness'; Mock Ag-Rpc { throw 'нельзя' }; Mock Get-DshLimit { @{ rate=$false; ctx=1 } }
    $q=Get-AgQuota; $q.h5.rem | Should -Be 100; $q.wk.rem | Should -Be 100
  }
  It 'dsharness: 429 → предупреждение в Telegram, но не стоп' {
    $Cfg.AgTarget='dsharness'; Mock Get-DshLimit { @{ rate=$true; error='429 RATE_LIMIT' } }
    $q=Get-AgQuota; $q.h5.rem | Should -Be 100; Should -Invoke Tg-Send -Times 1
  }
  It 'dsharness: Try-AcceptAll жмёт через DOM Harness, когда агент не работает' {
    $Cfg.AgTarget='dsharness'; Mock Ag-GetWindow { throw 'нельзя' }
    Mock DshCdp-AcceptAll { if($Dry){ @{found=$true;ok=$false;busy=$false} } else { @{found=$true;ok=$true} } }
    Try-AcceptAll | Should -BeTrue; Should -Invoke DshCdp-AcceptAll -Times 1 -ParameterFilter { -not $Dry }
  }
  It 'dsharness: агент работает — не жмёт' {
    $Cfg.AgTarget='dsharness'; Mock DshCdp-AcceptAll { @{found=$true;ok=$false;busy=$true} }
    Try-AcceptAll | Should -BeFalse; Should -Invoke DshCdp-AcceptAll -Times 0 -ParameterFilter { -not $Dry }
  }
  It 'dsharness: Try-AutoAllow — только DshCdp-AllowPrompt' {
    $Cfg.AgTarget='dsharness'; $Cfg.AutoAllowPrompts=$true; Mock DshCdp-AllowPrompt { @{found=$true;ok=$true;opt='Разрешить'} }; Mock AgCdp-AllowPrompt {}; Mock Ag-GetWindow { throw 'нельзя' }
    Try-AutoAllow | Should -BeTrue; Should -Invoke AgCdp-AllowPrompt -Times 0
  }
  It 'dsharness: Check-AgQueue ничего не делает' { $Cfg.AgTarget='dsharness'; Mock Ag-GetWindow { throw 'нельзя' }; { Check-AgQueue } | Should -Not -Throw }
  It 'dsharness: Ag-HasText сверяет с текстом страницы Harness' {
    $Cfg.AgTarget='dsharness'; $t='[ARGON>FLASH] [Arena] [S012] задание для агента с достаточно длинным текстом, чтобы сверка сработала'
    Mock DshCdp-Body { "шапка`n$t`nхвост" }; Ag-HasText $t | Should -BeTrue
    Mock DshCdp-Body { 'ничего' }; Ag-HasText $t | Should -BeFalse
  }
}
Describe 'Пункт 51: DshCdp-Send — гарантии' -Tag Item51 {
  BeforeEach { Mock Log {}; $Cfg.AgFieldReads=1; Mock Connect-DshCdp { @{ ws=$null } }; Mock Invoke-Cdp { @{} }; Mock Start-Sleep {} }
  It 'агент занят — не отправляет' {
    Mock DshEval-Js { if($Op -eq 'busy'){ $true } else { '' } }
    { DshCdp-Send -Text 'x' } | Should -Throw '*Остановить генерацию*'; Should -Invoke Invoke-Cdp -Times 0 -ParameterFilter { $Method -eq 'Input.insertText' }
  }
  It 'в поле чужой текст — не трогает' {
    Mock DshEval-Js { if($Op -eq 'busy'){ $false } elseif($Op -eq 'inputText'){ 'черновик пользователя' } else { $true } }
    { DshCdp-Send -Text 'наше задание' } | Should -Throw '*чужой текст*'; Should -Invoke Invoke-Cdp -Times 0 -ParameterFilter { $Method -eq 'Input.insertText' }
  }
  It 'нормальный путь: вставка, Enter, поле опустело' {
    $script:dshField=''
    Mock DshEval-Js { if($Op -eq 'busy'){ $false } elseif($Op -eq 'inputText'){ $script:dshField } else { $true } }
    Mock Invoke-Cdp { if($Method -eq 'Input.insertText'){ $script:dshField=$Params.text }; if($Method -eq 'Input.dispatchKeyEvent'){ $script:dshField='' }; @{} }
    DshCdp-Send -Text 'Тест связи GGskript: ответь одним словом OK' -Label 'тест'
    Should -Invoke Invoke-Cdp -Times 1 -ParameterFilter { $Method -eq 'Input.insertText' }
    Should -Invoke Log -ParameterFilter { $m -like 'Отправлено в DeepSeek Harness*' }
  }
}
Describe 'Пункт 51: панель' -Tag Item51 {
  It 'Get-TurnView: подпись хода и плитки по IDE' {
    $v=Get-TurnView 'antigravity' $true 'DeepSeek Harness'; $v.Caption | Should -Be 'Ход DeepSeek Harness'; $v.Ide | Should -Be 'DeepSeek Harness'
    (Get-TurnView 'antigravity').Caption | Should -Be 'Ход Antigravity'; (Get-TurnView 'gemini' $true 'DeepSeek Harness').Caption | Should -Be 'Ход Gemini'
  }
  It 'Get-IdeChoices: два варианта' { @(Get-IdeChoices).Count | Should -Be 2; (@(Get-IdeChoices))[1].t | Should -Be 'DeepSeek Harness' }
  It 'Restart-DshCdp: закрывает, добивает остатки (трей), запускает с портом' {
    Mock Test-PortUp { $false }; Mock Get-DshExe { 'C:\h\DeepSeek Harness.exe' }; Mock Start-Sleep {}
    $script:procs=@([pscustomobject]@{ Id=1; MainWindowHandle=[IntPtr]::Zero },[pscustomobject]@{ Id=2; MainWindowHandle=[IntPtr]::Zero })
    $script:started=$null
    $r=Restart-DshCdp 9334 0 -GetProcs { $script:procs } -Killer { param($p) $script:procs=@($script:procs | Where-Object { $_.Id -ne $p.Id }) } -Starter { param($e,$a) $script:started=$a }
    $r | Should -BeLike '*с портом 9334*'; $script:started | Should -Contain '--remote-debugging-port=9334'
  }
  It 'Restart-DshCdp: порт уже есть — не перезапускает' { Mock Test-PortUp { $true }; Restart-DshCdp 9334 -Starter { throw 'нельзя' } | Should -BeLike '*уже с портом*' }
}
