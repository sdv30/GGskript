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
function Get-IdeLabel{ if([string]$Cfg.AgTarget -eq 'dsharness'){ 'DeepSeek Harness' } else { 'Antigravity' } }
function Send-Cmd($text){ [void](Send-GuiCmd -Path $Cfg.CmdFile -Text $text) }

# ---- форма ----
$font=New-Object System.Drawing.Font('Segoe UI',9)
$mono=New-Object System.Drawing.Font('Consolas',9.5)
$form=New-Object System.Windows.Forms.Form
$form.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
$form.Text='GGskript'; $form.Font=$font
$form.Size=New-Object System.Drawing.Size(820,708)
$form.MinimumSize=New-Object System.Drawing.Size(700,620)
$form.StartPosition='CenterScreen'
try{ if(Test-Path -LiteralPath $IcoF){ $form.Icon=New-Object System.Drawing.Icon($IcoF) } }catch{}
$form.TopMost=$false

$pnlTop=New-Object System.Windows.Forms.TableLayoutPanel
$pnlTop.Dock='Top'; $pnlTop.AutoSize=$true; $pnlTop.ColumnCount=1; $pnlTop.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6); $pnlTop.BackColor=[System.Drawing.Color]::FromArgb(245,245,248)
function New-Lbl($t){ $l=New-Object System.Windows.Forms.Label; $l.AutoSize=$true; $l.Text=$t; $l.Margin=New-Object System.Windows.Forms.Padding(3,2,3,2); $l }
$lblState=New-Lbl 'Состояние: …'; $lblState.Font=New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$lblModel=New-Lbl 'Модель: —'; $lblFile=New-Lbl 'Файл/этап: —'; $lblLim=New-Lbl 'Лимиты: —'; $lblAct=New-Lbl ''; $lblAct.ForeColor=[System.Drawing.Color]::Gray
$pnlTop.Controls.AddRange(@($lblState,$lblModel,$lblFile,$lblLim,$lblAct))

