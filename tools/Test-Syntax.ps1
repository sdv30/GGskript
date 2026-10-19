# Проверка синтаксиса всех .ps1 через парсер PowerShell и наличия UTF-8 BOM (нужен Windows PowerShell 5.1 для кириллицы).
param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$bad=0; $n=0
# (в PS 5.1 -Include с -LiteralPath не работает — фильтруем сами; сторонний Pester в tools\Pester не проверяем)
Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { @('.ps1','.psm1') -contains $_.Extension.ToLower() -and $_.FullName -notmatch '[\\/]tools[\\/]Pester[\\/]' } | ForEach-Object {
  $n++
  $b=[IO.File]::ReadAllBytes($_.FullName)
  $bom=($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tok,[ref]$err)
  $rel=$_.FullName.Substring($Root.Length).TrimStart('\','/')
  if(-not $bom){ $bad++; "НЕТ BOM: $rel" }
  foreach($e in @($err)){ if($e){ $bad++; "ОШИБКА: $rel $($e.Extent.StartLineNumber): $($e.Message)" } }
}
"Файлов: $n, проблем: $bad (PowerShell $($PSVersionTable.PSVersion))"
if($bad){ exit 1 }
