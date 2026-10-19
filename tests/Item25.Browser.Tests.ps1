BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function W($h,$t,$p,$c='Chrome_WidgetWin_1'){ [pscustomobject]@{h=$h;title=$t;class=$c;proc=$p;pid=1} }
  $script:YaTitle='Тестовый чат - Google Gemini, группа Работа — Яндекс Браузер'   # настоящий заголовок с ПК 19.10
}
Describe 'Пункт 25E: Gemini в любом Chromium-браузере (Chrome, Яндекс Браузер, Edge)' -Tag Item25,Item25E {
  BeforeEach { $Cfg.GeminiBrowsers=@('chrome','browser','msedge'); $Cfg.GeminiSelectTab=$true; $script:GeminiBrowser=''; $script:GeminiBrowserLogged=''; Mock Log {} }
  Context 'хвосты заголовков' {
    It '«<T>» -> «<R>»' -TestCases @(
      @{T='Gemini - Google Chrome';R='Gemini'},
      @{T='Тестовый чат - Google Gemini, группа Работа — Яндекс Браузер';R='Тестовый чат - Google Gemini'},
      @{T='Google Gemini - Yandex Browser';R='Google Gemini'},
      @{T='Google Gemini – Яндекс.Браузер';R='Google Gemini'},
      @{T='Gemini и ещё 3 страницы - Microsoft​ Edge';R='Gemini'},
      @{T='Gemini — Microsoft Edge';R='Gemini'},
      @{T='Gemini';R='Gemini'},
      @{T='Табло — Яндекс Браузер';R='Табло'}) {
      param($T,$R) Remove-BrowserSuffix $T | Should -Be $R
    }
    It 'название браузера по процессу' { Get-BrowserName 'browser' | Should -Be 'Яндекс Браузер'; Get-BrowserName 'chrome' | Should -Be 'Google Chrome'; Get-BrowserName 'msedge' | Should -Be 'Microsoft Edge' }
    It 'GeminiBrowsers строкой «chrome, browser.exe» тоже работает' { $Cfg.GeminiBrowsers='chrome, browser.exe'; (Get-GeminiBrowsers) -join '|' | Should -Be 'chrome|browser' }
    It 'класс окна Яндекса Chrome_Yandex_WidgetWin_1 подходит, вложенные окна — нет' {
      'Chrome_Yandex_WidgetWin_1' | Should -Match $Cfg.GeminiBrowserClassRx; 'Chrome_WidgetWin_1' | Should -Match $Cfg.GeminiBrowserClassRx
      'Chrome_RenderWidgetHostHWND' | Should -Not -Match $Cfg.GeminiBrowserClassRx
    }
  }
  Context 'выбор окна (Select-GeminiWindow)' {
    It 'только Яндекс с активной вкладкой Gemini (как на ПК 19.10) — найден' {
      (Select-GeminiWindow @((W 1 'YouTube - Google Chrome' 'chrome'),(W 2 $script:YaTitle 'browser' 'Chrome_Yandex_WidgetWin_1'))).h | Should -Be 2
    }
    It 'Gemini открыт в двух браузерах — верхнее окно (Z-порядок)' {
      (Select-GeminiWindow @((W 3 'Gemini - Microsoft Edge' 'msedge'),(W 1 'Gemini - Google Chrome' 'chrome'),(W 2 $script:YaTitle 'browser' 'Chrome_Yandex_WidgetWin_1'))).h | Should -Be 3
    }
    It 'вкладка лимитов и «Табло» не считаются чатом' {
      Select-GeminiWindow @((W 1 'Использование Gemini - Google Chrome' 'chrome'),(W 2 'Табло — Яндекс Браузер' 'browser' 'Chrome_Yandex_WidgetWin_1')) | Should -BeNullOrEmpty
    }
    It 'чужие программы с «Gemini» в заголовке не берутся' {
      Select-GeminiWindow @((W 1 'Gemini notes - Блокнот' 'notepad' 'Notepad'),(W 2 'Gemini' 'Antigravity')) | Should -BeNullOrEmpty
    }
    It 'GeminiBrowsers=@(chrome) — Яндекс не рассматривается' { $Cfg.GeminiBrowsers=@('chrome'); Select-GeminiWindow @((W 2 $script:YaTitle 'browser' 'Chrome_Yandex_WidgetWin_1')) | Should -BeNullOrEmpty }
  }
  Context 'Find-GeminiWindow' {
    It 'Яндекс: окно найдено, в лог — название браузера (один раз)' {
      Mock Get-TopWindows { @((W 9 $script:YaTitle 'browser' 'Chrome_Yandex_WidgetWin_1')) }
      Find-GeminiWindow | Should -Be 9; Find-GeminiWindow | Should -Be 9
      $script:GeminiBrowser | Should -Be 'Яндекс Браузер'
      Should -Invoke Log -Times 1 -ParameterFilter { $m -like '*окно найдено — Яндекс Браузер*' }
    }
    It 'Яндекс: активна другая вкладка — переключаю на вкладку Gemini через UIA (TabItem, SelectionItem)' {
      Mock Get-TopWindows { @((W 9 'Пикабу — Яндекс Браузер' 'browser' 'Chrome_Yandex_WidgetWin_1'),(W 4 'YouTube - Google Chrome' 'chrome')) }
      Mock Uia-FindAll { if($Root -eq 9){ @('tabA','tabG') } else { @('tabY') } } -ParameterFilter { $ControlType -eq 'TabItem' }
      Mock Uia-Name { switch($el){ 'tabA'{'Пикабу'} 'tabG'{'Тестовый чат - Google Gemini'} default{'YouTube'} } }
      Mock Uia-Select { $true }; Mock Start-Sleep {}
      Find-GeminiWindow | Should -Be 9
      Should -Invoke Uia-Select -Times 1 -ParameterFilter { $el -eq 'tabG' }
      Should -Invoke Log -ParameterFilter { $m -like '*переключил вкладку Яндекс Браузер*' }
    }
    It 'нет вкладки Gemini нигде — $null, сообщение называет браузеры' {
      Mock Get-TopWindows { @((W 4 'YouTube - Google Chrome' 'chrome')) }; Mock Uia-FindAll { @() }
      Find-GeminiWindow | Should -BeNullOrEmpty
      Get-GeminiBrowserName | Should -Be 'Google Chrome / Яндекс Браузер / Microsoft Edge'
    }
  }
}
Describe 'Пункт 25D/25E: подпись блока кода — дерево UIA как в Яндекс Браузере 19.10 (Text подписи перед кнопками, шапка без Text)' -Tag Item25,Item25D {
  BeforeAll {
    function E($t,$n,$c,$kids=@()){ $o=[pscustomobject]@{ T=$t; N=$n; C=$c; P=$null; K=(New-Object System.Collections.ArrayList) }; foreach($k in $kids){ $k.P=$o; [void]$o.K.Add($k) }; $o }
    function script:DescOf($r){ foreach($k in $r.K){ $k; DescOf $k } }
    # реальная форма: code-block -> [Text 'Markdown'] [decoration -> buttons -> group -> Button] [Text кода…]; в control view decoration не содержит Text
    function Blk($label,[string[]]$code){
      $btn=E 'Button' 'Скопировать код' 'mdc-icon-button'
      $deco=E 'Group' '' 'code-block-decoration header-formatted gds-emphasized-body-m' @((E 'Group' '' 'buttons ng-star-inserted' @((E 'Group' '' 'download-button' @((E 'Button' 'Скачать код' 'x'))),(E 'Group' '' 'mat-mdc-tooltip-trigger copy-button' @($btn)))))
      $kids=@(); if($null -ne $label){ $kids+=E 'Text' $label '' }; $kids+=$deco; foreach($c in $code){ $kids+=E 'Text' $c '' }
      $b=E 'Group' '' 'code-block ng-tns-c1-73 ng-animate-disabled' $kids
      @{ blk=$b; btn=$btn }
    }
  }
  BeforeEach {
    $Cfg.CodeBlockLang='Markdown'; Mock Log {}
    Mock Uia-Parent { $el.P }; Mock Uia-Class { [string]$el.C }; Mock Uia-Name { [string]$el.N }; Mock Uia-CtlType { [string]$el.T }
    Mock Uia-GetText { '' }
    Mock Uia-FindAll { $a=@(DescOf $Root); if($ControlType){ $a=@($a | Where-Object { $_.T -eq $ControlType }) }; if($NameRx){ $a=@($a | Where-Object { $_.N -match $NameRx }) }; $a }
  }
  It '«<L>» -> «<R>»' -TestCases @(@{L='Markdown';R='Markdown'},@{L='Python';R='Python'},@{L='Plaintext';R='Plaintext'},@{L='  markdown  ';R='markdown'}) {
    param($L,$R) $x=Blk $L @('# код'); GemUia-CodeBlockLang $x.btn | Should -Be $R
  }
  It 'подписи нет, код начинается со слова Markdown — подпись пустая (НЕ Markdown)' {
    $x=Blk $null @('Markdown','остальной код'); GemUia-CodeBlockLang $x.btn | Should -Be ''
  }
  It 'текст блока читается без копирования: Text после кнопок шапки' {
    $x=Blk 'Markdown' @('<role>',"`nSenior`n",'</role>'); GemUia-CodeBodyText $x.btn | Should -Be "<role>`nSenior`n</role>"
  }
  It 'последний ответ Plaintext+Markdown+Python — выбран Markdown; только Python — ничего' {
    $p=E 'Button' 'Скопировать запрос' ''
    $a=Blk 'Plaintext' @('a'); $b=Blk 'Markdown' @('## MD'); $c=Blk 'Python' @('print(1)')
    $win=E 'Group' '' 'root' @($p,$a.blk,$b.blk,$c.blk)
    (GemUia-FindCodeCopyButtonOnce $win).btn | Should -Be $b.btn
    $script:LastCodeLangs -join ',' | Should -Be 'Plaintext,Markdown,Python'
    $win2=E 'Group' '' 'root' @((E 'Button' 'Скопировать запрос' ''),(Blk 'Python' @('x')).blk)
    (GemUia-FindCodeCopyButtonOnce $win2).btn | Should -BeNullOrEmpty
  }
}
