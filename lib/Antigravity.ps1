# ===== GGskript v2: Antigravity — окно, безопасная отправка (UIA с проверками) и «почтовый ящик» =====

function Ag-GetWindowInfo{
  $w=Select-TopWindow -Windows @(Get-TopWindows) -ProcessNames @($Cfg.AgProcess) -ExcludeTitleRx '^(MSCTFIME UI|Default IME)$'
  $w
}
function Ag-GetWindow{ $w=Ag-GetWindowInfo; if($w){ $w.h } else { $null } }
# Electron строит дерево UIA лениво: первый запрос после включения доступности может не увидеть поле — короткий повтор.
function AgUia-FindInput($h,[int]$Tries=3){
  for($i=0;$i -lt [Math]::Max(1,$Tries);$i++){
    if($i){ Start-Sleep -Milliseconds 400 }
    $in=Uia-FindFirst -Root $h -Name $Cfg.AgInputName
    if($in -and -not (Uia-IsOffscreen $in)){ return $in }
  }
  $null
}
# Ждёт условие до $Sec секунд (опрос раз в 300 мс). Возвращает $true/$false.
function Wait-Until([scriptblock]$Cond,[double]$Sec=5,[int]$StepMs=300){
  $n=[Math]::Max(1,[int][Math]::Ceiling($Sec*1000/$StepMs))
  for($i=0;$i -lt $n;$i++){ if(& $Cond){ return $true }; Start-Sleep -Milliseconds $StepMs }
  [bool](& $Cond)
}

# ---------- Доступность Antigravity: зависание / нет окна ----------
function New-AgBlocked([string]$Kind,[string]$Message,[string]$Detail=''){ [GG.AgBlockedException]::new($Kind,$Message,$Detail) }
function Get-AgGhost{ @(Get-TopWindows | Where-Object { ($_.class -eq 'Ghost' -or ([string]$_.title) -match '\((Не отвечает|Not Responding)\)\s*$') -and ([string]$_.title) -match 'Antigravity' }) | Select-Object -First 1 }
# Окно ищется заново при каждом вызове (после перезапуска Antigravity — новый hwnd/pid, старые ссылки не держим).
# kind: ok | hung | nowindow. Сигналы: IsHungAppWindow, WM_NULL с таймаутом, окно-призрак «(Не отвечает)», Process.Responding.
function Get-AgHealth{
  $r=@{ ok=$true; kind='ok'; reasons=@(); h=$null; pid=$null; title='' }
  $w=Ag-GetWindowInfo; $g=Get-AgGhost
  if(-not $w){
    $r.ok=$false
    if($g){ $r.kind='hung'; $r.reasons=@("окно-призрак «$($g.title)»") } else { $r.kind='nowindow'; $r.reasons=@('окно Antigravity не найдено') }
    return $r
  }
  $r.h=$w.h; $r.title=[string]$w.title; $r.pid=$w.pid
  $re=@()
  if(Test-WindowHung $w.h){ $re+='IsHungAppWindow=true' }
  if(-not (Test-WindowPing $w.h $Cfg.AgHangTimeoutMs)){ $re+="окно не ответило на WM_NULL за $($Cfg.AgHangTimeoutMs) мс" }
  if($g){ $re+="окно-призрак «$($g.title)»" }
  if(-not $re.Count -and $w.pid -and (Test-ProcessResponding $w.pid) -eq $false){ $re+="процесс $($w.pid): Responding=false" }
  if($re.Count){ $r.ok=$false; $r.kind='hung'; $r.reasons=$re }
  $r
}
function Assert-AgReady{
  if($Cfg.AgTransport -eq 'mailbox'){ return }
  $hl=Get-AgHealth
  if($hl.kind -eq 'nowindow'){ throw (New-AgBlocked 'nowindow' 'Окно Antigravity не найдено (закрыто или перезапускается)' ($hl.reasons -join '; ')) }
  if(-not $hl.ok){ throw (New-AgBlocked 'hung' "Antigravity не отвечает: $($hl.reasons -join '; ')" ($hl.reasons -join '; ')) }
  $hl
}
# Текст поля чата: ValuePattern, если он непустой, иначе TextPattern. Пустое поле Antigravity (ComboBox 'Message input')
# отдаёт Value='' и TextPattern='Message input' — это имя/плейсхолдер поля, а не текст (причина ложной тревоги 18:35).
function AgUia-ReadField($in){
  $name=[string](Uia-Name $in); $v=[string](Uia-GetValue $in)
  if($v.Trim()){ $t=$v; $via='value' } else { $t=[string](Uia-GetText $in); $via='text' }
  $tt=$t.Trim()
  $ph=[bool]($tt -and (($name.Trim() -and $tt -eq $name.Trim()) -or $tt -match $Cfg.AgPlaceholderRx))
  @{ text=$(if($ph){ '' } else { $t }); raw=$t; placeholder=$ph; via=$via }
}
function Format-FieldDiag($f){ if(-not $f){ return 'нет данных' }; "$($f.via): $(([string]$f.raw).Length) симв.$(if($f.placeholder){' (плейсхолдер)'}) «$(Format-Short ([string]$f.raw) 40)»" }
function Get-First40([string]$t){ $x=(([string]$t) -replace '\s+',' ').Trim(); if($x.Length -gt 40){ $x.Substring(0,40)+'…' } else { $x } }