# ---- кнопки: те же 11, что в Telegram, по группам; всё остальное — в меню «☰ Ещё» ----
$btnFont=New-Object System.Drawing.Font('Segoe UI',9.75)
$grpFont=New-Object System.Drawing.Font('Segoe UI',8.25,[System.Drawing.FontStyle]::Bold)
$accent=[System.Drawing.Color]::FromArgb(0,95,184)
$pnlBtn=New-Object System.Windows.Forms.TableLayoutPanel
$pnlBtn.Dock='Top'; $pnlBtn.AutoSize=$true; $pnlBtn.ColumnCount=2; $pnlBtn.Padding=New-Object System.Windows.Forms.Padding(8,4,8,6)
[void]$pnlBtn.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,124)))
[void]$pnlBtn.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$tip=New-Object System.Windows.Forms.ToolTip
$emoFont=New-Object System.Drawing.Font('Segoe UI Emoji',11)
function New-IconBmp([string]$e,[System.Drawing.Color]$c=[System.Drawing.Color]::FromArgb(60,64,72)){
  $e=$e.Replace([string][char]0xFE0F,""); $bm=New-Object System.Drawing.Bitmap(24,22); $g=[System.Drawing.Graphics]::FromImage($bm); $g.TextRenderingHint='AntiAliasGridFit'
  $sf=New-Object System.Drawing.StringFormat; $sf.Alignment='Center'; $sf.LineAlignment='Center'
  $g.DrawString($e,$emoFont,(New-Object System.Drawing.SolidBrush($c)),(New-Object System.Drawing.RectangleF(0,0,24,22)),$sf); $g.Dispose(); $bm
}
function New-Btn([string]$text,[string]$hint='',[int]$w=184){
  $b=New-Object System.Windows.Forms.Button; $b.Font=$btnFont; $b.Size=New-Object System.Drawing.Size($w,32)
  # Значок (эмодзи) рисуем отдельно шрифтом Segoe UI Emoji: обычный текст кнопки WinForms показывает их квадратиками.
  if($text -match '^(\S+)\s+(.+)$' -and $matches[1] -cnotmatch '[A-Za-zА-Яа-яЁё]'){ $b.Text=$matches[2]; $b.Image=New-IconBmp $matches[1]; $b.ImageAlign='MiddleCenter'; $b.TextImageRelation='ImageBeforeText' } else { $b.Text=$text }
  $b.Margin=New-Object System.Windows.Forms.Padding(3,2,3,2); $b.FlatStyle='Flat'; $b.UseVisualStyleBackColor=$false
  $b.BackColor=[System.Drawing.Color]::White; $b.FlatAppearance.BorderColor=[System.Drawing.Color]::FromArgb(200,204,212)
  $b.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(232,240,252); $b.Cursor=[System.Windows.Forms.Cursors]::Hand
  if($hint){ $tip.SetToolTip($b,$hint) }; $b
}
function Add-BtnRow([string]$title,[object[]]$ctl){
  $l=New-Object System.Windows.Forms.Label; $l.Text=$title; $l.Font=$grpFont; $l.ForeColor=[System.Drawing.Color]::FromArgb(110,116,128)
  $l.AutoSize=$false; $l.Size=New-Object System.Drawing.Size(120,32); $l.TextAlign='MiddleLeft'; $l.Margin=New-Object System.Windows.Forms.Padding(0,2,0,2)
  $f=New-Object System.Windows.Forms.FlowLayoutPanel; $f.AutoSize=$true; $f.WrapContents=$true; $f.Dock='Fill'; $f.Margin=New-Object System.Windows.Forms.Padding(0)
  $f.Controls.AddRange($ctl); $r=$pnlBtn.RowCount; $pnlBtn.RowCount=$r+1
  $pnlBtn.Controls.Add($l,0,$r); $pnlBtn.Controls.Add($f,1,$r)
}
$btnRep=New-Btn '📂 Отчёт в Gemini' 'Последний отчёт агента из Downloads снова в Gemini (спрошу подтверждение)'
$btnFwd=New-Btn '📂 Ответ в Antigravity' 'Весь последний ответ Gemini в Antigravity (спрошу подтверждение)'
$btnAgT=New-Btn '🛠 Antigravity: текст' 'Ввести текст → в Antigravity; ответом будет новый отчёт агента (покажу в журнале)'
$btnGmT=New-Btn '✨ Gemini: текст' 'Ввести текст → в Gemini; ответ покажу в журнале'
$btnAns=New-Btn '✨ Ответ Gemini' 'Показать последний ответ Gemini в журнале'
$btnStat=New-Btn 'ℹ️ Статус' 'Подробный статус (в Telegram и журнал)'
$btnPause=New-Btn '⏸ Стоп' 'Полная остановка: прерываю текущее действие, мышь/клавиатуру/буфер/окна не трогаю, ничего не проверяю. Слушаю только Telegram и панель.'
$btnStart=New-Btn '▶️ Старт' 'Запустить или продолжить работу'
$btnShot=New-Btn '📸 Скрин' 'Снимок экрана в Telegram'
$btnLim=New-Btn '📊 Лимиты' 'Проверить лимиты Gemini и Antigravity'
$btnHelp=New-Btn '❓ Помощь' 'Список команд (в Telegram)'
$btnMore=New-Btn '☰ Ещё ▾' 'Остальные команды'
$btnStart.ForeColor=[System.Drawing.Color]::ForestGreen; $btnPause.ForeColor=[System.Drawing.Color]::DarkOrange; $btnMore.ForeColor=$accent
$chkAuto=New-Object System.Windows.Forms.CheckBox; $chkAuto.Text='Автоподтверждение запросов Antigravity'; $chkAuto.Font=$btnFont; $chkAuto.AutoSize=$true; $chkAuto.Margin=New-Object System.Windows.Forms.Padding(6,8,3,2)
$chkAuto.Checked=[bool]$Cfg.AutoAllowPrompts
$tip.SetToolTip($chkAuto,'Сам отвечает «Yes, allow this time» и нажимает Submit на запросы разрешения агента. Никогда не выбирает «always», «No», Skip.')
$chkAcc=New-Object System.Windows.Forms.CheckBox; $chkAcc.Text='Автопринятие Accept all'; $chkAcc.Font=$btnFont; $chkAcc.AutoSize=$true; $chkAcc.Margin=New-Object System.Windows.Forms.Padding(6,8,3,2)
$chkAcc.Checked= if($null -ne $Cfg.AutoAcceptAll){ [bool]$Cfg.AutoAcceptAll } else { $true }
$tip.SetToolTip($chkAcc,'Когда агент Antigravity закончил работу, сам нажимает «Accept all» внизу панели (через порт, без мыши). «Reject all» — никогда.')
Add-BtnRow 'ФАЙЛЫ' @($btnRep,$btnFwd)
Add-BtnRow 'ТЕКСТ И ОТВЕТЫ' @($btnAgT,$btnGmT,$btnAns)
Add-BtnRow 'УПРАВЛЕНИЕ' @($btnStat,$btnPause,$btnStart)
Add-BtnRow 'ПРОЧЕЕ' @($btnShot,$btnLim,$btnHelp)
Add-BtnRow '' @($btnMore,$chkAuto,$chkAcc)
# ---- пункт 39: режим без мыши (порты отладки) ----
$btnCdpG=New-Btn '🌐 Chrome с портом' 'Открыть отдельный Chrome для Gemini с портом 9222 (обычный Chrome/Яндекс не закрываю). С портом скрипт работает без мыши.' 200
$btnCdpA=New-Btn '🛠 Antigravity с портом' 'Перезапустить Antigravity с портом 9333 (спрошу подтверждение). С портом — без мыши и автоподтверждение надёжнее.' 200
$btnCdpD=New-Btn '🛠 Harness с портом' 'Перезапустить DeepSeek Harness с портом 9334 (спрошу подтверждение): закрою все его процессы, включая трей, и запущу с портом.' 200
$lblCdpG=New-Lbl '○ Gemini 9222: …'; $lblCdpA=New-Lbl '○ Antigravity 9333: …'; $lblCdpD=New-Lbl '○ Harness 9334: …'
# пункт 51: выбор IDE-стороны (меняется только при ⏸ Стоп или когда скрипт не запущен)
$lblIde=New-Lbl 'IDE:'; $lblIde.Margin=New-Object System.Windows.Forms.Padding(6,9,0,2)
$cmbIde=New-Object System.Windows.Forms.ComboBox; $cmbIde.DropDownStyle='DropDownList'; $cmbIde.Font=$btnFont; $cmbIde.Width=170; $cmbIde.Margin=New-Object System.Windows.Forms.Padding(3,5,3,2)
foreach($c in Get-IdeChoices){ [void]$cmbIde.Items.Add($c.t) }
$script:ideVals=@(Get-IdeChoices | ForEach-Object { $_.v }); $cmbIde.SelectedIndex=[Math]::Max(0,[array]::IndexOf($script:ideVals,[string]$Cfg.AgTarget))
$tip.SetToolTip($cmbIde,'Кто на стороне IDE: Antigravity или DeepSeek Harness. Сменить можно только при «⏸ Стоп».')
foreach($l in $lblCdpG,$lblCdpA,$lblCdpD){ $l.Margin=New-Object System.Windows.Forms.Padding(6,9,3,2); $l.ForeColor=[System.Drawing.Color]::Gray }
Add-BtnRow 'РЕЖИМ БЕЗ МЫШИ' @($btnCdpG,$btnCdpA,$btnCdpD,$lblCdpG,$lblCdpA,$lblCdpD)
Add-BtnRow 'IDE' @($lblIde,$cmbIde)

