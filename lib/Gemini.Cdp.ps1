# ===== GGskript v2: Gemini через Chrome DevTools Protocol (GeminiTransport='cdp') =====
# Без фокуса, мыши и буфера обмена: ввод — Input.insertText, чтение — Runtime.evaluate, лимиты — фоновая вкладка.
# Chrome нужно запустить с --remote-debugging-port=<CdpPort> и ОТДЕЛЬНЫМ --user-data-dir (Chrome 136+ иначе порт не открывает),
# см. Start-GeminiChrome.bat. Порт слушает только 127.0.0.1.
# Селекторы страницы Gemini — ниже; при изменении вёрстки их можно переопределить в relay_settings.json → "CdpSelectors".

$script:CdpSelDefault=[ordered]@{
  input      = 'rich-textarea .ql-editor, div.ql-editor[contenteditable="true"]'
  upload     = 'button[aria-label*="upload" i], button[aria-label*="загруз" i], button[aria-label*="Add files" i], button[aria-label*="Добавить файл" i], uploader button'
  uploadItem = '[data-test-id="local-images-files-uploader-button"], [role="menuitem"]'
  send       = 'button.send-button, button[aria-label*="Send message"], button[aria-label*="Отправить"]'
  stop       = 'button[aria-label*="Stop response"], button[aria-label*="Остановить"], button.send-button.stop'
  prompt     = 'user-query'
  promptText = '.query-text'
  # пункт 28: вложенный файл-«чип» в запросе (имя — aria-label кнопки «MyProject_…_002.md», запасной — подпись без .md)
  promptFile = 'user-query-file-preview [data-test-id="uploaded-file"] button, user-query-file-preview button.new-file-preview-file'
  response   = 'model-response'
  codeBlock  = 'code-block'
  codeLang   = '.code-block-decoration'
  code       = 'code'
  model      = '[data-test-id="bard-mode-menu-button"], bard-mode-switcher button, .input-area-switch-label'
  modelBtn   = 'button.input-area-switch, [data-test-id="bard-mode-menu-button"], bard-mode-switcher button'
  modelItem  = '[role="menuitem"], [role="menuitemradio"], .mat-mdc-menu-item'
}
function Get-CdpSelectors{
  $s=[ordered]@{}; foreach($k in $script:CdpSelDefault.Keys){ $s[$k]=$script:CdpSelDefault[$k] }
  if($Cfg.CdpSelectors){ foreach($k in @($Cfg.CdpSelectors.Keys)){ if($s.Contains($k) -and $Cfg.CdpSelectors[$k]){ $s[$k]=[string]$Cfg.CdpSelectors[$k] } } }
  $s
}
# JS-помощник: одна функция, операция и аргумент передаются JSON-ом (никакой подстановки текста в код).
$script:GemJs=@'
(function(S,op,arg){
  const q=s=>document.querySelector(s), qa=s=>Array.from(document.querySelectorAll(s));
  const txt=e=>e?((e.innerText||e.textContent||'')+'').trim():'';
  const vis=e=>!!e&&!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length);
  const last=()=>{const r=qa(S.response);return r.length?r[r.length-1]:null;};
  const langOf=b=>{const h=b.querySelector(S.codeLang); if(!h) return '';
    for(const n of Array.from(h.childNodes)){ if(n.nodeType===1&&(n.matches('button,mat-icon,.buttons')||n.querySelector('button'))) continue;
      const t=((n.textContent||'')+'').trim(); if(t) return t.split('\n')[0].trim(); }
    return '';};
  const txtNoIcon=e=>{ if(!e) return ''; const c=e.cloneNode(true); c.querySelectorAll('mat-icon,.mat-icon,.google-symbols,[fonticon]').forEach(x=>x.remove()); return ((c.textContent||'')+'').replace(/\s+/g,' ').trim(); };
  // пункт 28: имена вложенных файлов запроса (по порядку в DOM, без повторов) — иначе отчёты, приложенные файлом, не видны
  const filesOf=e=>{ const o=[]; let sel=[]; try{ sel=Array.from(e.querySelectorAll(S.promptFile)); }catch(x){}
    for(const b of sel){ const lb=b.querySelector('[data-test-id="filename-label"], .filename-label'); const n=(((b.getAttribute('aria-label')||'')+'').trim()||txt(lb)); if(n&&!o.includes(n)) o.push(n); }
    return o; };
  const codeOf=b=>{const c=b.querySelector(S.code)||b;return ((c.innerText||c.textContent||'')+'').replace(/\n$/,'');};
  switch(op){
    case 'ready': return !!q(S.input);
    case 'model': { // пункт 27A: текст без значков (mat-icon «keyboard_arrow_down»), иначе aria-label «Выбор режима, сейчас используется Flash»
      const els=qa(S.model).filter(vis).concat(qa(S.modelBtn));
      for(const e of els){ const t=txtNoIcon(e); if(t) return t; }
      for(const e of els){ const a=(e.getAttribute('aria-label')||'')+''; const m=a.match(/^.*(?:используется|currently using|using|сейчас)[:\s]*(.+)$/i); if(m) return m[1].trim(); }
      return ''; }
    case 'prompts': return qa(S.prompt).length;
    case 'promptTexts': return qa(S.prompt).map(e=>{ const f=filesOf(e); const t=txt(e.querySelector(S.promptText)||e); return f.length?(f.join('\n')+'\n'+t):t; });
    case 'inputText': { const e=q(S.input); return e?((e.innerText||'')+''):null; }
    case 'focusClear': { const e=q(S.input); if(!e) return false; e.focus();
      if(txt(e).length){ document.execCommand('selectAll',false,null); document.execCommand('delete',false,null); }
      return document.activeElement===e||e.contains(document.activeElement); }
    case 'chips': return qa('.attachment-preview-wrapper, uploader-file-preview, [data-test-id="file-preview"]').map(e=>((e.getAttribute('aria-label')||'')+' '+txt(e)).trim());
    // CSS-флаг i не меняет регистр кириллицы («Загрузка» ≠ «загруз»), поэтому кнопка ищется регуляркой в JS (Gemini RU: «Загрузка и инструменты»)
    case 'openUpload': { const rx=/загрузк|загрузить|меню загрузки|upload|add files|добавить файл/i;
      let b=qa('button').filter(vis).find(x=>rx.test((x.getAttribute('aria-label')||'')+''));
      if(!b){ try{ b=qa(S.upload).filter(vis).pop(); }catch(e){} }
      if(!b) return 'nobtn'; if(b.getAttribute('aria-expanded')!=='true') b.click(); return 'ok'; }
    case 'clickUploadItem': { const its=qa(S.uploadItem).filter(vis); const lab=x=>txt(x)+' '+(x.getAttribute('aria-label')||'');
      const it=its.find(x=>x.getAttribute('data-test-id')==='local-images-files-uploader-button')||its.find(x=>/загрузить файл|upload file/i.test(lab(x)))||its.find(x=>/upload|загруз|файл|file/i.test(lab(x))&&!/диск|drive|фото|photo/i.test(lab(x)));
      if(!it) return false; it.click(); return true; }
    case 'sendEnabled': { return qa(S.send).some(x=>vis(x)&&!x.disabled&&x.getAttribute('aria-disabled')!=='true'); }
    case 'clickSend': { const b=qa(S.send).find(x=>vis(x)&&!x.disabled&&x.getAttribute('aria-disabled')!=='true'); if(!b) return false; b.click(); return true; }
    case 'state': { const r=last(); const t=r?txt(r):''; return {gen:qa(S.stop).some(vis), n:qa(S.response).length, len:t.length, tail:t.slice(-400)}; }
    case 'codes': { const r=last(); if(!r) return []; return Array.from(r.querySelectorAll(S.codeBlock)).map(b=>({lang:langOf(b), code:codeOf(b)})); }
    case 'whole': { const r=last(); if(!r) return '';
      const c=r.cloneNode(true);
      c.querySelectorAll(S.codeBlock).forEach(b=>{ const l=langOf(b).toLowerCase().replace(/\s+/g,''); const t=document.createElement('pre'); t.textContent='```'+l+'\n'+codeOf(b)+'\n```'; b.replaceWith(t); });
      const box=document.createElement('div'); box.style.cssText='position:absolute;left:-100000px;top:0;width:900px;white-space:normal'; box.appendChild(c); document.body.appendChild(box);
      const out=((box.innerText||'')+''); box.remove(); return out.trim(); }
    case 'body': return document.body?((document.body.innerText||'')+''):'';
    case 'modelOpen': { const b=qa(S.modelBtn).find(vis); if(!b) return false; if(b.getAttribute('aria-expanded')!=='true') b.click(); return true; }
    case 'modelItems': return qa(S.modelItem).filter(vis).map(e=>({name:txt(e).replace(/\s+/g,' '), enabled:!(e.disabled||e.getAttribute('aria-disabled')==='true'),
        selected:e.classList.contains('selected')||e.getAttribute('aria-checked')==='true'||e.getAttribute('aria-selected')==='true'}));
    case 'modelPick': { const w=(arg.want+'').toLowerCase(), skip=new RegExp(arg.skip||'^$','i');
      const it=qa(S.modelItem).filter(vis).find(e=>{ const n=txt(e).replace(/\s+/g,' '); return !skip.test(n) && n.toLowerCase().includes(w); });
      if(!it) return {ok:false, err:'notfound'};
      const n=txt(it).replace(/\s+/g,' ');
      if(it.disabled||it.getAttribute('aria-disabled')==='true') return {ok:false, err:'disabled', name:n};
      it.click(); return {ok:true, name:n}; }
    case 'modelClose': { const b=qa(S.modelBtn).find(vis); if(b && b.getAttribute('aria-expanded')==='true'){
        const bd=q('.cdk-overlay-backdrop'); if(bd) bd.click(); else document.body.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',code:'Escape',keyCode:27,bubbles:true})); }
      return true; }
  }
  throw new Error('unknown op '+op);
})
'@

