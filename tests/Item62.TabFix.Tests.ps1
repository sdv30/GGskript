BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe '25.10 tabfix: вкладка Gemini, проект с пробелом, чужой чат, факт IDE' -Tag Item62 {
  BeforeEach { $Cfg.Pattern=(Get-DefaultSettings -Root $TestDrive).Pattern; $Cfg.CdpUrlLike='gemini.google.com' }

  It 'имя проекта с пробелом: «Fishka 2_…_006.md» -> Fishka 2 (при известном проекте)' {
    $r=Get-AskedReportFromText 'Write report to C:\D\Fishka 2_2026-10-25_006.md now' $Cfg.Pattern -Known @('Fishka 2','Arena')
    $r.project | Should -Be 'Fishka 2'; $r.step | Should -Be 6
    (Get-AskedReportFromText 'Пришлите Eskalator_2026-10-23_007.md' $Cfg.Pattern -Known @('Fishka 2')).project | Should -Be 'Eskalator'
    (Get-AskedReportFromText 'x Fishka 2_2026-10-25_006.md' $Cfg.Pattern).project | Should -Be '2'   # без списка — как раньше
  }
  It 'Get-BlockAsk берёт известные проекты из $script:KnownProjects' {
    $script:KnownProjects=@('Fishka 2'); try{ (Get-BlockAsk "ROLE`nWrite report to C:\D\Fishka 2_2026-10-25_007.md" $Cfg.Pattern).project | Should -Be 'Fishka 2' } finally { $script:KnownProjects=@() }
  }
  It 'Test-SameProject: «2» == «Fishka 2», «Arena» != «Fishka 2»' {
    Test-SameProject '2' 'Fishka 2' | Should -BeTrue
    Test-SameProject 'Fishka 2' 'fishka 2' | Should -BeTrue
    Test-SameProject 'Arena' 'Fishka 2' | Should -BeFalse
    Test-SameProject '' 'Fishka 2' | Should -BeFalse
  }
  It 'миграция учёта: lastBlock и sent «2» -> «Fishka 2», чужие не трогает' {
    $s=[pscustomobject]@{ lastBlock=[pscustomobject]@{ project='2'; step=6 }; sent=@('ag|2|6|aaaa','gem|Fishka 2|5|bbbb','ag|Arena|3|cccc','ag||-1|dddd') }
    Repair-StateProjectNames $s @('Fishka 2','Arena') | Should -Be 2
    $s.lastBlock.project | Should -Be 'Fishka 2'
    $s.sent | Should -Contain 'ag|Fishka 2|6|aaaa'; $s.sent | Should -Contain 'ag|Arena|3|cccc'; $s.sent | Should -Contain 'ag||-1|dddd'
    Repair-StateProjectNames $s @('Arena') | Should -Be 0
  }
  It 'очередь: lastBlock «2»/S6 + отчёт 006 -> ход по номеру шага, не «без номера»' {
    $st=New-RelayState; Add-SentRecord $st 'ag' 'Fishka 2' 6 'h6'
    $hdr=@{ project='Fishka 2'; step=6; rework=$false }
    $rep=[pscustomobject]@{ Name='Fishka 2_2026-10-25_006.md'; Num=6; Project='Fishka 2'; Time=(Get-Date) }
    $d=Get-TurnDecision -Header $hdr -Report $rep -State $st -LastAgAt (Get-Date).AddMinutes(-10)
    $d.formatBroken | Should -BeFalse; $d.step | Should -Be 6
  }
  It 'чат Gemini: есть ли отчёты проекта' {
    Test-ChatHasProjectReports @('привет','Fishka 2_2026-10-25_004 Ваш запрос') 'Fishka 2' | Should -BeTrue
    Test-ChatHasProjectReports @('Arena_2026-10-25_066') 'Fishka 2' | Should -BeFalse
    Test-ChatHasProjectReports @('MyFishka 2_2026-10-25_004') 'Fishka 2' | Should -BeFalse
    Test-ChatHasProjectReports @() 'Fishka 2' | Should -BeFalse
  }
  It 'выбор вкладки: несколько /app — по фокусу/видимости/Argon, а не первая в списке' {
    $l=@(
      [pscustomobject]@{ id='A'; type='page'; url='https://gemini.google.com/u/1/app/x' },
      [pscustomobject]@{ id='U'; type='page'; url='https://gemini.google.com/u/1/usage' },
      [pscustomobject]@{ id='B'; type='page'; url='https://gemini.google.com/u/0/app/y' })
    $r=Select-GeminiChatTarget $l @{ A=@{ vis=$true; focus=$false; argon=$false; proj=$true }; B=@{ vis=$true; focus=$false; argon=$true; proj=$true } }
    $r.target.id | Should -Be 'B'; $r.ambiguous | Should -BeFalse
    (Select-GeminiChatTarget $l @{ A=@{ vis=$true; focus=$true }; B=@{ vis=$true; argon=$true } }).target.id | Should -Be 'A'
    (Select-GeminiChatTarget $l @{}).ambiguous | Should -BeTrue
    (Select-GeminiChatTarget @($l[0],$l[1])).target.id | Should -Be 'A'
  }
  It 'вкладка лимитов — того же аккаунта, что чат' {
    $l=@([pscustomobject]@{ id='U1'; type='page'; url='https://gemini.google.com/u/1/usage' },[pscustomobject]@{ id='U0'; type='page'; url='https://gemini.google.com/usage' })
    (Select-GeminiUsageTarget $l 'https://gemini.google.com/u/0/app/y').id | Should -Be 'U0'
    (Select-GeminiUsageTarget $l 'https://gemini.google.com/u/1/app/x').id | Should -Be 'U1'
    Select-GeminiUsageTarget @($l[0]) 'https://gemini.google.com/app/z' | Should -BeNullOrEmpty
    Get-GeminiAccountIndex 'https://gemini.google.com/u/2/app' | Should -Be 2
    Get-GeminiAccountIndex 'https://gemini.google.com/app' | Should -Be 0
    $script:CdpLastUrl='https://gemini.google.com/u/1/app/x'; try{ Get-GeminiUsageUrl | Should -Be 'https://gemini.google.com/u/1/usage' } finally { $script:CdpLastUrl='' }
  }
  It 'чужой чат: нет отчётов проекта -> причина; шаг 001 и resend — не блокирую' {
    $Cfg.ForeignChatGuard=$true; $Cfg.GeminiTransport='cdp'; $script:St=New-RelayState
    try{
      Mock GemCdp-PromptTexts { @('Arena_2026-10-25_066 текст') }
      Test-ForeignGeminiChat 'Fishka 2_2026-10-25_006.md' | Should -Match 'чужой чат'
      $script:GemForeign | Should -BeTrue
      Test-ForeignGeminiChat 'Fishka 2_2026-10-25_001.md' | Should -BeNullOrEmpty
      Mock GemCdp-PromptTexts { @() }
      Test-ForeignGeminiChat 'Fishka 2_2026-10-25_006.md' | Should -Match 'пустой'
      Mock GemCdp-PromptTexts { @('Fishka 2_2026-10-25_005 x') }
      Test-ForeignGeminiChat 'Fishka 2_2026-10-25_006.md' | Should -BeNullOrEmpty
      $script:GemForeign | Should -BeFalse
      Mock GemCdp-PromptTexts { throw 'нет связи' }
      Test-ForeignGeminiChat 'Fishka 2_2026-10-25_006.md' | Should -BeNullOrEmpty
    } finally { $Cfg.ForeignChatGuard=$false; $Cfg.GeminiTransport='uia'; $script:GemForeign=$false }
  }
  It 'факт IDE: агент работает -> ход IDE; выключено/не CDP -> $null' {
    $Cfg.TurnByAgFact=$true; $Cfg.AgTransport='cdp'; $Cfg.AgTarget='antigravity'; $script:AgFactAt=[datetime]::MinValue
    try{
      Mock AgCdp-IsBusy { $true }
      (Get-AgFactNow).busy | Should -BeTrue
      $Cfg.AgTransport='uia'; $script:AgFactAt=[datetime]::MinValue
      Get-AgFactNow | Should -BeNullOrEmpty
    } finally { $Cfg.TurnByAgFact=$false; $Cfg.AgTransport='uia'; $script:AgFactAt=[datetime]::MinValue }
  }
  It 'настройки по умолчанию включены' {
    $d=Get-DefaultSettings -Root $TestDrive
    $d.GemTabProbe | Should -BeTrue; $d.ForeignChatGuard | Should -BeTrue; $d.TurnByAgFact | Should -BeTrue; $d.GemTabRecheckSec | Should -BeGreaterThan 0
  }
}