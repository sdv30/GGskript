BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function New-AgResp($buckets){ [pscustomobject]@{ response=[pscustomobject]@{ groups=@([pscustomobject]@{ displayName='Gemini Models'; buckets=$buckets }) } } }
}
Describe 'Пункт 12: ConvertFrom-UsageText (страница лимитов Gemini)' -Tag Item12 {
  It 'русская страница в одну строку через |' {
    $r=ConvertFrom-UsageText 'Лимиты | Текущее использование | Использовано 37 % | Лимит обновится в 18:40 | Недельный лимит | Использовано 12% | Лимит обновится 21 окт.'
    $r.cur | Should -Be 37; $r.wk | Should -Be 12; $r.curReset | Should -Be 'Лимит обновится в 18:40'; $r.wkReset | Should -Be 'Лимит обновится 21 окт.'; $r.exhausted | Should -BeFalse
  }
  It 'английская страница построчно (CRLF)' {
    $r=ConvertFrom-UsageText "Usage`r`nCurrent usage`r`nUsed 5%`r`nResets at 6:40 PM`r`nWeekly limit`r`nUsed 81%`r`nResets Oct 21"
    $r.cur | Should -Be 5; $r.wk | Should -Be 81; $r.curReset | Should -Be 'Resets at 6:40 PM'
  }
  It 'текущий лимит исчерпан и процента нет — cur=100, exhausted' {
    $r=ConvertFrom-UsageText 'Вы достигли лимита. Лимит исчерпан до 18:40'
    $r.cur | Should -Be 100; $r.exhausted | Should -BeTrue
  }
  It 'есть недельный, но текущий без процента и «исчерпан» — cur=100' { (ConvertFrom-UsageText 'Текущее использование | лимит исчерпан | Недельный лимит | Использовано 50%').cur | Should -Be 100 }
  It 'мусор/страница входа — исключение (а не «0 %»)' { { ConvertFrom-UsageText 'Войдите в аккаунт Google' } | Should -Throw '*не удалось прочитать*'; { ConvertFrom-UsageText '' } | Should -Throw }
}
Describe 'Пункт 12: ConvertFrom-AgQuota (Antigravity)' -Tag Item12 {
  BeforeAll { $script:now=[datetime]::new(2026,10,18,3,0,0,[DateTimeKind]::Utc) }
  It 'обычный ответ: остаток в % и время сброса' {
    $r=ConvertFrom-AgQuota -Response (New-AgResp @([pscustomobject]@{window='5h';remainingFraction=0.42;resetTime='2026-10-18T05:00:00Z'},[pscustomobject]@{window='week';remainingFraction=0.9;resetTime='2026-10-21T00:00:00Z'})) -Group 'Gemini Models' -NowUtc $script:now
    $r.h5.rem | Should -Be 42; $r.wk.rem | Should -Be 90; $r.h5.note | Should -Be ''
    $r.h5.reset | Should -Be ([datetime]::new(2026,10,18,5,0,0,[DateTimeKind]::Utc).ToLocalTime().ToString('dd.MM HH:mm'))
  }
  It 'нет нужной группы — исключение' { { ConvertFrom-AgQuota -Response (New-AgResp @()) -Group 'Другая' -NowUtc $script:now } | Should -Throw "*нет группы*" }
  It 'сброс уже прошёл — 100% (уточнено), Refine не обязателен' {
    $r=ConvertFrom-AgQuota -Response (New-AgResp @([pscustomobject]@{window='5h';remainingFraction=0;resetTime='2026-10-18T01:00:00Z'})) -Group 'Gemini Models' -NowUtc $script:now
    $r.h5.rem | Should -Be 100; $r.h5.note | Should -Be ' (уточнено)'
  }
  It 'сброс прошёл — уточняет по GetUserStatus (минимальный остаток среди моделей Gemini с будущим сбросом)' {
    $st=[pscustomobject]@{ userStatus=[pscustomobject]@{ cascadeModelConfigData=[pscustomobject]@{ clientModelConfigs=@(
      [pscustomobject]@{label='Gemini 3 Pro';quotaInfo=[pscustomobject]@{remainingFraction=0.3;resetTime='2026-10-18T06:00:00Z'}},
      [pscustomobject]@{label='Gemini Flash';quotaInfo=[pscustomobject]@{remainingFraction=0.7;resetTime='2026-10-18T06:00:00Z'}},
      [pscustomobject]@{label='Claude';quotaInfo=[pscustomobject]@{remainingFraction=0.01;resetTime='2026-10-18T06:00:00Z'}}) } } }
    $r=ConvertFrom-AgQuota -Response (New-AgResp @([pscustomobject]@{window='5h';remainingFraction=0;resetTime='2026-10-18T01:00:00Z'})) -Group 'Gemini Models' -NowUtc $script:now -Refine { $st }
    $r.h5.rem | Should -Be 30
  }
  It 'Refine упал — не падает, остаётся 100% (уточнено)' {
    $r=ConvertFrom-AgQuota -Response (New-AgResp @([pscustomobject]@{window='5h';remainingFraction=0;resetTime='2026-10-18T01:00:00Z'})) -Group 'Gemini Models' -NowUtc $script:now -Refine { throw 'нет сервера' }
    $r.h5.rem | Should -Be 100
  }
}
Describe 'Пункт 12: пороги и остановка по лимитам' -Tag Item12 {
  BeforeEach {
    $script:QWarned=@{}; $script:QOverride=@{}; $script:QStopG=$false; $script:QStopA=$false
    Mock Log {}; Mock Tg-Send { $true }; Mock Next-FileName { 'A_001.md' }
    $script:gw=@{ cur=10; curReset=''; wk=10; wkReset=''; exhausted=$false }
    $script:ag=@{ h5=@{rem=80;reset='';note=''}; wk=@{rem=80;reset='';note=''} }
    Mock Get-GeminiWebUsage { $script:gw }; Mock Get-AgQuota { $script:ag }
  }
  It 'Test-QuotaOver: used/remaining и $null' {
    Test-QuotaOver 90 90 'used' | Should -BeTrue; Test-QuotaOver 89 90 'used' | Should -BeFalse
    Test-QuotaOver 91 10 'remaining' | Should -BeTrue; Test-QuotaOver 80 10 'remaining' | Should -BeFalse
    Test-QuotaOver $null 10 'used' | Should -BeFalse
  }
  It 'ниже порогов — работа не блокируется' { Check-Quotas | Out-Null; Quota-Blocked | Should -BeNullOrEmpty }
  It 'Gemini ≥ 90% — стоп Gemini, одно предупреждение; повтор без роста — без нового сообщения' {
    $script:gw.cur=92; Check-Quotas | Out-Null
    Quota-Blocked | Should -Be 'лимит Gemini (сайт)'
    Check-Quotas | Out-Null
    Should -Invoke Tg-Send -Times 1 -Exactly -ParameterFilter { $Text -like '⚠️ Лимиты*' }
  }
  It 'Antigravity остаток ≤ 10% — стоп Antigravity; восстановилось — «возобновлена»' {
    $script:ag.h5.rem=5; Check-Quotas | Out-Null; Quota-Blocked | Should -Be 'лимит Antigravity'
    $script:ag.h5.rem=60; Check-Quotas | Out-Null; Quota-Blocked | Should -BeNullOrEmpty
    Should -Invoke Tg-Send -ParameterFilter { $Text -like '▶️*' }
  }
  It '«продолжай» (Quota-Override): игнорирует до роста на QuotaReWarnStep' {
    $script:gw.cur=92; Check-Quotas | Out-Null; Quota-Override; Quota-Blocked | Should -BeNullOrEmpty
    $script:gw.cur=94; Check-Quotas | Out-Null; Quota-Blocked | Should -BeNullOrEmpty
    $script:gw.cur=97; Check-Quotas | Out-Null; Quota-Blocked | Should -Be 'лимит Gemini (сайт)'
  }
  It 'ошибка чтения страницы лимитов: не снимает действующую остановку и не создаёт новую' {
    Mock Get-GeminiWebUsage { throw 'нет вкладки' }
    Check-Quotas | Out-Null; $script:QStopG | Should -BeFalse
    $script:QStopG=$true; Check-Quotas | Out-Null; $script:QStopG | Should -BeTrue
  }
}
