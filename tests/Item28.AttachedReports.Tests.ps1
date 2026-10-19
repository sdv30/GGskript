# Пункт 28: при GeminiTransport=cdp «последний отчёт в чате» был MyProject_2026-10-18_004.md, хотя последним запросом
# пользователь приложил ФАЙЛАМИ 10-19_002 и 10-19_001. Причина: читался только текст .query-text, вложения-«чипы» не видны,
# а «последний отчёт» искался как последний «Файл отчёта:» в тексте (такой был только в старом запросе с 003/004).
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:AL='MyProject_2026-10-'
  # тексты запросов так, как их теперь отдаёт op 'promptTexts' (имена вложений — отдельными строками перед текстом)
  $script:Real=@(
    "Файл отчёта: $($AL)18_003.md`n# Report 003`nФайл отчёта: $($AL)18_004.md`n# Report 004",
    'Ваш запрос',
    "$($AL)18_007.md`nЯ случайно вставил третий отчет",
    "$($AL)18_008.md`nПрикрепляю отчет по 8 промпту",
    'Посмотри на скриншот', 'Ваш запрос', 'Проблемы с сетью', 'FlClashX', 'Ничего не работает',
    "$($AL)19_002.md`n$($AL)19_001.md`nВывод прокси от мегафона не работает с включенным VPN."
  )
}
Describe 'Пункт 28: последний отчёт — из последнего запроса, вложения учитываются (чистая логика)' -Tag Item28 {
  It 'имена из заголовков и строк-«чипов» (с .md и без); путь и упоминание в тексте — не имя' {
    $n=Get-ReportNamesInText "Файл отчёта: $($AL)18_003.md`n$($AL)19_002`nсм. C:\x\$($AL)19_005.md и $($AL)19_006.md" $Cfg.Pattern
    $n | Should -Be @("$($AL)18_003.md","$($AL)19_002.md")
  }
  It 'реальный чат 19.10: последний отчёт 10-19_002 (а не 10-18_004)' {
    Get-LastReportFromPrompts -Texts $script:Real -Pattern $Cfg.Pattern | Should -Be "$($AL)19_002.md"
  }
  It 'старое поведение (только «Файл отчёта:» в тексте) дало бы 004 — фиксирую причину' {
    $old=@($script:Real | Where-Object { $_ -match 'Файл отчёта:\s*\S+\.md' }) | Select-Object -Last 1
    [regex]::Match($old,'Файл отчёта:\s*(\S+\.md)').Groups[1].Value | Should -Be "$($AL)18_003.md"
  }
  It 'в одном запросе несколько отчётов — самый новый по дате/номеру, не по порядку' {
    Get-LastReportFromPrompts -Texts @("$($AL)19_001.md`n$($AL)19_002.md") -Pattern $Cfg.Pattern | Should -Be "$($AL)19_002.md"
    Get-LastReportFromPrompts -Texts @("Файл отчёта: $($AL)18_003.md`n…`nФайл отчёта: $($AL)18_004.md") -Pattern $Cfg.Pattern | Should -Be "$($AL)18_004.md"
  }
  It 'запросы без отчёта после отчёта не сбивают; пустой чат — $null' {
    Get-LastReportFromPrompts -Texts @("Файл отчёта: $($AL)19_003.md`nтекст",'вопрос','ещё вопрос') -Pattern $Cfg.Pattern | Should -Be "$($AL)19_003.md"
    Get-LastReportFromPrompts -Texts @() -Pattern $Cfg.Pattern | Should -BeNullOrEmpty
  }
  It 'GemCdp-LastReportPrompt берёт тексты запросов CDP' {
    Mock Eval-Js { $script:Real }
    GemCdp-LastReportPrompt | Should -Be "$($AL)19_002.md"
  }
  It 'Find-FileInTexts (CDP): 002 и 001 найдены по вложению в последнем запросе — name, last' {
    $r=Find-FileInTexts -Name "$($AL)19_002.md" -Content 'x' -Texts $script:Real -Whole; $r.how | Should -Be 'name'; $r.last | Should -BeTrue; $r.index | Should -Be 9
    (Find-FileInTexts -Name "$($AL)19_001.md" -Content 'x' -Texts $script:Real -Whole).last | Should -BeTrue
    (Find-FileInTexts -Name "$($AL)18_007.md" -Content 'x' -Texts $script:Real -Whole).last | Should -BeFalse
  }
  It 'Find-FileInTexts (UIA): строка-имя внутри многострочного текста ответа — не «вложение»' {
    Find-FileInTexts -Name "$($AL)19_003.md" -Content 'x' -Texts @("Напиши отчёт в`n$($AL)19_003.md`nи всё") | Should -BeNullOrEmpty
  }
}
Describe 'Пункт 28: сверка «ответ уже в Antigravity» при AgTransport=cdp — по тексту страницы' -Tag Item28 {
  BeforeEach { Mock Log {}; $Cfg.AgTransport='cdp' }
  AfterAll { $Cfg.AgTransport='uia' }
  BeforeAll { $script:code="<role>`nSenior Python Concurrency & Network Systems Architect.`n</role>`n<token_economy>`nSTRICT OUTPUT RULES: 1. In Antigravity chat: output ONLY a brief summary`n2. write to ``%USERPROFILE%\Downloads\MyProject_2026-10-19_003.md``" }
  It 'текст есть на странице (с другой разметкой/переносами) — ЕСТЬ, UIA не нужен' {
    Mock AgEval-Js { "Review 9:57 AM <role> Senior Python Concurrency &amp; Network Systems Architect. </role> <token_economy> STRICT OUTPUT RULES: 1. In Antigravity chat: output ONLY a brief summary 2. write to %USERPROFILE%\Downloads\MyProject_2026-10-19_003.md".Replace('&amp;','&') }
    Mock Ag-GetWindow { throw 'UIA не должен вызываться' }
    Ag-HasText $script:code | Should -BeTrue
  }
  It 'текста нет — нет' { Mock AgEval-Js { 'File Edit Selection View другой чат' }; Mock Ag-GetWindow { $null }; Ag-HasText $script:code | Should -BeFalse }
  It 'CDP недоступен — откат на UIA' { Mock AgEval-Js { throw 'CDP Antigravity: не отвечает' }; Mock Ag-GetWindow { $null }; Ag-HasText $script:code | Should -BeFalse; Should -Invoke Ag-GetWindow -Times 1 }
}
Describe 'Пункт 28: настоящий Chromium (headless) + копия DOM чата с вложениями' -Tag Item28,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $Cfg.CdpPort=9341; $Cfg.CdpUrlLike='fake_gemini_attach'
      $fx=Join-Path $PSScriptRoot 'fixtures'; $prof=Join-Path $TestDrive 'chrome_prof28'
      $script:proc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run','--allow-file-access-from-files',"--remote-debugging-port=$($Cfg.CdpPort)","--user-data-dir=$prof",('file://'+(Join-Path $fx 'fake_gemini_attach.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'chrome28.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' | Where-Object { $_.url -like '*fake_gemini_attach*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:CdpConn=$null
  }
  AfterAll { if($script:CdpConn){ Cdp-Close $script:CdpConn; $script:CdpConn=$null }; if($script:proc){ try{ Get-Process -Id $script:proc.Id -EA 0 | Stop-Process -Force }catch{}; Get-Process chrom* -EA 0 | Where-Object { $_.Parent.Id -eq $script:proc.Id } | Stop-Process -Force -EA 0 } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {} }
  It 'запросов 10; последний отчёт 10-19_002; последний запрос начинается с вложений' {
    GemCdp-CountPrompts | Should -Be 10
    GemCdp-LastReportPrompt | Should -Be 'MyProject_2026-10-19_002.md'
    $t=@(GemCdp-PromptTexts); $t[-1] | Should -Match '^MyProject_2026-10-19_002\.md\nMyProject_2026-10-19_001\.md\nВывод прокси'
    $t[2] | Should -Match '^MyProject_2026-10-18_007\.md\n'
  }
  It 'последний ответ (просит 003) — блок Markdown с <role>' {
    $pk=GemCdp-PeekAnswer; $pk.answered | Should -BeTrue; $pk.md | Should -BeTrue; Get-FirstLine $pk.code | Should -Be '<role>'; $pk.code | Should -Match '19_003\.md'
  }
  It 'вручную приложенный 002 узнаётся последним запросом (триаж не отправит его заново)' {
    $r=Find-FileInTexts -Name 'MyProject_2026-10-19_002.md' -Content 'x' -Texts (GemCdp-PromptTexts) -Whole
    $r.how | Should -Be 'name'; $r.last | Should -BeTrue
  }
}