# ---------- Транспорт (адаптеры; в тестах подменяются) ----------
# PS7 отдаёт JSON-массив одним объектом, PS5.1 — по элементам; ForEach-Object выравнивает оба случая.
function Cdp-HttpJson([string]$Path,[string]$Method='Get',[int]$Port=0){ if($Port -le 0){ $Port=[int]$Cfg.CdpPort }; Invoke-RestMethod -Uri ("http://127.0.0.1:{0}{1}" -f $Port,$Path) -Method $Method -TimeoutSec 5 | ForEach-Object { $_ } }
function Cdp-Open([string]$WsUrl){
  $ws=New-Object System.Net.WebSockets.ClientWebSocket
  $cts=New-Object System.Threading.CancellationTokenSource 10000
  try{ [void]$ws.ConnectAsync([Uri]$WsUrl,$cts.Token).GetAwaiter().GetResult() } finally { $cts.Dispose() }
  @{ ws=$ws; nextId=0; url=$WsUrl }
}
function Cdp-Close($Conn){ if($Conn -and $Conn.ws){ try{ $c=New-Object System.Threading.CancellationTokenSource 2000; [void]$Conn.ws.CloseAsync('NormalClosure','',$c.Token).GetAwaiter().GetResult() }catch{}; try{ $Conn.ws.Dispose() }catch{} } }
function Cdp-SendText($Conn,[string]$Text){
  $b=[Text.Encoding]::UTF8.GetBytes($Text); $seg=New-Object 'System.ArraySegment[byte]' (,$b)
  $cts=New-Object System.Threading.CancellationTokenSource 10000
  try{ [void]$Conn.ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$cts.Token).GetAwaiter().GetResult() } finally { $cts.Dispose() }
}
function Cdp-ReceiveText($Conn,[int]$TimeoutMs){
  $buf=New-Object byte[] 65536; $ms=New-Object IO.MemoryStream
  $cts=New-Object System.Threading.CancellationTokenSource $TimeoutMs
  try{
    do{
      $seg=New-Object 'System.ArraySegment[byte]' (,$buf)
      $r=$Conn.ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()
      if($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){ throw 'CDP: соединение закрыто браузером' }
      $ms.Write($buf,0,$r.Count)
    } while(-not $r.EndOfMessage)
    [Text.Encoding]::UTF8.GetString($ms.ToArray())
  } finally { $cts.Dispose(); $ms.Dispose() }
}

