BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:UsageText='Текущее использование | Использовано 28 % | Лимит обновится в 12:25 | Недельный лимит | Использовано 40 %'
  $script:ChatName='Тестовый чат - Google Gemini'
  $script:Suffix=', группа Работа — Яндекс Браузер'
  # Модель браузера: окна -> список вкладок и индекс активной
  function Set-Browser([hashtable]$W){ $script:B=@{}; foreach($k in $W.Keys){ $script:B[[int]$k]=@{ tabs=@($W[$k].tabs); act=[int]$W[$k].act } } }
  function ActiveName([int]$h){ $w=$script:B[$h]; $w.tabs[$w.act] }
  function Use-BrowserMocks{
    Mock Log { [void]$script:Logs.Add([string]@($PesterBoundParameters.Values)[0]) }
    Mock Tg-Send { [void]$script:Tg.Add([string]@($PesterBoundParameters.Values)[0]); 1 }
    Mock Start-Sleep {}
    Mock Find-GeminiWindow { 5 }
    Mock Get-TopWindows { @($script:B.Keys | ForEach-Object { [pscustomobject]@{ h=$_; title=((ActiveName $_)+$script:Suffix); class='Chrome_Yandex_WidgetWin_1'; proc='browser'; pid=1 } }) }
    Mock Invoke-WithFocus { $script:fg=$h; & $Body }
    Mock Get-ForegroundHandle { $script:fg }
    Mock GemUia-TabItems { $hh=[int]$h; $i=0; @($script:B[$hh].tabs | ForEach-Object { [pscustomobject]@{ name=$_; el="TAB:$hh`:$i" }; $i++ }) }
    Mock Uia-Root { "ROOT:$h" }
    Mock Uia-Name { $hh=[int](([string]$el) -replace '^ROOT:',''); (ActiveName $hh)+$script:Suffix } -ParameterFilter { ([string]$el) -like 'ROOT:*' }
    Mock Uia-Select { if($script:NoSelect){ return $false }; $p=([string]$el) -split ':'; $script:B[[int]$p[1]].act=[int]$p[2]; [void]$script:Selects.Add([string]$el); $true }
    Mock Uia-Invoke { $false }
    Mock Uia-FindAll { @('TXT') } -ParameterFilter { $ControlType -eq 'Text' }
    Mock Uia-Name { if(Test-UsageTabName (ActiveName $script:fg)){ $script:UsageText } else { 'чат' } } -ParameterFilter { $el -eq 'TXT' }
    Mock Send-Key { [void]$script:Keys.Add([int]$vk) }
    Mock Send-Ctrl { [void]$script:Keys.Add(1000+[int]$vk) }
    Mock GemUia-ReloadButton { $null }   # пункт 27D: здесь проверяется путь с фокусом и F5 (кнопки «Обновить» нет)
  }
}
Describe 'Пункт 26: лимиты Gemini — из уже открытой вкладки, без Ctrl+T' -Tag Item26 {
  BeforeEach {
    $Cfg.UsageOpenNewTab=$false; $Cfg.UsageReloadMin=5; $Cfg.GeminiWebCheck=$true; $Cfg.UsageNoFocus=$false
    $script:Logs=New-Object System.Collections.ArrayList; $script:Tg=New-Object System.Collections.ArrayList
    $script:Keys=New-Object System.Collections.ArrayList; $script:Selects=New-Object System.Collections.ArrayList
    $script:NoSelect=$false; $script:UsageReloadAt=$null; $script:UsageNoTabSaid=$false; $script:fg=0
    Set-Browser @{ 5=@{ tabs=@('Почта',$script:ChatName,'Использование - Google Gemini'); act=1 } }
    Use-BrowserMocks
  }
  It 'по умолчанию UsageOpenNewTab=$false' { (Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive).UsageOpenNewTab | Should -BeFalse }
  It 'вкладка лимитов есть: переключаю, F5 только на ней, читаю, возвращаю чат — Ctrl+T НЕ нажимается' {
    GemUia-GetUsageText | Should -Match 'Использовано 28'
    $script:Keys | Should -Not -Contain 1084   # Ctrl+T
    @($script:Keys) | Should -Be @(0x74)        # одна F5
    $script:Selects[0] | Should -Be 'TAB:5:2'
    ActiveName 5 | Should -Be $script:ChatName
    ($script:Logs -join "`n") | Should -Match 'вернул вкладку чата'
    $script:Tg.Count | Should -Be 0
  }
  It 'повтор через минуту: данные свежие — без F5' {
    GemUia-GetUsageText | Out-Null; $script:Keys.Clear()
    GemUia-GetUsageText | Should -Match 'Использовано 28'
    $script:Keys.Count | Should -Be 0
    ActiveName 5 | Should -Be $script:ChatName
  }
  It 'данные старше UsageReloadMin — снова F5' {
    $script:UsageReloadAt=(Get-Date).AddMinutes(-6)
    GemUia-GetUsageText | Out-Null; @($script:Keys) | Should -Be @(0x74)
  }
  It 'UsageReloadMin=-1 — F5 никогда' { $Cfg.UsageReloadMin=-1; GemUia-GetUsageText | Out-Null; $script:Keys.Count | Should -Be 0 }
  It 'F5 не жму, если на переднем плане не это окно' {
    Mock Get-ForegroundHandle { 99 }
    GemUia-GetUsageText | Out-Null
    $script:Keys.Count | Should -Be 0
    ($script:Logs -join "`n") | Should -Match 'перезагрузку не делаю'
  }
  It 'вкладки лимитов нет: ничего не открываю и не нажимаю, ошибка «нет открытой вкладки»' {
    Set-Browser @{ 5=@{ tabs=@('Почта',$script:ChatName); act=1 } }
    { GemUia-GetUsageText } | Should -Throw '*нет открытой вкладки gemini.google.com/usage*'
    $script:Keys.Count | Should -Be 0; $script:Selects.Count | Should -Be 0
    Should -Invoke Invoke-WithFocus -Times 0
  }
  It 'вкладка не стала активной — ошибка, F5 нет, чат на месте' {
    $script:NoSelect=$true
    { GemUia-GetUsageText } | Should -Throw '*переключиться на вкладку лимитов*'
    $script:Keys.Count | Should -Be 0; ActiveName 5 | Should -Be $script:ChatName
  }
  It 'вернуть чат не удалось — предупреждение в Telegram' {
    Mock Uia-Select { $p=([string]$el) -split ':'; if([int]$p[2] -eq 2){ $script:B[5].act=2 }; $true }
    GemUia-GetUsageText | Out-Null
    ($script:Tg -join "`n") | Should -Match 'не удалось вернуть вкладку чата'
  }
  It 'вкладка лимитов в другом окне того же браузера — чат-окно не трогаю' {
    Set-Browser @{ 5=@{ tabs=@($script:ChatName); act=0 }; 7=@{ tabs=@('Новости','Usage - Google Gemini'); act=0 } }
    GemUia-GetUsageText | Should -Match 'Использовано 28'
    ActiveName 5 | Should -Be $script:ChatName; ActiveName 7 | Should -Be 'Новости'
    $script:Selects | Should -Contain 'TAB:7:1'; $script:Selects | Should -Not -Contain 'TAB:5:0'
  }
  It 'UsageOpenNewTab=$true — прежний способ (новая вкладка)' {
    $Cfg.UsageOpenNewTab=$true; Mock GemUia-GetUsageTextNewTab { 'old' }
    GemUia-GetUsageText | Should -Be 'old'
  }
  Context 'Check-Quotas: нет вкладки — лимиты неизвестны, не блокируют, сообщение один раз' {
    BeforeEach { $Cfg.AgCheck=$false; Mock Get-GeminiWebUsage { throw 'нет открытой вкладки gemini.google.com/usage' }; Mock Write-Status {}; $script:QStopG=$true }
    It 'два прогона — одно сообщение, QStopG снят' {
      Check-Quotas | Out-Null; Check-Quotas | Out-Null
      @($script:Tg | Where-Object { $_ -match 'лимиты Gemini не прочитаны: нет открытой вкладки gemini.google.com/usage' }).Count | Should -Be 1
      $script:Q.gwebNoTab | Should -BeTrue; $script:QStopG | Should -BeFalse; Quota-Blocked | Should -Be ''
    }
    It 'после успешного чтения сообщение снова возможно' {
      Check-Quotas | Out-Null
      Mock Get-GeminiWebUsage { @{ cur=10; wk=20; curReset=''; wkReset='' } }; Check-Quotas | Out-Null
      $script:UsageNoTabSaid | Should -BeFalse
    }
  }
  It 'автовозобновление: нет вкладки лимитов — не стоп, проверяю модель' {
    $script:LimitStop=$true; $script:QStopG=$false; $script:QStopA=$false
    Mock Check-Quotas { $script:Q=@{ gwebNoTab=$true; gwebErr='нет открытой вкладки gemini.google.com/usage' } }
    Mock Get-ModelNow { 'Argon' }; Mock Resume-Work {}; Mock Register-AutoFail {}
    Invoke-AutoResume | Should -BeTrue
    Should -Invoke Register-AutoFail -Times 0; Should -Invoke Resume-Work -Times 1
  }
  Context 'чистая логика' {
    It 'имя вкладки лимитов: «<N>» -> <R>' -TestCases @(
      @{N='Использование - Google Gemini';R=$true},@{N='Usage - Google Gemini — Яндекс Браузер';R=$true},@{N='Лимиты';R=$true},
      @{N='https://gemini.google.com/usage';R=$true},@{N='Тестовый чат - Google Gemini';R=$false},@{N='Табло';R=$false},@{N='';R=$false}) {
      param($N,$R) Test-UsageTabName $N | Should -Be $R
    }
    It 'вкладка чата: точное имя важнее первой «Gemini»' {
      $t=@([pscustomobject]@{name='Другой - Google Gemini';el=1},[pscustomobject]@{name='Использование - Google Gemini';el=2},[pscustomobject]@{name=$script:ChatName;el=3})
      (Select-ChatTab $t $script:ChatName).el | Should -Be 3
      (Select-ChatTab $t 'нет такого').el | Should -Be 1
    }
    It 'устаревание: нет текста / нет F5 / старше N мин — да; свежо — нет' {
      $n=Get-Date
      Test-UsageStale '' $n $n | Should -BeTrue
      Test-UsageStale $script:UsageText $null $n | Should -BeTrue
      Test-UsageStale $script:UsageText $n.AddMinutes(-6) $n | Should -BeTrue
      Test-UsageStale $script:UsageText $n.AddMinutes(-1) $n | Should -BeFalse
    }
  }
}
Describe 'Пункт 26: Find-GeminiWindow не путает вкладку лимитов с чатом' -Tag Item26 {
  BeforeEach { $script:Selects=New-Object System.Collections.ArrayList; $script:ChatName='Тестовый чат - Google Gemini'; Mock Log {}; Mock Start-Sleep {} }
  It 'Find-GeminiWindow: вкладку лимитов за чат не принимает' {
    $Cfg.GeminiSelectTab=$true; $Cfg.GeminiBrowsers=@('browser')
    Mock Get-TopWindows { @([pscustomobject]@{ h=5; title='Почта — Яндекс Браузер'; class='Chrome_Yandex_WidgetWin_1'; proc='browser'; pid=1 }) }
    Mock Uia-FindAll { @('TA','TB') } -ParameterFilter { $ControlType -eq 'TabItem' }
    Mock Uia-Name { 'Использование - Google Gemini' } -ParameterFilter { $el -eq 'TA' }
    Mock Uia-Name { $script:ChatName } -ParameterFilter { $el -eq 'TB' }
    Mock Uia-Select { [void]$script:Selects.Add([string]$el); $true }
    Mock Note-GeminiBrowser {}
    Find-GeminiWindow | Should -Be 5
    @($script:Selects) | Should -Be @('TB')
    }
}
Describe 'Пункт 26: переключение модели после вывода окна на передний план' -Tag Item26 {
  BeforeEach {
    $script:Logs=New-Object System.Collections.ArrayList; $script:Tg=New-Object System.Collections.ArrayList
    Mock Log { [void]$script:Logs.Add([string]@($PesterBoundParameters.Values)[0]) }; Mock Tg-Send { [void]$script:Tg.Add([string]@($PesterBoundParameters.Values)[0]); 1 }
    Mock Start-Sleep {}; $Cfg.ModelButtonWaitSec=0.3; $script:ManualModelSaid=$false
  }
  It 'кнопка «Выбор режима» появляется не сразу — дожидаюсь и открываю меню' {
    $script:n=0; Mock GemUia-ModelButton { $script:n++; if($script:n -ge 3){ 'BTN' } else { $null } }
    Mock Uia-ExpandState { 'Expanded' }; Mock GemUia-ModelItems { @('ITEM') }
    @(GemUia-OpenModelMenu 5) | Should -Be @('ITEM')
    $script:n | Should -Be 3
  }
  It 'кнопки нет совсем — ошибка и в логе похожие кнопки' {
    Mock GemUia-ModelButton { $null }
    Mock GemUia-Buttons { @('B1','B2') }
    Mock Uia-Name { 'Режим: Flash' } -ParameterFilter { $el -eq 'B1' }
    Mock Uia-Name { 'Отправить' } -ParameterFilter { $el -eq 'B2' }
    { GemUia-OpenModelMenu 5 } | Should -Throw '*переключатель модели Gemini не найден*'
    ($script:Logs -join "`n") | Should -Match 'похожие кнопки: «Режим: Flash»'
  }
  It 'Switch-ToArgon не удалось — «выберите Argon вручную» один раз' {
    Mock Get-ModelNow { 'Flash' }; Mock Gem-SelectModel { throw 'переключатель модели Gemini не найден' }
    { Switch-ToArgon } | Should -Throw; { Switch-ToArgon } | Should -Throw
    @($script:Tg | Where-Object { $_ -match 'Выберите Argon вручную' }).Count | Should -Be 1
  }
  It 'после успешного переключения сообщение снова возможно' {
    $script:ManualModelSaid=$true
    Mock Get-ModelNow { 'Argon' }; Mock Gem-SelectModel { 'Argon' }
    Switch-ToArgon | Should -Be 'Argon'; $script:ManualModelSaid | Should -BeFalse
  }
}
