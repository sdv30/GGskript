# ===== GGskript v2: Chat — вопросы с кнопками в Telegram, копия ответа, пересылка между Gemini и Antigravity (пункт 21) =====
# Вопросы живут только в памяти процесса: после перезапуска старые кнопки отвечают «устарела» и ничего не делают.
# Отправка в агентов всегда идёт через очередь команд ($script:Queue) — выполняется между шагами, не посреди передачи.

$script:TgPrompts=[ordered]@{}; $script:TgAwait=$null; $script:PromptSeq=0
# kind → что значит текстовый «да»/«нет»
$script:PromptYesNo=@{
  nocode =@{ confirm='copy'; cancel='no' }
  confirm=@{ confirm='send'; cancel='cancel' }
  gemcode=@{ confirm='toag'; cancel='no' }
  where  =@{ cancel='cancel' }
  offer  =@{ cancel='cancel' }
  shutdown=@{ confirm='yes'; cancel='no' }
  shutwarn=@{ cancel='abort' }
  newest =@{ confirm='send'; cancel='wait' }
  exit   =@{ confirm='yes'; cancel='no' }
  proto  =@{ confirm='relay'; cancel='norelay' }
  gate   =@{ confirm='force' }   # пункт 44
  operator=@{}
}

# ---------- Сохранённые полные ответы ----------
function Get-FullAnswerPath([string]$Name){ Join-Path $Cfg.AnswerDir (([IO.Path]::GetFileNameWithoutExtension(($Name -replace '[\\/:*?"<>|]','_')))+'.full.md') }
function Save-FullAnswer([string]$Name,[string]$Text){
  try{
    if(-not (Test-Path -LiteralPath $Cfg.AnswerDir)){ New-Item -ItemType Directory -Force $Cfg.AnswerDir | Out-Null }
    $p=Get-FullAnswerPath $Name; Write-AtomicText -Path $p -Text $Text -NoBackup; Prune-Answers; $p
  }catch{ Log "Не удалось сохранить полный ответ ($($_.Exception.Message))"; $null }
}
function Prune-Answers{
  try{ $f=@(Get-ChildItem -LiteralPath $Cfg.AnswerDir -Filter '*.full.md' -File -EA Stop | Sort-Object LastWriteTime -Descending)
    if($f.Count -gt $Cfg.AnswerKeep){ $f | Select-Object -Skip $Cfg.AnswerKeep | Remove-Item -Force -EA 0 } }catch{}
}
function Read-TextFile([string]$Path){ if($Path -and (Test-Path -LiteralPath $Path)){ [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) } else { $null } }
# Весь последний ответ Gemini: кнопка «Копировать ответ» (как «что ответил джемини»), запасной путь — текст из DOM по CDP (только чтение).
function Get-WholeAnswer{
  $t=$null; $via=''
  try{ $t=Gem-CopyWhole; $via='кнопка копирования' }catch{ Log "Весь ответ: кнопка копирования не сработала ($($_.Exception.Message))" }
  if(-not $t -and $Cfg.WholeCdpFallback){ try{ $t=GemCdp-GetWhole; $via='текст страницы (CDP)' }catch{ Log "Весь ответ: CDP недоступен ($($_.Exception.Message))" } }
  @{ text=[string]$t; via=$via }
}
function Get-Preview([string]$Text,[int]$Max=200){ $x=([string]$Text).Trim(); if($x.Length -gt $Max){ $x=$x.Substring(0,$Max); if([char]::IsHighSurrogate($x[$x.Length-1])){ $x=$x.Substring(0,$x.Length-1) }; $x+'…' } else { $x } }

