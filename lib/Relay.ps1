# ===== GGskript v2: Relay — логика передачи, этапы, команды, лимиты, диалоги, статус =====

# ---------- Состояние процесса ----------
$script:State='запуск'; $script:Busy=$false; $script:Paused=$false; $script:StopReq=$false
$script:Queue=New-Object System.Collections.Queue; $script:LastDone=$null
$script:StartUnix=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$script:TgOffset=0
$script:LimitStop=$false; $script:LimitModel=''; $script:LimitSince=$null; $script:LastLimitCheck=Get-Date
$script:LastModel=''; $script:LastAction=$null; $script:LogReplies=$false; $script:LastStatusWrite=(Get-Date).AddYears(-1)
$script:AgPending=$null; $script:QueueSeen=@{}; $script:QueueTries=@{}; $script:LastQueueCheck=Get-Date
$script:NeedStart=$true; $script:LastStartTry=(Get-Date).AddYears(-1)
$script:Q=$null; $script:QWarned=@{}; $script:QOverride=@{}; $script:QStopG=$false; $script:QStopA=$false; $script:LastQuota=Get-Date
$script:AgSrv=$null
$script:St=$null
$script:PendingConfirm=$null
$script:StaleNotified=@{}
$script:Blk=@{ key=$null; info=$null; since=$null; notified=$false; lastRecheck=(Get-Date) }
$script:AutoPlan=$null; $script:AutoPlanKey=''; $script:AutoFails=0; $script:AutoLastAttempt=$null
$script:TriageNeeded=$true; $script:LastStartReport=''; $script:StopAnnounced=$false; $script:AbortOnStop=$false; $script:PausedSince=$null; $script:Held=@{}; $script:Adopted=@{}; $script:AutoSend=@{}; $script:SendNotBefore=@{}   # пункт 24
$script:UsageNoTabSaid=$false; $script:ManualModelSaid=$false   # пункт 26
$script:TurnSide=""   # пункт 41: последняя сторона, которой передали работу (gemini|antigravity)
$script:OperatorWait=''; $script:GateSaid=''; $script:GateHold=''   # пункт 44: ждём оператора (имя отчёта) / проверка меток шага
$script:AgBlock=$null   # @{ kind; msg; detail; file; since; notifiedAt; lastLog; restartedAt } — Antigravity не принимает ответ

# ---------- Этапы ----------
function Save-State{ try{ Save-RelayState $script:St $Cfg.StateJson }catch{ Log "Состояние: не удалось сохранить ($($_.Exception.Message))" } }
function Get-Stage([string]$n){ Get-FileStage $script:St $n }
function Set-Stage{
  param([string]$n,[string]$st,[string]$hash,[switch]$Quiet,[switch]$Force,[switch]$NoSave)
  if(Set-FileStage -State $script:St -Name $n -Stage $st -Hash $hash -Force:$Force){
    if(-not $NoSave){ Save-State }; if(-not $Quiet){ Log "Этап: $n → $(Get-StageRu $st)" }
  }
  $script:TurnSide=Get-TurnSideOfStage $st $script:TurnSide   # пункт 41: чей ход (для индикатора на панели)
  if($st -ne 'operator' -and $script:OperatorWait){ $script:OperatorWait='' }   # пункт 44: работа пошла дальше
}
function Is-Done([string]$n){ Test-FileDone $script:St $n }
function ProjOf([string]$n){ Get-ProjectOf $n $Cfg.Pattern }
function Mark-Done([string]$n){ $script:LastDone=$n }
# Последний переданный файл по учёту (для статуса сразу после запуска, а не только «за этот запуск»).
function Get-LastDoneName{ $f=@(Get-Files -All | Where-Object { (Get-Stage $_.Name) -in @('relayed','done') }) | Select-Object -Last 1; if($f){ $f.Name } else { $null } }

# ---------- Папка Downloads ----------
function Get-IgnoreBeforeDt{ if($Cfg.IgnoreBefore){ try{ [datetime]::ParseExact($Cfg.IgnoreBefore,'yyyy-MM-dd HH:mm',$null) }catch{ $null } } else { $null } }
function Get-Files([switch]$All,[switch]$AllProjects){
  $ib=Get-IgnoreBeforeDt
  $ap= if($AllProjects){ '' } else { Get-ActiveProjectNow }
  $age=[double]$Cfg.MaxReportAgeHours; $lim=(Get-Date).AddHours(-$age)
  @(Get-ChildItem -LiteralPath $Cfg.Downloads -File -Filter '*.md' -EA 0 | Where-Object {
      $_.Name -match $Cfg.Pattern -and $_.Length -gt 0 -and (-not $ap -or (ProjOf $_.Name) -eq $ap) -and
      ($All -or ((-not $ib -or $_.LastWriteTime -ge $ib) -and ($age -le 0 -or (Get-ReportFileTime $_) -ge $lim)) -or ((Get-Stage $_.Name) -in @('sent','answered','resend','stale')))
    } | ForEach-Object { [pscustomobject]@{ Name=$_.Name; FullName=$_.FullName; LastWriteTime=$_.LastWriteTime; CreationTime=$_.CreationTime; Time=(Get-ReportFileTime $_); Key=(Get-SortKey $_.Name $Cfg.Pattern) } } |
    Sort-Object Key,LastWriteTime)
}
# ---------- Пункт 43: активный проект и очередь по номеру шага ----------
# Проект: из заголовка последнего блока Gemini (St.activeProject); пока его нет — проект самого свежего отчёта (по времени файла, не старше MaxReportAgeHours).
# Если в Downloads появился отчёт ДРУГОГО проекта новее последней вставки в Antigravity — переключаюсь на него (пользователь сменил проект).
function Get-ActiveProjectNow{
  if($script:InActiveProject){ return [string]$script:St.activeProject }
  $script:InActiveProject=$true
  try{
    if(-not $script:St){ return '' }
    $known= if($script:St){ [string]$script:St.activeProject } else { '' }
    $all=@(Get-ReportCandidates -Files @(Get-ChildItem -LiteralPath $Cfg.Downloads -File -Filter '*.md' -EA 0) -Pattern $Cfg.Pattern -MaxAgeHours ([double]$Cfg.MaxReportAgeHours))
    $nw=$all | Select-Object -Last 1
    if(-not $known){ if($nw){ Set-ActiveProject $nw.Project "самый свежий отчёт $($nw.Name)" }; return [string]$nw.Project }
    if($nw -and $nw.Project -ne $known){
      $t=Get-LastAgRelayTime $script:St
      if(-not $t -or $nw.Time -gt $t.AddSeconds(3)){ Set-ActiveProject $nw.Project "отчёт $($nw.Name) ($($nw.Time.ToString('HH:mm:ss'))) новее последней вставки в Antigravity" }
    }
    [string]$script:St.activeProject
  } finally { $script:InActiveProject=$false }
}
function Set-ActiveProject([string]$P,[string]$Why){
  if(-not $P -or -not $script:St -or [string]$script:St.activeProject -eq $P){ return }
  $old=[string]$script:St.activeProject; $script:St.activeProject=$P; Save-State
  Log "📁 Проект: $(if($old){"$old → "})$P ($Why). Отчёты других проектов не трогаю."
}
# Заголовок блока Gemini -> активный проект и номер шага. Без заголовка — пишу в лог «формат промпта нарушен» (один раз на блок).
function Note-BlockHeader([string]$Code){
  $h=Get-PromptHeader $Code
  if($h){ Set-ActiveProject $h.project "заголовок блока Gemini [$($h.project)] [S$($h.step)]" }
  elseif($Code){ $k=Get-Hash8 $Code; if($script:FormatWarned -ne $k){ $script:FormatWarned=$k; Log "⚠ формат промпта нарушен: в блоке Gemini нет заголовка «[…] [Проект] [S<N>] […]» (первая строка «$(Get-FirstLine $Code)») — очередь по чередованию содержимого" } }
  $h
}
function Get-FileHash8([string]$Path){ try{ Get-Hash8 ([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)) }catch{ '' } }
# Решение по состоянию (без чтения окон): заголовок — последний переданный блок (St.lastBlock).
function Get-TurnDecisionNow([string]$BlockCode=''){
  $ap=Get-ActiveProjectNow
  $hdr=$null; $bh=''
  if($BlockCode){ $hdr=Get-PromptHeader $BlockCode; $bh=Get-Hash8 $BlockCode }
  elseif($script:St.lastBlock -and [string]$script:St.lastBlock.project -eq $ap){ $hdr=@{ project=[string]$script:St.lastBlock.project; step=[int]$script:St.lastBlock.step; rework=[bool]$script:St.lastBlock.rework } }
  $rep=@(Get-ReportCandidates -Files @(Get-Files) -Project $(if($hdr){$hdr.project}else{$ap}) -Pattern $Cfg.Pattern -MaxAgeHours ([double]$Cfg.MaxReportAgeHours)) | Select-Object -Last 1
  $rh= if($rep){ Get-FileHash8 $rep.FullName } else { '' }
  $t=Get-LastAgRelayTime $script:St; if(-not $t){ $t=[datetime]::MinValue }
  Get-TurnDecision -Header $hdr -BlockHash $bh -Report $rep -ReportHash $rh -State $script:St -LastAgAt $t
}
function Note-Contradiction($d){
  if(-not $d -or -not $d.contradiction){ return }
  if($script:ContraSaid -eq $d.contradiction){ return }; $script:ContraSaid=$d.contradiction
  $msg="⚖ Очередь: противоречие — $($d.contradiction). Безопасный вариант: ничего не отправляю повторно, жду новое."; Log $msg; try{ Tg-Send $msg | Out-Null }catch{}
}
# Запомнить переданный в Antigravity блок (проект, шаг, хэш).
function Register-BlockRelayed([string]$Code,[string]$Hash){
  $h=Get-PromptHeader $Code; $ap=Get-ActiveProjectNow
  $pr= if($h){ $h.project } else { $ap }; $stp= if($h){ [int]$h.step } else { -1 }
  Add-SentRecord $script:St 'ag' $pr $stp $Hash
  $script:St.lastBlock=[ordered]@{ project=$pr; step=$stp; hash=$Hash; at=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); rework=[bool]($h -and $h.rework) }
  $script:St.lastAgAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $script:OperatorWait=''; $script:GateHold=''
}
# ---------- Пункт 44: проверка меток шага перед вставкой в Antigravity ----------
function Get-LatestReportNum([string]$Project){
  if(-not $Project){ return -1 }
  $r=@(Get-ReportCandidates -Files @(Get-ChildItem -LiteralPath $Cfg.Downloads -File -Filter '*.md' -EA 0) -Project $Project -Pattern $Cfg.Pattern) | Select-Object -Last 1
  if($r){ [int]$r.Num } else { -1 }
}
# Пункт 46: блок дописан при не-Argon модели (лимит) — чей он? Метки [ARGON>FLASH]…[[END S<N>]] верны -> Argon (передать);
# метки есть, но неверны -> нет (гейт); меток нет -> передать, но с записью в лог.
function Test-BlockFromArgon([string]$Code,[bool]$ArgonNow,$Gate){
  if($ArgonNow){ return @{ ok=$true; why='модель Argon' } }
  if(-not $Gate){ $Gate=@{ tagged=$false; ok=$true } }
  $argTag=([string]$Code -replace '&gt;','>') -match '\[ARGON>FLASH\]'
  if($Gate.tagged -and $Gate.ok -and $argTag){ return @{ ok=$true; why='метки [ARGON>FLASH] и [[END S…]] совпадают — блок дописан Argon до переключения' } }
  if($Gate.tagged -and $Gate.ok){ return @{ ok=$true; why='метки шага и [[END S…]] совпадают (нет [ARGON>FLASH])' } }
  if($Gate.tagged){ return @{ ok=$false; why="метки не сходятся: $($Gate.reason)" } }
  @{ ok=$true; why='меток нет — не могу проверить, что блок от Argon; передаю (формат промпта нарушен)' }
}
function Get-BlockGate([string]$Code){
  $h=Get-PromptHeader $Code; $pr= if($h){ $h.project } else { '' }
  Test-BlockStepTags $Code (Get-LatestReportNum $pr)
}
# Несовпадение меток: НЕ вставляю, одна заметка в Telegram с кнопками (не блокирующий вопрос), жду.
function Notify-BlockGate($g,[string]$Hash,[string]$n=''){
  $script:GateHold=$Hash
  if($script:GateSaid -eq $Hash){ return }; $script:GateSaid=$Hash
  $msg="⚠️ [$($g.project)] Блок Gemini S$('{0:D3}' -f $g.step)$(if($g.rework){' (REWORK)'})$(if($n){" (ответ на $n)"}) в Antigravity НЕ вставлен: $($g.reason). Жду: новый ответ Gemini или ваше решение."
  Log $msg
  try{ [void](New-TgPrompt -Kind 'gate' -Text $msg -Buttons '⏩ Передай всё равно=force|🔁 Отправь заново=resend' -Data @{ file=$n; hash=$Hash }) }catch{ try{ Tg-Send $msg | Out-Null }catch{} }
}
# Ссылка ответа на отчёт («Ответ на: <имя>.md» первой строкой) — только через CDP (без мыши); иначе $null.
function Get-AnswerRefNow{
  if($Cfg.GeminiTransport -ne 'cdp'){ return $null }
  try{ Get-AnswerReportRef ([string](GemCdp-GetWhole)) }catch{ $null }
}
# ---------- Пункт 44: «СТОП — РЕШЕНИЕ ОПЕРАТОРА» ----------
function Enter-OperatorWait([string]$n,[string]$Text,[string]$Model){
  Set-Stage $n 'operator' -Force; Mark-Done $n; $script:OperatorWait=$n
  $full=Save-FullAnswer $n $Text
  $msg="🛑 [$(ProjOf $n)] Argon остановился: «СТОП — РЕШЕНИЕ ОПЕРАТОРА» (ответ на $n, модель $Model). В Antigravity ничего не передаю, повторно не отправляю — жду вас."
  Log "$msg`r`n$(($Text -replace "`r?`n","`r`n").TrimEnd())"
  try{ Send-OperatorAnswer $Text $n }catch{ Log "Текст остановки в Telegram не отправлен: $($_.Exception.Message)" }
  try{ [void](New-TgPrompt -Kind 'operator' -Text $msg -Buttons '✍️ Напиши=write|🔁 Отправь заново=resend' -Data @{ file=$n; full=$full } -TimeoutMin ([Math]::Max([double]$Cfg.TgPromptTimeoutMin,720))) }catch{ try{ Tg-Send $msg | Out-Null }catch{} }
  [void](Play-Sound 'nocode')
}
function Send-OperatorAnswer([string]$Text,[string]$n){
  $max=[int]$Cfg.TgMaxLen-120; if($max -lt 500){ $max=3500 }
  $parts=@(Split-TgParagraphs $Text $max)
  if($parts.Count -le 4){ $i=0; foreach($p in $parts){ $i++; Tg-Send "$(if($parts.Count -gt 1){"($i/$($parts.Count)) "})$p" | Out-Null }; return }
  $fp=Join-Path $Cfg.AnswerDir ("operator_"+([IO.Path]::GetFileNameWithoutExtension($n))+'.md')
  if(-not (Test-Path -LiteralPath $Cfg.AnswerDir)){ New-Item -ItemType Directory -Force $Cfg.AnswerDir | Out-Null }
  Write-AtomicText -Path $fp -Text $Text -NoBackup
  Tg-Send "$($parts[0])`n…(полный текст — файлом)" | Out-Null; [void](Tg-SendDocument $fp "Ответ Argon на $n — СТОП, решение оператора")
}
function Reset-RewrittenReports{
  foreach($f in @(Get-Files)){
    if(Test-ReportRewritten $script:St $f.Name $f.LastWriteTime){
      $old=$script:St.files[$f.Name]; Remove-FileStage $script:St $f.Name; Save-State; $script:Held.Remove($f.Name)
      $msg="🔁 Очередь: $($f.Name) перезаписан в $($f.LastWriteTime.ToString('HH:mm:ss')) — после этапа «$(Get-StageRu ([string]$old.stage))» ($($old.time)). Antigravity написал новый отчёт → очередь Gemini, отправлю."
      Log $msg; try{ Tg-Send $msg | Out-Null }catch{}
    }
  }
}
function Get-LastAgRelayTimeRu{ $t=Get-LastAgRelayTime $script:St; if($t){ $t.ToString('HH:mm:ss') } else { 'не было' } }
function Next-File{
  Reset-RewrittenReports
  $files=@(Get-Files); if(-not $files.Count){ return $null }
  # уже начатые (отправлен/ответ получен/ждёт решения) — доводим до конца
  if(-not $Cfg.StartupNewestOnly){ return (@($files | Where-Object { -not (Is-Done $_.Name) -and -not $script:Held.ContainsKey($_.Name) }) | Select-Object -First 1) }   # прежнее поведение
  $busy=@($files | Where-Object { (Get-Stage $_.Name) -in @('sent','answered','stale','resend') -and -not $script:Held.ContainsKey($_.Name) }) | Select-Object -First 1
  if($busy){ return $busy }
  # пункт 43: только самый свежий по времени файла (max LastWriteTime/CreationTime) отчёт активного проекта; старые не трогаю и не помечаю
  $nw=@($files | Sort-Object Time,Key) | Select-Object -Last 1
  if(-not $nw -or (Is-Done $nw.Name) -or $script:Held.ContainsKey($nw.Name)){ return $null }
  $lb=$script:St.lastBlock
  if($lb -and [int]$lb.step -ge 0 -and [string]$lb.project -eq (ProjOf $nw.Name)){
    $M=[int][regex]::Match($nw.Name,$Cfg.Pattern).Groups['n'].Value
    if($M -lt [int]$lb.step){ $k="$($nw.Name)<$($lb.step)"; if($script:StepGateSaid -ne $k){ $script:StepGateSaid=$k; Log "⚖ Очередь: $($nw.Name) (№$M) меньше шага S$($lb.step), который уже у Antigravity — ход Antigravity, отчёт не отправляю, жду №$($lb.step)" }; return $null }
  }
  $nw
}
# ---------- Пункт 24: запуск без «хвоста» ----------
# Самый новый файл: по времени изменения, при равенстве — по номеру NNN (ключ сортировки).
function Get-NewestFile($Files){ @($Files | Sort-Object @{e={ if($_.PSObject.Properties['Time'] -and $_.Time){ $_.Time } else { $_.LastWriteTime } }},Key) | Select-Object -Last 1 }
# Файл старее уже обработанного/отправленного (по времени изменения) — такой автоматически не отправляем. -> имя более нового или $null
function Get-NewerHandled($f){
  @(Get-Files | Where-Object { $_.Name -ne $f.Name -and $_.LastWriteTime -gt $f.LastWriteTime -and (Get-Stage $_.Name) -notin @('','resend') } | Sort-Object LastWriteTime) | Select-Object -Last 1 | ForEach-Object { $_.Name }
}
# План запуска: старые необработанные -> skipped; самый новый — виден в чате Gemini -> «отправлен» (жду/беру ответ),
# не виден -> вопрос в Telegram (StartupAskNewest) или обычная отправка. -> @{ lines; skipped; newest; ask }
function Invoke-StartupTriage([string]$LastPrompt,[switch]$DryRun,[switch]$NoChat){
  if(-not $DryRun){ Reset-RewrittenReports }
  $files=@(Get-Files); $out=@{ lines=@(); skipped=@(); newest=$null; ask=$null; pending=$false }
  if(-not $files.Count){ $out.lines+='   файлов отчётов нет — жду новый'; return $out }
  $nw=Get-NewestFile $files; $out.newest=$nw.Name
  foreach($f in $files){
    if($f.Name -eq $nw.Name -or (Is-Done $f.Name)){ continue }
    $out.skipped+=$f.Name
    if(-not $DryRun){ [void](Set-FileStage -State $script:St -Name $f.Name -Stage 'skipped' -Note 'пропущен при запуске: старее самого нового файла (сделан вручную или устарел)' -Force); $script:Held.Remove($f.Name) }
  }
  if($out.skipped.Count){ if(-not $DryRun){ Save-State }; $out.lines+="   ⏭ пропущены (старее $($nw.Name), в Gemini НЕ отправляю): $($out.skipped -join ', ')"; Log "Запуск: пропущены $($out.skipped -join ', ')" }
  $n=$nw.Name; $st=Get-Stage $n; $vis=($LastPrompt -and $LastPrompt -eq $n)
  if(-not $DryRun){ $script:Held.Remove($n) }
  if($NoChat -and -not (Is-Done $n) -and $st -notin @('answered','stale')){
    # окна Gemini нет — старые уже пропущены; самый новый не трогаю, пока не увижу чат (решу при следующей попытке)
    if(-not $DryRun){ $script:Held[$n]=$true }; $out.pending=$true
    $out.lines+="   самый новый $($n): окно Gemini не найдено — НЕ отправляю; решу, когда найду окно (есть ли он в чате, иначе спрошу)"; return $out
  }
  if(Is-Done $n){ $out.lines+="   самый новый $n — уже обработан ($(Get-StageRu $st)); жду новый файл"; return $out }
  if($st -in @('answered','stale')){ $out.lines+="   самый новый $($n): $(Get-StageRu $st) — в Gemini повторно НЕ отправляю"; return $out }
  $how=''
  if(-not $vis -and -not $NoChat -and $Cfg.MatchByContent){
    # пункт 27C: отправлен вручную — узнаю по содержимому (или по вложению с именем файла)
    $hit=Test-FileInGemini $nw
    if($hit -and $hit.how -eq 'name' -and (Test-ReportNewerThanAg $script:St $nw.LastWriteTime)){
      $out.lines+="   ⚖ очередь: $n ($($nw.LastWriteTime.ToString('HH:mm:ss'))) новее последней вставки в Antigravity ($(Get-LastAgRelayTimeRu)) — имя в чате Gemini не считаю отправкой (это упоминание в промпте), очередь Gemini"; $hit=Test-FileInGemini $nw -ContentOnly }
    if($hit -and $hit.last){ $vis=$true; $how=$(if($hit.how -eq 'content'){' (узнал по содержимому — отправлен вручную)'}else{' (по имени файла во вложении)'}) }
    elseif($hit){
      if(-not $DryRun){ [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note 'уже есть в чате Gemini (найден по содержимому), но не последним запросом — ответ автоматически не беру' -Force); Save-State }
      $out.lines+="   самый новый $n уже есть в чате Gemini (по $(if($hit.how -eq 'content'){'содержимому'}else{'имени'})), но после него были другие запросы — повторно НЕ отправляю и ответ автоматически не беру («передай ответ» — вручную)"; return $out
    }
  }
  if($vis){
    if(-not $DryRun){ if($st -ne 'sent'){ Set-Stage $n 'sent' -Force }; $script:Adopted[$n]=$true }
    $out.lines+="   самый новый $n уже есть в чате Gemini$how — повторно НЕ отправляю, беру ответ (если ответ уже есть в Antigravity — не вставляю)"; return $out
  }
  if($Cfg.StartupAskNewest -and -not $Cfg.AutoDecide){
    if(-not $DryRun){ $script:Held[$n]=$true }
    $out.ask=$n; $out.lines+="   самый новый $n в чате Gemini НЕ найден — спрошу в Telegram, отправлять ли (до ответа не отправляю)"; return $out
  }
  if(-not $DryRun){
    if($st -eq 'sent'){ Set-Stage $n 'resend' }
    $g=[int]$Cfg.AutoSendGraceSec; $script:AutoSend[$n]=$true
    if($g -gt 0){ $script:SendNotBefore[$n]=(Get-Date).AddSeconds($g) }
    Log "Авторешение: $n новее последней вставки в Antigravity и в чате Gemini не найден — очередь Gemini; отправлю сам через $g сек, перед отправкой перепроверю чат (если отправлен вручную — не дублирую)"
  }
  $out.lines+="   самый новый $n в чате Gemini не найден — очередь Gemini, отправлю сам через $([int]$Cfg.AutoSendGraceSec) сек (перед отправкой перепроверю чат, вопрос не задаю)"
  $out
}
# Пункт 27C: файл уже в чате Gemini? (по имени или содержимому; ошибки чтения — $null, т.е. «не знаю»)
function Test-FileInGemini($f,[switch]$ContentOnly){
  if(-not $f){ return $null }
  try{
    $p= if($f.FullName){ $f.FullName } else { Join-Path $Cfg.Downloads $f.Name }
    $txt= if(Test-Path -LiteralPath $p){ [IO.File]::ReadAllText($p,[Text.Encoding]::UTF8) } else { '' }
    $r=Gem-FindFile $(if($ContentOnly){''}else{$f.Name}) $txt
    if($r){ Log "Чат Gemini: $($f.Name) найден ($(if($r.how -eq 'content'){'по содержимому'}else{'по имени'}), $(if($r.last){'последним запросом'}else{'не последним'}))" }
    $r
  }catch{ Log "Чат Gemini: не удалось проверить, есть ли $($f.Name) в чате ($($_.Exception.Message))"; $null }
}
function Send-NewestPrompt([string]$n,[string]$Why=''){
  $q= if($Why){ "$Why`nОтправить $n в Gemini?" } else { "📄 После запуска самый новый отчёт — $n, его нет в текущем чате Gemini. Отправить его в Gemini?" }
  $p=New-TgPrompt -Kind 'newest' -Text "$q`nБолее старые файлы пропущены (считаю, что сделаны вручную). Новые файлы, которые появятся, обработаю как обычно." -Buttons "Отправить $n в Gemini=send;Не отправлять, ждать новый=wait" -Data @{ name=$n }
  if(-not $p){ $script:Held.Remove($n); [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note 'не отправлен: вопрос в Telegram не ушёл' -Force); Save-State; Log "Запуск: вопрос про $n не отправлен — файл пропущен (ничего не отправлено)" }
}
function Resolve-NewestChoice([string]$n,[string]$Choice){
  $script:Held.Remove($n)
  if($Choice -eq 'send'){
    if((Get-Stage $n) -eq 'sent'){ Set-Stage $n 'resend' } elseif((Get-Stage $n) -eq 'skipped'){ Set-Stage $n 'resend' }
    $script:AutoSend[$n]=$true   # перед отправкой перепроверю чат: если уже отправлен вручную — не дублирую
    Tg-Send "Ок, отправлю $n в Gemini$(if($script:Busy){' после текущего шага'})." | Out-Null
  } else {
    [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note $(if($Choice -eq 'expired'){'вопрос при запуске: время вышло'}else{'«не отправлять» по кнопке'}) -Force); Save-State
    Tg-Send "Ок, $n не отправляю$(if($Choice -eq 'expired'){' (ответа не было)'}). Жду новый файл." | Out-Null
  }
}
function Next-FileName{ $f=Next-File; if($f){ $f.Name } else { $null } }
# Файл дописан: размер и время изменения не меняются StableSec и файл открывается эксклюзивно. По таймауту — исключение (не отправляем недописанное).
function Test-FileExclusive([string]$Path){ try{ $fs=[IO.File]::Open($Path,'Open','Read','None'); $fs.Dispose(); $true }catch{ $false } }
function Wait-FileStable([string]$Path,[int]$StableSec=$Cfg.StableSec,[int]$TimeoutSec=$Cfg.StableTimeoutSec){
  $t0=Get-Date
  while($true){
    $a=Get-Item -LiteralPath $Path -EA Stop; $s1=$a.Length; $m1=$a.LastWriteTimeUtc
    Nap $StableSec
    $b=Get-Item -LiteralPath $Path -EA Stop
    if($b.Length -eq $s1 -and $b.LastWriteTimeUtc -eq $m1 -and $b.Length -gt 0 -and (Test-FileExclusive $Path)){ return }
    if(((Get-Date)-$t0).TotalSeconds -gt $TimeoutSec){ throw "Файл $([IO.Path]::GetFileName($Path)) не стабилизировался за $TimeoutSec сек (ещё пишется или занят) — не отправляю, повторю позже" }
  }
}

