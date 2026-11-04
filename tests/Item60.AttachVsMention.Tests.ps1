BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 60: вложение vs упоминание имени файла' -Tag Item60 {
  BeforeEach { $Cfg.Pattern=(Get-DefaultSettings -Root $TestDrive).Pattern; $Cfg.MatchByContent=$true; $Cfg.ContentKeyChars=120; $Cfg.ContentKeyMin=40 }
  It 'CDP Whole: строка-имя / чип — attached=$true' {
    $r=Find-FileInTexts -Name 'Eskalator_2026-10-23_007.md' -Content 'x' -Texts @('привет','Eskalator_2026-10-23_007.md') -Whole
    $r.how | Should -Be 'name'; $r.attached | Should -BeTrue; $r.last | Should -BeTrue
    $r2=Find-FileInTexts -Name 'Eskalator_2026-10-23_007.md' -Content 'x' -Texts @('Eskalator_...-10-23_007') -Whole
    $r2.attached | Should -BeTrue
  }
  It 'CDP Whole: «Файл отчёта:» — attached' {
    (Find-FileInTexts -Name 'A_2026-10-20_001.md' -Content 'x' -Texts @("Файл отчёта: A_2026-10-20_001.md`nтекст") -Whole).attached | Should -BeTrue
  }
  It 'UIA: точное равенство Text — attached=$false (слабое); заголовок — true' {
    $r=Find-FileInTexts -Name 'A_2026-10-20_001.md' -Content 'x' -Texts @('другое','A_2026-10-20_001.md')
    $r.how | Should -Be 'name'; $r.attached | Should -BeFalse
    (Find-FileInTexts -Name 'A_2026-10-20_001.md' -Content 'x' -Texts @('Файл отчёта: A_2026-10-20_001.md')).attached | Should -BeTrue
  }
  It 'упоминание внутри фразы — не находим' {
    Find-FileInTexts -Name 'A_2.md' -Content 'x' -Texts @('В отчёте A_2.md вы пишете…') | Should -BeNullOrEmpty
  }
}