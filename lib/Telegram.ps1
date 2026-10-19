# ===== GGskript v2: Telegram — токен (DPAPI), единый отправитель, опрос команд, скриншот =====

function Load-TgCfg{ $r=Read-JsonWithBackup $Cfg.ConfigFile; $r.Data }
function Save-TgCfg($c){ Write-AtomicText -Path $Cfg.ConfigFile -Text ($c | ConvertTo-Json -Depth 6) }
# Токен: tg_token.dpapi (DPAPI, только этот пользователь на этом ПК), иначе — telegram_token из relay_config.json (с предупреждением).
$script:TokenWarned=$false
function Get-TgToken($c){
  if($Cfg.TokenFile -and (Test-Path -LiteralPath $Cfg.TokenFile)){
    try{ return (Unprotect-Secret ([IO.File]::ReadAllText($Cfg.TokenFile))) }catch{ Log "Telegram: не удалось расшифровать $($Cfg.TokenFile) ($($_.Exception.Message))" }
  }
  if($c -and $c.telegram_token){
    if(-not $script:TokenWarned){ $script:TokenWarned=$true; Log '⚠️ Токен Telegram хранится открытым текстом в relay_config.json. Выполните Set-TgToken.ps1 (DPAPI) и удалите telegram_token из файла.' }
    return [string]$c.telegram_token
  }
  $null
}
# Единственная точка обращения к API Telegram (в тестах подменяется Mock).
function Invoke-Tg([string]$Method,$Body,[int]$TimeoutSec=15,[string]$Query=''){
  $u="https://api.telegram.org/bot$($script:TgToken)/$Method$Query"
  if($null -eq $Body){ return Invoke-RestMethod $u -TimeoutSec $TimeoutSec }
  $bytes=[Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10))
  Invoke-RestMethod $u -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
}
function Resolve-ChatId($c){
  if($c.chat_id){ return [string]$c.chat_id }
  try{
    $u=Invoke-Tg 'getUpdates' $null 15
    $m=@($u.result) | ForEach-Object { if($_.message){$_.message}elseif($_.my_chat_member){$_.my_chat_member} } | Where-Object { $_.from.username -and $_.from.username -ieq $c.telegram_username -and $_.chat.id -eq $_.from.id } | Select-Object -Last 1
    if($m){ $c.chat_id=[string]$m.chat.id; Save-TgCfg $c; Log 'Telegram: chat_id найден и сохранён'; return [string]$c.chat_id }
    Log 'Telegram: chat_id ещё не найден — напишите боту /start'
  }catch{ Log "Telegram getUpdates: $($_.Exception.Message)" }
  $null
}
$script:TgToken=$null; $script:TgChat=$null; $script:LastTg=@{}
function Init-Tg{
  $c=Load-TgCfg; $script:TgToken=Get-TgToken $c
  if($script:TgToken){ if(-not $c){ $c=[ordered]@{} }; $script:TgChat=[string](Resolve-ChatId $c) }
}
# Единый отправитель. -DedupMin N — не повторять тот же текст чаще раза в N минут (как прежний Notify). -Force — без дедупа.
function Tg-Send{
  param([string]$Text,[int]$DedupMin=0,[switch]$Force,$Markup=$null)
  if($script:LogReplies){ Log ('> '+(Format-Short $Text $Cfg.LogTextMax)) }
  if(!$script:TgToken -or !$script:TgChat){ return $false }
  if($DedupMin -gt 0 -and -not $Force -and $script:LastTg.ContainsKey($Text) -and ((Get-Date)-$script:LastTg[$Text]).TotalMinutes -lt $DedupMin){ return $false }
  $ok=$true
  $parts=Split-TgText $Text; $i=0
  foreach($p in $parts){
    $i++; $b=@{ chat_id=$script:TgChat; text=$p }; if($Markup -and $i -eq $parts.Count){ $b.reply_markup=$Markup }
    try{ Invoke-Tg 'sendMessage' $b 15 | Out-Null }
    catch{ $ok=$false; Log "Telegram: не удалось отправить ($($_.Exception.Message))" -NoAction }
  }
  if($ok){ $script:LastTg[$Text]=Get-Date }
  $ok
}
function Notify([string]$Text,[switch]$Force){ Tg-Send -Text "GGskript: $Text" -DedupMin 10 -Force:$Force | Out-Null }
function Poll-Tg{
  if(!$script:TgToken -or !$script:TgChat){ return }
  if($script:TgBackoffUntil -and (Get-Date) -lt $script:TgBackoffUntil){ return }
  try{ $u=Invoke-Tg 'getUpdates' $null 8 "?timeout=1&offset=$($script:TgOffset)&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D"; $script:TgBackoffUntil=$null }
  catch{ $script:TgBackoffUntil=(Get-Date).AddSeconds(30); return }   # нет сети — не тормозим каждый Pump
  foreach($x in @($u.result)){
    if(!$x){ continue }
    $script:TgOffset=[int64]$x.update_id+1; try{ Write-AtomicText -Path $Cfg.TgOffsetFile -Text ([string]$script:TgOffset) -NoBom -NoBackup }catch{}
    $cq=$x.callback_query
    if($cq){
      # кнопки: только от разрешённого чата (тот же chat_id, что и для команд)
      if([string]$cq.from.id -ne $script:TgChat -or ($cq.message -and [string]$cq.message.chat.id -ne $script:TgChat)){ Log "Telegram: игнорирую кнопку от @$($cq.from.username) (id $($cq.from.id))"; Tg-AnswerCb ([string]$cq.id) 'Нет доступа'; continue }
      Log "Telegram кнопка: $(Format-Short ([string]$cq.data) 80)"
      try{ Handle-Callback ([string]$cq.data) ([string]$cq.id) ([int64]$cq.message.message_id) }catch{ Log "Telegram кнопка: ошибка $($_.Exception.Message)"; Tg-AnswerCb ([string]$cq.id) 'Ошибка — см. журнал' }
      continue
    }
    $m=$x.message; if(!$m -or !$m.text){ continue }
    if([int64]$m.date -lt $script:StartUnix){ continue }
    if([string]$m.chat.id -ne $script:TgChat -or [string]$m.from.id -ne $script:TgChat){ Log "Telegram: игнорирую сообщение от @$($m.from.username) (id $($m.from.id))"; continue }
    Log "Telegram команда: $(Format-Short $m.text $Cfg.LogTextMax)"
    $rt=[int64]0; if($m.reply_to_message){ $rt=[int64]$m.reply_to_message.message_id }
    try{ Handle-Command $m.text 'tg' -ReplyTo $rt }catch{ Log "Telegram команда: ошибка $($_.Exception.Message)" }
  }
}
# ---------- Кнопки, длинные тексты, файлы ----------
# Клавиатура из строки: ряды через «;», кнопки через «|», «Надпись=данные». callback_data = Prefix+данные (≤ 64 байт).
function New-TgKeyboard([string]$Spec,[string]$Prefix=''){
  $kb=New-Object System.Collections.ArrayList
  foreach($r in ($Spec -split ';')){ if(-not $r.Trim()){ continue }
    $row=New-Object System.Collections.ArrayList
    foreach($b in ($r -split '\|')){ $kv=$b -split '=',2; [void]$row.Add([ordered]@{ text=$kv[0].Trim(); callback_data=($Prefix+$kv[1].Trim()) }) }
    [void]$kb.Add($row) }
  @{ inline_keyboard=$kb }
}
# ---- Пункт 22: постоянная клавиатура с русскими кнопками (ReplyKeyboardMarkup) ----
# Кнопка отправляет в чат свой текст — его разбирает Parse-Command, как набранный вручную.
# Ряды через «;», кнопки через «|». Меню команд с «/» (setMyCommands) не трогаем.
$script:TgReplyButtons='Статус|Стоп|Старт;Прими|Передай ответ|Передай всё равно;Перешли ответ в Antigravity|Перешли отчёт в Gemini;Что ответил Джемини|Отправь заново|Выключи скрипт;Напиши|Скрин|Лимиты|Помощь'
function Get-TgReplyLabels([string]$Spec=$script:TgReplyButtons){ @(($Spec -split '[;|]') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
function New-TgReplyKeyboard([string]$Spec=$script:TgReplyButtons){
  $kb=New-Object System.Collections.ArrayList
  foreach($r in ($Spec -split ';')){ if(-not $r.Trim()){ continue }
    $row=New-Object System.Collections.ArrayList
    foreach($b in ($r -split '\|')){ if($b.Trim()){ [void]$row.Add([ordered]@{ text=$b.Trim() }) } }
    [void]$kb.Add($row) }
  [ordered]@{ keyboard=$kb; resize_keyboard=$true; is_persistent=$true }
}
# Разметка для стартового сообщения и «помощи»: $null, если TgReplyKeyboard выключен.
function Get-TgReplyMarkup{ if($Cfg.TgReplyKeyboard -eq $false){ return $null }; New-TgReplyKeyboard }
function Get-TgButtonLabels([string]$Spec){ $h=[ordered]@{}; foreach($b in ($Spec -split '[;|]')){ $kv=$b -split '=',2; if($kv.Count -eq 2){ $h[$kv[1].Trim()]=$kv[0].Trim() } }; $h }
# Отправка с кнопками (на последней части) и ответом-цитатой; возвращает message_id последней части (0 — неизвестен), $null — ошибка.
function Tg-SendMsg{
  param([string]$Text,$Markup=$null,[int64]$ReplyTo=0)
  if($script:LogReplies){ Log ('> '+(Format-Short $Text $Cfg.LogTextMax)) }
  if(!$script:TgToken -or !$script:TgChat){ return $null }
  $parts=@(Split-TgParagraphs $Text $Cfg.TgMaxLen); $id=[int64]0
  for($i=0;$i -lt $parts.Count;$i++){
    $b=@{ chat_id=$script:TgChat; text=$parts[$i] }
    if($Markup -and $i -eq $parts.Count-1){ $b.reply_markup=$Markup }
    if($ReplyTo -and $i -eq 0){ $b.reply_to_message_id=$ReplyTo }
    try{ $r=Invoke-Tg 'sendMessage' $b 15; if($r -and $r.result -and $r.result.message_id){ $id=[int64]$r.result.message_id } }
    catch{ Log "Telegram: не удалось отправить ($($_.Exception.Message))" -NoAction; return $null }
  }
  $id
}
function Tg-AnswerCb([string]$Id,[string]$Text=''){ if(!$Id){ return }; try{ Invoke-Tg 'answerCallbackQuery' @{ callback_query_id=$Id; text=$Text } 10 | Out-Null }catch{ Log "Telegram answerCallbackQuery: $($_.Exception.Message)" -NoAction } }
# Убрать кнопки и пометить выбор: editMessageText (текст + отметка), при ошибке — только убрать клавиатуру.
function Tg-CloseButtons([int64]$MsgId,[string]$Text=''){
  if(-not $MsgId -or !$script:TgChat){ return }
  if($Text){ try{ Invoke-Tg 'editMessageText' @{ chat_id=$script:TgChat; message_id=$MsgId; text=(@(Split-TgParagraphs $Text $Cfg.TgMaxLen))[-1] } 10 | Out-Null; return }catch{} }
  try{ Invoke-Tg 'editMessageReplyMarkup' @{ chat_id=$script:TgChat; message_id=$MsgId; reply_markup=@{ inline_keyboard=(New-Object System.Collections.ArrayList) } } 10 | Out-Null }catch{ Log "Telegram: не удалось убрать кнопки ($($_.Exception.Message))" -NoAction }
}
# Единая точка загрузки файлов (multipart); в тестах подменяется Mock.
function Invoke-TgUpload([string]$Method,[hashtable]$Fields,[string]$FileField,[string]$Path,[string]$FileName,[string]$Mime='application/octet-stream'){
  Add-Type -AssemblyName System.Net.Http
  $hc=$null; $mp=$null
  try{
    $hc=New-Object System.Net.Http.HttpClient; $hc.Timeout=[TimeSpan]::FromSeconds(60)
    $mp=New-Object System.Net.Http.MultipartFormDataContent
    foreach($k in $Fields.Keys){ $mp.Add((New-Object System.Net.Http.StringContent([string]$Fields[$k],[Text.Encoding]::UTF8,'text/plain')),$k) }
    $fc=New-Object System.Net.Http.ByteArrayContent(,[IO.File]::ReadAllBytes($Path)); $fc.Headers.ContentType=[System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($Mime)
    $mp.Add($fc,$FileField,$FileName)
    $r=$hc.PostAsync("https://api.telegram.org/bot$($script:TgToken)/$Method",$mp).GetAwaiter().GetResult()
    if(-not $r.IsSuccessStatusCode){ throw "$($Method): $($r.StatusCode)" }
  } finally { if($mp){ $mp.Dispose() }; if($hc){ $hc.Dispose() } }
}
function Tg-SendDocument([string]$Path,[string]$Caption='',[string]$FileName=''){
  if(!$script:TgToken -or !$script:TgChat){ return $false }
  if(-not $FileName){ $FileName=[IO.Path]::GetFileName($Path) }
  $f=@{ chat_id=$script:TgChat }; if($Caption){ $f.caption=(Format-Short $Caption 1000) }
  try{ Invoke-TgUpload 'sendDocument' $f 'document' $Path $FileName 'text/markdown'; $true }catch{ Log "Telegram sendDocument: $($_.Exception.Message)" -NoAction; $false }
}
function Send-Screenshot([string]$Caption='',$Rect=$null){
  if(!$script:TgToken -or !$script:TgChat){ throw 'Telegram не настроен' }
  Add-Type -AssemblyName System.Net.Http
  $f=Save-ScreenshotJpeg $Rect; $hc=$null; $mp=$null
  try{
    $hc=New-Object System.Net.Http.HttpClient; $hc.Timeout=[TimeSpan]::FromSeconds(60)
    $mp=New-Object System.Net.Http.MultipartFormDataContent
    $mp.Add((New-Object System.Net.Http.StringContent($script:TgChat)),'chat_id')
    if($Caption){ $mp.Add((New-Object System.Net.Http.StringContent($Caption,[Text.Encoding]::UTF8,'text/plain')),'caption') }
    $fc=New-Object System.Net.Http.ByteArrayContent(,[IO.File]::ReadAllBytes($f)); $fc.Headers.ContentType=[System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('image/jpeg')
    $mp.Add($fc,'photo','screen.jpg')
    $r=$hc.PostAsync("https://api.telegram.org/bot$($script:TgToken)/sendPhoto",$mp).GetAwaiter().GetResult()
    if(-not $r.IsSuccessStatusCode){ throw "sendPhoto: $($r.StatusCode)" }
  } finally { if($mp){ $mp.Dispose() }; if($hc){ $hc.Dispose() }; Remove-Item -LiteralPath $f -EA 0 }
}
