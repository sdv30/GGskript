BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  function New-Report($name,$text='отчёт'){ $p=Join-Path $Cfg.Downloads $name; [IO.File]::WriteAllText($p,$text); Get-Item $p }
  function Reset-Tg{
    $script:TgToken='TEST'; $script:TgChat='42'; $script:TgCalls=New-Object System.Collections.ArrayList; $script:MsgId=100; $script:Uploads=New-Object System.Collections.ArrayList
    $script:TgPrompts.Clear(); $script:TgAwait=$null; $script:Queue.Clear(); $script:Busy=$false; $script:Paused=$false; $script:PendingConfirm=$null; $script:Blk=@{key=$null}
  }
  function Sent([string]$Like='*'){ ,@($script:TgCalls | Where-Object { $_.m -eq 'sendMessage' -and $_.b.text -like $Like }) }
  function Calls([string]$M){ ,@($script:TgCalls | Where-Object { $_.m -eq $M }) }
  function LastPrompt{ @($script:TgPrompts.Values)[-1] }
  function Press($p,[string]$choice,[string]$cb='cb1'){ Handle-Callback "p:$($p.id):$choice" $cb $p.msgId }
}
Describe 'Пункт 21: Telegram — кнопки, копия ответа, пересылка' -Tag Item21 {
  BeforeEach {
    Reset-Tg
    $Cfg.TgOfferForward=$true; $Cfg.TgPromptTimeoutMin=30; $Cfg.TgAwaitTextMin=10; $Cfg.TgCopyFileAfterParts=3; $Cfg.TgCopyMaxMessages=10; $Cfg.TgMaxLen=4096; $Cfg.TgConfirmAg=$false
    Remove-Item $Cfg.AnswerDir -Recurse -Force -EA 0
    Mock Log {}
    Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query }); if($Method -eq 'sendMessage'){ $script:MsgId++; @{ ok=$true; result=@{ message_id=$script:MsgId } } } else { @{ ok=$true; result=$true } } }
    Mock Invoke-TgUpload { [void]$script:Uploads.Add(@{ m=$Method; f=$Fields; field=$FileField; path=$Path; name=$FileName; text=[IO.File]::ReadAllText($Path) }) }
  }

  Context 'разбиение на части ≤ 4096' {
    It 'по абзацам, ничего не теряется' {
      $paras=1..40 | ForEach-Object { ('Абзац {0}: ' -f $_) + ('текст ' * 30).Trim() }
      $t=$paras -join "`n`n"
      $parts=@(Split-TgParagraphs $t 1000)
      $parts.Count | Should -BeGreaterThan 1
      $parts | ForEach-Object { $_.Length | Should -BeLessOrEqual 1000 }
      ($parts -join "`n`n") | Should -Be $t
      $parts | ForEach-Object { $_ | Should -Match '^Абзац \d+:' }
    }
    It 'длинная строка кириллицы без пробелов — режет ровно по лимиту, без потерь' {
      $t='я'*10000; $parts=@(Split-TgParagraphs $t 4096)
      $parts.Count | Should -Be 3; $parts[0].Length | Should -Be 4096; ($parts -join '') | Should -Be $t
    }
    It 'суррогатные пары (эмодзи) не разрываются' {
      $e=[char]::ConvertFromUtf32(0x1F600); $t='a'+($e*3000)   # 1 + 6000 UTF-16 единиц
      $parts=@(Split-TgParagraphs $t 4096)
      foreach($p in $parts){ $p.Length | Should -BeLessOrEqual 4096; [char]::IsHighSurrogate($p[$p.Length-1]) | Should -BeFalse; [char]::IsLowSurrogate($p[0]) | Should -BeFalse }
      ($parts -join '') | Should -Be $t
    }
    It 'короткий текст — одна часть, ровно 4096 — одна часть' {
      @(Split-TgParagraphs 'привет').Count | Should -Be 1
      @(Split-TgParagraphs ('ж'*4096) 4096).Count | Should -Be 1
    }
    It 'клавиатура: ряд из одной кнопки остаётся массивом (JSON для PS 5.1 и 7)' {
      $j=(New-TgKeyboard 'Да=copy|Нет=no;Переслать в Antigravity=toag' 'p:ab1:') | ConvertTo-Json -Depth 10 -Compress
      $j | Should -Match '"inline_keyboard":\[\[\{"text":"Да","callback_data":"p:ab1:copy"\},\{"text":"Нет","callback_data":"p:ab1:no"\}\],\[\{"text":"Переслать в Antigravity","callback_data":"p:ab1:toag"\}\]\]'
    }
  }

  Context 'разбор новых команд' {
    It '«<t>» -> <k>' -TestCases @(
      @{t='перешли ответ в Antigravity';k='fwdans'},@{t='Перешли ответ в антигравити';k='fwdans'},@{t='/toag';k='fwdans'},@{t='/toag@GGbot';k='fwdans'},
      @{t='перешли ответ в Gemini';k='fwdrep'},@{t='перешли ответ в джемини';k='fwdrep'},@{t='перешли отчёт в Gemini';k='fwdrep'},@{t='/togemini';k='fwdrep'},
      @{t='напиши';k='write'},@{t='Напиши.';k='write'},@{t='/send';k='write'},@{t='/send привет';k='write'},
      @{t='напиши джемини: привет';k='gemini'},@{t='/gemini тест';k='gemini'},@{t='/ag тест';k='ag'},@{t='передай весь ответ';k='relay'},@{t='передай ответ';k='relay'}
    ) { (Parse-Command -Text $t -Strict $true).k | Should -Be $k }
    It 'без ложных срабатываний: «<t>» -> <k>' -TestCases @(
      @{t='перешли мне ответ';k='unknown'},@{t='напиши пожалуйста';k='unknown'},@{t='перешли ответ в Antigravity завтра';k='unknown'},
      @{t='я напишу позже';k='unknown'},@{t='ответ в Gemini хороший';k='unknown'},@{t='/sender';k='unknown'},@{t='!asknocode x.md';k='asknocode'}
    ) { (Parse-Command -Text $t -Strict $true).k | Should -Be $k }
    It '/send <текст> сохраняет текст' { (Parse-Command "/send строка 1`nстрока 2").arg | Should -Be "строка 1`nстрока 2" }
    It 'помощь перечисляет новые команды' { $HelpText | Should -Match 'перешли ответ в Antigravity'; $HelpText | Should -Match 'перешли ответ в Gemini'; $HelpText | Should -Match '/send' }
  }

  Context 'сценарий А: ответ без блока Markdown' {
    BeforeEach {
      $script:St=New-RelayState; $script:QStopG=$false; $script:QStopA=$false; $script:LimitStop=$false; $script:StaleNotified=@{}
      $script:whole="Я не могу продолжить без решения.`n`nВариант 1: ...`n`nВариант 2: ..."
      Mock Save-State {}; Mock Wait-FileStable {}; Mock Gem-GetModel { 'Argon Высокая' }; Mock Gem-Send { @{ before=1; pBefore=1 } }; Mock Gem-WaitAnswer { 1 }
      Mock Gem-CountPrompts { 2 }; Mock Gem-LastReportPrompt { $null }; Mock Gem-CopyCode { $null }; Mock Gem-CopyWhole { $script:whole }; Mock Ag-Send {}
      Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    }
    It 'вопрос с кнопками, полный ответ сохранён один раз, этап nocode, в Antigravity ничего' {
      $f=New-Report 'A_2026-10-18_004.md'; Process-File $f
      Get-Stage $f.Name | Should -Be 'nocode'; Should -Invoke Ag-Send -Times 0; Should -Invoke Gem-CopyWhole -Times 1 -Exactly
      $q=Sent 'ℹ️ Gemini ответил на A_2026-10-18_004.md, но без блока Markdown (похоже, объяснение или вопрос). В Antigravity ничего не отправлено. Прислать копию ответа?*'
      $q.Count | Should -Be 1
      $kb=$q[0].b.reply_markup.inline_keyboard
      @($kb[0] | ForEach-Object { $_.text }) -join ',' | Should -Be 'Да,Нет'
      $kb[1][0].text | Should -Be 'Переслать в Antigravity'; $kb[2][0].text | Should -Be 'Написать ответ Gemini'
      [IO.File]::ReadAllText((Get-FullAnswerPath $f.Name)) | Should -Be $script:whole
    }
    It '«Да» — копия ответа, answerCallbackQuery, кнопки убраны и помечены' {
      $f=New-Report 'A_2026-10-18_004.md'; Process-File $f; $p=LastPrompt
      Press $p 'copy'
      (Sent '📄 Ответ Gemini на A_2026-10-18_004.md:*').Count | Should -Be 1
      (Sent '📄*')[0].b.text | Should -BeLike "*$($script:whole)"
      (Calls 'answerCallbackQuery').Count | Should -Be 1
      $e=Calls 'editMessageText'; $e.Count | Should -Be 1; $e[0].b.message_id | Should -Be $p.msgId; $e[0].b.text | Should -BeLike '*— выбрано: «Да»'
      $script:Uploads.Count | Should -Be 0
    }
    It 'повторное нажатие — не дублирует (идемпотентность), отвечает «Уже выбрано»' {
      $f=New-Report 'A_2026-10-18_004.md'; Process-File $f; $p=LastPrompt
      Press $p 'copy'; Press $p 'copy' 'cb2'; Press $p 'no' 'cb3'
      (Sent '📄*').Count | Should -Be 1; (Sent 'Ок, копию*').Count | Should -Be 0
      @((Calls 'answerCallbackQuery') | Where-Object { $_.b.text -like 'Уже выбрано*' }).Count | Should -Be 2
    }
    It 'текстовый «да» ответом-reply на вопрос — копия; второй «да» — «вопрос уже закрыт»' {
      $f=New-Report 'A_2026-10-18_004.md'; Process-File $f; $p=LastPrompt
      Handle-Command 'да' 'tg' -ReplyTo $p.msgId
      (Sent '📄*').Count | Should -Be 1
      Handle-Command 'да' 'tg' -ReplyTo $p.msgId
      (Sent 'Этот вопрос уже закрыт*').Count | Should -Be 1; (Sent '📄*').Count | Should -Be 1
    }
    It 'текстовый «нет» без reply — последнему открытому вопросу' {
      $f=New-Report 'A_2026-10-18_004.md'; Process-File $f
      Handle-Command 'нет' 'tg'
      (Sent 'Ок, копию не присылаю.').Count | Should -Be 1; (LastPrompt).done | Should -Be 'no'
    }
    It 'длинный ответ: части ≤ 4096 по абзацам + файл .md (sendDocument), если частей больше 3' {
      $script:whole=(1..60 | ForEach-Object { "Абзац $_ " + ('слово ' * 60) }) -join "`n`n"   # ~22 000 симв.
      $f=New-Report 'A_2026-10-18_005.md'; Process-File $f; Press (LastPrompt) 'copy'
      $parts=Sent '📄*'; $parts.Count | Should -BeGreaterThan 3
      $parts | ForEach-Object { $_.b.text.Length | Should -BeLessOrEqual 4096 }
      $parts[0].b.text | Should -BeLike "📄 Ответ Gemini на A_2026-10-18_005.md (1/$($parts.Count)):*"
      $script:Uploads.Count | Should -Be 1; $script:Uploads[0].m | Should -Be 'sendDocument'; $script:Uploads[0].field | Should -Be 'document'
      $script:Uploads[0].name | Should -Be 'A_2026-10-18_005_answer.md'; $script:Uploads[0].text | Should -Be $script:whole
    }
    It 'очень длинный: не больше TgCopyMaxMessages сообщений, остальное — в файле' {
      $Cfg.TgCopyMaxMessages=2; $script:whole=(1..60 | ForEach-Object { "Абзац $_ " + ('слово ' * 60) }) -join "`n`n"
      $f=New-Report 'A_2026-10-18_006.md'; Process-File $f; Press (LastPrompt) 'copy'
      (Sent '📄*').Count | Should -Be 2; $script:Uploads.Count | Should -Be 1; (Sent 'Показал 2 из *').Count | Should -Be 1
    }
    It 'полный текст не сохранился — честно говорит, копию не выдумывает' {
      Mock Gem-CopyWhole { $null }; Mock GemCdp-GetWhole { throw 'нет CDP' }
      $f=New-Report 'A_2026-10-18_007.md'; Process-File $f
      (Sent '*Полный текст ответа сохранить не удалось*').Count | Should -Be 1
      Press (LastPrompt) 'copy'
      (Sent 'Полный текст ответа на A_2026-10-18_007.md не сохранён*').Count | Should -Be 1; (Sent '📄*').Count | Should -Be 0
    }
    It 'кнопка кода копирования не сработала — берёт текст по CDP (только чтение)' {
      Mock Gem-CopyWhole { throw 'кнопка не найдена' }; Mock GemCdp-GetWhole { 'текст из DOM' }
      $f=New-Report 'A_2026-10-18_008.md'; Process-File $f
      [IO.File]::ReadAllText((Get-FullAnswerPath $f.Name)) | Should -Be 'текст из DOM'
    }
    It '«Переслать в Antigravity» — подтверждение с первыми 200 символами; «Отправить» — через очередь, этап → relayed' {
      $script:whole='Ж'*500
      $f=New-Report 'A_2026-10-18_009.md'; Process-File $f; Press (LastPrompt) 'toag'
      $c=LastPrompt; $c.kind | Should -Be 'confirm'
      $c.text | Should -BeLike "Подтвердите: в Antigravity (младшая модель) уйдёт весь ответ Gemini на A_2026-10-18_009.md*500 симв. целиком*«$('Ж'*200)…»"
      Should -Invoke Ag-Send -Times 0
      Press $c 'send'
      $script:Queue.Count | Should -Be 1; Should -Invoke Ag-Send -Times 0
      Run-Action $script:Queue.Dequeue()
      Should -Invoke Ag-Send -Times 1 -Exactly -ParameterFilter { $Text -eq ('Ж'*500) }
      Get-Stage $f.Name | Should -Be 'relayed'
      (Sent '✅ Доставлено в Antigravity: весь ответ Gemini*').Count | Should -Be 1
    }
    It '«Отмена» в подтверждении — ничего не отправлено' {
      $f=New-Report 'A_2026-10-18_010.md'; Process-File $f; Press (LastPrompt) 'toag'; Press (LastPrompt) 'cancel'
      $script:Queue.Count | Should -Be 0; (Sent 'Отменено, ничего не отправлено.').Count | Should -Be 1
    }
    It '«Написать ответ Gemini» — ждёт текст, потом «Отправить в Gemini?»' {
      $f=New-Report 'A_2026-10-18_011.md'; Process-File $f; Press (LastPrompt) 'writegem'
      (Sent '✏️ Введите текст для Gemini*').Count | Should -Be 1
      Handle-Command 'Выбираю вариант 2' 'tg'
      $p=LastPrompt; $p.kind | Should -Be 'where'; @($p.labels.Keys) -contains 'gemini' | Should -BeTrue; @($p.labels.Keys) -contains 'ag' | Should -BeFalse
    }
  }

  Context 'таймауты, устаревшие кнопки, чужой chat_id' {
    It 'время вышло — кнопка не срабатывает, сообщение помечается' {
      $p=Ask-WhereToSend -Text 'привет' -Kind 'offer'; $p.expires=(Get-Date).AddMinutes(-1)
      Press $p 'ag'
      $script:Queue.Count | Should -Be 0
      (Calls 'answerCallbackQuery')[0].b.text | Should -BeLike 'Время ответа вышло*'
      (Calls 'editMessageText')[0].b.text | Should -BeLike '*Время ответа вышло*'
    }
    It 'Sweep помечает просроченные вопросы один раз' {
      $p=Ask-WhereToSend -Text 'привет' -Kind 'offer'; $p.expires=(Get-Date).AddMinutes(-1)
      Sweep-TgPrompts; Sweep-TgPrompts
      (Calls 'editMessageText').Count | Should -Be 1; $p.done | Should -Be 'expired'
    }
    It 'кнопка неизвестного вопроса (после перезапуска) — «устарела», кнопки убираются, ничего не делается' {
      Handle-Callback 'p:abcd99:copy' 'cbX' 555
      (Calls 'answerCallbackQuery')[0].b.text | Should -BeLike 'Кнопка устарела*'
      (Calls 'editMessageReplyMarkup')[0].b.message_id | Should -Be 555
      $script:Queue.Count | Should -Be 0; (Sent).Count | Should -Be 0
    }
    It 'мусорные callback_data — «Неизвестная кнопка»' { Handle-Callback 'zzz' 'cb' 1; (Calls 'answerCallbackQuery')[0].b.text | Should -Be 'Неизвестная кнопка' }
    It 'нажатие из чужого chat_id — игнорируется, вопрос не закрыт' {
      $p=Ask-WhereToSend -Text 'привет' -Kind 'offer'
      $script:StartUnix=0; $script:TgOffset=0
      $upd=@{ result=@(@{ update_id=7; callback_query=@{ id='cbE'; data="p:$($p.id):ag"; from=@{ id=666; username='evil' }; message=@{ message_id=$p.msgId; chat=@{ id=666 } } } }) }
      Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query }); if($Method -eq 'getUpdates'){ $upd } else { @{ ok=$true; result=$true } } }
      Poll-Tg
      $p.done | Should -BeNullOrEmpty; $script:Queue.Count | Should -Be 0
      (Calls 'answerCallbackQuery')[0].b.text | Should -Be 'Нет доступа'
      (Calls 'getUpdates')[0].q | Should -BeLike '*allowed_updates=*callback_query*'
    }
    It 'нажатие из своего чата через getUpdates — срабатывает' {
      $p=Ask-WhereToSend -Text 'привет' -Kind 'offer'
      $script:StartUnix=0; $script:TgOffset=0
      $upd=@{ result=@(@{ update_id=8; callback_query=@{ id='cbOk'; data="p:$($p.id):ag"; from=@{ id=42 }; message=@{ message_id=$p.msgId; chat=@{ id=42 } } } }) }
      Mock Invoke-Tg { [void]$script:TgCalls.Add(@{ m=$Method; b=$Body; q=$Query }); if($Method -eq 'getUpdates'){ $upd } else { @{ ok=$true; result=@{ message_id=1 } } } }
      Poll-Tg
      $p.done | Should -Be 'ag'; $script:Queue.Count | Should -Be 1; $script:Queue.Peek().text | Should -Be 'привет'
    }
    It 'reply в сообщении передаётся в Handle-Command (да/нет ответом на вопрос)' {
      $script:StartUnix=0; $script:TgOffset=0
      $upd=@{ result=@(@{ update_id=9; message=@{ text='да'; date=10; chat=@{ id=42 }; from=@{ id=42 }; reply_to_message=@{ message_id=321 } } }) }
      Mock Invoke-Tg { if($Method -eq 'getUpdates'){ $upd } else { @{ ok=$true } } }
      Mock Handle-Command {}
      Poll-Tg
      Should -Invoke Handle-Command -Times 1 -ParameterFilter { $Text -eq 'да' -and $ReplyTo -eq 321 }
    }
    It '«напиши»: время ввода вышло — сообщение один раз, следующий текст — обычный' {
      Handle-Command 'напиши' 'tg'; $script:TgAwait.until=(Get-Date).AddMinutes(-1)
      Sweep-TgPrompts; Sweep-TgPrompts
      (Sent '⌛ Время ввода текста вышло*').Count | Should -Be 1
      Handle-Command 'просто мысль вслух' 'tg'
      (LastPrompt).kind | Should -Be 'offer'
    }
  }

  Context 'свободный текст и «напиши»' {
    BeforeEach { Mock Ag-Send {}; Mock Send-GeminiManual {}; $script:St=New-RelayState; Mock Save-State {} }
    It '«напиши» → «Введите текст» → текст → «Куда переслать?» → Antigravity → доставлено' {
      Handle-Command 'напиши' 'tg'
      (Sent '✏️ Введите текст одним сообщением*').Count | Should -Be 1
      Handle-Command "запусти тесты`nи пришли отчёт" 'tg'
      $p=LastPrompt; $p.text | Should -BeLike 'Куда переслать?*'
      @($p.labels.Values) -join ',' | Should -Be 'Gemini,Antigravity,Отмена'
      Press $p 'ag'
      Run-Action $script:Queue.Dequeue()
      Should -Invoke Ag-Send -Times 1 -ParameterFilter { $Text -eq "запусти тесты`nи пришли отчёт" }
      (Sent '✅ Доставлено в Antigravity: ваш текст*').Count | Should -Be 1
    }
    It 'во время ожидания текста слово-команда тоже считается текстом, «отмена» — отменяет' {
      Handle-Command 'напиши' 'tg'; Handle-Command 'статус' 'tg'
      (LastPrompt).data.text | Should -Be 'статус'
      Handle-Command 'напиши' 'tg'; Handle-Command 'отмена' 'tg'
      (Sent 'Отменено, ничего не отправлено.').Count | Should -Be 1
    }
    It '/send <текст> — сразу «Куда переслать?»; Gemini → ручная отправка в Gemini' {
      Handle-Command '/send привет, Gemini' 'tg'; Press (LastPrompt) 'gemini'
      Run-Action $script:Queue.Dequeue()
      Should -Invoke Send-GeminiManual -Times 1 -ParameterFilter { $Text -eq 'привет, Gemini' }
    }
    It 'текст не-команда — «Это не команда. Переслать этот текст?» с Gemini / Antigravity / Нет; «Нет» — ничего' {
      Handle-Command 'вот мысль для агента' 'tg'
      $p=LastPrompt; $p.kind | Should -Be 'offer'; $p.text | Should -BeLike 'Это не команда. Переслать этот текст?*'
      @($p.labels.Values) -join ',' | Should -Be 'Gemini,Antigravity,Нет'
      Press $p 'cancel'; $script:Queue.Count | Should -Be 0
    }
    It 'TgOfferForward=false — прежнее «Не понял команду»; с ПК и слэш-команды — не предлагает' {
      $Cfg.TgOfferForward=$false; Handle-Command 'вот мысль' 'tg'; (Sent 'Не понял команду*').Count | Should -Be 1
      $Cfg.TgOfferForward=$true; Handle-Command 'вот мысль' 'pc'; Handle-Command '/unknowncmd' 'tg'
      (Sent 'Не понял команду*').Count | Should -Be 3; $script:TgPrompts.Count | Should -Be 0
    }
    It '«да» на вопрос «куда» — просит выбрать кнопкой' {
      Handle-Command 'вот мысль' 'tg'; Handle-Command 'да' 'tg'
      (Sent 'Выберите кнопкой*').Count | Should -Be 1; $script:Queue.Count | Should -Be 0
    }
    It 'во время передачи — в очередь, не отправляет сразу' {
      $script:Busy=$true
      Handle-Command 'вот мысль' 'tg'; Press (LastPrompt) 'ag'
      (Sent '🕐 Принял. Сейчас идёт передача*').Count | Should -Be 1
      Should -Invoke Ag-Send -Times 0; $script:Queue.Count | Should -Be 1
    }
    It 'очередь выполняется главным циклом после шага (не посреди передачи)' {
      Handle-Command 'вот мысль' 'tg'; Press (LastPrompt) 'ag'
      Mock Pump {}; Mock Nap {}; Mock Check-Blocking {}; Mock Process-File {}
      $Cfg.QuotaEveryMin=0; $script:NeedStart=$false
      Invoke-MainStep | Should -Be 'continue'
      Should -Invoke Ag-Send -Times 1 -Exactly; Should -Invoke Process-File -Times 0
    }
    It 'пауза пользователя — в Antigravity не отправляется, понятная ошибка' {
      $script:Paused=$true
      { Invoke-ChatAction @{ k='fwdtext'; target='ag'; text='x'; what='ваш текст' } } | Should -Throw -ExceptionType ([GG.RelayPausedException])
      Should -Invoke Ag-Send -Times 0
    }
    It '/ag и /gemini не сломаны: идут прежним путём (в очередь, без новых вопросов)' {
      Handle-Command '/ag тест' 'tg'; $script:Queue.Dequeue().k | Should -Be 'ag'
      Handle-Command '/gemini тест' 'tg'; $script:Queue.Dequeue().k | Should -Be 'gemini'
      $script:TgPrompts.Count | Should -Be 0
    }
  }

  Context '«перешли ответ в Antigravity / Gemini»' {
    BeforeEach {
      $script:St=New-RelayState; Mock Save-State {}; Mock Ag-Send {}
      Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    }
    It '«перешли ответ в Antigravity»: берёт ответ в очереди, показывает начало, по «Отправить» — весь ответ' {
      Mock Gem-CopyWhole { "Полный ответ Gemini`n`nс абзацами" }
      Handle-Command 'перешли ответ в Antigravity' 'tg'
      Should -Invoke Gem-CopyWhole -Times 0
      Run-Action $script:Queue.Dequeue()
      $p=LastPrompt; $p.text | Should -BeLike 'Подтвердите: в Antigravity (младшая модель) уйдёт последний ответ Gemini целиком*«Полный ответ Gemini*'
      Press $p 'send'; Run-Action $script:Queue.Dequeue()
      Should -Invoke Ag-Send -Times 1 -ParameterFilter { $Text -eq "Полный ответ Gemini`n`nс абзацами" }
    }
    It '«передай весь ответ» из Telegram — тот же путь с подтверждением' {
      Handle-Command 'передай весь ответ' 'tg'; $script:Queue.Peek().k | Should -Be 'fwdans-prep'
    }
    It '«перешли ответ в Gemini»: подтверждение прямо говорит, что и откуда; «Отправить» — этап resend' {
      New-Report 'A_2026-10-18_001.md' 'первый' | Out-Null; [void](Set-FileStage $script:St 'A_2026-10-18_001.md' 'sent'); [void](Set-FileStage $script:St 'A_2026-10-18_001.md' 'relayed')
      $f=New-Report 'A_2026-10-18_002.md' 'Отчёт агента: сделал задачу 2'
      [void](Set-FileStage $script:St $f.Name 'sent'); [void](Set-FileStage $script:St $f.Name 'relayed')
      Handle-Command 'перешли ответ в Gemini' 'tg'
      $p=LastPrompt; $p.text | Should -BeLike '*в Gemini заново уйдёт последний отчёт агента Antigravity — файл A_2026-10-18_002.md из Downloads*«Файл отчёта: A_2026-10-18_002.md» + содержимое*Отчёт агента: сделал задачу 2*'
      Press $p 'send'; Run-Action $script:Queue.Dequeue()
      Get-Stage $f.Name | Should -Be 'resend'; (Next-File).Name | Should -Be $f.Name
    }
    It 'команды пересылки с ПК — не выполняются без кнопок' {
      Handle-Command 'перешли ответ в Antigravity' 'pc'; $script:Queue.Count | Should -Be 0
    }
  }

  Context 'ручной текст в Gemini: учёт этапов' {
    BeforeEach {
      $script:St=New-RelayState; $script:QStopG=$false; $script:QStopA=$false; Mock Save-State {}
      Mock Gem-GetModel { 'Argon Высокая' }; Mock Gem-Send { @{ before=1; pBefore=1 } }; Mock Gem-WaitAnswer { 1 }; Mock Gem-CountPrompts { 2 }
      Mock Gem-CopyWhole { "Ответ`n``````markdown`n## Задача`n``````" }; Mock Ag-Send {}
    }
    It 'в ответе есть блок — спрашивает «Переслать блок в Antigravity?»; «Да» — пересылает блок' {
      Mock Gem-CopyCode { "## Задача`nсделай" }
      Send-GeminiManual 'вопрос'
      (Sent '✅ Доставлено в Gemini*').Count | Should -Be 1
      $p=LastPrompt; $p.kind | Should -Be 'gemcode'; $p.text | Should -BeLike '*Переслать блок в Antigravity?'
      Should -Invoke Ag-Send -Times 0
      Press $p 'toag'; Run-Action $script:Queue.Dequeue()
      Should -Invoke Ag-Send -Times 1 -ParameterFilter { $Text -eq "## Задача`nсделай" }
      Test-RelayHash $script:St (Get-Hash8 "## Задача`nсделай") | Should -BeTrue
    }
    It 'без блока — предлагает копию (сценарий А)' {
      Mock Gem-CopyCode { $null }
      Send-GeminiManual 'вопрос'; (LastPrompt).kind | Should -Be 'nocode'
    }
    It 'отчёт ждёт ответа Gemini — ручной текст не отправляется (учёт не сбивается)' {
      [void](Set-FileStage $script:St 'A_003.md' 'sent')
      { Send-GeminiManual 'вопрос' } | Should -Throw '*ручное сообщение в Gemini сбило бы учёт*'
      Should -Invoke Gem-Send -Times 0
    }
    It 'этапы файлов ручная отправка не меняет' {
      Mock Gem-CopyCode { $null }
      [void](Set-FileStage $script:St 'A_002.md' 'sent'); [void](Set-FileStage $script:St 'A_002.md' 'relayed')
      Send-GeminiManual 'вопрос'; Get-Stage 'A_002.md' | Should -Be 'relayed'
    }
  }

  Context 'служебная !asknocode (только с ПК) — для живой проверки' {
    It 'с ПК — отправляет вопрос по сохранённому ответу; из Telegram — не срабатывает' {
      [void](Save-FullAnswer 'A_004.md' 'сохранённый ответ')
      Handle-Command '!asknocode A_004.md' 'tg'; $script:TgPrompts.Count | Should -Be 0
      Handle-Command '!asknocode A_004.md' 'pc'; (LastPrompt).kind | Should -Be 'nocode'
      Press (LastPrompt) 'copy'; (Sent '📄*сохранённый ответ').Count | Should -Be 1
    }
  }
}
