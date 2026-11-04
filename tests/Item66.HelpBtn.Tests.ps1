# 04.11: кнопка «❓ Помощь» открывает docs\HELP.txt (запасной вариант README.md) в Блокноте и шлёт «помощь» в Telegram.
BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1') }
Describe 'Item66 кнопка Помощь' -Tag 'Item66' {
  It 'Get-HelpDocPath: есть docs\HELP.txt — берёт его' {
    New-Item -ItemType Directory (Join-Path $TestDrive 'a\docs') -Force | Out-Null
    Set-Content (Join-Path $TestDrive 'a\docs\HELP.txt') 'x'; Set-Content (Join-Path $TestDrive 'a\README.md') 'y'
    Get-HelpDocPath (Join-Path $TestDrive 'a') | Should -Be (Join-Path (Join-Path $TestDrive 'a') 'docs\HELP.txt')
  }
  It 'Get-HelpDocPath: нет HELP.txt — README.md' {
    New-Item -ItemType Directory (Join-Path $TestDrive 'b') -Force | Out-Null; Set-Content (Join-Path $TestDrive 'b\README.md') 'y'
    Get-HelpDocPath (Join-Path $TestDrive 'b') | Should -Be (Join-Path (Join-Path $TestDrive 'b') 'README.md')
  }
  It 'Get-HelpDocPath: ничего нет — $null' {
    New-Item -ItemType Directory (Join-Path $TestDrive 'c') -Force | Out-Null
    Get-HelpDocPath (Join-Path $TestDrive 'c') | Should -BeNullOrEmpty
  }
  It 'обработчик кнопки: Блокнот + команда «помощь» в Telegram' {
    $g=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\GGskript_gui.ps1'),[Text.Encoding]::UTF8)
    $g | Should -Match '\$btnHelp\.Add_Click\(\{[^\r\n]*Get-HelpDocPath[^\r\n]*notepad\.exe[^\r\n]*Send-Cmd ''помощь'''
  }
  It 'в репозитории есть docs\HELP.txt в UTF-8 с BOM' {
    $b=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..\docs\HELP.txt'))
    ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue
  }
}