# ---------- Протокол ----------
$script:CdpConn=$null
function Find-CdpTarget{
  $list=@(Cdp-HttpJson '/json/list')
  $c=@($list | Where-Object { $_.type -eq 'page' -and ([string]$_.url) -like "*$($Cfg.CdpUrlLike)*" -and ([string]$_.url) -notlike '*/usage*' })
  # пункт 27A: вкладка чата (/app) важнее прочих страниц Gemini
  $a=@($c | Where-Object { ([string]$_.url) -like '*/app*' }) | Select-Object -First 1
  if($a){ $a } else { $c | Select-Object -First 1 }
}
function Find-CdpUsageTarget{ @(Cdp-HttpJson '/json/list' | Where-Object { $_.type -eq 'page' -and ([string]$_.url) -like "*$($Cfg.CdpUrlLike)*" -and ([string]$_.url) -like '*/usage*' }) | Select-Object -First 1 }
# Ошибка «CDP недоступен» (браузер без порта, нет вкладки, связь оборвалась) — только тогда допустим откат на UIA (пункт 27A).
function Test-CdpUnreachable($Err){
  $m= if($Err -is [System.Management.Automation.ErrorRecord]){ [string]$Err.Exception.Message } else { [string]$Err }
  [bool]($m -match '(?i)CDP[^:]*:.*(не отвечает|нет вкладки)|соединение закрыто|WebSocket|Unable to connect|actively refused|connection refused|No connection could be made|отверг|невозможно установить')
}
function Connect-Cdp([switch]$Force){
  if(-not $Force -and $script:CdpConn -and $script:CdpConn.ws -and $script:CdpConn.ws.State -eq 'Open'){ return $script:CdpConn }
  if($script:CdpConn){ Cdp-Close $script:CdpConn; $script:CdpConn=$null }
  try{ $t=Find-CdpTarget }catch{ throw [GG.RelayNotSentException]::new("CDP: Chrome с --remote-debugging-port=$($Cfg.CdpPort) не отвечает ($($_.Exception.Message))") }
  if(-not $t){ throw [GG.RelayNotSentException]::new("CDP: нет вкладки с адресом '*$($Cfg.CdpUrlLike)*'") }
  $c=Cdp-Open $t.webSocketDebuggerUrl; $c.targetId=$t.id; $script:CdpConn=$c
  try{ [void](Invoke-Cdp 'Emulation.setFocusEmulationEnabled' @{ enabled=$true } -Conn $c) }catch{}
  $c
}
function Invoke-Cdp{
  param([string]$Method,$Params=@{},[int]$TimeoutSec=30,$Conn)
  Assert-Running "CDP $Method"
  if(-not $Conn){ $Conn=Connect-Cdp }
  $Conn.nextId++; $id=$Conn.nextId
  Cdp-SendText $Conn (@{ id=$id; method=$Method; params=$Params } | ConvertTo-Json -Depth 10 -Compress)
  $end=(Get-Date).AddSeconds($TimeoutSec)
  while($true){
    $left=[int](($end-(Get-Date)).TotalMilliseconds); if($left -le 0){ throw "CDP: нет ответа на $Method за $TimeoutSec сек" }
    $m=(Cdp-ReceiveText $Conn $left) | ConvertFrom-Json
    if($null -eq $m.id){ if($m.method -and $Conn.events -is [System.Collections.IList]){ [void]$Conn.events.Add($m) }; continue }   # события (копим, если запрошено)
    if([int]$m.id -ne $id){ continue }   # чужие ответы
    if($m.error){ throw "CDP $($Method): $($m.error.message)" }
    return $m.result
  }
}
function Eval-Js{
  param([string]$Op,$Arg=$null,$Conn)
  $sel=(Get-CdpSelectors) | ConvertTo-Json -Compress
  $a= if($null -eq $Arg){ 'null' } else { ConvertTo-Json $Arg -Compress -Depth 5 }
  $expr="$($script:GemJs)($sel,$(ConvertTo-Json $Op -Compress),$a)"
  $r=Invoke-Cdp 'Runtime.evaluate' @{ expression=$expr; returnByValue=$true; awaitPromise=$true; userGesture=$true } -Conn $Conn
  if($r.exceptionDetails){ throw "CDP JS ($Op): $($r.exceptionDetails.exception.description)" }
  $r.result.value
}

