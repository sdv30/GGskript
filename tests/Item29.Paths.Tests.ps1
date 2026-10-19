# Пункт 29: проект можно переносить в любую папку — в коде, запускаторах и настройках нет жёстко прописанного пути проекта.
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:R=Split-Path $PSScriptRoot -Parent
  # что проверяем: код, запускаторы, настройки (служебные/исторические файлы — нет)
  $script:CodeExt=@('.ps1','.psm1','.psd1','.bat','.cmd','.vbs','.json')
  $script:SkipRx='[\\/](tools[\\/]Pester|tests[\\/]fixtures|_archive_[^\\/]*|answers|inbox|test-results|docs)[\\/]'
  function Get-CodeFiles{ @(Get-ChildItem -LiteralPath $script:R -Recurse -File -Force | Where-Object { $script:CodeExt -contains $_.Extension.ToLower() -and $_.FullName -notmatch $script:SkipRx }) }
  # шаблоны собраны из частей, чтобы этот файл не находил сам себя
  $script:Bad=@(
    @{ why='путь с буквой диска к папке GGskript'; rx=('(?i)\b[a-z]:[\\/][^\r\n"'']*'+'GG'+'skript') }
    @{ why='старая папка на рабочем столе';     rx=('(?i)Desk'+'top[\\/]+GG'+'skript') }
    @{ why='новая папка проекта';                  rx=('(?i)Anti'+'gavity[\\/]+GG'+'skript') }
  )
}
Describe 'Пункт 29: нет жёстко прописанного пути проекта' -Tag Item29 {
  It 'файлов кода и настроек найдено' { (Get-CodeFiles).Count | Should -BeGreaterThan 20 }
  It 'ни в одном файле кода/настроек нет абсолютного пути к проекту' {
    $hits=@()
    foreach($f in Get-CodeFiles){
      $t=[IO.File]::ReadAllText($f.FullName)
      foreach($b in $script:Bad){ foreach($m in [regex]::Matches($t,$b.rx)){ $hits+="$($f.FullName.Substring($script:R.Length+1)): $($b.why): $($m.Value)" } }
    }
    $hits -join "`n" | Should -BeNullOrEmpty
  }
  It 'все файлы состояния и служебные папки лежат в корне проекта (Get-DefaultSettings -Root)' {
    $root=Join-Path $TestDrive 'любая папка'
    $d=Get-DefaultSettings -Root $root -UserProfile (Join-Path $TestDrive 'profile')
    foreach($k in 'LogFile','TgOffsetFile','ConfigFile','PauseFile','StopFile','CmdFile','StatusFile','StateJson','TokenFile','SettingsFile','AnswerDir','ShutdownFile','InboxDir'){
      [string]$d[$k] | Should -BeLike ($root+'*') -Because $k
    }
    [string]$d.Downloads | Should -BeLike ((Join-Path $TestDrive 'profile')+'*')
  }
  It 'точки входа берут корень из своего расположения' {
    foreach($n in 'GGskript.ps1','GGskript_gui.ps1','Set-TgToken.ps1','Run-Tests.ps1'){ [IO.File]::ReadAllText((Join-Path $script:R $n)) | Should -Match '\$PSScriptRoot' -Because $n }
    foreach($n in 'GGskript.bat','GGskript_cmd.bat','GGskript_exit.bat'){ [IO.File]::ReadAllText((Join-Path $script:R $n)) | Should -Match '%~dp0' -Because $n }
    [IO.File]::ReadAllText((Join-Path $script:R 'GGskript_launch.vbs')) | Should -Match 'WScript\.ScriptFullName'
  }
  It 'Start-*.bat: профили браузера — в %LOCALAPPDATA%\GGskript, не в папке проекта' {
    foreach($n in 'Start-GeminiChrome.bat','Start-GeminiBrowser.bat'){ [IO.File]::ReadAllText((Join-Path $script:R $n)) | Should -Match 'set "PROFILE=%LOCALAPPDATA%\\GGskript\\' -Because $n }
  }
}
Describe 'Пункт 29: копия проекта в другой папке запускается' -Tag Item29,WindowsOnly {
  It 'GGskript.ps1 -testparse из папки с пробелом и кириллицей (Windows PowerShell 5.1)' {
    $dst=Join-Path $TestDrive 'Новая папка GG'
    New-Item -ItemType Directory -Force (Join-Path $dst 'lib') | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:R 'GGskript.ps1') -Destination $dst
    Copy-Item -Path (Join-Path $script:R 'lib\*.ps1') -Destination (Join-Path $dst 'lib')
    $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dst 'GGskript.ps1') -testparse 2>&1 | Out-String
    $LASTEXITCODE | Should -Be 0
    # кодировка вывода дочерней консоли зависит от ПК — проверяю только ASCII-часть
    $out | Should -Match '-> status'
    $out | Should -Match '-> gemini'
    $out | Should -Match '-> help'
    Test-Path -LiteralPath (Join-Path $dst 'relay_state.json') | Should -BeFalse   # -testparse ничего не пишет
  }
}