# ---------- Модель / лимит ----------
function Get-ModelNow{ $m=Gem-GetModel; if(!$m){ throw 'Не удалось прочитать название модели Gemini' }; $script:LastModel=$m; $m }
function Is-Argon($m){ [bool]($m -and ([string]$m).IndexOf($Cfg.ModelMustContain,[StringComparison]::OrdinalIgnoreCase) -ge 0) }
# ---------- Пункт 27D: звуки (Sounds = important | off | all; один и тот же звук не чаще SoundRepeatMin мин) ----------
$script:SoundLast=@{}
function Invoke-Beep([int]$Freq,[int]$Ms){ if($env:GG_NO_BEEP -eq '1'){ return }; try{ [Console]::Beep($Freq,$Ms) }catch{} }
function Play-Sound([string]$Kind){
  if(Test-StopNow){ return $false }
  $last=$script:SoundLast[$Kind]
  if(-not (Test-SoundAllowed $Kind ([string]$Cfg.Sounds) $last (Get-Date) ([double]$Cfg.SoundRepeatMin))){ return $false }
  $script:SoundLast[$Kind]=Get-Date
  $first=$true
  foreach($t in @(Get-SoundTones $Kind)){ if(-not $first){ Start-Sleep -Milliseconds 140 }; $first=$false; Invoke-Beep $t.f $t.ms }
  $true
}
function Enter-LimitStop($m,$note){
  $script:LimitModel=$m; $script:LastLimitCheck=Get-Date
  if($script:LimitStop){ if($note){ Log $note; Tg-Send "⛔ $note" | Out-Null }; return }
  $script:LimitStop=$true; $script:LimitSince=Get-Date; $script:AutoPlan=$null; $script:AutoPlanKey=''
  $auto= if($Cfg.AutoResume){ "`nПосле сброса лимита сам проверю страницу лимитов$(if($Cfg.AutoSwitchModel){", верну $($Cfg.ModelMustContain)"}) и продолжу." } else { '' }
  $msg="⛔ Работа остановлена: в Gemini вместо $($Cfg.ModelMustContain) выбрана модель «$m» — похоже, закончился дневной лимит. Смени аккаунт.$(if($note){"`n$note"})`nПроверяю модель раз в $($Cfg.ModelRecheckSec) сек; можно написать «продолжай».$auto"
  Log $msg; Tg-Send $msg | Out-Null; [void](Play-Sound 'limit')
}
function Resume-Work($how){
  $script:LimitStop=$false; $script:AutoPlan=$null; $script:AutoPlanKey=''; $script:AutoFails=0; $m= try{ Get-ModelNow }catch{ '?' }; $n=Next-FileName
  $msg="▶️ Работа возобновлена ($how). Модель: $m. Следующий файл: $(if($n){$n}else{'новых файлов пока нет'})"; Log $msg; Tg-Send $msg | Out-Null
}
function Assert-Argon($ctx){ $m=$null; try{ $m=Get-ModelNow }catch{ Enter-LimitStop '?' "Не удалось прочитать модель Gemini. $ctx"; throw [GG.RelayLimitException]::new('модель не прочитана') }; if(-not (Is-Argon $m)){ Enter-LimitStop $m $ctx; throw [GG.RelayLimitException]::new("модель «$m»") }; $m }
function Assert-NotPaused($ctx){ if($script:Paused){ throw [GG.RelayPausedException]::new("СТОП — $ctx не выполняю") } }
function Assert-CanSendGemini($ctx){
  Assert-NotPaused $ctx
  if($script:QStopG){ throw [GG.RelayLimitException]::new("остановлено по лимиту Gemini (сайт) — $ctx не выполняю") }
  Assert-Argon "$ctx не выполняю."
}
function Assert-Quota([switch]$Gemini,[switch]$Ag){
  if($Gemini -and $script:QStopG){ throw [GG.RelayLimitException]::new('остановлено по лимиту Gemini (сайт)') }
  if($Ag -and $script:QStopA){ throw [GG.RelayLimitException]::new('остановлено по лимиту Antigravity') }
}

# ---------- Свежесть ответа ----------
function Check-Fresh([string]$Text){
  $hh=Get-Hash8 $Text
  if(Test-RelayHash $script:St $hh){ throw [GG.RelayStaleException]::new("Скопирован ответ, который уже передавался (хэш $hh, первая строка «$(Get-FirstLine $Text)»)") }
  $hh
}
# Длинный чат Gemini подгружает историю лениво — число запросов может уменьшиться. Тогда сверяем последний «Файл отчёта: …».
function Check-OurPrompt($pBefore,[string]$Name){
  if($pBefore -lt 0){ return }; $pNow=Gem-CountPrompts; if($pNow -gt $pBefore){ return }
  if($Name){ $lp=$null; try{ $lp=Gem-LastReportPrompt }catch{}; if($lp -eq $Name){ Log "Запросов в чате Gemini было $pBefore, стало $pNow (история подгружается частично), но последний отчёт в чате — ${Name}: ответ беру"; return } }
  throw "Не вижу нашего сообщения в диалоге Gemini (запросов было $pBefore, стало $pNow) — ответ НЕ передаю"
}
function Ag-HasText([string]$Text){
  # пункт 28: AgTransport=cdp — сверяю с текстом страницы Antigravity (UIA-дерево Electron чат не показывает — была ложная «нет»)
  if($Cfg.AgTransport -eq 'cdp'){
    try{ $r=Test-TextInBody -Text $Text -Body ([string](AgEval-Js 'body')); if($null -ne $r){ return $r } }catch{ Log "Сверка с Antigravity через CDP: $($_.Exception.Message) — пробую UIA" }
  }
  $h=Ag-GetWindow; if(!$h){ return $false }
  $k=Get-NormKey $Text 120; if($k.Length -lt 20){ return $false }
  foreach($ct in 'Text','Edit','ListItem','Group'){
    foreach($e in @(Uia-FindAll -Root $h -ControlType $ct)){ $nm=Get-NormKey (Uia-Name $e) 100000; if($nm.Length -ge 60 -and ($nm.StartsWith($k) -or $k.StartsWith($nm))){ return $true } }
  }
  $false
}

