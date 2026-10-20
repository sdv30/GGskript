BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function Reset-Tg{
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100
    $script:TgPrompts.Clear(); $script:TgAwait=$null; $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:PendingConfirm=$null; $script:Blk=@{key=$null}
  }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
}
Describe 'Пункт 22: русские кнопки Telegram (ReplyKeyboardMarkup)' -Tag Item22 {
  BeforeEach { Mock Gem-IsGenerating { $false }; Mock Gem-PeekAnswer { $null }; Mock Get-AgHealth { @{ ok=$true; kind="ok"; reasons=@() } }; Mock Find-QueuedItems { @() }; $script:LastStartReport=""; $script:StopAnnounced=$false;
    Reset-Tg
    $Cfg.TgReplyKeyboard=$true; $Cfg.StrictCommands=$true; $Cfg.TgOfferForward=$true; $Cfg.TgAwaitTextMin=10; $Cfg.TgPromptTimeoutMin=30; $Cfg.TgMaxLen=4096
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query; json=($Body | ConvertTo-Json -Depth 10) }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
  }

  Context 'надпись кнопки -> команда (строгий режим)' {
    It '«<B>» -> <K>' -TestCases @(
      @{B='Статус';K='status'},@{B='Пауза';K='pause'},@{B='Продолжай';K='resume'},@{B='Стоп';K='stop'},@{B='Старт';K='resume'},@{B='Выключи скрипт';K='exit'},
      @{B='Прими';K='accept'},@{B='Передай ответ';K='relay'},@{B='Передай всё равно';K='force'},
      @{B='Перешли ответ в Antigravity';K='fwdans'},@{B='Перешли отчёт в Gemini';K='fwdrep'},
      @{B='Что ответил Джемини';K='lastanswer'},@{B='Отправь заново';K='resendstale'},
      @{B='Напиши';K='write'},@{B='Скрин';K='shot'},@{B='Лимиты';K='limits'},@{B='Помощь';K='help'}) {
      param($B,$K)
      (Parse-Command -Text $B -Strict $true).k | Should -Be $K
      (Parse-Command -Text $B -Strict $true -HasDialog $true).k | Should -Be $K -Because 'при открытом диалоге кнопка тоже не должна перехватываться'
    }
    It '«Передай ответ» — без флага whole (только блок Markdown)' { (Parse-Command -Text 'Передай ответ').whole | Should -BeFalse }
    It 'все 11 надписей клавиатуры распознаются (ни одна не unknown)' {
      $l=@(Get-TgReplyLabels); $l.Count | Should -Be 11
      foreach($x in $l){ (Parse-Command -Text $x -Strict $true).k | Should -Not -Be 'unknown' -Because $x }
    }
    It 'надпись с эмодзи и без — одна команда: «<B>» -> <K>' -TestCases @(
      @{B='📂 Отчёт в Gemini';K='fwdrep'},@{B='📂 Ответ в Antigravity';K='fwdans'},@{B='🛠 Antigravity: текст';K='agwrite'},
      @{B='✨ Gemini: текст';K='gemwrite'},@{B='✨ Ответ Gemini';K='lastanswer'},@{B='ℹ️ Статус';K='status'},@{B='⏸ Стоп';K='stop'},
      @{B='▶️ Старт';K='resume'},@{B='📸 Скрин';K='shot'},@{B='📊 Лимиты';K='limits'},@{B='❓ Помощь';K='help'}) {
      param($B,$K)
      (Parse-Command -Text $B -Strict $true).k | Should -Be $K
      $plain=($B -replace '^(?:[^\p{L}\p{N}/!]|\u2139)+','').Trim()
      (Parse-Command -Text $plain -Strict $true).k | Should -Be $K
    }
  }

  Context 'форма клавиатуры' {
    It 'ряды по смыслу: файлы · Antigravity+Gemini · управление · прочее' {
      $k=New-TgReplyKeyboard
      $k.resize_keyboard | Should -BeTrue; $k.is_persistent | Should -BeTrue
      $k.keyboard.Count | Should -Be 4
      ($k.keyboard | ForEach-Object { $_.Count }) -join ',' | Should -Be '2,3,3,3'
      $k.keyboard[0][0].text | Should -Be '📂 Отчёт в Gemini'; $k.keyboard[3][2].text | Should -Be '❓ Помощь'
    }
    It 'убранные с клавиатуры кнопки остались командами' {
      $l=@(Get-TgReplyLabels)
      foreach($x in 'Прими','Передай всё равно','Передай ответ','Отправь заново','Выключи скрипт','Напиши'){ $l | Should -Not -Contain $x; (Parse-Command -Text $x).k | Should -Not -Be 'unknown' }
    }
    It 'все надписи начинаются с эмодзи, затем заглавная буква; ≤ 64 символов' {
      foreach($x in Get-TgReplyLabels){ $x.Length | Should -BeLessOrEqual 64; $x | Should -Not -Match '^/'; $w=($x -replace '^(?:[^\p{L}\p{N}]|\u2139)+',''); $w.Substring(0,1) | Should -BeExactly $w.Substring(0,1).ToUpper() }
    }
  }

  Context 'меню «/»' {
    It 'без дублей, описания с заглавной, команды разбираются' {
      $m=@(Get-TgMenuCommands); ($m.command | Select-Object -Unique).Count | Should -Be $m.Count
      $m.command | Should -Not -Contain 'pause'; $m.command | Should -Not -Contain 'send'; $m.command | Should -Not -Contain 'resend'; $m.command | Should -Not -Contain 'cancel'
      foreach($c in $m){ $c.description.Length | Should -BeLessOrEqual 256; $w=($c.description -replace '^[^\p{L}]+',''); $w.Substring(0,1) | Should -BeExactly $w.Substring(0,1).ToUpper()
        if($c.command -ne 'shutdown'){ (Parse-Command -Text "/$($c.command)").k | Should -Not -Be 'unknown' -Because $c.command } }
    }
    It 'Register-TgCommands шлёт setMyCommands' {
      Register-TgCommands | Should -BeTrue
      $r=@($script:TgCalls | Where-Object { $_.m -eq 'setMyCommands' }); $r.Count | Should -Be 1; @($r[0].b.commands).Count | Should -Be 18
    }
  }

  Context 'куда прикрепляется' {
    It '«помощь» — с клавиатурой' {
      Handle-Command 'Помощь' 'tg'
      $s=(Sent '*команды*'); $s.Count | Should -Be 1
      $s[0].b.parse_mode | Should -Be 'HTML'
      $s[0].b.reply_markup.keyboard.Count | Should -Be 4
      $s[0].json | Should -Match '"is_persistent":\s*true'
    }
    It 'стартовое сообщение — с клавиатурой' {
      Mock Gem-IsReady { $false }; Mock Ag-GetWindow { $null }; Mock Get-Files { @() }
      Start-Procedure | Out-Null
      $s=(Sent '*процедура запуска*'); $s.Count | Should -Be 1
      $s[0].b.reply_markup.resize_keyboard | Should -BeTrue
    }
    It 'обычные ответы (статус и т.п.) клавиатуру не шлют повторно' {
      Tg-Send 'просто текст' | Out-Null
      (Sent 'просто текст')[0].b.Contains('reply_markup') | Should -BeFalse
    }
    It 'длинная «помощь» из нескольких частей — клавиатура только на последней' {
      Tg-Send (('x'*3900)+"`n"+('y'*3900)) -Markup (New-TgReplyKeyboard) | Out-Null
      $s=@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' }); $s.Count | Should -Be 2
      $s[0].b.Contains('reply_markup') | Should -BeFalse; $s[1].b.reply_markup.keyboard.Count | Should -Be 4
    }
    It 'TgReplyKeyboard=false — ни в «помощи», ни при запуске клавиатуры нет' {
      $Cfg.TgReplyKeyboard=$false
      Get-TgReplyMarkup | Should -BeNullOrEmpty
      Handle-Command 'помощь' 'tg'
      (Sent '*команды*')[0].b.Contains('reply_markup') | Should -BeFalse
      Mock Gem-IsReady { $false }; Mock Ag-GetWindow { $null }; Mock Get-Files { @() }
      Start-Procedure | Out-Null
      (Sent '*процедура запуска*')[0].b.Contains('reply_markup') | Should -BeFalse
    }
    It 'нет ключа в настройках — по умолчанию включено' {
      (Get-DefaultSettings -Root $TestDrive -UserProfile $TestDrive).TgReplyKeyboard | Should -BeTrue
      $c2=[ordered]@{}; $save=$script:Cfg; $script:Cfg=$c2; $Cfg=$c2
      try{ (Get-TgReplyMarkup).is_persistent | Should -BeTrue } finally { $script:Cfg=$save; $Cfg=$save }
    }
  }

  Context 'инлайн-кнопки не сломаны' {
    It 'вопрос «Куда переслать?» по-прежнему с inline_keyboard и без reply-клавиатуры' {
      Handle-Command 'какой-то свободный текст' 'tg'
      $s=(Sent '*Переслать*'); $s.Count | Should -Be 1
      $s[0].b.reply_markup.inline_keyboard | Should -Not -BeNullOrEmpty
      $s[0].b.reply_markup.Contains('keyboard') | Should -BeFalse
    }
    It 'New-TgKeyboard (inline) не изменился' {
      $k=New-TgKeyboard 'Да=yes|Нет=no' 'p:1:'; $k.inline_keyboard[0][0].callback_data | Should -Be 'p:1:yes'
    }
  }

  Context 'кнопка во время «напиши» (ожидание текста) — поведение пункта 21 сохранено' {
    It 'нажатая кнопка «Статус» считается текстом: спрашиваю «Куда переслать?», команду не выполняю' {
      Handle-Command 'Напиши' 'tg'; Handle-Command 'Статус' 'tg'
      $script:TgAwait | Should -BeNullOrEmpty
      (Sent '*Куда переслать*').Count | Should -Be 1
      $script:Queue.Count | Should -Be 0
    }
  }
}
