# ===== GGskript v2: пункт 23 — выключение компьютера по команде из Telegram =====
# Всегда с подтверждением (inline «Да/Нет» или текстом «да»), только из своего чата Telegram (общая проверка chat_id в Poll-Tg).
# План хранится в relay_shutdown.json (переживает перезапуск GGskript). Сам вызов shutdown.exe — Invoke-ShutdownExe (Platform.Win), в тестах — Mock.
# Важно: у shutdown.exe при /t > 0 Windows всегда подразумевает /f (принудительное закрытие программ). Поэтому:
#   ShutdownForce=$false (по умолчанию) — GGskript сам в назначенное время вызывает «shutdown /s /t 0» (без /f): программы
#     с несохранённой работой могут остановить выключение; GGskript должен работать в это время;
#   ShutdownForce=$true — таймер Windows «shutdown /s /f /t N»: сработает и без GGskript, программы закрываются принудительно.
# Отмена — «shutdown /a» (для таймера Windows) + удаление плана.
$script:ShutPlan=$null; $script:ShutLoaded=$false
$script:ShutComment='GGskript: выключение по команде из Telegram'
function Get-ShutdownPlan{
  if(-not $script:ShutLoaded){
    $script:ShutLoaded=$true; $script:ShutPlan=$null
    try{ $r=Read-JsonWithBackup $Cfg.ShutdownFile; $d=$r.Data
      if($d -and $d.at){ $script:ShutPlan=@{ at=$(if($d.at -is [datetime]){ [datetime]$d.at }else{ [datetime]::ParseExact([string]$d.at,'s',[Globalization.CultureInfo]::InvariantCulture) }); force=[bool]$d.force; warned=[bool]$d.warned; created=[string]$d.created; how=[string]$d.how } }
    }catch{ Log "Выключение: не удалось прочитать план ($($_.Exception.Message))" }
  }
  $script:ShutPlan
}
function Save-ShutdownPlan($P){
  $script:ShutPlan=$P; $script:ShutLoaded=$true
  $o=[ordered]@{ at=$P.at.ToString('s'); force=[bool]$P.force; warned=[bool]$P.warned; created=[string]$P.created; how=[string]$P.how }
  Write-AtomicText -Path $Cfg.ShutdownFile -Text ($o | ConvertTo-Json) -NoBackup
}
function Clear-ShutdownPlan{
  $script:ShutPlan=$null; $script:ShutLoaded=$true
  foreach($f in @($Cfg.ShutdownFile,"$($Cfg.ShutdownFile).bak")){ Remove-Item -LiteralPath $f -Force -EA 0 }
}
function Get-ShutModeText([bool]$Force){
  if($Force){ 'таймер Windows (сработает, даже если GGskript выключен); программы будут закрыты ПРИНУДИТЕЛЬНО — несохранённое пропадёт' }
  else{ 'выключит GGskript (он должен работать в это время), без принудительного закрытия: программы с несохранённой работой могут помешать выключению' }
}
# Команда «выключи компьютер …» -> вопрос с подтверждением.
function Request-Shutdown($Spec,[string]$Source='tg',[int64]$ReplyTo=0){
  if($Source -ne 'tg'){ Tg-Send 'Выключение компьютера — только командой из Telegram (с подтверждением).' | Out-Null; return }
  if(-not $Cfg.ShutdownEnabled){ Tg-Send 'Выключение компьютера по команде отключено (ShutdownEnabled=false в relay_settings.json).' | Out-Null; return }
  if(-not $Spec -or $Spec.mode -eq 'bad'){ Tg-Send "Не понял время выключения$(if($Spec.raw){" («$($Spec.raw)»)"}). Примеры: «выключи компьютер», «выключи компьютер в 14-00» (или 14:00, 14.00, «в 14»), «выключи компьютер через 30 минут», «через 2 часа», /shutdown 14:00, /shutdown +30." | Out-Null; return }
  $now=Get-Date; $r=Resolve-ShutdownTime $Spec $now ([int]$Cfg.ShutdownNowDelaySec)
  $when= if($Spec.mode -eq 'now'){ "сейчас (через $($Cfg.ShutdownNowDelaySec) сек после подтверждения)" } else { "$(Format-ShutWhen $r.at $now) (через $(Format-ShutLeft $r.at $now))" }
  $note= if($Spec.mode -eq 'at' -and $r.tomorrow){ "`nСегодня $($r.at.ToString('HH:mm')) уже прошло — значит, завтра." } else { '' }
  $old=Get-ShutdownPlan; $ov= if($old){ "`nУже запланировано на $(Format-ShutWhen $old.at $now) — заменю." } else { '' }
  $msg="🔌 Выключить компьютер $when?$note$ov`nСпособ: $(Get-ShutModeText ([bool]$Cfg.ShutdownForce)).`nПодтвердите в течение $($Cfg.ShutdownConfirmMin) мин (кнопкой или словом «да»), иначе — отмена."
  [void](New-TgPrompt -Kind 'shutdown' -Text $msg -Buttons 'Да, выключить=yes|Нет=no' -Data @{ spec=$Spec; at=$r.at } -TimeoutMin ([double]$Cfg.ShutdownConfirmMin) -ReplyTo $ReplyTo)
}
# Подтверждено: планируем (время «сейчас»/«через N» считаем от момента запроса, но не раньше чем через 30 сек).
function Confirm-Shutdown($D){
  $now=Get-Date
  $at= if($D.spec.mode -eq 'now'){ $now.AddSeconds([int]$Cfg.ShutdownNowDelaySec) } else { [datetime]$D.at }
  if($at -lt $now.AddSeconds(30)){ $at=$now.AddSeconds(30) }
  $sec=[int64][math]::Ceiling(($at-$now).TotalSeconds)
  if($sec -gt 315360000){ Tg-Send 'Слишком далеко: Windows разрешает не больше 10 лет.' | Out-Null; return }
  $force=[bool]$Cfg.ShutdownForce
  $old=Get-ShutdownPlan
  if($old -and $old.force){ [void](Invoke-ShutdownExe @('/a')) }   # заменяем прежний таймер Windows
  if($force){
    $r=Invoke-ShutdownExe @('/s','/f','/t',[string]$sec,'/c',$script:ShutComment)
    if($r.code -ne 0){ $m="❌ Не удалось запланировать выключение: shutdown.exe вернул $($r.code)$(if($r.out){" ($($r.out))"})"; Log $m; Tg-Send $m | Out-Null; return }
  }
  $warned=($sec -le [int]$Cfg.ShutdownWarnSec)
  Save-ShutdownPlan @{ at=$at; force=$force; warned=$warned; created=$now.ToString('s'); how=$(if($force){'windows'}else{'ggskript'}) }
  $m="✅ Выключение компьютера запланировано: $(Format-ShutWhen $at $now), точное время $($at.ToString('dd.MM.yyyy HH:mm:ss')) (через $(Format-ShutLeft $at $now)).`nСпособ: $(Get-ShutModeText $force).`nОтменить: «отмени выключение» или /shutdown_cancel. Узнать: «когда выключение»."
  if(-not $warned){ $m+="`nЗа $([math]::Round($Cfg.ShutdownWarnSec/60)) мин до выключения предупрежу здесь$(if($force){' (если GGskript будет работать)'})." }
  Log "Выключение запланировано на $($at.ToString('dd.MM HH:mm:ss')) ($(if($force){'shutdown /s /f /t '+$sec}else{'GGskript, shutdown /s /t 0'}))"; Tg-Send $m | Out-Null
}
function Cancel-Shutdown{
  $p=Get-ShutdownPlan
  $r=$null; if(-not $p -or $p.force){ $r=Invoke-ShutdownExe @('/a') }   # таймер Windows (или неизвестный план) — снимаем
  Clear-ShutdownPlan
  if($p){ $m="🟢 Выключение отменено (было запланировано на $(Format-ShutWhen $p.at))."; Log $m; Tg-Send $m | Out-Null }
  elseif($r -and $r.code -eq 0){ $m='🟢 Отменил выключение компьютера, запланированное в Windows (не через GGskript).'; Log $m; Tg-Send $m | Out-Null }
  else{ Tg-Send 'Выключение не запланировано — отменять нечего.' | Out-Null }
}
function Get-ShutdownStatusText{
  $p=Get-ShutdownPlan
  if(-not $p){ return 'Выключение компьютера не запланировано.' }
  "🔌 Выключение запланировано: $(Format-ShutWhen $p.at), точное время $($p.at.ToString('dd.MM.yyyy HH:mm:ss')) (через $(Format-ShutLeft $p.at)).`nСпособ: $(Get-ShutModeText $p.force).`nОтменить: «отмени выключение» или /shutdown_cancel."
}
# Вызывается из Pump: предупреждение за ShutdownWarnSec, выполнение (режим GGskript), пропуск при опоздании.
function Check-Shutdown([datetime]$Now=(Get-Date)){
  $p=Get-ShutdownPlan; if(-not $p){ return }
  $left=($p.at-$Now).TotalSeconds
  if($p.force){
    if($left -lt -120){ Log 'Выключение: время таймера Windows прошло — план удалён'; Clear-ShutdownPlan; return }
  } elseif($left -le 0){
    if(-$left -gt 60*[double]$Cfg.ShutdownLateMin){
      Clear-ShutdownPlan; $m="⚠️ Выключение на $($p.at.ToString('dd.MM HH:mm')) пропущено: GGskript в это время не работал. Компьютер НЕ выключаю — если нужно, дайте команду снова."; Log $m; Tg-Send $m | Out-Null; return
    }
    Clear-ShutdownPlan   # сначала удаляем план — чтобы после перезапуска не выключать повторно
    $m='🔌 Выключаю компьютер (shutdown /s /t 0, без принудительного закрытия). Если программа с несохранённой работой помешает — выключение остановится на её запросе.'; Log $m; Tg-Send $m | Out-Null
    $r=Invoke-ShutdownExe @('/s','/t','0','/c',$script:ShutComment)
    if($r.code -ne 0){ $m="❌ Выключить не удалось: shutdown.exe вернул $($r.code)$(if($r.out){" ($($r.out))"})"; Log $m; Tg-Send $m | Out-Null }
    return
  }
  if(-not $p.warned -and $left -le [double]$Cfg.ShutdownWarnSec){
    $p.warned=$true; Save-ShutdownPlan $p
    [void](New-TgPrompt -Kind 'shutwarn' -Text "⚠️ Через $(Format-ShutLeft $p.at $Now) ($($p.at.ToString('HH:mm:ss'))) выключу компьютер. Сохраните работу.$(if(-not $p.force){' Программы с несохранённой работой могут помешать выключению.'})" -Buttons 'Отменить выключение=abort' -TimeoutMin 5)
  }
}