# ---------- Передача ----------
function Relay-ToAg([string]$n,[string]$ans,[string]$hh,[string]$m2,[string]$how='',[switch]$NoGate){
  Assert-Quota -Ag   # пункт 46: лимит Antigravity блокирует только передачу В Antigravity (ответ остаётся «получен» в кэше)
  if(-not $NoGate){ $g=Get-BlockGate $ans; if($g.tagged -and -not $g.ok){ Set-Stage $n 'stale' $hh -Force; $script:StaleNotified[$n]=1; Notify-BlockGate $g $hh $n; return } }
  Ag-Send -Text $ans -Label "ответ на $n" -Name $n
  Register-BlockRelayed $ans $hh
  Add-RelayHash $script:St $hh $Cfg.HashKeep; Set-Stage $n 'relayed' $hh -Force:((Get-Stage $n) -in @('','done','relayed'))
  Remove-AnswerCache $n
  [void](Play-Sound 'info')
  $rec= if($script:AgBlock){ "✅ Antigravity снова $(if($script:AgBlock.kind -eq 'foreign'){'свободен (поле чата очищено)'}else{'отвечает'}), ответ передан.`n" } else { '' }
  if($script:AgBlock){ Log "Antigravity: состояние «$($script:AgBlock.kind)» с $($script:AgBlock.since.ToString('HH:mm:ss')) закончилось" }
  $script:AgBlock=$null
  $msg="$rec✅ [$(ProjOf $n)] Ответ на $n дала модель $m2; блок Markdown ($($ans.Length) симв., хэш $hh, первая строка «$(Get-FirstLine $ans)») передан в Antigravity$how"
  Log $msg; Tg-Send $msg | Out-Null; Mark-Done $n
}
# ---------- Сохранённые ответы (до подтверждённой доставки в Antigravity) ----------
function Get-AnswerCachePath([string]$n){ Join-Path $Cfg.AnswerDir ($n -replace '[\\/:*?"<>|]','_') }
function Save-AnswerCache([string]$n,[string]$ans){ try{ if(-not (Test-Path -LiteralPath $Cfg.AnswerDir)){ New-Item -ItemType Directory -Force $Cfg.AnswerDir | Out-Null }; Write-AtomicText -Path (Get-AnswerCachePath $n) -Text $ans -NoBackup }catch{ Log "Ответ на $($n): не удалось сохранить копию ($($_.Exception.Message))" } }
function Get-AnswerCache([string]$n,[string]$hash){
  $p=Get-AnswerCachePath $n; if(-not (Test-Path -LiteralPath $p)){ return $null }
  try{ $t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8) }catch{ return $null }
  if($hash -and (Get-Hash8 $t) -ne $hash){ return $null }
  $t
}
function Remove-AnswerCache([string]$n){ Remove-Item -LiteralPath (Get-AnswerCachePath $n) -EA 0 }
function Set-Stale([string]$n,[string]$hh,[string]$why){
  Set-Stage $n 'stale' $hh
  if(-not $script:StaleNotified.ContainsKey($n)){
    $script:StaleNotified[$n]=1
    $msg="⚠️ $($n): $why. В Antigravity НЕ передаю и не повторяю автоматически. Ответь «передай всё равно» — передам этот ответ, или «отправь заново» — отправлю отчёт в Gemini ещё раз."
    Log $msg; Tg-Send $msg | Out-Null
  }
}
function Finish-Answered([string]$n){
  $hh=[string]$script:St.files[$n].hash
  [void](Assert-AgReady)   # Antigravity завис/перезапускается — Gemini не трогаем, ждём
  $ans=Get-AnswerCache $n $hh
  if($ans){ $m2= if($script:LastModel){ $script:LastModel } else { $Cfg.ModelMustContain } }
  else{
    $m2=Assert-Argon "Ответ на $n НЕ передан."
    if($script:QStopG){ throw "остановлено по лимиту Gemini (сайт) — ответ на $n не передаю" }
    $ans=Gem-CopyCode
    if(!$ans){ throw "у $n этап «ответ скопирован», но блок Markdown в чате сейчас не найден — не передаю" }
    $h2=Get-Hash8 $ans
    if($hh -and $h2 -ne $hh){ throw "ответ в Gemini изменился (хэш $h2, а был $hh) — $n автоматически не передаю" }
    Save-AnswerCache $n $ans
  }
  $h2=Get-Hash8 $ans
  if((Test-RelayHash $script:St $h2) -or (Ag-HasText $ans)){ $msg="ℹ️ Ответ на $n уже есть в Antigravity — повторно не вставляю"; if($script:AgBlock){ $msg="✅ Antigravity снова отвечает.`n$msg"; $script:AgBlock=$null }; Log $msg; Tg-Send $msg | Out-Null; Register-BlockRelayed $ans $h2; Add-RelayHash $script:St $h2 $Cfg.HashKeep; Set-Stage $n 'relayed' $h2; Remove-AnswerCache $n; Mark-Done $n; return }
  Relay-ToAg $n $ans $h2 $m2
}
function Process-File($next){
  $n=$next.Name; $st=Get-Stage $n
  if($st -eq 'operator'){ $script:State="🛑 $($n): Argon ждёт решения оператора («Напиши» / «Отправь заново»)"; return }
  if($st -eq 'stale'){ $script:State="$($n): ждёт решения по повторному ответу («передай всё равно» / «отправь заново»)"; return }
  if($st -eq 'answered'){ if($script:QStopA){ $script:State="ответ на $n получен — передам в Antigravity после сброса его лимита"; return }; $script:State="передаю уже полученный ответ на $n"; Finish-Answered $n; return }
  $ctx=$null; $pBefore=-1
  if($st -eq '' -and $Cfg.StartupNewestOnly){
    $nh=Get-NewerHandled $next
    if($nh){ [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note "старее уже обработанного $nh" -Force); Save-State
      $msg="⏭ $n старее уже обработанного $nh (по времени файла) — в Gemini НЕ отправляю, пропускаю. Если он всё-таки нужен — пришлите его текст через «Напиши»."; Log $msg; Tg-Send $msg | Out-Null; return }
  }
  if($script:SendNotBefore.ContainsKey($n)){
    if((Get-Date) -lt $script:SendNotBefore[$n]){ $script:State="$($n): отправлю в Gemini в $($script:SendNotBefore[$n].ToString('HH:mm:ss')) (жду, не отправлен ли вручную)"; return }
    $script:SendNotBefore.Remove($n)
  }
  $auto=$script:AutoSend.ContainsKey($n); if($auto){ $script:AutoSend.Remove($n) }
  if(($st -eq '' -or ($auto -and $st -eq 'resend')) -and $Cfg.MatchByContent){
    # пункт 27C: пользователь мог отправить файл в Gemini сам — не дублирую
    $hit=Test-FileInGemini $next
    if($hit -and $hit.how -eq 'name' -and (Test-ReportNewerThanAg $script:St $next.LastWriteTime)){
      Log "⚖ Очередь: $n ($($next.LastWriteTime.ToString('HH:mm:ss'))) новее последней вставки в Antigravity ($(Get-LastAgRelayTimeRu)) — имя в чате Gemini — это упоминание в промпте, а не отправка; очередь Gemini → проверяю по содержимому, не отправлен ли вручную"; $hit=Test-FileInGemini $next -ContentOnly }
    if($hit -and $hit.last){
      Set-Stage $n 'sent'; $st='sent'; $script:Adopted[$n]=$true
      $msg="ℹ️ [$(ProjOf $n)] $n уже есть в чате Gemini ($(if($hit.how -eq 'content'){'узнал по содержимому — отправлен вручную'}else{'вложение с именем файла'})) — повторно НЕ отправляю, жду и беру ответ"; Log $msg; Tg-Send $msg | Out-Null
    } elseif($hit){
      [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note 'уже есть в чате Gemini, но не последним запросом' -Force); Save-State
      $msg="⏭ [$(ProjOf $n)] $n уже есть в чате Gemini, но после него были другие запросы — повторно НЕ отправляю и ответ автоматически не беру («передай ответ» — вручную, «отправь заново» — отправить)"; Log $msg; Tg-Send $msg | Out-Null; return
    }
  }
  if($st -eq '' -and $next.FullName){
    $fh=Get-FileHash8 $next.FullName; $pM=[int][regex]::Match($n,$Cfg.Pattern).Groups['n'].Value
    if($fh -and (Test-SentRecord $script:St 'gem' '' -1 $fh)){ Set-Stage $n 'sent' -Force; $st='sent'; $script:Adopted[$n]=$true; Log "ℹ️ $($n): это содержимое (хэш $fh) уже отправлялось в Gemini — повторно не отправляю, жду ответ" }
  }
  if($st -ne 'sent'){
    $script:State="обрабатываю $n"
    Log "Новый файл: $n (проект: $(ProjOf $n))$(if($st -eq 'resend'){' (повторная отправка)'})"
    Wait-FileStable $next.FullName
    $m=Assert-CanSendGemini "Файл $n НЕ отправлен и остаётся в очереди;"
    try{ $ctx=Gem-SendFile $next.FullName $n }
    catch{ if((Get-ErrorKind $_) -eq 'notsent'){ $em="❌ [$(ProjOf $n)] $n НЕ отправлен в Gemini: не удалось прикрепить файл ($($_.Exception.Message)). Текст в поле не вставляю; повторю позже."; Log $em; Tg-Send $em | Out-Null }; throw }
    $pBefore=[int]$ctx.pBefore
    Set-Stage $n 'sent'
    try{ Add-SentRecord $script:St 'gem' (ProjOf $n) $pM (Get-FileHash8 $next.FullName); Save-State }catch{}
    Tg-Send "📤 [$(ProjOf $n)] Файл $n отправлен в Gemini (модель: $m)" | Out-Null
  } else { Log "Повтор: $n уже отправлен в Gemini (этап «отправлен»), повторно не отправляю — забираю ответ" }
  $script:State="жду ответ Gemini на $n"
  if(-not $ctx -and $Cfg.WaitAfterLastPrompt){ Wait-AnswerAfterLastPrompt $n }   # файл в чате без нашей отправки: ответ — только ПОСЛЕ последнего запроса (с этим отчётом)
  [void](Wait-GemAnswerStoppable $ctx)
  $m2=Get-ModelNow
  if(-not (Is-Argon $m2)){
    Set-Stage $n 'resend'
    Enter-LimitStop $m2 "Ответ на $n пришёл от модели «$m2» и в Antigravity НЕ передан; после возобновления файл будет отправлен в Gemini заново."
    return
  }
  Check-OurPrompt $pBefore $n
  $ref=Get-AnswerRefNow   # пункт 44: «Ответ на: <отчёт>.md» первой строкой ответа
  if($ref -and $ref -ne $n){ Set-Stale $n '' "Gemini пишет «Ответ на: $ref», а ждём ответ на $n — ответ не беру"; return }
  if($ref){ Log "Ответ Gemini привязан к $n по строке «Ответ на: $ref»" }
  if($pBefore -lt 0 -and -not $ref){ $lp=Gem-LastReportPrompt; if($lp -and $lp -ne $n){
    $hit= if($Cfg.MatchByContent){ Test-FileInGemini $next } else { $null }   # пункт 27C: отправлен вручную без «Файл отчёта:»
    if(-not ($hit -and $hit.last)){ throw "последний отчёт в чате Gemini — $lp, а не $n; ответ не беру" }
    Log "Последний «Файл отчёта:» в чате — $lp, но $n найден последним запросом ($($hit.how)) — ответ беру"
  } }
  $ans=Gem-CopyCode
  if(!$ans){
    # пункт 21: весь ответ берём из Gemini один раз сейчас и сохраняем; в Telegram — вопрос «Прислать копию?» с кнопками
    $w=Get-WholeAnswer
    if($w.text -and (Test-OperatorStop $w.text)){ Enter-OperatorWait $n $w.text $m2; return }   # пункт 44: осознанная остановка — не nocode, без resend
    $full= if($w.text){ Save-FullAnswer $n $w.text } else { $null }
    Set-Stage $n 'nocode'; Mark-Done $n
    Log "⚠️ Файл $($n): в последнем ответе Gemini (модель $m2) нет блока кода '$($Cfg.CodeBlockLang)'. В Antigravity ничего не вставлено. Полный ответ: $(if($full){"сохранён ($($w.text.Length) симв., $($w.via))"}else{'не сохранён'})"
    [void](Send-NoCodePrompt -Label $n -Model $m2 -FullPath $full -File $n); [void](Play-Sound 'nocode')
    return
  }
  $hh=Get-Hash8 $ans
  if(Test-RelayHash $script:St $hh){
    # прежний ответ ещё на экране (новый не начался/генерируется) — жду новый, и только по таймауту спрашиваю
    Log "Ответ на $n совпал с уже переданным (хэш $hh) — похоже, это прежний ответ; жду новый до $($Cfg.DupAnswerWaitSec) сек"
    $fresh=Wait-FreshAnswer $n $hh
    if(-not $fresh){ Set-Stale $n $hh "ответ Gemini совпадает с уже переданным раньше (хэш $hh, «$(Get-FirstLine $ans)»), нового ответа за $($Cfg.DupAnswerWaitSec) сек не появилось"; return }
    $m2=Get-ModelNow
    if(-not (Is-Argon $m2)){ Set-Stage $n 'resend'; Enter-LimitStop $m2 "Ответ на $n пришёл от модели «$m2» и в Antigravity НЕ передан; после возобновления файл будет отправлен в Gemini заново."; return }
    $ans=$fresh; $hh=Get-Hash8 $ans; Log "Новый ответ на $n получен (хэш $hh)"
    if(Test-RelayHash $script:St $hh){ Set-Stale $n $hh "ответ Gemini совпадает с уже переданным раньше (хэш $hh)"; return }
  }
  if($script:Adopted.ContainsKey($n)){   # пункт 24: файл подхвачен при запуске — ответ мог быть уже вставлен вручную
    $script:Adopted.Remove($n)
    if(Ag-HasText $ans){ Register-BlockRelayed $ans $hh; Add-RelayHash $script:St $hh $Cfg.HashKeep; Set-Stage $n 'answered' $hh; Set-Stage $n 'relayed' $hh; Mark-Done $n; $msg="ℹ️ Ответ на $n уже есть в Antigravity (вставлен вручную) — повторно не вставляю"; Log $msg; Tg-Send $msg | Out-Null; return }
  }
  Set-Stage $n 'answered' $hh
  Save-AnswerCache $n $ans
  Relay-ToAg $n $ans $hh $m2
}
# Ждёт, пока после последнего запроса в чате (он содержит отчёт) появится законченный ответ. Только чтение.
function Wait-AnswerAfterLastPrompt([string]$n){
  $t0=Get-Date; $quiet=$null
  while($true){
    $gen=$false; try{ $gen=[bool](Gem-IsGenerating) }catch{}
    $ok=$false; if(-not $gen){ try{ $ok=[bool](Gem-PeekAnswer).answered }catch{} }
    if($ok){ if(-not $quiet){ $quiet=Get-Date }; if(((Get-Date)-$quiet).TotalSeconds -ge $Cfg.GeminiQuietSec){ return } } else { $quiet=$null }
    if(((Get-Date)-$t0).TotalSeconds -gt $Cfg.GeminiTimeoutSec){ throw "Таймаут ожидания ответа Gemini на $n (после последнего запроса ответа нет)" }
    Nap 2
  }
}
# Ответ совпал с уже переданным: ждать ответ с другим хэшем (после генерации/изменения), до DupAnswerWaitSec. $null — не дождался.
function Wait-FreshAnswer([string]$n,[string]$OldHash){
  $lim=[double]$Cfg.DupAnswerWaitSec; if($lim -le 0){ return $null }
  $t0=Get-Date; $base=$null; $quiet=Get-Date; $seenGen=$false; $lastCopy=[datetime]::MinValue
  while(((Get-Date)-$t0).TotalSeconds -lt $lim){
    Nap 2
    $gen=$false; try{ $gen=[bool](Gem-IsGenerating) }catch{}
    if($gen){ $seenGen=$true; $quiet=Get-Date; continue }
    $pk=$null; try{ $pk=Gem-PeekAnswer }catch{}
    $sig= if($pk){ "$($pk.answered)|$(@($pk.labels) -join ',')|$(if($pk.code){ Get-Hash8 ([string]$pk.code) })" } else { '' }
    if($null -eq $base){ $base=$sig }
    if($sig -ne $base){ $base=$sig; $quiet=Get-Date; $seenGen=$true; continue }
    if(((Get-Date)-$quiet).TotalSeconds -lt $Cfg.GeminiQuietSec){ continue }
    if($pk -and $pk.code){ if((Get-Hash8 ([string]$pk.code)) -eq $OldHash){ continue } }
    elseif(-not $seenGen -and ((Get-Date)-$lastCopy).TotalSeconds -lt 30){ continue }   # текст блока не читается — копирую не чаще раза в 30 с
    if($pk -and -not $pk.answered){ continue }
    $lastCopy=Get-Date; $seenGen=$false
    $a=Gem-CopyCode
    if($a -and (Get-Hash8 $a) -ne $OldHash){ return $a }
  }
  $null
}
function Get-StaleFile{ @(Get-Files -All | Where-Object { (Get-Stage $_.Name) -in @('stale','operator') }) | Sort-Object Time | Select-Object -Last 1 }

# ---------- Команды ----------
$HelpText=@'
<b>GGskript — команды</b>
Кнопки внизу и меню «/» сгруппированы одинаково. Эмодзи набирать не нужно.

<b>📂 Файлы</b>
• <b>Отчёт в Gemini</b> (/togemini) — последний отчёт агента из Downloads снова в Gemini (с подтверждением)
• <b>Ответ в Antigravity</b> (/toag) — весь последний ответ Gemini в Antigravity (с подтверждением)

<b>🛠 Antigravity</b>
• <b>Antigravity: текст</b> (/ag) — бот попросит текст, отправит агенту и пришлёт его ответ (новый отчёт)
• /relay — только блок «Markdown» из последнего ответа Gemini
• /force — передать ответ, совпавший со старым
• /accept — нажать «Accept all»
• /autoallow вкл | выкл — сам отвечать «Yes, allow this time»

<b>✨ Gemini</b>
• <b>Gemini: текст</b> (/gemini) — бот попросит текст, отправит в Gemini и пришлёт ответ
• <b>Ответ Gemini</b> (/answer) — последний ответ Gemini (длинный — частями и файлом)

<b>⚙️ Управление</b>
• <b>Статус</b> — что сейчас происходит
• <b>Стоп</b> — пауза: окна не трогаю, слушаю Telegram
• <b>Старт</b> — проверка окон, лимитов, модели и продолжение
• /exit — выключить скрипт (запуск снова — только ярлыком на ПК)

<b>🧰 Прочее</b>
• <b>Скрин</b> — снимок экрана · <b>Лимиты</b> — проверить сейчас
• «выключи компьютер [в 14:00 | через 30 минут]» (/shutdown) · «отмени выключение» (/shutdown_cancel) · «когда выключение»
• /windows — авто-закрываемые окна · «убери из списка N»
• Любой другой текст — спрошу, куда переслать

