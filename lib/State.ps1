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

function New-RelayState{ [ordered]@{ version=2; files=[ordered]@{}; hashes=@() } }
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
