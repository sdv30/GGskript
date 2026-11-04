BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe '27.10 sendfix: прикрепление файла в Gemini и панель' -Tag Item63 {
  BeforeEach { $Cfg.Pattern=(Get-DefaultSettings -Root $TestDrive).Pattern }

  It 'чип с обрезанным по центру именем «AccessLabU...-10-27_001» узнаётся (причина бага 27.10)' {
    $n='AccessLabUnified_2026-10-27_001.md'
    Test-ChipMatchesName 'AccessLabU...-10-27_001' $n | Should -BeTrue
    Test-ChipMatchesName 'AccessLabU…-10-27_001' $n | Should -BeTrue
    Test-ChipMatchesName 'AccessLabUnified_2026-10-27_001.md AccessLabUnified_2026-10-27_001' $n | Should -BeTrue
    Test-ChipMatchesName 'Eskalator_...-10-23_007' 'Eskalator_2026-10-23_007.md' | Should -BeTrue
  }
  It 'чужие чипы не принимаются: другой номер, другой проект, чужая история' {
    $n='AccessLabUnified_2026-10-27_001.md'
    Test-ChipMatchesName 'AccessLabU...-10-27_002' $n | Should -BeFalse
    Test-ChipMatchesName 'Fishka 2_...-10-25_009' $n | Should -BeFalse
    Test-ChipMatchesName 'Other...-10-27_001' $n | Should -BeFalse
    Test-ChipMatchesName 'TASKS-FIX-2026-10-27' $n | Should -BeFalse
    Test-ChipMatchesName 'ARGON_SYSTEM_PROMPT' $n | Should -BeFalse
  }
  It 'JS «chips»: только поле ввода — без вложений истории (user-query) и кнопок «источники»' {
    $js=$script:GemJs
    $js | Should -Match "case 'chips':"
    $js | Should -Match "closest\('user-query, model-response'\)"
    $js | Should -Match "multiple-button"
    $js | Should -Match "INPUT-CONTAINER"
  }
  It 'SendFile: чип в поле с обрезанным именем + Send доступен -> нажимает «Отправить» ровно один раз, файл повторно не грузит' {
    $script:sent=0; $script:calls=@()
    Mock Connect-Cdp { @{ ws=$null } }
    Mock Assert-CanSendGemini { $true }
    Mock Start-Sleep {}
    Mock Log {}
    Mock Invoke-Cdp { $script:calls+=$Method; @{} }
    Mock Eval-Js {
      switch($Op){
        'ready'{ $true } 'state'{ @{ n=0 } } 'inputText'{ '' } 'sendEnabled'{ $true } 'focusClear'{ $true }
        'chips'{ ,@('AccessLabU...-10-27_001') }
        'prompts'{ if($script:sent){ 1 } else { 0 } }
        'clickSend'{ $script:sent++; $true }
        'promptTexts'{ ,@('AccessLabUnified_2026-10-27_001.md') }
        default{ $null } } }
    $r=GemCdp-SendFile (Join-Path $TestDrive 'x.md') 'AccessLabUnified_2026-10-27_001.md'
    $r.via | Should -Be 'cdp-file'
    $script:sent | Should -Be 1
    $script:calls | Should -Not -Contain 'Page.setInterceptFileChooserDialog'
    Should -Invoke Log -ParameterFilter { $m -like '*новый запрос с этим файлом появился*' }
  }
  It 'SendFile: в поле нет чипа нашего файла (только история/другое) — не отправляет' {
    $Cfg.AttachTimeoutSec=1; $script:sent=0
    Mock Connect-Cdp { @{ ws=$null } }
    Mock Assert-CanSendGemini { $true }
    Mock Start-Sleep {}
    Mock Log {}
    Mock Invoke-Cdp { @{} }
    Mock Eval-Js {
      switch($Op){
        'ready'{ $true } 'state'{ @{ n=0 } } 'inputText'{ '' } 'sendEnabled'{ $true } 'focusClear'{ $true } 'prompts'{ 0 }
        'chips'{ ,@('TASKS-FIX-2026-10-27','ARGON_SYSTEM_PROMPT','TASKS-FIX-2026-10-27','ARGON_SYSTEM_PROMPT') }
        'openUpload'{ 'nobtn' }
        'clickSend'{ $script:sent++; $true }
        default{ $null } } }
    { GemCdp-SendFile (Join-Path $TestDrive 'x.md') 'AccessLabUnified_2026-10-27_001.md' } | Should -Throw
    $script:sent | Should -Be 0
  }
  It 'Format-ShortState: реальная ошибка 27.10 -> одна короткая строка' {
    $raw="Gemini/CDP (файл): чип файла AccessLabUnified_2026-10-27_001.md не появился или загрузка не закончилась (чипы=[TASKS-FIX-2026-10-27`nЕщё 1 | Посмотреть сведения об источнике для цитаты с сайта MD: TASKS-FIX-2026-10-27.md. Нажмите Ввод | ARGON_SYSTEM_PROMPT]; hasChip=False; sendEnabled=True) — НЕ отправлено"
    $s=Format-ShortState "повтор после ошибки: $raw"
    $s | Should -Be 'не удалось прикрепить файл AccessLabUnified_2026-10-27_001.md в Gemini — повторю'
    $s | Should -Not -Match "[\r\n|]"
  }
  It 'Format-ShortState: обычное состояние не меняется; длинное/многострочное — одна строка ≤ Max' {
    Format-ShortState 'слежу за папкой Downloads, жду новый отчёт' | Should -Be 'слежу за папкой Downloads, жду новый отчёт'
    $x=Format-ShortState ("повтор после ошибки: что-то пошло не так " + ('очень длинный текст ' * 40) + "`nвторая строка")
    $x.Length | Should -BeLessOrEqual 130; $x | Should -Not -Match "[\r\n]"
    Format-ShortState '' | Should -Be ''
  }
  It 'Get-GuiStateView: верхняя строка короткая и без переводов строк' {
    $j=[pscustomobject]@{ kind='running'; state="повтор после ошибки: Gemini/CDP (файл): чип файла A_2026-10-27_001.md не появился (чипы=[x | y])`nещё"; model='Argon'; project='A'; pending=@() }
    $v=Get-GuiStateView $j
    $v.State | Should -Match '^Состояние: работает — не удалось прикрепить файл A_2026-10-27_001.md'
    $v.State | Should -Not -Match "[\r\n|]"; $v.Model | Should -Match 'Argon'
  }
  It 'панель: одна строка состояния с переносом, журнал с переносом и растягивается, индикаторы портов не обрезаются' {
    $g=Get-Content (Join-Path $script:V2Root 'GGskript_gui.ps1') -Raw -Encoding UTF8
    $g | Should -Match '\$pnlTop\.Controls\.Add\(\$lblState\)'
    $g | Should -Not -Match 'pnlTop\.Controls\.AddRange'
    $g | Should -Match '\$lblState\.AutoSize=\$false; \$lblState\.Dock=''Fill'''
    $g | Should -Match '\$txtLog\.WordWrap=\$true; \$txtLog\.ScrollBars=''Vertical'''
    $g | Should -Match "\`$txtLog\.Dock='Fill'"
    $g | Should -Match 'function Fit-Layout'
    $g | Should -Match 'Add_Resize\(\{ Fit-Layout \}\)'
    $g | Should -Match 'MaximumSize=New-Object System\.Drawing\.Size'
    $g | Should -Match 'function Add-InfoLog'
    $g | Should -Not -Match 'lblModel\.Text='
  }
}