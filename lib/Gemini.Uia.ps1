# ===== GGskript v2: Gemini через UI Automation (прежний способ, с исправлениями) =====

# Окно Chrome с Gemini: все верхние окна (EnumWindows), класс Chrome_WidgetWin_1, заголовок активной вкладки;
# если не нашли и GeminiSelectTab — ищем вкладку «*Gemini*» через UIA и переключаемся на неё.
# Пункт 25E: любой Chromium-браузер из GeminiBrowsers (Chrome, Яндекс Браузер, Edge); класс окна Chrome_WidgetWin_1 / Chrome_Yandex_WidgetWin_1.
$script:GeminiBrowser=''; $script:GeminiBrowserLogged=''
function Note-GeminiBrowser($w){
  $script:GeminiBrowser=Get-BrowserName $w.proc
  if($script:GeminiBrowserLogged -ne "$($w.proc)|$($w.h)"){ $script:GeminiBrowserLogged="$($w.proc)|$($w.h)"; Log "Gemini: окно найдено — $($script:GeminiBrowser) (процесс $($w.proc), «$(Remove-BrowserSuffix $w.title)»)" }
}
function Get-GeminiBrowserName{ if($script:GeminiBrowser){ $script:GeminiBrowser } else { (@(Get-GeminiBrowsers) | ForEach-Object { Get-BrowserName $_ }) -join ' / ' } }
function Find-GeminiWindow{
  $wins=@(Get-TopWindows)
  $w=Select-GeminiWindow $wins
  if($w){ Note-GeminiBrowser $w; return $w.h }
  if(-not $Cfg.GeminiSelectTab){ return $null }
  foreach($c in @(Get-BrowserWindows $wins)){
    $tab=@(Uia-FindAll -Root $c.h -ControlType 'TabItem' | Where-Object { (Uia-Name $_) -like "*$($Cfg.GeminiTitle)*" -and -not (Test-UsageTabName (Uia-Name $_)) }) | Select-Object -First 1   # пункт 26: вкладку лимитов за чат не принимаю
    if($tab -and ((Uia-Select $tab) -or (Uia-Invoke $tab))){ Start-Sleep -Milliseconds 600; Note-GeminiBrowser $c; Log "Gemini: переключил вкладку $(Get-BrowserName $c.proc) на «$(Uia-Name $tab)»"; return $c.h }
  }
  $null
}
function GemUia-Buttons($h){ @(Uia-FindAll -Root $h -ControlType 'Button') }
function GemUia-FindCopyButtons($h){ @(GemUia-Buttons $h | Where-Object { (Uia-Name $_) -match $Cfg.RxCopy }) }
function GemUia-IsGenerating($h){ [bool](@(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.RxStop).Count) }
function GemUia-CountPrompts($h){ @(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.RxPrompt).Count }
function GemUia-FindInput($h){
  @(Uia-FindAll -Root $h -ControlType 'Edit' | Where-Object { (Uia-Class $_) -match $Cfg.GeminiInputClassRx -or (Uia-Name $_) -match $Cfg.GeminiInputNameRx }) | Select-Object -Last 1
}
function GemUia-InputHasText($h,[string]$Needle){
  $e=GemUia-FindInput $h; if(!$e){ return $false }
  $t=[string](Uia-GetText $e)
  if($Needle){ return ($t.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) }
  ($t.Trim().Length -gt 0) -or ((Uia-Class $e) -notmatch 'ql-blank')
}
# Фокус в поле ввода. $true — фокус подтверждён UIA.
function GemUia-FocusInput($h){
  $inp=GemUia-FindInput $h
  if(!$inp){ Log 'Поле ввода Gemini через UIA не найдено, кликаю по координатам'; ClickRel $h $Cfg.GeminiInputX $Cfg.GeminiInputY; return $false }
  [void](Uia-Focus $inp); [void](Uia-ClickEl $inp)
  $ok=Uia-IsFocused $inp
  if(-not $ok){ $f=Uia-Focused; Log "Фокус не в поле Gemini, а в: '$(Uia-Name $f)'" }
  $ok
}
function GemUia-GetModel($h){
  $b=@(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.RxModel) | Select-Object -First 1
  if(!$b){ return $null }
  ((Uia-Name $b) -replace '^.*(currently|используется|сейчас)[:\s]*','')
}
# Пункт 25D: подпись блока читается ТОЛЬКО из шапки этого блока (code-block-decoration), а не из текста кода.
# Путь вверх от кнопки: сначала шапка (кнопка лежит в ней) -> её первый Text; иначе контейнер блока -> его шапка;
# шапки нет -> только Text, стоящие ДО тела кода (pre/code/formatted-code…). Не прочитали -> '' (= НЕ Markdown).
$script:GemCodeHeaderRx='code-block-decoration|(^|\s)header-formatted(\s|$)'
$script:GemCodeBlockRx='(^|\s)code-block(\s|$)'
$script:GemCodeBodyRx='formatted-code-block-internal-container|code-container|(^|\s)(pre|code)(\s|$)'
function GemUia-HeaderText($hdr){
  $t=@(Uia-FindAll -Root $hdr -ControlType 'Text' | Where-Object { (Uia-Name $_).Trim() }) | Select-Object -First 1
  if($t){ Normalize-CodeLang (Uia-Name $t) } else { '' }
}
function GemUia-CodeHeaderLabel($blk){
  $all=@(Uia-FindAll -Root $blk)
  $hdr=@($all | Where-Object { (Uia-Class $_) -match $script:GemCodeHeaderRx }) | Select-Object -First 1
  if($hdr){ $l=GemUia-HeaderText $hdr; if($l){ return $l } }
  # Chromium (Яндекс/Chrome, 19.10): в дереве UIA подпись — Text ПЕРЕД кнопками шапки, сама шапка Text не содержит.
  # Берём только Text до первой кнопки/тела кода: текст кода идёт после кнопок и сюда не попадает.
  foreach($x in $all){
    if((Uia-Class $x) -match $script:GemCodeBodyRx){ break }
    $ct=Uia-CtlType $x
    if($ct -eq 'Button'){ break }
    if($ct -eq 'Text' -and (Uia-Name $x).Trim()){ return (Normalize-CodeLang (Uia-Name $x)) }
  }
  ''
}
function GemUia-CodeBlockLang($btn){
  try{ $e=$btn
    for($i=0;$i -lt 8 -and $e;$i++){
      $e=Uia-Parent $e; if(!$e){ break }
      $c=Uia-Class $e
      if($c -match $script:GemCodeHeaderRx){ $l=GemUia-HeaderText $e; if($l){ return $l }; continue }   # в шапке нет Text — ищу в контейнере блока
      if($c -match $script:GemCodeBlockRx){ return (GemUia-CodeHeaderLabel $e) }
    } }catch{}
  ''
}
# Кнопки «Копировать код» только в ПОСЛЕДНЕМ ответе (после последней «Скопировать запрос»).
function GemUia-FindCodeCopyButtonOnce($h,[switch]$Quiet){
  $all=@(GemUia-Buttons $h); $start=0
  for($i=$all.Count-1;$i -ge 0;$i--){ if((Uia-Name $all[$i]) -match $Cfg.RxPrompt){ $start=$i; break } }
  $cands=@(); for($i=$start;$i -lt $all.Count;$i++){ if((Uia-Name $all[$i]) -match $Cfg.RxCode){ $cands+=$all[$i] } }
  $langs=@($cands | ForEach-Object { GemUia-CodeBlockLang $_ })
  $script:LastCodeLangs=$langs
  if(-not $Quiet){ Log "Блоков кода в последнем ответе: $($cands.Count) $(($langs | ForEach-Object { "'$_'" }) -join ', ')" }
  $idx=Select-CodeBlockIndex -Langs $langs -Lang $Cfg.CodeBlockLang -Pick $Cfg.CodeBlockPick
  @{ btn=$(if($idx -ge 0){ $cands[$idx] }else{ $null }); all=$all; start=$start }
}
function GemUia-FindCodeCopyButton($h){
  $r=GemUia-FindCodeCopyButtonOnce $h; if($r.btn){ return $r.btn }
  $all=$r.all; $start=$r.start; $rx="$($Cfg.RxCopy)|$($Cfg.RxCode)|$($Cfg.RxPrompt)"
  $steps=@(); for($i=$all.Count-1;$i -ge $start;$i--){ if((Uia-Name $all[$i]) -match $rx){ $steps+=$all[$i] } }
  foreach($el in $steps){ Uia-ScrollIntoView $el; $r=GemUia-FindCodeCopyButtonOnce $h -Quiet; if($r.btn){ Log 'Блок кода найден после прокрутки'; return $r.btn } }
  Log 'Блок кода не найден даже после прокрутки последнего ответа'
  $null
}
# Копирование кнопкой: уникальный маркер в буфере, проверка, что пользователь не трогал ввод во время копирования,
# буфер пользователя восстанавливается (Use-TempClipboard).
function Copy-ViaButton($h,[scriptblock]$Finder,[string]$What,[scriptblock]$Verify){
  for($try=1;$try -le 3;$try++){
    $res=Invoke-WithFocus $h {
      $b=& $Finder $h; if(!$b){ return @{ none=$true } }
      Uia-ScrollIntoView $b; Start-Sleep -Milliseconds 700
      $b=& $Finder $h; if(!$b){ return @{ none=$true } }
      Use-TempClipboard {
        $sentinel="__gg_$([guid]::NewGuid().ToString('N'))__"
        Set-ClipText $sentinel; $seq0=Get-ClipSeq
        if(-not (Uia-ClickEl $b)){ [void](Uia-Invoke $b) }
        $t0=Get-Date; $out=@{ text=$null; race=$false }
        for($i=0;$i -lt 6;$i++){
          Start-Sleep -Milliseconds 500
          if((Get-ClipSeq) -eq $seq0){ continue }
          $t=Get-ClipText
          if($t -and $t -ne $sentinel){
            $elapsed=((Get-Date)-$t0).TotalMilliseconds
            if((Get-IdleMs) -lt ($elapsed-150)){ $out.race=$true } else { $out.text=$t }
            if($out.text -and $Verify){ $v=& $Verify $b; if(-not $v.ok){ $out.text=$null; $out.bad=$true; $out.label=[string]$v.label } }
            break
          }
        }
        $out
      }
    }
    if($res.none){ return $null }
    if($res.bad){
      $msg="⛔ ${What}: после копирования подпись блока — «$($res.label)», а не «$($Cfg.CodeBlockLang)». Скопированное отброшено, в Antigravity НЕ передаю."
      Log $msg; Tg-Send $msg | Out-Null; return $null
    }
    if($res.text){ return $res.text }
    if($res.race){ Log "${What}: во время копирования пользователь работал с мышью/клавиатурой — результат отброшен (попытка $try)" }
    else { Log "$What не скопировался (попытка $try)" }
  }
  throw "Не удалось скопировать: $What"
}
# Пункт 25D: после копирования ещё раз читаем подпись блока нажатой кнопки; не Markdown -> ничего не возвращаем.
function GemUia-CopyCode($h){
  $r=Copy-ViaButton $h { param($x) GemUia-FindCodeCopyButton $x } 'блок кода' -Verify { param($b) $l=GemUia-CodeBlockLang $b; @{ ok=(Test-CodeLangMatch $l $Cfg.CodeBlockLang); label=$l } }
  $r
}
function GemUia-CopyWhole($h){ Copy-ViaButton $h { param($x) (GemUia-FindCopyButtons $x) | Select-Object -Last 1 } 'весь ответ' }
function GemUia-CodeBodyText($btn){
  $e=$btn
  for($i=0;$i -lt 8 -and $e;$i++){ $e=Uia-Parent $e; if(!$e){ return $null }; if((Uia-Class $e) -match $script:GemCodeBlockRx){ break } }
  if(!$e){ return $null }
  $all=@(Uia-FindAll -Root $e)
  $body=@($all | Where-Object { (Uia-Class $_) -match $script:GemCodeBodyRx }) | Select-Object -First 1
  $t=$null
  if($body){ $t=Uia-GetText $body; if(-not $t){ $t=(@(Uia-FindAll -Root $body -ControlType 'Text' | ForEach-Object { Uia-Name $_ }) -join '') } }
  else{
    # тела как отдельного элемента нет (так в Chromium 19.10): текст кода — Text после последней кнопки шапки
    $lb=-1; for($i=0;$i -lt $all.Count;$i++){ if((Uia-CtlType $all[$i]) -eq 'Button'){ $lb=$i } }
    if($lb -ge 0 -and $lb -lt $all.Count-1){ $t=(@($all[($lb+1)..($all.Count-1)] | Where-Object { (Uia-CtlType $_) -eq 'Text' } | ForEach-Object { Uia-Name $_ }) -join '') }
  }
  if($t){ $t } else { $null }
}
function GemUia-PeekAnswer($h){
  $all=@(GemUia-Buttons $h); $start=-1; $r=@{ answered=$false; labels=@(); md=$false; code=$null }
  for($i=$all.Count-1;$i -ge 0;$i--){ if((Uia-Name $all[$i]) -match $Cfg.RxPrompt){ $start=$i; break } }
  if($start -lt 0){ return $r }
  $cands=@(); $copy=$false
  for($i=$start+1;$i -lt $all.Count;$i++){ $nm=Uia-Name $all[$i]; if($nm -match $Cfg.RxCode){ $cands+=$all[$i] } elseif($nm -match $Cfg.RxCopy){ $copy=$true } }
  $r.answered=($copy -or $cands.Count -gt 0)
  $r.labels=@($cands | ForEach-Object { GemUia-CodeBlockLang $_ })
  $idx=Select-CodeBlockIndex -Langs $r.labels -Lang $Cfg.CodeBlockLang -Pick $Cfg.CodeBlockPick
  if($idx -ge 0){ $r.md=$true; $r.code=GemUia-CodeBodyText $cands[$idx] }
  $r
}
function GemUia-ChatTexts($h){ @(Uia-FindAll -Root $h -ControlType 'Text' | ForEach-Object { [string](Uia-Name $_) } | Where-Object { $_ }) }
function GemUia-LastReportPrompt($h){
  $t=@(Uia-FindAll -Root $h -ControlType 'Text' -NameRx 'Файл отчёта:\s*\S+\.md') | Select-Object -Last 1
  if($t){ [regex]::Match((Uia-Name $t),'Файл отчёта:\s*(\S+\.md)').Groups[1].Value } else { $null }
}
function GemUia-LastErrorText($h){
  $names=@(Uia-FindAll -Root $h -ControlType 'Text' | ForEach-Object { Uia-Name $_ } | Where-Object { $_ }) | Select-Object -Last 15
  @($names | Where-Object { Test-GeminiErrorText $_ }) | Select-Object -Last 1
}
function GemUia-Send([string]$Text,[string]$Marker){
  $h=Find-GeminiWindow; if(!$h){ throw [GG.RelayNotSentException]::new("Не найдено окно/вкладка браузера ($(Get-GeminiBrowserName)) с '$($Cfg.GeminiTitle)'. Откройте вкладку Gemini.") }
  Invoke-WithFocus $h {
    $ok=$false
    for($try=1;$try -le 3 -and -not $ok;$try++){
      $focused=GemUia-FocusInput $h
      if($focused -and (GemUia-InputHasText $h)){ ClearField; Start-Sleep -Milliseconds 300 }
      if(-not $focused){ Log "Фокус в поле Gemini не подтверждён (попытка $try) — не очищаю и не вставляю"; Activate-Window $h; continue }
      Use-TempClipboard { Set-ClipText $Text; Paste }
      $n=[Math]::Min(30,10+[int]($Text.Length/20000)*5)
      for($i=0;$i -lt $n -and -not $ok;$i++){ Start-Sleep -Milliseconds 500; $ok=GemUia-InputHasText $h $Marker }
      if(-not $ok){ Log "Текст не появился в поле Gemini (попытка $try)"; Activate-Window $h }
    }
    if(-not $ok){ throw [GG.RelayNotSentException]::new('Не удалось вставить текст в поле Gemini (проверено через UIA) — НЕ отправлено') }
    $before=(GemUia-FindCopyButtons $h).Count; $pBefore=GemUia-CountPrompts $h
    if(-not (GemUia-FocusInput $h)){ throw [GG.RelayNotSentException]::new('Перед Enter фокус не в поле Gemini — НЕ отправлено') }
    Assert-CanSendGemini 'отправку (Enter) в Gemini' | Out-Null
    PressEnter
    $sent=$false
    for($i=0;$i -lt 30 -and -not $sent;$i++){ Start-Sleep -Milliseconds 500; $sent=(-not (GemUia-InputHasText $h $Marker)) -and ((GemUia-CountPrompts $h) -gt $pBefore -or (GemUia-IsGenerating $h)) }
    if(-not $sent){ throw [GG.RelayNotSentException]::new('После Enter сообщение не появилось в диалоге Gemini — НЕ отправлено') }
    @{ before=$before; pBefore=$pBefore; h=$h; via='uia' }
  }
}
function GemUia-WaitAnswer($Ctx){
  $h=Find-GeminiWindow; if(!$h){ throw 'Окно Gemini пропало' }
  $before= if($Ctx){ [int]$Ctx.before } else { -1 }
  $t0=Get-Date; $quiet=Get-Date; $last=''; $seenGen=$false; $errSince=$null
  while($true){
    Nap 2
    if(((Get-Date)-$t0).TotalSeconds -gt $Cfg.GeminiTimeoutSec){ throw 'Таймаут ожидания ответа Gemini' }
    $gen=GemUia-IsGenerating $h; if($gen){ $seenGen=$true }
    $cnt=(GemUia-FindCopyButtons $h).Count
    if(-not $gen){
      $err=GemUia-LastErrorText $h
      if($err){ if(-not $errSince){ $errSince=Get-Date } elseif(((Get-Date)-$errSince).TotalSeconds -ge $Cfg.GeminiQuietSec){ throw "Gemini показал ошибку: $err" } } else { $errSince=$null }
    }
    $sig="$gen|$cnt"; if($sig -ne $last){ $last=$sig; $quiet=Get-Date; continue }
    $newBtn=($before -lt 0) -or ($cnt -gt $before) -or ($seenGen -and $cnt -gt 0)
    if(-not $gen -and $newBtn -and ((Get-Date)-$quiet).TotalSeconds -ge $Cfg.GeminiQuietSec){ break }
  }
  Start-Sleep 1
  $h
}
# ---------- Пункт 26: лимиты — из УЖЕ ОТКРЫТОЙ вкладки gemini.google.com/usage (новые вкладки не открываю) ----------
$script:UsageNoTabMsg='нет открытой вкладки gemini.google.com/usage'
$script:UsageReloadAt=$null
function GemUia-TabItems($h){ @(Uia-FindAll -Root $h -ControlType 'TabItem' | ForEach-Object { [pscustomobject]@{ name=(Uia-Name $_); el=$_ } }) }
function GemUia-ActiveTitle($h){ Remove-BrowserSuffix (Uia-Name (Uia-Root $h)) }
function GemUia-ReadUsage($h,[int]$Sec){
  $t0=Get-Date; $txt=''
  do{
    $txt=(@(Uia-FindAll -Root $h -ControlType 'Text' | ForEach-Object { Uia-Name $_ } | Where-Object { $_ }) -join ' | ')
    if(Test-UsageTextReady $txt){ break }
    Start-Sleep -Milliseconds 700
  } while(((Get-Date)-$t0).TotalSeconds -lt $Sec)
  $txt
}
function GemUia-SelectTab($tab){ [bool]((Uia-Select $tab.el) -or (Uia-Invoke $tab.el)) }
# Вернуть вкладку чата Gemini и проверить, что она активна. $true — чат активен.
function GemUia-BackToChat($h,[string]$Chat){
  if((GemUia-ActiveTitle $h) -eq $Chat){ return $true }
  $ct=Select-ChatTab (GemUia-TabItems $h) $Chat
  if($ct){ [void](GemUia-SelectTab $ct) }
  for($i=0;$i -lt 10;$i++){ Start-Sleep -Milliseconds 300; if((GemUia-ActiveTitle $h) -eq $Chat){ Log "Лимиты: вернул вкладку чата «$Chat»"; return $true } }
  $now=GemUia-ActiveTitle $h
  $m="⚠️ Лимиты: не удалось вернуть вкладку чата Gemini «$Chat» — сейчас активна «$now». Переключите вкладку вручную."
  Log $m; try{ Tg-Send $m | Out-Null }catch{}
  if(Get-Command Play-Sound -EA 0){ [void](Play-Sound 'error') }
  $false
}
function GemUia-GetUsageText{
  if($Cfg.UsageOpenNewTab){ return (GemUia-GetUsageTextNewTab) }
  $h=Find-GeminiWindow; if(!$h){ throw 'окно Gemini не найдено' }
  $chat=GemUia-ActiveTitle $h
  $cands=@($h)+@(Get-BrowserWindows (Get-TopWindows) | Where-Object { [IntPtr]$_.h -ne [IntPtr]$h } | ForEach-Object { $_.h })
  $hu=$null; $tab=$null
  foreach($w in $cands){ $t=Select-UsageTab (GemUia-TabItems $w); if($t){ $hu=$w; $tab=$t; break } }
  if(-not $tab){ throw $script:UsageNoTabMsg }
  $huChat= if([IntPtr]$hu -eq [IntPtr]$h){ $chat } else { GemUia-ActiveTitle $hu }
  $script:UsageTxt=''   # тело Invoke-WithFocus выполняется в дочерней области — результат только через $script:
  # Пункт 27D: сначала без фокуса и без клавиш — вкладку выбираю UIA SelectionItem/Invoke, перезагружаю кнопкой «Обновить эту страницу».
  if($Cfg.UsageNoFocus){
    $nf=$null
    if([IntPtr](Get-ForegroundHandle) -eq [IntPtr]$hu){ [void](Wait-UserIdle) }   # пользователь сейчас в этом окне браузера — вкладку не дёргаю, пока он активен
    try{ $nf=GemUia-UsageOnTab $hu $tab }catch{ Log "Лимиты без фокуса: $($_.Exception.Message) — пробую с выводом окна" }
    finally{ if($huChat){ [void](GemUia-BackToChat $hu $huChat) } }
    if(Test-UsageTextReady $nf){ return [string]$nf }
  }
  Invoke-WithFocus $hu {
    try{ $script:UsageTxt=GemUia-UsageOnTab $hu $tab -AllowF5 }
    finally { if($huChat){ [void](GemUia-BackToChat $hu $huChat) } }
  }
  [string]$script:UsageTxt
}
# Кнопка браузера «Обновить эту страницу» (Яндекс: aid view_1020, Invoke) — перезагрузка без клавиатуры.
function GemUia-ReloadButton($h){
  @(Uia-FindAll -Root $h -ControlType 'Button' | Where-Object { (Uia-Name $_) -match $Cfg.ReloadButtonRx -and -not (Uia-IsOffscreen $_) }) | Select-Object -First 1
}
# Переключиться на вкладку лимитов, прочитать, при необходимости перезагрузить. F5 — только с -AllowF5 (окно уже на переднем плане),
# только если кнопки «Обновить» нет, и только при проверенных переднем окне и заголовке вкладки (прямо перед клавишей).
function GemUia-UsageOnTab($hu,$tab,[switch]$AllowF5){
  if(-not (GemUia-SelectTab $tab)){ throw "не удалось переключиться на вкладку лимитов «$($tab.name)»" }
  $ok=$false; for($i=0;$i -lt 10 -and -not $ok;$i++){ Start-Sleep -Milliseconds 300; $ok=Test-UsageTabName (GemUia-ActiveTitle $hu) }
  if(-not $ok){ throw "вкладка лимитов не стала активной (заголовок '$(GemUia-ActiveTitle $hu)')" }
  Log "Лимиты: переключил на вкладку «$(Remove-BrowserSuffix $tab.name)»$(if(-not $AllowF5){' (без фокуса)'})"
  $txt=GemUia-ReadUsage $hu 3
  if(Test-UsageStale $txt $script:UsageReloadAt){
    $rb=GemUia-ReloadButton $hu
    if($rb -and (Test-UsageTabName (GemUia-ActiveTitle $hu)) -and (Uia-Invoke $rb)){
      $script:UsageReloadAt=Get-Date; Start-Sleep -Milliseconds 1500; $txt=GemUia-ReadUsage $hu 25
    } elseif($AllowF5 -and ([IntPtr](Get-ForegroundHandle) -eq [IntPtr]$hu) -and (Test-UsageTabName (GemUia-ActiveTitle $hu))){
      Log 'Лимиты: кнопки «Обновить» нет — F5'
      Send-Key 0x74; $script:UsageReloadAt=Get-Date; Start-Sleep -Milliseconds 1500; $txt=GemUia-ReadUsage $hu 25
    } else { Log "Лимиты: перезагрузку не делаю (кнопки «Обновить» нет$(if($AllowF5){", активна '$(GemUia-ActiveTitle $hu)'"}))" }
  }
  [string]$txt
}
# Прежний способ (UsageOpenNewTab=$true): новая вкладка (Ctrl+T). Всё после открытия вкладки — в try/finally: вкладка закрывается при любом исходе.
function GemUia-GetUsageTextNewTab{
  $h=Find-GeminiWindow; if(!$h){ throw 'окно Gemini не найдено' }
  $chat=Uia-Name (Uia-Root $h); $txt=''
  Invoke-WithFocus $h {
    Send-Ctrl 0x54
    try{
      $opened=$false; for($i=0;$i -lt 8 -and -not $opened;$i++){ Start-Sleep -Milliseconds 400; $tt=Uia-Name (Uia-Root $h); $opened=($tt -ne $chat -and $tt -match $Cfg.UsageTabTitle) }
      if(-not $opened){ throw "новая вкладка не открылась (заголовок '$(Uia-Name (Uia-Root $h))') — адрес не вставлял" }
      Send-Ctrl 0x4C; Start-Sleep -Milliseconds 300   # Ctrl+L — адресная строка (в Яндекс Браузере новая вкладка «Табло» ставит фокус в поиск на странице)
      $fe=Uia-Focused; $fc= if($fe){ Uia-Class $fe } else { '' }
      if($fe -and $fc -match $Cfg.GeminiInputClassRx){ throw 'фокус в поле чата Gemini — адрес не вставлял' }
      if($fe -and $fc -notmatch $Cfg.AddressBarClassRx){ throw "фокус не в адресной строке ($fc) — адрес не вставлял" }
      Use-TempClipboard { Set-ClipText $Cfg.GeminiUsageUrl; Paste }
      Start-Sleep -Milliseconds 400; PressEnter
      $t0=Get-Date
      while(((Get-Date)-$t0).TotalSeconds -lt 25){
        Start-Sleep 2
        $script:UsageTxt=(@(Uia-FindAll -Root $h -ControlType 'Text' | ForEach-Object { Uia-Name $_ } | Where-Object { $_ }) -join ' | ')
        if($script:UsageTxt -match '(Недельный лимит|Weekly limit).*?(Использовано|Used)\s*\d+'){ break }
      }
    } finally {
      $title=Uia-Name (Uia-Root $h)
      if($title -ne $chat -and $title -match $Cfg.UsageTabTitle){ Activate-Window $h; Send-Ctrl 0x57; Start-Sleep -Milliseconds 1200 }
      elseif($title -ne $chat){ Log "Лимиты: НЕ закрываю вкладку — заголовок '$title' не похож на вкладку лимитов" }
      $after=Uia-Name (Uia-Root $h)
      if($after -ne $chat){ Log "Лимиты: после закрытия вкладки заголовок '$after', ожидался чат '$chat'" }
    }
  }
  [string]$script:UsageTxt
}