<i>Звуки на ПК: 1 длинный низкий — остановка (лимит/модель), 2 коротких — нет блока Markdown, 3 коротких — нужна помощь.</i>
'@
# Статус для Telegram: заголовок, «<b>Поле:</b> значение», хвост журнала моноширинно.
function Format-StatusHtml([string]$T){
  $i=$T.IndexOf("`nПоследние строки журнала:"); $head= if($i -ge 0){ $T.Substring(0,$i) } else { $T }; $tail= if($i -ge 0){ $T.Substring($i).Trim() -replace '^Последние строки журнала:\s*','' } else { '' }
  $lines=@($head.Trim() -split "`r?`n" | ForEach-Object { if($_ -match '^([^:]{2,45}):\s*(.*)$'){ "<b>$(ConvertTo-TgHtml $matches[1]):</b> $(ConvertTo-TgHtml $matches[2])" } elseif($_.Trim()){ ConvertTo-TgHtml $_ } })
  $o="ℹ️ <b>Статус GGskript</b>`n`n"+($lines -join "`n")
  if($tail){ $o+="`n`n<b>Журнал:</b>`n<pre>$(ConvertTo-TgHtml $tail)</pre>" }
  $o
}
function Get-StatusText{
  $m=try{ Get-ModelNow }catch{ "? ($($_.Exception.Message))" }
  $acc=try{ $h=Ag-GetWindow; [bool]($h -and (Find-AcceptAll $h)) }catch{ $false }
  $pend=@($script:St.files.Keys | Where-Object { (Get-Stage $_) -in @('sent','answered','resend','stale','operator') } | ForEach-Object { "$_ — $(Get-StageRu (Get-Stage $_))" }) -join '; '; if(!$pend){ $pend='нет' }
  $tail= try{ (Get-Content -LiteralPath $Cfg.LogFile -Encoding UTF8 -Tail 5) -join "`n" }catch{ '' }
  $st= if($script:Paused){ "⏸ Остановлен — ничего не делаю (жду «Старт»)" } else { $script:State }
  $lim= if($script:LimitStop){ "ДА — модель «$($script:LimitModel)» вместо $($Cfg.ModelMustContain) с $($script:LimitSince.ToString('HH:mm')) (Якутск)" } else { 'нет' }
  $nx=Next-FileName
  $auto= if(-not $Cfg.AutoResume){ 'выключено (AutoResume=false)' } elseif($script:AutoPlan){ "проверю в $(Format-PlanTime $script:AutoPlan.at) — $($script:AutoPlan.why)" } else { 'не требуется' }
@"
Состояние: $st
Остановка по лимиту: $lim
Автовозобновление: $auto
Antigravity: $(if($script:AgBlock){ "НЕ принимает ответ — $($script:AgBlock.kind) с $($script:AgBlock.since.ToString('HH:mm')): $($script:AgBlock.msg)" } else { 'принимает ввод' })
Следующий файл в очереди: $(if($nx){$nx}else{'нет'})
Последний переданный файл: $(if($script:LastDone){$script:LastDone}else{'за этот запуск ещё не было'})
Незавершённые этапы: $pend
Пауза: $(if($script:Paused){'ДА'}else{'нет'})
Команд в очереди: $($script:Queue.Count)
Модель Gemini: $m
Транспорт: Gemini=$($Cfg.GeminiTransport), Antigravity=$($Cfg.AgTransport)
Кнопка Accept all в Antigravity: $(if($acc){'есть'}else{'нет'})
Лимиты: $(Quota-Text)
Выключение компьютера: $(try{ $sp=Get-ShutdownPlan; if($sp){ "$(Format-ShutWhen $sp.at) ($(if($sp.force){'таймер Windows'}else{'выключит GGskript'}))" } else { 'не запланировано' } }catch{ '?' })

Последние строки журнала:
$tail
"@
}
# Пункт 25B/C: в режиме СТОП — никаких лимитов, модели и окон. Только Telegram/команды и таймер выключения ПК.
$script:WindowKinds=@('gemini','ag','relay','force','lastanswer','accept','limits','fwdans','fwdans-prep','fwdtext','resendfile','gemask','agask','fwdans-pc')
function Get-StopRefusal([string]$K){ "⏹ Сейчас СТОП — окна не трогаю, команду ($K) не выполняю. Нажмите «Старт», потом повторите." }
function Invoke-StoppedStep{
  $script:State='⏸ Остановлен — ничего не делаю (жду «Старт»)'
  if($script:NeedStart -and -not $script:StopAnnounced){
    $script:StopAnnounced=$true
    $msg="🚀 GGskript v2 запущен (pid $PID) в режиме СТОП: окна, лимиты и модель не проверяю, ничего не отправляю, слушаю Telegram.`n«Старт» — выполнить протокол запуска и начать работу. «выключи скрипт» — завершить процесс."
    Log $msg; Tg-Send $msg -Markup (Get-TgReplyMarkup) | Out-Null
  }
  while($script:Queue.Count -gt 0){ $c=$script:Queue.Dequeue(); if($c.k -in $script:WindowKinds){ Log "Стоп: команда $($c.k) из очереди не выполнена"; Tg-Send (Get-StopRefusal $c.k) | Out-Null } else { try{ Run-Action $c }catch{ Tg-Send "❌ Команда не выполнена: $($_.Exception.Message)" | Out-Null } } }
  Nap $Cfg.PollSec
}
function Handle-Command([string]$Text,[string]$Source='pc',[int64]$ReplyTo=0){
  # «напиши» → ждём текст: любое сообщение (кроме «отмена»/«нет») — это текст для пересылки
  if($Source -eq 'tg' -and $script:TgAwait){
    if((Get-Date) -gt $script:TgAwait.until){ $script:TgAwait=$null }
    else{
      $aw=$script:TgAwait; $script:TgAwait=$null
      if((Parse-Command -Text $Text).k -eq 'cancel'){ Tg-Send 'Отменено, ничего не отправлено.' | Out-Null; return }
      if($aw.direct){ Queue-ChatAction @{ k=$(if($aw.target -eq 'ag'){'agask'}else{'gemask'}); text=$Text.Trim() }; return }
      [void](Ask-WhereToSend -Text $Text.Trim() -Kind 'where' -Target $aw.target); return
    }
  }
  # Кнопки панели на ПК (/pc_…): подтверждение уже получено в окне панели, ответы — в журнал панели.
  if($Source -eq 'pc' -and $Text -match '^\s*/pc_(\w+)(?:\s+(.*))?$'){ Invoke-PcButton $matches[1] ([string]$matches[2]); return }
  $c=Parse-Command -Text $Text -HasDialog ([bool]($script:Blk -and $script:Blk.key)) -Strict ([bool]$Cfg.StrictCommands)
  $c.src=$Source
  if($script:Paused -and $c.k -in $script:WindowKinds){ Log "Стоп: команда $($c.k) отклонена"; Tg-Send (Get-StopRefusal $c.k) | Out-Null; return }
  switch($c.k){
    'help'    { Tg-Send $HelpText -Html -Markup (Get-TgReplyMarkup) | Out-Null }
    'status'  { Tg-Send (Format-StatusHtml (Get-StatusText)) -Html | Out-Null }
    'shutdown'       { Request-Shutdown $c.spec $Source $ReplyTo }
    'shutdowncancel' { Cancel-Shutdown }
    'shutdownstatus' { Tg-Send (Get-ShutdownStatusText) | Out-Null }
    { $_ -in 'pause','stop' } { if($script:Paused){ Tg-Send '⏹ Уже СТОП. «Старт» — продолжить, «выключи скрипт» — завершить процесс.' | Out-Null } else { Set-Pause $true $(if($Source -eq 'tg'){'Telegram'}else{'ПК'}) } }
    'exit'    { if($Source -ne 'tg'){ $script:StopReq=$true; Log 'Выключение скрипта (команда с ПК)'; return }
                [void](New-TgPrompt -Kind 'exit' -Text "Выключить GGskript совсем? Процесс завершится, и из Telegram его снова запустить будет НЕЛЬЗЯ — только ярлыком GGskript на ПК.`nЕсли нужно просто остановиться — «Стоп» (процесс останется и будет слушать Telegram)." -Buttons 'Да, выключить скрипт=yes|Нет=no' -TimeoutMin ([double]$Cfg.ShutdownConfirmMin) -ReplyTo $ReplyTo) }
    'resume'  { $wasP=$script:Paused; if($wasP){ Set-Pause $false 'команда' }; $qb=Quota-Blocked; if($qb){ Quota-Override; Tg-Send "▶️ Ок, игнорирую остановку по лимитам ($qb), пока не станет хуже ещё на $($Cfg.QuotaReWarnStep) пунктов." | Out-Null }
      if($script:LimitStop){ Resume-Work 'по команде' } elseif(-not $qb -and -not $wasP){ Tg-Send "▶️ Продолжаю работу. Следующий файл: $(if($n=Next-FileName){$n}else{'новых файлов пока нет'})" | Out-Null } }
    'autoaccept' { if($null -ne $c.on){ Set-AutoAccept ([bool]$c.on) $Source } else { Tg-Send "Автопринятие «Accept all»: $(if($Cfg.AutoAcceptAll){'ВКЛ'}else{'выкл'}). «автопринятие вкл» / «автопринятие выкл»." | Out-Null } }
    'autoallow' { if($null -ne $c.on){ Set-AutoAllow ([bool]$c.on) $Source } else { Tg-Send "Автоподтверждение запросов Antigravity: $(if($Cfg.AutoAllowPrompts){'ВКЛ'}else{'выкл'}). Включить/выключить: «автоподтверждение вкл» / «автоподтверждение выкл»." | Out-Null } }
    'shot'    { try{ Send-Screenshot }catch{ Tg-Send "Не удалось сделать скриншот: $($_.Exception.Message)" | Out-Null } }
    'confirm' { if($Source -eq 'tg' -and $ReplyTo -and (Resolve-TextAnswer 'confirm' $ReplyTo)){ return }
      if(-not $script:PendingConfirm -and $Source -eq 'tg' -and (Resolve-TextAnswer 'confirm' 0)){ return }
      if($script:PendingConfirm -and ((Get-Date)-$script:PendingConfirm.time).TotalMinutes -lt 5){ $pc=$script:PendingConfirm.c; $pc.confirmed=$true; $script:PendingConfirm=$null; $script:Queue.Enqueue($pc); Tg-Send 'Подтверждено, выполняю.' | Out-Null } else { Tg-Send 'Нечего подтверждать.' | Out-Null } }
    'cancel'  { if($Source -eq 'tg' -and $ReplyTo -and (Resolve-TextAnswer 'cancel' $ReplyTo)){ return }
      if(-not $script:PendingConfirm -and $Source -eq 'tg' -and (Resolve-TextAnswer 'cancel' 0)){ return }
      if($script:PendingConfirm){ $script:PendingConfirm=$null; Tg-Send 'Отменено.' | Out-Null } else { Tg-Send 'Нечего отменять.' | Out-Null } }
    'dlglist' {
      $al=@(Get-Allowlist)
      if(!$al.Count){ Tg-Send 'Список авто-закрываемых окон пуст.' | Out-Null }
      else { $txt=(0..($al.Count-1) | ForEach-Object { "$($_+1)) заголовок ~ «$($al[$_].titleRegex)», программа «$($al[$_].processName)», кнопка «$($al[$_].button)»" }) -join "`n"; Tg-Send "Авто-закрываемые окна:`n$txt`n`nУбрать: «убери из списка N»." | Out-Null }
    }
    'dlgremove' {
      $al=@(Get-Allowlist); $idx=$c.idx-1
      if($idx -lt 0 -or $idx -ge $al.Count){ Tg-Send "Нет пункта $($c.idx) в списке (всего $($al.Count))." | Out-Null }
      else { $nm=$al[$idx].titleRegex; $new=@(); for($k=0;$k -lt $al.Count;$k++){ if($k -ne $idx){ $new+=$al[$k] } }; Save-Allowlist $new; Tg-Send "Убрал пункт $($c.idx): «$nm»." | Out-Null }
    }
    'allowdlg' {
      if(!($script:Blk -and $script:Blk.key)){ Tg-Send 'Сейчас нет активного блокирующего окна.' | Out-Null }
      else {
        $info=$script:Blk.info
        if(Test-ForbiddenWindow $info){ Tg-Send 'Это системное окно (UAC/учётные данные) — в список не добавляю и не нажимаю.' | Out-Null }
        else {
          $btn= if($c.button){ @($info.buttons | Where-Object { Test-ButtonMatch $_ $c.button }) | Select-Object -First 1 } else { Select-SafeButton $info.buttons $Cfg.SafeBtnRx }
          if(!$btn){ Tg-Send "Не вижу такой безопасной кнопки. Доступные: $(($info.buttons) -join ', '). Напиши «добавь в список <кнопка>» с точным названием." | Out-Null }
          else {
            $entry=[ordered]@{ titleRegex=('^'+[regex]::Escape($info.title)+'$'); processName=('^'+[regex]::Escape($info.proc)+'$'); button=$btn }
            Save-Allowlist (@(Get-Allowlist)+$entry)
            Tg-Send "Добавил в список: окно «$($info.title)» [$($info.proc)], кнопка «$btn». Нажимаю сейчас…" | Out-Null
            if(Click-DialogButton $info $btn){ Reset-Block "✅ Нажал «$btn» — окно закрыто, продолжаю работу." } else { Tg-Send "Не удалось нажать «$btn» в этом окне." | Out-Null }
          }
        }
      }
    }
    'clickdlg' {
      if(!($script:Blk -and $script:Blk.key)){ Tg-Send 'Сейчас нет активного блокирующего окна.' | Out-Null }
      else {
        $info=$script:Blk.info
        if(Test-ForbiddenWindow $info){ Tg-Send 'Это системное окно (UAC/учётные данные) — не нажимаю.' | Out-Null }
        elseif(Click-DialogButton $info $c.button){ Reset-Block "✅ Нажал «$($c.button)» — окно закрыто, продолжаю работу." }
        else { Tg-Send "Не нашёл кнопку «$($c.button)» (нужно точное название). Доступные: $(($info.buttons) -join ', ')" | Out-Null }
      }
    }
    { $_ -in 'gemwrite','agwrite' } { if($Source -ne 'tg'){ Tg-Send 'Эта кнопка работает только из Telegram.' | Out-Null; return }
                Start-AwaitText -Target $(if($c.k -eq 'agwrite'){'ag'}else{'gemini'}) -Direct }
    'write'   { if($Source -ne 'tg'){ Tg-Send '«напиши» работает только из Telegram.' | Out-Null; return }
                if($c.arg){ [void](Ask-WhereToSend -Text $c.arg -Kind 'where') } else { Start-AwaitText } }
    'fwdans'  { if($Source -ne 'tg'){ Tg-Send 'Эта команда работает только из Telegram (нужно подтверждение кнопкой).' | Out-Null; return }
                $script:Queue.Enqueue(@{ k='fwdans-prep'; src=$Source }); Tg-Send $(if($script:Busy){'🕐 Возьму последний ответ Gemini после текущего шага и покажу, что уйдёт.'}else{'🕐 Беру последний ответ Gemini…'}) | Out-Null }
    'fwdrep'  { if($Source -ne 'tg'){ Tg-Send 'Эта команда работает только из Telegram (нужно подтверждение кнопкой).' | Out-Null; return }
                Start-ReportResendConfirm }
    'asknocode' { if($Source -ne 'pc'){ Tg-Send 'Не понял команду. Напиши «помощь» — пришлю список того, что я умею.' | Out-Null; return }
                  $fp=Get-FullAnswerPath $c.arg
                  if(Test-Path -LiteralPath $fp){ [void](Send-NoCodePrompt -Label $c.arg -Model $script:LastModel -FullPath $fp -File $c.arg); Log "Вопрос про ответ на $($c.arg) отправлен в Telegram" } else { Log "Нет сохранённого ответа для $($c.arg) ($fp)" } }
    'unknown' {
      $tt=([string]$Text).Trim()
      if($Source -eq 'tg' -and $Cfg.TgOfferForward -and $tt.Length -ge 2 -and -not $tt.StartsWith('/')){ [void](Ask-WhereToSend -Text $tt -Kind 'offer') }
      else { Tg-Send 'Не понял команду. Напиши «помощь» — пришлю список того, что я умею.' | Out-Null }
    }
    default   {
      if($Cfg.TgConfirmAg -and $Source -eq 'tg' -and ($c.k -in @('ag','gemini')) -and -not $c.confirmed){
        $script:PendingConfirm=@{ c=$c; time=Get-Date }
        Tg-Send "Отправить в $(if($c.k -eq 'ag'){'Antigravity'}else{'Gemini'}): «$(Format-Short $c.arg 200)»? Ответь «да» (5 минут) или «нет»." | Out-Null
        return
      }
      if($c.k -eq 'relay' -and $c.whole -and $Source -eq 'tg'){ $script:Queue.Enqueue(@{ k='fwdans-prep'; src=$Source }); Tg-Send '🕐 «передай весь ответ» = «перешли ответ в Antigravity»: возьму последний ответ Gemini и покажу, что уйдёт.' | Out-Null; return }
      $script:Queue.Enqueue($c); if($script:Busy){ Tg-Send 'Принял, выполню после текущего шага.' | Out-Null } else { Tg-Send 'Принял, выполняю.' | Out-Null }
    }
  }
}
function Run-Action($c){
  $prev=$script:LogReplies; if($c.src -eq 'pc'){ $script:LogReplies=$true }
  try{ Run-ActionCore $c } finally { $script:LogReplies=$prev }
}
# Кнопки панели: текст приходит как b64:<base64 UTF-8> (многострочный текст в одной строке commands.txt).
function ConvertFrom-PcArg([string]$A){ $a=$A.Trim(); if($a -match '^b64:(.*)$'){ if(-not $matches[1]){ return '' }; try{ return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[1])) }catch{ return '' } }; $a }
# Пункт 39: после кнопок «… с портом» — не ждать CdpRecheckSec, а сразу попробовать CDP снова.
function Reset-CdpRecheck{ $script:CdpDownUntil=$null; $script:AgCdpDownUntil=$null }
function Invoke-PcButton([string]$K,[string]$Arg){
  $k=$K.ToLower()
  if($script:Paused -and $k -in 'gemask','agask','togemini','toag','answer'){ Log "Стоп: кнопка панели $k не выполнена — нажмите «Старт»"; return }
  switch($k){
    'cdpcheck' { Reset-CdpRecheck; Log '🌐 Порты отладки: проверю CDP Gemini и Antigravity при следующем обращении (кнопка панели)' }
    'gemask'   { $t=ConvertFrom-PcArg $Arg; if(-not $t.Trim()){ Log 'Gemini: пустой текст — ничего не отправлено'; return }; $script:Queue.Enqueue(@{ k='gemask'; text=$t.Trim(); src='pc' }); Log "✨ Gemini: текст принят ($($t.Length) симв.), отправлю$(if($script:Busy){' после текущего шага'}) и покажу ответ здесь" }
    'agask'    { $t=ConvertFrom-PcArg $Arg; if(-not $t.Trim()){ Log 'Antigravity: пустой текст — ничего не отправлено'; return }; $script:Queue.Enqueue(@{ k='agask'; text=$t.Trim(); src='pc' }); Log "🛠 Antigravity: текст принят ($($t.Length) симв.), отправлю$(if($script:Busy){' после текущего шага'}); ответом будет новый отчёт агента" }
    'togemini' { $f=@(Get-Files) | Select-Object -Last 1; if(-not $f){ Log 'В Downloads нет отчётов агента — пересылать нечего.'; return }; $script:Queue.Enqueue(@{ k='resendfile'; name=$f.Name; src='pc' }) }
    'toag'     { $script:Queue.Enqueue(@{ k='fwdans-pc'; src='pc' }); Log '🕐 Беру последний ответ Gemini целиком для Antigravity…' }
    'answer'   { $script:Queue.Enqueue(@{ k='lastanswer'; src='pc' }) }
    default    { Log "Неизвестная кнопка панели: $K" }
  }
}
function Run-ActionCore($c){
  switch($c.k){
    'limits' { Tg-Send ('📊 Лимиты, '+(Check-Quotas)) | Out-Null }
    'gemini' {
      Assert-NotPaused 'сообщение в Gemini'
      Assert-Quota -Gemini -Ag
      $m=Assert-Argon 'Сообщение из Telegram в Gemini НЕ отправлено.'
      $ctx=Gem-Send $c.arg (Get-Marker $c.arg)
      Tg-Send "📤 Сообщение отправлено в Gemini (модель: $m)" | Out-Null
      $script:State='жду ответ Gemini на сообщение из Telegram'
      [void](Wait-GemAnswerStoppable $ctx)
      $m2=Get-ModelNow
      if(-not (Is-Argon $m2)){ Enter-LimitStop $m2 "Ответ на сообщение пришёл от модели «$m2» и НЕ передан."; return }
      Check-OurPrompt ([int]$ctx.pBefore)
      $code=Gem-CopyCode
      if($code){ $hh=Check-Fresh $code; Ag-Send -Text $code -Label 'ответ на сообщение из Telegram'; $script:TurnSide='antigravity'; Register-BlockRelayed $code $hh; Add-RelayHash $script:St $hh $Cfg.HashKeep; Save-State; $msg="✅ Ответ на сообщение дала модель $m2; блок Markdown ($($code.Length) симв., хэш $hh, первая строка «$(Get-FirstLine $code)») передан в Antigravity"; Log $msg; Tg-Send $msg | Out-Null }
      else { $a=Gem-CopyWhole; Tg-Send "Ответ Gemini (модель $m2; блока Markdown нет, в Antigravity не передавал):`n`n$a" | Out-Null }
    }
    'ag' { Assert-NotPaused 'текст в Antigravity'; Assert-Quota -Ag; Ag-Send -Text $c.arg -Label 'текст из Telegram'; Log 'Текст отправлен в Antigravity'; Tg-Send 'Отправил в Antigravity.' | Out-Null }
    'relay' {
      Assert-NotPaused 'передачу ответа в Antigravity'
      Assert-Quota -Gemini -Ag
      $m=Assert-Argon 'Ответ по команде «передай ответ» НЕ передан.'
      if($c.whole){ $a=Gem-CopyWhole } else { $a=Gem-CopyCode; if(!$a){ Tg-Send 'В последнем ответе Gemini нет блока Markdown. Напиши «передай весь ответ», если нужно передать его целиком.' | Out-Null; return } }
      if(!$a){ throw 'не нашёл ответ Gemini' }
      $hh=Check-Fresh $a
      Ag-Send -Text $a -Label 'ответ Gemini (по команде)'; $script:TurnSide='antigravity'; Register-BlockRelayed $a $hh; Add-RelayHash $script:St $hh $Cfg.HashKeep; Save-State
      $msg="✅ По команде передал в Antigravity $(if($c.whole){'весь ответ'}else{'блок Markdown'}) (модель $m, $($a.Length) симв., хэш $hh, первая строка «$(Get-FirstLine $a)»)"; Log $msg; Tg-Send $msg | Out-Null
    }
    'force' {
      Assert-NotPaused 'передачу ответа в Antigravity'
      Assert-Quota -Gemini -Ag
      $m=Assert-Argon 'Ответ («передай всё равно») НЕ передан.'
      $a=Gem-CopyCode; if(!$a){ Tg-Send 'В последнем ответе Gemini нет блока Markdown — передавать нечего.' | Out-Null; return }
      $hh=Get-Hash8 $a; $sf=Get-StaleFile
      if($sf){ Relay-ToAg $sf.Name $a $hh $m ' (принудительно, по команде «передай всё равно»)' -NoGate; $script:StaleNotified.Remove($sf.Name) }
      else { Ag-Send -Text $a -Label 'ответ Gemini (принудительно)'; $script:TurnSide='antigravity'; Register-BlockRelayed $a $hh; Add-RelayHash $script:St $hh $Cfg.HashKeep; Save-State; $msg="✅ Принудительно передал в Antigravity блок Markdown (хэш $hh, «$(Get-FirstLine $a)»)"; Log $msg; Tg-Send $msg | Out-Null }
    }
    'resendstale' {
      $sf=Get-StaleFile
      if(!$sf){ Tg-Send 'Нет файла в состоянии «ждёт решения».' | Out-Null; return }
      Set-Stage $sf.Name 'resend'; $script:StaleNotified.Remove($sf.Name); Tg-Send "🔁 $($sf.Name) будет отправлен в Gemini заново." | Out-Null
    }
    'lastanswer' { $a=Gem-CopyWhole; if(!$a){ throw 'не нашёл ответ Gemini' }; $p=Save-FullAnswer ('last_'+(Get-Date).ToString('yyyyMMdd_HHmmss')+'.md') $a; if($p){ Send-AnswerCopy $p 'последнее сообщение' } else { Tg-Send "Последний ответ Gemini:`n`n$a" | Out-Null } }
    { $_ -in 'fwdtext','fwdans-prep','resendfile','gemask','agask','fwdans-pc' } { Invoke-ChatAction $c }
    'accept' { if(Try-AcceptAll){ Tg-Send 'Нажал «Accept all».' | Out-Null } else { Tg-Send 'Кнопки «Accept all» в Antigravity сейчас нет.' | Out-Null } }
  }
}

