BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1') }
Describe 'Item47: stop only at exhaustion' {
  It 'Antigravity 9% remaining does not stop' { Test-QuotaOver 91 0 'remaining' | Should -BeFalse }
  It 'Antigravity 0% remaining stops' { Test-QuotaOver 100 0 'remaining' | Should -BeTrue }
  It 'Gemini 99% used does not stop' { Test-QuotaOver 99 100 'used' | Should -BeFalse }
  It 'Gemini 100% used stops' { Test-QuotaOver 100 100 'used' | Should -BeTrue }
}