Describe 'Пункт 28: протокол запуска — 002 пропущен по кнопке, но отправлен вручную и ответ уже у агента' -Tag Item28 {
  BeforeAll {
    . (Join-Path $PSScriptRoot '_Load.ps1')
    $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
    function N([int]$i){ 'MyProject_2026-10-18_{0:D3}.md' -f $i }
    function New-Rep([int]$i,[datetime]$t){ $p=Join-Path $Cfg.Downloads (N $i); [IO.File]::WriteAllText($p,"отчёт $i"); (Get-Item $p).LastWriteTime=$t; $p }
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
    Mock Gem-Send { [void]$script:GemSent.Add($Text); @{ pBefore=1 } }; Mock Ag-Send { [void]$script:AgSent.Add($Text) }
  }
  It 'последний отчёт = самый новый (пропущен), ответ уже в Antigravity — ход Antigravity; ничего не отправляю' {
    [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'skipped' -Note '«не отправлять» по кнопке' -Force)
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Markdown'); md=$true; code="<role>`nSenior Python Concurrency & Network Systems Architect.`n</role>" }; $script:InAg=$true
    Start-Procedure | Should -BeTrue
    $t=StartText
    $t | Should -Match 'последний отчёт в чате — MyProject_2026-10-18_007\.md'
    $t | Should -Match 'в чате Antigravity — ЕСТЬ'
    $t | Should -Match '👉 Ход: Antigravity — MyProject_2026-10-18_007\.md пропущен скриптом'
    $script:GemSent.Count | Should -Be 0; $script:AgSent.Count | Should -Be 0
  }
  It 'то же, но ответа в Antigravity нет — ход ничей (как раньше), ничего не отправляю' {
    [void](Set-FileStage -State $script:St -Name (N 7) -Stage 'skipped' -Force)
    $script:LP=(N 7); $script:PK=@{ answered=$true; labels=@('Markdown'); md=$true; code="<role>`nSenior Python Concurrency & Network Systems Architect.`n</role>" }; $script:InAg=$false
    Start-Procedure | Should -BeTrue
    StartText | Should -Match '👉 Ход: ничей — MyProject_2026-10-18_007\.md пропущен'
    $script:GemSent.Count | Should -Be 0; $script:AgSent.Count | Should -Be 0
  }
}

