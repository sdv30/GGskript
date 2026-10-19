BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 14: единственный экземпляр (именованный мьютекс)' -Tag Item14 {
  It 'второй захват в другом процессе не удаётся, после освобождения — удаётся; Test-InstanceRunning видит владельца' {
    $name='Local\GGtest_'+[guid]::NewGuid().ToString('N')
    $plat=(Resolve-Path (Join-Path $PSScriptRoot '..\lib\Platform.Win.ps1')).Path
    $m=Enter-SingleInstance $name
    try{
      $m | Should -Not -BeNullOrEmpty
      $r=Start-Job -ScriptBlock { param($p,$n) . $p; $x=Enter-SingleInstance $n; $got=[bool]$x; Exit-SingleInstance $x; @{ got=$got; running=(Test-InstanceRunning $n) } } -ArgumentList $plat,$name | Wait-Job -Timeout 60 | Receive-Job
      $r.got | Should -BeFalse
      $r.running | Should -BeTrue
    } finally { Exit-SingleInstance $m }
    $r2=Start-Job -ScriptBlock { param($p,$n) . $p; $x=Enter-SingleInstance $n; $got=[bool]$x; Exit-SingleInstance $x; $got } -ArgumentList $plat,$name | Wait-Job -Timeout 60 | Receive-Job
    $r2 | Should -BeTrue
  }
  It 'никто не держит — Test-InstanceRunning=false' { Test-InstanceRunning ('Local\GGnone_'+[guid]::NewGuid().ToString('N')) | Should -BeFalse }
  It 'имена мьютексов — Local\ (сеанс пользователя), без имени пользователя в коде' { $Cfg.WorkerMutex | Should -Be 'Local\GGskript_Worker'; $Cfg.GuiMutex | Should -Be 'Local\GGskript_GUI' }
}
Describe 'Пункт 14: Read-LogTail' -Tag Item14 {
  BeforeEach { $script:lp=Join-Path $TestDrive ('l_{0}.txt' -f [guid]::NewGuid().ToString('N')) }
  It 'первый вызов — последние N байт с границы строки, без обрезанного символа' {
    $lines=1..3000 | ForEach-Object { "строка $_ кириллица" }; [IO.File]::WriteAllText($script:lp,($lines -join "`n")+"`n")
    $r=Read-LogTail $script:lp -1 2000
    $r.Text | Should -Match '^строка \d+ кириллица'
    $r.Text | Should -Match "строка 3000 кириллица`n$"
    $r.Text.IndexOf([char]0xFFFD) | Should -Be -1
    $r.Pos | Should -Be (Get-Item $script:lp).Length
  }
  It 'дальше — только новое; незавершённая строка ждёт перевода строки' {
    [IO.File]::WriteAllText($script:lp,"a`n"); $r=Read-LogTail $script:lp -1
    [IO.File]::AppendAllText($script:lp,"бб`nвв"); $r2=Read-LogTail $script:lp $r.Pos
    $r2.Text | Should -Be "бб`n"
    [IO.File]::AppendAllText($script:lp,"в`n"); (Read-LogTail $script:lp $r2.Pos).Text | Should -Be "ввв`n"
  }
  It 'файл стал короче (ротация) — читаем с начала' {
    [IO.File]::WriteAllText($script:lp,('x'*100)+"`n"); $r=Read-LogTail $script:lp -1
    [IO.File]::WriteAllText($script:lp,"новый`n"); (Read-LogTail $script:lp $r.Pos).Text | Should -Be "новый`n"
  }
  It 'файл открыт на запись другим кодом — читается; после чтения файл не заблокирован' {
    $w=[IO.File]::Open($script:lp,'Create','Write','ReadWrite'); $b=[Text.Encoding]::UTF8.GetBytes("лог`n"); $w.Write($b,0,$b.Length); $w.Flush()
    try{ (Read-LogTail $script:lp -1).Text | Should -Be "лог`n" } finally { $w.Dispose() }
    { Move-Item $script:lp "$($script:lp).1" } | Should -Not -Throw
  }
  It 'нет файла — пусто, без ошибки' { (Read-LogTail (Join-Path $TestDrive 'none.txt') -1).Text | Should -Be '' }
  It 'старый лог с BOM — BOM не попадает в текст' { [IO.File]::WriteAllText($script:lp,"старое`n",(New-Object Text.UTF8Encoding $true)); (Read-LogTail $script:lp -1).Text | Should -Be "старое`n" }
}
Describe 'Пункт 14: логика панели' -Tag Item14 {
  It 'воркер жив по мьютексу, даже если статус устарел' { Test-WorkerAlive -StatusPath (Join-Path $TestDrive 'none.json') -MutexName 'x' -MutexCheck { $true } | Should -BeTrue }
  It 'без мьютекса: свежий статус + живой pid — жив; устаревший/kind=stopped/мёртвый pid — нет' {
    $sp=Join-Path $TestDrive 'st.json'; $now=Get-Date
    [IO.File]::WriteAllText($sp,(@{ ts=$now.ToString('yyyy-MM-dd HH:mm:ss'); pid=$PID; kind='running' } | ConvertTo-Json))
    Test-WorkerAlive -StatusPath $sp -MutexName 'x' -MutexCheck { $false } -Now $now | Should -BeTrue
    Test-WorkerAlive -StatusPath $sp -MutexName 'x' -MutexCheck { $false } -Now $now.AddSeconds(30) | Should -BeFalse
    [IO.File]::WriteAllText($sp,(@{ ts=$now.ToString('yyyy-MM-dd HH:mm:ss'); pid=$PID; kind='stopped' } | ConvertTo-Json))
    Test-WorkerAlive -StatusPath $sp -MutexName 'x' -MutexCheck { $false } -Now $now | Should -BeFalse
    [IO.File]::WriteAllText($sp,(@{ ts=$now.ToString('yyyy-MM-dd HH:mm:ss'); pid=999999; kind='running' } | ConvertTo-Json))
    Test-WorkerAlive -StatusPath $sp -MutexName 'x' -MutexCheck { $false } -Now $now | Should -BeFalse
  }
  It 'Send-GuiCmd: одна строка, UTF-8 без BOM, пустое не пишет' {
    $cp=Join-Path $TestDrive 'cmd.txt'
    Send-GuiCmd $cp "/ag строка1`nстрока2" | Should -BeTrue; Send-GuiCmd $cp '   ' | Should -BeFalse
    $b=[IO.File]::ReadAllBytes($cp); $b[0] | Should -Not -Be 0xEF
    @(ConvertFrom-CommandBytes $b) | Should -Be @('/ag строка1 строка2')
  }
  It 'закрытие: спрашивать только при UserClosing' { Get-CloseAction 'UserClosing' | Should -Be 'ask'; Get-CloseAction 'WindowsShutDown' | Should -Be 'close'; Get-CloseAction 'TaskManagerClosing' | Should -Be 'close' }
  It 'автопрокрутка только если были в конце' { Test-AtEnd 100 101 | Should -BeTrue; Test-AtEnd 10 101 | Should -BeFalse }
  It 'вид статуса: остановлен/лимит, транспорт виден' {
    $v=Get-GuiStateView ([pscustomobject]@{ kind='limit'; state='x'; limitStop=$true; limitModel='Flash'; transport='Gemini=uia, AG=uia'; pending=@() })
    $v.Color | Should -Be 'Firebrick'; $v.Model | Should -Match 'лимит: Flash'; $v.Action | Should -Match 'Gemini=uia'
    (Get-GuiStateView ([pscustomobject]@{ kind='stopped'; state='' })).State | Should -Match 'остановлен'
  }
  It 'GGskript_gui.ps1: Local-мьютекс из настроек, CloseReason, AutoScale, $atEnd используется, Exit-SingleInstance в finally' {
    $src=Get-Content (Join-Path $PSScriptRoot '..\GGskript_gui.ps1') -Raw
    $src | Should -Not -Match 'Global\\GGskript_GUI'
    $src | Should -Match 'Enter-SingleInstance \$Cfg\.GuiMutex'
    $src | Should -Match 'Get-CloseAction'
    $src | Should -Match 'AutoScaleMode'
    $src | Should -Match 'if\(\$atEnd\)'
    $src | Should -Match 'finally \{ \$timer\.Stop\(\); \$timer\.Dispose\(\); Exit-SingleInstance \$mtx \}'
  }
}