# ---------- Вопросы с кнопками ----------
function New-TgPrompt{
  param([string]$Kind,[string]$Text,[string]$Buttons,[hashtable]$Data=@{},[double]$TimeoutMin=$Cfg.TgPromptTimeoutMin,[int64]$ReplyTo=0)
  $script:PromptSeq++; $id='{0}{1}' -f ([Guid]::NewGuid().ToString('N').Substring(0,4)),$script:PromptSeq
  $mid=Tg-SendMsg -Text $Text -Markup (New-TgKeyboard $Buttons "p:$($id):") -ReplyTo $ReplyTo
  if($null -eq $mid){ Log "Вопрос в Telegram не отправлен: $(Format-Short $Text 120)"; return $null }
  $p=@{ id=$id; kind=$Kind; text=$Text; labels=(Get-TgButtonLabels $Buttons); data=$Data; msgId=[int64]$mid; created=(Get-Date); expires=(Get-Date).AddMinutes($TimeoutMin); done=$null }
  $script:TgPrompts[$id]=$p
  while($script:TgPrompts.Count -gt 50){ $script:TgPrompts.RemoveAt(0) }
  $p
}
function Test-PromptActive($p){ $p -and -not $p.done -and (Get-Date) -le $p.expires }
function Complete-Prompt($p,[string]$Choice){
  $lbl= if($p.labels.Contains($Choice)){ $p.labels[$Choice] } else { $Choice }
  $p.done=$Choice; $p.doneLabel=$lbl
  Tg-CloseButtons $p.msgId "$($p.text)`n`n— выбрано: «$lbl»"
  $lbl
}
function Expire-Prompt($p){ if($p.done){ return }; $p.done='expired'; $p.doneLabel='время вышло'; Tg-CloseButtons $p.msgId "$($p.text)`n`n⌛ Время ответа вышло — кнопки не действуют."
  if($p.kind -eq 'newest'){ Resolve-NewestChoice $p.data.name 'expired' }
  if($p.kind -eq 'shutdown'){ Tg-Send '⌛ Подтверждения не было — выключение компьютера НЕ запланировано.' | Out-Null } }
