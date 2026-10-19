BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 4: буфер обмена' -Tag Item04 {
  BeforeEach { Mock Log {} }
  Context 'Use-TempClipboard' {
    BeforeEach { $script:restored=@(); Mock Save-Clipboard { 'USERDATA' }; Mock Restore-Clipboard { $script:restored+=,$Saved } ; $Cfg.RestoreClipboard=$true }
    It 'восстанавливает буфер пользователя после успешной операции и отдаёт результат' {
      (Use-TempClipboard { 42 }) | Should -Be 42
      $script:restored | Should -Be @('USERDATA')
    }
    It 'восстанавливает буфер и при исключении' {
      { Use-TempClipboard { throw 'x' } } | Should -Throw 'x'
      $script:restored | Should -Be @('USERDATA')
    }
    It 'если у пользователя буфер был пуст — восстанавливается пустота ($null)' {
      Mock Save-Clipboard { $null }
      Use-TempClipboard { } | Out-Null
      $script:restored.Count | Should -Be 1; $script:restored[0] | Should -BeNullOrEmpty
    }
    It 'RestoreClipboard=false — старое поведение (не сохраняет и не восстанавливает)' {
      $Cfg.RestoreClipboard=$false; Use-TempClipboard { } | Out-Null
      Should -Invoke Save-Clipboard -Times 0; Should -Invoke Restore-Clipboard -Times 0
    }
  }
  Context 'Copy-ViaButton: маркер, гонка, повторы' {
    BeforeEach {
      $script:clip=''; $script:seq=10; $script:sentinels=@(); $script:idle=100000; $script:clickResult='ОТВЕТ'
      Mock Invoke-WithFocus { & $Body }
      Mock Use-TempClipboard { & $Body }
      Mock Uia-ScrollIntoView {}; Mock Start-Sleep {}
      Mock Set-ClipText { $script:clip=$Text; $script:seq++; $script:sentinels+=$Text }
      Mock Get-ClipSeq { $script:seq }
      Mock Get-ClipText { $script:clip }
      Mock Uia-ClickEl { if($null -ne $script:clickResult){ $script:clip=$script:clickResult; $script:seq++ }; $true }
      Mock Get-IdleMs { $script:idle }
    }
    It 'возвращает скопированный текст; маркер уникальный (GUID), а не "__empty__"' {
      Copy-ViaButton 1 { 'BTN' } 'блок' | Should -Be 'ОТВЕТ'
      $script:sentinels[0] | Should -Match '^__gg_[0-9a-f]{32}__$'
      Copy-ViaButton 1 { 'BTN' } 'блок' | Out-Null
      $script:sentinels[1] | Should -Not -Be $script:sentinels[0]
    }
    It 'кнопки нет — $null без исключения' { Copy-ViaButton 1 { $null } 'блок' | Should -BeNullOrEmpty }
    It 'пользователь работал во время копирования — результат отброшен, после 3 попыток исключение' {
      $script:idle=0
      Mock Start-Sleep { [Threading.Thread]::Sleep(200) }
      { Copy-ViaButton 1 { 'BTN' } 'блок' } | Should -Throw '*Не удалось скопировать*'
      Should -Invoke Log -ParameterFilter { $m -like '*результат отброшен*' } -Times 3
    }
    It 'буфер не изменился после клика — повтор и исключение' {
      $script:clickResult=$null
      { Copy-ViaButton 1 { 'BTN' } 'блок' } | Should -Throw '*Не удалось скопировать*'
      Should -Invoke Uia-ClickEl -Times 3
    }
    It 'кнопка не кликается мышью — используется InvokePattern' {
      Mock Uia-ClickEl { $false }; Mock Uia-Invoke { $script:clip='ИЗ INVOKE'; $script:seq++; $true }
      Copy-ViaButton 1 { 'BTN' } 'блок' | Should -Be 'ИЗ INVOKE'
    }
    It 'копирование всегда идёт через временный буфер' { Copy-ViaButton 1 { 'BTN' } 'блок' | Out-Null; Should -Invoke Use-TempClipboard -Times 1 }
  }
  It 'Set-ClipText по умолчанию исключает содержимое из журнала Win+V и облака (настройка и код)' {
    (Get-DefaultSettings -Root 'R' -UserProfile 'U').ClipExcludeHistory | Should -BeTrue
    $src=Get-Content (Join-Path $V2Root 'lib/Platform.Win.ps1') -Raw
    $src | Should -Match 'ExcludeClipboardContentFromMonitorProcessing'; $src | Should -Match 'CanIncludeInClipboardHistory'
  }
}
