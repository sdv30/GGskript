# ===== GGskript v2: Antigravity через Chrome DevTools Protocol (AgTransport='cdp', пункт 27B) =====
# Без фокуса, клавиатуры ОС и буфера обмена: текст — Input.insertText, Enter — Input.dispatchKeyEvent в страницу,
# кнопки — click() в DOM. Antigravity нужно один раз перезапустить с --remote-debugging-port=<AgCdpPort>
# (Start-Antigravity-Debug.bat). Порт слушает только 127.0.0.1.
# Селекторы — ниже; при изменении вёрстки их можно переопределить в relay_settings.json → "AgCdpSelectors".

$script:AgCdpSelDefault=[ordered]@{
  input = '[aria-label="Message input"], [role="combobox"][contenteditable="true"], div[contenteditable="true"][class*="cursor-text"]'
  # по исходникам Antigravity IDE 1.107 (out\jetskiAgent\main.js, чтение 19.10): поле — aria-label «Message input»;
  # отправка — button[data-testid=send-button] «Send message»; во время работы агента на её месте «Cancel (Ctrl+D)».
  send  = 'button[data-testid="send-button"], button[aria-label="Send message"]'
  busy  = 'button[data-tooltip-id="input-send-button-cancel-tooltip"], button[aria-label^="Cancel ("]'
}
function Get-AgCdpSelectors{
  $s=[ordered]@{}; foreach($k in $script:AgCdpSelDefault.Keys){ $s[$k]=$script:AgCdpSelDefault[$k] }
  if($Cfg.AgCdpSelectors){ foreach($k in @($Cfg.AgCdpSelectors.Keys)){ if($s.Contains($k) -and $Cfg.AgCdpSelectors[$k]){ $s[$k]=[string]$Cfg.AgCdpSelectors[$k] } } }
  $s
}
$script:AgJs=@'
(function(S,op,arg){
  const qa=s=>{ try{ return Array.from(document.querySelectorAll(s)); }catch(e){ return []; } };
  const vis=e=>!!e&&!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length);
  const txt=e=>e?((e.innerText||e.textContent||'')+''):'';
  const inp=()=>qa(S.input).find(vis)||null;
  const label=b=>(((b.getAttribute('aria-label')||'')+' '+txt(b)).replace(/\s+/g,' ')).trim();
  const enabled=b=>!(b.disabled||b.getAttribute('aria-disabled')==='true');
  // пункт 28: кнопки отмены/остановки агента НИКОГДА не нажимаю (на месте «Отправить» во время работы агента — «Cancel (Ctrl+D)»)
  const stopRx=/cancel|отмен|stop|останов|abort|interrupt|reject|отклон|ctrl\+d/i;
  const isStop=b=>{ if(qa(S.busy).includes(b)) return true; const a=[b.getAttribute('aria-label'),b.getAttribute('title'),b.getAttribute('data-tooltip-id'),b.getAttribute('data-testid'),txt(b)].map(x=>(x||'')+'').join(' '); return stopRx.test(a.replace(/send-button/g,'')); };
  switch(op){
    case 'probe': { const e=inp(); return { input:!!e, title:document.title, url:location.href }; }
    case 'inputText': { const e=inp(); return e?txt(e):null; }
    case 'focus': { const e=inp(); if(!e) return false; e.focus(); return document.activeElement===e||e.contains(document.activeElement); }
    case 'clear': { const e=inp(); if(!e) return false; e.focus(); document.execCommand('selectAll',false,null); document.execCommand('delete',false,null); return txt(e).trim().length===0; }
    case 'clickSend': { if(qa(S.busy).some(vis)) return false; const b=qa(S.send).find(x=>vis(x)&&enabled(x)&&!isStop(x)); if(!b) return false; b.click(); return true; }
    case 'busy': return qa(S.busy).some(vis);
    case 'buttons': { const re=new RegExp(arg.rx,'i'); return qa('button,[role="button"],a.monaco-button').filter(vis).map(label).filter(t=>re.test(t)); }
    case 'clickText': { const re=new RegExp(arg.rx,'i');
      const b=qa('button,[role="button"],a.monaco-button').filter(x=>vis(x)&&enabled(x)&&!isStop(x)).find(x=>re.test(txt(x).replace(/\s+/g,' ').trim())||re.test((x.getAttribute('aria-label')||'').trim()));
      if(!b) return false; b.click(); return true; }
    case 'acceptAll': {
      // «Accept all» в Antigravity — это <span class="... bg-primary ..."> с onClick, НЕ button (main.js 1.107), поэтому ищу и span.
      // Только точный текст «Accept all»; «Reject all», шеврон-меню и всё похожее на отмену — никогда.
      const norm=s=>((s||'')+'').replace(/\s+/g,' ').trim();
      const busy=qa(S.busy).some(vis);
      const fl=qa('span[data-tooltip-id="toolbar-title-tooltip"]').filter(vis).map(e=>norm(txt(e))).find(t=>/files? with changes/i.test(t))||'';
      const m=fl.match(/(\d+)\s+files?/i), files=m?parseInt(m[1],10):null;
      const cand=qa('span,button,[role="button"]').filter(x=>vis(x)&&enabled(x)&&/^accept all$/i.test(norm(txt(x)))&&!/reject|отклон/i.test(norm(txt(x)))&&!x.querySelector('span,button'));
      if(!cand.length) return { found:false, busy, files };
      if(busy) return { found:true, ok:false, busy, files, why:'агент ещё работает' };
      if(arg.dry) return { found:true, ok:false, busy, files, why:'dry' };
      cand[0].click(); return { found:true, ok:true, busy, files }; }
    case 'body': return document.body?txt(document.body):'';
    case 'allowPrompt': return (async()=>{
      // Автоподтверждение: вариант «Yes, allow this time» + Submit в той же панели. Никогда — always / No / Skip / Cancel.
      const ore=new RegExp(arg.opt,'i'), sre=new RegExp(arg.sub,'i'), deny=new RegExp(arg.deny,'i');
      const norm=s=>((s||'')+'').replace(/\s+/g,' ').trim();
      const subIn=root=>qa('button,[role="button"],a.monaco-button').filter(b=>root.contains(b)&&vis(b)&&!isStop(b)&&!deny.test(label(b))&&(sre.test(norm(txt(b)).replace(/\u21B5/g,'').trim())||sre.test(norm(b.getAttribute('aria-label')))||(b.getAttribute('data-testid')==='interaction-continue-button'&&/submit|подтверд/i.test(norm(txt(b))))));
      const rowOf=p=>{ const cl=p.closest('label,button,li,[role="radio"],[role="option"],[role="menuitemradio"],[role="button"]'); return (cl&&norm(txt(cl)).length<=160&&!deny.test(norm(txt(cl))))?cl:p; };
      // все видимые варианты; беру тот, у которого Submit ближе всего по дереву (не строку истории чата с тем же текстом)
      const tw=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); let n, best=null, seen=new Set();
      while((n=tw.nextNode())){ if(!/allow|разреш/i.test(n.data)) continue; const p=n.parentElement; if(!p||seen.has(p)||!vis(p)) continue; seen.add(p);
        const t=norm(n.data), pt=norm(txt(p));
        if(!((t&&t.length<=120&&ore.test(t)&&!deny.test(t))||(pt.length<=120&&ore.test(pt)&&!deny.test(pt)))) continue;
        const row=rowOf(p); let box=row, k=0; while(box&&k<=14&&!subIn(box).length){ box=box.parentElement; k++; }
        if(box&&k<=14&&(!best||k<best.k)) best={row,box,k};
        else if(!best) best={row,box:null,k:99}; }
      if(!best) return { found:false };
      const row=best.row, box=best.box;
      if(!box) return { found:true, ok:false, why:'нет кнопки Submit рядом с вариантом' };
      const title=(txt(box).split('\n').map(norm).find(x=>x)||'').slice(0,100);
      const radio=row.querySelector('input[type="radio"]'); (radio||row).click();
      await new Promise(r=>setTimeout(r,250));
      const st=radio?radio.checked:(row.hasAttribute('aria-checked')?row.getAttribute('aria-checked')==='true':(row.hasAttribute('aria-selected')?row.getAttribute('aria-selected')==='true':null));
      if(st===false) return { found:true, ok:false, why:'вариант не выбрался', title };
      if(!box.isConnected) return { found:true, ok:true, opt:norm(txt(row)), title, note:'панель закрылась после выбора' };
      const sb=subIn(box).find(enabled); if(!sb) return { found:true, ok:false, why:'Submit неактивна', title };
      sb.click(); return { found:true, ok:true, opt:norm(txt(row)), title };
    })();
  }
  throw new Error('unknown op '+op);
})
'@

