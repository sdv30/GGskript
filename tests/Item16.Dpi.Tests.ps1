BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 16: DPI' -Tag Item16 {
  It 'Per-Monitor V2 доступен — pmv2, System DPI не вызывается' { Mock Dpi-SetPerMonitorV2 { $true }; Mock Dpi-SetSystemAware { $true }; Initialize-Dpi | Should -Be 'pmv2'; Should -Invoke Dpi-SetSystemAware -Times 0 }
  It 'старая Windows (нет функции) — откат на System DPI' { Mock Dpi-SetPerMonitorV2 { throw 'EntryPointNotFound' }; Mock Dpi-SetSystemAware { $true }; Initialize-Dpi | Should -Be 'system' }
  It 'уже задано манифестом (false) — откат дальше, без исключения' { Mock Dpi-SetPerMonitorV2 { $false }; Mock Dpi-SetSystemAware { $false }; Initialize-Dpi | Should -Be 'none' }
  It 'границы окна: DWM без тени' { Mock Get-DwmBounds { @{L=10;T=20;R=1010;B=820} }; Mock Get-RawWindowRect { @{L=3;T=13;R=1017;B=827} }; (Get-WindowBounds 1).L | Should -Be 10; Should -Invoke Get-RawWindowRect -Times 0 }
  It 'DWM недоступен/пустой прямоугольник — GetWindowRect' {
    Mock Get-RawWindowRect { @{L=3;T=13;R=1017;B=827} }
    Mock Get-DwmBounds { throw 'нет DWM' }; (Get-WindowBounds 1).L | Should -Be 3
    Mock Get-DwmBounds { @{L=0;T=0;R=0;B=0} }; (Get-WindowBounds 1).L | Should -Be 3
  }
  It 'ClickRel считает от видимых границ (доли окна → экранные пиксели)' {
    Mock Get-WindowBounds { @{L=100;T=200;R=1100;B=1200} }; Mock ClickAt { $script:xy=@($x,$y) }
    ClickRel 1 0.5 0.9
    $script:xy[0] | Should -Be 600; $script:xy[1] | Should -Be 1100
  }
}
Describe 'Пункт 16: производительность UIA' -Tag Item16 {
  It 'точное имя уходит в условие поиска UIA (а не фильтр по всем элементам)' {
    $fake=[pscustomobject]@{}; $fake | Add-Member ScriptMethod FindAll { param($scope,$cond) $script:cond=$cond; @('e1') }
    Mock Uia-Root { $fake }; Mock Uia-Cond { "COND:$ControlType/$Name" }
    @(Uia-FindAll -Root 5 -ControlType 'Button' -Name 'Копировать') | Should -Be @('e1')
    $script:cond | Should -Be 'COND:Button/Копировать'
  }
  It 'регэксп имени — фильтром после поиска по типу' {
    $e1=[pscustomobject]@{ Current=[pscustomobject]@{ Name='Copy code' } }; $e2=[pscustomobject]@{ Current=[pscustomobject]@{ Name='Share' } }
    $fake=[pscustomobject]@{}; $fake | Add-Member ScriptMethod FindAll { param($scope,$cond) $script:cond=$cond; @($e1,$e2) }
    Mock Uia-Root { $fake }; Mock Uia-Cond { "COND:$ControlType/$Name" }
    @(Uia-FindAll -Root 5 -ControlType 'Button' -NameRx '^Copy') | Should -HaveCount 1
    $script:cond | Should -Be 'COND:Button/'
  }
}
Describe 'Пункт 16: откат UiaPerfAnd' -Tag Item16 {
  It 'UiaPerfAnd=false — поиск по типу, точное имя фильтром' {
    $Cfg.UiaPerfAnd=$false
    try{
      $e1=[pscustomobject]@{ Current=[pscustomobject]@{ Name='OK' } }; $e2=[pscustomobject]@{ Current=[pscustomobject]@{ Name='OK2' } }
      $fake=[pscustomobject]@{}; $fake | Add-Member ScriptMethod FindAll { param($scope,$cond) $script:cond=$cond; @($e1,$e2) }
      Mock Uia-Root { $fake }; Mock Uia-Cond { "COND:$ControlType/$Name" }
      @(Uia-FindAll -Root 5 -ControlType 'Button' -Name 'OK') | Should -HaveCount 1
      $script:cond | Should -Be 'COND:Button/'
    } finally { $Cfg.UiaPerfAnd=$true }
  }
}
Describe 'Пункт 16: UIA-условия на Windows' -Tag Item16,WindowsOnly {
  It 'тип+имя — AndCondition; ничего — TrueCondition' {
    Initialize-Uia
    (Uia-Cond 'Button' 'OK').GetType().Name | Should -Be 'AndCondition'
    (Uia-Cond 'Button' '').GetType().Name | Should -Be 'PropertyCondition'
    (Uia-Cond '' '') | Should -Be ([System.Windows.Automation.Condition]::TrueCondition)
  }
}
