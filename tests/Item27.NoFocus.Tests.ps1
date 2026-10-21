BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Manual="# Отчёт MyProject, шаг 2`nСделано: **настроил** прокси-парсер, добавил ``retry`` и логирование ошибок; проверил на 50 страницах — всё работает стабильно и быстро.`n`n## Дальше`nещё текст"
  function Capture-Tg{ $script:Tg=New-Object System.Collections.ArrayList; Mock Tg-Send { [void]$script:Tg.Add([string]@($PesterBoundParameters.Values)[0]); 1 } }
}
Describe 'Пункт 27C: файл в чате Gemini — по имени и по содержимому (чистая логика)' -Tag Item27,Item27C {
  BeforeEach { $Cfg.MatchByContent=$true; $Cfg.ContentKeyChars=120; $Cfg.ContentKeyMin=40 }
  It 'ключ: только буквы/цифры, без «Файл отчёта:», регистр не важен' {
    Get-ContentKey "Файл отчёта: X_1.md`n`n# Привет, МИР! 1-2" | Should -Be 'приветмир12'
    (Get-ContentKey ('а'*500) 120).Length | Should -Be 120
  }
  It 'CDP (целые запросы): «Файл отчёта: имя» последним — name, last' {
    $r=Find-FileInTexts -Name 'A_1.md' -Content 'x' -Texts @('привет',"Файл отчёта: A_1.md`n`nтекст") -Whole
    $r.how | Should -Be 'name'; $r.last | Should -BeTrue
  }
  It 'CDP: отправлен вручную (без заголовка, другая разметка) последним — content, last' {
    $prompt="# Отчёт MyProject, шаг 2`nСделано: *настроил* прокси-парсер, добавил retry и логирование ошибок; проверил на 50 страницах — всё работает стабильно и быстро.`n## Дальше`nещё текст"
    $r=Find-FileInTexts -Name 'MyProject_2026-10-19_002.md' -Content $script:Manual -Texts @("Файл отчёта: MyProject_2026-10-18_003.md`n`nстарый",$prompt) -Whole
    $r.how | Should -Be 'content'; $r.last | Should -BeTrue; $r.index | Should -Be 1
  }
  It 'CDP: найден, но после него был другой запрос — last=false' {
    $r=Find-FileInTexts -Name 'B.md' -Content $script:Manual -Texts @($script:Manual,'ещё вопрос') -Whole
    $r.how | Should -Be 'content'; $r.last | Should -BeFalse
  }
  It 'нет в чате — $null; короткий файл по содержимому не сравниваю; MatchByContent=false — только имя' {
    Find-FileInTexts -Name 'B.md' -Content $script:Manual -Texts @('другое') -Whole | Should -BeNullOrEmpty
    Find-FileInTexts -Name 'B.md' -Content 'ок' -Texts @('ок') -Whole | Should -BeNullOrEmpty
    $Cfg.MatchByContent=$false; Find-FileInTexts -Name 'B.md' -Content $script:Manual -Texts @($script:Manual) -Whole | Should -BeNullOrEmpty
  }
  It 'упоминание имени файла в ответе Gemini — не считается' {
    Find-FileInTexts -Name 'A_2.md' -Content 'x' -Texts @('В отчёте A_2.md вы пишете…') | Should -BeNullOrEmpty
  }
  It 'вложение-«чип» с именем файла — name' {
    (Find-FileInTexts -Name 'A_2.md' -Content 'x' -Texts @('вопрос','A_2.md','Ответ')).how | Should -Be 'name'
  }
  It 'UIA: текст запроса разбит на элементы — совпадение находится; позже «Файл отчёта:» другого файла — last=false' {
    $parts=@('Ответ на 003','# Отчёт MyProject, шаг 2','Сделано: настроил прокси-парсер, добавил retry','и логирование ошибок; проверил на 50 страницах — всё работает стабильно и быстро.','Дальше')
    $r=Find-FileInTexts -Name 'X.md' -Content $script:Manual -Texts $parts
    $r.how | Should -Be 'content'; $r.index | Should -Be 1; $r.last | Should -BeTrue
    $r2=Find-FileInTexts -Name 'X.md' -Content $script:Manual -Texts ($parts+@('Файл отчёта: Y.md'))
    $r2.last | Should -BeFalse
  }
}
Describe 'Пункт 27C: запуск и обычная работа узнают вручную отправленный файл' -Tag Item27,Item27C {
  BeforeEach {
    Mock Log {}; Capture-Tg; Mock Save-State {}
    $script:St=New-RelayState; $script:Held=@{}; $script:Adopted=@{}
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $p=Join-Path $Cfg.Downloads 'MyProject_2026-10-19_002.md'; [IO.File]::WriteAllText($p,$script:Manual)
    $script:F=Get-Item $p
    $Cfg.StartupAskNewest=$true; $Cfg.MatchByContent=$true
  }
  It 'триаж: найден последним по содержимому — «уже в чате», не спрашиваю и не отправляю' {
    Mock Gem-FindFile { @{ how='content'; index=3; last=$true } }
    $o=Invoke-StartupTriage -LastPrompt 'MyProject_2026-10-18_003.md'
    $o.ask | Should -BeNullOrEmpty
    ($o.lines -join "`n") | Should -Match 'узнал по содержимому'
    Get-Stage 'MyProject_2026-10-19_002.md' | Should -Be 'sent'; $script:Adopted['MyProject_2026-10-19_002.md'] | Should -BeTrue
  }
  It 'триаж: найден, но не последним — пропущен, ответ не беру' {
    Mock Gem-FindFile { @{ how='content'; index=1; last=$false } }
    $o=Invoke-StartupTriage -LastPrompt 'MyProject_2026-10-18_003.md'
    Get-Stage 'MyProject_2026-10-19_002.md' | Should -Be 'skipped'; $o.ask | Should -BeNullOrEmpty
  }
  It 'триаж: не найден — как раньше, вопрос в Telegram' {
    Mock Gem-FindFile { $null }
    (Invoke-StartupTriage -LastPrompt 'MyProject_2026-10-18_003.md').ask | Should -Be 'MyProject_2026-10-19_002.md'
  }
  It 'триаж: ошибка чтения чата — «не знаю», как раньше (вопрос)' {
    Mock Gem-FindFile { throw 'окно не найдено' }
    (Invoke-StartupTriage -LastPrompt '').ask | Should -Be 'MyProject_2026-10-19_002.md'
  }
  Context 'Process-File' {
    BeforeEach {
      $script:GemSent=0; Mock Gem-Send { $script:GemSent++; @{ pBefore=1 } }; Mock Gem-SendFile { $script:GemSent++; @{ pBefore=1 } }
      Mock Wait-FileStable {}; Mock Assert-CanSendGemini { 'Argon' }; Mock Wait-GemAnswerStoppable {}; Mock Get-ModelNow { 'Argon' }
      Mock Check-OurPrompt {}; Mock Gem-LastReportPrompt { 'MyProject_2026-10-18_003.md' }
      Mock Gem-CopyCode { "текст для агента" }; Mock Finish-Answered {}; Mock Relay-ToAg {}; Mock Ag-HasText { $false }
    }
    It 'новый файл уже в чате последним — в Gemini НЕ отправляю, беру ответ (последний «Файл отчёта:» — другой, но это не мешает)' {
      Mock Gem-FindFile { @{ how='content'; index=5; last=$true } }
      Process-File $script:F
      $script:GemSent | Should -Be 0
      ($script:Tg -join "`n") | Should -Match 'уже есть в чате Gemini.*узнал по содержимому'
      Should -Invoke Gem-CopyCode -Times 1
    }
    It 'новый файл в чате не последним — пропуск, ничего не отправляю и не беру' {
      Mock Gem-FindFile { @{ how='content'; index=1; last=$false } }
      Process-File $script:F
      $script:GemSent | Should -Be 0; Should -Invoke Gem-CopyCode -Times 0
      Get-Stage 'MyProject_2026-10-19_002.md' | Should -Be 'skipped'
    }
    It 'не в чате — отправляю как обычно' {
      Mock Gem-FindFile { $null }
      Process-File $script:F
      $script:GemSent | Should -Be 1
    }
    It '«отправь заново» (resend) — чат не проверяю, отправляю' {
      Mock Gem-FindFile { @{ how='content'; index=5; last=$true } }
      Set-Stage 'MyProject_2026-10-19_002.md' 'resend'
      Process-File $script:F
      $script:GemSent | Should -Be 1; Should -Invoke Gem-FindFile -Times 0
    }
  }
}
Describe 'Пункт 27A: откат Gemini CDP → UIA только при недоступном CDP' -Tag Item27,Item27A {
  BeforeEach { $Cfg.GeminiTransport='cdp'; $Cfg.GeminiCdpFallback=$true; Mock Log {}; Capture-Tg; $script:CdpDownSaid=$false; $script:CdpDownUntil=$null }
  It 'CDP недоступен — UIA и одно сообщение в Telegram; потом CDP вернулся — сообщение «снова доступен»' {
    Use-GemTransport 'модель' { 'uia' } { throw [GG.RelayNotSentException]::new('CDP: браузер с --remote-debugging-port=9222 не отвечает (refused)') } | Should -Be 'uia'
    Use-GemTransport 'модель' { 'uia' } { throw [GG.RelayNotSentException]::new('CDP: нет вкладки с адресом') } | Should -Be 'uia'
    @($script:Tg | Where-Object { $_ -match 'без порта отладки' }).Count | Should -Be 1
    Use-GemTransport 'модель' { 'uia' } { throw 'CDP не должен вызываться в окне ожидания' } | Should -Be 'uia'
    $script:CdpDownUntil=(Get-Date).AddSeconds(-1)
    Use-GemTransport 'модель' { 'uia' } { 'cdp' } | Should -Be 'cdp'
    @($script:Tg | Where-Object { $_ -match 'снова доступен' }).Count | Should -Be 1
  }
  It 'другая ошибка CDP (страница есть) — без отката на UIA (фокус не трогаю)' {
    { Use-GemTransport 'модель' { 'uia' } { throw 'CDP JS (model): TypeError' } } | Should -Throw '*TypeError*'
  }
  It 'отправка: NotSent из-за недоступности — откат; NotSent по другой причине — нет' {
    Use-GemTransport 'отправка' { 'uia' } { throw [GG.RelayNotSentException]::new('Gemini/CDP: CDP: браузер с --remote-debugging-port=9222 не отвечает (x) — НЕ отправлено') } -Send | Should -Be 'uia'
    $script:CdpDownUntil=$null
    { Use-GemTransport 'отправка' { 'uia' } { throw [GG.RelayNotSentException]::new('Gemini/CDP: нет поля ввода — НЕ отправлено') } -Send } | Should -Throw '*нет поля ввода*'
  }
  It 'Find-CdpTarget: вкладка /app важнее прочих страниц Gemini' {
    $Cfg.CdpUrlLike='gemini.google.com'
    Mock Cdp-HttpJson { @([pscustomobject]@{type='page';url='https://gemini.google.com/gems';id='1'},[pscustomobject]@{type='page';url='https://gemini.google.com/usage';id='2'},[pscustomobject]@{type='page';url='https://gemini.google.com/app/x';id='3'}) }
    (Find-CdpTarget).id | Should -Be '3'; (Find-CdpUsageTarget).id | Should -Be '2'
  }
  It 'Gem-FindFile через CDP берёт целые запросы (-Whole)' {
    Mock GemCdp-PromptTexts { @('старый',$script:Manual) }
    (Gem-FindFile 'X.md' $script:Manual).last | Should -BeTrue
  }
}
Describe 'Пункт 27B: Antigravity без фокуса' -Tag Item27,Item27B {
  BeforeEach { Mock Log {}; Capture-Tg; $script:AgCdpDownSaid=$false; $script:AgCdpDownUntil=$null; $Cfg.AgTransport='cdp'; $Cfg.AgCdpFallback=$true }
  It 'CDP Antigravity недоступен — UIA и одно сообщение в Telegram' {
    Mock AgCdp-Send { throw [GG.RelayNotSentException]::new('CDP Antigravity: порт 9333 не отвечает — Antigravity запущен без --remote-debugging-port (refused)') }
    Mock AgUia-Send {}
    Ag-Send -Text 'a' -Label 'x'; Ag-Send -Text 'b' -Label 'y'
    Should -Invoke AgUia-Send -Times 2
    Should -Invoke AgCdp-Send -Times 1
    @($script:Tg | Where-Object { $_ -match 'без порта отладки' }).Count | Should -Be 1
  }
  It 'чужой текст в поле (CDP) — ошибка, на UIA НЕ откатываюсь' {
    Mock AgCdp-Send { throw (New-AgBlocked 'foreign' 'В поле чата Antigravity чужой текст' 'x') }
    Mock AgUia-Send {}
    { Ag-Send -Text 'a' } | Should -Throw '*чужой текст*'
    Should -Invoke AgUia-Send -Times 0
  }
  It 'AgTransport=uia — как раньше' { $Cfg.AgTransport='uia'; Mock AgUia-Send {}; Mock AgCdp-Send {}; Ag-Send -Text 'a'; Should -Invoke AgUia-Send -Times 1; Should -Invoke AgCdp-Send -Times 0 }
  Context 'Accept all' {
    BeforeEach { $script:Paused=$false; $Cfg.GitCheckpointRepo=''; Mock Ag-GetWindow { 7 }; Mock Find-AcceptAll { 'BTN' }; Mock Invoke-WithFocus { & $Body }; Mock Uia-ClickEl { $true } }
    It 'CDP: DOM-клик, окно на передний план не вывожу' {
      Mock AgCdp-AcceptAll { @{found=$true;ok=$true;busy=$false;files=2} }; Mock Uia-Invoke { $true }
      Try-AcceptAll | Should -BeTrue
      Should -Invoke Invoke-WithFocus -Times 0; Should -Invoke Uia-Invoke -Times 0
    }
    It 'UIA: Invoke без фокуса (AgInvokeNoFocus)' {
      $Cfg.AgTransport='uia'; $Cfg.AgInvokeNoFocus=$true; Mock Uia-Invoke { $true }
      Try-AcceptAll | Should -BeTrue
      Should -Invoke Invoke-WithFocus -Times 0
    }
    It 'Invoke не сработал — прежний путь с фокусом' {
      $Cfg.AgTransport='uia'; Mock Uia-Invoke { $false }
      Try-AcceptAll | Should -BeTrue
      Should -Invoke Invoke-WithFocus -Times 1
    }
  }
}
Describe 'Пункт 27: настоящий Chromium (headless) — Antigravity и Gemini через CDP, без фокуса' -Tag Item27,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $fx=Join-Path $PSScriptRoot 'fixtures'
      $ud=Join-Path $TestDrive 'fake_gemini'; New-Item -ItemType Directory -Force $ud | Out-Null; Copy-Item (Join-Path $fx 'usage.html') (Join-Path $ud 'usage.html')
      $Cfg.AgCdpPort=9343; $Cfg.CdpPort=9344; $Cfg.CdpUrlLike='fake_gemini'
      $script:p1=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.AgCdpPort)","--user-data-dir=$(Join-Path $TestDrive 'p1')",('file://'+(Join-Path $fx 'fake_antigravity.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'c1.err')
      $script:p2=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.CdpPort)","--user-data-dir=$(Join-Path $TestDrive 'p2')",('file://'+(Join-Path $fx 'fake_gemini_model_aria.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'c2.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort | Where-Object { $_.url -like '*fake_antigravity*' }).Count -and @(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*model_aria*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
      # headless открывает одну вкладку — «уже открытую» вкладку лимитов добавляю заранее (как Start-GeminiChrome.bat)
      try{ [void](Cdp-HttpJson ('/json/new?file://'+(Join-Path $ud 'usage.html')) -Method Put) }catch{}
      for($i=0;$i -lt 20;$i++){ try{ if(@(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*fake_gemini/usage*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 300 }
    }
    $script:AgCdpConn=$null; $script:CdpConn=$null
    function Ag-Js([string]$e){ (Invoke-Cdp 'Runtime.evaluate' @{ expression=$e; returnByValue=$true } -Conn (Connect-AgCdp)).result.value }
  }
  AfterAll {
    foreach($c in $script:AgCdpConn,$script:CdpConn){ if($c){ Cdp-Close $c } }
    foreach($p in $script:p1,$script:p2){ if($p){ try{ Get-Process -Id $p.Id -EA 0 | Stop-Process -Force }catch{} } }
  }
  BeforeEach {
    if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }
    Mock Log {}; Capture-Tg; Mock Assert-AgReady { @{ ok=$true } }
    # никакого фокуса/клавиатуры/буфера ОС — если вызовутся, тест упадёт
    Mock Invoke-WithFocus { throw 'фокус запрещён' }; Mock Activate-Window { throw 'фокус запрещён' }; Mock PressEnter { throw 'клавиатура запрещена' }; Mock Use-TempClipboard { throw 'буфер запрещён' }
    $Cfg.AgFieldReads=2; $Cfg.AgTransport='cdp'; $Cfg.GeminiTransport='cdp'
  }
  It 'Antigravity: поле чата найдено среди целей DevTools' { (Get-AgCdpDiag).chat | Should -Match 'Antigravity'; (Get-AgCdpDiag).accept | Should -BeTrue }
  It 'Antigravity: отправка — текст в поле → Enter в страницу → ушёл; ни фокуса, ни клавиатуры ОС' {
    $t="Задание для агента`n## Шаг 1`nсделай «X» & <Y>"
    Ag-Send -Text $t -Label 'тест'
    $s=@(Ag-Js 'window.__sent')
    $s.Count | Should -Be 1; ($s[0] -replace '\s+',' ') | Should -Match 'Задание для агента'
    Ag-Js 'document.querySelector("[aria-label=\"Message input\"]").innerText.trim()' | Should -Be ''
    AgCdp-IsBusy | Should -BeTrue
  }
  It 'Antigravity: чужой текст в поле — НЕ отправляю и не трогаю' {
    Ag-Js 'window.setForeign("пишу сам")' | Out-Null
    { Ag-Send -Text 'новое задание' } | Should -Throw '*чужой текст*'
    Ag-Js 'document.querySelector("[aria-label=\"Message input\"]").innerText' | Should -Be 'пишу сам'
    Ag-Js 'window.setForeign("")' | Out-Null
  }
  It 'Antigravity: Enter не сработал — кнопки отправки нет — ошибка, текст остаётся' {
    Ag-Js 'window.__enterIgnored=true' | Out-Null
    { AgCdp-Send -Text 'зависшее задание' } | Should -Throw '*не ушло*'
    Ag-Js 'window.__enterIgnored=false; document.querySelector("[aria-label=\"Message input\"]").innerHTML=""' | Out-Null
  }
  It 'Antigravity: Accept all — DOM-клик без фокуса' {
    $Cfg.GitCheckpointRepo=''; $script:Paused=$false; Mock Ag-GetWindow { 7 }; Mock Find-AcceptAll { 'BTN' }
    Try-AcceptAll | Should -BeTrue
    Ag-Js 'window.__accepted' | Should -Be 1
  }
  It 'Gemini: модель без значка — «Flash»; только aria-label — тоже «Flash»' {
    GemCdp-GetModel | Should -Be 'Flash'
    Invoke-Cdp 'Runtime.evaluate' @{ expression='window.onlyAria()'; returnByValue=$true } | Out-Null
    GemCdp-GetModel | Should -Be 'Flash'
  }
  It 'Gemini: вручную отправленный отчёт найден в запросах по содержимому (последним)' {
    $r=Gem-FindFile 'MyProject_2026-10-19_002.md' "# Отчёт MyProject, шаг 2`nСделано: **настроил** прокси-парсер, добавил ``retry`` и логирование ошибок; проверил на 50 страницах — всё работает стабильно и быстро."
    $r.how | Should -Be 'content'; $r.last | Should -BeTrue
    (Gem-FindFile 'MyProject_2026-10-18_003.md' 'x').last | Should -BeFalse
  }
  It 'Gemini: лимиты — из открытой вкладки /usage (Page.reload), новую вкладку не открываю' {
    $Cfg.GeminiTransport='cdp'; $script:CdpUsageReloadAt=$null
    $n0=@(Cdp-HttpJson '/json/list' | Where-Object { $_.type -eq 'page' }).Count
    GemCdp-GetUsageText | Should -Match 'Использовано 37'
    @(Cdp-HttpJson '/json/list' | Where-Object { $_.type -eq 'page' }).Count | Should -Be $n0
    $script:CdpUsageReloadAt | Should -Not -BeNullOrEmpty
  }
}