Describe 'Пункт 28: Antigravity — кнопки отмены агента никогда не нажимаются (CDP, настоящий Chromium)' -Tag Item28,Integration {
  BeforeAll {
    $script:chrome=@('/usr/bin/chromium','/usr/bin/google-chrome') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if($script:chrome){
      $fx=Join-Path $PSScriptRoot 'fixtures'; $Cfg.AgCdpPort=9347
      $script:pc=Start-Process $script:chrome -ArgumentList '--headless=new','--no-sandbox','--disable-gpu','--no-first-run',"--remote-debugging-port=$($Cfg.AgCdpPort)","--user-data-dir=$(Join-Path $TestDrive 'pc28')",('file://'+(Join-Path $fx 'fake_antigravity_cancel.html')) -PassThru -RedirectStandardError (Join-Path $TestDrive 'pc28.err')
      for($i=0;$i -lt 40;$i++){ try{ if(@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort | Where-Object { $_.url -like '*fake_antigravity_cancel*' }).Count){ break } }catch{}; Start-Sleep -Milliseconds 500 }
    }
    $script:AgCdpConn=$null
    function Ag-Js([string]$e){ (Invoke-Cdp 'Runtime.evaluate' @{ expression=$e; returnByValue=$true } -Conn (Connect-AgCdp)).result.value }
  }
  AfterAll { if($script:AgCdpConn){ Cdp-Close $script:AgCdpConn; $script:AgCdpConn=$null }; if($script:pc){ try{ Get-Process -Id $script:pc.Id -EA 0 | Stop-Process -Force }catch{} } }
  BeforeEach { if(-not $script:chrome){ Set-ItResult -Skipped -Because 'нет Chromium' }; Mock Log {}; [void](Ag-Js 'window.setBusy(false);window.__cancelled=0;window.__rejected=0;window.__accepted=0;window.__sent=[];1') }
  It 'агент работает (кнопка стала «Cancel (Ctrl+D)» с тем же data-testid) — clickSend не нажимает' {
    [void](Ag-Js 'window.setBusy(true);1')
    AgCdp-IsBusy | Should -BeTrue
    AgEval-Js 'clickSend' | Should -BeFalse
    Ag-Js 'window.__cancelled' | Should -Be 0
  }
  It 'агент свободен — clickSend нажимает «Send message»' {
    [void](Ag-Js 'document.querySelector(''[aria-label="Message input"]'').textContent=''x'';1')
    AgEval-Js 'clickSend' | Should -BeTrue
    Ag-Js 'window.__sent.length' | Should -Be 1; Ag-Js 'window.__cancelled' | Should -Be 0
  }
  It 'clickText с широким шаблоном не нажимает Cancel/Reject — только Accept all' {
    [void](Ag-Js 'window.setBusy(true);1')
    AgCdp-ClickText 'all|cancel|reject' | Should -BeTrue
    Ag-Js 'window.__accepted' | Should -Be 1; Ag-Js 'window.__rejected' | Should -Be 0; Ag-Js 'window.__cancelled' | Should -Be 0
    AgCdp-ClickText '^(cancel|reject|stop)' | Should -BeFalse
    Ag-Js 'window.__cancelled' | Should -Be 0
  }
}
