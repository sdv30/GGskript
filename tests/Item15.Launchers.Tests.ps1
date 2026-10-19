BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:R=Split-Path $PSScriptRoot -Parent
  function Get-Bytes($n){ [IO.File]::ReadAllBytes((Join-Path $script:R $n)) }
}
Describe 'Пункт 15: ярлыки .bat/.vbs (статическая проверка)' -Tag Item15 {
  It '<n>: без BOM, CRLF, первая строка — @echo off' -TestCases @(@{n='GGskript.bat'},@{n='GGskript_cmd.bat'},@{n='GGskript_exit.bat'}) {
    $b=Get-Bytes $n
    ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) | Should -BeFalse
    $t=[Text.Encoding]::UTF8.GetString($b)
    $t.Split("`n")[0].TrimEnd("`r") | Should -Be '@echo off'
    ([regex]::Matches($t,"(?<!`r)`n")).Count | Should -Be 0
  }
  It '<n>: до chcp 65001 нет не-ASCII байтов; пути через %~dp0' -TestCases @(@{n='GGskript.bat'},@{n='GGskript_cmd.bat'},@{n='GGskript_exit.bat'}) {
    $b=Get-Bytes $n; $t=[Text.Encoding]::UTF8.GetString($b)
    $firstNonAscii=-1; for($i=0;$i -lt $b.Length;$i++){ if($b[$i] -gt 127){ $firstNonAscii=$i; break } }
    if($firstNonAscii -ge 0){ $chcp=[Text.Encoding]::UTF8.GetByteCount($t.Substring(0,$t.IndexOf('chcp 65001'))); $chcp | Should -BeLessThan $firstNonAscii }
    if($t -match '(PAUSE|STOP|commands\.txt|GGskript\.ps1|launch\.vbs)'){ $t | Should -Match '%~dp0' }
  }
  It 'GGskript_cmd.bat: безопасная запись (echo( + отложенное раскрытие), пустой ввод не пишется' {
    $t=[Text.Encoding]::UTF8.GetString((Get-Bytes 'GGskript_cmd.bat'))
    $t | Should -Match 'setlocal EnableDelayedExpansion'
    $t | Should -Match 'set "CMD="'
    $t | Should -Match 'if not defined CMD goto :eof'
    $t | Should -Match '>>"%~dp0commands\.txt" echo\(!CMD!'
    $t | Should -Not -Match 'echo %CMD%'
  }
  It 'GGskript_launch.vbs: ASCII, скрытый запуск панели из своей папки' {
    $b=Get-Bytes 'GGskript_launch.vbs'; @($b | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    $t=[Text.Encoding]::ASCII.GetString($b)
    $t | Should -Match 'WScript\.ScriptFullName'; $t | Should -Match '-STA'; $t | Should -Match '-WindowStyle Hidden'; $t | Should -Match 'GGskript_gui\.ps1'; $t | Should -Match ', 0, False'
  }
}
Describe 'Пункт 15: кодировки commands.txt' -Tag Item15 {
  It 'UTF-8 без BOM' { @(ConvertFrom-CommandBytes ([Text.Encoding]::UTF8.GetBytes("статус`r`nпауза`r`n"))) | Should -Be @('статус','пауза') }
  It 'UTF-8 с BOM (Add-Content -Encoding UTF8 в PS 5.1)' { @(ConvertFrom-CommandBytes ([byte[]](0xEF,0xBB,0xBF)+[Text.Encoding]::UTF8.GetBytes("стоп`r`n"))) | Should -Be @('стоп') }
  It 'BOM посреди файла (несколько дописываний с BOM)' { $bom=[byte[]](0xEF,0xBB,0xBF); @(ConvertFrom-CommandBytes ($bom+[Text.Encoding]::UTF8.GetBytes("а`r`n")+$bom+[Text.Encoding]::UTF8.GetBytes("б`r`n"))) | Should -Be @('а','б') }
  It 'OEM 866 (cmd без chcp 65001)' { @(ConvertFrom-CommandBytes ((Get-Cp866).GetBytes("напиши джемини: привет`r`n"))) | Should -Be @('напиши джемини: привет') }
  It 'шум «ECHO is off» / «Режим вывода команд…» и пустые строки отбрасываются' {
    @(ConvertFrom-CommandBytes ([Text.Encoding]::UTF8.GetBytes("ECHO is off.`r`n`r`nРежим вывода команд на экран (ECHO) отключен.`r`nстатус`r`n"))) | Should -Be @('статус')
  }
  It 'пустой файл — пустой список' { @(ConvertFrom-CommandBytes ([byte[]]@())).Count | Should -Be 0 }
  It 'спецсимволы сохраняются как текст' { @(ConvertFrom-CommandBytes ([Text.Encoding]::UTF8.GetBytes("/ag a & b | c > d`r`n"))) | Should -Be @('/ag a & b | c > d') }
  It 'Read-CmdFile: забирает файл атомарно, выполняет строки, удаляет .proc' {
    [IO.File]::WriteAllBytes($Cfg.CmdFile,(Get-Cp866).GetBytes("статус`r`nпауза`r`n"))
    $script:got=@(); Mock Handle-Command { $script:got+="$Text|$Source" }; Mock Log {}
    Read-CmdFile
    $script:got | Should -Be @('статус|pc','пауза|pc')
    Test-Path $Cfg.CmdFile | Should -BeFalse; Test-Path "$($Cfg.CmdFile).proc" | Should -BeFalse
  }
}
Describe 'Пункт 15: GGskript_cmd.bat в настоящем cmd.exe' -Tag Item15,WindowsOnly {
  It 'текст со спецсимволами пишется дословно и не исполняется; пустой ввод не пишет ничего' {
    $d=Join-Path $TestDrive 'bat'; New-Item $d -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $script:R 'GGskript_cmd.bat') $d
    $bat=Join-Path $d 'GGskript_cmd.bat'
    [IO.File]::WriteAllText("$d\in.txt","status & echo HACKED > `"$d\pwn.txt`"`r`n")
    # ввод через конвейер cmd (как при наборе): Start-Process -RedirectStandardInput не доходит до set /p
    $null=& cmd.exe /c "type `"$d\in.txt`" | `"$bat`" 2>nul"
    Test-Path "$d\pwn.txt" | Should -BeFalse
    @(ConvertFrom-CommandBytes ([IO.File]::ReadAllBytes("$d\commands.txt"))) | Should -Be @("status & echo HACKED > `"$d\pwn.txt`"")
    Remove-Item "$d\commands.txt"
    Set-Content "$d\in.txt" -Value '' -NoNewline
    $null=& cmd.exe /c "type `"$d\in.txt`" | `"$bat`" 2>nul"
    Test-Path "$d\commands.txt" | Should -BeFalse
  }
}