# ---------- Операции Gemini ----------
function GemCdp-IsReady{ [bool](Eval-Js 'ready') }
function GemCdp-GetModel{ [string](Eval-Js 'model') }
function GemCdp-CountPrompts{ [int](Eval-Js 'prompts') }
function GemCdp-PromptTexts{ @(Eval-Js 'promptTexts' | ForEach-Object { [string]$_ }) }
# Пункт 28: последний ЗАПРОС пользователя (по порядку DOM), в котором есть отчёт — «Файл отчёта: имя» или вложенный файл;
# в одном запросе несколько отчётов — самый новый по дате/номеру. Раньше брался последний «Файл отчёта:» в тексте, а вложения не читались.
function GemCdp-LastReportPrompt{ Get-LastReportFromPrompts -Texts (GemCdp-PromptTexts) -Pattern $Cfg.Pattern }
# Отправка. До клика «Отправить» любая ошибка — GG.RelayNotSentException (можно откатиться на UIA). После клика — обычная ошибка (повторная отправка недопустима).
function GemCdp-Send([string]$Text,[string]$Marker){
  try{
    $c=Connect-Cdp
    if(-not (Eval-Js 'ready' -Conn $c)){ throw 'нет поля ввода' }
    $pBefore=[int](Eval-Js 'prompts' -Conn $c); $before=[int](Eval-Js 'state' -Conn $c).n
    if(-not (Eval-Js 'focusClear' -Conn $c)){ throw 'фокус в поле ввода не подтверждён' }
    [void](Invoke-Cdp 'Input.insertText' @{ text=$Text } -Conn $c)
    $ok=$false
    for($i=0;$i -lt 10 -and -not $ok;$i++){ $cur=[string](Eval-Js 'inputText' -Conn $c); $ok=(-not $Marker -and $cur.Trim()) -or ($Marker -and $cur.IndexOf($Marker,[StringComparison]::OrdinalIgnoreCase) -ge 0); if(-not $ok){ Start-Sleep -Milliseconds 300 } }
    if(-not $ok){ try{ [void](Eval-Js 'focusClear' -Conn $c) }catch{}; throw 'текст не появился в поле ввода' }
    if(-not (Eval-Js 'clickSend' -Conn $c)){ try{ [void](Eval-Js 'focusClear' -Conn $c) }catch{}; throw 'кнопка «Отправить» не найдена или недоступна' }
  }catch{
    if((Get-ErrorKind $_) -in @('stop','paused','limit')){ throw }
    if((Get-ErrorKind $_) -eq 'notsent'){ throw }
    throw [GG.RelayNotSentException]::new("Gemini/CDP: $($_.Exception.Message) — НЕ отправлено")
  }
  # После клика: подтверждаем, что запрос ушёл (новый запрос в чате или поле очистилось)
  for($i=0;$i -lt 20;$i++){
    Start-Sleep -Milliseconds 500
    try{ if([int](Eval-Js 'prompts' -Conn $c) -gt $pBefore -or -not ([string](Eval-Js 'inputText' -Conn $c)).Trim()){ Log "Отправлено в Gemini (CDP), $($Text.Length) симв."; return @{ before=$before; pBefore=$pBefore; via='cdp' } } }catch{}
  }
  throw 'Gemini/CDP: после нажатия «Отправить» запрос в чате не появился — проверьте вкладку (повторно не отправляю)'
}
# Вложение через «+»: перехват диалога выбора файла (Page.setInterceptFileChooserDialog) и DOM.setFileInputFiles; поле ввода пустое.
function GemCdp-SendFile([string]$Path,[string]$Name){
  try{
    $c=Connect-Cdp
    if(-not (Eval-Js 'ready' -Conn $c)){ throw 'нет поля ввода' }
    if(-not (Eval-Js 'focusClear' -Conn $c)){ throw 'фокус в поле ввода не подтверждён' }
    $pBefore=[int](Eval-Js 'prompts' -Conn $c); $before=[int](Eval-Js 'state' -Conn $c).n
    # Диалог выбора файла перехватывается (окно Windows не открывается); событие Page.fileChooserOpened даёт backendNodeId поля <input type=file>,
    # которое Gemini создаёт на лету и часто не вставляет в DOM — поэтому файл ставится по backendNodeId, а поиск в DOM только запасной.
    $c.events=New-Object System.Collections.ArrayList
    try{ [void](Invoke-Cdp 'Page.enable' @{} -Conn $c) }catch{}
    [void](Invoke-Cdp 'Page.setInterceptFileChooserDialog' @{ enabled=$true } -Conn $c)
    try{
      if((Eval-Js 'openUpload' -Conn $c) -ne 'ok'){ throw 'кнопка «+» («Загрузка и инструменты») не найдена' }
      $clicked=$false; for($i=0;$i -lt 8 -and -not $clicked;$i++){ Start-Sleep -Milliseconds 400; $clicked=[bool](Eval-Js 'clickUploadItem' -Conn $c) }
      if(-not $clicked){ throw 'пункт меню «Загрузить файлы» не найден' }
      $bk=$null; $t1=Get-Date
      while(-not $bk -and ((Get-Date)-$t1).TotalSeconds -lt 6){
        $ev=@($c.events | Where-Object { $_.method -eq 'Page.fileChooserOpened' }) | Select-Object -Last 1
        if($ev -and $ev.params.backendNodeId){ $bk=[int]$ev.params.backendNodeId; break }
        Start-Sleep -Milliseconds 300; [void](Invoke-Cdp 'Runtime.evaluate' @{ expression='1'; returnByValue=$true } -Conn $c)   # прокачать события
      }
      if($bk){ [void](Invoke-Cdp 'DOM.setFileInputFiles' @{ files=@($Path); backendNodeId=$bk } -Conn $c) }
      else{
        $doc=Invoke-Cdp 'DOM.getDocument' @{ depth=-1; pierce=$true } -Conn $c
        $ids=@((Invoke-Cdp 'DOM.querySelectorAll' @{ nodeId=$doc.root.nodeId; selector='input[type=file]' } -Conn $c).nodeIds)
        if(-not $ids.Count){ throw 'поле выбора файла не найдено (диалог не открылся)' }
        [void](Invoke-Cdp 'DOM.setFileInputFiles' @{ files=@($Path); nodeId=$ids[-1] } -Conn $c)
      }
    } finally { try{ [void](Invoke-Cdp 'Page.setInterceptFileChooserDialog' @{ enabled=$false } -Conn $c) }catch{}; $c.events=$null }
    $base=$Name -replace '\.md$',''; $ok=$false; $t0=Get-Date
    while(((Get-Date)-$t0).TotalSeconds -lt $Cfg.AttachTimeoutSec -and -not $ok){ Start-Sleep -Milliseconds 700
      $ch=@(Eval-Js 'chips' -Conn $c | ForEach-Object { [string]$_ }); $ok=(@($ch | Where-Object { $_ -like "*$base*" }).Count -gt 0) -and [bool](Eval-Js 'sendEnabled' -Conn $c) }
    if(-not $ok){ throw "чип файла $Name не появился или загрузка не закончилась" }
    if(([string](Eval-Js 'inputText' -Conn $c)).Trim()){ throw 'в поле ввода есть текст — вместе с файлом не отправляю' }
    Assert-CanSendGemini 'отправку файла в Gemini' | Out-Null
    if(-not (Eval-Js 'clickSend' -Conn $c)){ throw 'кнопка «Отправить» не найдена или недоступна' }
  }catch{
    if((Get-ErrorKind $_) -in @('stop','paused','limit','notsent')){ throw }
    throw [GG.RelayNotSentException]::new("Gemini/CDP (файл): $($_.Exception.Message) — НЕ отправлено")
  }
  for($i=0;$i -lt 20;$i++){ Start-Sleep -Milliseconds 500
    try{ if([int](Eval-Js 'prompts' -Conn $c) -gt $pBefore){ Log "Отправлено в Gemini (CDP): только вложение $Name"; return @{ before=$before; pBefore=$pBefore; via='cdp-file' } } }catch{} }
  throw "Gemini/CDP: после «Отправить» запрос с файлом $Name не появился (повторно не отправляю)"
}
function GemCdp-WaitAnswer($Ctx){
  $before= if($Ctx){ [int]$Ctx.before } else { -1 }
  $t0=Get-Date; $quiet=Get-Date; $last=''; $errSince=$null
  while($true){
    Nap 2
    if(((Get-Date)-$t0).TotalSeconds -gt $Cfg.GeminiTimeoutSec){ throw 'Таймаут ожидания ответа Gemini' }
    $s=Eval-Js 'state'
    if(-not $s.gen -and (Test-GeminiErrorText ([string]$s.tail))){ if(-not $errSince){ $errSince=Get-Date } elseif(((Get-Date)-$errSince).TotalSeconds -ge $Cfg.GeminiQuietSec){ throw "Gemini показал ошибку: $(Format-Short $s.tail 200)" } } else { $errSince=$null }
    $sig="$($s.gen)|$($s.n)|$($s.len)"; if($sig -ne $last){ $last=$sig; $quiet=Get-Date; continue }
    if(-not $s.gen -and [int]$s.n -gt $before -and [int]$s.len -gt 0 -and ((Get-Date)-$quiet).TotalSeconds -ge $Cfg.GeminiQuietSec){ return [int]$s.n }
  }
}
function GemCdp-GetCode{
  $b=@(Eval-Js 'codes'); $script:LastCodeLangs=@($b | ForEach-Object { Normalize-CodeLang ([string]$_.lang) })
  Log "Блоков кода в последнем ответе (CDP): $($b.Count) $(($script:LastCodeLangs | ForEach-Object { "'$_'" }) -join ', ')"
  if(-not $b.Count){ return $null }
  $i=Select-CodeBlockIndex -Langs @($b | ForEach-Object { [string]$_.lang }) -Lang $Cfg.CodeBlockLang -Pick $Cfg.CodeBlockPick
  if($i -lt 0){ return $null }; [string]$b[$i].code
}
function GemCdp-PeekAnswer{
  $s=Eval-Js 'state'; $np=[int](Eval-Js 'prompts'); $b=@(Eval-Js 'codes')
  $l=@($b | ForEach-Object { Normalize-CodeLang ([string]$_.lang) })
  $i=Select-CodeBlockIndex -Langs $l -Lang $Cfg.CodeBlockLang -Pick $Cfg.CodeBlockPick
  @{ answered=([int]$s.n -ge $np -and $np -gt 0 -and [int]$s.len -gt 0 -and -not $s.gen); labels=$l; md=($i -ge 0); code=$(if($i -ge 0){ [string]$b[$i].code }else{ $null }) }
}
function GemCdp-GetWhole{ [string](Eval-Js 'whole') }
# Лимиты (пункт 27A): вкладка gemini.google.com/usage в CDP-браузере — чтение Runtime.evaluate, обновление Page.reload (без фокуса).
# Вкладки нет — одна фоновая (Target.createTarget background) и она ОСТАЁТСЯ открытой для следующих проверок.
$script:CdpUsageReloadAt=$null
function GemCdp-GetUsageText{
  $t=$null
  try{ $t=Find-CdpUsageTarget }catch{ throw [GG.RelayNotSentException]::new("CDP: браузер с --remote-debugging-port=$($Cfg.CdpPort) не отвечает ($($_.Exception.Message))") }
  $fresh=$false
  if(-not $t){
    $c=Connect-Cdp
    $tid=(Invoke-Cdp 'Target.createTarget' @{ url=$Cfg.GeminiUsageUrl; background=$true } -Conn $c).targetId
    for($i=0;$i -lt 20 -and -not $t;$i++){ Start-Sleep -Milliseconds 300; $t=@(Cdp-HttpJson '/json/list' | Where-Object { $_.id -eq $tid }) | Select-Object -First 1 }
    if(-not $t){ throw 'фоновая вкладка лимитов не появилась' }
    Log 'Лимиты (CDP): вкладки лимитов не было — открыл фоновую, она останется открытой'; $fresh=$true; $script:CdpUsageReloadAt=Get-Date
  }
  $uc=Cdp-Open $t.webSocketDebuggerUrl
  try{
    $txt=''; try{ $txt=[string](Eval-Js 'body' -Conn $uc) }catch{}
    if(-not $fresh -and (Test-UsageStale $txt $script:CdpUsageReloadAt)){ [void](Invoke-Cdp 'Page.reload' @{ ignoreCache=$true } -Conn $uc); $script:CdpUsageReloadAt=Get-Date; Start-Sleep -Milliseconds 800 }
    $t0=Get-Date
    while($true){
      try{ $txt=[string](Eval-Js 'body' -Conn $uc) }catch{ $txt='' }
      if($txt -match '(Использовано|Used)\s*\d+\s*%|исчерпан|limit reached'){ return $txt }
      if(((Get-Date)-$t0).TotalSeconds -ge 25){ break }
      Start-Sleep 1
    }
    throw "страница лимитов не загрузилась (текст: $(Format-Short $txt 120))"
  } finally { Cdp-Close $uc }
}
# Только чтение (-testcdp): вкладки CDP-браузера
function GemCdp-Targets{ @(Cdp-HttpJson '/json/list' | Where-Object { $_.type -eq 'page' } | ForEach-Object { [pscustomobject]@{ title=[string]$_.title; url=[string]$_.url } }) }