# ---------- Accept all и очередь Antigravity ----------
function Find-AcceptAll($h){ @(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.AcceptAllName | Where-Object { -not (Uia-IsOffscreen $_) }) | Select-Object -First 1 }
# git без исключений на stderr (PS 5.1 превращает предупреждения git в ошибки при ErrorActionPreference=Stop).
function Invoke-Git([string[]]$GitArgs){
  $eap=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try{ $out=& git @GitArgs 2>&1 | ForEach-Object { "$_" }; $code=$LASTEXITCODE } finally { $ErrorActionPreference=$eap }
  if($code -ne 0){ throw "git $($GitArgs -join ' '): код $code $(($out | Select-Object -First 3) -join ' ')" }
  $out
}
# Git-чекпоинт перед Accept all: коммит всех изменений в GitCheckpointRepo. $true — успешно, нечего коммитить или не настроено.
function Invoke-GitCheckpoint{
  $repo=[string]$Cfg.GitCheckpointRepo; if(-not $repo){ return $true }
  try{
    if(-not (Test-Path -LiteralPath (Join-Path $repo '.git'))){ throw "$repo — не git-репозиторий" }
    $st=@(Invoke-Git @('-C',$repo,'status','--porcelain'))
    if(-not ($st -join '').Trim()){ return $true }
    [void](Invoke-Git @('-C',$repo,'add','-A'))
    $id=@(); $em=''; try{ $em=(@(Invoke-Git @('-C',$repo,'config','user.email')) -join '').Trim() }catch{}
    if(-not $em){ $id=@('-c','user.name=GGskript','-c','user.email=ggskript@localhost') }
    [void](Invoke-Git (@('-C',$repo)+$id+@('commit','-q','-m',("GGskript checkpoint before Accept all {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)))))
    Log "Git-чекпоинт перед Accept all: $repo ($($st.Count) изм.)"; $true
  }catch{ Log "Git-чекпоинт не удался: $($_.Exception.Message)"; $false }
}
function Try-AcceptAll([switch]$Report){
  if($script:Paused){ return $false }
  $h=Ag-GetWindow; if(!$h){ return $false }
  # пункт 46: в Antigravity «Accept all» — <span> с onClick, не Button: UIA его не видит. С CDP — только DOM (span), агент не должен работать.
  if($Cfg.AgTransport -eq 'cdp'){
    $d=$null; try{ $d=AgCdp-AcceptAll -Dry }catch{ Log "Accept all через CDP: $($_.Exception.Message)" }
    if($d){
      if(-not $d.found -or $d.busy){ return $false }
      if(-not (Invoke-GitCheckpoint) -and $Cfg.GitCheckpointRequired){ Tg-Send '⛔ Accept all НЕ нажат: не удался git-чекпоинт (GitCheckpointRequired=true).' -DedupMin 30 | Out-Null; return $false }
      if(Test-StopNow){ return $false }
      $r=$null; try{ $r=AgCdp-AcceptAll }catch{ Log "Accept all через CDP: $($_.Exception.Message)" }
      if($r -and $r.ok){ $nf=if($null -ne $r.files){ [string]$r.files } else { '?' }; Log "✅ Accept all нажат ($nf files) (CDP, без фокуса)"; if($Report){ Tg-Send "✅ Accept all нажат ($nf files)" | Out-Null }; return $true }
      return $false
    }
  }
  if(!(Find-AcceptAll $h)){ return $false }
  if(-not (Invoke-GitCheckpoint) -and $Cfg.GitCheckpointRequired){ Tg-Send '⛔ Accept all НЕ нажат: не удался git-чекпоинт (GitCheckpointRequired=true).' -DedupMin 30 | Out-Null; return $false }
  $ok=$false; $how=''
  if(-not $ok -and $Cfg.AgInvokeNoFocus){ try{ $el=Find-AcceptAll $h; if($el -and (Uia-Invoke $el)){ $ok=$true; $how=' (UIA Invoke, без фокуса)' } }catch{} }
  if(-not $ok){ try{ Invoke-WithFocus $h { $el=Find-AcceptAll $h; if($el -and (Uia-ClickEl $el -PreferInvoke)){ $script:AccOk=$true } else { $script:AccOk=$false } }; $ok=[bool]$script:AccOk }catch{ return $false } }
  if($ok){ Log "✅ Accept all нажат (? files)$how"; if($Report){ Tg-Send '✅ Accept all нажат' | Out-Null } }
  $ok
}
function Find-QueuedItems($h){
  foreach($b in @(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.AgSendNowName | Where-Object { -not (Uia-IsOffscreen $_) })){
    $txt=''; $e=$b; $br=Uia-Rect $b
    for($i=0;$i -lt 4 -and -not $txt;$i++){
      $e=Uia-Parent $e; if(!$e){ break }
      $t=@(Uia-FindAll -Root $e -ControlType 'Text' | Where-Object { $r=Uia-Rect $_; $nm=Uia-Name $_
        $nm.Length -gt 5 -and $nm -notmatch '^(Queued Messages|Sends after|\d+ Files With Changes)' -and $r -and $br -and $r.L -lt $br.L -and $r.T -le $br.B -and ($r.T+[Math]::Min($r.B-$r.T,40)) -ge $br.T }) | Select-Object -First 1
      if($t){ $txt=Uia-Name $t }
    }
    @{ btn=$b; key=(Get-NormKey $txt 80) }
  }
}
function Check-AgQueue{
  $h=Ag-GetWindow; if(!$h){ return }
  $items=@(Find-QueuedItems $h)
  foreach($k in @($script:QueueSeen.Keys)){ if(-not ($items | Where-Object { $_.key -eq $k })){ $script:QueueSeen.Remove($k); $script:QueueTries.Remove($k) } }
  foreach($it in $items){
    $k=$it.key; if(!$script:QueueSeen.ContainsKey($k)){ $script:QueueSeen[$k]=Get-Date; Log "Antigravity: в очереди сообщение «$(Get-NormKey $k 50)…»" }
    $age=((Get-Date)-$script:QueueSeen[$k]).TotalSeconds
    if($age -lt $Cfg.AgQueueWaitSec){ continue }
    $tries=[int]$script:QueueTries[$k]; if($tries -ge $Cfg.AgQueueMaxTries){ continue }
    $script:QueueTries[$k]=$tries+1
    $ours= $script:AgPending -and $k.StartsWith($script:AgPending.key)
    $label= if($ours -and $script:AgPending.label){ $script:AgPending.label } else { "«$(Get-NormKey $k 50)…»" }
    $still=$true; $done=$false
    if($Cfg.AgInvokeNoFocus){ try{   # пункт 27B: «отправить сейчас» через UIA Invoke без фокуса
      $b=(@(Find-QueuedItems $h) | Where-Object { $_.key -eq $k } | Select-Object -First 1).btn
      if($b -and (Uia-Name $b) -match $Cfg.AgSendNowName -and (Uia-Invoke $b)){ Start-Sleep 3; $still=[bool](@(Find-QueuedItems $h) | Where-Object { $_.key -eq $k }); $done=-not $still }
    }catch{} }
    if(-not $done){ try{ Invoke-WithFocus $h {
      $b=(@(Find-QueuedItems $h) | Where-Object { $_.key -eq $k } | Select-Object -First 1).btn
      if($b -and (Uia-Name $b) -match $Cfg.AgSendNowName){ [void](Uia-ClickEl $b -PreferInvoke); Start-Sleep 3 }
      $script:QStill=[bool](@(Find-QueuedItems $h) | Where-Object { $_.key -eq $k })
    }; $still=$script:QStill }catch{ continue } }
    if(-not $still){
      $msg="⏩ Antigravity завис на предыдущем задании (сообщение $([int]$age) сек в очереди), нажал «отправить сейчас» для $label — сообщение ушло агенту"; Log $msg; Tg-Send $msg | Out-Null
      $script:QueueSeen.Remove($k); $script:QueueTries.Remove($k)
    } else {
      $msg="❌ Нажал «отправить сейчас» для $label (попытка $($tries+1) из $($Cfg.AgQueueMaxTries)), но сообщение всё ещё в очереди Antigravity"
      if($tries+1 -ge $Cfg.AgQueueMaxTries){ $msg+='. Больше не пробую — нужна ручная проверка.' }
      Log $msg; Tg-Send $msg | Out-Null
    }
  }
}

# ---------- Pump / Nap ----------
function Pump{ Poll-Tg; Sweep-TgPrompts; try{ Check-Shutdown }catch{ Log "Выключение: $($_.Exception.Message)" }; Read-CmdFile; Check-LocalControl; Write-Status; if($script:StopReq){ throw [GG.RelayStopException]::new() }
  if($script:Paused -and $script:AbortOnStop){ $script:AbortOnStop=$false; throw [GG.RelayPausedException]::new('СТОП — ожидание ответа Gemini прервано (после «Старт» протокол проверит чат)') }
  # пункт 38: «Стоп» посреди любого рабочего шага (вставка, копирование, прикрепление, ожидание) — прерываем его сразу
  if($script:Paused -and $script:Busy){ throw [GG.RelayPausedException]::new('СТОП — текущее действие прервано') }
  if($script:Paused){ return }   # на стопе: никаких фоновых действий (автоподтверждение, Accept all, ответ Antigravity)
  Invoke-AuxDuringWait; Invoke-AutoAllowTick; Invoke-AutoAcceptTick; try{ Check-AgWatch }catch{ if((Get-ErrorKind $_) -eq 'paused'){ throw }; Log "Ответ Antigravity: $($_.Exception.Message)" } }
# Ожидание ответа Gemini, которое «Стоп» может прервать (пункт 25B). Внутри — только чтение окна Gemini.
function Wait-GemAnswerStoppable($ctx){ $script:AbortOnStop=$true; try{ Gem-WaitAnswer $ctx } finally { $script:AbortOnStop=$false } }
# AcceptAllDuringWait: во время долгого ожидания ответа Gemini нажимать Accept all (и смотреть очередь Antigravity).
# Не запускается: на паузе, вне рабочего шага, внутри операции с фокусом/буфером, повторно изнутри себя.
$script:LastAuxDuringWait=Get-Date; $script:InAux=$false
function Invoke-AuxDuringWait{
  if(-not $Cfg.AcceptAllDuringWait -or -not $script:Busy -or $script:Paused -or $script:InAux -or [int]$script:FocusDepth -gt 0){ return }
  if($Cfg.AcceptAllEverySec -le 0 -or ((Get-Date)-$script:LastAuxDuringWait).TotalSeconds -lt $Cfg.AcceptAllEverySec){ return }
  $script:LastAuxDuringWait=Get-Date; $script:InAux=$true
  try{ try{ [void](Try-AcceptAll -Report) }catch{ Log "Accept all (во время ожидания): $($_.Exception.Message)" } } finally { $script:InAux=$false }
}
# ---------- Автоподтверждение запросов разрешения Antigravity ----------
$script:LastAutoAllow=Get-Date; $script:InAutoAllow=$false; $script:AutoAllowWarn=@{ key=''; time=[datetime]::MinValue }
function Set-AutoAllow([bool]$On,[string]$Source='pc'){
  $Cfg.AutoAllowPrompts=$On
  try{ Save-SettingValue $Cfg.SettingsFile 'AutoAllowPrompts' $On }catch{ Log "Автоподтверждение: не удалось сохранить в relay_settings.json ($($_.Exception.Message))" }
  Log "Автоподтверждение запросов Antigravity: $(if($On){'ВКЛ'}else{'выкл'}) ($Source)"
  Tg-Send "Автоподтверждение запросов Antigravity: $(if($On){'ВКЛ — отвечаю «Yes, allow this time» + Submit (никогда «always»/«No»)'}else{'выкл'})." | Out-Null
  try{ Write-Status -Force }catch{}
}
function Try-AutoAllow{
  if(-not $Cfg.AutoAllowPrompts -or (Test-StopNow)){ return $false }
  $r=$null
  if($Cfg.AgTransport -eq 'cdp'){ try{ $r=AgCdp-AllowPrompt; if($r -and $r.ok){ $r.how='CDP, без фокуса' } }catch{ $r=$null } }
  if(-not ($r -and $r.ok)){
    $h=Ag-GetWindow
    if($h){ try{ $u=AgUia-AllowPrompt $h; if($u.ok){ $u.how='UIA, без фокуса'; $r=$u } elseif($u.found -or -not $r){ $r=$u } }catch{ Log "Автоподтверждение (UIA): $($_.Exception.Message)" } }
  }
  if($r -and $r.ok){ Log "Автоподтверждение: «$(Format-Short ([string]$r.opt) 40)» + Submit ($($r.how))$(if($r.title){" — «$(Format-Short ([string]$r.title) 80)»"})"; return $true }
  if($r -and $r.found){
    $k=[string]$r.why
    if($k -ne $script:AutoAllowWarn.key -or ((Get-Date)-$script:AutoAllowWarn.time).TotalMinutes -ge 10){ $script:AutoAllowWarn=@{ key=$k; time=Get-Date }; Log "Автоподтверждение: запрос виден, но не подтвердил — $k" }
  }
  $false
}
# Из Pump: и в простое, и во время ожидания Gemini. Не внутри операций с фокусом/буфером, не к зависшему окну, без повторного входа.
function Invoke-AutoAllowTick{
  if(Test-StopNow){ return }
  if(-not $Cfg.AutoAllowPrompts -or $script:InAutoAllow -or [int]$script:FocusDepth -gt 0){ return }
  if($script:AgBlock -and $script:AgBlock.kind -in @('hung','nowindow')){ return }
  if(((Get-Date)-$script:LastAutoAllow).TotalSeconds -lt [Math]::Max(1,[double]$Cfg.AutoAllowEverySec)){ return }
  $script:LastAutoAllow=Get-Date; $script:InAutoAllow=$true
  try{ try{ [void](Try-AutoAllow) }catch{ Log "Автоподтверждение: $($_.Exception.Message)" } } finally { $script:InAutoAllow=$false }
}
# пункт 46: автопринятие «Accept all» из Pump (и во время ожидания Gemini) — только через CDP (без фокуса и мыши), только когда агент не работает.
$script:LastAutoAccept=Get-Date; $script:InAutoAccept=$false
function Invoke-AutoAcceptTick{
  if(Test-StopNow){ return }
  if(-not $Cfg.AutoAcceptAll -or $Cfg.AgTransport -ne 'cdp' -or $script:InAutoAccept -or [int]$script:FocusDepth -gt 0){ return }
  if($script:AgBlock -and $script:AgBlock.kind -in @('hung','nowindow')){ return }
  if($Cfg.AcceptAllEverySec -le 0 -or ((Get-Date)-$script:LastAutoAccept).TotalSeconds -lt $Cfg.AcceptAllEverySec){ return }
  $script:LastAutoAccept=Get-Date; $script:LastAccept=Get-Date; $script:InAutoAccept=$true
  try{ try{ [void](Try-AcceptAll -Report) }catch{ Log "Accept all: $($_.Exception.Message)" } } finally { $script:InAutoAccept=$false }
}
function Set-AutoAccept([bool]$On,[string]$Source='pc'){
  $Cfg.AutoAcceptAll=$On
  try{ Save-SettingValue $Cfg.SettingsFile 'AutoAcceptAll' $On }catch{ Log "Автопринятие: не удалось сохранить в relay_settings.json ($($_.Exception.Message))" }
  Log "Автопринятие «Accept all»: $(if($On){'ВКЛ'}else{'выкл'}) ($Source)"
  Tg-Send "Автопринятие «Accept all»: $(if($On){'ВКЛ — жму, когда агент закончил (никогда «Reject all»)'}else{'выкл'})." | Out-Null
  try{ Write-Status -Force }catch{}
}
function Nap($sec){ $end=(Get-Date).AddSeconds($sec); while((Get-Date) -lt $end){ Pump; $r=($end-(Get-Date)).TotalMilliseconds; if($r -gt 0){ Start-Sleep -Milliseconds ([int][Math]::Min(1000,$r)) } } }

# ---------- Пауза ----------
function Update-Title{ try{ $Host.UI.RawUI.WindowTitle="GGskript v2$(if($script:Paused){' — СТОП'}) (P — стоп, S — старт, Ctrl+C — выключить)" }catch{} }
function Set-Pause($on,$src){
  try{ if($on){ New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null } else { Remove-Item -LiteralPath $Cfg.PauseFile -EA 0 } }catch{}
  if($script:Paused -eq $on){ return }
  $script:Paused=$on
  if($on){ $script:PausedSince=Get-Date } elseif(-not $script:PausedSince -or ((Get-Date)-$script:PausedSince).TotalMinutes -ge [double]$Cfg.StartupTriagePauseMin){ $script:TriageNeeded=$true }
  # пункт 25C: «стоп» = процесс жив и слушает Telegram, но ничего не отправляет, лимиты/модель не проверяет и окна не трогает
  if($on){ $script:MirrorSeen=$null; $msg="⏸ GGskript: Остановлен ($src) — ничего не делаю.$(if($script:Busy -or $script:AbortOnStop){' Текущее действие прервал.'})`nМышь, клавиатуру, буфер обмена и окна не трогаю; автоподтверждение, Accept all, наблюдатель, лимиты, модель, закрытие окон и звуки выключены. Слушаю только Telegram и панель.`nПродолжить — «Старт» (сначала проверю окна, лимиты, модель и чаты). Выключить скрипт совсем — «выключи скрипт»." }
  else { $msg="▶️ GGskript: старт ($src) — выполняю протокол запуска"; $script:NeedStart=$true; $script:LastStartTry=(Get-Date).AddYears(-1); $script:LastStartReport=''; $script:StopAnnounced=$true }
  Log $msg; Tg-Send $msg | Out-Null; Update-Title
}
function Check-LocalControl{
  try{ if(-not [Console]::IsInputRedirected){ while([Console]::KeyAvailable){ $k=[Console]::ReadKey($true); $c=[string]$k.KeyChar
    if($c -match '^[pPзЗ]$'){ Set-Pause $true 'клавиша P' } elseif($c -match '^[sSыЫ]$'){ Set-Pause $false 'клавиша S' } } } }catch{}
  $f=Test-Path -LiteralPath $Cfg.PauseFile
  if($f -ne $script:Paused){ Set-Pause $f $(if($f){'файл PAUSE'}else{'ярлык GGskript'}) }
}
# ---------- commands.txt ----------
function Read-CmdFile{
  if(-not (Test-Path -LiteralPath $Cfg.CmdFile)){ return }
  $tmp="$($Cfg.CmdFile).proc"
  try{ Move-Item -LiteralPath $Cfg.CmdFile -Destination $tmp -Force }catch{ return }
  $lines=@(); try{ $lines=@(ConvertFrom-CommandBytes ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($tmp)))) }catch{ Log "Команды с ПК: не удалось прочитать ($($_.Exception.Message))" }
  Remove-Item -LiteralPath $tmp -EA 0
  foreach($t in $lines){
    Log "Команда с ПК: $(Format-Short $t $Cfg.LogTextMax)"
    $script:LogReplies=$true
    try{ Handle-Command $t 'pc' }catch{ Log "Команда с ПК: ошибка $($_.Exception.Message)" }
    finally{ $script:LogReplies=$false }
  }
}
# ---------- Статус для GUI ----------
function Write-Status([switch]$Force){
  if(-not $Force -and ((Get-Date)-$script:LastStatusWrite).TotalMilliseconds -lt 1500){ return }
  $script:LastStatusWrite=Get-Date
  try{
    $nf=Next-FileName; $q=$script:Q
    $kind= if($script:Stopped){ 'stopped' } elseif($script:Paused){ 'paused' } elseif($script:LimitStop -or (Quota-Blocked)){ 'limit' } elseif($script:OperatorWait){ 'operator' } else { 'running' }
    $limSide= if($script:QStopA -and -not ($script:LimitStop -or $script:QStopG)){ 'antigravity' } elseif($script:QStopA){ 'both' } elseif($kind -eq 'limit'){ 'gemini' } else { '' }
    $o=[ordered]@{
      ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); pid=$PID; version=2
      state=[string]$script:State; kind=$kind; paused=[bool]$script:Paused
      limitStop=[bool]$script:LimitStop; limitModel=[string]$script:LimitModel; model=[string]$script:LastModel
      quotaBlocked=[string](Quota-Blocked); nextFile=[string]$nf
      project=[string]$(if($nf){ ProjOf $nf } elseif($script:LastDone){ ProjOf $script:LastDone } else { '' })
      lastDone=[string]$script:LastDone
      agBlock= if($script:AgBlock){ "$($script:AgBlock.kind) с $($script:AgBlock.since.ToString('HH:mm'))" } else { '' }
      resumeAt= if($script:AutoPlan){ Format-PlanTime $script:AutoPlan.at } else { '' }; resumeWhy= if($script:AutoPlan){ [string]$script:AutoPlan.why } else { '' }
      lastAction= if($script:LastAction){ $script:LastAction.ToString('HH:mm:ss') } else { '' }
      pending=@($script:St.files.Keys | Where-Object { (Get-Stage $_) -in @('sent','answered','resend','stale','operator') } | ForEach-Object { "$_ ($(Get-StageRu (Get-Stage $_)))" })
      transport="Gemini=$($Cfg.GeminiTransport), AG=$($Cfg.AgTransport)"; autoAllow=[bool]$Cfg.AutoAllowPrompts; autoAccept=[bool]$Cfg.AutoAcceptAll
      quotaTime= if($q){ [string]$q.time } else { '' }
      gwebCur= if($q -and $q.gweb){ $q.gweb.cur } else { $null }; gwebWk= if($q -and $q.gweb){ $q.gweb.wk } else { $null }
      gwebCurReset= if($q -and $q.gweb){ [string]$q.gweb.curReset } else { '' }; gwebWkReset= if($q -and $q.gweb){ [string]$q.gweb.wkReset } else { '' }
      agH5= if($q -and $q.ag -and $q.ag.h5){ $q.ag.h5.rem } else { $null }; agH5Reset= if($q -and $q.ag -and $q.ag.h5){ [string]$q.ag.h5.reset } else { '' }
      agWk= if($q -and $q.ag -and $q.ag.wk){ $q.ag.wk.rem } else { $null }; agWkReset= if($q -and $q.ag -and $q.ag.wk){ [string]$q.ag.wk.reset } else { '' }
      turn=[string](Get-RelayTurn -Kind $kind -Stages @($script:St.files.Keys | ForEach-Object { Get-Stage $_ }) -NextFile ([string]$nf) -LastSide ([string]$script:TurnSide) -AgWatch ([bool]$script:AgWatch) -Decision $(try{ [string](Get-TurnDecisionNow).turn }catch{ '' }) -LimitSide $limSide)
      limitSide=$limSide
    }
    Write-AtomicText -Path $Cfg.StatusFile -Text ($o | ConvertTo-Json -Depth 5) -NoBackup
  }catch{}
}

# ---------- Протокол запуска (пункт 25A) ----------
# Выполняется при запуске и при каждом «Старт» после стопа. Шаги строго по порядку; каждый шаг — строка в отчёте.
# Нет окна / Gemini генерирует / Antigravity не отвечает -> дальше не иду, повтор через StartRetrySec (отчёт уходит в Telegram только если изменился).
# Лимит исчерпан / модель не та -> дальше не иду, жду сброса (автовозобновление).
function Send-StartReport([string[]]$Rep,[switch]$DryRun){
  $txt="🚀 GGskript: процедура запуска (протокол проверки)`n$($Rep -join "`n")"
  if($txt -eq $script:LastStartReport){ Log 'Протокол запуска: без изменений (в Telegram повторно не отправляю)'; return }
  $script:LastStartReport=$txt
  Log "Протокол запуска$(if($DryRun){' (пробный прогон, ничего не меняю)'}):"; $Rep | ForEach-Object { Log "  $_" }
  if(-not $DryRun){ Tg-Send $txt -Markup (Get-TgReplyMarkup) | Out-Null }
}
function Format-Langs($l){ $a=@($l | ForEach-Object { if([string]$_){ "'$_'" } else { '(без подписи)' } }); if($a.Count){ $a -join ', ' } else { 'нет' } }
function Start-Procedure([switch]$DryRun){
  $rep=@()
  # 1. Окна
  $gi=$false; try{ $gi=Gem-IsReady }catch{}
  $ah=Ag-GetWindow; $ai=$false; if($ah){ try{ $ai=[bool](AgUia-FindInput $ah) }catch{} }
  $rep+="1) Окна: Gemini $(if($gi){'есть (поле ввода найдено)'}else{'НЕТ или нет поля ввода'}), Antigravity $(if($ah){'есть'}else{'НЕТ'}) (поле чата: $(if($ai){'есть'}elseif($Cfg.AgCoordFallback){'не найдено, будет клик по координатам'}else{'НЕ найдено — отправка в Antigravity будет отклоняться'}))"
  if(!$gi -or !$ah){
    $rep+="   ⛔ нет нужного окна — лимиты, модель и чаты НЕ проверяю; повторю через $($Cfg.StartRetrySec) сек"
    $rep+='2) Модель Gemini: не проверена (нет окна Gemini)'
    if($Cfg.StartupNewestOnly -and $script:TriageNeeded){
      # пункт 24: старые файлы пропускаются сразу (только учёт, окна не нужны); самый новый — когда будут окна
      $tr=Invoke-StartupTriage $null -DryRun:$DryRun -NoChat; $rep+='4) Файлы:'; $rep+=$tr.lines
    }
    $rep+='👉 Ход: ничей — жду окна Gemini и Antigravity, ничего не отправляю'
    Send-StartReport $rep -DryRun:$DryRun; return $false
  }
  # 2. Лимиты
  if($DryRun){ try{ $aq=Get-AgQuota; $rep+="2) Лимиты: Antigravity 5 ч осталось $($aq.h5.rem)%, неделя осталось $($aq.wk.rem)% (страницу лимитов Gemini в пробном прогоне не открываю)" }catch{ $rep+="2) Лимиты Antigravity: ошибка $($_.Exception.Message)" } }
  else{
    if(-not $script:Q -or ((Get-Date)-$script:LastQuota).TotalMinutes -ge 2){ try{ Check-Quotas | Out-Null }catch{ Log "Лимиты: $($_.Exception.Message)" }; $script:LastQuota=Get-Date }
    $rep+="2) Лимиты: $((Quota-Text) -replace "`n",'; ')"
  }
  $qb= if($DryRun){ '' } else { Quota-Blocked }
  if($qb -and $script:QStopG -and -not $script:QStopA -and $Cfg.MirrorRelay){
    # пункт 46: Gemini исчерпан, но дописанный блок Argon в Antigravity передам (наблюдатель)
    Update-AutoPlan -Quiet
    $rep+="   ⛔ исчерпан: $qb — в Gemini ничего не отправляю; готовый блок Argon (если не передан) передам в Antigravity"
    $rep+='👉 Ход: Antigravity, если в Gemini есть непереданный блок; иначе жду сброса лимита Gemini'
    Send-StartReport $rep -DryRun:$DryRun; return $true
  }
  if($qb -and $script:QStopA -and -not $script:QStopG){
    Update-AutoPlan -Quiet
    $rep+="   ⛔ исчерпан: $qb — в Antigravity ничего не вставляю; готовые отчёты в Gemini отправлять буду"
    $qb=''
  }
  if($qb){
    Update-AutoPlan -Quiet
    $rep+="   ⛔ исчерпан: $qb — ничего не отправляю$(if($script:AutoPlan -and $Cfg.AutoResume){"; проверю снова в $(Format-PlanTime $script:AutoPlan.at) и продолжу сам"})"
    $rep+='👉 Ход: ничей — жду сброса лимита («продолжай» — игнорировать лимит)'
    Send-StartReport $rep -DryRun:$DryRun; return $true
  }
  # 3. Модель и занятость
  $m=$null; try{ $m=Get-ModelNow }catch{}
  if(-not $m){ $rep+="3) Модель Gemini: не прочитана — повторю через $($Cfg.StartRetrySec) сек"; $rep+='👉 Ход: ничей — ничего не отправляю'; Send-StartReport $rep -DryRun:$DryRun; return $false }
  if(-not (Is-Argon $m)){
    if($Cfg.AutoSwitchModel -and -not $DryRun){
      $old=$m
      try{ $m=Switch-ToArgon; $rep+="3) Модель Gemini: была «$old» — переключил на «$m»" }
      catch{ $rep+="3) Модель Gemini: «$old» — НЕ $($Cfg.ModelMustContain), переключить не удалось ($($_.Exception.Message))"; Enter-LimitStop $old 'Обнаружено при запуске.'; $rep+='👉 Ход: Antigravity, если в Gemini есть дописанный непереданный блок Argon (передам); иначе жду нужную модель'; Send-StartReport $rep; return $true }
    } else {
      $rep+="3) Модель Gemini: «$m» — НЕ $($Cfg.ModelMustContain)$(if(-not $DryRun){', передачу останавливаю'})"
      if(-not $DryRun){ Enter-LimitStop $m 'Обнаружено при запуске.' }
      $rep+='👉 Ход: Antigravity, если в Gemini есть дописанный непереданный блок Argon (передам); иначе жду нужную модель'; Send-StartReport $rep -DryRun:$DryRun; return $true
    }
  } else { $rep+="3) Модель Gemini: $m ✅" }
  $gen=$false; try{ $gen=[bool](Gem-IsGenerating) }catch{}
  if($gen){ $rep+="   Gemini сейчас генерирует ответ — жду, пока закончит (повтор через $($Cfg.StartRetrySec) сек)"; $rep+='👉 Ход: Gemini — генерирует'; Send-StartReport $rep -DryRun:$DryRun; return $false }
  $hl=$null; try{ $hl=Get-AgHealth }catch{}
  if($hl -and -not $hl.ok){ $rep+="   Antigravity не отвечает ($($hl.reasons -join '; ')) — повтор через $($Cfg.StartRetrySec) сек"; $rep+='👉 Ход: ничей — жду Antigravity'; Send-StartReport $rep -DryRun:$DryRun; return $false }
  $qn=0; try{ $qn=@(Find-QueuedItems $ah).Count }catch{}
  $rep+="   Gemini: не генерирует; Antigravity: окно отвечает$(if($qn){", в очереди $qn сообщ. (агент занят)"})"
  # 4. Самый новый файл (пункт 24)
  $lp=$null; try{ $lp=Gem-LastReportPrompt }catch{}
  $rep+='4) Файлы:'
  $files=@(Get-Files); $last=$files | Where-Object { Is-Done $_.Name } | Select-Object -Last 1
  if($last){ $rep+="   последний обработанный: $($last.Name) — $(Get-StageRu (Get-Stage $last.Name))" }
  $tr=$null; $askNewest=$null; $askWhy=''
  if($Cfg.StartupNewestOnly -and $script:TriageNeeded){
    $tr=Invoke-StartupTriage $lp -DryRun:$DryRun; $rep+=$tr.lines; $askNewest=$tr.ask
    if(-not $DryRun){ $script:TriageNeeded=$false }
  }
  $n= if($tr){ $tr.newest } else { (Get-NewestFile $files) | ForEach-Object { $_.Name } }
  if(-not $tr){
    $pend=@($files | Where-Object { -not (Is-Done $_.Name) })
    if($pend.Count){
      $n=$pend[0].Name; $sf=Get-Stage $n
      if($sf -eq 'sent' -and $lp -ne $n){ $rep+="   $n помечен «отправлен», но в текущем чате Gemini его нет (сменился чат/аккаунт?) — отправлю заново"; if(-not $DryRun){ Set-Stage $n 'resend' } }
      elseif($sf -eq '' -and $lp -eq $n){ $rep+="   $n уже есть в чате Gemini — повторно НЕ отправляю, забираю ответ"; if(-not $DryRun){ Set-Stage $n 'sent' } }
      $rep+="   в очереди: $(($pend | ForEach-Object { $_.Name }) -join ', ')"
    }
  }
  # 5. Сверка: Gemini (последний запрос, ответ, блоки) и Antigravity (есть ли там ответ)
  $rep+='5) Сверка чатов:'
  $rep+="   Gemini: последний отчёт в чате — $(if($lp){$lp}else{'не найден'})"
  if(-not $n){ $rep+='👉 Ход: ничей — файлов нет, слежу за папкой'; Send-StartReport $rep -DryRun:$DryRun; return $true }
  if($lp -and $lp -ne $n -and (ProjOf $lp) -eq (ProjOf $n) -and (Get-SortKey $lp $Cfg.Pattern) -gt (Get-SortKey $n $Cfg.Pattern)){
    # противоречие: в Gemini уже более новый отчёт, чем есть в Downloads
    $rep+="   ⚠️ противоречие: в Gemini последний отчёт $lp, а в Downloads самый новый — $n"
    if($Cfg.AutoDecide){
      if(-not $DryRun -and -not (Is-Done $n)){ $script:Held.Remove($n); [void](Set-FileStage -State $script:St -Name $n -Stage 'skipped' -Note "авторешение: в Gemini уже более новый отчёт $lp" -Force); Save-State; $askNewest=$null
        $m="⚖ Авторешение: в Gemini последний отчёт $lp новее файла $n — $n НЕ отправляю (безопасный вариант), жду новый файл"; Log $m; Tg-Send $m | Out-Null }
      $rep+="   авторешение: $n не отправляю — жду новый файл"
    } else {
    if(-not $DryRun -and -not (Is-Done $n) -and -not $askNewest){ $script:Held[$n]=$true; $askNewest=$n } }
    $askWhy="⚠️ В чате Gemini последний отчёт — $lp, а самый новый файл в Downloads — $n (старее). Не понимаю, что сейчас происходит, поэтому ничего не делаю сам."
  }
  $pk=$null; try{ $pk=Gem-PeekAnswer }catch{ Log "Протокол: ответ Gemini не прочитан ($($_.Exception.Message))" }
  $inAg=$null
  if($pk){
    $rep+="   Gemini: ответ после последнего запроса — $(if($pk.answered){'есть'}else{'нет'}); блоки: $(Format-Langs $pk.labels)$(if($pk.answered -and -not $pk.md){" — блока '$($Cfg.CodeBlockLang)' НЕТ"})"
    if($pk.code){ try{ $inAg=[bool](Ag-HasText $pk.code) }catch{}; $rep+="   Antigravity: ответ («$(Get-FirstLine $pk.code)») в чате Antigravity — $(if($inAg){'ЕСТЬ'}else{'нет'})" }
    elseif($pk.md){ $rep+='   Antigravity: текст блока без копирования не прочитан — сверю при копировании (если уже вставлен — повторно не вставлю)' }
  }
  $st=Get-Stage $n; $turn=''
  if($askNewest){ $turn="ваш — ответьте в Telegram, отправлять ли $askNewest в Gemini" }
  elseif($tr -and $tr.pending){ $turn="ничей — про $n решу, когда найду окно Gemini" }
  elseif($st -eq 'skipped' -and $lp -eq $n -and $inAg){ $turn="Antigravity — $n пропущен скриптом (отправлен вручную), ответ Gemini на него уже у агента; жду следующий файл" }
  elseif($st -eq 'skipped'){ $turn="ничей — $n пропущен; жду новый файл" }
  elseif(Is-Done $n){
    if($st -eq 'relayed' -and $lp -eq $n -and $pk -and $pk.code -and $inAg -eq $false -and -not $DryRun -and $Cfg.AutoDecide){
      $turn="Antigravity — ответ на $n по учёту передан; в окне Antigravity не виден (через окно читается не всё), повторно НЕ вставляю (авторешение); жду следующий файл"
      Log "Авторешение: ответ на $n по учёту передан, в Antigravity не виден — повторно не вставляю (безопасный вариант)"
    }
    elseif($st -eq 'relayed' -and $lp -eq $n -and $pk -and $pk.code -and $inAg -eq $false -and -not $DryRun){
      $turn="ваш — ответ на $n по учёту передан, но в Antigravity его не вижу; спрашиваю"
      $p=New-TgPrompt -Kind 'proto' -Text "⚠️ Ответ Gemini на $n по моему учёту уже передан в Antigravity, но в чате Antigravity я его не вижу. Передать его в Antigravity?" -Buttons "Передать ответ в Antigravity=relay;Не передавать=norelay" -Data @{ name=$n }
    }
    elseif($st -eq 'nocode'){ $turn="ваш — ответ на $n был без блока Markdown; жду новый файл" }
    else { $turn="Antigravity — ответ на $n у агента; жду следующий файл" }
  }
  elseif($st -eq 'answered'){ $turn="GGskript — передам уже полученный ответ на $n в Antigravity (если его там ещё нет)" }
  elseif($st -eq 'stale'){ $turn="ваш — ответ на $n совпал со старым: «передай всё равно» или «отправь заново»" }
  elseif($st -eq 'sent' -or $lp -eq $n){
    if($pk -and -not $pk.answered){ $turn="Gemini — ответа на $n ещё нет; жду" }
    elseif($pk -and -not $pk.md){ $turn="ваш — в ответе на $n нет блока Markdown (блоки: $(Format-Langs $pk.labels)); другие блоки не беру, пришлю вопрос" }
    elseif($inAg){ $turn="Antigravity — ответ на $n уже вставлен; отмечу как переданный и жду следующий файл" }
    else { $turn="GGskript — заберу ответ на $n (только блок Markdown) и передам в Antigravity" }
  }
  else { $turn="GGskript — отправлю $n в Gemini" }
  $rep+="👉 Ход: $turn"
  Send-StartReport $rep -DryRun:$DryRun
  if(-not $DryRun -and $askNewest){ Send-NewestPrompt $askNewest $askWhy }
  $true
}