# Отправка текста в чат агента. Enter нажимается ТОЛЬКО после подтверждения, что текст в поле чата.
# Не отправлено — GG.AgBlockedException (kind hung|nowindow|foreign|unknown) или GG.RelayNotSentException; безопасно повторить.
function AgUia-Send{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='')
  $hl=Assert-AgReady; $h=$hl.h
  $marker=Get-Marker $Text
  $hasMarker={ param($t) [bool]($marker -and ([string]$t).IndexOf($marker,[StringComparison]::OrdinalIgnoreCase) -ge 0) }
  Invoke-WithFocus $h {
    $sw=[Diagnostics.Stopwatch]::StartNew(); $in=AgUia-FindInput $h; $findMs=$sw.ElapsedMilliseconds
    $viaCoords=$false
    if(!$in){
      if($findMs -ge $Cfg.AgUiaSlowMs){ throw (New-AgBlocked 'hung' "Antigravity не отвечает: поиск поля чата через UIA занял $findMs мс" "UIA $findMs мс") }
      if(-not $Cfg.AgCoordFallback){ throw (New-AgBlocked 'unknown' "Поле чата Antigravity ('$($Cfg.AgInputName)') не найдено — НЕ отправляю (клик по координатам выключен)" "окно «$($hl.title)», pid $($hl.pid), поиск $findMs мс") }
      Log 'Поле чата Antigravity не найдено — клик по координатам (AgCoordFallback=true)'
      ClickRel $h $Cfg.AgInputX $Cfg.AgInputY; $viaCoords=$true
      $in=Uia-Focused
    } else {
      if($findMs -ge $Cfg.AgUiaSlowMs){ Log "Antigravity: поиск поля чата занял $findMs мс (медленно)" }
      [void](Uia-Focus $in); [void](Uia-ClickEl $in)
      if(-not (Uia-IsFocused $in)){
        $h2=Get-AgHealth; if(-not $h2.ok){ throw (New-AgBlocked 'hung' "Antigravity не отвечает: фокус не встал в поле чата; $($h2.reasons -join '; ')" ($h2.reasons -join '; ')) }
        throw [GG.RelayNotSentException]::new('Фокус не в поле чата Antigravity — НЕ отправляю')
      }
    }
    $reads=@(); for($i=0;$i -lt [Math]::Max(1,[int]$Cfg.AgFieldReads);$i++){ if($i){ Start-Sleep -Milliseconds 250 }; $reads+=,(AgUia-ReadField $in) }
    $pre=[string]$reads[-1].text
    if(@($reads | ForEach-Object { [string]$_.text } | Select-Object -Unique).Count -gt 1){ throw (New-AgBlocked 'foreign' "В поле чата Antigravity текст меняется (кто-то печатает): '$(Get-First40 $pre)' — не трогаю" (Get-First40 $pre)) }
    if($pre.Trim()){
      if(& $hasMarker $pre){ Log 'В поле чата Antigravity остался наш прошлый текст — очищаю'; ClearField; $pre='' }
      else { throw (New-AgBlocked 'foreign' "В поле чата Antigravity чужой текст: '$(Get-First40 $pre)' — не трогаю, НЕ отправляю" (Get-First40 $pre)) }
    }
    Use-TempClipboard { Set-ClipText $Text; Paste }
    $ok=Wait-Until { & $hasMarker (AgUia-ReadField $in).text } 6
    if(-not $ok){
      $after=AgUia-ReadField $in
      $h3=Get-AgHealth
      if(-not $h3.ok){ throw (New-AgBlocked 'hung' "Antigravity не отвечает (после вставки): $($h3.reasons -join '; ')" ($h3.reasons -join '; ')) }
      if(-not $after.text -and -not $viaCoords -and $Cfg.AgVerifyPaste -eq 'lenient'){ Log 'Текст поля Antigravity не читается через UIA — отправляю без проверки (AgVerifyPaste=lenient)' }
      elseif([string]$after.text -eq $pre){ throw (New-AgBlocked 'hung' 'Antigravity не принимает ввод: после вставки поле не изменилось (Enter не нажимал)' "до: «$(Get-First40 $pre)», после: $(Format-FieldDiag $after)") }
      else { throw (New-AgBlocked 'unknown' 'Текст не появился в поле чата Antigravity — НЕ отправлен (Enter не нажимал)' "после вставки: $(Format-FieldDiag $after); поиск поля $findMs мс") }
    }
    PressEnter
    $gone=Wait-Until { -not (& $hasMarker (AgUia-ReadField $in).text) } 6
    if(-not $gone){ throw (New-AgBlocked 'unknown' 'После Enter текст остался в поле Antigravity — сообщение не ушло' (Format-FieldDiag (AgUia-ReadField $in))) }
  }
  $script:AgPending=@{ key=(Get-NormKey $Text 40); label=$Label; time=Get-Date }
  Log "Отправлено в Antigravity ($Label), проверено: текст был в поле и ушёл после Enter"
}
# Только чтение (для -testag): здоровье окна и что в поле. Без фокуса, кликов, буфера.
function Get-AgDiag{
  $d=[ordered]@{ health=(Get-AgHealth); findMs=$null; found=$false; reads=@(); verdict='' }
  $hl=$d.health
  if($hl.kind -eq 'nowindow'){ $d.verdict='нет окна'; return $d }
  if(-not $hl.ok){ $d.verdict="зависло: $($hl.reasons -join '; ')"; return $d }
  $sw=[Diagnostics.Stopwatch]::StartNew(); $in=AgUia-FindInput $hl.h; $d.findMs=$sw.ElapsedMilliseconds; $d.found=[bool]$in
  if(!$in){ $d.verdict= if($d.findMs -ge $Cfg.AgUiaSlowMs){ "зависло: UIA $($d.findMs) мс" } else { 'поле не найдено' }; return $d }
  for($i=0;$i -lt [Math]::Max(1,[int]$Cfg.AgFieldReads);$i++){ if($i){ Start-Sleep -Milliseconds 250 }; $d.reads+=,(AgUia-ReadField $in) }
  $tx=@($d.reads | ForEach-Object { [string]$_.text } | Select-Object -Unique)
  $d.verdict= if($tx.Count -gt 1){ 'текст меняется (кто-то печатает)' } elseif(([string]$tx[0]).Trim()){ "чужой текст: '$(Get-First40 $tx[0])'" } else { 'поле пустое — готово к вставке' }
  $d
}
# ---------- Автоподтверждение запроса разрешения через UIA (без фокуса и мыши: только SelectionItem/Invoke) ----------
function Uia-IsSelected($el){ try{ [bool]$el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }catch{ $null } }
function AgUia-AllowPrompt($h){
  # дешёвая предпроверка: есть ли видимая кнопка Submit (поиск только по кнопкам, как у Accept all)
  $subs=@(Uia-FindAll -Root $h -ControlType 'Button' | Where-Object { -not (Uia-IsOffscreen $_) -and (Test-AutoAllowSubmit (Uia-Name $_)) -and (Uia-IsEnabled $_) })
  if(-not $subs.Count){ return @{ found=$false } }
  $opt=@(Uia-FindAll -Root $h -NameRx $Cfg.AutoAllowOptionRx | Where-Object { -not (Uia-IsOffscreen $_) -and (Test-AutoAllowOption (Uia-Name $_)) }) | Select-Object -First 1
  if(-not $opt){
    # Submit видна, а нужного варианта нет — сообщаю, что вижу рядом (для диагностики; ничего не нажимаю)
    $near=@(Uia-FindAll -Root $h -NameRx '(?i)allow|разреш' | Where-Object { -not (Uia-IsOffscreen $_) } | ForEach-Object { "[$(Uia-CtlType $_)] $(Format-Short (Uia-Name $_) 50)" } | Select-Object -First 6)
    return @{ found=$true; ok=$false; why="вижу кнопку Submit, но варианта «Yes, allow this time» нет$(if($near.Count){' (рядом: '+($near -join '; ')+')'}else{' (элементов с «allow» не видно через UIA)'})" }
  }
  $name=(Uia-Name $opt).Trim(); $orect=Uia-Rect $opt
  $done=$false; $el=$opt
  for($i=0;$i -lt 3 -and $el -and -not $done;$i++){
    $en=Uia-Name $el; if($i -and $en -and ($en -match $script:AutoAllowDenyRx)){ break }   # не подниматься в общий контейнер со «always»/«No»
    if(Uia-Select $el){ $done=$true; if((Uia-IsSelected $el) -eq $false){ return @{ found=$true; ok=$false; why='вариант не выбрался (UIA)' } } }
    elseif(Uia-Invoke $el){ $done=$true }
    else { $el=Uia-Parent $el }
  }
  if(-not $done){ return @{ found=$true; ok=$false; why='вариант не поддерживает Invoke/SelectionItem — мышью без фокуса не нажимаю' } }
  Start-Sleep -Milliseconds 250
  $c=Select-NearestBelow $orect @(Uia-FindAll -Root $h -ControlType 'Button' | Where-Object { -not (Uia-IsOffscreen $_) -and (Test-AutoAllowSubmit (Uia-Name $_)) -and (Uia-IsEnabled $_) } | ForEach-Object { @{ el=$_; rect=(Uia-Rect $_) } })
  if(-not $c){ return @{ found=$true; ok=$true; opt=$name; note='Submit исчезла после выбора' } }
  if(-not (Uia-Invoke $c.el)){ return @{ found=$true; ok=$false; why='Submit не нажалась через Invoke' } }
  @{ found=$true; ok=$true; opt=$name }
}
# Перезапуск зависшего Antigravity (только при AgAutoRestartMin>0; по умолчанию выключено).
function Restart-Antigravity($ProcessId){
  $p=Get-Process -Id $ProcessId -EA Stop; $exe=$p.Path
  if(-not $exe){ throw 'не удалось узнать путь к Antigravity' }
  Stop-Process -Id $ProcessId -Force -EA Stop
  Start-Sleep -Seconds 3
  Start-Process -FilePath $exe | Out-Null
  $exe
}