# ---------- Переключатель модели (CDP) ----------
function GemCdp-ModelItems{ @(Eval-Js 'modelItems' | ForEach-Object { $_ } | Where-Object { $_ -and $_.name -and $_.name -notmatch $Cfg.ModelMenuSkipRx } | ForEach-Object { $i=ConvertTo-ModelItemInfo ([string]$_.name) ([bool]$_.enabled); if($_.selected){ $i.selected=$true }; $i }) }
function GemCdp-OpenModelMenu{
  if(-not (Eval-Js 'modelOpen')){ throw 'CDP: переключатель модели Gemini не найден' }
  for($i=0;$i -lt 10;$i++){ Start-Sleep -Milliseconds 300; $it=@(GemCdp-ModelItems); if($it.Count){ return $it } }
  @()
}
function GemCdp-ListModels{
  $cur=GemCdp-GetModel; $items=@()
  try{ $items=@(GemCdp-OpenModelMenu) } finally { try{ [void](Eval-Js 'modelClose') }catch{} }
  @{ current=$cur; items=$items }
}
function GemCdp-SelectModel([string]$Want){
  $cur=GemCdp-GetModel
  if($cur -and $cur.IndexOf($Want,[StringComparison]::OrdinalIgnoreCase) -ge 0){ return $cur }
  $s=Eval-Js 'state'; if($s -and $s.gen){ throw 'Gemini сейчас отвечает — модель не переключаю' }
  try{
    $items=@(GemCdp-OpenModelMenu)
    if(-not $items.Count){ throw 'CDP: меню моделей не открылось' }
    $r=Eval-Js 'modelPick' @{ want=$Want; skip=$Cfg.ModelMenuSkipRx }
    if(-not $r.ok){
      if($r.err -eq 'disabled'){ throw "пункт «$((ConvertTo-ModelItemInfo ([string]$r.name)).name)» недоступен (лимит ещё не обновился?)" }
      throw "в меню моделей нет пункта «$Want» (есть: $((@($items | ForEach-Object { $_.name }) -join '; ')))"
    }
    Start-Sleep -Milliseconds 1200
  } finally { try{ [void](Eval-Js 'modelClose') }catch{} }
  GemCdp-GetModel
}
