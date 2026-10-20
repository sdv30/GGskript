BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 34: чья очередь — по времени файла и последней вставки в Antigravity' -Tag Item34 {
  BeforeEach {
    $script:S=New-RelayState
    $S.files['A_001.md']=[ordered]@{ stage='relayed'; time='2026-10-20 22:32:48'; hash='h'; attempts=1; note='' }
  }
  It 'последняя вставка — по этапу relayed' { (Get-LastAgRelayTime $S).ToString('HH:mm:ss') | Should -Be '22:32:48' }
  It 'lastAgAt позже этапа — берётся он' { $S.lastAgAt='2026-10-20 22:40:00'; (Get-LastAgRelayTime $S).ToString('HH:mm:ss') | Should -Be '22:40:00' }
  It 'отчёт новее вставки — очередь Gemini' { Test-ReportNewerThanAg $S ([datetime]'2026-10-20 22:34:47') | Should -BeTrue }
  It 'отчёт старее вставки — не очередь Gemini' { Test-ReportNewerThanAg $S ([datetime]'2026-10-20 22:32:06') | Should -BeFalse }
  It 'вставок не было — очередь Gemini' { Test-ReportNewerThanAg (New-RelayState) (Get-Date) | Should -BeTrue }
  It 'перезаписанный после relayed файл — новый отчёт' { Test-ReportRewritten $S 'A_001.md' ([datetime]'2026-10-20 22:34:47') | Should -BeTrue }
  It 'не перезаписан — нет' { Test-ReportRewritten $S 'A_001.md' ([datetime]'2026-10-20 22:32:06') | Should -BeFalse }
  It 'sent/skipped не сбрасываются' {
    $S.files['A_001.md'].stage='sent'; Test-ReportRewritten $S 'A_001.md' ([datetime]'2026-10-20 23:00:00') | Should -BeFalse
    $S.files['A_001.md'].stage='skipped'; Test-ReportRewritten $S 'A_001.md' ([datetime]'2026-10-20 23:00:00') | Should -BeFalse
  }
  It 'lastAgAt сохраняется и читается' {
    $S.lastAgAt='2026-10-20 22:40:00'; $p=Join-Path $TestDrive 'st.json'; Save-RelayState $S $p
    (Read-RelayState $p).State.lastAgAt | Should -Be '2026-10-20 22:40:00'
  }
}
