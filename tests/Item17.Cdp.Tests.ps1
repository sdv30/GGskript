BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 17: выбор транспорта и безопасный откат' -Tag Item17 {
  BeforeEach { $Cfg.GeminiTransport='cdp'; $Cfg.GeminiCdpFallback=$true; Mock Log {}; $script:CdpDownUntil=$null; $script:CdpDownSaid=$false }
  It 'GeminiTransport=uia (по умолчанию) — CDP не вызывается' { $Cfg.GeminiTransport='uia'; Use-GemTransport 'x' { 'uia' } { throw 'не должно' } | Should -Be 'uia' }
  It 'чтение: CDP недоступен — откат на UIA с записью в лог' { Mock Tg-Send { 1 }; Use-GemTransport 'модель' { 'uia' } { throw 'CDP: Chrome с --remote-debugging-port=9222 не отвечает (нет Chrome)' } | Should -Be 'uia'; Should -Invoke Log -ParameterFilter { $m -like '*откат на UIA*' } }
  It 'отправка: NotSent из-за недоступного CDP — откат на UIA' { Mock Tg-Send { 1 }; Use-GemTransport 'отправка' { 'uia' } { throw [GG.RelayNotSentException]::new('CDP: нет вкладки с адресом gemini') } -Send | Should -Be 'uia' }
  It 'отправка: ошибка ПОСЛЕ клика — без отката (нет двойной отправки)' { { Use-GemTransport 'отправка' { 'uia' } { throw 'запрос не появился' } -Send } | Should -Throw '*не появился*' }
  It 'Stop/Limit/Paused никогда не откатываются' { { Use-GemTransport 'x' { 'uia' } { throw [GG.RelayStopException]::new('стоп') } } | Should -Throw -ExceptionType ([GG.RelayStopException]) }
  It 'GeminiCdpFallback=false — ошибка пробрасывается' { $Cfg.GeminiCdpFallback=$false; { Use-GemTransport 'x' { 'uia' } { throw 'CDP: Chrome не отвечает (нет Chrome)' } } | Should -Throw '*нет Chrome*' }
  It 'Gem-WaitAnswer идёт тем же транспортом, что и отправка' { Mock GemUia-WaitAnswer { 'u' }; Mock GemCdp-WaitAnswer { 'c' }; Gem-WaitAnswer @{via='uia'} | Should -Be 'u'; Gem-WaitAnswer @{via='cdp'} | Should -Be 'c' }
}
Describe 'Пункт 17: GemCdp-* с подменённым протоколом' -Tag Item17 {
  BeforeEach { Mock Log {}; $script:CdpConn=$null }
  It 'Chrome без порта — NotSent (безопасно откатиться)' { Mock Cdp-HttpJson { throw 'connection refused' }; { Connect-Cdp } | Should -Throw -ExceptionType ([GG.RelayNotSentException]) }
  It 'нет вкладки Gemini — NotSent' { Mock Cdp-HttpJson { @([pscustomobject]@{type='page';url='https://example.com';id='1'}) }; { Connect-Cdp } | Should -Throw -ExceptionType ([GG.RelayNotSentException]) }
  It 'вкладка /usage не принимается за чат' { Mock Cdp-HttpJson { @([pscustomobject]@{type='page';url='https://gemini.google.com/usage';id='1'},[pscustomobject]@{type='page';url='https://gemini.google.com/app/abc';id='2'}) }; (Find-CdpTarget).id | Should -Be '2' }
  It 'текст не вставился — NotSent, кнопка «Отправить» не нажималась' {
    Mock Connect-Cdp { @{nextId=0} }; Mock Invoke-Cdp {}; Mock Start-Sleep {}
    Mock Eval-Js { switch($Op){ 'ready'{$true} 'prompts'{1} 'state'{@{n=1}} 'focusClear'{$true} 'inputText'{''} 'clickSend'{ $script:clicked=$true; $true } } }
    $script:clicked=$false
    { GemCdp-Send 'отчёт' 'отчёт' } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
    $script:clicked | Should -BeFalse
  }
  It 'фокус не подтверждён — NotSent, текст не вставлялся' {
    Mock Connect-Cdp { @{nextId=0} }; Mock Invoke-Cdp {}; Mock Eval-Js { switch($Op){ 'ready'{$true} 'prompts'{1} 'state'{@{n=1}} 'focusClear'{$false} } }
    { GemCdp-Send 'x' 'x' } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
    Should -Invoke Invoke-Cdp -Times 0 -ParameterFilter { $Method -eq 'Input.insertText' }
  }
  It 'GemCdp-GetCode: выбирает блок по языку и CodeBlockPick' {
    Mock Eval-Js { @([pscustomobject]@{lang='Markdown';code='A'},[pscustomobject]@{lang='Python';code='P'},[pscustomobject]@{lang='Markdown';code='B'}) }
    $Cfg.CodeBlockPick='last'; GemCdp-GetCode | Should -Be 'B'
    $Cfg.CodeBlockPick='first'; GemCdp-GetCode | Should -Be 'A'; $Cfg.CodeBlockPick='last'
    Mock Eval-Js { @([pscustomobject]@{lang='Python';code='P'}) }; GemCdp-GetCode | Should -BeNullOrEmpty
  }
  It 'селекторы можно переопределить в настройках' { $Cfg.CdpSelectors=@{ input='#my' }; (Get-CdpSelectors).input | Should -Be '#my'; (Get-CdpSelectors).prompt | Should -Be 'user-query'; $Cfg.CdpSelectors=@{} }
}
Describe 'Пункт 17: интеграция с настоящим Chromium (headless) и тестовой страницей Gemini' -Tag Item17,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $Cfg.CdpPort=9339; $Cfg.CdpUrlLike='fake_gemini'; $Cfg.GeminiQuietSec=2; $Cfg.GeminiTimeoutSec=60; $Cfg.CodeBlockPick='last'
      $fx=Join-Path $PSScriptRoot 'fixtures'
      $Cfg.GeminiUsageUrl='file://'+(Join-Path $fx 'usage.html')
      $prof=Join-Path $TestDrive 'chrome_prof'
      $script:proc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run','--allow-file-access-from-files',"--remote-debugging-port=$($Cfg.CdpPort)","--user-data-dir=$prof",('file://'+(Join-Path $fx 'fake_gemini.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'chrome.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*fake_gemini*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:CdpConn=$null
  }
  AfterAll { if($script:CdpConn){ Cdp-Close $script:CdpConn }; if($script:proc){ try{ Get-Process -Id $script:proc.Id -EA 0 | Stop-Process -Force }catch{}; Get-Process chrom* -EA 0 | Where-Object { $_.Parent.Id -eq $script:proc.Id } | Stop-Process -Force -EA 0 } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {}; Mock Pump {} }
  It 'готовность, модель, пустой чат' { GemCdp-IsReady | Should -BeTrue; GemCdp-GetModel | Should -Be 'Argon Ultra'; GemCdp-CountPrompts | Should -Be 0 }
  It 'полный цикл: отправка → ожидание → блок Markdown (последний из двух) → весь ответ' {
    $msg="Файл отчёта: P_2026-10-18_001.md`nТекст отчёта с кавычками `"'` и <тегами> & прочим"
    $ctx=GemCdp-Send $msg 'Файл отчёта: P_2026-10-18_001.md'
    $ctx.via | Should -Be 'cdp'; $ctx.pBefore | Should -Be 0
    GemCdp-WaitAnswer $ctx | Should -Be 1
    GemCdp-GetCode | Should -Be "## Задача 1`nсделай X"
    $w=GemCdp-GetWhole
    $w | Should -Match 'Ответ номер 1'
    $w | Should -Match '```markdown'
    GemCdp-CountPrompts | Should -Be 1
    GemCdp-LastReportPrompt | Should -Be 'P_2026-10-18_001.md'
    (Eval-Js 'body') | Should -Match 'с кавычками "'' и <тегами> & прочим'
  }
  It 'второй запрос: поле очищено перед вставкой, ответ №2' {
    $ctx=GemCdp-Send 'Файл отчёта: P_2026-10-18_002.md' 'P_2026-10-18_002.md'
    GemCdp-WaitAnswer $ctx | Should -Be 2
    GemCdp-GetCode | Should -Be "## Задача 2`nсделай X"
  }
  It 'ошибка Gemini на странице — исключение «Gemini показал ошибку»' {
    $ctx=GemCdp-Send 'ОШИБКА тест' 'ОШИБКА тест'
    { GemCdp-WaitAnswer $ctx } | Should -Throw '*Gemini показал ошибку*'
  }
  It 'лимиты: вкладки лимитов нет — открывается фоновая, читается и ОСТАЁТСЯ (пункт 27A)' {
    $t=GemCdp-GetUsageText
    (ConvertFrom-UsageText $t).cur | Should -Be 37
    Start-Sleep -Milliseconds 500
    @(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*usage.html*' }).Count | Should -Be 1
  }
  It 'через общий интерфейс Gem-* (GeminiTransport=cdp)' { $Cfg.GeminiTransport='cdp'; Gem-GetModel | Should -Be 'Argon Ultra'; Gem-CountPrompts | Should -Be 3; $Cfg.GeminiTransport='uia' }
}
