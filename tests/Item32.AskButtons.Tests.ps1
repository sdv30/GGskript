BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
}
Describe 'Пункт 32: кнопки «Gemini: текст» и «Antigravity: текст»' -Tag Item32 {
  BeforeEach {
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList
    $script:TgPrompts.Clear(); $script:TgAwait=$null; $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:PendingConfirm=$null; $script:AgWatch=$null
    $Cfg.TgAwaitTextMin=10; $Cfg.AgReplyWaitMin=30; $Cfg.TgMaxLen=4096; $Cfg.StrictCommands=$true
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body }); @{ ok=$true; result=@{ message_id=1 } } }
  }
  It 'Gemini: кнопка просит текст, затем ставит в очередь gemask без вопроса «куда»' {
    Handle-Command '✨ Gemini: текст' 'tg'
    $script:TgAwait.direct | Should -BeTrue; $script:TgAwait.target | Should -Be 'gemini'
    Handle-Command 'Привет, проверь план' 'tg'
    $c=$script:Queue.Dequeue(); $c.k | Should -Be 'gemask'; $c.text | Should -Be 'Привет, проверь план'
    (Sent '*Куда переслать*').Count | Should -Be 0
  }
  It 'Antigravity: текст отправляется, ответ агента — новый отчёт — приходит в Telegram' {
    $dl=Join-Path $TestDrive 'dl32'; New-Item -ItemType Directory $dl -Force | Out-Null; $Cfg.Downloads=$dl
    Handle-Command 'Antigravity: текст' 'tg'; $script:TgAwait.target | Should -Be 'ag'
    Handle-Command 'сделай тесты' 'tg'
    $c=$script:Queue.Dequeue(); $c.k | Should -Be 'agask'
    Mock Assert-Quota {}; Mock Ag-Send {}
    Invoke-ChatAction $c
    Should -Invoke Ag-Send -Times 1 -ParameterFilter { $Text -eq 'сделай тесты' }
    $script:AgWatch | Should -Not -BeNullOrEmpty
    $f=Join-Path $dl 'report_099.md'; [IO.File]::WriteAllText($f,"Готово: тесты зелёные",[Text.Encoding]::UTF8)
    (Get-Item $f).LastWriteTime=(Get-Date).AddSeconds(-5); $script:AgWatch.since=(Get-Date).AddSeconds(-10)
    Mock Get-Files { @([pscustomobject]@{ Name='report_099.md'; FullName=$f; LastWriteTime=(Get-Date).AddSeconds(-5) }) }
    $script:AgWatchLast=(Get-Date).AddMinutes(-1); Check-AgWatch
    (Sent '*Ответ Antigravity*Готово: тесты зелёные*').Count | Should -Be 1
    $script:AgWatch | Should -BeNullOrEmpty
  }
  It 'отмена — ничего не отправляется' {
    Handle-Command 'Gemini: текст' 'tg'; Handle-Command 'отмена' 'tg'
    $script:Queue.Count | Should -Be 0
  }
  It 'статус в HTML экранирует угловые скобки' {
    $h=Format-StatusHtml "Состояние: жду <x>`nПауза: нет`n`nПоследние строки журнала:`na<b"
    $h | Should -Match '<b>Состояние:</b> жду &lt;x&gt;'; $h | Should -Match '<pre>a&lt;b</pre>'
  }
}
