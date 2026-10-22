BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function N([int]$i){ 'MyProject_2026-10-18_{0:D3}.md' -f $i }
  function New-Rep([int]$i,[datetime]$t){ $p=Join-Path $Cfg.Downloads (N $i); [IO.File]::WriteAllText($p,"отчёт $i"); $gi=Get-Item $p; $gi.CreationTime=$t; $gi.LastWriteTime=$t; $p }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
  function Press($p,[string]$choice){ Handle-Callback "p:$($p.id):$choice" 'cb' $p.msgId }
  function PromptOf([string]$k){ @($script:TgPrompts.Values | Where-Object kind -eq $k) | Select-Object -Last 1 }
  function StartText{ $s=Sent '*процедура запуска*'; if($s.Count){ [string]$s[-1].b.text } else { '' } }
  function Set-Files{
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $script:St=New-RelayState; $t0=[datetime]'2026-10-18 09:00'
    foreach($i in 1..7){ [void](New-Rep $i $t0.AddMinutes(30*$i)) }
    foreach($i in 1,2){ [void](Set-FileStage -State $script:St -Name (N $i) -Stage 'relayed' -Force) }
  }
  function Use-Base{
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100
    $script:TgPrompts.Clear(); $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:Held=@{}; $script:Adopted=@{}
    $script:TriageNeeded=$true; $script:PausedSince=$null; $script:LastStartReport=''; $script:StopAnnounced=$false; $script:AbortOnStop=$false
    $script:NeedStart=$true; $script:StopReq=$false; $script:LimitStop=$false; $script:QStopG=$false; $script:QStopA=$false; $script:Q=$null; $script:AutoPlan=$null
    $Cfg.StartupNewestOnly=$true; $Cfg.StartupAskNewest=$true; $Cfg.StartupTriagePauseMin=0; $Cfg.QuotaEveryMin=0; $Cfg.IgnoreBefore=''; $Cfg.TgReplyKeyboard=$true
    $Cfg.AutoSwitchModel=$true; $Cfg.CodeBlockLang='Markdown'; $Cfg.CodeBlockPick='last'; $Cfg.CodeFromWholeFallback=$false
    $Cfg.StateJson=(Join-Path $TestDrive 'relay_state.json'); $Cfg.PauseFile=(Join-Path $TestDrive 'PAUSE'); $Cfg.StopFile=(Join-Path $TestDrive 'STOP'); $Cfg.CmdFile=(Join-Path $TestDrive 'commands.txt')
    Remove-Item $Cfg.PauseFile,$Cfg.StopFile -EA 0
    $script:GemSent=New-Object System.Collections.ArrayList; $script:AgSent=New-Object System.Collections.ArrayList
    $script:LP=$null; $script:PK=$null; $script:InAg=$false; $script:Model='Argon Ultra'
  }
}

Describe 'Пункт 53: протокол запуска по выбранной IDE' -Tag Item53 {
  BeforeEach {
    Use-Base; Set-Files
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Gem-IsReady { $true }; Mock Ag-GetWindow { [IntPtr]1 }; Mock AgUia-FindInput { $true }
    Mock Get-ModelNow { $script:LastModel=$script:Model; $script:Model }
    Mock Switch-ToArgon { $script:Model='Argon Ultra'; 'Argon Ultra' }
    Mock Check-Quotas { $script:Q=@{ time='08:50' }; 'ok' }; Mock Quota-Text { 'в норме' }; Mock Update-AutoPlan {}
    Mock Gem-IsGenerating { $false }; Mock Get-AgHealth { @{ ok=$true; kind='ok'; reasons=@() } }; Mock Find-QueuedItems { @() }
    Mock Gem-LastReportPrompt { $script:LP }; Mock Gem-PeekAnswer { $script:PK }; Mock Ag-HasText { $script:InAg }
    Mock Gem-Send { [void]$script:GemSent.Add($Text); @{ pBefore=1 } }; Mock Gem-SendFile { [void]$script:GemSent.Add($Name); @{ pBefore=1 } }; Mock Ag-Send { [void]$script:AgSent.Add($Text) }
  }
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'Harness без порта — «DeepSeek Harness НЕТ», окно Antigravity не ищу' {
    $Cfg.AgTarget='dsharness'; Mock Connect-DshCdp { throw 'порт 9334 не отвечает' }
    Start-Procedure | Should -BeFalse
    $t=StartText; $t | Should -Match 'DeepSeek Harness НЕТ'; $t | Should -Match 'жду окна Gemini и DeepSeek Harness'; $t | Should -Not -Match 'Antigravity'
    Should -Invoke Ag-GetWindow -Times 0; Should -Invoke Get-AgHealth -Times 0
  }
  It 'Harness с портом — протокол идёт дальше без проверок окна Antigravity' {
    $Cfg.AgTarget='dsharness'; Mock Connect-DshCdp { @{ title='Сессия — DeepSeek Harness' } }; Mock DshCdp-IsBusy { $false }
    Start-Procedure | Out-Null
    $t=StartText; $t | Should -Match 'DeepSeek Harness есть'; $t | Should -Match 'связь по порту 9334'
    Should -Invoke Ag-GetWindow -Times 0; Should -Invoke Get-AgHealth -Times 0; Should -Invoke Find-QueuedItems -Times 0
  }
  It 'Antigravity — как раньше' {
    Mock Ag-GetWindow { $null }; Start-Procedure | Should -BeFalse; StartText | Should -Match 'Antigravity НЕТ'
  }
  It 'текст блокировки — по имени IDE' {
    $Cfg.AgTarget='dsharness'; Get-AgBlockText @{ kind='foreign'; detail='x'; file='' } | Should -Match 'DeepSeek Harness'
  }
}
