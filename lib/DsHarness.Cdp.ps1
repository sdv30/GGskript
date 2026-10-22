# ===== GGskript v2: DeepSeek Harness через Chrome DevTools Protocol (пункт 51, AgTarget='dsharness') =====
# DeepSeek Harness 0.2.1 — Electron (dsh-desktop). Запуск с портом: "DeepSeek Harness.exe" --remote-debugging-port=<DshCdpPort>.
# Страница dsh-app://app/. Селекторы сняты вживую 22.10.2026 (RU-интерфейс), переопределяются в relay_settings.json → "DshCdpSelectors".
# Порт 9230 приложения (dsh-experimental-inspector, «DeepSeek Harness Host») — доступ к самому агенту, НЕ используется.
$script:DshCdpSelDefault=[ordered]@{
  input  = '[data-composer-input][contenteditable="true"], [role="textbox"][data-lexical-editor="true"]'
  send   = 'button[aria-label="Отправить сообщение"], button[aria-label="Send message"]'
  busy   = 'button[aria-label="Остановить генерацию"], button[aria-label^="Stop generat"]'
  answer = '[data-chat-flow-kind="assistant-step"][data-turn-process-answer]'
  user   = '[data-chat-flow-kind="user"]'
  error  = '[data-chat-flow-kind="turn-error"]'
  ctx    = 'button[aria-label*="контекста"], button[aria-label*="context"]'
  stat   = '[data-composer-stat]'
  access = 'button[aria-label^="Режим доступа"], button[aria-label^="Access mode"]'
  model  = 'button[aria-label^="Выбор модели"], button[aria-label^="Model"]'
  newSession = 'button[class*="_newSession"]'
}
function Get-DshCdpSelectors{
  $s=[ordered]@{}; foreach($k in $script:DshCdpSelDefault.Keys){ $s[$k]=$script:DshCdpSelDefault[$k] }
  if($Cfg.DshCdpSelectors){ foreach($k in @($Cfg.DshCdpSelectors.Keys)){ if($s.Contains($k) -and $Cfg.DshCdpSelectors[$k]){ $s[$k]=[string]$Cfg.DshCdpSelectors[$k] } } }
  $s
}
function Test-IsDsh{ [string]$Cfg.AgTarget -eq 'dsharness' }
function Get-IdeName{ if(Test-IsDsh){ 'DeepSeek Harness' } else { 'Antigravity' } }
function Get-IdePort{ if(Test-IsDsh){ [int]$Cfg.DshCdpPort } else { [int]$Cfg.AgCdpPort } }
$script:DshJs=@'
(function(S,op,arg){
  const qa=s=>{ try{ return Array.from(document.querySelectorAll(s)); }catch(e){ return []; } };
  const vis=e=>!!e&&!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length);
  const txt=e=>e?((e.innerText||e.textContent||'')+''):'';
  const norm=s=>((s||'')+'').replace(/\s+/g,' ').trim();
  const inp=()=>qa(S.input).find(vis)||null;
  const label=b=>norm((b.getAttribute('aria-label')||'')+' '+txt(b));
  const enabled=b=>!(b.disabled||b.getAttribute('aria-disabled')==='true');
  // кнопки остановки/отмены/отклонения НИКОГДА не нажимаю
  const stopRx=/cancel|отмен|stop|останов|abort|interrupt|reject|отклон|запрет|deny|всегда|always/i;
  const isStop=b=>qa(S.busy).includes(b)||stopRx.test(label(b)+' '+(b.getAttribute('title')||''));
  const busy=()=>qa(S.busy).some(vis);
  const last=s=>{ const a=qa(s); return a.length?a[a.length-1]:null; };
  const after=(a,b)=>!!(a&&b&&(b.compareDocumentPosition(a)&Node.DOCUMENT_POSITION_FOLLOWING));
  switch(op){
    case 'probe': { const e=inp(); return { input:!!e, title:document.title, url:location.href }; }
    case 'inputText': { const e=inp(); return e?txt(e).replace(/\n$/,''):null; }
    case 'focus': { const e=inp(); if(!e) return false; e.focus(); return document.activeElement===e||e.contains(document.activeElement); }
    case 'clear': { const e=inp(); if(!e) return false; e.focus(); document.execCommand('selectAll',false,null); document.execCommand('delete',false,null); return txt(e).trim().length===0; }
    case 'clickSend': { if(busy()) return false; const b=qa(S.send).find(x=>vis(x)&&enabled(x)&&!isStop(x)); if(!b) return false; b.click(); return true; }
    case 'busy': return busy();
    case 'body': return document.body?txt(document.body):'';
    case 'lastReply': {
      const a=last(S.answer), u=last(S.user), er=last(S.error);
      return { busy:busy(), text:a?norm(txt(a)):'', afterUser:!!(a&&(!u||after(a,u))), user:u?norm(txt(u)).slice(0,200):'', error:(er&&(!u||after(er,u)))?norm(txt(er)).slice(0,300):'' };
    }
    case 'limit': {
      const u=last(S.user), er=last(S.error);
      const e=(er&&(!u||after(er,u)))?norm(txt(er)):'';
      const c=qa(S.ctx).find(vis); const cm=c?((c.getAttribute('aria-label')||'').match(/(\d+)\s*%/)):null;
      const st=qa(S.stat).map(x=>(x.getAttribute('data-composer-stat')||'')+'='+norm(txt(x)));
      const acc=qa(S.access).find(vis), mdl=qa(S.model).find(vis);
      return { rate:/\b429\b|RATE_LIMIT|FreeUsageLimit|rate limit/i.test(e), error:e.slice(0,300), ctx:cm?parseInt(cm[1],10):null, stats:st, access:acc?norm(txt(acc)):'', model:mdl?norm(mdl.getAttribute('title')||txt(mdl)):'' };
    }
    case 'acceptAll': {
      // Шаг «принять все изменения»: только точный текст «Принять все»/«Accept all». Отклонение — никогда.
      const cand=qa('button,[role="button"],span').filter(x=>vis(x)&&enabled(x)&&/^(accept all|принять все|принять всё)$/i.test(norm(txt(x)))&&!x.querySelector('span,button'));
      if(!cand.length) return { found:false, busy:busy() };
      if(busy()) return { found:true, ok:false, busy:true, why:'агент ещё работает' };
      if(arg&&arg.dry) return { found:true, ok:false, busy:false, why:'dry' };
      cand[0].click(); return { found:true, ok:true, busy:false };
    }
    case 'allowPrompt': {
      // Запрос разрешения: только «разрешить один раз». Никогда — всегда / запретить / отклонить / отмена.
      const ore=new RegExp(arg.opt,'i');
      const b=qa('button,[role="button"]').filter(x=>vis(x)&&enabled(x)&&!isStop(x)).find(x=>{ const t=norm(txt(x)); return t.length<=60&&ore.test(t); });
      if(!b) return { found:false };
      const t=norm(txt(b)); b.click(); return { found:true, ok:true, opt:t };
    }
    case 'newSession': { const b=qa(S.newSession).find(vis); if(!b) return false; b.click(); return true; }
  }
  throw new Error('unknown op '+op);
})
'@
$script:DshCdpConn=$null
function Connect-DshCdp([switch]$Force){
  if(-not $Force -and $script:DshCdpConn -and $script:DshCdpConn.ws -and $script:DshCdpConn.ws.State -eq 'Open'){ return $script:DshCdpConn }
  if($script:DshCdpConn){ Cdp-Close $script:DshCdpConn; $script:DshCdpConn=$null }
  $list=$null
  try{ $list=@(Cdp-HttpJson '/json/list' -Port $Cfg.DshCdpPort) }catch{ throw [GG.RelayNotSentException]::new("CDP DeepSeek Harness: порт $($Cfg.DshCdpPort) не отвечает — Harness запущен без --remote-debugging-port (кнопка «🛠 Harness с портом») ($($_.Exception.Message))") }
  foreach($t in @($list | Where-Object { $_.webSocketDebuggerUrl -and [string]$_.type -eq 'page' })){
    $c=$null
    try{
      $c=Cdp-Open $t.webSocketDebuggerUrl
      $p=DshEval-Js 'probe' -Conn $c
      if($p -and $p.input){ $c.targetId=$t.id; $c.title=[string]$t.title; $script:DshCdpConn=$c; try{ [void](Invoke-Cdp 'Emulation.setFocusEmulationEnabled' @{ enabled=$true } -Conn $c) }catch{}; return $c }
    }catch{}
    if($c){ Cdp-Close $c }
  }
  throw [GG.RelayNotSentException]::new('CDP DeepSeek Harness: нет окна с полем «Напишите агенту» — откройте сессию в Harness')
}
function DshEval-Js{
  param([string]$Op,$Arg=$null,$Conn)
  if(-not $Conn){ $Conn=Connect-DshCdp }
  $sel=(Get-DshCdpSelectors) | ConvertTo-Json -Compress
  $a= if($null -eq $Arg){ 'null' } else { ConvertTo-Json $Arg -Compress -Depth 5 }
  $r=Invoke-Cdp 'Runtime.evaluate' @{ expression="$($script:DshJs)($sel,$(ConvertTo-Json $Op -Compress),$a)"; returnByValue=$true; awaitPromise=$true; userGesture=$true } -Conn $Conn
  if($r.exceptionDetails){ throw "CDP DeepSeek Harness JS ($Op): $($r.exceptionDetails.exception.description)" }
  $r.result.value
}
function DshCdp-PressEnter($Conn){ foreach($t in 'rawKeyDown','keyUp'){ [void](Invoke-Cdp 'Input.dispatchKeyEvent' @{ type=$t; key='Enter'; code='Enter'; windowsVirtualKeyCode=13; nativeVirtualKeyCode=13 } -Conn $Conn) } }
function DshCdp-InputText($Conn){ [string](DshEval-Js 'inputText' -Conn $Conn) }
function DshCdp-IsBusy{ [bool](DshEval-Js 'busy') }
function DshCdp-LastReply{ DshEval-Js 'lastReply' }
function DshCdp-AcceptAll([switch]$Dry){ DshEval-Js 'acceptAll' @{ dry=[bool]$Dry } }
function DshCdp-AllowPrompt{ DshEval-Js 'allowPrompt' @{ opt=[string]$Cfg.DshAllowOptionRx } }
function DshCdp-Body{ [string](DshEval-Js 'body') }
function Test-DshDelivered([string]$Text){ Test-TextInBody -Text $Text -Body (DshCdp-Body) }
# Лимит: Harness квоту не публикует. 429/RATE_LIMIT в последнем шаге (после последнего сообщения) → rate=$true.
function Get-DshLimit{ DshEval-Js 'limit' }
# Тот же формат, что Get-AgQuota (h5/wk.rem): лимит неизвестен → 100%, чтобы порог Antigravity не останавливал работу.
function Get-DshQuota{
  $l=$null; try{ $l=Get-DshLimit }catch{}
  $note=' (DeepSeek Harness: квота не публикуется)'
  if($l -and $l.rate){ $note=' (DeepSeek Harness: последний шаг — 429 RATE_LIMIT)'; try{ Tg-Send "⚠️ DeepSeek Harness: последний шаг завершился ошибкой лимита модели: $(Format-Short ([string]$l.error) 160). Смените модель в Harness или подождите." -DedupMin 30 | Out-Null }catch{} }
  @{ h5=@{ rem=100; reset='—'; note=$note }; wk=@{ rem=100; reset='—'; note=$note }; dsh=$l }
}
# Отправка в чат Harness. Гарантии как у AgCdp-Send: чужой/меняющийся текст не трогаю; агент занят — не отправляю; Enter — только когда наш текст в поле.
function DshCdp-Send{
  param([Parameter(Mandatory)][string]$Text,[string]$Label='')
  $c=Connect-DshCdp
  if([bool](DshEval-Js 'busy' -Conn $c)){ throw (New-AgBlocked 'busy' 'DeepSeek Harness ещё работает (кнопка «Остановить генерацию») — НЕ отправляю' '') }
  $marker=Get-Marker $Text
  $has={ param($t) [bool]($marker -and ([string]$t).IndexOf($marker,[StringComparison]::OrdinalIgnoreCase) -ge 0) }
  $reads=@(); for($i=0;$i -lt [Math]::Max(1,[int]$Cfg.AgFieldReads);$i++){ if($i){ Start-Sleep -Milliseconds 250 }; $reads+=,(DshCdp-InputText $c) }
  $pre=[string]$reads[-1]
  if(@($reads | Select-Object -Unique).Count -gt 1){ throw (New-AgBlocked 'foreign' "В поле чата DeepSeek Harness текст меняется (кто-то печатает): '$(Get-First40 $pre)' — не трогаю" (Get-First40 $pre)) }
  if($pre.Trim()){
    if(& $has $pre){ Log 'В поле DeepSeek Harness остался наш прошлый текст — очищаю (CDP)'; [void](DshEval-Js 'clear' -Conn $c) }
    else { throw (New-AgBlocked 'foreign' "В поле чата DeepSeek Harness чужой текст: '$(Get-First40 $pre)' — не трогаю, НЕ отправляю" (Get-First40 $pre)) }
  }
  if(-not (DshEval-Js 'focus' -Conn $c)){ throw [GG.RelayNotSentException]::new('CDP DeepSeek Harness: фокус в поле чата не подтверждён — НЕ отправляю') }
  [void](Invoke-Cdp 'Input.insertText' @{ text=$Text } -Conn $c)
  if(-not (Wait-Until { & $has (DshCdp-InputText $c) } 6)){
    $after=DshCdp-InputText $c
    try{ if(-not (& $has $after) -and $after.Trim() -and $after -ne $pre){ [void](DshEval-Js 'clear' -Conn $c) } }catch{}
    throw (New-AgBlocked 'unknown' 'Текст не появился в поле DeepSeek Harness (CDP) — НЕ отправлен' "после вставки: $($after.Length) симв.")
  }
  DshCdp-PressEnter $c
  $gone=Wait-Until { -not (& $has (DshCdp-InputText $c)) } 4
  if(-not $gone -and -not [bool](DshEval-Js 'busy' -Conn $c) -and (DshEval-Js 'clickSend' -Conn $c)){ Log 'DeepSeek Harness (CDP): Enter не отправил — нажал «Отправить сообщение»'; $gone=Wait-Until { -not (& $has (DshCdp-InputText $c)) } 4 }
  if(-not $gone){ throw (New-AgBlocked 'unknown' 'После Enter текст остался в поле DeepSeek Harness — сообщение не ушло' (Get-First40 (DshCdp-InputText $c))) }
  $script:AgPending=@{ key=(Get-NormKey $Text 40); label=$Label; time=Get-Date }
  Log "Отправлено в DeepSeek Harness через CDP ($Label), без фокуса"
}
# Ждать ответ (для -testdsh и проверки связи): @{ok;text;error}
function DshCdp-WaitReply([int]$TimeoutSec=120){
  $t0=Get-Date; Start-Sleep -Milliseconds 800
  while(((Get-Date)-$t0).TotalSeconds -lt $TimeoutSec){
    $r=DshCdp-LastReply
    if($r -and -not $r.busy){ if($r.error){ return @{ ok=$false; text=''; error=$r.error } }; if($r.afterUser -and $r.text){ return @{ ok=$true; text=$r.text; error='' } } }
    Start-Sleep -Seconds 1
  }
  @{ ok=$false; text=''; error="нет ответа за $TimeoutSec с" }
}
function Get-DshCdpDiag{
  $d=[ordered]@{ port=$Cfg.DshCdpPort; chat=$null; field=$null; busy=$null; limit=$null; err='' }
  try{ $c=Connect-DshCdp -Force; $d.chat=$c.title; $d.field=DshCdp-InputText $c; $d.busy=DshCdp-IsBusy; $d.limit=Get-DshLimit }catch{ $d.err=$_.Exception.Message }
  $d
}
# пункт 53: окно/связь выбранной IDE для протокола запуска: @{ present; input; h; note }
function Get-IdeWindowState{
  if(Test-IsDsh){
    try{ $c=Connect-DshCdp; return @{ present=$true; input=$true; h=$null; note="порт $($Cfg.DshCdpPort), окно «$(Format-Short ([string]$c.title) 50)»" } }
    catch{ return @{ present=$false; input=$false; h=$null; note="порт $($Cfg.DshCdpPort): $($_.Exception.Message)" } }
  }
  $h=Ag-GetWindow; $i=$false; if($h){ try{ $i=[bool](AgUia-FindInput $h) }catch{} }
  @{ present=[bool]$h; input=$i; h=$h; note='' }
}
