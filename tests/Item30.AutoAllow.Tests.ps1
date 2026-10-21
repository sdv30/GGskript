BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 30: выбор варианта и кнопки (чистая логика)' -Tag Item30 {
  It 'по умолчанию выключено' { (Get-DefaultSettings -Root $TestDrive).AutoAllowPrompts | Should -BeFalse }
  It 'разовое разрешение — подходит (с номером и без)' {
    foreach($t in 'Yes, allow this time','1 Yes, allow this time','1Yes, allow this time','  Yes,  allow this time ','Да, разрешить в этот раз'){ Test-AutoAllowOption $t | Should -BeTrue -Because $t }
  }
  It '«always», «No» и прочее — никогда' {
    foreach($t in 'Yes, and always allow pytest in this conversation','2 Yes, and always allow pytest','Yes, allow this time and always','No (tell the agent what to do instead)','4 No','Skip','Cancel','Reject','Allow running pytest on step 1 tests?',''){ Test-AutoAllowOption $t | Should -BeFalse -Because $t }
  }
  It 'даже широкий шаблон в настройках не пропускает always/No' {
    $old=$Cfg.AutoAllowOptionRx; try{ $Cfg.AutoAllowOptionRx='.*'; Test-AutoAllowOption 'Yes, and always allow' | Should -BeFalse; Test-AutoAllowOption 'No' | Should -BeFalse; Test-AutoAllowOption 'Yes, allow this time' | Should -BeTrue } finally { $Cfg.AutoAllowOptionRx=$old }
  }
  It 'кнопка: только Submit/Подтвердить' {
    Test-AutoAllowSubmit 'Submit' | Should -BeTrue; Test-AutoAllowSubmit 'Подтвердить' | Should -BeTrue
    Test-AutoAllowSubmit "Submit $([char]0x21B5)" | Should -BeTrue; Test-AutoAllowSubmit "Submit$([char]0x21B5)" | Should -BeTrue; Test-AutoAllowSubmit 'Submit (Enter)' | Should -BeTrue; Test-AutoAllowSubmit "Continue $([char]0x21B5)" | Should -BeFalse
    foreach($t in 'Skip','Cancel (Ctrl+D)','Send message','Stop','Reject all','Отправить'){ Test-AutoAllowSubmit $t | Should -BeFalse -Because $t }
    $old=$Cfg.AutoAllowSubmitRx; try{ $Cfg.AutoAllowSubmitRx='.*'; Test-AutoAllowSubmit 'Skip' | Should -BeFalse; Test-AutoAllowSubmit 'Cancel' | Should -BeFalse } finally { $Cfg.AutoAllowSubmitRx=$old }
  }
  It 'Select-NearestBelow: ближайшая кнопка ниже варианта, выше — не берётся' {
    $o=@{T=100}; $c=@(@{el='far';rect=@{T=600}},@{el='near';rect=@{T=180}},@{el='above';rect=@{T=20}})
    (Select-NearestBelow $o $c).el | Should -Be 'near'
    Select-NearestBelow $o @(@{el='above';rect=@{T=20}}) | Should -BeNullOrEmpty
  }
}
Describe 'Пункт 30: команды и настройка' -Tag Item30 {
  It 'Parse-Command: вкл / выкл / состояние' {
    (Parse-Command 'автоподтверждение вкл').on | Should -BeTrue
    (Parse-Command 'Автоподтверждение включить').on | Should -BeTrue
    $c=Parse-Command 'автоподтверждение выкл'; $c.k | Should -Be 'autoallow'; $c.on | Should -BeFalse
    (Parse-Command '/autoallow on').on | Should -BeTrue; (Parse-Command '/autoallow off').on | Should -BeFalse
    $c=Parse-Command 'автоподтверждение'; $c.k | Should -Be 'autoallow'; $c.on | Should -BeNullOrEmpty
  }
  It 'Save-SettingValue меняет один ключ и сохраняет остальные' {
    $p=Join-Path $TestDrive 's.json'; [IO.File]::WriteAllText($p,'{"AgTransport":"cdp","_comment":"x","AgCdpSelectors":{"input":"a"}}')
    Save-SettingValue $p 'AutoAllowPrompts' $true
    $j=Get-Content $p -Raw | ConvertFrom-Json; $j.AutoAllowPrompts | Should -BeTrue; $j.AgTransport | Should -Be 'cdp'; $j._comment | Should -Be 'x'; $j.AgCdpSelectors.input | Should -Be 'a'
    (Merge-Settings -Defaults (Get-DefaultSettings -Root $TestDrive) -OverridePath $p).Cfg.AutoAllowPrompts | Should -BeTrue
    Save-SettingValue (Join-Path $TestDrive 'new.json') 'AutoAllowPrompts' $false; (Get-Content (Join-Path $TestDrive 'new.json') -Raw | ConvertFrom-Json).AutoAllowPrompts | Should -BeFalse
  }
  It 'Set-AutoAllow: меняет настройку на лету и пишет в relay_settings.json' {
    Mock Log {}; Mock Tg-Send { $true }; Mock Write-Status {}
    $Cfg.SettingsFile=Join-Path $TestDrive 'rs.json'
    Set-AutoAllow $true 'pc'; $Cfg.AutoAllowPrompts | Should -BeTrue; (Get-Content $Cfg.SettingsFile -Raw | ConvertFrom-Json).AutoAllowPrompts | Should -BeTrue
    Set-AutoAllow $false 'tg'; $Cfg.AutoAllowPrompts | Should -BeFalse
  }
}
Describe 'Пункт 30: Try-AutoAllow / Invoke-AutoAllowTick' -Tag Item30 {
  BeforeEach { Mock Log {}; $Cfg.AutoAllowPrompts=$true; $Cfg.AgTransport='uia'; $script:FocusDepth=0; $script:AgBlock=$null; $script:InAutoAllow=$false; $script:LastAutoAllow=(Get-Date).AddMinutes(-1); Mock Ag-GetWindow { 42 } }
  It 'выключено — ничего не ищет' { $Cfg.AutoAllowPrompts=$false; Mock AgUia-AllowPrompt { @{found=$false} }; Try-AutoAllow | Should -BeFalse; Should -Invoke AgUia-AllowPrompt -Times 0 }
  It 'UIA подтвердил — $true и строка в лог' { Mock AgUia-AllowPrompt { @{found=$true;ok=$true;opt='Yes, allow this time'} }; Try-AutoAllow | Should -BeTrue; Should -Invoke Log -ParameterFilter { $m -like 'Автоподтверждение:*Yes, allow this time*' } }
  It 'CDP подтвердил — UIA не трогается' { $Cfg.AgTransport='cdp'; Mock AgCdp-AllowPrompt { @{found=$true;ok=$true;opt='Yes, allow this time'} }; Mock AgUia-AllowPrompt { @{found=$false} }; Try-AutoAllow | Should -BeTrue; Should -Invoke AgUia-AllowPrompt -Times 0 }
  It 'CDP недоступен — откат на UIA' { $Cfg.AgTransport='cdp'; Mock AgCdp-AllowPrompt { throw 'порт 9333 не отвечает' }; Mock AgUia-AllowPrompt { @{found=$true;ok=$true;opt='x'} }; Try-AutoAllow | Should -BeTrue }
  It 'виден, но не подтвердил — одно предупреждение в лог, без спама' { $script:AutoAllowWarn=@{key='';time=[datetime]::MinValue}; Mock AgUia-AllowPrompt { @{found=$true;ok=$false;why='нет Invoke'} }; Try-AutoAllow | Should -BeFalse; Try-AutoAllow | Should -BeFalse; Should -Invoke Log -Times 1 -Exactly }
  It 'тик: не чаще AutoAllowEverySec, не внутри фокуса, не к зависшему окну' {
    Mock Try-AutoAllow { $true }
    Invoke-AutoAllowTick; Invoke-AutoAllowTick; Should -Invoke Try-AutoAllow -Times 1 -Exactly
    $script:LastAutoAllow=(Get-Date).AddMinutes(-1); $script:FocusDepth=1; Invoke-AutoAllowTick; $script:FocusDepth=0
    $script:AgBlock=@{kind='hung'}; Invoke-AutoAllowTick; Should -Invoke Try-AutoAllow -Times 1 -Exactly
  }
  It 'тик: ошибка не вылетает наружу' { Mock Try-AutoAllow { throw 'UIA упал' }; { Invoke-AutoAllowTick } | Should -Not -Throw; $script:InAutoAllow | Should -BeFalse }
}
Describe 'Пункт 30: AgUia-AllowPrompt (без мыши и фокуса)' -Tag Item30 {
  BeforeEach {
    Mock Uia-IsOffscreen { $false }; Mock Uia-IsEnabled { $true }; Mock Uia-Rect { @{T=100;L=0;R=10;B=110} }; Mock Start-Sleep {}
    Mock Uia-FindAll { if($ControlType -eq 'Button'){ @('SUBMIT','SKIP') } else { @('OPT1','OPT2') } }
    Mock Uia-Name { switch($el){ 'SUBMIT'{'Submit'} 'SKIP'{'Skip'} 'OPT1'{'Yes, allow this time'} 'OPT2'{'Yes, and always allow pytest'} default{''} } }
    Mock Uia-Select { $true }; Mock Uia-IsSelected { $true }; Mock Uia-Invoke { $true }; Mock Uia-ClickEl { throw 'мышь запрещена' }; Mock ClickAt { throw 'мышь запрещена' }
  }
  It 'выбирает «Yes, allow this time» и жмёт Submit через Invoke' {
    $r=AgUia-AllowPrompt 42; $r.ok | Should -BeTrue; $r.opt | Should -Be 'Yes, allow this time'
    Should -Invoke Uia-Select -Times 1 -Exactly -ParameterFilter { $el -eq 'OPT1' }
    Should -Invoke Uia-Invoke -Times 1 -Exactly -ParameterFilter { $el -eq 'SUBMIT' }
    Should -Invoke Uia-Invoke -Times 0 -ParameterFilter { $el -eq 'SKIP' -or $el -eq 'OPT2' }
  }
  It 'нет Submit — запрос не считается найденным, ничего не нажимает' { Mock Uia-FindAll { if($ControlType -eq 'Button'){ @('SKIP') } else { @('OPT1') } }; (AgUia-AllowPrompt 42).found | Should -BeFalse; Should -Invoke Uia-Select -Times 0; Should -Invoke Uia-Invoke -Times 0 }
  It 'есть только «always» — ничего не выбирает' { Mock Uia-FindAll { if($ControlType -eq 'Button'){ @('SUBMIT') } else { @('OPT2') } }; $r=AgUia-AllowPrompt 42; $r.ok | Should -BeFalse; $r.why | Should -Match 'варианта'; Should -Invoke Uia-Invoke -Times 0; Should -Invoke Uia-Select -Times 0 }
  It 'вариант не выбирается без фокуса — Submit НЕ нажимается' { Mock Uia-Select { $false }; Mock Uia-Invoke { $false }; Mock Uia-Parent { $null }; $r=AgUia-AllowPrompt 42; $r.ok | Should -BeFalse; $r.found | Should -BeTrue }
}
Describe 'Пункт 30: CDP — запрос разрешения в DOM (headless Chromium, fake_antigravity_allow.html)' -Tag Item30,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $fx=Join-Path $PSScriptRoot 'fixtures'; $Cfg.AgCdpPort=9348
      $script:pc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.AgCdpPort)","--user-data-dir=$(Join-Path $TestDrive 'pc30')",('file://'+(Join-Path $fx 'fake_antigravity_allow.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'pc30.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort | Where-Object { $_.url -like '*fake_antigravity_allow*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:AgCdpConn=$null
    function Ag-Js([string]$e){ (Invoke-Cdp 'Runtime.evaluate' @{ expression=$e; returnByValue=$true } -Conn (Connect-AgCdp)).result.value }
  }
  AfterAll { if($script:AgCdpConn){ Cdp-Close $script:AgCdpConn; $script:AgCdpConn=$null }; if($script:pc){ try{ Get-Process -Id $script:pc.Id -EA 0 | Stop-Process -Force }catch{} } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {}; [void](Ag-Js 'window.reset(true);1') }
  It 'выбирает вариант 1 и жмёт Submit; Skip не трогает' {
    $r=AgCdp-AllowPrompt; $r.ok | Should -BeTrue; $r.title | Should -Match 'Allow running pytest'
    Ag-Js 'JSON.stringify(window.__submitted)' | Should -Be '["1"]'; Ag-Js 'window.__skipped' | Should -Be 0
  }
  It 'нет панели — ничего не делает' { [void](Ag-Js 'window.reset(false);1'); (AgCdp-AllowPrompt).found | Should -BeFalse; Ag-Js 'window.__submitted.length' | Should -Be 0 }
  It 'строка «Yes, allow this time» в истории чата не мешает выбрать вариант в панели' { [void](Ag-Js 'window.showHistory();1'); (AgCdp-AllowPrompt).ok | Should -BeTrue; Ag-Js 'JSON.stringify(window.__submitted)' | Should -Be '["1"]' }
  It 'если первый вариант — «always», ничего не выбирает и не жмёт Submit' {
    [void](Ag-Js 'window.reset(true,"Yes, and always allow");1')
    (AgCdp-AllowPrompt).found | Should -BeFalse; Ag-Js 'window.__submitted.length' | Should -Be 0; Ag-Js 'window.__sel' | Should -BeNullOrEmpty
  }
}
