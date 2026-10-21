BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1') }
Describe 'Item47: Antigravity stops at 1% remaining, Gemini at 100% used' {
  It 'default AgThreshold is 1' { $d=Get-DefaultSettings -Root 'R' -UserProfile 'U'; $d.AgThreshold | Should -Be 1 }
  It 'Antigravity 9% remaining does not stop' { Test-QuotaOver 91 1 'remaining' | Should -BeFalse }
  It 'Antigravity 2% remaining does not stop' { Test-QuotaOver 98 1 'remaining' | Should -BeFalse }
  It 'Antigravity 1% remaining stops' { Test-QuotaOver 99 1 'remaining' | Should -BeTrue }
  It 'Antigravity 0% remaining stops' { Test-QuotaOver 100 1 'remaining' | Should -BeTrue }
  It 'Gemini 99% used does not stop' { Test-QuotaOver 99 100 'used' | Should -BeFalse }
  It 'Gemini 100% used stops' { Test-QuotaOver 100 100 'used' | Should -BeTrue }
}
