BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  if(-not (Get-Command Tg-Send -EA 0)){ function Tg-Send($t){} }
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function Reset-Fake{
    $script:Field=''; $script:Clip=''; $script:Enter=0; $script:Coords=0; $script:Cleared=0
    $script:InputFound=$true; $script:Focused=$true; $script:PasteWorks=$true; $script:SendWorks=$true; $script:Readable=$true
  }
}
Describe 'Пункт 2' -Tag Item02 {
  BeforeEach {
    Reset-Fake
    $Cfg.AgCoordFallback=$false; $Cfg.AgVerifyPaste='strict'; $Cfg.AgTransport='uia'
    Mock Log {}
    Mock Tg-Send {}
    Mock Get-TopWindows { @([pscustomobject]@{h=101;title='chrome';class='Chrome_WidgetWin_1';proc='chrome'},[pscustomobject]@{h=202;title='proj - Antigravity';class='Chrome_WidgetWin_1';proc='Antigravity'}) }
    Mock Invoke-WithFocus { & $Body }
    Mock Uia-FindFirst { if($script:InputFound){ 'INPUT' } else { $null } }
    Mock Uia-IsOffscreen { $false }
    Mock Uia-Focus { $true }
    Mock Uia-ClickEl { $true }
    Mock Uia-IsFocused { $script:Focused }
    Mock Uia-Focused { 'FOCUSED' }
    Mock Uia-GetText { if($script:Readable){ $script:Field } else { '' } }
    Mock Uia-GetValue { '' }
    Mock Uia-Name { 'Message input' }
    Mock Test-WindowHung { $false }; Mock Test-WindowPing { $true }; Mock Test-ProcessResponding { $true }
    Mock Use-TempClipboard { & $Body }
    Mock Set-ClipText { $script:Clip=$Text }
    Mock Paste { if($script:PasteWorks){ $script:Field+=$script:Clip } }
    Mock ClearField { $script:Field=''; $script:Cleared++ }
    Mock PressEnter { $script:Enter++; if($script:SendWorks){ $script:Field='' } }
    Mock ClickRel { $script:Coords++ }
    Mock Start-Sleep {}
  }

  Describe 'Пункт 2: окно Antigravity' -Tag Item02 {
    It 'находит окно Antigravity среди нескольких окон по процессу' { Ag-GetWindow | Should -Be 202 }
    It 'поле чата: повторяет поиск, если первый запрос UIA его не увидел (ленивое дерево Electron)' {
      $script:FindCalls=0
      Mock Uia-FindFirst { $script:FindCalls++; if($script:FindCalls -ge 2){ 'INPUT' } else { $null } }
      AgUia-FindInput 202 | Should -Be 'INPUT'
      $script:FindCalls | Should -Be 2
    }
    It 'поле чата: после всех попыток не найдено — $null' {
      $script:InputFound=$false
      AgUia-FindInput 202 | Should -BeNullOrEmpty
      Should -Invoke Uia-FindFirst -Times 3 -Exactly
    }
    It 'нет окна — NotSent, Enter не нажат' {
      Mock Get-TopWindows { @() }
      { AgUia-Send -Text "## Задача`nтекст" } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
      $script:Enter | Should -Be 0
    }
  }

  Describe 'Пункт 2: AgUia-Send — проверки до и после Enter' -Tag Item02 {
    It 'нормальный сценарий: вставил, проверил, Enter, поле опустело' {
      AgUia-Send -Text "## Задача 5`nсделай X" -Label 'ответ на A_001'
      $script:Enter | Should -Be 1; $script:Coords | Should -Be 0
      $script:AgPending.label | Should -Be 'ответ на A_001'
    }
    It 'поле не найдено и AgCoordFallback=false — НЕ кликает по координатам и НЕ жмёт Enter' {
      $script:InputFound=$false
      { AgUia-Send -Text "## Задача" } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
      $script:Coords | Should -Be 0; $script:Enter | Should -Be 0
    }
    It 'поле не найдено и AgCoordFallback=true — клик по координатам, но Enter только после проверки текста в фокусе' {
      $script:InputFound=$false; $Cfg.AgCoordFallback=$true
      AgUia-Send -Text "## Задача"
      $script:Coords | Should -Be 1; $script:Enter | Should -Be 1
    }
    It 'фокус не в поле — NotSent без вставки' {
      $script:Focused=$false
      { AgUia-Send -Text "## Задача" } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
      Should -Invoke Paste -Times 0; $script:Enter | Should -Be 0
    }
    It 'вставка не появилась — Enter не нажат' {
      $script:PasteWorks=$false
      { AgUia-Send -Text "## Задача" } | Should -Throw '*не принимает ввод*'
      $script:Enter | Should -Be 0
    }
    It 'в поле посторонний текст пользователя — не трогает' {
      $script:Field='мой черновик'
      { AgUia-Send -Text "## Задача" } | Should -Throw '*чужой текст*'
      $script:Field | Should -Be 'мой черновик'; $script:Cleared | Should -Be 0
    }
    It 'в поле наш прошлый текст — очищает и отправляет' {
      $script:Field="## Задача`nстарое"
      AgUia-Send -Text "## Задача`nновое"
      $script:Cleared | Should -Be 1; $script:Enter | Should -Be 1
    }
    It 'после Enter текст остался — NotSent' {
      $script:SendWorks=$false
      { AgUia-Send -Text "## Задача" } | Should -Throw '*остался*'
    }
    It 'текст поля не читается: strict — не отправляет; lenient — отправляет как раньше' {
      $script:Readable=$false
      { AgUia-Send -Text "## Задача" } | Should -Throw -ExceptionType ([GG.RelayNotSentException])
      $script:Enter | Should -Be 0
      $Cfg.AgVerifyPaste='lenient'
      Mock Uia-GetText { '' }
      AgUia-Send -Text "## Задача"
      $script:Enter | Should -Be 1
      Should -Invoke Log -ParameterFilter { $m -like '*AgVerifyPaste=lenient*' }
    }
    It 'вставка идёт через временный буфер (Use-TempClipboard)' {
      AgUia-Send -Text "## Задача"
      Should -Invoke Use-TempClipboard -Times 1
    }
  }

  Describe 'Пункт 2: почтовый ящик' -Tag Item02 {
    It 'имя задания безопасное и предсказуемое' {
      Get-InboxTaskName 'MyProject_2026-10-18_003.md' | Should -Be 'task_MyProject_2026-10-18_003.md'
      Get-InboxTaskName 'a b:c?.md' | Should -Be 'task_a_b_c_.md'
      Get-InboxTaskName 'C:\dir\R_2026-10-18_001.md' | Should -Be 'task_R_2026-10-18_001.md'
    }
    It 'New-InboxTask пишет атомарно UTF-8 без BOM и удаляет старые .taken/.ack' {
      $dir=Join-Path $TestDrive 'inbox'; New-Item -ItemType Directory $dir -Force | Out-Null
      $p0=Join-Path $dir 'task_X_2026-10-18_001.md'; New-Item "$p0.taken" -ItemType File -Force | Out-Null
      $p=New-InboxTask -InboxDir $dir -Name 'X_2026-10-18_001.md' -Text "## Задача`nтекст"
      [IO.File]::ReadAllText($p) | Should -Be "## Задача`nтекст"
      ([IO.File]::ReadAllBytes($p))[0] | Should -Not -Be 0xEF
      Test-Path "$p.taken" | Should -BeFalse
      Test-Path "$p.tmp" | Should -BeFalse
    }
    It 'триггер короткий, однострочный и содержит путь' {
      $t=Get-MailboxTrigger 'C:\x\inbox\task_A.md'
      $t | Should -Match ([regex]::Escape('C:\x\inbox\task_A.md')); $t | Should -Not -Match "`n"; $t.Length | Should -BeLessThan 400
    }
    It 'AgMailbox-Send: файл + короткий триггер через проверенную отправку, подтверждение .taken' {
      $Cfg.InboxDir=Join-Path $TestDrive 'inbox2'; $Cfg.AgTransport='mailbox'
      Ag-Send -Text ("длинный ответ`n"*100) -Label 'ответ' -Name 'P_2026-10-18_002.md'
      $p=[IO.Path]::GetFullPath((Join-Path $Cfg.InboxDir 'task_P_2026-10-18_002.md'))
      Test-Path $p | Should -BeTrue
      $script:Clip | Should -Match 'task_P_2026-10-18_002.md'; $script:Clip | Should -Not -Match 'длинный ответ'
      @(Check-MailboxAcks).Count | Should -Be 0
      Rename-Item $p "$p.taken" -ErrorAction SilentlyContinue; New-Item "$p.taken" -ItemType File -Force | Out-Null
      Check-MailboxAcks | Out-Null
      $script:MailboxPending.ContainsKey($p) | Should -BeFalse
    }
    It 'нет подтверждения дольше MailboxAckSec — одно предупреждение' {
      $script:MailboxPending=@{}; $Cfg.InboxDir=Join-Path $TestDrive 'inbox3'; $Cfg.MailboxAckSec=0
      [void](AgMailbox-Send -Text 'x' -Name 'Q_2026-10-18_001.md')
      @(Check-MailboxAcks).Count | Should -Be 1
      @(Check-MailboxAcks).Count | Should -Be 0
      Should -Invoke Tg-Send -Times 1
    }
  }

}
