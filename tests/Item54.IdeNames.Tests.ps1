BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 54: тексты по выбранной IDE' -Tag Item54 {
  AfterEach { $Cfg.AgTarget='antigravity'; $script:Q=$null }
  It 'busy — спокойное «ещё работает», не «причина не ясна»' {
    $Cfg.AgTarget='dsharness'; $t=Get-AgBlockText @{ kind='busy'; msg='x'; detail=''; file='A_2026-10-21_019.md' }
    $t | Should -Match '⏳ DeepSeek Harness ещё работает'; $t | Should -Not -Match 'причина не ясна'
  }
  It 'этапы: «ответ передан в <IDE>»' {
    Get-StageRu 'relayed' | Should -Be 'ответ передан в Antigravity'
    $Cfg.AgTarget='dsharness'; Get-StageRu 'relayed' | Should -Be 'ответ передан в DeepSeek Harness'
  }
  It 'Quota-Text: Harness — без процентов' {
    $Cfg.AgTarget='dsharness'; $script:Q=@{ time='15:54'; ag=@{ h5=@{rem=100;reset='—';note=''}; wk=@{rem=100;reset='—';note=''}; dsh=@{rate=$false} } }
    $t=Quota-Text; $t | Should -Match 'DeepSeek Harness: квота не публикуется'; $t | Should -Not -Match 'Antigravity'; $t | Should -Not -Match 'осталось 100%'
  }
  It 'Quota-Text: Antigravity — как раньше' {
    $script:Q=@{ time='15:54'; ag=@{ h5=@{rem=80;reset='18:00';note=''}; wk=@{rem=60;reset='24.10';note=''} } }
    Quota-Text | Should -Match "Antigravity \($($Cfg.AgGroup)\): 5 ч осталось 80%"
  }
  It 'нигде в текстах Relay/Chat/State не осталось жёсткого «Antigravity» в строках с Log/Tg-Send (кроме Antigravity-only кода)' {
    foreach($f in 'Relay','Chat','State'){
      $src=Get-Content (Join-Path $PSScriptRoot "../lib/$f.ps1") -Encoding UTF8
      $bad=@($src | Where-Object { $_ -notmatch '^\s*#' -and $_ -cmatch '(Log|Tg-Send)\s+["''][^"'']*Antigravity' })
      $bad | Should -BeNullOrEmpty
    }
  }
}