# ---- меню «☰ Ещё» ----
$menu=New-Object System.Windows.Forms.ContextMenuStrip; $menu.Font=$btnFont; $menu.ShowImageMargin=$false
function Add-Mi([string]$text,[scriptblock]$act){ $i=New-Object System.Windows.Forms.ToolStripMenuItem($text); if($act){ $i.Add_Click($act) }; [void]$menu.Items.Add($i); $i }
function Add-MHead([string]$text){ $i=New-Object System.Windows.Forms.ToolStripMenuItem($text); $i.Enabled=$false; $i.Font=$grpFont; [void]$menu.Items.Add($i) }
function Add-MSep{ [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }
Add-MHead 'ANTIGRAVITY'
[void](Add-Mi '✅ Принять «Accept all»' { Send-Cmd 'прими' })
[void](Add-Mi '📨 Передать ответ (блок Markdown)' { Send-Cmd 'передай ответ' })
[void](Add-Mi '⏩ Передать всё равно (совпавший ответ)' { Send-Cmd 'передай всё равно' })
$miAuto=Add-Mi '☑ Автоподтверждение запросов' { $chkAuto.Checked=-not $chkAuto.Checked }
Add-MSep; Add-MHead 'ОКНА И КОМПЬЮТЕР'
[void](Add-Mi '🪟 Список авто-закрываемых окон' { Send-Cmd 'список окон' })
[void](Add-Mi '🕑 Когда выключение компьютера' { Send-Cmd 'когда выключение' })
[void](Add-Mi '🚫 Отменить выключение компьютера' { Send-Cmd 'отмени выключение' })
Add-MSep; Add-MHead 'GGSKRIPT'
[void](Add-Mi '📁 Открыть папку проекта' { Start-Process explorer.exe $dir })
$miExit=Add-Mi '⛔ Выключить скрипт' $null; $miExit.ForeColor=[System.Drawing.Color]::Firebrick
$menu.Add_Opening({ $miAuto.Text= if($chkAuto.Checked){ '☑ Автоподтверждение: ВКЛ' } else { '☐ Автоподтверждение: выкл' } })

$pnlCmd=New-Object System.Windows.Forms.Panel
$pnlCmd.Dock='Bottom'; $pnlCmd.Height=40; $pnlCmd.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6)
$txtCmd=New-Object System.Windows.Forms.TextBox; $txtCmd.Dock='Fill'; $txtCmd.Font=$font
$btnSend=New-Object System.Windows.Forms.Button; $btnSend.Text='Отправить'; $btnSend.Dock='Right'; $btnSend.Width=100
$pnlCmd.Controls.Add($txtCmd); $pnlCmd.Controls.Add($btnSend)

