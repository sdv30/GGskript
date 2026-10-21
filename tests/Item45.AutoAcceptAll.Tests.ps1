BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 45: настройка и команды автопринятия' -Tag Item45 {
  It 'по умолчанию включено' { (Get-DefaultSettings -Root $TestDrive).AutoAcceptAll | Should -BeTrue }
  It 'Parse-Command: вкл / выкл / состояние' {
    (Parse-Command 'автопринятие вкл').k | Should -Be 'autoaccept'; (Parse-Command 'автопринятие вкл').on | Should -BeTrue
    (Parse-Command 'автопринятие выкл').on | Should -BeFalse; (Parse-Command '/autoaccept off').on | Should -BeFalse
    $c=Parse-Command 'автопринятие'; $c.k | Should -Be 'autoaccept'; $c.on | Should -BeNullOrEmpty
  }
  It 'Set-AutoAccept сохраняет в relay_settings.json' {
    Mock Log {}; Mock Tg-Send { $true }; Mock Write-Status {}; Mock Save-SettingValue {}
    Set-AutoAccept $false 'pc'; $Cfg.AutoAcceptAll | Should -BeFalse
    Should -Invoke Save-SettingValue -ParameterFilter { $Key -eq 'AutoAcceptAll' -and $Value -eq $false }
    $Cfg.AutoAcceptAll=$true
  }
}
Describe 'Пункт 45: Try-AcceptAll через CDP (span, не Button)' -Tag Item45 {
  BeforeEach {
    $script:Paused=$false; $Cfg.AgTransport='cdp'; $Cfg.GitCheckpointRepo=''; $Cfg.GitCheckpointRequired=$false
    Mock Log {}; Mock Tg-Send { $true }; Mock Ag-GetWindow { 42 }; Mock Find-AcceptAll { $null }; Mock Uia-ClickEl { $true }; Mock Test-StopNow { $false }
  }
  AfterAll { $Cfg.AgTransport='uia' }
  It 'кнопка есть, агент не работает — жмёт через CDP, UIA не нужен, лог с числом файлов' {
    Mock AgCdp-AcceptAll { if($Dry){ @{found=$true;ok=$false;busy=$false;files=6} } else { @{found=$true;ok=$true;busy=$false;files=6} } }
    Try-AcceptAll -Report | Should -BeTrue
    Should -Invoke AgCdp-AcceptAll -Times 1 -ParameterFilter { -not $Dry }
    Should -Invoke Log -ParameterFilter { $m -eq '✅ Accept all нажат (6 files) (CDP, без фокуса)' }
    Should -Invoke Uia-ClickEl -Times 0
  }
  It 'агент ещё работает — не жмёт' {
    Mock AgCdp-AcceptAll { @{found=$true;ok=$false;busy=$true;files=6} }
    Try-AcceptAll | Should -BeFalse; Should -Invoke AgCdp-AcceptAll -Times 0 -ParameterFilter { -not $Dry }
  }
  It 'кнопки нет — не жмёт и не падает в UIA/фокус' {
    Mock AgCdp-AcceptAll { @{found=$false;busy=$false;files=0} }; Mock Invoke-WithFocus {}
    Try-AcceptAll | Should -BeFalse; Should -Invoke Invoke-WithFocus -Times 0
  }
  It 'Стоп — не жмёт' { $script:Paused=$true; Mock AgCdp-AcceptAll { @{found=$true;ok=$true} }; Try-AcceptAll | Should -BeFalse; Should -Invoke AgCdp-AcceptAll -Times 0 }
}
Describe 'Пункт 45: Invoke-AutoAcceptTick' -Tag Item45 {
  BeforeEach { $script:Paused=$false; $Cfg.AgTransport='cdp'; $Cfg.AutoAcceptAll=$true; $Cfg.AcceptAllEverySec=12; $script:FocusDepth=0; $script:AgBlock=$null; $script:InAutoAccept=$false; $script:LastAutoAccept=[datetime]::MinValue; Mock Try-AcceptAll { $true }; Mock Log {} }
  AfterAll { $Cfg.AgTransport='uia' }
  It 'вкл + CDP — жмёт' { Mock Test-StopNow { $false }; Invoke-AutoAcceptTick; Should -Invoke Try-AcceptAll -Times 1 }
  It 'выкл — не жмёт' { Mock Test-StopNow { $false }; $Cfg.AutoAcceptAll=$false; Invoke-AutoAcceptTick; Should -Invoke Try-AcceptAll -Times 0 }
  It 'без CDP — не трогает окно' { Mock Test-StopNow { $false }; $Cfg.AgTransport='uia'; Invoke-AutoAcceptTick; Should -Invoke Try-AcceptAll -Times 0 }
  It 'на Стопе — не жмёт' { Mock Test-StopNow { $true }; Invoke-AutoAcceptTick; Should -Invoke Try-AcceptAll -Times 0 }
  It 'не чаще AcceptAllEverySec' { Mock Test-StopNow { $false }; Invoke-AutoAcceptTick; Invoke-AutoAcceptTick; Should -Invoke Try-AcceptAll -Times 1 }
}
Describe 'Пункт 45: CDP — «Accept all» в DOM (headless Chromium, fake_antigravity_accept.html)' -Tag Item45,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $fx=Join-Path $PSScriptRoot 'fixtures'; $Cfg.AgCdpPort=9349
      $script:pc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.AgCdpPort)","--user-data-dir=$(Join-Path $TestDrive 'pc45')",('file://'+(Join-Path $fx 'fake_antigravity_accept.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'pc45.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort | Where-Object { $_.url -like '*fake_antigravity_accept*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:AgCdpConn=$null
    function Ag-Js([string]$e){ (Invoke-Cdp 'Runtime.evaluate' @{ expression=$e; returnByValue=$true } -Conn (Connect-AgCdp)).result.value }
  }
  AfterAll { if($script:AgCdpConn){ Cdp-Close $script:AgCdpConn; $script:AgCdpConn=$null }; if($script:pc){ try{ Get-Process -Id $script:pc.Id -EA 0 | Stop-Process -Force }catch{} } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {}; [void](Ag-Js 'window.reset(true,false);1') }
  It 'жмёт span «Accept all», Reject all и шеврон не трогает' { $r=AgCdp-AcceptAll; $r.ok | Should -BeTrue; $r.files | Should -Be 6; Ag-Js 'window.__acc' | Should -Be 1; Ag-Js 'window.__rej+window.__chev' | Should -Be 0 }
  It 'агент работает — не жмёт' { [void](Ag-Js 'window.reset(true,true);1'); $r=AgCdp-AcceptAll; $r.busy | Should -BeTrue; Ag-Js 'window.__acc' | Should -Be 0 }
  It '-Dry — только смотрит' { (AgCdp-AcceptAll -Dry).found | Should -BeTrue; Ag-Js 'window.__acc' | Should -Be 0 }
  It 'нет панели — found=false' { [void](Ag-Js 'window.reset(false,false);1'); (AgCdp-AcceptAll).found | Should -BeFalse }
}
