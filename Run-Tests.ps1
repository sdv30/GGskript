# Запуск юнит-тестов GGskript v2.  Пример: .\Run-Tests.ps1            (все)
#                                          .\Run-Tests.ps1 -Tag Item06 (один пункт плана)
#                                          .\Run-Tests.ps1 -Safe       (только тесты без побочных эффектов — для ПК пользователя)
param([string[]]$Tag,[switch]$Safe,[string]$PesterPath,[string]$OutXml)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
if(-not $PesterPath){ $loc=Get-ChildItem (Join-Path $PSScriptRoot 'tools\Pester') -Recurse -Filter Pester.psd1 -EA 0 | Select-Object -First 1; if($loc){ $PesterPath=$loc.FullName } }   # необязательная локальная копия Pester (в git не входит), иначе — установленный модуль
if($PesterPath){ Import-Module $PesterPath -Force } else { Import-Module Pester -MinimumVersion 5.5 -MaximumVersion 5.99 -Force }
$c=New-PesterConfiguration
$c.Run.Path=(Join-Path $here 'tests')
$c.Run.PassThru=$true
$c.Output.Verbosity='Detailed'
if($Tag){ $c.Filter.Tag=$Tag }
$ex=@()
if($Safe){ $ex+='Integration','LinuxOnly' }
if($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows){ $ex+='LinuxOnly' } else { $ex+='WindowsOnly' }
$c.Filter.ExcludeTag=@($ex | Select-Object -Unique)
if($OutXml){ $c.TestResult.Enabled=$true; $c.TestResult.OutputPath=$OutXml }
$r=Invoke-Pester -Configuration $c
"ИТОГО: всего $($r.TotalCount), пройдено $($r.PassedCount), упало $($r.FailedCount), пропущено $($r.SkippedCount + $r.NotRunCount)"
if($r.FailedCount -gt 0){ exit 1 }