function Sweep-TgPrompts{
  foreach($p in @($script:TgPrompts.Values)){ if(-not $p.done -and (Get-Date) -gt $p.expires){ Expire-Prompt $p } }
  if($script:TgAwait -and (Get-Date) -gt $script:TgAwait.until){ $script:TgAwait=$null; Tg-Send '⌛ Время ввода текста вышло — ничего не отправлено.' | Out-Null }
}
function Handle-Callback([string]$Data,[string]$CbId,[int64]$MsgId){
  if($Data -notmatch '^p:([0-9a-f]{4}\d+):(\w+)$'){ Tg-AnswerCb $CbId 'Неизвестная кнопка'; return }
  $id=$matches[1]; $choice=$matches[2]
  $p= if($script:TgPrompts.Contains($id)){ $script:TgPrompts[$id] } else { $null }
  if(-not $p){ Tg-AnswerCb $CbId 'Кнопка устарела (вопрос старый или GGskript перезапускался)'; Tg-CloseButtons $MsgId ''; return }
  if($p.done){ Tg-AnswerCb $CbId "Уже выбрано: «$($p.doneLabel)»"; return }
  if((Get-Date) -gt $p.expires){ Expire-Prompt $p; Tg-AnswerCb $CbId 'Время ответа вышло — кнопка не действует'; return }
  if(-not $p.labels.Contains($choice)){ Tg-AnswerCb $CbId 'Неизвестная кнопка'; return }
  $lbl=Complete-Prompt $p $choice
  Tg-AnswerCb $CbId "Выбрано: $lbl"
  Invoke-PromptChoice $p $choice
}
# Текстовый «да»/«нет»: сначала вопрос, на который ответили reply, иначе последний открытый вопрос с таким смыслом.
# $true — ответ принят (или объяснено, почему нет); $false — открытых вопросов нет.
function Resolve-TextAnswer([string]$K,[int64]$ReplyTo=0){
  $p=$null
  if($ReplyTo){
    $p=@($script:TgPrompts.Values | Where-Object { $_.msgId -eq $ReplyTo }) | Select-Object -First 1
    if($p -and -not (Test-PromptActive $p)){ Tg-Send "Этот вопрос уже закрыт ($(if($p.doneLabel){"«$($p.doneLabel)»"}else{'время вышло'}))." | Out-Null; return $true }
  }
  if(-not $p){ $p=@($script:TgPrompts.Values | Where-Object { Test-PromptActive $_ }) | Select-Object -Last 1 }
  if(-not $p){ return $false }
  $choice=$script:PromptYesNo[$p.kind][$K]
  if(-not $choice){ Tg-Send $(if($p.kind -in 'where','offer'){'Выберите кнопкой, куда переслать: Gemini или Antigravity (или «нет»).'}else{'Ответьте кнопкой под вопросом.'}) | Out-Null; return $true }
  [void](Complete-Prompt $p $choice)
  Invoke-PromptChoice $p $choice
  $true
}
function Queue-ChatAction([hashtable]$C){
  $C.src='tg'; $script:Queue.Enqueue($C)
  if($script:Busy){ Tg-Send '🕐 Принял. Сейчас идёт передача — выполню сразу после текущего шага.' | Out-Null } else { Tg-Send '🕐 Принял, выполняю…' | Out-Null }
}
function Invoke-PromptChoice($p,[string]$Choice){
  $d=$p.data
  switch($p.kind){
    'nocode' {
      switch($Choice){
        'copy'     { Send-AnswerCopy $d.full $d.label }
        'no'       { Tg-Send 'Ок, копию не присылаю.' | Out-Null }
        'toag'     { $t=Read-TextFile $d.full
                     if(-not $t){ Tg-Send "Полный текст ответа на $($d.label) не сохранён — переслать нечего. «перешли ответ в Antigravity» возьмёт текущий последний ответ Gemini (с подтверждением)." | Out-Null }
                     else{ Start-ForwardConfirm -Target 'ag' -Text $t -What "весь ответ Gemini на $($d.label) (сохранённый в момент ответа)" -File $d.file } }
        'writegem' { Start-AwaitText -Target 'gemini' }
      }
    }
    'gemcode' {
      switch($Choice){
        'toag' { $t=Read-TextFile $d.code; if(-not $t){ Tg-Send 'Блок Markdown не сохранён — переслать нечего.' | Out-Null } else { Queue-ChatAction @{ k='fwdtext'; target='ag'; text=$t; what='блок Markdown из ответа Gemini'; relay=$true } } }
        'copy' { Send-AnswerCopy $d.full $d.label }
        'no'   { Tg-Send 'Ок, в Antigravity не пересылаю.' | Out-Null }
      }
    }
    'gate'     { if($Choice -eq 'force'){ Queue-ChatAction @{ k='force' } } elseif($Choice -eq 'resend'){ Queue-ChatAction @{ k='resendstale' } } }   # пункт 44
    'operator' { if($Choice -eq 'write'){ Start-AwaitText -Target 'gemini' } elseif($Choice -eq 'resend'){ Queue-ChatAction @{ k='resendstale' } } }
    'shutdown' { if($Choice -eq 'yes'){ Confirm-Shutdown $d } else { Tg-Send 'Ок, компьютер не выключаю.' | Out-Null } }
    'newest'   { Resolve-NewestChoice $d.name $Choice }
    'exit'     { if($Choice -eq 'yes'){ Log 'Выключение скрипта (подтверждено в Telegram)'; Tg-Send 'Выключаю GGskript. Запустить снова — ярлыком GGskript на ПК.' | Out-Null; $script:StopReq=$true } else { Tg-Send 'Ок, GGskript не выключаю.' | Out-Null } }
    'proto'    { if($Choice -eq 'relay'){ [void](Set-FileStage -State $script:St -Name $d.name -Stage 'sent' -Note 'протокол запуска: передать ответ по кнопке' -Force); Save-State; $script:Adopted[$d.name]=$true; Tg-Send "Ок, заберу ответ на $($d.name) (только блок Markdown) и передам в Antigravity$(if($script:Paused){' после «Старт»'})." | Out-Null } else { Tg-Send "Ок, ответ на $($d.name) не передаю." | Out-Null } }
    'shutwarn' { if($Choice -eq 'abort'){ Cancel-Shutdown } }
    'confirm' { if($Choice -eq 'send'){ Queue-ChatAction $d.action } else { Tg-Send 'Отменено, ничего не отправлено.' | Out-Null } }
    { $_ -in 'where','offer' } {
      if($Choice -in 'gemini','ag'){ Queue-ChatAction @{ k='fwdtext'; target=$Choice; text=$d.text; what='ваш текст'; ask=$true } }
      else { Tg-Send 'Ок, не пересылаю.' | Out-Null }
    }
  }
}