# ---------- «Почтовый ящик» ----------
function Get-InboxTaskName([string]$Name){
  $b=([string]$Name -split '[\\/]')[-1] -replace '\.md$',''; if(-not $b){ $b='task' }
  $b=($b -replace '[^\w\-\.]','_'); if($b.Length -gt 80){ $b=$b.Substring(0,80) }
  "task_$b.md"
}
function New-InboxTask{
  param([Parameter(Mandatory)][string]$InboxDir,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Text)
  if(-not (Test-Path -LiteralPath $InboxDir)){ New-Item -ItemType Directory -Force -Path $InboxDir | Out-Null }
  $p=Join-Path $InboxDir (Get-InboxTaskName $Name)
  foreach($x in "$p.taken","$p.ack"){ if(Test-Path -LiteralPath $x){ Remove-Item -LiteralPath $x -Force } }
  Write-AtomicText -Path $p -Text $Text -NoBom -NoBackup
  [IO.Path]::GetFullPath($p)
}
function Get-MailboxTrigger([string]$Path){
  "GGskript: новое задание от старшей модели в файле $Path . Прочитай файл целиком и выполни задание. В начале работы переименуй файл, добавив к имени .taken (или создай рядом файл с суффиксом .ack). Отчёт сохрани как обычно."
}
function Test-InboxAck([string]$Path){ (Test-Path -LiteralPath "$Path.taken") -or (Test-Path -LiteralPath "$Path.ack") }
$script:MailboxPending=@{}
function AgMailbox-Send{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='',[string]$Name)
  if(-not $Name){ $Name="msg_{0:yyyyMMdd_HHmmss}" -f (Get-Date) }
  $p=New-InboxTask -InboxDir $Cfg.InboxDir -Name $Name -Text $Text
  Log "Почтовый ящик: задание записано в $p"
  AgUia-Send -Text (Get-MailboxTrigger $p) -Label $Label
  $script:MailboxPending[$p]=@{ time=Get-Date; label=$Label; warned=$false }
  $p
}
# Проверка подтверждений от агента; возвращает список просроченных (без подтверждения дольше MailboxAckSec).
function Check-MailboxAcks{
  $late=@()
  foreach($p in @($script:MailboxPending.Keys)){
    if(Test-InboxAck $p){ Log "Почтовый ящик: агент взял задание $([IO.Path]::GetFileName($p))"; $script:MailboxPending.Remove($p); continue }
    $it=$script:MailboxPending[$p]
    if(-not $it.warned -and ((Get-Date)-$it.time).TotalSeconds -ge $Cfg.MailboxAckSec){ $it.warned=$true; $late+=$p
      $m="⚠️ Агент Antigravity не подтвердил задание $([IO.Path]::GetFileName($p)) за $($Cfg.MailboxAckSec) сек (нет .taken/.ack)"; Log $m; Tg-Send $m }
  }
  $late
}
# Единая точка отправки в Antigravity.
# Пункт 27B: AgTransport='cdp' — без фокуса; откат на UIA только если CDP Antigravity недоступен (одно сообщение в Telegram).
$script:AgCdpDownSaid=$false
$script:AgCdpDownUntil=$null
function Ag-Send{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='',[string]$Name)
  Ag-SendCore -Text $Text -Label $Label -Name $Name
  try{ if($script:St){ $script:St.lastAgAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Save-State } }catch{}
}
function Ag-SendCore{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='',[string]$Name)
  if($Cfg.AgTransport -eq 'mailbox'){ [void](AgMailbox-Send -Text $Text -Label $Label -Name $Name); return }
  if($Cfg.AgTransport -eq 'cdp' -and -not ($script:AgCdpDownUntil -and (Get-Date) -lt $script:AgCdpDownUntil -and $Cfg.AgCdpFallback)){
    try{
      AgCdp-Send -Text $Text -Label $Label
      if($script:AgCdpDownSaid){ $script:AgCdpDownSaid=$false; $m='✅ Antigravity: CDP снова доступен — отправляю без фокуса и клавиатуры.'; Log $m; try{ Tg-Send $m | Out-Null }catch{} }
      return
    }catch{
      if(-not $Cfg.AgCdpFallback -or -not (Test-CdpUnreachable $_)){ throw }
      $sec=[int]$Cfg.CdpRecheckSec; if($sec -lt 10){ $sec=10 }; $script:AgCdpDownUntil=(Get-Date).AddSeconds($sec)
      if(-not $script:AgCdpDownSaid){ $script:AgCdpDownSaid=$true; Log "Antigravity: CDP-порт $($Cfg.AgCdpPort) не отвечает (Antigravity запущен обычным способом) — вставляю через окно (UIA)"; try{ Tg-Send "ℹ️ Antigravity запущен без порта отладки $($Cfg.AgCdpPort) — вставляю через окно (UIA: фокус, клавиатура, буфер)." | Out-Null }catch{} }
    }
  }
  AgUia-Send -Text $Text -Label $Label
}