$txtLog=New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock='Fill'; $txtLog.ReadOnly=$true; $txtLog.Font=$mono; $txtLog.BackColor=[System.Drawing.Color]::FromArgb(24,24,28); $txtLog.ForeColor=[System.Drawing.Color]::Gainsboro
$txtLog.WordWrap=$false; $txtLog.ScrollBars='Both'; $txtLog.DetectUrls=$false

# ---- пункт 41: индикатор «чей ход» (плитки Gemini / Antigravity, анимированная стрелка) ----
if(-not ('GG.TurnPanel' -as [type])){
  Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
namespace GG { public class TurnPanel : System.Windows.Forms.Panel {
  public TurnPanel(){ SetStyle(System.Windows.Forms.ControlStyles.AllPaintingInWmPaint|System.Windows.Forms.ControlStyles.OptimizedDoubleBuffer|System.Windows.Forms.ControlStyles.UserPaint|System.Windows.Forms.ControlStyles.ResizeRedraw,true); DoubleBuffered=true; }
} }
'@
}
$script:turnView=Get-TurnView 'idle' $false (Get-IdeLabel); $script:turnPhase=0
$pnlTurn=New-Object GG.TurnPanel; $pnlTurn.Dock='Top'; $pnlTurn.Height=72; $pnlTurn.BackColor=[System.Drawing.Color]::White
$tfEmo=New-Object System.Drawing.Font('Segoe UI Emoji',20); $tfName=New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$tfSub=New-Object System.Drawing.Font('Segoe UI',8.5); $tfCap=New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold); $tfChev=New-Object System.Drawing.Font('Segoe UI',14,[System.Drawing.FontStyle]::Bold)
function Get-TilePal([string]$st){
  $C=[System.Drawing.Color]
  switch($st){
    'active'{ @{ Fill=$C::FromArgb(225,245,230); Edge=$C::FromArgb(34,139,34); Text=$C::FromArgb(20,100,30); Sub=$C::FromArgb(34,139,34) } }
    'limit' { @{ Fill=$C::FromArgb(255,243,220); Edge=$C::FromArgb(230,140,0);  Text=$C::FromArgb(150,85,0);  Sub=$C::FromArgb(200,110,0) } }
    'off'   { @{ Fill=$C::FromArgb(246,246,248); Edge=$C::FromArgb(215,215,220); Text=$C::FromArgb(150,150,155); Sub=$C::FromArgb(165,165,170) } }
    default { @{ Fill=$C::FromArgb(240,240,243); Edge=$C::FromArgb(200,200,206); Text=$C::FromArgb(95,95,102);  Sub=$C::FromArgb(130,130,136) } }
  }
}
function New-RoundPath([System.Drawing.RectangleF]$r,[float]$rad){
  $p=New-Object System.Drawing.Drawing2D.GraphicsPath; $d=$rad*2
  $p.AddArc($r.X,$r.Y,$d,$d,180,90); $p.AddArc($r.Right-$d,$r.Y,$d,$d,270,90); $p.AddArc($r.Right-$d,$r.Bottom-$d,$d,$d,0,90); $p.AddArc($r.X,$r.Bottom-$d,$d,$d,90,90); $p.CloseFigure(); $p
}
$pnlTurn.Add_Paint({ param($s,$e)
  try{
    $g=$e.Graphics; $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='ClearTypeGridFit'; $v=$script:turnView
    $W=[float]$s.ClientSize.Width; $gap=[Math]::Max(150,[Math]::Min(220,$W*0.26)); $tw=[Math]::Min(250,($W-$gap-24)/2); $top=8; $th=53
    $xG=($W-$gap)/2-$tw; $xA=($W+$gap)/2
    $sf=New-Object System.Drawing.StringFormat; $sf.Alignment='Center'; $sf.LineAlignment='Center'
    $sfL=New-Object System.Drawing.StringFormat; $sfL.LineAlignment='Center'
    foreach($t in @(@($xG,'✨','Gemini',$v.G),@($xA,'🛠',$(if($v.Ide){[string]$v.Ide}else{'Antigravity'}),$v.A))){
      $pal=Get-TilePal $t[3]; $r=New-Object System.Drawing.RectangleF([float]$t[0],[float]$top,[float]$tw,[float]$th)
      $path=New-RoundPath $r 12
      $g.FillPath((New-Object System.Drawing.SolidBrush($pal.Fill)),$path)
      $g.DrawPath((New-Object System.Drawing.Pen($pal.Edge,$(if($t[3] -in 'active','limit'){2.5}else{1}))),$path); $path.Dispose()
      $g.DrawString($t[1],$tfEmo,(New-Object System.Drawing.SolidBrush($pal.Text)),(New-Object System.Drawing.RectangleF(($r.X+10),$r.Y,44,$r.Height)),$sf)
      $g.DrawString($t[2],$tfName,(New-Object System.Drawing.SolidBrush($pal.Text)),(New-Object System.Drawing.RectangleF(($r.X+58),($r.Y+3),($tw-62),26)),$sfL)
      $g.DrawString((Get-TurnTileSub $t[3]),$tfSub,(New-Object System.Drawing.SolidBrush($pal.Sub)),(New-Object System.Drawing.RectangleF(($r.X+59),($r.Y+28),($tw-62),20)),$sfL)
    }
    $cc=[System.Drawing.Color]::FromName($v.Color); $cr=New-Object System.Drawing.RectangleF((($W-$gap)/2),$top,$gap,($th/2+4))
    $g.DrawString($v.Caption,$tfCap,(New-Object System.Drawing.SolidBrush($cc)),$cr,$sf)
    $dir= if($v.G -eq 'active'){ '◀  ◀  ◀' } elseif($v.A -eq 'active'){ '▶  ▶  ▶' } else { '' }
    if($dir){
      $k=$script:turnPhase % 3; $parts=$dir -split '  '
      $x0=($W-$gap)/2; $step=$gap/4
      for($i=0;$i -lt 3;$i++){ $j= if($v.A -eq 'active'){ $i } else { 2-$i }; $a= if($j -eq $k){255}else{90}
        $g.DrawString($parts[$i],$tfChev,(New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a,34,139,34))),(New-Object System.Drawing.RectangleF(($x0+$step*($i+0.5)),($top+$th/2-4),$step,28)),$sf) }
    }
    $g.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(228,228,232))),0,($s.ClientSize.Height-1),$W,($s.ClientSize.Height-1))
  }catch{}
})
$turnTimer=New-Object System.Windows.Forms.Timer; $turnTimer.Interval=200
$turnTimer.Add_Tick({ $script:turnPhase=($script:turnPhase+1)%48; $pnlTurn.Invalidate() })
function Set-TurnView($v){
  $old=$script:turnView; $script:turnView=$v
  if($v.Anim){ if(-not $turnTimer.Enabled){ $turnTimer.Start() } } else { if($turnTimer.Enabled){ $turnTimer.Stop() } }
  if(-not $old -or $old.Caption -ne $v.Caption -or $old.Ide -ne $v.Ide -or $old.G -ne $v.G -or $old.A -ne $v.A){ $pnlTurn.Invalidate() }
}
$form.Controls.Add($txtLog); $form.Controls.Add($pnlCmd); $form.Controls.Add($pnlBtn); $form.Controls.Add($pnlTop); $form.Controls.Add($pnlTurn)

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
    Set-TurnView (Get-TurnView 'off' $false (Get-IdeLabel)); $cmbIde.Enabled=$true; return
  }
  try{
    $j=[IO.File]::ReadAllText($Cfg.StatusFile,[Text.Encoding]::UTF8) | ConvertFrom-Json; $v=Get-GuiStateView $j
    $lblState.Text=$v.State; $lblState.ForeColor=[System.Drawing.Color]::FromName($v.Color)
    $lblModel.Text=$v.Model; $lblFile.Text=$v.File; $lblLim.Text=$v.Limits; $lblAct.Text=$v.Action
    $tn= if($j.turn){ [string]$j.turn } else { Get-RelayTurn -Kind ([string]$j.kind) }; Set-TurnView (Get-TurnView $tn $true $(if($j.ideName){[string]$j.ideName}else{Get-IdeLabel})); $cmbIde.Enabled=(Test-Path -LiteralPath $Cfg.PauseFile)
    if($j.ide -and -not $script:ideSync -and $script:ideVals[$cmbIde.SelectedIndex] -ne [string]$j.ide){ $script:ideSync=$true; $cmbIde.SelectedIndex=[Math]::Max(0,[array]::IndexOf($script:ideVals,[string]$j.ide)); $script:ideSync=$false }
    if($null -ne $j.autoAccept -and ((Get-Date)-$script:chkAccAt).TotalSeconds -gt 5 -and $chkAcc.Checked -ne [bool]$j.autoAccept){ $script:chkSync=$true; $chkAcc.Checked=[bool]$j.autoAccept; $script:chkSync=$false }
    if($null -ne $j.autoAllow -and ((Get-Date)-$script:chkAt).TotalSeconds -gt 5 -and $chkAuto.Checked -ne [bool]$j.autoAllow){ $script:chkSync=$true; $chkAuto.Checked=[bool]$j.autoAllow; $script:chkSync=$false }
  }catch{}
}
$timer=New-Object System.Windows.Forms.Timer; $timer.Interval=800
$timer.Add_Tick({ Load-LogTail; Update-Status; try{ Update-CdpView }catch{} })

