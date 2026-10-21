# ===== GGskript v2: State — атомарная запись, единое состояние, машина переходов, лог =====

# Атомарная запись текста: tmp -> File.Replace (с .bak) или Move. По умолчанию UTF-8 с BOM (как Set-Content -Encoding UTF8 в PS 5.1).
function Write-AtomicText{
  param([Parameter(Mandatory)][string]$Path,[AllowEmptyString()][string]$Text,[switch]$NoBom,[switch]$NoBackup)
  $Path=[IO.Path]::GetFullPath($Path)
  $enc=New-Object System.Text.UTF8Encoding (-not $NoBom)
  $tmp="$Path.tmp"
  [IO.File]::WriteAllText($tmp,$Text,$enc)
  for($i=0;$i -lt 10;$i++){
    try{
      if([IO.File]::Exists($Path)){
        if($NoBackup){ [IO.File]::Replace($tmp,$Path,[System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Replace($tmp,$Path,"$Path.bak") }
      } else { [IO.File]::Move($tmp,$Path) }
      return
    }catch [System.IO.IOException]{ Start-Sleep -Milliseconds 100 }
     catch [System.UnauthorizedAccessException]{ Start-Sleep -Milliseconds 100 }
  }
  throw "Не удалось атомарно записать $Path"
}
# Читает JSON; при ошибке — из .bak. Возвращает @{ Data; Source='main'|'bak'|'none'; Error }
function Read-JsonWithBackup{
  param([Parameter(Mandatory)][string]$Path)
  $err=$null
  foreach($p in @($Path,"$Path.bak")){
    if(-not (Test-Path -LiteralPath $p)){ continue }
    try{
      $raw=[IO.File]::ReadAllText([IO.Path]::GetFullPath($p),[Text.Encoding]::UTF8)
      if(-not $raw.Trim()){ throw 'пустой файл' }
      return [pscustomobject]@{ Data=(ConvertTo-PlainHashtable ($raw | ConvertFrom-Json)); Source=$(if($p -eq $Path){'main'}else{'bak'}); Error=$err }
    }catch{ $err="$($p): $($_.Exception.Message)" }
  }
  [pscustomobject]@{ Data=$null; Source='none'; Error=$err }
}

# ---------- Этапы и переходы ----------
$script:TerminalStages=@('relayed','nocode','done','abandoned','skipped')
$script:StageTransitions=@{
  ''          = @('sent','resend','done','abandoned','nocode')
  'resend'    = @('sent','done','abandoned')
  'sent'      = @('answered','resend','nocode','stale','relayed','done')
  'answered'  = @('relayed','resend','stale','done')
  'stale'     = @('relayed','resend','done','abandoned')
  'nocode'    = @('resend')
  'abandoned' = @('resend')
  'skipped'   = @('resend')   # пункт 24: пропущен при запуске (сделан вручную/устарел); вернуть — только явной командой
  'relayed'   = @()
  'done'      = @()
}
function Get-StageRu([string]$Stage){
  switch($Stage){ 'sent'{'отправлен в Gemini, ждёт ответа'} 'answered'{'ответ скопирован, в Antigravity не подтверждён'} 'relayed'{'ответ передан в Antigravity'} 'nocode'{'нет блока Markdown (пропущен)'} 'resend'{'нужно отправить в Gemini заново'} 'stale'{'ответ совпал со старым — ждёт решения («передай всё равно» / «отправь заново»)'} 'done'{'обработан (до учёта этапов)'} 'abandoned'{'старый проект — пропущен (не отправлялся заново)'} 'skipped'{'пропущен при запуске (сделан вручную или устарел) — не отправлялся'} default{'новый'} }
}
function Test-StageTransition([string]$From,[string]$To){ if($null -eq $From){ $From='' }; ($script:StageTransitions.ContainsKey($From) -and (@($script:StageTransitions[$From]) -contains $To)) }

function New-RelayState{ [ordered]@{ version=2; files=[ordered]@{}; hashes=@(); lastAgAt=''; activeProject=''; lastBlock=$null; lastSide=''; sent=@() } }
function Get-FileStage($State,[string]$Name){ if($State.files.Contains($Name)){ [string]$State.files[$Name].stage } else { '' } }
function Set-FileStage{
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Stage,[string]$Hash,[string]$Note,[switch]$Force)
  $from=Get-FileStage $State $Name
  if($from -eq $Stage -and -not $Force){ return $false }
  if(-not $Force -and -not (Test-StageTransition $from $Stage)){ throw "Недопустимый переход этапа для $($Name): '$from' → '$Stage'" }
  $old= if($State.files.Contains($Name)){ $State.files[$Name] } else { $null }
  $State.files[$Name]=[ordered]@{
    stage=$Stage; time=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    hash=$(if($Hash){$Hash}elseif($old){[string]$old.hash}else{''})
    attempts=$(if($old -and $old.attempts){[int]$old.attempts}else{0}) + $(if($Stage -eq 'sent'){1}else{0})
    note=$(if($Note){$Note}else{''})
  }
  $true
}
function Remove-FileStage($State,[string]$Name){ if($State.files.Contains($Name)){ $State.files.Remove($Name) } }
function Test-FileDone($State,[string]$Name){ $script:TerminalStages -contains (Get-FileStage $State $Name) }
function Test-RelayHash($State,[string]$Hash){ @($State.hashes) -contains $Hash }
function Add-RelayHash($State,[string]$Hash,[int]$Keep=200){ if(-not $Hash){ return }; $l=@(@($State.hashes) | Where-Object { $_ -ne $Hash }) + $Hash; if($l.Count -gt $Keep){ $l=$l[($l.Count-$Keep)..($l.Count-1)] }; $State.hashes=$l }

function Save-RelayState($State,[string]$Path){ Write-AtomicText -Path $Path -Text ($State | ConvertTo-Json -Depth 6) }
function Read-RelayState([string]$Path){
  $r=Read-JsonWithBackup $Path
  if(-not $r.Data){ return [pscustomobject]@{ State=$null; Source=$r.Source; Error=$r.Error } }
  $s=New-RelayState
  if($r.Data.files){ foreach($k in $r.Data.files.Keys){ $v=$r.Data.files[$k]; $s.files[$k]=[ordered]@{ stage=[string]$v.stage; time=[string]$v.time; hash=[string]$v.hash; attempts=[int]$v.attempts; note=[string]$v.note } } }
  if($r.Data.hashes){ $s.hashes=@($r.Data.hashes | ForEach-Object { [string]$_ }) }
  if($r.Data.lastAgAt){ $s.lastAgAt=[string]$r.Data.lastAgAt }
  if($r.Data.activeProject){ $s.activeProject=[string]$r.Data.activeProject }
  if($r.Data.lastSide){ $s.lastSide=[string]$r.Data.lastSide }
  if($r.Data.lastBlock){ $b=$r.Data.lastBlock; $s.lastBlock=[ordered]@{ project=[string]$b.project; step=[int]$b.step; hash=[string]$b.hash; at=[string]$b.at } }
  if($r.Data.sent){ $s.sent=@($r.Data.sent | ForEach-Object { [string]$_ }) }
  [pscustomobject]@{ State=$s; Source=$r.Source; Error=$r.Error }
}
# Чистка: удаляет только завершённые записи о файлах, которых уже НЕТ в папке, оставляя последние $Keep завершённых.
function Compress-RelayState{
  param($State,[string[]]$ExistingNames,[int]$Keep=500,[string]$Pattern)
  $exist=@{}; foreach($e in @($ExistingNames)){ $exist[$e]=1 }
  $term=@($State.files.Keys | Where-Object { (Test-FileDone $State $_) -and -not $exist.ContainsKey($_) })
  if($term.Count -le $Keep){ return 0 }
  $sorted=@($term | Sort-Object { Get-SortKey $_ $Pattern })
  $drop=$sorted[0..($sorted.Count-$Keep-1)]
  foreach($k in $drop){ $State.files.Remove($k) }
  $drop.Count
}

# ---------- Лог ----------
function Invoke-LogRotate{
  param([Parameter(Mandatory)][string]$Path,[double]$MaxMB=5,[int]$Keep=5)
  if(-not (Test-Path -LiteralPath $Path)){ return $false }
  if((Get-Item -LiteralPath $Path).Length -le $MaxMB*1MB){ return $false }
  for($i=$Keep-1;$i -ge 1;$i--){ if(Test-Path -LiteralPath "$Path.$i"){ Move-Item -LiteralPath "$Path.$i" -Destination "$Path.$($i+1)" -Force } }
  if(Test-Path -LiteralPath "$Path.$($Keep+1)"){ Remove-Item -LiteralPath "$Path.$($Keep+1)" -Force }
  Move-Item -LiteralPath $Path -Destination "$Path.1" -Force
  $true
}
$script:LogLines=0
function Log([string]$m,[switch]$NoAction){
  if(-not $NoAction){ $script:LastAction=Get-Date }
  $l="{0:HH:mm:ss}  {1}" -f (Get-Date),$m
  Write-Host $l
  if(-not $Cfg -or -not $Cfg.LogFile){ return }
  $script:LogLines++
  if(($script:LogLines % 200) -eq 1){ try{ [void](Invoke-LogRotate -Path $Cfg.LogFile -MaxMB $Cfg.LogMaxMB -Keep $Cfg.LogKeep) }catch{} }
  for($i=0;$i -lt 3;$i++){ try{ [IO.File]::AppendAllText([IO.Path]::GetFullPath($Cfg.LogFile),$l+[Environment]::NewLine,(New-Object System.Text.UTF8Encoding $false)); return }catch{ Start-Sleep -Milliseconds 50 } }
}

# ---------- Пункт 34: чья очередь — по времени ----------
function ConvertTo-StageTime([string]$t){ if(-not $t){ return $null }; try{ [datetime]::ParseExact($t,'yyyy-MM-dd HH:mm:ss',$null) }catch{ $null } }
# Время последней вставки в Antigravity: явная отметка lastAgAt или самое позднее время этапа «relayed».
function Get-LastAgRelayTime($State){
  $best=ConvertTo-StageTime ([string]$State.lastAgAt)
  foreach($k in @($State.files.Keys)){ $v=$State.files[$k]; if([string]$v.stage -eq 'relayed'){ $t=ConvertTo-StageTime ([string]$v.time); if($t -and (-not $best -or $t -gt $best)){ $best=$t } } }
  $best
}
# Отчёт новее последней вставки в Antigravity (с запасом GraceSec) — значит, Antigravity уже отработал промпт и сейчас очередь Gemini.
function Test-ReportNewerThanAg($State,[datetime]$FileTime,[int]$GraceSec=3){
  $t=Get-LastAgRelayTime $State; if(-not $t){ return $true }
  ($FileTime -gt $t.AddSeconds($GraceSec))
}
# Файл, уже обработанный (relayed/done/nocode), перезаписан ПОСЛЕ своего этапа — это новый отчёт под тем же именем.
function Test-ReportRewritten($State,[string]$Name,[datetime]$FileTime,[int]$GraceSec=5){
  if(-not $State.files.Contains($Name)){ return $false }
  $v=$State.files[$Name]; if([string]$v.stage -notin @('relayed','done','nocode')){ return $false }
  $t=ConvertTo-StageTime ([string]$v.time); if(-not $t){ return $false }
  ($FileTime -gt $t.AddSeconds($GraceSec))
}

# ---------- Пункт 41: чей ход (пишется воркером в relay_status.json, поле turn) ----------
# Сторона по этапу файла: отчёт ушёл в Gemini -> ждём Gemini; ответ передан в Antigravity -> ждём Antigravity.
function Get-TurnSideOfStage([string]$Stage,[string]$Prev){
  switch($Stage){ {$_ -in 'sent','resend','stale'}{ 'gemini' } {$_ -in 'answered','relayed'}{ 'antigravity' } default{ $Prev } }
}
# Чей ход сейчас: stopped | limit | gemini | antigravity | idle. Чистая функция (тесты Item41).
function Get-RelayTurn([string]$Kind,[string[]]$Stages=@(),[string]$NextFile='',[string]$LastSide='',[bool]$AgWatch=$false,[string]$Decision=''){
  if($Kind -in 'paused','stopped'){ return 'stopped' }
  if($Kind -eq 'limit'){ return 'limit' }
  if($Decision -in 'gemini','antigravity'){ return $Decision }   # пункт 43: решение по номеру шага и проекту
  if(@($Stages | Where-Object { $_ -in 'sent','resend','stale' }).Count){ return 'gemini' }      # отчёт в Gemini, ждём ответ
  if(@($Stages | Where-Object { $_ -eq 'answered' }).Count){ return 'antigravity' }             # ответ получен, идёт в Antigravity
  if($NextFile){ return 'gemini' }                                                              # новый отчёт ждёт отправки в Gemini
  if($AgWatch){ return 'antigravity' }                                                          # «Antigravity: текст» — ждём отчёт
  if($LastSide -in 'gemini','antigravity'){ return $LastSide }
  'idle'
}


# ---------- Пункт 43: очередь по номеру шага и проекту (чистые функции) ----------
# Время отчёта: самое позднее из LastWriteTime и CreationTime (копия файла может получить новое CreationTime при старом LastWriteTime).
function Get-ReportFileTime($f){
  $w=$f.LastWriteTime; $c=$null; try{ $c=$f.CreationTime }catch{}
  if($c -and $c -is [datetime] -and $c -gt $w){ $c } else { $w }
}
# Заголовок блока Gemini: «[ARGON>FLASH] [Arena] [S006] [2026-10-20]» (в первых строках; &gt; допускается). -> @{ project; step } или $null.
function Get-PromptHeader([string]$Text){
  $t=([string]$Text) -replace '&gt;','>' -replace '&lt;','<' -replace '&amp;','&'
  $head=(@($t -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' ')
  $m=[regex]::Match($head,'\[(?<project>[^\[\]>]+)\]\s*\[\s*(?:REWORK\s*)?S(?<n>\d{1,4})\s*\]')
  if(-not $m.Success){ return $null }
  $pr=$m.Groups['project'].Value.Trim(); if(-not $pr -or $pr -match '\s{2,}'){ return $null }
  @{ project=$pr; step=[int]$m.Groups['n'].Value }
}
# Кандидаты-отчёты: только проект $Project (если задан), не старше MaxAgeHours (если > 0); сортировка по времени файла, затем по номеру.
function Get-ReportCandidates{
  param($Files,[string]$Project,[string]$Pattern,[datetime]$Now=(Get-Date),[double]$MaxAgeHours=0)
  @(@($Files) | Where-Object { $_ } | ForEach-Object {
      $m=[regex]::Match([string]$_.Name,$Pattern); if(-not $m.Success){ return }
      $pr=$m.Groups['project'].Value; if($Project -and $pr -ne $Project){ return }
      $t= if($_.PSObject.Properties['Time'] -and $_.Time){ $_.Time } else { Get-ReportFileTime $_ }
      if($MaxAgeHours -gt 0 -and $t -lt $Now.AddHours(-$MaxAgeHours)){ return }
      [pscustomobject]@{ Name=[string]$_.Name; FullName=[string]$_.FullName; Time=$t; Num=[int]$m.Groups['n'].Value; Project=$pr }
    } | Sort-Object Time,Num)
}
# Активный проект: из заголовка последнего блока Gemini; иначе — проект самого свежего отчёта (по времени файла).
function Get-ActiveProject{
  param($Header,$Files,[string]$Pattern,[datetime]$Now=(Get-Date),[double]$MaxAgeHours=0,[string]$Known='')
  if($Header -and $Header.project){ return [string]$Header.project }
  $nw=@(Get-ReportCandidates -Files $Files -Pattern $Pattern -Now $Now -MaxAgeHours $MaxAgeHours) | Select-Object -Last 1
  if($nw){ return $nw.Project }; $Known
}
# Учёт отправленного: «kind|project|step|hash» (kind: ag — блок в Antigravity, gem — отчёт в Gemini).
function Add-SentRecord($State,[string]$Kind,[string]$Project,[int]$Step,[string]$Hash,[int]$Keep=300){
  $r="$Kind|$Project|$Step|$Hash"; $l=@(@($State.sent) | Where-Object { $_ -and $_ -ne $r }) + $r
  if($l.Count -gt $Keep){ $l=$l[($l.Count-$Keep)..($l.Count-1)] }; $State.sent=$l; $State.lastSide=$Kind
}
# Есть ли запись: по хэшу (если задан) или по проекту+шагу.
function Test-SentRecord($State,[string]$Kind,[string]$Project,[int]$Step=-1,[string]$Hash=''){
  foreach($r in @($State.sent)){ $p=([string]$r) -split '\|',4; if($p.Count -lt 4 -or $p[0] -ne $Kind){ continue }
    if($Hash -and $p[3] -eq $Hash){ return $true }
    if($Step -ge 0 -and $Project -and $p[1] -eq $Project -and [int]$p[2] -eq $Step){ return $true } }
  $false
}
# Решение «чей ход». $Header — заголовок последнего блока Gemini (или $null); $BlockHash — его хэш; $Report — самый свежий кандидат
# (Get-ReportCandidates | Select -Last 1); $ReportHash — хэш его содержимого. -> @{ turn; action; project; step; num; report; reason; formatBroken; contradiction }
# action: relay-block | send-report | wait-report | wait-answer | wait
function Get-TurnDecision{
  param($Header,[string]$BlockHash='',$Report,[string]$ReportHash='',$State,[datetime]$LastAgAt=[datetime]::MinValue)
  $o=@{ turn='idle'; action='wait'; project=''; step=-1; num=-1; report=''; reason=''; formatBroken=$false; contradiction='' }
  if($Report){ $o.report=$Report.Name; $o.num=[int]$Report.Num; $o.project=$Report.Project }
  $blockSent= $BlockHash -and ((Test-SentRecord $State 'ag' '' -1 $BlockHash) -or (Test-RelayHash $State $BlockHash))
  $repSent= $Report -and ((($ReportHash) -and (Test-SentRecord $State 'gem' '' -1 $ReportHash)) -or (Test-SentRecord $State 'gem' $Report.Project $Report.Num))
  $repNew= $Report -and ($LastAgAt -eq [datetime]::MinValue -or $Report.Time -gt $LastAgAt.AddSeconds(3))
  if($Header){
    $o.project=$Header.project; $o.step=[int]$Header.step; $N=$o.step
    if($Report -and $Report.Project -ne $Header.project){ $Report=$null; $o.report=''; $o.num=-1; $repSent=$false; $repNew=$false }
    $M= if($Report){ $o.num } else { -1 }
    if($N -gt $M){
      $o.turn='antigravity'
      if($BlockHash -and -not $blockSent -and -not (Test-SentRecord $State 'ag' $o.project $N)){ $o.action='relay-block'; $o.reason="блок S$N новее отчёта $(if($M -ge 0){"№$M"}else{'(отчётов нет)'}) — передать в Antigravity" }
      elseif($BlockHash -and -not $blockSent){ $o.action='wait-report'; $o.contradiction="блок S$N с другим содержимым, а S$N уже передавался — повторно не передаю"; $o.reason="жду $($o.project)_…_$('{0:D3}' -f $N).md" }
      else { $o.action='wait-report'; $o.reason="S$N у Antigravity — жду $($o.project)_…_$('{0:D3}' -f $N).md" }
      return $o
    }
    # M >= N: отчёт на текущий шаг (или новее) есть
    if($repSent){ $o.turn='gemini'; $o.action='wait-answer'; $o.reason="отчёт №$M уже в Gemini — жду блок S$($M+1)"; return $o }
    if($repNew){ $o.turn='gemini'; $o.action='send-report'; $o.reason="отчёт №$M ≥ S$N и новее последней вставки — прикрепить в Gemini"; return $o }
    $o.turn='gemini'; $o.action='wait'; $o.contradiction="отчёт $($Report.Name) (№$M ≥ S$N) старее последней вставки в Antigravity — не отправляю, жду новый"; $o.reason=$o.contradiction; return $o
  }
  # заголовка нет — чередование по содержимому
  $o.formatBroken= [bool]$BlockHash
  $last=[string]$State.lastSide
  $canRelay= $BlockHash -and -not $blockSent
  $canSend= $Report -and -not $repSent -and $repNew
  if($last -eq 'ag'){ if($canSend){ $o.turn='gemini'; $o.action='send-report'; $o.reason='без номера: последним ушёл блок в Antigravity, есть новый отчёт' } else { $o.turn='antigravity'; $o.action='wait-report'; $o.reason='без номера: последним ушёл блок в Antigravity — жду отчёт' } }
  elseif($last -eq 'gem'){ if($canRelay){ $o.turn='antigravity'; $o.action='relay-block'; $o.reason='без номера: последним ушёл отчёт в Gemini, есть новый блок' } else { $o.turn='gemini'; $o.action='wait-answer'; $o.reason='без номера: последним ушёл отчёт в Gemini — жду блок' } }
  elseif($canSend){ $o.turn='gemini'; $o.action='send-report'; $o.reason='без номера: новый отчёт' }
  elseif($canRelay){ $o.turn='antigravity'; $o.action='relay-block'; $o.reason='без номера: новый блок' }
  $o
}
