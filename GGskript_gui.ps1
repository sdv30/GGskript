# ===== GGskript v2 GUI: панель управления (WinForms, без установок) =====
# Запуск скрыто через GGskript_launch.vbs. Воркер (GGskript.ps1) работает отдельным скрытым процессом.
$ErrorActionPreference='Continue'
$dir=$PSScriptRoot
. (Join-Path $dir 'lib\Core.ps1'); Repair-PSModulePath; . (Join-Path $dir 'lib\State.ps1'); . (Join-Path $dir 'lib\Platform.Win.ps1'); . (Join-Path $dir 'lib\Gui.Core.ps1')
$Cfg=(Merge-Settings -Defaults (Get-DefaultSettings -Root $dir) -OverridePath (Join-Path $dir 'relay_settings.json')).Cfg
$Worker=Join-Path $dir 'GGskript.ps1'; $IcoF=Join-Path $dir 'GGskript.ico'

try{ Initialize-Platform; [void](Initialize-Dpi) }catch{}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- единственный экземпляр (Local\ — в пределах сеанса пользователя) ----
$mtx=Enter-SingleInstance $Cfg.GuiMutex
if(-not $mtx){
  Remove-Item -LiteralPath $Cfg.PauseFile -EA 0
  $w=Get-Process | Where-Object { $_.MainWindowTitle -eq 'GGskript' -and $_.Id -ne $PID } | Select-Object -First 1
  if($w){ [void][GG.Native]::ShowWindow($w.MainWindowHandle,9); [void][GG.Native]::SetForegroundWindow($w.MainWindowHandle) }
  return
}
function Worker-Alive{ Test-WorkerAlive -StatusPath $Cfg.StatusFile -MutexName $Cfg.WorkerMutex -MutexCheck { param($n) Test-InstanceRunning $n } }
function Start-Worker{
  Remove-Item -LiteralPath $Cfg.StopFile -EA 0
  Start-Process powershell -WindowStyle Hidden -WorkingDirectory $dir -ArgumentList '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$Worker+'"')
}
function Send-Cmd($text){ [void](Send-GuiCmd -Path $Cfg.CmdFile -Text $text) }

# ---- форма ----
$font=New-Object System.Drawing.Font('Segoe UI',9)
$mono=New-Object System.Drawing.Font('Consolas',9.5)
$form=New-Object System.Windows.Forms.Form
$form.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
$form.Text='GGskript'; $form.Font=$font
$form.Size=New-Object System.Drawing.Size(820,640)
$form.MinimumSize=New-Object System.Drawing.Size(700,520)
$form.StartPosition='CenterScreen'
try{ if(Test-Path -LiteralPath $IcoF){ $form.Icon=New-Object System.Drawing.Icon($IcoF) } }catch{}
$form.TopMost=$false

$pnlTop=New-Object System.Windows.Forms.TableLayoutPanel
$pnlTop.Dock='Top'; $pnlTop.AutoSize=$true; $pnlTop.ColumnCount=1; $pnlTop.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6); $pnlTop.BackColor=[System.Drawing.Color]::FromArgb(245,245,248)
function New-Lbl($t){ $l=New-Object System.Windows.Forms.Label; $l.AutoSize=$true; $l.Text=$t; $l.Margin=New-Object System.Windows.Forms.Padding(3,2,3,2); $l }
$lblState=New-Lbl 'Состояние: …'; $lblState.Font=New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$lblModel=New-Lbl 'Модель: —'; $lblFile=New-Lbl 'Файл/этап: —'; $lblLim=New-Lbl 'Лимиты: —'; $lblAct=New-Lbl ''; $lblAct.ForeColor=[System.Drawing.Color]::Gray
$pnlTop.Controls.AddRange(@($lblState,$lblModel,$lblFile,$lblLim,$lblAct))

$pnlBtn=New-Object System.Windows.Forms.FlowLayoutPanel
$pnlBtn.Dock='Top'; $pnlBtn.AutoSize=$true; $pnlBtn.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6)
function New-Btn($text){ $b=New-Object System.Windows.Forms.Button; $b.Text=$text; $b.AutoSize=$true; $b.Margin=New-Object System.Windows.Forms.Padding(3,2,3,2); $b }
$btnStart=New-Btn 'Старт'; $btnPause=New-Btn 'Стоп'; $btnStop=New-Btn 'Выключить скрипт'; $btnLim=New-Btn 'Лимиты'; $btnStat=New-Btn 'Статус'
$btnAcc=New-Btn 'Accept All'; $btnShot=New-Btn 'Скриншот'; $btnDir=New-Btn 'Открыть папку'
$pnlBtn.Controls.AddRange(@($btnStart,$btnPause,$btnStop,$btnLim,$btnStat,$btnAcc,$btnShot,$btnDir))