# ---- ввод текста для «Gemini: текст» / «Antigravity: текст» ----
function Show-TextInput([string]$title,[string]$hint){
  $d=New-Object System.Windows.Forms.Form; $d.Text=$title; $d.Font=$btnFont; $d.StartPosition='CenterParent'; $d.Size=New-Object System.Drawing.Size(560,330)
  $d.FormBorderStyle='FixedDialog'; $d.MaximizeBox=$false; $d.MinimizeBox=$false; $d.ShowInTaskbar=$false; $d.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
  $l=New-Object System.Windows.Forms.Label; $l.Text=$hint; $l.Dock='Top'; $l.Height=44; $l.Padding=New-Object System.Windows.Forms.Padding(10,8,10,0)
  $t=New-Object System.Windows.Forms.TextBox; $t.Multiline=$true; $t.ScrollBars='Vertical'; $t.AcceptsReturn=$true; $t.Dock='Fill'; $t.Font=New-Object System.Drawing.Font('Segoe UI',10)
  $p=New-Object System.Windows.Forms.FlowLayoutPanel; $p.Dock='Bottom'; $p.Height=46; $p.FlowDirection='RightToLeft'; $p.Padding=New-Object System.Windows.Forms.Padding(6)
  $ok=New-Btn 'Отправить' '' 120; $ok.DialogResult='OK'; $ok.ForeColor=$accent; $no=New-Btn 'Отмена' '' 100; $no.DialogResult='Cancel'
  $p.Controls.AddRange(@($ok,$no)); $box=New-Object System.Windows.Forms.Panel; $box.Dock='Fill'; $box.Padding=New-Object System.Windows.Forms.Padding(10,4,10,4); $box.Controls.Add($t)
  $d.Controls.Add($box); $d.Controls.Add($p); $d.Controls.Add($l); $d.CancelButton=$no
  $t.Add_KeyDown({ if($_.Control -and $_.KeyCode -eq 'Enter'){ $_.SuppressKeyPress=$true; $d.DialogResult='OK'; $d.Close() } })
  $r=$d.ShowDialog($form); $txt=$t.Text; $d.Dispose()
  if($r -eq 'OK' -and $txt.Trim()){ $txt } else { $null }
}
function Send-PcText([string]$k,[string]$text){ Send-Cmd ("/pc_$k b64:"+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))) }
function Confirm-Gui([string]$msg){ ([System.Windows.Forms.MessageBox]::Show($form,$msg,'GGskript',[System.Windows.Forms.MessageBoxButtons]::OKCancel,[System.Windows.Forms.MessageBoxIcon]::Question)) -eq 'OK' }