$script:AgCdpConn=$null
# Все цели DevTools Antigravity (окна, webview, iframe) — ищу ту, где есть поле чата агента.
function Connect-AgCdp([switch]$Force){
  if(-not $Force -and $script:AgCdpConn -and $script:AgCdpConn.ws -and $script:AgCdpConn.ws.State -eq 'Open'){ return $script:AgCdpConn }
  if($script:AgCdpConn){ Cdp-Close $script:AgCdpConn; $script:AgCdpConn=$null }
  $list=$null
  try{ $list=@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort) }catch{ throw [GG.RelayNotSentException]::new("CDP Antigravity: порт $($Cfg.AgCdpPort) не отвечает — Antigravity запущен без --remote-debugging-port ($($_.Exception.Message))") }
  $cands=@($list | Where-Object { $_.webSocketDebuggerUrl -and @('page','iframe','webview','other') -contains [string]$_.type })
  foreach($t in $cands){
    $c=$null
    try{
      $c=Cdp-Open $t.webSocketDebuggerUrl
      $p=AgEval-Js 'probe' -Conn $c
      if($p -and $p.input){
        $c.targetId=$t.id; $c.title=[string]$t.title; $script:AgCdpConn=$c
        try{ [void](Invoke-Cdp 'Emulation.setFocusEmulationEnabled' @{ enabled=$true } -Conn $c) }catch{}
        return $c
      }
    }catch{}
    if($c){ Cdp-Close $c }
  }
  throw [GG.RelayNotSentException]::new("CDP Antigravity: нет вкладки с полем чата агента (целей: $($cands.Count)) — нет вкладки с чатом")
}
function AgEval-Js{
  param([string]$Op,$Arg=$null,$Conn)
  if(-not $Conn){ $Conn=Connect-AgCdp }
  $sel=(Get-AgCdpSelectors) | ConvertTo-Json -Compress
  $a= if($null -eq $Arg){ 'null' } else { ConvertTo-Json $Arg -Compress -Depth 5 }
  $r=Invoke-Cdp 'Runtime.evaluate' @{ expression="$($script:AgJs)($sel,$(ConvertTo-Json $Op -Compress),$a)"; returnByValue=$true; awaitPromise=$true; userGesture=$true } -Conn $Conn
  if($r.exceptionDetails){ throw "CDP Antigravity JS ($Op): $($r.exceptionDetails.exception.description)" }
  $r.result.value
}
# Enter прямо в страницу (не через клавиатуру ОС): keydown без символа — редактор чата отправляет сообщение.
function AgCdp-PressEnter($Conn){
  foreach($t in 'rawKeyDown','keyUp'){ [void](Invoke-Cdp 'Input.dispatchKeyEvent' @{ type=$t; key='Enter'; code='Enter'; windowsVirtualKeyCode=13; nativeVirtualKeyCode=13 } -Conn $Conn) }
}
function AgCdp-InputText($Conn){ [string](AgEval-Js 'inputText' -Conn $Conn) }
function AgCdp-IsBusy{ [bool](AgEval-Js 'busy') }
function AgCdp-HasButton([string]$Rx){ [bool]@(AgEval-Js 'buttons' @{ rx=$Rx }).Count }
function AgCdp-ClickText([string]$Rx){ [bool](AgEval-Js 'clickText' @{ rx=$Rx }) }
# «Accept all» (span с onClick) через DOM: @{found;ok;busy;files;why}. -Dry — только посмотреть.
function AgCdp-AcceptAll([switch]$Dry){ AgEval-Js 'acceptAll' @{ dry=[bool]$Dry } }
# Автоподтверждение через DOM (без фокуса): @{found;ok;opt;title;why}
function AgCdp-AllowPrompt{ AgEval-Js 'allowPrompt' @{ opt=$Cfg.AutoAllowOptionRx; sub=$Cfg.AutoAllowSubmitRx; deny=($script:AutoAllowDenyRx -replace '^\(\?i\)','') } }
# Отправка в чат агента. Те же гарантии, что у AgUia-Send: чужой/меняющийся текст — не трогаю; Enter — только когда наш текст в поле.
function AgCdp-Send{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='')
  [void](Assert-AgReady)
  $c=Connect-AgCdp
  $marker=Get-Marker $Text
  $has={ param($t) [bool]($marker -and ([string]$t).IndexOf($marker,[StringComparison]::OrdinalIgnoreCase) -ge 0) }
  $reads=@(); for($i=0;$i -lt [Math]::Max(1,[int]$Cfg.AgFieldReads);$i++){ if($i){ Start-Sleep -Milliseconds 250 }; $reads+=,(AgCdp-InputText $c) }
  $pre=[string]$reads[-1]
  if(@($reads | Select-Object -Unique).Count -gt 1){ throw (New-AgBlocked 'foreign' "В поле чата Antigravity текст меняется (кто-то печатает): '$(Get-First40 $pre)' — не трогаю" (Get-First40 $pre)) }
  if($pre.Trim()){
    if(& $has $pre){ Log 'В поле чата Antigravity остался наш прошлый текст — очищаю (CDP)'; [void](AgEval-Js 'clear' -Conn $c) }
    else { throw (New-AgBlocked 'foreign' "В поле чата Antigravity чужой текст: '$(Get-First40 $pre)' — не трогаю, НЕ отправляю" (Get-First40 $pre)) }
  }
  if(-not (AgEval-Js 'focus' -Conn $c)){ throw [GG.RelayNotSentException]::new('CDP Antigravity: фокус в поле чата не подтверждён — НЕ отправляю') }
  [void](Invoke-Cdp 'Input.insertText' @{ text=$Text } -Conn $c)
  if(-not (Wait-Until { & $has (AgCdp-InputText $c) } 6)){
    $after=AgCdp-InputText $c
    try{ if(& $has $after){ } elseif($after.Trim() -and $after -ne $pre){ [void](AgEval-Js 'clear' -Conn $c) } }catch{}
    throw (New-AgBlocked 'unknown' 'Текст не появился в поле чата Antigravity (CDP) — НЕ отправлен (Enter не нажимал)' "после вставки: $($after.Length) симв. «$(Get-First40 $after)»")
  }
  AgCdp-PressEnter $c
  $gone=Wait-Until { -not (& $has (AgCdp-InputText $c)) } 4
  # пункт 28: запасной клик по кнопке — только если агент НЕ занят (иначе на её месте «Cancel» и клик отменил бы работу агента)
  if(-not $gone -and -not [bool](AgEval-Js 'busy' -Conn $c) -and (AgEval-Js 'clickSend' -Conn $c)){ Log 'Antigravity (CDP): Enter не отправил — нажал кнопку отправки в DOM'; $gone=Wait-Until { -not (& $has (AgCdp-InputText $c)) } 4 }
  if(-not $gone){ throw (New-AgBlocked 'unknown' 'После Enter текст остался в поле Antigravity (CDP) — сообщение не ушло' (Get-First40 (AgCdp-InputText $c))) }
  $script:AgPending=@{ key=(Get-NormKey $Text 40); label=$Label; time=Get-Date }
  Log "Отправлено в Antigravity через CDP ($Label), без фокуса: текст был в поле и ушёл после Enter"
}
# Только чтение (-testcdp): цели DevTools Antigravity и состояние чата.
function Get-AgCdpDiag{
  $d=[ordered]@{ port=$Cfg.AgCdpPort; targets=@(); chat=$null; field=$null; busy=$null; accept=$null; err='' }
  try{ $d.targets=@(Cdp-HttpJson '/json/list' -Port $Cfg.AgCdpPort | ForEach-Object { "[$($_.type)] $(Format-Short ([string]$_.title) 60) — $(Format-Short ([string]$_.url) 80)" }) }catch{ $d.err="порт $($Cfg.AgCdpPort) не отвечает ($($_.Exception.Message))"; return $d }
  try{ $c=Connect-AgCdp -Force; $d.chat=$c.title; $d.field=AgCdp-InputText $c; $d.busy=AgCdp-IsBusy; $d.accept=[bool](AgCdp-AcceptAll -Dry).found }catch{ $d.err=$_.Exception.Message }
  $d
}
