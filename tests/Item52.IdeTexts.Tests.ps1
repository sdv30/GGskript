BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 52: надписи панели по выбранной IDE' -Tag Item52 {
  It 'Antigravity — прежние надписи' {
    $x=Get-IdeTexts 'antigravity' 9333 9334
    $x.Fwd | Should -Be '📂 Ответ в Antigravity'; $x.AgT | Should -Be '🛠 Antigravity: текст'; $x.Cdp | Should -Be '🛠 Antigravity с портом'
    $x.Auto | Should -Be 'Автоподтверждение запросов Antigravity'; $x.Port | Should -Be 9333; $x.MenuHead | Should -Be 'ANTIGRAVITY'
  }
  It 'DeepSeek Harness — ни одной надписи с «Antigravity» (кроме подсказки выбора)' {
    $x=Get-IdeTexts 'dsharness' 9333 9334
    $x.Fwd | Should -Be '📂 Ответ в Harness'; $x.AgT | Should -Be '🛠 Harness: текст'; $x.Cdp | Should -Be '🛠 Harness с портом'; $x.Port | Should -Be 9334; $x.Acc | Should -Be 'Автопринятие «Принять все»'
    foreach($k in @($x.Keys)){ if($k -ne 'TileTip'){ [string]$x[$k] | Should -Not -Match 'Antigravity' } }
  }
  It 'Get-BtnPlainText отрезает эмодзи' { Get-BtnPlainText '🛠 Harness: текст' | Should -Be 'Harness: текст'; Get-BtnPlainText 'Просто' | Should -Be 'Просто' }
  It 'лимиты на панели: Harness — «квота не публикуется»' {
    Format-GuiLimits ([pscustomobject]@{ ide='dsharness'; ideName='DeepSeek Harness'; agH5=100 }) | Should -Match 'DeepSeek Harness: квота не публикуется'
    Format-GuiLimits ([pscustomobject]@{ agH5=50; agH5Reset='1'; agWk=40; agWkReset='2' }) | Should -Match 'Antigravity: 5ч ост. 50%'
  }
}
Describe 'Пункт 52: Telegram и команды по IDE' -Tag Item52 {
  AfterEach { $Cfg.AgTarget='antigravity' }
  It 'клавиатура Telegram переключается и возвращается' {
    $Cfg.AgTarget='dsharness'; $l=Get-TgReplyLabels; $l | Should -Contain '📂 Ответ в Harness'; $l | Should -Contain '🛠 Harness: текст'; ($l -join '|') | Should -Not -Match 'Antigravity'
    (@(Get-TgMenuCommands).description -join '|') | Should -Not -Match 'Antigravity'
    $Cfg.AgTarget='antigravity'; Get-TgReplyLabels | Should -Contain '📂 Ответ в Antigravity'
  }
  It 'кнопки Harness распознаются как команды' {
    (Parse-Command '🛠 Harness: текст').k | Should -Be 'agwrite'; (Parse-Command '📂 Ответ в Harness').k | Should -Be 'fwdans'
    (Parse-Command 'Ответ в Antigravity').k | Should -Be 'fwdans'
  }
  It 'панель: старой строки IDE/комбобокса нет, плитка — выбор IDE' {
    $g=Get-Content (Join-Path $script:V2Root 'GGskript_gui.ps1') -Raw -Encoding UTF8
    $g | Should -Not -Match 'cmbIde'; $g | Should -Not -Match "Add-BtnRow 'IDE'"; $g | Should -Match 'ideMenu'; $g | Should -Match 'Test-IdeChangeAllowed'
  }
}
