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
  $tag= switch([string]$j.kind){ 'running'{'работает'} 'paused'{'СТОП (ждёт «Старт»)'} 'limit'{'ОСТАНОВЛЕНО (лимит/модель)'} 'stopped'{'остановлен'} default{[string]$j.kind} }
  $color= switch([string]$j.kind){ 'running'{'ForestGreen'} 'paused'{'DarkOrange'} 'limit'{'Firebrick'} 'stopped'{'DimGray'} default{'Black'} }
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
