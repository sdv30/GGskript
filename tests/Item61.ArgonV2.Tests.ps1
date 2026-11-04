# Пункт 61: Argon v2 маркеры — step id + «конец задания»; акт junior; legacy совместим.
BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1'); $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg; Mock Log {}; Mock Tg-Send {}
}
Describe 'Item61 Argon v2 markers' -Tag 'Item61' {
  It 'Get-PromptHeader: legacy [ARGON>FLASH] [Project] [SNNN]' {
    $h=Get-PromptHeader "[ARGON>FLASH] [Arena] [S006] [2026-10-20]`nbody"
    $h.project | Should -Be 'Arena'; $h.step | Should -Be 6; $h.from | Should -Be 'header'
  }
  It 'Get-PromptHeader: step id Project_YYYY-MM-DD_NNN' {
    $h=Get-PromptHeader "Eskalator_2026-10-24_008`n<role>DevOps</role>"
    $h.project | Should -Be 'Eskalator'; $h.step | Should -Be 8; $h.from | Should -Be 'stepid'; $h.date | Should -Be '2026-10-24'
  }
  It 'Get-PromptHeader: step id with .md still parses' {
    $h=Get-PromptHeader "Arena_2026-10-20_012.md`nx"
    $h.project | Should -Be 'Arena'; $h.step | Should -Be 12
  }
  It 'Test-BlockStepTags: v2 ok when step id + конец задания + matching report name' {
    $code=@(
      'Eskalator_2026-10-24_008'
      '<role>Senior DevOps</role>'
      'do the work'
      'конец задания'
      'Сформулируй отчет Eskalator_2026-10-24_008.md'
    ) -join "`n"
    $t=Test-BlockStepTags $code 7
    $t.tagged | Should -BeTrue; $t.ok | Should -BeTrue; $t.style | Should -Be 'v2'; $t.end | Should -Be 8
  }
  It 'Test-BlockStepTags: v2 fails when report NNN mismatches step id' {
    $code="Eskalator_2026-10-24_008`nbody`nконец задания`nСформулируй отчет Eskalator_2026-10-24_009.md"
    $t=Test-BlockStepTags $code 7
    $t.tagged | Should -BeTrue; $t.ok | Should -BeFalse; $t.reason | Should -Match '009|008'
  }
  It 'Test-BlockStepTags: legacy [[END SNNN]] still ok' {
    $code="[ARGON>FLASH] [Arena] [S006] [2026-10-20]`n<role>x</role>`n[[END S006]]"
    $t=Test-BlockStepTags $code 5
    $t.tagged | Should -BeTrue; $t.ok | Should -BeTrue; $t.style | Should -Be 'legacy'
  }
  It 'Get-BlockAsk prefers step id over bare filename mention' {
    $code="Eskalator_2026-10-24_008`nplease also see Other_2026-10-01_001.md later`nконец задания`nСформулируй отчет Eskalator_2026-10-24_008.md"
    $a=Get-BlockAsk $code $Cfg.Pattern
    $a.project | Should -Be 'Eskalator'; $a.step | Should -Be 8; $a.from | Should -Be 'stepid'
  }
  It 'Get-JuniorActDone extracts name and path' {
    $a=Get-JuniorActDone "Краткий акт.`n`nОтчет Eskalator_2026-10-24_008.md создан и лежит в папке C:\Users\user\Downloads"
    $a.ok | Should -BeTrue
    $a.name | Should -Be 'Eskalator_2026-10-24_008.md'
    $a.path | Should -Match 'Downloads'
  }
  It 'Get-JuniorActDone: missing phrase -> null' {
    Get-JuniorActDone 'просто текст без финальной фразы' | Should -BeNullOrEmpty
  }
  It 'Enter-LimitStop telegram text mentions лимит Argon закончен' {
    $script:LimitStop=$false; $script:LimitTg=@()
    Mock Tg-Send { param([string]$Text) $script:LimitTg += $Text; 1 }
    Mock Log {}; Mock Play-Sound {}
    Enter-LimitStop 'FlashLite' 'тест: вложение не шлём'
    $script:LimitStop | Should -BeTrue
    ($script:LimitTg -join "`n") | Should -Match 'лимит Argon закончен'
    ($script:LimitTg -join "`n") | Should -Match 'FlashLite'
    ($script:LimitTg -join "`n") | Should -Match 'переключена'
  }
}