# ---------- Сценарии ----------
function Send-NoCodePrompt([string]$Label,[string]$Model,[string]$FullPath,[string]$File=''){
  $t=Read-TextFile $FullPath
  $info= if($t){ "Ответ: $($t.Length) симв., начало: «$(Get-Preview $t 150)»" } else { 'Полный текст ответа сохранить не удалось — копию прислать не смогу.' }
  $ol=@($script:LastCodeLangs | ForEach-Object { $l=[string]$_; if($l){ $l } else { 'без подписи' } })
  if($ol.Count){ $info+="`nДругие блоки в ответе (их НЕ передаю — беру только «$($Cfg.CodeBlockLang)»): $($ol -join ', ')" }
  $msg="ℹ️ Gemini ответил на $Label, но без блока Markdown (похоже, объяснение или вопрос). В Antigravity ничего не отправлено. Прислать копию ответа?`n$(if($Model){"Модель: $Model. "})$info`nЕщё можно: «Переслать в Antigravity» — весь ответ (покажу, что уйдёт, и спрошу), «Написать ответ Gemini» — ваш текст в Gemini."
  New-TgPrompt -Kind 'nocode' -Text $msg -Buttons 'Да=copy|Нет=no;Переслать в Antigravity=toag;Написать ответ Gemini=writegem' -Data @{ label=$Label; full=$FullPath; file=$File }
}
function Send-AnswerCopy([string]$Path,[string]$Label,[string]$Who='Gemini'){
  $t=Read-TextFile $Path
  if($t -and $script:LogReplies){ Log ("📄 Ответ $Who на $($Label):`r`n"+(($t -replace "`r?`n","`r`n").TrimEnd())) }
  if(-not $t){ Tg-Send "Полный текст ответа на $Label не сохранён (не удалось скопировать в момент ответа), поэтому копию прислать не могу. «что ответил джемини» пришлёт текущий последний ответ из окна Gemini." | Out-Null; return }
  $parts=@(Split-TgParagraphs $t ($Cfg.TgMaxLen-120)); $k=$parts.Count; $lim=[Math]::Min($k,[int]$Cfg.TgCopyMaxMessages)
  for($i=0;$i -lt $lim;$i++){ $h= if($k -gt 1){ "📄 Ответ $Who на $Label ($($i+1)/$k):" } else { "📄 Ответ $Who на $($Label):" }; [void](Tg-SendMsg -Text "$h`n`n$($parts[$i])") }
  if($k -gt $Cfg.TgCopyFileAfterParts){
    $fn=([IO.Path]::GetFileNameWithoutExtension(($Label -replace '[\\/:*?"<>|\s]','_')))+'_answer.md'
    $ok=Tg-SendDocument $Path "Ответ $Who на $Label целиком ($($t.Length) симв.)" $fn
    if($lim -lt $k){ Tg-Send "Показал $lim из $k частей; $(if($ok){'полный текст — в файле выше'}else{'файл отправить не удалось'})." | Out-Null }
  }
  Log "Копия ответа на $Label отправлена в Telegram ($($t.Length) симв., частей: $k)"
}
function Start-ForwardConfirm([string]$Target,[string]$Text,[string]$What,[string]$File=''){
  $tn= if($Target -eq 'ag'){ 'Antigravity (младшая модель)' } else { 'Gemini' }
  $act=@{ k='fwdtext'; target=$Target; text=$Text; what=$What; file=$File }
  New-TgPrompt -Kind 'confirm' -Text "Подтвердите: в $tn уйдёт $What — $($Text.Length) симв. целиком. Начало:`n«$(Get-Preview $Text 200)»" -Buttons 'Отправить=send|Отмена=cancel' -Data @{ action=$act } | Out-Null
}
function Start-ReportResendConfirm{
  $f=@(Get-Files) | Select-Object -Last 1
  if(-not $f){ Tg-Send 'В Downloads нет отчётов агента — пересылать нечего.' | Out-Null; return }
  $txt=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8); $st=Get-Stage $f.Name
  $msg="Подтвердите: в Gemini заново уйдёт последний отчёт агента Antigravity — файл $($f.Name) из Downloads ($($txt.Length) симв., этап: $(Get-StageRu $st)). Уйдёт так же, как GGskript отправляет сам: только файлом-вложением через «+», без текста в поле. Ответ Gemini дальше пойдёт по обычным правилам: блок Markdown → в Antigravity, без блока — спрошу.$(if(-not (Is-Done $f.Name)){' Файл ещё в работе — отправится, когда до него дойдёт очередь.'})`nНачало:`n«$(Get-Preview $txt 200)»"
  New-TgPrompt -Kind 'confirm' -Text $msg -Buttons 'Отправить=send|Отмена=cancel' -Data @{ action=@{ k='resendfile'; name=$f.Name } } | Out-Null
}
function Start-AwaitText([string]$Target='',[switch]$Direct){
  $script:TgAwait=@{ target=$Target; direct=[bool]$Direct; until=(Get-Date).AddMinutes($Cfg.TgAwaitTextMin) }
  if($Direct){ $nm= if($Target -eq 'ag'){ '🛠 <b>Antigravity</b>' } else { '✨ <b>Gemini</b>' }
    Tg-Send "$nm`nНапишите текст одним сообщением — отправлю и пришлю ответ.`n<i>«отмена» — ничего не отправлять · жду $($Cfg.TgAwaitTextMin) мин</i>" -Html | Out-Null; return }
  Tg-Send "✏️ Введите текст$(if($Target -eq 'gemini'){' для Gemini'}elseif($Target -eq 'ag'){' для Antigravity'}) одним сообщением (или «отмена»). Жду $($Cfg.TgAwaitTextMin) мин." | Out-Null
}
function Ask-WhereToSend([string]$Text,[string]$Kind='where',[string]$Target=''){
  if($Target -eq 'gemini'){ return (New-TgPrompt -Kind $Kind -Text "Отправить в Gemini ($($Text.Length) симв.)?`n«$(Get-Preview $Text 200)»" -Buttons 'Отправить в Gemini=gemini|Отмена=cancel' -Data @{ text=$Text }) }
  $q= if($Kind -eq 'offer'){ 'Это не команда. Переслать этот текст?' } else { 'Куда переслать?' }
  $no= if($Kind -eq 'offer'){ 'Нет' } else { 'Отмена' }
  New-TgPrompt -Kind $Kind -Text "$q ($($Text.Length) симв.)`n«$(Get-Preview $Text 200)»$(if($Kind -eq 'offer'){"`n(Список команд — «помощь».)"})" -Buttons "Gemini=gemini|Antigravity=ag|$no=cancel" -Data @{ text=$Text }
}
# Перед ручным сообщением в Gemini: нельзя, если какой-то отчёт ждёт ответа/решения — последний ответ в чате Gemini сбил бы учёт.
function Assert-GeminiFree{
  foreach($k in @($script:St.files.Keys)){
    $s=Get-Stage $k
    if($s -in 'sent','stale' -or ($s -eq 'answered' -and -not (Get-AnswerCache $k ([string]$script:St.files[$k].hash)))){
      throw [GG.RelayNotSentException]::new("отчёт $k сейчас «$(Get-StageRu $s)» — ручное сообщение в Gemini сбило бы учёт; сначала дождитесь/решите его")
    }
  }
}
# Ручной текст в Gemini (из «напиши» / свободного текста / «Написать ответ Gemini»): ждём ответ; с блоком — спрашиваем
# «Переслать в Antigravity?», без блока — предлагаем копию. Этапы файлов не меняются.
function Send-GeminiManual([string]$Text,[switch]$SendCopy){
  Assert-NotPaused 'сообщение в Gemini'
  Assert-Quota -Gemini -Ag
  Assert-GeminiFree
  $m=Assert-Argon 'Сообщение из Telegram в Gemini НЕ отправлено.'
  $ctx=Gem-Send $Text (Get-Marker $Text)
  Tg-Send "✅ Доставлено в Gemini (модель: $m). Жду ответ…" | Out-Null
  $script:State='жду ответ Gemini на сообщение из Telegram'
  [void](Gem-WaitAnswer $ctx)
  $m2=Get-ModelNow
  if(-not (Is-Argon $m2)){ Enter-LimitStop $m2 "Ответ на сообщение из Telegram пришёл от модели «$m2» — не пересылаю."; return }
  Check-OurPrompt ([int]$ctx.pBefore)
  $tag='manual_'+(Get-Date).ToString('yyyyMMdd_HHmmss')
  $code=Gem-CopyCode
  $w=Get-WholeAnswer
  $full= if($w.text){ Save-FullAnswer "$tag.md" $w.text } else { $null }
  $label="ваше сообщение ($((Get-Date).ToString('HH:mm')))"
  if($SendCopy -and $full){ Send-AnswerCopy $full $label }
  if($code){
    $cp=Save-FullAnswer "$($tag)_code.md" $code
    New-TgPrompt -Kind 'gemcode' -Text "💬 Gemini ответил на $label (модель $m2). В ответе есть блок Markdown: $($code.Length) симв., первая строка «$(Get-FirstLine $code)». Переслать блок в Antigravity?" -Buttons 'Да=toag|Нет=no;Прислать копию ответа=copy' -Data @{ code=$cp; full=$(if($full){$full}else{$cp}); label=$label } | Out-Null
  } elseif(-not ($SendCopy -and $full)){ Send-NoCodePrompt -Label $label -Model $m2 -FullPath $full | Out-Null }
}
# «Antigravity: текст»: ответ агента — новый отчёт в Downloads после отправки; пришлём его копию в Telegram.
$script:AgWatch=$null; $script:AgWatchLast=Get-Date
function Start-AgWatch([string]$Src='tg'){ $script:AgWatch=@{ src=$Src; since=(Get-Date); known=@(Get-Files -All | ForEach-Object { $_.Name }); until=(Get-Date).AddMinutes([double]$Cfg.AgReplyWaitMin) } }
function Check-AgWatch{
  if(Test-StopNow){ return }
  if(-not $script:AgWatch -or ((Get-Date)-$script:AgWatchLast).TotalSeconds -lt 5){ return }; $script:AgWatchLast=Get-Date
  $w=$script:AgWatch
  $f=@(Get-Files -All | Where-Object { $w.known -notcontains $_.Name -and $_.LastWriteTime -ge $w.since.AddSeconds(-2) -and ((Get-Date)-$_.LastWriteTime).TotalSeconds -ge 3 }) | Select-Object -First 1
  if($f){ $script:AgWatch=$null; $prev=$script:LogReplies; if($w.src -eq 'pc'){ $script:LogReplies=$true }; try{ Send-AnswerCopy $f.FullName $f.Name -Who 'Antigravity' } finally { $script:LogReplies=$prev }; return }
  if((Get-Date) -gt $w.until){ $script:AgWatch=$null; Tg-Send "⌛ Antigravity за $($Cfg.AgReplyWaitMin) мин не прислал новый отчёт. Когда он появится, GGskript обработает его как обычно." | Out-Null }
}
function Invoke-ChatAction($c){
  switch($c.k){
    'gemask' { Send-GeminiManual $c.text -SendCopy; return }
    'agask' {
      Assert-NotPaused 'текст в Antigravity'; Assert-Quota -Ag
      Start-AgWatch ([string]$c.src); try{ Ag-Send -Text $c.text -Label 'текст из Telegram' }catch{ $script:AgWatch=$null; throw }
      Log 'Текст из Telegram отправлен в Antigravity, жду отчёт агента'
      Tg-Send "🛠 <b>Отправлено в Antigravity</b> ($($c.text.Length) симв.)`nПришлю ответ агента, как только появится новый отчёт (до $($Cfg.AgReplyWaitMin) мин)." -Html | Out-Null
    }
    'fwdtext' {
      if($c.target -eq 'gemini'){ Send-GeminiManual $c.text; return }
      Assert-NotPaused 'текст в Antigravity'; Assert-Quota -Ag
      Ag-Send -Text $c.text -Label "$($c.what) (из $(if($c.src -eq 'pc'){'панели'}else{'Telegram'}))"
      $hh=Get-Hash8 $c.text; if($c.relay -or $c.file){ Add-RelayHash $script:St $hh $Cfg.HashKeep }
      if($c.file -and (Get-Stage $c.file) -eq 'nocode'){ Set-Stage $c.file 'relayed' $hh -Force; Log "$($c.file): ответ без блока передан в Antigravity по кнопке" }
      Save-State
      $msg="✅ Доставлено в Antigravity: $($c.what) ($($c.text.Length) симв., «$(Get-FirstLine $c.text)»)"; Log $msg; Tg-Send $msg | Out-Null
    }
    'fwdans-pc' {
      $w=Get-WholeAnswer
      if(-not $w.text){ Log 'Не удалось взять последний ответ Gemini — пересылать нечего.'; return }
      Invoke-ChatAction @{ k='fwdtext'; target='ag'; text=$w.text; what="последний ответ Gemini целиком ($($w.via))"; src='pc' }
    }
    'fwdans-prep' {
      $w=Get-WholeAnswer
      if(-not $w.text){ Tg-Send 'Не удалось взять последний ответ Gemini — пересылать нечего.' | Out-Null; return }
      $p=Save-FullAnswer ('last_'+(Get-Date).ToString('yyyyMMdd_HHmmss')+'.md') $w.text
      Start-ForwardConfirm -Target 'ag' -Text $w.text -What "последний ответ Gemini целиком (взят сейчас: $($w.via))"
    }
    'resendfile' {
      $n=$c.name
      if(-not (Test-Path -LiteralPath (Join-Path $Cfg.Downloads $n))){ Tg-Send "Файла $n уже нет в Downloads." | Out-Null; return }
      Set-Stage $n 'resend' -Force; Save-State
      $msg="🔁 $n поставлен на повторную отправку в Gemini (этап «отправить заново»); дальше — по обычным правилам."; Log $msg; Tg-Send $msg | Out-Null
    }
  }
}