# ---------- Переключатель модели (меню «Выбор режима») ----------
# Пункты меню — MenuItem «4 Argon Сложные задачи», выбранный — «Выбрано 3.8 Flash …»; «Уровень рассуждений» — подменю, не модель.
function GemUia-ModelButton($h){ @(Uia-FindAll -Root $h -ControlType 'Button' -NameRx $Cfg.RxModel) | Select-Object -First 1 }
function GemUia-ModelItems($h){ @(Uia-FindAll -Root $h -ControlType 'MenuItem' | Where-Object { -not (Uia-IsOffscreen $_) -and (Uia-Name $_) -and (Uia-Name $_) -notmatch $Cfg.ModelMenuSkipRx }) }
function ConvertTo-ModelItemInfo([string]$Name,[bool]$Enabled=$true){ @{ name=(([string]$Name) -replace $Cfg.ModelSelectedRx,'').Trim(); selected=([string]$Name -match $Cfg.ModelSelectedRx); enabled=$Enabled } }
# Пункт 26: после SetForegroundWindow Chromium/Яндекс перестраивает дерево доступности — кнопка «Выбор режима» пропадает
# на долю секунды (до вывода окна она читалась). Ждём её до ModelButtonWaitSec, при неудаче пишем в лог похожие кнопки.
function GemUia-WaitModelButton($h){
  $t0=Get-Date
  do{
    $b=GemUia-ModelButton $h; if($b){ return $b }
    Start-Sleep -Milliseconds 300
  } while(((Get-Date)-$t0).TotalSeconds -lt [double]$Cfg.ModelButtonWaitSec)
  $sim=@(GemUia-Buttons $h | ForEach-Object { Uia-Name $_ } | Where-Object { $_ -match '(?i)режим|mode|flash|argon|модел|model' } | Select-Object -First 6)
  Log "Модель: кнопка «Выбор режима» не найдена за $($Cfg.ModelButtonWaitSec) сек после вывода окна (RxModel='$($Cfg.RxModel)'); похожие кнопки: $(if($sim.Count){($sim | ForEach-Object { "«$_»" }) -join ', '}else{'нет'})"
  $null
}
function GemUia-OpenModelMenu($h){
  $b=GemUia-WaitModelButton $h; if(!$b){ throw 'переключатель модели Gemini не найден' }
  if((Uia-ExpandState $b) -ne 'Expanded'){ if(-not (Uia-Expand $b)){ [void](Uia-ClickEl $b) } }
  for($i=0;$i -lt 10;$i++){ Start-Sleep -Milliseconds 300; $it=@(GemUia-ModelItems $h); if($it.Count){ return $it } }
  @()
}
function GemUia-CloseModelMenu($h){
  for($i=0;$i -lt 2;$i++){
    $b=GemUia-ModelButton $h; if(-not $b -or (Uia-ExpandState $b) -ne 'Expanded'){ return }
    if($i -eq 0 -and (Uia-Collapse $b)){ Start-Sleep -Milliseconds 300; continue }
    if([IntPtr](Get-ForegroundHandle) -ne [IntPtr]$h){ Log 'Модель: меню не закрылось, Esc не жму — окно Gemini не на переднем плане'; return }   # 27D: клавиши — только в своё окно
    PressEsc; Start-Sleep -Milliseconds 300
  }
}
function GemUia-ListModels($h){
  $cur=GemUia-GetModel $h
  $items=@(Invoke-WithFocus $h {
    try{ @(GemUia-OpenModelMenu $h | ForEach-Object { ConvertTo-ModelItemInfo (Uia-Name $_) (Uia-IsEnabled $_) }) }
    finally{ GemUia-CloseModelMenu $h }
  })
  @{ current=$cur; items=$items }
}
function GemUia-SelectModel($h,[string]$Want){
  $cur=GemUia-GetModel $h
  if($cur -and $cur.IndexOf($Want,[StringComparison]::OrdinalIgnoreCase) -ge 0){ return $cur }
  if(GemUia-IsGenerating $h){ throw 'Gemini сейчас отвечает — модель не переключаю' }
  Invoke-WithFocus $h {
    $items=@(GemUia-OpenModelMenu $h)
    try{
      if(-not $items.Count){ throw 'меню моделей не открылось' }
      $it=@($items | Where-Object { (Uia-Name $_).IndexOf($Want,[StringComparison]::OrdinalIgnoreCase) -ge 0 }) | Select-Object -First 1
      if(-not $it){ throw "в меню моделей нет пункта «$Want» (есть: $((@($items | ForEach-Object { (ConvertTo-ModelItemInfo (Uia-Name $_)).name }) -join '; ')))" }
      if(-not (Uia-IsEnabled $it)){ throw "пункт «$((ConvertTo-ModelItemInfo (Uia-Name $it)).name)» недоступен (лимит ещё не обновился?)" }
      if(-not (Uia-Invoke $it)){ if(-not (Uia-ClickEl $it)){ throw "не удалось нажать пункт «$(Uia-Name $it)»" } }
      Start-Sleep -Milliseconds 1200
    } finally { GemUia-CloseModelMenu $h }
  }
  GemUia-GetModel $h
}