$btnStart.Add_Click({ Remove-Item -LiteralPath $Cfg.PauseFile -EA 0; if(-not (Worker-Alive)){ Start-Worker } else { Send-Cmd 'старт' } })
$btnPause.Add_Click({ try{ New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null }catch{}; Send-Cmd 'стоп'; Set-TurnView (Get-TurnView 'stopped' $true (Get-IdeLabel)); $cmbIde.Enabled=$true; $lblState.Text='Состояние: ⏸ Остановлен — ничего не делаю'; $lblState.ForeColor=[System.Drawing.Color]::DarkOrange })
$miExit.Add_Click({
  $r=[System.Windows.Forms.MessageBox]::Show($form,"Выключить GGskript (воркер) совсем? Из Telegram запустить снова будет нельзя — только кнопкой «Старт» здесь или ярлыком.`nЧтобы просто остановиться и слушать Telegram — кнопка «Стоп».",'GGskript',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
  if($r -eq 'Yes'){ try{ New-Item -ItemType File $Cfg.StopFile -Force | Out-Null }catch{} }
})
$btnLim.Add_Click({ Send-Cmd 'лимиты' }); $btnStat.Add_Click({ Send-Cmd 'статус' }); $btnShot.Add_Click({ Send-Cmd 'скрин' }); $btnHelp.Add_Click({ Send-Cmd 'помощь' })
$btnAns.Add_Click({ Send-Cmd '/pc_answer' })
$btnRep.Add_Click({ if(Confirm-Gui "Отправить в Gemini заново последний отчёт агента из Downloads?`nОтвет Gemini дальше пойдёт по обычным правилам."){ Send-Cmd '/pc_togemini' } })
$btnFwd.Add_Click({ if(Confirm-Gui "Переслать в Antigravity ВЕСЬ последний ответ Gemini целиком (не только блок Markdown)?"){ Send-Cmd '/pc_toag' } })
$btnGmT.Add_Click({ $t=Show-TextInput '✨ Gemini: текст' 'Текст для Gemini. Отправлю и покажу ответ в журнале. Ctrl+Enter — отправить.'; if($t){ Send-PcText 'gemask' $t } })
$btnAgT.Add_Click({ $t=Show-TextInput '🛠 Antigravity: текст' 'Текст для агента Antigravity. Ответом будет его новый отчёт в Downloads — покажу в журнале. Ctrl+Enter — отправить.'; if($t){ Send-PcText 'agask' $t } })
$script:cdpAt=[datetime]::MinValue
function Update-CdpView([switch]$Force){
  if(-not $Force -and ((Get-Date)-$script:cdpAt).TotalSeconds -lt 5){ return }; $script:cdpAt=Get-Date
  foreach($x in @(@($lblCdpG,'Gemini',[int]$Cfg.CdpPort),@($lblCdpA,'Antigravity',[int]$Cfg.AgCdpPort),@($lblCdpD,'Harness',[int]$Cfg.DshCdpPort))){ $v=Get-PortView (Test-PortUp $x[2]) $x[1] $x[2]; $x[0].Text=$v.Text; $x[0].ForeColor=[System.Drawing.Color]::FromName($v.Color) }
}
function Write-PanelLog([string]$m){ $txtLog.AppendText("$(Get-Date -Format 'HH:mm:ss') $m`r`n"); $txtLog.ScrollToCaret() }
$btnCdpG.Add_Click({ try{ Write-PanelLog (Start-GeminiCdpChrome ([int]$Cfg.CdpPort)) }catch{ Write-PanelLog "❌ Chrome с портом: $($_.Exception.Message)" }; Send-Cmd '/pc_cdpcheck'; Update-CdpView -Force })
$btnCdpA.Add_Click({
  if(-not (Confirm-Gui "Перезапустить Antigravity с портом отладки $($Cfg.AgCdpPort)?`n`nAntigravity закроется (как File → Exit) и сразу откроется снова. Несохранённые файлы он предложит сохранить.`nПосле перезапуска откройте прошлый разговор: значок часов → последний → Open in current window.`n`nСовет: сначала нажмите «⏸ Стоп», после перезапуска — «▶️ Старт».")){ return }
  $form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor
  try{ Write-PanelLog (Restart-AgCdp ([int]$Cfg.AgCdpPort)) }catch{ Write-PanelLog "❌ Antigravity с портом: $($_.Exception.Message)" } finally { $form.Cursor=[System.Windows.Forms.Cursors]::Default }
  Send-Cmd '/pc_cdpcheck'; Update-CdpView -Force
})
$btnCdpD.Add_Click({
  if(-not (Confirm-Gui "Перезапустить DeepSeek Harness с портом отладки $($Cfg.DshCdpPort)?`n`nВсе процессы Harness (и значок в трее) будут закрыты, затем он откроется с портом.`nТекущий ответ агента, если он идёт, прервётся.")){ return }
  $form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor
  try{ Write-PanelLog (Restart-DshCdp ([int]$Cfg.DshCdpPort)) }catch{ Write-PanelLog "❌ Harness с портом: $($_.Exception.Message)" } finally { $form.Cursor=[System.Windows.Forms.Cursors]::Default }
  Update-CdpView -Force
})
$script:ideSync=$false
$cmbIde.Add_SelectedIndexChanged({
  if($script:ideSync){ return }
  $v=$script:ideVals[$cmbIde.SelectedIndex]; if($v -eq $Cfg.AgTarget){ return }
  if((Worker-Alive) -and -not (Test-Path -LiteralPath $Cfg.PauseFile)){ Write-PanelLog '⛔ IDE меняю только при «⏸ Стоп».'; $script:ideSync=$true; $cmbIde.SelectedIndex=[Math]::Max(0,[array]::IndexOf($script:ideVals,[string]$Cfg.AgTarget)); $script:ideSync=$false; return }
  $Cfg.AgTarget=$v; try{ Save-SettingValue (Join-Path $dir 'relay_settings.json') 'AgTarget' $v }catch{}
  if(Worker-Alive){ Send-Cmd "ide $v" }; Write-PanelLog "🛠 IDE: $(Get-IdeLabel)"; Set-TurnView (Get-TurnView 'stopped' $true (Get-IdeLabel))
})
$btnMore.Add_Click({ $menu.Show($btnMore,(New-Object System.Drawing.Point(0,$btnMore.Height))) })
$script:chkSync=$false; $script:chkAt=[datetime]::MinValue
$chkAuto.Add_CheckedChanged({
  if($script:chkSync){ return }
  $script:chkAt=Get-Date; $on=[bool]$chkAuto.Checked
  try{ Save-SettingValue (Join-Path $dir 'relay_settings.json') 'AutoAllowPrompts' $on }catch{}
  Send-Cmd $(if($on){'автоподтверждение вкл'}else{'автоподтверждение выкл'})
})
$script:chkAccAt=[datetime]::MinValue
$chkAcc.Add_CheckedChanged({
  if($script:chkSync){ return }
  $script:chkAccAt=Get-Date; $on=[bool]$chkAcc.Checked
  try{ Save-SettingValue (Join-Path $dir 'relay_settings.json') 'AutoAcceptAll' $on }catch{}
  Send-Cmd $(if($on){'автопринятие вкл'}else{'автопринятие выкл'})
})
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