Describe 'Пункт 27D: лимиты без фокуса и без клавиш; звуки' -Tag Item27 {
  BeforeAll {
    $script:ChatName='Тестовый чат - Google Gemini'
    $script:UsageText='Текущее использование | Использовано 28 % | Недельный лимит | Использовано 40 %'
    function Set-Tabs([string[]]$T,[int]$A){ $script:Tabs=@($T); $script:Act=$A }
    function ActTab{ $script:Tabs[$script:Act] }
  }
  BeforeEach {
    $Cfg.UsageOpenNewTab=$false; $Cfg.UsageReloadMin=5; $Cfg.UsageNoFocus=$true; $Cfg.Sounds='important'; $Cfg.SoundRepeatMin=10
    $script:UsageReloadAt=$null; $script:SoundLast=@{}
    $script:Logs=New-Object System.Collections.ArrayList; $script:Tg=New-Object System.Collections.ArrayList
    $script:Keys=New-Object System.Collections.ArrayList; $script:Reloads=0; $script:Focus=0; $script:Idle=0; $script:Beeps=New-Object System.Collections.ArrayList
    $script:fg=42; $script:NoSelect=$false
    Set-Tabs @('Почта',$script:ChatName,'Использование - Google Gemini') 1
    Mock Log { [void]$script:Logs.Add([string]@($PesterBoundParameters.Values)[0]) }
    Mock Tg-Send { [void]$script:Tg.Add([string]@($PesterBoundParameters.Values)[0]); 1 }
    Mock Start-Sleep {}
    Mock Find-GeminiWindow { 5 }
    Mock Get-TopWindows { @() }
    Mock Get-ForegroundHandle { $script:fg }
    Mock Invoke-WithFocus { $script:Focus++; $script:fg=$h; & $Body }
    Mock Wait-UserIdle { $script:Idle++; $false }
    Mock GemUia-TabItems { $i=0; @($script:Tabs | ForEach-Object { [pscustomobject]@{ name=$_; el="TAB:$i" }; $i++ }) }
    Mock GemUia-ActiveTitle { ActTab }
    Mock Uia-Select { if($script:NoSelect){ return $false }; $script:Act=[int](([string]$el) -replace 'TAB:',''); $true }
    Mock Uia-Invoke { if($el -eq 'RELOAD'){ $script:Reloads++; return $true }; $false }
    Mock GemUia-ReloadButton { 'RELOAD' }
    Mock GemUia-ReadUsage { if(Test-UsageTabName (ActTab)){ $script:UsageText } else { 'чат' } }
    Mock Send-Key { [void]$script:Keys.Add([int]$vk) }
    Mock Send-Ctrl { [void]$script:Keys.Add(1000+[int]$vk) }
    Mock PressEsc { [void]$script:Keys.Add(0x1B) }
    Mock Invoke-Beep { [void]$script:Beeps.Add("$Freq`:$Ms") }
  }
  It 'по умолчанию: Sounds=important, UsageNoFocus, кнопка «Обновить» вместо F5' {
    $d=Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive
    $d.Sounds | Should -Be 'important'; $d.UsageNoFocus | Should -BeTrue; $d.SoundRepeatMin | Should -Be 10
    'Обновить эту страницу' | Should -Match $d.ReloadButtonRx; 'Reload' | Should -Match $d.ReloadButtonRx
    'Обновить тариф' | Should -Not -Match $d.ReloadButtonRx; 'Обновить' | Should -Not -Match $d.ReloadButtonRx
  }
  It 'лимиты: без вывода окна, без клавиш; перезагрузка — кнопкой «Обновить» (UIA Invoke); чат возвращён' {
    GemUia-GetUsageText | Should -Match 'Использовано 28'
    $script:Focus | Should -Be 0; $script:Keys.Count | Should -Be 0; $script:Reloads | Should -Be 1
    ActTab | Should -Be $script:ChatName
    ($script:Logs -join "`n") | Should -Match 'без фокуса'
  }
  It 'кнопки «Обновить» нет — без фокуса F5 не жму, данные читаю как есть' {
    Mock GemUia-ReloadButton { $null }
    GemUia-GetUsageText | Should -Match 'Использовано 28'
    $script:Keys.Count | Should -Be 0; $script:Focus | Should -Be 0
  }
  It 'вкладку без фокуса выбрать не удалось — прежний путь с фокусом (один раз), чат на месте' {
    $script:NoSelect=$true
    { GemUia-GetUsageText } | Should -Throw '*не удалось переключиться*'
    $script:Focus | Should -Be 1; ActTab | Should -Be $script:ChatName
  }
  It 'пользователь сейчас в окне браузера с Gemini — сначала жду, пока он не трогает мышь/клавиатуру' {
    $script:fg=5; GemUia-GetUsageText | Out-Null; $script:Idle | Should -Be 1
  }
  It 'меню моделей: Esc не жму, если окно Gemini не на переднем плане' {
    Mock GemUia-ModelButton { 'BTN' }; Mock Uia-ExpandState { 'Expanded' }; Mock Uia-Collapse { $false }
    $script:fg=99; GemUia-CloseModelMenu 5; $script:Keys.Count | Should -Be 0
    $script:fg=5; GemUia-CloseModelMenu 5; $script:Keys | Should -Contain 0x1B
  }
  It 'Activate-Window: клавиша-разблокировка — только со второй попытки' {
    (Get-Content (Join-Path $V2Root 'lib/Platform.Win.ps1') -Raw) | Should -Match '\$k -gt 0 -and \$i -gt 0'
  }
  It 'шаблоны: лимит/модель — 1 длинный низкий, нет Markdown — 2 коротких, ошибка — 3 коротких' {
    $l=@(Get-SoundTones 'limit'); $l.Count | Should -Be 1; $l[0].ms | Should -BeGreaterThan 500; $l[0].f | Should -BeLessThan 500
    $n=@(Get-SoundTones 'nocode'); $n.Count | Should -Be 2; ($n | ForEach-Object { $_.ms } | Measure-Object -Maximum).Maximum | Should -BeLessThan 300
    $e=@(Get-SoundTones 'error'); $e.Count | Should -Be 3; ($e | ForEach-Object { $_.ms } | Measure-Object -Maximum).Maximum | Should -BeLessThan 300
    @(Get-SoundTones 'что-то').Count | Should -Be 0
  }
  It 'Test-SoundAllowed: <M>/<K> -> <R>' -TestCases @(
    @{ M='important'; K='limit'; R=$true },  @{ M='important'; K='nocode'; R=$true }, @{ M='important'; K='error'; R=$true },
    @{ M='important'; K='info'; R=$false },  @{ M='all'; K='info'; R=$true },         @{ M='off'; K='limit'; R=$false },
    @{ M='off'; K='error'; R=$false },       @{ M=''; K='nocode'; R=$true },          @{ M='important'; K='beep'; R=$false }
  ) { param($M,$K,$R) Test-SoundAllowed $K $M $null | Should -Be $R }
  It 'один и тот же звук — не чаще раза в 10 мин; разные звуки независимы' {
    Play-Sound 'error' | Should -BeTrue; $script:Beeps.Count | Should -Be 3
    Play-Sound 'error' | Should -BeFalse; $script:Beeps.Count | Should -Be 3
    Play-Sound 'nocode' | Should -BeTrue; $script:Beeps.Count | Should -Be 5
    $script:SoundLast['error']=(Get-Date).AddMinutes(-11); Play-Sound 'error' | Should -BeTrue; $script:Beeps.Count | Should -Be 8
  }
  It 'Sounds=off — тишина; Sounds=all — ещё короткий сигнал после передачи' {
    $Cfg.Sounds='off'; Play-Sound 'limit' | Should -BeFalse; Play-Sound 'error' | Should -BeFalse; $script:Beeps.Count | Should -Be 0
    $Cfg.Sounds='important'; Play-Sound 'info' | Should -BeFalse
    $Cfg.Sounds='all'; Play-Sound 'info' | Should -BeTrue; $script:Beeps.Count | Should -Be 1
  }
  It 'остановка по модели: один длинный сигнал; повторное уведомление в той же остановке — без звука' {
    $script:LimitStop=$false
    Enter-LimitStop 'Flash' 'тест'; Enter-LimitStop 'Flash' 'ещё'
    @($script:Beeps) | Should -Be @('392:900')
    $script:LimitStop=$false
  }
  It '«выберите Argon вручную» — 3 коротких (нужна помощь)' {
    $script:ManualModelSaid=$false; Send-ManualModelNotice 'тест'; $script:Beeps.Count | Should -Be 3
  }
  It 'в коде нет прямых [Console]::Beep кроме Invoke-Beep; тесты не пищат (GG_NO_BEEP)' {
    $hits=@(Get-ChildItem (Join-Path $V2Root 'lib') -Filter *.ps1 | Select-String -Pattern '\[Console\]::Beep' | Where-Object { $_.Line -notmatch 'function Invoke-Beep' })
    $hits.Count | Should -Be 0
    $env:GG_NO_BEEP | Should -Be '1'
  }
  It '«помощь» расшифровывает звуки' { $HelpText | Should -Match 'Звуки на ПК: 1 длинный низкий' }
  It 'настройка Sounds: допустимые значения' {
    (Get-Content (Join-Path $V2Root 'lib/Core.ps1') -Raw) | Should -Match "@\('Sounds','important','off','all'\)"
  }
}
Describe 'Пункт 27A: запускаторы браузера для Gemini (Chrome по умолчанию)' -Tag Item27,Item27A {
  BeforeAll {
    $script:Br=[IO.File]::ReadAllText((Join-Path $V2Root 'Start-GeminiBrowser.bat'))
    $script:Ch=[IO.File]::ReadAllText((Join-Path $V2Root 'Start-GeminiChrome.bat'))
  }
  It 'подсказка при недоступном CDP советует Start-GeminiChrome.bat' {
    $g=[IO.File]::ReadAllText((Join-Path $V2Root 'lib/Gemini.ps1'))
    $g | Should -Match 'Start-GeminiChrome\.bat'; $g | Should -Not -Match 'Start-GeminiBrowser\.bat'
  }
  It 'Start-GeminiBrowser.bat: без аргумента — Chrome' { $Br | Should -Match 'if "%PREF%"=="" set "PREF=chrome"' }
  It 'Start-GeminiBrowser.bat: yandex и edge — только явным аргументом' {
    $Br | Should -Match '(?m)^if /i "%PREF%"=="yandex" goto yandex'
    $Br | Should -Match '(?m)^if /i "%PREF%"=="edge" goto edge'
    $Br | Should -Match 'msedge\.exe'; $Br | Should -Match 'YandexBrowser\\Application\\browser\.exe'
  }
  It 'у каждого браузера свой профиль; Chrome — тот же, что у Start-GeminiChrome.bat' {
    foreach($p in 'chrome-gemini-profile','gemini-profile','edge-gemini-profile'){ $Br | Should -Match ([regex]::Escape("set ""PROFILE=%LOCALAPPDATA%\GGskript\$p""")) -Because $p }
    $Ch | Should -Match ([regex]::Escape('set "PROFILE=%LOCALAPPDATA%\GGskript\chrome-gemini-profile"'))
  }
  It 'оба запускатора: только 127.0.0.1 и строки CRLF' {
    foreach($t in $Br,$Ch){ $t | Should -Match '--remote-debugging-address=127\.0\.0\.1'; ($t -replace "`r`n",'') | Should -Not -Match "`n" }
  }
}
