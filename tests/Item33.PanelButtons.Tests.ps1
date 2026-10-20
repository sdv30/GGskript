BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 33: кнопки панели ПК (/pc_…) и меню «Ещё»' -Tag Item33 {
  BeforeEach {
    $script:TgToken=''; $script:TgChat=''; $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:TgAwait=$null
    $script:Logs=New-Object System.Collections.ArrayList
    Mock Log { [void]$script:Logs.Add($m) }
  }
  It 'Gemini: текст — base64, многострочный текст доходит целиком, источник pc' {
    $t="строка 1`nстрока 2 ✨"; $b=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t))
    Handle-Command "/pc_gemask b64:$b" 'pc'
    $c=$script:Queue.Dequeue(); $c.k | Should -Be 'gemask'; $c.text | Should -Be $t; $c.src | Should -Be 'pc'
  }
  It 'Antigravity: текст — в очередь agask' {
    Handle-Command ('/pc_agask b64:'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('сделай'))) 'pc'
    $script:Queue.Dequeue().k | Should -Be 'agask'
  }
  It 'пустой текст и Telegram-источник не исполняются как кнопки панели' {
    Handle-Command '/pc_gemask b64:' 'pc'; $script:Queue.Count | Should -Be 0
    Mock Tg-Send { $true }; Mock New-TgPrompt { $true }; Mock Start-ForwardConfirm {}
    try{ Handle-Command '/pc_toag' 'tg' }catch{}; @($script:Queue.ToArray() | Where-Object { $_.k -eq 'fwdans-pc' }).Count | Should -Be 0
  }
  It 'Ответ в Antigravity / Ответ Gemini — в очередь; в режиме СТОП — нет' {
    Handle-Command '/pc_toag' 'pc'; $script:Queue.Dequeue().k | Should -Be 'fwdans-pc'
    Handle-Command '/pc_answer' 'pc'; $script:Queue.Dequeue().k | Should -Be 'lastanswer'
    $script:Paused=$true; Handle-Command '/pc_answer' 'pc'; $script:Queue.Count | Should -Be 0
  }
  It 'fwdans-pc — окно-команда (в СТОП не выполняется)' { $script:WindowKinds | Should -Contain 'fwdans-pc' }
  It 'панель: 11 кнопок как в Telegram, меню «Ещё» с остальными командами, флажок виден' {
    $g=Get-Content (Join-Path $PSScriptRoot '..\GGskript_gui.ps1') -Raw -Encoding UTF8
    foreach($x in '📂 Отчёт в Gemini','📂 Ответ в Antigravity','🛠 Antigravity: текст','✨ Gemini: текст','✨ Ответ Gemini','ℹ️ Статус','⏸ Стоп','▶️ Старт','📸 Скрин','📊 Лимиты','❓ Помощь','☰ Ещё'){ $g | Should -Match ([regex]::Escape("New-Btn '$x")) }
    foreach($x in 'Accept all','Передать ответ','Передать всё равно','Автоподтверждение','Список авто-закрываемых окон','Отменить выключение','Открыть папку проекта','Выключить скрипт'){ $g | Should -Match ([regex]::Escape($x)) }
    $g | Should -Match 'ContextMenuStrip'; $g | Should -Match 'Add-BtnRow .+\$chkAuto'
  }
}
