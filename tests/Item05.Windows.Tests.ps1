BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  if(-not (Get-Command Nap -EA 0)){ function Nap($sec){} }
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function W($h,$t,$p='chrome',$c='Chrome_WidgetWin_1'){ [pscustomobject]@{h=$h;title=$t;class=$c;proc=$p} }
}
Describe 'Пункт 5: поиск окон и вкладка лимитов' -Tag Item05 {
  BeforeEach { Mock Log {}; Mock Start-Sleep {}; $Cfg.GeminiSelectTab=$true }
  Context 'Select-TopWindow' {
    It 'находит Gemini во ВТОРОМ окне Chrome (раньше MainWindowHandle видел только одно)' {
      $w=@((W 1 'YouTube - Google Chrome'),(W 2 'Gemini - Google Chrome'))
      (Select-TopWindow -Windows $w -ProcessNames chrome -ClassRx '^Chrome_WidgetWin_1$' -TitleLike '*Gemini*').h | Should -Be 2
    }
    It 'игнорирует окна без заголовка, чужие классы и процессы' {
      $w=@((W 1 '' ),(W 2 'Gemini' 'notepad' 'Notepad'),(W 3 'Gemini' 'chrome' 'Chrome_RenderWidgetHostHWND'),(W 4 'Gemini'))
      (Select-TopWindow -Windows $w -ProcessNames chrome -ClassRx '^Chrome_WidgetWin_1$' -TitleLike '*Gemini*').h | Should -Be 4
    }
    It 'исключает вкладку лимитов по ExcludeTitleRx' {
      $w=@((W 1 'Использование — Gemini'),(W 2 'Gemini'))
      (Select-TopWindow -Windows $w -ProcessNames chrome -TitleLike '*Gemini*' -ExcludeTitleRx $Cfg.UsageTabTitle).h | Should -Be 2
    }
    It 'ничего не нашлось — $null' { Select-TopWindow -Windows @() -TitleLike '*x*' | Should -BeNullOrEmpty }
  }
  Context 'Find-GeminiWindow' {
    It 'по заголовку активной вкладки' { Mock Get-TopWindows { @((W 7 'Почта'),(W 8 'Google Gemini')) }; Find-GeminiWindow | Should -Be 8 }
    It 'вкладка Gemini неактивна — находит TabItem через UIA и переключает' {
      Mock Get-TopWindows { @((W 7 'Почта - Google Chrome')) }
      Mock Uia-FindAll { @('TAB_MAIL','TAB_GEM') } -ParameterFilter { $ControlType -eq 'TabItem' }
      Mock Uia-Name { if($el -eq 'TAB_GEM'){ 'Google Gemini' } else { 'Почта' } }
      Mock Uia-Select { $script:selected=$el; $true }
      Find-GeminiWindow | Should -Be 7
      $script:selected | Should -Be 'TAB_GEM'
    }
    It 'GeminiSelectTab=false — вкладки не переключает' {
      $Cfg.GeminiSelectTab=$false; Mock Get-TopWindows { @((W 7 'Почта')) }; Mock Uia-FindAll { @('TAB') }
      Find-GeminiWindow | Should -BeNullOrEmpty; Should -Invoke Uia-FindAll -Times 0
    }
  }
  Context 'GemUia-GetUsageTextNewTab: вкладка закрывается при любом исходе (баг стр. 829)' {
    BeforeEach {
      $script:title='Gemini'; $script:keys=@(); $script:focusClass='omnibox'
      Mock Find-GeminiWindow { 5 }
      Mock Invoke-WithFocus { & $Body }; Mock Activate-Window {}
      Mock Uia-Root { 'ROOT' }
      Mock Uia-Name { $script:title } -ParameterFilter { $el -eq 'ROOT' }
      Mock Send-Ctrl { $script:keys+=$vk; if($vk -eq 0x54){ $script:title='Новая вкладка' } elseif($vk -eq 0x57){ $script:title='Gemini' } }
      Mock Uia-Focused { 'FOC' }; Mock Uia-Class { $script:focusClass }
      Mock Use-TempClipboard { & $Body }; Mock Set-ClipText {}; Mock Paste {}
      Mock PressEnter { $script:title='Использование' }
      Mock Uia-FindAll { @('T1') } -ParameterFilter { $ControlType -eq 'Text' }
      Mock Uia-Name { 'Текущее использование | Использовано 28 % | Лимит обновится в 12:25 | Недельный лимит | Использовано 40 %' } -ParameterFilter { $el -eq 'T1' }
    }
    It 'фокус оказался в поле чата — исключение, НО вкладка закрыта (Ctrl+W) и адрес не вставлен' {
      $script:focusClass='ql-editor'
      { GemUia-GetUsageTextNewTab } | Should -Throw '*фокус в поле чата*'
      $script:keys | Should -Be @(0x54,0x4C,0x57)
      Should -Invoke Paste -Times 0
      $script:title | Should -Be 'Gemini'
    }
    It 'успех — текст лимитов получен, вкладка закрыта' {
      $t=GemUia-GetUsageTextNewTab
      $t | Should -Match 'Использовано 28'
      $script:keys | Should -Be @(0x54,0x4C,0x57)
    }
    It 'фокус не в адресной строке (поиск на «Табло» Яндекса) — адрес не вставлен, вкладка закрыта' {
      $script:focusClass='search-input'
      { GemUia-GetUsageTextNewTab } | Should -Throw '*не в адресной строке*'
      Should -Invoke Paste -Times 0; $script:keys | Should -Be @(0x54,0x4C,0x57)
    }
    It 'Яндекс Браузер: новая вкладка «Табло», поле адреса SmartboxEditField — лимиты прочитаны' {
      Mock Send-Ctrl { $script:keys+=$vk; if($vk -eq 0x54){ $script:title='Табло' } elseif($vk -eq 0x57){ $script:title='Gemini' } }
      $script:focusClass='SmartboxEditField'
      GemUia-GetUsageTextNewTab | Should -Match 'Использовано 28'
      $script:keys | Should -Be @(0x54,0x4C,0x57)
    }
    It 'вкладка не открылась (заголовок не изменился) — Ctrl+W НЕ нажимается (чтобы не закрыть чат)' {
      Mock Send-Ctrl { $script:keys+=$vk }
      { GemUia-GetUsageTextNewTab } | Should -Throw '*не открылась*'
      $script:keys | Should -Be @(0x54)
    }
    It 'чужая вкладка (заголовок не похож на лимиты) — не закрывает, пишет в лог' {
      Mock Send-Ctrl { $script:keys+=$vk; if($vk -eq 0x54){ $script:title='Новая вкладка' } }
      Mock PressEnter { $script:title='Какой-то сайт' }
      GemUia-GetUsageTextNewTab | Out-Null
      $script:keys | Should -Be @(0x54,0x4C)
      Should -Invoke Log -ParameterFilter { $m -like '*НЕ закрываю вкладку*' }
    }
  }
}
