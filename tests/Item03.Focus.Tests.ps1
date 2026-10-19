BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  if(-not (Get-Command Nap -EA 0)){ function Nap($sec){} }
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 3: фокус и активность пользователя' -Tag Item03 {
  BeforeEach { Mock Log {}; $Cfg.IdleSec=3; $Cfg.IdleMaxWaitSec=60; $Cfg.RestoreFocus=$true }

  Context 'Wait-UserIdle' {
    It 'IdleSec=0 — не ждёт' { $Cfg.IdleSec=0; Mock Get-IdleMs { 0 }; Wait-UserIdle | Should -BeFalse; Should -Invoke Get-IdleMs -Times 0 }
    It 'пользователь уже неактивен — не ждёт' { Mock Get-IdleMs { 10000 }; Mock Nap {}; Wait-UserIdle | Should -BeFalse; Should -Invoke Nap -Times 0 }
    It 'пользователь активен — ждёт через Nap, пока не станет неактивен' {
      $script:i=0; Mock Get-IdleMs { $script:i++; if($script:i -le 3){ 100 } else { 5000 } }; Mock Nap {}
      Wait-UserIdle | Should -BeTrue; Should -Invoke Nap -Times 3
    }
    It 'пользователь активен постоянно — сдаётся по IdleMaxWaitSec и пишет в лог' {
      $Cfg.IdleMaxWaitSec=0; Mock Get-IdleMs { 0 }; Mock Nap {}
      Wait-UserIdle | Should -BeTrue
      Should -Invoke Log -ParameterFilter { $m -like '*продолжаю*' }
    }
  }
  Context 'Invoke-WithFocus' {
    BeforeEach {
      $script:fg=500; $script:set=@()
      Mock Wait-UserIdle { $false }; Mock Get-ForegroundHandle { $script:fg }
      Mock Activate-Window { $script:fg=$h }; Mock Set-ForegroundHandle { $script:set+=$h; $script:fg=$h }
    }
    It 'возвращает фокус предыдущему окну после успеха и возвращает результат тела' {
      $r=Invoke-WithFocus 202 { 'ok' }
      $r | Should -Be 'ok'; $script:set | Should -Be @(500)
    }
    It 'возвращает фокус даже при исключении в теле' {
      { Invoke-WithFocus 202 { throw 'boom' } } | Should -Throw 'boom'
      $script:set | Should -Be @(500)
    }
    It 'не трогает фокус, если окно уже было активным' { $script:fg=202; Invoke-WithFocus 202 { } ; $script:set.Count | Should -Be 0 }
    It 'RestoreFocus=false — не возвращает (старое поведение)' { $Cfg.RestoreFocus=$false; Invoke-WithFocus 202 { }; $script:set.Count | Should -Be 0 }
    It 'ждёт простоя пользователя перед перехватом фокуса (и не ждёт с -NoIdleWait)' {
      Invoke-WithFocus 202 { }; Should -Invoke Wait-UserIdle -Times 1 -Exactly
      Invoke-WithFocus 202 { } -NoIdleWait; Should -Invoke Wait-UserIdle -Times 1 -Exactly
    }
  }
  Context 'Клавиши отпускаются при исключениях' {
    BeforeEach { $script:keys=New-Object System.Collections.Generic.List[string]; Mock KeyDown { $script:keys.Add("d$vk") }; Mock KeyUp { $script:keys.Add("u$vk") }; Mock Start-Sleep {}; Mock Wait-ModifiersUp {} }
    It 'Send-Ctrl: Ctrl отпущен, даже если нажатие буквы упало' {
      Mock Send-Key { throw 'fail' }
      { Send-Ctrl 0x56 } | Should -Throw 'fail'
      $script:keys | Should -Contain 'u17'
    }
    It 'Send-Key: клавиша отпускается в finally' {
      $script:n=0; Mock Start-Sleep { $script:n++; if($script:n -eq 1){ throw 'x' } }
      { Send-Key 13 } | Should -Throw
      $script:keys | Should -Be @('d13','u13')
    }
    It 'Paste = Ctrl+V с ожиданием отпускания модификаторов пользователя' {
      Paste; Should -Invoke Wait-ModifiersUp -Times 1 -Exactly
      ($script:keys -join ',') | Should -Be 'd17,d86,u86,u17'
    }
    It 'PressEnter ждёт отпускания Shift (иначе Shift+Enter = перенос строки)' { PressEnter; Should -Invoke Wait-ModifiersUp -Times 1; ($script:keys -join ',') | Should -Be 'd13,u13' }
  }
  It 'по умолчанию для разблокировки фокуса используется нейтральная клавиша, а не Alt' {
    (Get-DefaultSettings -Root 'R' -UserProfile 'U').ActivateKey | Should -Be 0xE8
    (Get-Content (Join-Path $V2Root 'lib/Platform.Win.ps1') -Raw) | Should -Not -Match 'keybd_event\(0x12'
  }
}
