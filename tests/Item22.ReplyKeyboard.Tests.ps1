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
    It 'все 15 надписей клавиатуры распознаются (ни одна не unknown)' {
      $l=@(Get-TgReplyLabels); $l.Count | Should -Be 15
      foreach($x in $l){ (Parse-Command -Text $x -Strict $true).k | Should -Not -Be 'unknown' -Because $x }
    }
  }

  Context 'форма клавиатуры' {
    It 'ряды и кнопки как задумано, resize_keyboard и is_persistent' {
      $k=New-TgReplyKeyboard
      $k.resize_keyboard | Should -BeTrue; $k.is_persistent | Should -BeTrue
      $k.Contains('inline_keyboard') | Should -BeFalse
      $k.keyboard.Count | Should -Be 5
      ($k.keyboard | ForEach-Object { $_.Count }) -join ',' | Should -Be '3,3,2,3,4'
      $k.keyboard[0][0].text | Should -Be 'Статус'; $k.keyboard[4][3].text | Should -Be 'Помощь'
      $k.keyboard[2][1].text | Should -Be 'Перешли отчёт в Gemini'
    }
    It 'JSON: массив массивов объектов {text}, без callback_data' {
      $j=(@{ reply_markup=(New-TgReplyKeyboard) } | ConvertTo-Json -Depth 10 -Compress)
      $j | Should -Match '"keyboard":\[\[\{"text":"Статус"\},'
      $j | Should -Match '"resize_keyboard":true'; $j | Should -Match '"is_persistent":true'
      $j | Should -Not -Match 'callback_data'
      $o=$j | ConvertFrom-Json; @($o.reply_markup.keyboard).Count | Should -Be 5; @($o.reply_markup.keyboard[1]).Count | Should -Be 3
    }
    It 'надписи кнопок ≤ 64 символов и без «/» (это текст, а не slash-команда)' {
      foreach($x in Get-TgReplyLabels){ $x.Length | Should -BeLessOrEqual 64; $x | Should -Not -Match '^/' }
    }
  }

  Context 'куда прикрепляется' {
    It '«помощь» — с клавиатурой' {
      Handle-Command 'Помощь' 'tg'
      $s=(Sent '*Команды*'); $s.Count | Should -Be 1
      $s[0].b.reply_markup.keyboard.Count | Should -Be 5
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
      $s[0].b.Contains('reply_markup') | Should -BeFalse; $s[1].b.reply_markup.keyboard.Count | Should -Be 5
    }
    It 'TgReplyKeyboard=false — ни в «помощи», ни при запуске клавиатуры нет' {
      $Cfg.TgReplyKeyboard=$false
      Get-TgReplyMarkup | Should -BeNullOrEmpty
      Handle-Command 'помощь' 'tg'
      (Sent '*Команды*')[0].b.Contains('reply_markup') | Should -BeFalse
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