$pnlCmd=New-Object System.Windows.Forms.Panel
$pnlCmd.Dock='Bottom'; $pnlCmd.Height=40; $pnlCmd.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6)
$txtCmd=New-Object System.Windows.Forms.TextBox; $txtCmd.Dock='Fill'; $txtCmd.Font=$font
$btnSend=New-Object System.Windows.Forms.Button; $btnSend.Text='Отправить'; $btnSend.Dock='Right'; $btnSend.Width=100
$pnlCmd.Controls.Add($txtCmd); $pnlCmd.Controls.Add($btnSend)

$txtLog=New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock='Fill'; $txtLog.ReadOnly=$true; $txtLog.Font=$mono; $txtLog.BackColor=[System.Drawing.Color]::FromArgb(24,24,28); $txtLog.ForeColor=[System.Drawing.Color]::Gainsboro
$txtLog.WordWrap=$false; $txtLog.ScrollBars='Both'; $txtLog.DetectUrls=$false

$form.Controls.Add($txtLog); $form.Controls.Add($pnlCmd); $form.Controls.Add($pnlBtn); $form.Controls.Add($pnlTop)

# ---- хвост лога ----
$script:logPos=-1
function Load-LogTail{
  try{
    $r=Read-LogTail -Path $Cfg.LogFile -Pos $script:logPos; $script:logPos=$r.Pos
    if($r.Text){
      $atEnd=Test-AtEnd $txtLog.SelectionStart $txtLog.TextLength
      $txtLog.AppendText($r.Text)
      if($txtLog.TextLength -gt 400000){ $txtLog.Text=$txtLog.Text.Substring($txtLog.TextLength-300000); $atEnd=$true }
      if($atEnd){ $txtLog.SelectionStart=$txtLog.TextLength; $txtLog.ScrollToCaret() }
    }
  }catch{}
}
function Update-Status{
  if(-not (Worker-Alive)){
    $lblState.Text='Состояние: воркер не запущен'; $lblState.ForeColor=[System.Drawing.Color]::DimGray
    $lblModel.Text='Модель: —'; $lblFile.Text='Нажмите «Старт», чтобы запустить передачу.'; $lblLim.Text='Лимиты: —'; $lblAct.Text=''
    return
  }
  try{
    $j=[IO.File]::ReadAllText($Cfg.StatusFile,[Text.Encoding]::UTF8) | ConvertFrom-Json; $v=Get-GuiStateView $j
    $lblState.Text=$v.State; $lblState.ForeColor=[System.Drawing.Color]::FromName($v.Color)
    $lblModel.Text=$v.Model; $lblFile.Text=$v.File; $lblLim.Text=$v.Limits; $lblAct.Text=$v.Action
  }catch{}
}
$timer=New-Object System.Windows.Forms.Timer; $timer.Interval=800
$timer.Add_Tick({ Load-LogTail; Update-Status })

$btnStart.Add_Click({ Remove-Item -LiteralPath $Cfg.PauseFile -EA 0; if(-not (Worker-Alive)){ Start-Worker } else { Send-Cmd 'старт' } })
$btnPause.Add_Click({ try{ New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null }catch{} })
$btnStop.Add_Click({
  $r=[System.Windows.Forms.MessageBox]::Show("Выключить GGskript (воркер) совсем? Из Telegram запустить снова будет нельзя — только кнопкой «Старт» здесь или ярлыком.`nЧтобы просто остановиться и слушать Telegram — кнопка «Стоп».",'GGskript',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
  if($r -eq 'Yes'){ try{ New-Item -ItemType File $Cfg.StopFile -Force | Out-Null }catch{} }
})
$btnLim.Add_Click({ Send-Cmd 'лимиты' }); $btnStat.Add_Click({ Send-Cmd 'статус' }); $btnAcc.Add_Click({ Send-Cmd 'прими' }); $btnShot.Add_Click({ Send-Cmd 'скрин' })
$btnDir.Add_Click({ Start-Process explorer.exe $dir })
$doSend={ $t=$txtCmd.Text.Trim(); if($t){ Send-Cmd $t; $txtCmd.Clear() } }
$btnSend.Add_Click($doSend)
$txtCmd.Add_KeyDown({ if($_.KeyCode -eq 'Enter'){ $_.SuppressKeyPress=$true; & $doSend } })

$form.Add_FormClosing({
  if((Get-CloseAction ([string]$_.CloseReason)) -ne 'ask'){ return }
  $r=[System.Windows.Forms.MessageBox]::Show("Закрыть панель GGskript?`n`nДа — остановить передачу и закрыть.`nНет — закрыть окно, оставить передачу в фоне.`nОтмена — не закрывать.",'GGskript',[System.Windows.Forms.MessageBoxButtons]::YesNoCancel,[System.Windows.Forms.MessageBoxIcon]::Question)
  if($r -eq 'Cancel'){ $_.Cancel=$true }
  elseif($r -eq 'Yes'){ try{ New-Item -ItemType File $Cfg.StopFile -Force | Out-Null }catch{} }
})
$form.Add_Shown({ if(-not (Worker-Alive)){ Start-Worker }; Load-LogTail; Update-Status; $timer.Start() })
try{ [void]$form.ShowDialog() } finally { $timer.Stop(); $timer.Dispose(); Exit-SingleInstance $mtx }
