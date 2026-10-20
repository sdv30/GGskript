BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:Txt="# Отчёт Arena, шаг 3`nСделано: переработал модуль арены, исправил подсчёт очков, добавил проверку входных данных и логирование; всё проверено на тестах."
  function Capture-Tg{ $script:Tg=New-Object System.Collections.ArrayList; Mock Tg-Send { [void]$script:Tg.Add([string]@($PesterBoundParameters.Values)[0]); 1 } }
}
Describe 'Пункт 35: автоматический поток решает сам, без вопросов' -Tag Item35 {
  BeforeEach {
    Mock Log {}; Capture-Tg; Mock Save-State {}; Mock New-TgPrompt { throw 'вопрос в автоматическом потоке запрещён' }
    $script:St=New-RelayState; $script:Held=@{}; $script:Adopted=@{}; $script:AutoSend=@{}; $script:SendNotBefore=@{}
    $script:St.files['Arena_2026-10-20_002.md']=[ordered]@{ stage='relayed'; time='2026-10-20 22:32:48'; hash='h'; attempts=1; note='' }
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $p=Join-Path $Cfg.Downloads 'Arena_2026-10-20_003.md'; [IO.File]::WriteAllText($p,$script:Txt)
    (Get-Item $p).LastWriteTime=[datetime]'2026-10-20 22:34:47'; $script:F=Get-Item $p
    $Cfg.AutoDecide=$true; $Cfg.StartupAskNewest=$true; $Cfg.AutoSendGraceSec=60; $Cfg.MatchByContent=$true; $Cfg.StartupNewestOnly=$true
    $script:GemSent=0; Mock Gem-Send { $script:GemSent++; @{ pBefore=1 } }
    Mock Wait-FileStable {}; Mock Assert-CanSendGemini { 'Argon' }; Mock Wait-GemAnswerStoppable {}; Mock Get-ModelNow { 'Argon' }
    Mock Check-OurPrompt {}; Mock Gem-LastReportPrompt { 'Arena_2026-10-20_003.md' }; Mock Wait-AnswerAfterLastPrompt {}
    Mock Gem-CopyCode { 'текст для агента' }; Mock Finish-Answered {}; Mock Relay-ToAg {}; Mock Ag-HasText { $false }
  }
  It 'настройки по умолчанию: AutoDecide вкл, пауза 60 сек' {
    $d=Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive; $d.AutoDecide | Should -BeTrue; $d.AutoSendGraceSec | Should -Be 60
  }
  It 'запуск: 003 не в чате — вопроса нет, отправка отложена на 60 сек с перепроверкой' {
    Mock Gem-FindFile { $null }
    $o=Invoke-StartupTriage -LastPrompt ''
    $o.ask | Should -BeNullOrEmpty; $script:AutoSend['Arena_2026-10-20_003.md'] | Should -BeTrue
    $script:SendNotBefore['Arena_2026-10-20_003.md'] | Should -BeGreaterThan (Get-Date).AddSeconds(30)
    $script:Held.ContainsKey('Arena_2026-10-20_003.md') | Should -BeFalse
  }
  It 'до конца паузы — не отправляю' {
    Mock Gem-FindFile { $null }; $script:SendNotBefore['Arena_2026-10-20_003.md']=(Get-Date).AddSeconds(60)
    Process-File $script:F; $script:GemSent | Should -Be 0
  }
  It 'после паузы: пользователь отправил вручную (имя — упоминание, содержимое — последний запрос) — НЕ дублирую, беру ответ' {
    Mock Gem-FindFile { if($Name){ @{ how='name'; index=2; last=$true } } else { @{ how='content'; index=4; last=$true } } }
    $script:SendNotBefore['Arena_2026-10-20_003.md']=(Get-Date).AddSeconds(-1); $script:AutoSend['Arena_2026-10-20_003.md']=$true
    Process-File $script:F
    $script:GemSent | Should -Be 0; Get-Stage 'Arena_2026-10-20_003.md' | Should -BeIn @('sent','answered','relayed'); Should -Invoke Gem-CopyCode -Times 1
  }
  It 'после паузы: только упоминание имени, содержимого нет — отправляю сам' {
    Mock Gem-FindFile { if($Name){ @{ how='name'; index=2; last=$true } } else { $null } }
    $script:SendNotBefore['Arena_2026-10-20_003.md']=(Get-Date).AddSeconds(-1)
    Process-File $script:F; $script:GemSent | Should -Be 1
  }
  It 'авто-resend (был sent, чат сменился) — тоже перепроверяю содержимое' {
    $script:St.files['Arena_2026-10-20_003.md']=[ordered]@{ stage='resend'; time='2026-10-20 22:44:00'; hash=''; attempts=1; note='' }
    $script:AutoSend['Arena_2026-10-20_003.md']=$true
    Mock Gem-FindFile { @{ how='content'; index=4; last=$true } }
    Process-File $script:F; $script:GemSent | Should -Be 0
  }
  It 'старая кнопка «Отправить» после ручной отправки — не дублирую' {
    Resolve-NewestChoice 'Arena_2026-10-20_003.md' 'send'
    Mock Gem-FindFile { @{ how='content'; index=4; last=$true } }
    Process-File $script:F; $script:GemSent | Should -Be 0
  }
  It 'Find-FileInTexts без имени — ищет только по содержимому' {
    $Cfg.ContentKeyChars=120; $Cfg.ContentKeyMin=40
    (Find-FileInTexts -Name '' -Content $script:Txt -Texts @('Файл отчёта: Arena_2026-10-20_003.md упомянут',$script:Txt) -Whole).index | Should -Be 1
  }
}