# ---------- Лимиты ----------
function Find-AgServers{
  $res=@()
  Get-CimInstance Win32_Process -Filter "Name LIKE 'language_server%'" -EA 0 | ForEach-Object {
    $tok=[regex]::Match([string]$_.CommandLine,'--csrf_token\s+(\S+)').Groups[1].Value
    if($tok){ foreach($c in @(Get-NetTCPConnection -OwningProcess $_.ProcessId -State Listen -EA 0)){ $res+=@{port=$c.LocalPort; tok=$tok} } }
  }
  $res
}
# ВНИМАНИЕ: внутренний недокументированный API Antigravity (может сломаться при обновлении).
function Ag-Rpc($method){
  $body='{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}'
  $tryOne={ param($c) Invoke-RestMethod "http://127.0.0.1:$($c.port)/exa.language_server_pb.LanguageServerService/$method" -Method Post -Body $body -ContentType 'application/json' -Headers @{'X-Codeium-Csrf-Token'=$c.tok;'Connect-Protocol-Version'='1'} -TimeoutSec 6 }
  if($script:AgSrv){ try{ return (& $tryOne $script:AgSrv) }catch{ $script:AgSrv=$null } }
  foreach($c in Find-AgServers){ try{ $r=& $tryOne $c; $script:AgSrv=$c; return $r }catch{} }
  throw 'локальный сервер Antigravity не отвечает'
}
function Get-AgQuota{ ConvertFrom-AgQuota -Response (Ag-Rpc 'RetrieveUserQuotaSummary') -Group $Cfg.AgGroup -Refine { Ag-Rpc 'GetUserStatus' } }
function Get-GeminiWebUsage{ ConvertFrom-UsageText (Gem-GetUsageText) }
function Quota-Text{
  if(!$script:Q){ return 'ещё не проверялись' }
  $q=$script:Q; $l=@("проверено в $($q.time)")
  if($q.gweb){ $l+="Gemini (сайт): текущее использовано $($q.gweb.cur)% ($($q.gweb.curReset)); неделя использовано $($q.gweb.wk)% ($($q.gweb.wkReset))" } elseif($q.gwebErr){ $l+="Gemini (сайт): ошибка — $($q.gwebErr)" }
  if($q.ag){ $l+="Antigravity ($($Cfg.AgGroup)): 5 ч осталось $($q.ag.h5.rem)%$($q.ag.h5.note) (сброс $($q.ag.h5.reset)); неделя осталось $($q.ag.wk.rem)%$($q.ag.wk.note) (сброс $($q.ag.wk.reset))" } elseif($q.agErr){ $l+="Antigravity: ошибка — $($q.agErr)" }
  $b=Quota-Blocked; if($b){ $l+="⛔ Остановлено по лимиту: $b" }
  $l -join "`n"
}
# ---------- Автовозобновление после сброса лимита ----------
function Format-PlanTime([datetime]$At,[datetime]$Now=(Get-Date)){ if($At.Date -eq $Now.Date){ $At.ToString('HH:mm') } else { $At.ToString('dd.MM HH:mm') } }
function Get-AutoResumeRetryMin([int]$Fails,$C=$Cfg){ $r=[double]$C.AutoResumeRetryMin; if($Fails -gt 1){ $r=$r*[Math]::Pow(2,[Math]::Min(10,$Fails-1)) }; [Math]::Min($r,[double]$C.AutoResumeMaxRetryMin) }
# Когда перепроверять: позже всех сбросов блокирующих лимитов (+запас); лимит Gemini не исчерпан, а модель не та — сразу;
# время неизвестно — через интервал повтора. Не чаще, чем раз в интервал повтора после прошлой попытки. Чистая функция.
function Get-AutoResumePlan{
  param($Q,[bool]$LimitStop,[bool]$QStopG,[bool]$QStopA,[datetime]$Now=(Get-Date),$LastAttempt=$null,[int]$Fails=0,$C=$Cfg)
  if(-not ($LimitStop -or $QStopG -or $QStopA)){ return $null }
  $margin=[double]$C.AutoResumeMarginMin; $retry=Get-AutoResumeRetryMin $Fails $C
  $resets=@(); $ats=@(); $why=@()
  if($LimitStop -or $QStopG){
    $g= if($Q){ $Q.gweb } else { $null }
    if($g){
      $over=@()
      if(Test-QuotaOver $g.cur $C.GeminiWebThreshold $C.GeminiWebThresholdIs){ $over+=,@('лимит Gemini (текущий)',$g.curResetAt,$g.curReset) }
      if(Test-QuotaOver $g.wk $C.GeminiWebThreshold $C.GeminiWebThresholdIs){ $over+=,@('лимит Gemini (неделя)',$g.wkResetAt,$g.wkReset) }
      if($over.Count){ $resets+=$over }
      elseif($LimitStop){ $ats+=$Now; $why+="лимит Gemini не исчерпан (использовано $($g.cur)%) — верну $($C.ModelMustContain)" }
      else { $ats+=$Now.AddMinutes($retry); $why+="лимит Gemini — перепроверю через $retry мин" }
    } elseif($LimitStop){ $ats+=$Now; $why+="проверю страницу лимитов и верну $($C.ModelMustContain)" }
    else { $ats+=$Now.AddMinutes($retry); $why+="лимиты Gemini не прочитаны — перепроверю через $retry мин" }
  }
  if($QStopA){
    $n0=$resets.Count
    if($Q -and $Q.ag){ foreach($kk in 'h5','wk'){ $v=$Q.ag[$kk]; if($v -and (Test-QuotaOver (100-[double]$v.rem) $C.AgThreshold $C.AgThresholdIs)){ $resets+=,@("лимит Antigravity ($(if($kk -eq 'h5'){'5 ч'}else{'неделя'}))",$v.resetAt,[string]$v.reset) } } }
    if($resets.Count -eq $n0){ $ats+=$Now.AddMinutes($retry); $why+="лимит Antigravity — перепроверю через $retry мин" }
  }
  foreach($r in $resets){
    $at=$r[1]; if($null -eq $at -and $r[2]){ $at=ConvertFrom-ResetText $r[2] $Now }
    if($at){ $at=[datetime]$at; $why+="$($r[0]): сброс в $(Format-PlanTime $at $Now)"; if($at -lt $Now){ $at=$Now }; $ats+=$at.AddMinutes($margin) }
    else { $ats+=$Now.AddMinutes($retry); $why+="$($r[0]): время сброса не прочитано — перепроверю через $retry мин" }
  }
  $at=@($ats | Sort-Object)[-1]
  if($LastAttempt){ $min=([datetime]$LastAttempt).AddMinutes($retry); if($at -lt $min){ $at=$min; $why+="повтор не чаще раза в $retry мин" } }
  @{ at=$at; why=($why -join '; ') }
}
function Update-AutoPlan([switch]$Quiet){
  if(-not $Cfg.AutoResume -or -not ($script:LimitStop -or $script:QStopG -or $script:QStopA)){ $script:AutoPlan=$null; $script:AutoPlanKey=''; return }
  $p=Get-AutoResumePlan -Q $script:Q -LimitStop ([bool]$script:LimitStop) -QStopG ([bool]$script:QStopG) -QStopA ([bool]$script:QStopA) -Now (Get-Date) -LastAttempt $script:AutoLastAttempt -Fails $script:AutoFails
  $script:AutoPlan=$p
  $key=$p.at.ToString('yyyy-MM-dd HH:mm'); if($key -eq $script:AutoPlanKey){ return }
  $script:AutoPlanKey=$key
  if(-not $Quiet -and $p.at -gt (Get-Date).AddSeconds(90)){
    $msg="⏰ Жду сброса лимита: проверю в $(Format-PlanTime $p.at) ($($p.why)). Затем$(if($Cfg.AutoSwitchModel){" верну модель $($Cfg.ModelMustContain) и"}) продолжу сам."
    Log $msg; Tg-Send $msg | Out-Null
  } else { Log "Автовозобновление: попытка в $(Format-PlanTime $p.at) ($($p.why))" }
}
function Register-AutoFail([string]$Reason){
  $script:AutoFails++; $script:AutoPlanKey=''
  Update-AutoPlan -Quiet
  $nx= if($script:AutoPlan){ Format-PlanTime $script:AutoPlan.at } else { '—' }
  $msg="⏳ Автовозобновление не удалось: $Reason. Остаюсь на остановке, следующая попытка в $nx."
  Log $msg; Tg-Send $msg | Out-Null
}
function Switch-ToArgon{
  $want=$Cfg.ModelMustContain; $before= try{ Get-ModelNow }catch{ '?' }
  Log "Модель: переключаю «$before» → $want"
  try{
    [void](Gem-SelectModel $want)
    Start-Sleep -Seconds 2
    $m=Get-ModelNow
    if(-not (Is-Argon $m)){ throw "после переключения выбрана «$m»" }
  } catch { Send-ManualModelNotice $_.Exception.Message; throw }
  $script:ManualModelSaid=$false
  Log "Модель: выбрана «$m»"; $m
}
# Пункт 26: автопереключение не удалось — один раз (до успешного выбора) прошу выбрать модель вручную.
function Send-ManualModelNotice([string]$Why){
  if($script:ManualModelSaid){ return }
  $script:ManualModelSaid=$true
  $w=$Cfg.ModelMustContain
  Tg-Send "⚠️ Не смог сам переключить модель Gemini на $w ($Why). Выберите $w вручную (меню «Выбор режима» в Gemini) — проверяю модель раз в $($Cfg.ModelRecheckSec) сек и продолжу сам, как только будет $w." | Out-Null
  [void](Play-Sound 'error')
}
# Одна попытка: страница лимитов → лимит ниже порога → модель ModelMustContain → снять остановку. Ручную паузу не трогает.
function Invoke-AutoResume{
  $script:AutoLastAttempt=Get-Date
  $why= if($script:AutoPlan){ $script:AutoPlan.why } else { '' }
  $script:State='автовозобновление: проверяю лимиты'; Log "Автовозобновление: проверяю лимиты ($why)"
  try{ Check-Quotas | Out-Null }catch{ Log "Лимиты: $($_.Exception.Message)" }
  $script:LastQuota=Get-Date
  $qb=Quota-Blocked
  if($qb){ Register-AutoFail "лимит ещё не обновился ($qb)"; return $false }
  if($script:LimitStop -and $Cfg.GeminiWebCheck){
    $g= if($script:Q){ $script:Q.gweb } else { $null }
    if(-not $g -and -not ($script:Q -and $script:Q.gwebNoTab)){ Register-AutoFail "страница лимитов Gemini не прочитана$(if($script:Q -and $script:Q.gwebErr){" ($($script:Q.gwebErr))"})"; return $false }
    if($g -and (Test-QuotaOver $g.cur $Cfg.GeminiWebThreshold $Cfg.GeminiWebThresholdIs) -or (Test-QuotaOver $g.wk $Cfg.GeminiWebThreshold $Cfg.GeminiWebThresholdIs)){ Register-AutoFail "лимит Gemini ещё не обновился (текущий $($g.cur)%, неделя $($g.wk)%)"; return $false }
  }
  $m=$null; try{ $m=Get-ModelNow }catch{}
  if(-not (Is-Argon $m)){
    if(-not $Cfg.AutoSwitchModel){
      if($script:LimitStop){ Register-AutoFail "лимит обновился, но в Gemini модель «$m», а автопереключение выключено (AutoSwitchModel=false) — выбери $($Cfg.ModelMustContain) вручную"; return $false }
    } else {
      $script:State="автовозобновление: переключаю модель на $($Cfg.ModelMustContain)"
      try{ $m=Switch-ToArgon }
      catch{
        $e=$_.Exception.Message
        if(-not $script:LimitStop){ $script:LimitStop=$true; $script:LimitSince=Get-Date }
        $script:LimitModel= try{ Get-ModelNow }catch{ '?' }
        Register-AutoFail "не удалось переключить модель на $($Cfg.ModelMustContain): $e"; return $false
      }
    }
  }
  $script:AutoFails=0; $script:AutoPlan=$null; $script:AutoPlanKey=''
  if($script:LimitStop){ Resume-Work "автоматически после сброса лимита" } else { Log "Автовозобновление: лимиты в норме, модель «$m»" }
  $true
}
function Quota-Blocked{ $r=@(); if($script:QStopG){ $r+='лимит Gemini (сайт)' }; if($script:QStopA){ $r+='лимит Antigravity' }; $r -join ', ' }
function Check-Quotas{
  $q=@{ time=(Get-Date).ToString('HH:mm') }
  if($Cfg.AgCheck){ try{ $q.ag=Get-AgQuota }catch{ $q.agErr=$_.Exception.Message; Log "Лимиты Antigravity: $($q.agErr)" } }
  if($Cfg.GeminiWebCheck){
    try{ $q.gweb=Get-GeminiWebUsage; $script:UsageNoTabSaid=$false }
    catch{
      $q.gwebErr=$_.Exception.Message
      if($q.gwebErr -like "*$($script:UsageNoTabMsg)*"){
        # пункт 26: вкладки лимитов нет — ничего не открываю, лимиты Gemini считаю неизвестными (не блокируют); сообщаю один раз
        $q.gwebNoTab=$true
        if(-not $script:UsageNoTabSaid){ $script:UsageNoTabSaid=$true; $m="лимиты Gemini не прочитаны: $($script:UsageNoTabMsg)"; Log $m; Tg-Send "ℹ️ $m. Новую вкладку не открываю; лимиты Gemini считаю неизвестными (работу не блокирую). Откройте https://gemini.google.com/usage вкладкой в том же браузере." | Out-Null }
      } else { Log "Лимиты Gemini: $($q.gwebErr)" }
    }
  }
  $script:Q=$q
  $m=@()
  if($q.gweb){ $m+=@{k='gcur';side='g';used=$q.gweb.cur;txt="Gemini (сайт), текущее: использовано $($q.gweb.cur)% ($($q.gweb.curReset))"}
               $m+=@{k='gwk';side='g';used=$q.gweb.wk;txt="Gemini (сайт), неделя: использовано $($q.gweb.wk)% ($($q.gweb.wkReset))"} }
  if($q.ag){ foreach($kk in 'h5','wk'){ $v=$q.ag[$kk]; if($v){ $m+=@{k="ag$kk";side='a';used=(100-$v.rem);txt="Antigravity, $(if($kk -eq 'h5'){'5 часов'}else{'неделя'}): осталось $($v.rem)% (сброс $($v.reset))"} } } }
  $warn=@(); $stopG=$false; $stopA=$false; $step=$Cfg.QuotaReWarnStep
  foreach($x in $m){
    if($x.side -eq 'g'){ $pct=$Cfg.GeminiWebThreshold; $mode=$Cfg.GeminiWebThresholdIs } else { $pct=$Cfg.AgThreshold; $mode=$Cfg.AgThresholdIs }
    if(Test-QuotaOver $x.used $pct $mode){
      $ign= $script:QOverride.ContainsKey($x.k) -and $x.used -lt ($script:QOverride[$x.k]+$step)
      if(-not $ign){ $script:QOverride.Remove($x.k); if($x.side -eq 'g'){ $stopG=$true } else { $stopA=$true } }
      if(-not $script:QWarned.ContainsKey($x.k) -or $x.used -ge ($script:QWarned[$x.k]+$step)){ $script:QWarned[$x.k]=$x.used; $warn+="$($x.txt) — порог: $(if($mode -eq 'remaining'){"осталось ≤ $pct%"}else{"использовано ≥ $pct%"})$(if($ign){' (игнорирую по «продолжай»)'})" }
    } else { $script:QWarned.Remove($x.k); $script:QOverride.Remove($x.k) }
  }
  $wasBlocked=[bool](Quota-Blocked)
  if($q.gweb){ $script:QStopG=$stopG } elseif($q.gwebNoTab){ $script:QStopG=$false } elseif($q.gwebErr -and $script:QStopG){ Log 'Лимиты Gemini не прочитаны — остановка по лимиту остаётся в силе до успешной проверки.' }
  if($q.ag){ $script:QStopA=$stopA }
  $nowBlocked=Quota-Blocked
  if($warn.Count){ $msg="⚠️ Лимиты:`n• "+($warn -join "`n• ")+$(if($nowBlocked){"`n⛔ Передачу останавливаю ($nowBlocked). Продолжу сам, когда станет ниже порога, или напиши «продолжай»."}else{''}); Log $msg; Tg-Send $msg | Out-Null }
  elseif($nowBlocked -and -not $wasBlocked){ $msg="⛔ Остановлено по лимиту: $nowBlocked"; Log $msg; Tg-Send $msg | Out-Null }
  if($wasBlocked -and -not $nowBlocked){ $n=Next-FileName; $msg="▶️ Лимиты в норме, работа возобновлена. Следующий файл: $(if($n){$n}else{'новых файлов пока нет'})"; Log $msg; Tg-Send $msg | Out-Null }
  Log "Лимиты: $((Quota-Text) -replace "`n",' | ')"
  Quota-Text
}
function Quota-Override{ foreach($k in @($script:QWarned.Keys)){ $script:QOverride[$k]=$script:QWarned[$k] }; $script:QStopG=$false; $script:QStopA=$false }

# ---------- Блокирующие окна ----------
function Inspect-Foreground([switch]$Light){
  $h=Get-ForegroundHandle; $i=Get-WindowInfo $h
  $btns=@(); $area=$null
  if(-not $Light){
    try{ $btns=@(Uia-FindAll -Root $h -ControlType 'Button' | ForEach-Object { (Uia-Name $_).Trim() } | Where-Object { $_ } | Select-Object -Unique) }catch{}
    try{ $r=Get-WindowBounds $h; $s=[System.Windows.Forms.SystemInformation]::VirtualScreen; $area=(($r.R-$r.L)*($r.B-$r.T))/[double]([Math]::Max(1,$s.Width*$s.Height)); $i | Add-Member -NotePropertyName rect -NotePropertyValue $r -Force }catch{}
  }
  $i | Add-Member -NotePropertyName buttons -NotePropertyValue $btns -Force
  $i | Add-Member -NotePropertyName area -NotePropertyValue $area -Force
  $i
}
function Blk-Key($i){ "$($i.proc)|$($i.title)|$($i.class)" }
function Click-DialogButton($i,[string]$Button){
  if(Test-ForbiddenWindow $i){ return $false }
  if(-not $Button){ return $false }
  try{
    $b=@(Uia-FindAll -Root $i.h -ControlType 'Button' | Where-Object { Test-ButtonMatch (Uia-Name $_) $Button }) | Select-Object -First 1
    if(!$b){ return $false }
    if(Uia-Invoke $b){ Start-Sleep -Milliseconds 500; return $true }
    return [bool](Uia-ClickEl $b)
  }catch{ return $false }
}
function Get-Allowlist{ $c=Load-TgCfg; if($c -and $c.Contains('blocking_allowlist') -and $c.blocking_allowlist){ @($c.blocking_allowlist) } else { @() } }
function Save-Allowlist($list){ $c=Load-TgCfg; if(!$c){ $c=[ordered]@{} }; $c['blocking_allowlist']=@($list); Save-TgCfg $c }
function Try-AutoClose($i){
  if(Test-ForbiddenWindow $i){ return $false }
  if($Cfg.AutoCloseProcRx -and ([string]$i.proc -notmatch $Cfg.AutoCloseProcRx)){ return $false }
  foreach($e in (Get-Allowlist)){
    $tr=[string]$e.titleRegex; $pr=[string]$e.processName; $bt=[string]$e.button
    if($tr -and ($i.title -match $tr) -and ((-not $pr) -or ($i.proc -match $pr))){
      if(Click-DialogButton $i $bt){ $m="✅ Закрыл окно «$($i.title)» кнопкой «$bt» (из списка разрешённых) — продолжаю работу."; Log $m; Tg-Send $m | Out-Null; return $true }
    }
  }
  $false
}
function Note-Blocking{
  $i=Inspect-Foreground -Light; $key=Blk-Key $i
  if(-not ($key.Trim('|'))){ return }
  if($script:Blk.key -ne $key){ $script:Blk=@{ key=$key; info=$i; since=Get-Date; notified=$false; lastRecheck=Get-Date } }
}
function Notify-Block($i){
  $dlg=Test-LooksLikeDialog $i
  $cap="🚧 Не могу переключиться на рабочее окно — поверх открыто окно:`nЗаголовок: «$($i.title)»`nПрограмма: $($i.proc)`nКласс: $($i.class)`nКнопки: $(if($i.buttons){($i.buttons) -join ', '}else{'—'})"
  if($dlg){ $cap+="`n`nОтветь: «нажми <точное название кнопки>» — нажать один раз; «разрешай такие» или «добавь в список <кнопка>» — закрывать такие окна автоматически. Проверяю раз в 60 сек." }
  else { $cap+="`n`nПохоже, это обычное окно, в котором ты работаешь (не диалог). Жду, пока освободится фокус." }
  Log "Блокирующее окно: «$($i.title)» [$($i.proc)] класс=$($i.class) кнопки=$(($i.buttons) -join ', ') диалог=$dlg"
  $sent=$false
  $mode=[string]$Cfg.ScreenshotMode
  if($mode -eq 'full' -or ($mode -eq 'dialog' -and $dlg -and $i.rect)){
    try{ Send-Screenshot $cap $(if($mode -eq 'full'){ $null } else { $i.rect }); $sent=$true }catch{ Log "Скрин блок-окна: $($_.Exception.Message)" }
  }
  if(-not $sent){ Tg-Send $cap | Out-Null }
  [void](Play-Sound 'error')
}
function Reset-Block($msg){ if($msg){ Log $msg; Tg-Send $msg | Out-Null }; $script:Blk=@{ key=$null; info=$null; since=$null; notified=$false; lastRecheck=(Get-Date) } }
function Check-Blocking{
  if(-not $script:Blk.key){ return }
  $i=Inspect-Foreground -Light; $key=Blk-Key $i
  if($key -ne $script:Blk.key){ if($script:Blk.notified){ Reset-Block "✅ Блокирующее окно «$($script:Blk.info.title)» исчезло — продолжаю работу." } else { Reset-Block $null }; return }
  if(-not $script:Blk.notified){
    if(((Get-Date)-$script:Blk.since).TotalSeconds -lt 8){ return }
    $full=Inspect-Foreground; $script:Blk.info=$full
    if(Try-AutoClose $full){ Reset-Block $null; return }
    Notify-Block $full; $script:Blk.notified=$true; $script:Blk.lastRecheck=Get-Date
  } else {
    if(((Get-Date)-$script:Blk.lastRecheck).TotalSeconds -lt 60){ return }
    $script:Blk.lastRecheck=Get-Date
    $full=Inspect-Foreground; $script:Blk.info=$full
    if(Try-AutoClose $full){ Reset-Block $null }
  }
}

# ---------- Antigravity недоступен: одно сообщение на состояние, редкие напоминания ----------
function Get-AgBlockText($b){
  $f= if($b.file){ "ответ на $($b.file) сохранён и будет передан ровно один раз, когда Antigravity примет ввод" } else { 'ответ сохранён' }
  switch($b.kind){
    'hung'     { "⏸ Antigravity не отвечает (зависло) — жду, $f.`nПризнаки: $($b.detail)" }
    'nowindow' { "⏸ Окно Antigravity не найдено (закрыто или перезапускается) — жду, $f." }
    'foreign'  { "✋ В поле чата Antigravity чужой текст: '$($b.detail)' — не трогаю. Отправь или очисти его; $f." }
    default    { "⚠️ Не удалось вставить ответ в Antigravity, причина не ясна: $($b.msg)`nДиагностика: $($b.detail)`n$f; повторяю раз в $($Cfg.AgBlockRetrySec) сек." }
  }
}
function Report-AgBlock($Ex,[string]$File){
  $kind=[string]$Ex.Kind; if(-not $kind){ $kind='unknown' }
  $now=Get-Date; $b=$script:AgBlock
  if(-not $b -or $b.kind -ne $kind){
    $script:AgBlock=@{ kind=$kind; msg=$Ex.Message; detail=[string]$Ex.Detail; file=$File; since=$now; notifiedAt=$now; restartedAt=$(if($b){$b.restartedAt}else{$null}) }
    $t=Get-AgBlockText $script:AgBlock; Log $t; Tg-Send $t | Out-Null
    if($kind -in @('foreign','unknown')){ [void](Play-Sound 'error') }   # нужен человек: чужой текст в поле / непонятная ошибка
  } else {
    $b.msg=$Ex.Message; $b.detail=[string]$Ex.Detail; if($File){ $b.file=$File }
    if($Cfg.AgBlockRemindMin -gt 0 -and ($now-$b.notifiedAt).TotalMinutes -ge $Cfg.AgBlockRemindMin){
      $b.notifiedAt=$now; $t="🔔 Напоминание (уже $([int]($now-$b.since).TotalMinutes) мин): $(Get-AgBlockText $b)"; Log $t; Tg-Send $t | Out-Null
    } else { Log "Antigravity: всё ещё «$kind» ($($Ex.Message)) — повтор через $($Cfg.AgBlockRetrySec) сек" }
  }
  $b=$script:AgBlock
  if($Cfg.AgAutoRestartMin -gt 0 -and $b.kind -eq 'hung' -and ($now-$b.since).TotalMinutes -ge $Cfg.AgAutoRestartMin -and (-not $b.restartedAt -or ($now-$b.restartedAt).TotalMinutes -ge $Cfg.AgAutoRestartMin)){
    $b.restartedAt=$now
    try{ $w=Ag-GetWindowInfo; if(-not $w -or -not $w.pid){ throw 'нет pid окна Antigravity' }; $exe=Restart-Antigravity $w.pid; $t="🔄 Antigravity не отвечал $($Cfg.AgAutoRestartMin)+ мин — перезапустил ($exe). Ответ передам, когда окно поднимется."; Log $t; Tg-Send $t | Out-Null }
    catch{ $t="❌ Автоперезапуск Antigravity не удался: $($_.Exception.Message)"; Log $t; Tg-Send $t | Out-Null }
  }
}

