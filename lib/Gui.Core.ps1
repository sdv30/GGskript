# ===== GGskript v2: логика панели управления (без WinForms — тестируется отдельно) =====

# Чтение нового хвоста лога с позиции Pos. Возвращает @{Text; Pos}.
# Первый вызов (Pos<0) — последние MaxInitial байт, начиная с целой строки. Файл стал короче (ротация) — читаем с начала.
# Поток и StreamReader закрываются всегда (finally). Незавершённая последняя строка не отдаётся — дочитаем в следующий раз.
function Read-LogTail{
  param([string]$Path,[long]$Pos=-1,[int]$MaxInitial=60000)
  if(-not (Test-Path -LiteralPath $Path)){ return @{ Text=''; Pos=0 } }
  $fs=$null
  try{
    $fs=[IO.File]::Open([IO.Path]::GetFullPath($Path),'Open','Read','ReadWrite,Delete')
    $len=$fs.Length; $initial=$false
    if($Pos -lt 0){ $initial=$true; $Pos=[Math]::Max(0,$len-$MaxInitial) }
    elseif($len -lt $Pos){ $Pos=0 }
    if($len -le $Pos){ return @{ Text=''; Pos=$Pos } }
    $fs.Position=$Pos
    $buf=New-Object byte[] ($len-$Pos); $read=0
    while($read -lt $buf.Length){ $n=$fs.Read($buf,$read,$buf.Length-$read); if($n -le 0){ break }; $read+=$n }
    $start=0
    if($initial -and $Pos -gt 0){ $nl=[Array]::IndexOf($buf,[byte]10,0,$read); $start= if($nl -ge 0){ $nl+1 } else { $read } }
    $end=[Array]::LastIndexOf($buf,[byte]10,$read-1)
    if($end -lt $start){ return @{ Text=''; Pos=($Pos+$start) } }
    $text=(New-Object Text.UTF8Encoding $false).GetString($buf,$start,$end-$start+1)
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){ $text=$text.Substring(1) }
    @{ Text=$text; Pos=($Pos+$end+1) }
  } finally { if($fs){ $fs.Dispose() } }
}
# Воркер жив: держит именованный мьютекс; иначе (старый воркер) — свежий relay_status.json и живой pid.
function Test-WorkerAlive{
  param([string]$StatusPath,[string]$MutexName,[scriptblock]$MutexCheck,[datetime]$Now=(Get-Date),[int]$FreshSec=15)
  if($MutexCheck){ if(& $MutexCheck $MutexName){ return $true } }
  if(-not (Test-Path -LiteralPath $StatusPath)){ return $false }
  try{
    $j=[IO.File]::ReadAllText([IO.Path]::GetFullPath($StatusPath),[Text.Encoding]::UTF8) | ConvertFrom-Json
    if($j.kind -eq 'stopped'){ return $false }
    $t=[datetime]::ParseExact([string]$j.ts,'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
    if(($Now-$t).TotalSeconds -ge $FreshSec){ return $false }
    if($j.pid){ return [bool](Get-Process -Id ([int]$j.pid) -EA 0) }
    $true
  }catch{ $false }
}
# Команда в commands.txt: одна строка, UTF-8 без BOM, с повторами при занятости файла.
function Send-GuiCmd([string]$Path,[string]$Text){
  $t=(([string]$Text) -replace '[\r\n]+',' ').Trim(); if(-not $t){ return $false }
  for($i=0;$i -lt 5;$i++){ try{ [IO.File]::AppendAllText([IO.Path]::GetFullPath($Path),$t+"`r`n",(New-Object Text.UTF8Encoding $false)); return $true }catch{ Start-Sleep -Milliseconds 60 } }
  $false
}
function Format-GuiLimits($j){
  $g= if($null -ne $j.gwebCur){ "Gemini сайт: исп. $($j.gwebCur)% (сброс $($j.gwebCurReset)); неделя $($j.gwebWk)% ($($j.gwebWkReset))" } else { 'Gemini сайт: —' }
  $a= if($null -ne $j.agH5){ "Antigravity: 5ч ост. $($j.agH5)% (сброс $($j.agH5Reset)); неделя ост. $($j.agWk)% ($($j.agWkReset))" } else { 'Antigravity: —' }
  if($j.quotaTime){ "Лимиты ($($j.quotaTime)) — $g | $a" } else { "Лимиты: $g | $a" }
}
function Get-GuiStateView($j){
  $tag= switch([string]$j.kind){ 'running'{'работает'} 'paused'{'⏸ Остановлен — ничего не делаю'} 'limit'{'ОСТАНОВЛЕНО (лимит/модель)'} 'operator'{'✋ ждёт решения оператора'} 'stopped'{'остановлен'} default{[string]$j.kind} }
  $color= switch([string]$j.kind){ 'running'{'ForestGreen'} 'paused'{'DarkOrange'} 'limit'{'Firebrick'} 'operator'{'Firebrick'} 'stopped'{'DimGray'} default{'Black'} }
  $pend= if($j.pending -and @($j.pending).Count){ (@($j.pending) -join '; ') } else { 'нет' }
  @{ State="Состояние: $tag — $($j.state)"; Color=$color
     Model="Модель Gemini: $(if($j.model){$j.model}else{'—'})$(if($j.limitStop){ ' | лимит: '+$j.limitModel })$(if($j.resumeAt){ ' | жду сброса в '+$j.resumeAt })"
     File="Проект: $(if($j.project){$j.project}else{'—'}) | Следующий файл: $(if($j.nextFile){$j.nextFile}else{'нет'}) | в работе: $pend | передан: $(if($j.lastDone){$j.lastDone}else{'—'})"
     Limits=(Format-GuiLimits $j); Action="посл. действие: $($j.lastAction)$(if($j.transport){' | '+$j.transport})" }
}
# Решение при закрытии окна: спрашивать только при закрытии пользователем; выход из Windows/диспетчер задач — не мешать.
function Get-CloseAction([string]$CloseReason){ if($CloseReason -eq 'UserClosing'){ 'ask' } else { 'close' } }
# Автопрокрутка: только если пользователь и так был в конце (не сбивать чтение старых строк).
function Test-AtEnd([int]$SelectionStart,[int]$TextLength){ $SelectionStart -ge ($TextLength-2) }

# ---------- Пункт 39: режим без мыши — Chrome и Antigravity с портом отладки (только по кнопке пользователя) ----------
# Порт слушает на 127.0.0.1? (быстро, без исключений наружу)
function Test-PortUp([int]$Port,[int]$TimeoutMs=300){
  $c=New-Object System.Net.Sockets.TcpClient
  try{ $a=$c.BeginConnect('127.0.0.1',$Port,$null,$null); if(-not $a.AsyncWaitHandle.WaitOne($TimeoutMs)){ return $false }; $c.EndConnect($a); $true }catch{ $false } finally { $c.Close() }
}
function Get-PortView([bool]$Up,[string]$Name,[int]$Port){ @{ Text="$(if($Up){'●'}else{'○'}) $Name ${Port}: $(if($Up){'порт есть — без мыши'}else{'нет порта — через окно'})"; Color=$(if($Up){'ForestGreen'}else{'Gray'}) } }
function Find-FirstPath([string[]]$Paths){ foreach($p in $Paths){ if($p -and (Test-Path -LiteralPath $p)){ return $p } }; $null }
function Get-ChromeExe{ Find-FirstPath @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") }
function Get-AgExe{ Find-FirstPath @("$env:LOCALAPPDATA\Programs\Antigravity IDE\Antigravity IDE.exe","$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe") }
# Аргументы как в Start-GeminiChrome.bat: отдельный профиль GGskript, обычный Chrome/Яндекс не трогаем.
function Get-GeminiChromeArgs([int]$Port,[string]$Profile){
  @("--remote-debugging-port=$Port",'--remote-debugging-address=127.0.0.1',"--remote-allow-origins=http://127.0.0.1:$Port","--user-data-dir=`"$Profile`"",'--no-first-run','--no-default-browser-check','https://gemini.google.com/app','https://gemini.google.com/usage')
}
function Get-AgDebugArgs([int]$Port){ @("--remote-debugging-port=$Port","--remote-allow-origins=http://127.0.0.1:$Port") }
# Запуск Chrome для Gemini с портом. Возвращает строку для журнала.
function Start-GeminiCdpChrome([int]$Port=9222,[scriptblock]$Starter={ param($exe,$a) Start-Process -FilePath $exe -ArgumentList $a }){
  if(Test-PortUp $Port){ return "🌐 Chrome с портом $Port уже запущен — новый не открываю." }
  $exe=Get-ChromeExe; if(-not $exe){ return '❌ Google Chrome не найден.' }
  $prof=Join-Path $env:LOCALAPPDATA 'GGskript\chrome-gemini-profile'; if(-not (Test-Path -LiteralPath $prof)){ [void](New-Item -ItemType Directory $prof -Force) }
  & $Starter $exe (Get-GeminiChromeArgs $Port $prof)
  "🌐 Запустил отдельный Chrome для Gemini с портом $Port (профиль GGskript). Обычный Chrome/Яндекс не трогал. Первый раз войдите в Google и откройте свой чат."
}
# Перезапуск Antigravity с портом: мягко закрыть (CloseMainWindow), подождать, запустить с флагом.
function Restart-AgCdp([int]$Port=9333,[int]$WaitSec=30,
  [scriptblock]$GetProcs={ @(Get-Process -Name 'Antigravity IDE','Antigravity' -EA 0) },
  [scriptblock]$Starter={ param($exe,$a) Start-Process -FilePath $exe -ArgumentList $a }){
  if(Test-PortUp $Port){ return "🛠 Antigravity уже с портом $Port — перезапуск не нужен." }
  $exe=Get-AgExe; if(-not $exe){ return '❌ Antigravity не найден.' }
  $ps=@(& $GetProcs)
  foreach($p in $ps){ try{ if($p.MainWindowHandle -ne [IntPtr]::Zero){ [void]$p.CloseMainWindow() } }catch{} }
  $t0=Get-Date; while(@(& $GetProcs).Count -and ((Get-Date)-$t0).TotalSeconds -lt $WaitSec){ Start-Sleep -Milliseconds 500 }
  if(@(& $GetProcs).Count){ return "❌ Antigravity не закрылся за $WaitSec с (возможно, ждёт сохранения файла). Закройте его сами (File → Exit) и нажмите кнопку ещё раз." }
  & $Starter $exe (Get-AgDebugArgs $Port)
  "🛠 Перезапустил Antigravity с портом $Port. Откройте прошлый разговор: значок часов → последний → Open in current window."
}

# ---------- Пункт 41: индикатор «чей ход» (Gemini / Antigravity) ----------
# Как рисовать индикатор: подписи, подсветка плиток, анимация.
function Get-TurnView([string]$Turn,[bool]$WorkerAlive=$true){
  if(-not $WorkerAlive){ $Turn='off' }
  switch($Turn){
    'gemini'      { @{ Caption='Ход Gemini';       G='active'; A='wait'; Anim=$true;  Color='ForestGreen' } }
    'antigravity' { @{ Caption='Ход Antigravity';  G='wait'; A='active'; Anim=$true;  Color='ForestGreen' } }
    'stopped'     { @{ Caption='⏸ Остановлен';     G='off';  A='off';    Anim=$false; Color='DimGray' } }
    'operator'    { @{ Caption='✋ Ждём оператора'; G='wait'; A='wait';   Anim=$false; Color='Firebrick' } }   # пункт 44: «СТОП — РЕШЕНИЕ ОПЕРАТОРА»
    'limit'       { @{ Caption='⛔ Лимит Gemini';   G='limit';A='off';    Anim=$false; Color='DarkOrange' } }
    'off'         { @{ Caption='Скрипт не запущен'; G='off';  A='off';    Anim=$false; Color='DimGray' } }
    default       { @{ Caption='Ожидание работы';  G='wait'; A='wait';   Anim=$false; Color='DimGray' } }
  }
}
function Get-TurnTileSub([string]$St){ switch($St){ 'active'{'в работе'} 'wait'{'ожидание'} 'limit'{'лимит'} default{'—'} } }
