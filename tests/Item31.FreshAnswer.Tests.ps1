BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 31: прежний ответ не принимается за ответ на новый отчёт' -Tag Item31 {
  BeforeEach { Mock Log {}; Mock Nap {}; $Cfg.GeminiQuietSec=0; $Cfg.DupAnswerWaitSec=5; $Cfg.GeminiTimeoutSec=5; $Cfg.WaitAfterLastPrompt=$true }
  It 'Wait-FreshAnswer: пока идёт генерация — ждёт, потом берёт новый ответ' {
    $script:i=0; Mock Gem-IsGenerating { $script:i++; $script:i -le 2 }
    Mock Gem-PeekAnswer { @{ answered=$true; labels=@('XML'); code=$(if($script:i -le 2){'OLD'}else{'NEW'}) } }
    Mock Gem-CopyCode { 'NEW' }
    Wait-FreshAnswer 'f.md' (Get-Hash8 'OLD') | Should -Be 'NEW'
  }
  It 'Wait-FreshAnswer: ответ так и не изменился — $null по таймауту, без копирования старого' {
    $Cfg.DupAnswerWaitSec=1; Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { @{ answered=$true; labels=@('XML'); code='OLD' } }; Mock Gem-CopyCode { 'OLD' }
    Wait-FreshAnswer 'f.md' (Get-Hash8 'OLD') | Should -BeNullOrEmpty
    Should -Invoke Gem-CopyCode -Times 0
  }
  It 'Wait-FreshAnswer: текст блока не читается (UIA) — копирует и сравнивает хэш' {
    Mock Gem-IsGenerating { $false }; $script:k=0; Mock Gem-PeekAnswer { $script:k++; @{ answered=$true; labels=@($(if($script:k -le 1){'XML'}else{'Markdown'})); code=$null } }
    Mock Gem-CopyCode { 'NEW2' }
    Wait-FreshAnswer 'f.md' (Get-Hash8 'OLD') | Should -Be 'NEW2'
  }
  It 'DupAnswerWaitSec=0 — сразу $null (прежнее поведение)' { $Cfg.DupAnswerWaitSec=0; Mock Gem-CopyCode { 'x' }; Wait-FreshAnswer 'f.md' 'h' | Should -BeNullOrEmpty; Should -Invoke Gem-CopyCode -Times 0 }
  It 'Wait-AnswerAfterLastPrompt: ждёт, пока после последнего запроса появится ответ' {
    $script:j=0; Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { $script:j++; @{ answered=($script:j -ge 3) } }
    Wait-AnswerAfterLastPrompt 'f.md'; $script:j | Should -BeGreaterOrEqual 3
  }
  It 'Wait-AnswerAfterLastPrompt: ответа нет — таймаут' { $Cfg.GeminiTimeoutSec=0; Mock Gem-IsGenerating { $true }; Mock Gem-PeekAnswer { @{ answered=$false } }; { Wait-AnswerAfterLastPrompt 'f.md' } | Should -Throw '*Таймаут*' }
  It 'команды «передай файл в гемини» / «перешли отчёт в гемини» = /togemini' {
    foreach($t in 'передай файл в гемини','перешли отчёт в гемини','Перешли отчет в Gemini','отправь отчёт в джемини','/togemini'){ (Parse-Command $t).k | Should -Be 'fwdrep' -Because $t }
    (Parse-Command 'передай ответ').k | Should -Be 'relay'
  }
}
