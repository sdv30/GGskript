BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 56: любые имена проекта <Name>_YYYY-MM-DD_NNN.md' -Tag Item56 {
  It 'шаблон по умолчанию принимает любой префикс проекта' {
    $p=(Get-DefaultSettings -Root $TestDrive).Pattern
    foreach($n in 'Eskalator_2026-10-23_003.md','Arena_2026-10-22_024.md','AccessLab_2026-01-01_001.md','My-Proj.v2_2026-10-24_012.md','Проект_2026-10-24_007.md'){ $n | Should -Match $p }
    foreach($n in 'Eskalator_2026-10-23_03.md','Eskalator-2026-10-23-003.md','notes.md','Eskalator_2026-10-23_003.txt'){ $n | Should -Not -Match $p }
  }
  It 'ProjOf и номер берутся из имени' {
    ProjOf 'Eskalator_2026-10-23_003.md' | Should -Be 'Eskalator'
    (Get-SortKey 'Eskalator_2026-10-23_003.md' $Cfg.Pattern) | Should -BeLessThan (Get-SortKey 'Eskalator_2026-10-24_001.md' $Cfg.Pattern)
  }
  It 'Get-FileStage/Get-Files: отчёт Eskalator вчерашней даты находится (дата в имени ≠ сегодня — не помеха)' {
    $dl=Join-Path $TestDrive 'dl56'; New-Item -ItemType Directory $dl -Force | Out-Null; $Cfg.Downloads=$dl; $Cfg.MaxReportAgeHours=48
    'отчёт' | Set-Content (Join-Path $dl 'Eskalator_2026-10-23_003.md'); 'x' | Set-Content (Join-Path $dl 'readme.md')
    Mock Get-ActiveProjectNow { 'Eskalator' }; Mock Get-IgnoreBeforeDt { $null }; Mock Get-Stage { '' }
    @(Get-Files).Name | Should -Be @('Eskalator_2026-10-23_003.md')
    @(Get-Files -AllProjects).Name | Should -Contain 'Eskalator_2026-10-23_003.md'
  }
}