# ---------- Один шаг главного цикла (вынесен для тестов) ----------
# Возвращает 'stop' — выйти из цикла, 'continue' — сразу следующая итерация, 'ok'.
# ---------- Пункт 36: наблюдатель-зеркало (Gemini -> Antigravity) без привязки к этапам файлов ----------
# Номер отчёта NNN, на который ссылается ответ (первая строка вида «[S004] [REWORK S003]» или «…_003.md»).
function Test-AnswerRefersTo([string]$Answer,[string]$Name){
  $m=[regex]::Match($Name,$Cfg.Pattern); if(-not $m.Success){ return $false }
  $num=[int]$m.Groups['n'].Value; $head=(([string]$Answer) -split "`r?`n" | Select-Object -First 5) -join ' '
  if($head.Contains($Name)){ return $true }
  foreach($x in [regex]::Matches($head,'(?i)(?:S|REWORK\s*S|_)0*(\d{1,4})\b')){ if([int]$x.Groups[1].Value -eq $num){ return $true } }
  $false
}
# Отчёт, к которому отнести ответ: самый новый файл, ещё не «relayed» (пропущен/отправлен вручную/в работе).
function Get-MirrorTarget{ $f=Get-NewestFile @(Get-Files -All); if($f -and (Get-Stage $f.Name) -ne 'relayed'){ $f.Name } else { $null } }
function Invoke-MirrorGemini([switch]$Force){
  # пункт 46: лимит Gemini / не-Argon блокирует только отправку В Gemini; дописанный блок Argon в Antigravity передаю. Блокирует лишь лимит Antigravity.
  if(-not $Cfg.MirrorRelay -or $script:Paused -or $script:QStopA){ return $false }
  if(-not $Force -and $script:LastMirror -and ((Get-Date)-$script:LastMirror).TotalSeconds -lt $Cfg.MirrorEverySec){ return $false }
  $script:LastMirror=Get-Date
  if($script:AgBlock -and $script:AgBlock.kind -in @('hung','nowindow')){ return $false }
  $gen=$false; try{ $gen=[bool](Gem-IsGenerating) }catch{ return $false }
  if($gen){ $script:MirrorSeen=$null; return $false }
  $pk=$null; try{ $pk=Gem-PeekAnswer }catch{ return $false }
  if(-not $pk -or -not $pk.answered -or -not $pk.md){ $script:MirrorSeen=$null; return $false }
  $peekKey= if($pk.code){ Get-Hash8 $pk.code } else { 'md:' + (@($pk.labels) -join ',') }
  if($pk.code -and (Test-RelayHash $script:St $peekKey)){ $script:MirrorSeen=$null; return $false }
  if($pk.code){
    # пункт 43: очередь по номеру шага — блок передаю, только если сейчас ход Antigravity (S<N> новее отчёта и ещё не передавался)
    [void](Note-BlockHeader $pk.code); $d=Get-TurnDecisionNow $pk.code; $script:TurnDecision=$d.turn
    if($d.action -ne 'relay-block'){ Note-Contradiction $d; $script:MirrorSeen=$null
      $k="$peekKey|$($d.action)"; if($script:MirrorDecSaid -ne $k){ $script:MirrorDecSaid=$k; Log "🔭 Наблюдатель: блок в Gemini не передаю — $($d.reason)" }; return $false }
  }
  # два одинаковых чтения подряд — ответ дописан и стабилен
  if($script:MirrorSeen -ne $peekKey){ $script:MirrorSeen=$peekKey; return $false }
  $m2=$null; try{ $m2=Get-ModelNow }catch{}
  $argNow=[bool]($m2 -and (Is-Argon $m2))
  $ans=Gem-CopyCode; if(-not $ans){ return $false }
  if(-not $argNow){
    $ok=Test-BlockFromArgon -Code $ans -ArgonNow $false -Gate (Get-BlockGate $ans)
    if(-not $ok.ok){ $script:MirrorSeen=$null; return $false }
    Log "🔭 Наблюдатель: модель сейчас «$m2» (лимит), но блок уже дописан — $($ok.why); передаю в Antigravity"
  }
  $hh=Get-Hash8 $ans
  if(Test-RelayHash $script:St $hh){ $script:MirrorSeen=$null; return $false }
  $n=Get-MirrorTarget
  $ref=Get-AnswerRefNow; if($ref -and (Test-Path -LiteralPath (Join-Path $Cfg.Downloads $ref))){ $n=$ref }   # пункт 44: привязка по «Ответ на:»
  if(Ag-HasText $ans){
    Register-BlockRelayed $ans $hh
    Add-RelayHash $script:St $hh $Cfg.HashKeep; if($n){ [void](Set-FileStage -State $script:St -Name $n -Stage 'relayed' -Hash $hh -Note 'наблюдатель: уже был в Antigravity' -Force) }; Save-State
    Log "🔭 Наблюдатель: блок Markdown (хэш $hh) уже есть в Antigravity — отметил как переданный"; $script:MirrorSeen=$null; return $false
  }
  $g=Get-BlockGate $ans; if($g.tagged -and -not $g.ok){ Notify-BlockGate $g $hh $n; $script:MirrorSeen=$null; return $false }   # пункт 44
  [void](Assert-AgReady)
  Ag-Send -Text $ans -Label 'ответ Gemini (наблюдатель)' -Name $n
  Register-BlockRelayed $ans $hh
  Add-RelayHash $script:St $hh $Cfg.HashKeep; $script:TurnSide='antigravity'
  if($n){ $script:Held.Remove($n); [void](Set-FileStage -State $script:St -Name $n -Stage 'relayed' -Hash $hh -Note 'наблюдатель: ответ Gemini передан' -Force); Mark-Done $n }
  Save-State; $script:MirrorSeen=$null; [void](Play-Sound 'info')
  $msg="🔭 Наблюдатель: в Gemini новый блок Markdown (модель $m2, $($ans.Length) симв., хэш $hh, «$(Get-FirstLine $ans)»)$(if($n){" — ответ на $n"}) — передал в Antigravity"
  Log $msg; Tg-Send $msg | Out-Null; $true
}
function Invoke-MainStep{
  try{
    Pump
    if(Test-Path -LiteralPath $Cfg.StopFile){ Remove-Item -LiteralPath $Cfg.StopFile -EA 0; Log 'Остановлено (файл STOP).'; return 'stop' }
    if($script:Paused){ Invoke-StoppedStep; return 'ok' }
    try{ Check-Blocking }catch{}
    if($script:Queue.Count -gt 0){
      $c=$script:Queue.Dequeue(); $script:Busy=$true; $script:State="выполняю команду ($($c.k))"
      try{ Run-Action $c }
      catch{ $err=$_; $kind=Get-ErrorKind $err; if($kind -eq 'stop'){ throw }
        $em=switch($kind){ 'limit'{ "лимит/модель: $($err.Exception.Message)" } 'stale'{ "скопирован старый ответ (можно «передай всё равно»)" } default{ $err.Exception.Message } }
        $msg="❌ Команда не выполнена: $em"; Log $msg; Tg-Send $msg | Out-Null }
      finally{ $script:Busy=$false }
      return 'continue'
    }
    if($Cfg.QuotaEveryMin -gt 0 -and ((Get-Date)-$script:LastQuota).TotalMinutes -ge $Cfg.QuotaEveryMin){
      $script:LastQuota=Get-Date; $script:State='проверяю лимиты'; try{ Check-Quotas | Out-Null }catch{ Log "Лимиты: $($_.Exception.Message)" }
      Update-AutoPlan
    }
    if($script:NeedStart){
      if(((Get-Date)-$script:LastStartTry).TotalSeconds -ge $Cfg.StartRetrySec){
        $script:LastStartTry=Get-Date; $script:State='процедура запуска'
        $script:Busy=$true; try{ if(Start-Procedure){ $script:NeedStart=$false } else { $script:State="процедура запуска не пройдена (нет окна) — повтор через $($Cfg.StartRetrySec) сек" } } finally { $script:Busy=$false }
      }
      if($script:NeedStart){ Nap 2; return 'continue' }
    }
    $qb=Quota-Blocked
    if(($script:LimitStop -or $qb) -and $Cfg.AutoResume -and -not $script:Paused){
      if(-not $script:AutoPlan){ Update-AutoPlan }
      if($script:AutoPlan -and (Get-Date) -ge $script:AutoPlan.at){ $script:Busy=$true; try{ [void](Invoke-AutoResume) } finally { $script:Busy=$false }; return 'continue' }
    } elseif(-not ($script:LimitStop -or $qb)){ $script:AutoPlan=$null }
    $wait= if($script:AutoPlan -and $Cfg.AutoResume){ " — жду сброса, проверю в $(Format-PlanTime $script:AutoPlan.at)" } else { '' }
    if($script:LimitStop){
      $script:State="⛔ остановлено: в Gemini модель «$($script:LimitModel)» вместо $($Cfg.ModelMustContain)$wait"
      if(((Get-Date)-$script:LastLimitCheck).TotalSeconds -ge $Cfg.ModelRecheckSec){
        $script:LastLimitCheck=Get-Date
        try{ $m=Get-ModelNow; if(Is-Argon $m){ Resume-Work "автоматически: снова выбрана $m" } else { $script:LimitModel=$m; Log "Лимит: модель всё ещё «$m»" } }catch{ Log "Лимит: не удалось проверить модель ($($_.Exception.Message))" }
      }
    }
    elseif($qb){ $script:State="⛔ остановлено по лимиту: $qb$(if($wait){$wait}else{" (проверка раз в $($Cfg.QuotaEveryMin) мин)"})" }
    # пункт 46: лимит одной стороны блокирует только передачу В эту сторону
    $gemBlk=[bool]($script:LimitStop -or $script:QStopG); $agBlk=[bool]$script:QStopA
    if($gemBlk -and -not $agBlk -and $Cfg.MirrorRelay){
      $script:Busy=$true; try{ if(Invoke-MirrorGemini){ return 'continue' } }catch{ if((Get-ErrorKind $_) -eq 'stop'){ throw }; Log "Наблюдатель (лимит Gemini): $($_.Exception.Message)" } finally { $script:Busy=$false }
    }
    elseif($agBlk -and -not $gemBlk){
      $next=Next-File
      if($next -and (Get-Stage $next.Name) -ne 'answered'){ $script:Busy=$true; try{ Process-File $next } finally { $script:Busy=$false } }
    }
    if($script:LimitStop -or $qb){}
    else{
      $script:State='слежу за папкой Downloads, жду новый отчёт'
      $next=Next-File
      # ответ Gemini, относящийся к ожидающему отчёту (отправлен вручную) — сначала зеркало, иначе отчёт уйдёт повторно
      $pre=$false; if($next -and $Cfg.MirrorRelay){ try{ $pre=(Get-Stage $next.Name) -in @('','resend') }catch{} }
      if($pre){
        $pk=$null; try{ if(-not (Gem-IsGenerating)){ $pk=Gem-PeekAnswer } }catch{}
        if($pk -and $pk.answered -and $pk.md -and $pk.code -and -not (Test-RelayHash $script:St (Get-Hash8 $pk.code)) -and (Test-AnswerRefersTo $pk.code $next.Name)){
          $script:Busy=$true; try{ $script:MirrorSeen= Get-Hash8 $pk.code; if(Invoke-MirrorGemini -Force){ return 'continue' } } finally { $script:Busy=$false }
        }
      }
      if($next){ $script:Busy=$true; try{ Process-File $next } finally { $script:Busy=$false } }
      elseif($Cfg.MirrorRelay){ $script:Busy=$true; try{ [void](Invoke-MirrorGemini) }catch{ if((Get-ErrorKind $_) -eq 'stop'){ throw }; Log "Наблюдатель: $($_.Exception.Message)" } finally { $script:Busy=$false } }
    }
  }catch{
    $script:Busy=$false
    $kind=Get-ErrorKind $_
    if($kind -eq 'stop'){ Remove-Item -LiteralPath $Cfg.StopFile -EA 0; Log 'Остановлено.'; return 'stop' }
    if($kind -eq 'limit'){ Log "Остановка по лимиту/модели: $($_.Exception.Message)"; return 'continue' }
    if($kind -eq 'paused'){ Log "Стоп: $($_.Exception.Message)"; return 'ok' }
    if($kind -eq 'agblock'){
      $ex=$_.Exception; while($ex -and -not ($ex -is [GG.AgBlockedException])){ $ex=$ex.InnerException }
      if(-not $ex){ $ex=$_.Exception }
      $nf=$null; try{ $nf=Next-FileName }catch{}
      Report-AgBlock $ex $nf
      $script:State="⏸ жду Antigravity ($($script:AgBlock.kind)): $($ex.Message)"
      try{ Nap $(if($script:AgBlock.kind -eq 'foreign'){ $Cfg.AgForeignRetrySec } else { $Cfg.AgBlockRetrySec }) }catch{ if((Get-ErrorKind $_) -eq 'stop'){ Log 'Остановлено.'; return 'stop' } }
      return 'ok'
    }
    $msg="❌ ОШИБКА: $($_.Exception.Message). Повтор через $($Cfg.RetrySec) сек."; Log $msg -NoAction; Notify $msg
    $script:State="повтор после ошибки: $($_.Exception.Message)"
    try{ for($i=$Cfg.RetrySec;$i -gt 0;$i-=10){ Write-Host "  ...повтор через $i сек"; Nap ([Math]::Min(10,$i)) } }catch{ if((Get-ErrorKind $_) -eq 'stop'){ Log 'Остановлено.'; return 'stop' } }
  }
  try{
    $agDown= $script:AgBlock -and $script:AgBlock.kind -in @('hung','nowindow')   # к зависшему окну UIA не обращаемся
    if(-not $agDown -and -not $script:Paused -and $Cfg.AgQueueCheckSec -gt 0 -and ((Get-Date)-$script:LastQueueCheck).TotalSeconds -ge $Cfg.AgQueueCheckSec){ $script:LastQueueCheck=Get-Date; try{ Check-AgQueue }catch{ Log "Очередь Antigravity: $($_.Exception.Message)" }; if($Cfg.AgTransport -eq 'mailbox'){ try{ [void](Check-MailboxAcks) }catch{} } }
    if(-not $agDown -and -not $script:Paused -and $Cfg.AcceptAllEverySec -gt 0 -and ((Get-Date)-$script:LastAccept).TotalSeconds -ge $Cfg.AcceptAllEverySec){ $script:LastAccept=Get-Date; if($Cfg.AutoAcceptAll){ try{ Try-AcceptAll -Report | Out-Null }catch{ Log "Accept all: $($_.Exception.Message)" } } }
    Nap $Cfg.PollSec
  }catch{ if((Get-ErrorKind $_) -eq 'stop'){ Log 'Остановлено.'; return 'stop' }; Log "Ошибка в цикле: $($_.Exception.Message)" }
  'ok'
}
$script:LastAccept=Get-Date
