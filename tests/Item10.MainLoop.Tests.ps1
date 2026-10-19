BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 10: классификация ошибок' -Tag Item10 {
  It 'типизированные исключения: <t> -> <k>' -TestCases @(
    @{t='GG.RelayStopException';k='stop'},@{t='GG.RelayLimitException';k='limit'},@{t='GG.RelayStaleException';k='stale'},
    @{t='GG.RelayNoCodeException';k='nocode'},@{t='GG.RelayPausedException';k='paused'},@{t='GG.RelayNotSentException';k='notsent'}
  ) { $e=New-Object $t 'x'; try{ throw $e }catch{ Get-ErrorKind $_ | Should -Be $k } }
  It 'GG.AgBlockedException -> agblock (подкласс NotSent, но своя ветка)' { try{ throw [GG.AgBlockedException]::new('hung','x','y') }catch{ Get-ErrorKind $_ | Should -Be 'agblock' } }
  It 'вложенное исключение (из .NET-вызова/скриптблока) распознаётся' {
    try{ & { throw [GG.RelayStopException]::new('стоп') } }catch{ $outer=New-Object System.Exception('обёртка',$_.Exception) }
    Get-ErrorKind $outer | Should -Be 'stop'
  }
  It 'текст «STOP» в чужом сообщении больше не означает остановку' { try{ throw 'Ошибка: STOP button not found' }catch{ Get-ErrorKind $_ | Should -Be 'error' } }
  It 'совместимость со старыми сигналами throw ''STOP''/''LIMIT''/''OLDANSWER''' {
    try{ throw 'STOP' }catch{ Get-ErrorKind $_ | Should -Be 'stop' }
    try{ throw 'OLDANSWER' }catch{ Get-ErrorKind $_ | Should -Be 'stale' }
  }
}
Describe 'Пункт 10: Invoke-MainStep' -Tag Item10 {
  BeforeEach {
    $Cfg.QuotaEveryMin=0; $Cfg.AgQueueCheckSec=0; $Cfg.AcceptAllEverySec=0; $Cfg.RetrySec=20
    $script:NeedStart=$false; $script:LimitStop=$false; $script:Paused=$false; $script:Queue.Clear(); $script:Busy=$false
    Mock Pump {}; Mock Nap {}; Mock Check-Blocking {}; Mock Quota-Blocked { $null }; Mock Write-Host {}; Mock Log {}; Mock Notify {}; Mock Tg-Send { $true }
    Mock Next-File { [pscustomobject]@{ Name='A_001.md' } }; Mock Process-File {}
    Remove-Item $Cfg.StopFile -EA 0
  }
  It 'файл STOP — ''stop'' и файл удалён' { New-Item $Cfg.StopFile -ItemType File | Out-Null; Invoke-MainStep | Should -Be 'stop'; Test-Path $Cfg.StopFile | Should -BeFalse }
  It 'обычный шаг — обрабатывает файл и возвращает ''ok''' { Invoke-MainStep | Should -Be 'ok'; Should -Invoke Process-File -Times 1 }
  It 'Stop из глубины обработки — ''stop'' (Remove-Item STOP без ошибки, даже если файла нет)' { Mock Process-File { throw [GG.RelayStopException]::new('стоп') }; Invoke-MainStep | Should -Be 'stop' }
  It 'Limit — без «❌ ОШИБКА» и без ожидания повтора' { Mock Process-File { throw [GG.RelayLimitException]::new('модель') }; Invoke-MainStep | Should -Be 'continue'; Should -Invoke Notify -Times 0; Should -Invoke Nap -Times 0 }
  It 'Paused — тихо' { Mock Process-File { throw [GG.RelayPausedException]::new('пауза') }; Invoke-MainStep | Should -Be 'ok'; Should -Invoke Notify -Times 0 }
  It 'прочая ошибка — уведомление и ожидание RetrySec по 10 с' { Mock Process-File { throw 'сломалось' }; Invoke-MainStep | Should -Be 'ok'; Should -Invoke Notify -Times 1 -ParameterFilter { $Text -like '*сломалось*' }; Should -Invoke Nap -Times 2 -ParameterFilter { $sec -eq 10 } }
  It 'STOP во время ожидания повтора — ''stop''' { Mock Process-File { throw 'сломалось' }; Mock Nap { throw [GG.RelayStopException]::new('стоп') }; Invoke-MainStep | Should -Be 'stop' }
  It 'ошибка команды из очереди — сообщение «Команда не выполнена», цикл продолжается' {
    $script:Queue.Enqueue(@{k='ag';arg='x'}); Mock Run-Action { throw 'нет окна' }
    Invoke-MainStep | Should -Be 'continue'; Should -Invoke Tg-Send -ParameterFilter { $Text -like '❌ Команда не выполнена: нет окна' }; $script:Busy | Should -BeFalse
  }
  It 'пауза: файлы не обрабатываются' { $script:Paused=$true; Invoke-MainStep | Should -Be 'ok'; Should -Invoke Process-File -Times 0 }
  It '«/ag» на паузе не отправляется в Antigravity' {
    $script:Paused=$true; Mock Ag-Send {}; $script:Queue.Enqueue(@{k='ag';arg='x'})
    Invoke-MainStep | Out-Null; Should -Invoke Ag-Send -Times 0; Should -Invoke Tg-Send -ParameterFilter { $Text -like '⏹*СТОП*' }
  }
  It 'Wait-And-Copy (мёртвый код) удалён' { Get-Command Wait-And-Copy -EA 0 | Should -BeNullOrEmpty }
}
Describe 'Пункт 10: GGskript.ps1 — финальное уведомление об остановке с -Force' -Tag Item10 {
  It 'в finally: Notify ... -Force и Exit-SingleInstance' {
    $src=Get-Content (Join-Path $PSScriptRoot '..\GGskript.ps1') -Raw
    $src | Should -Match "Notify 'остановлен\.' -Force"
    $src | Should -Match 'Exit-SingleInstance \$script:WorkerMutexObj'
  }
}
Describe 'Пункт 10: GGskript.ps1 -testparse в отдельном процессе (без WinAPI и Downloads)' -Tag Item10,WindowsOnly {
  It 'запускается, разбирает фразы, опасные — unknown' {
    $exe=(Get-Process -Id $PID).Path
    $out=& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\GGskript.ps1') -testparse 2>&1 | Out-String
    $LASTEXITCODE | Should -Be 0
    $out | Should -Match 'принял, спасибо\s+-> unknown'
    $out | Should -Match 'передай всё равно\s+-> force'
    $out | Should -Match '/ag тест\s+-> ag'
  }
}
