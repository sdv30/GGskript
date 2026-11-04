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
# GG_RENDER_OUT — только снимок панели вне экрана (для документации/тестов): без мьютекса, воркера и команд
$script:RenderOut=[string]$env:GG_RENDER_OUT
if($script:RenderOut){ $mtx=$null; if($env:GG_RENDER_IDE){ $Cfg.AgTarget=[string]$env:GG_RENDER_IDE } } else { $mtx=Enter-SingleInstance $Cfg.GuiMutex }
if(-not $mtx -and -not $script:RenderOut){
  Remove-Item -LiteralPath $Cfg.PauseFile -EA 0
  $w=Get-Process | Where-Object { $_.MainWindowTitle -eq 'GGskript' -and $_.Id -ne $PID } | Select-Object -First 1
  if($w){ [void][GG.Native]::ShowWindow($w.MainWindowHandle,9); [void][GG.Native]::SetForegroundWindow($w.MainWindowHandle) }
  return
}
function Worker-Alive{ if($script:RenderOut){ return $false }; Test-WorkerAlive -StatusPath $Cfg.StatusFile -MutexName $Cfg.WorkerMutex -MutexCheck { param($n) Test-InstanceRunning $n } }
function Start-Worker{
  Remove-Item -LiteralPath $Cfg.StopFile -EA 0
  Start-Process powershell -WindowStyle Hidden -WorkingDirectory $dir -ArgumentList '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$Worker+'"')
}
function Get-IdeLabel{ switch([string]$Cfg.AgTarget){ 'dsharness'{'DeepSeek Harness'} 'cursor'{'Cursor'} default{'Antigravity'} } }
function Send-Cmd($text){ if($script:RenderOut){ return }; [void](Send-GuiCmd -Path $Cfg.CmdFile -Text $text) }

# ---- форма ----
$font=New-Object System.Drawing.Font('Segoe UI',9)
$mono=New-Object System.Drawing.Font('Consolas',9.5)
$form=New-Object System.Windows.Forms.Form
$form.AutoScaleMode=[System.Windows.Forms.AutoScaleMode]::Dpi
$form.Text='GGskript'; $form.Font=$font
$form.Size=New-Object System.Drawing.Size(820,780)
$form.MinimumSize=New-Object System.Drawing.Size(760,740)   # 27.10: ниже кнопки не помещаются в строку и журналу не остаётся места
$form.StartPosition='CenterScreen'
try{ if(Test-Path -LiteralPath $IcoF){ $form.Icon=New-Object System.Drawing.Icon($IcoF) } }catch{}
$form.TopMost=$false

# 27.10 (sendfix): наверху ОДНА строка состояния (с переносом, высота подстраивается под ширину окна — Fit-Layout).
# Модель / проект / лимиты / последнее действие в верхнюю часть не выводятся — они пишутся строкой «ℹ» в журнал (Add-InfoLog) при изменении.
$pnlTop=New-Object System.Windows.Forms.Panel
$pnlTop.Dock='Top'; $pnlTop.Height=40; $pnlTop.Padding=New-Object System.Windows.Forms.Padding(10,6,10,6); $pnlTop.BackColor=[System.Drawing.Color]::FromArgb(245,245,248)
function New-Lbl($t){ $l=New-Object System.Windows.Forms.Label; $l.AutoSize=$true; $l.Text=$t; $l.Margin=New-Object System.Windows.Forms.Padding(3,2,3,2); $l }
$lblState=New-Object System.Windows.Forms.Label; $lblState.Text='Состояние: …'; $lblState.AutoSize=$false; $lblState.Dock='Fill'; $lblState.UseCompatibleTextRendering=$false
$lblState.Font=New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
$lblModel=New-Lbl ''; $lblFile=New-Lbl ''; $lblLim=New-Lbl ''; $lblAct=New-Lbl ''   # не показываются (оставлены для совместимости присваиваний)
$pnlTop.Controls.Add($lblState)

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
$btnAcct=New-Btn '🔄 Сменил аккаунт' 'Сменили аккаунт Google в Chrome: сбросить соединение с Gemini, заново выбрать вкладку, перечитать лимит и модель. Лимит в норме — верну Argon и продолжу сам; иначе напишу причину в журнал.'
$btnHelp=New-Btn '❓ Помощь' 'Открыть подробную справку (docs\HELP.txt в Блокноте; нет — README.md) и прислать список команд в Telegram'
$btnMore=New-Btn '☰ Ещё ▾' 'Остальные команды'
$btnExit=New-Btn '⛔ Выключить скрипт' 'Завершить воркер GGskript совсем (спрошу подтверждение). Работает всегда, даже посреди действия: файл STOP, а если воркер не завершится за 8 с — процесс принудительно.'; $btnExit.ForeColor=[System.Drawing.Color]::Red
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
Add-BtnRow 'АККАУНТ' @($btnAcct)
Add-BtnRow 'ВЫКЛЮЧЕНИЕ' @($btnExit)
Add-BtnRow '' @($btnMore,$chkAuto,$chkAcc)
# ---- пункт 39: режим без мыши (порты отладки) ----
$btnCdpG=New-Btn '🌐 Chrome с портом' 'Открыть отдельный Chrome для Gemini с портом 9222 (обычный Chrome/Яндекс не закрываю). С портом скрипт работает без мыши.' 200
$btnCdpA=New-Btn '🛠 Antigravity с портом' 'Перезапустить Antigravity с портом 9333 (спрошу подтверждение). С портом — без мыши и автоподтверждение надёжнее.' 200
$lblCdpG=New-Lbl '○ Gemini 9222: …'; $lblCdpA=New-Lbl '○ Antigravity 9333: …'
foreach($l in $lblCdpG,$lblCdpA){ $l.Margin=New-Object System.Windows.Forms.Padding(6,9,3,2); $l.ForeColor=[System.Drawing.Color]::Gray }
Add-BtnRow 'РЕЖИМ БЕЗ МЫШИ' @($btnCdpG,$btnCdpA,$lblCdpG,$lblCdpA)

# ---- меню «☰ Ещё» ----
$menu=New-Object System.Windows.Forms.ContextMenuStrip; $menu.Font=$btnFont; $menu.ShowImageMargin=$false
function Add-Mi([string]$text,[scriptblock]$act){ $i=New-Object System.Windows.Forms.ToolStripMenuItem($text); if($act){ $i.Add_Click($act) }; [void]$menu.Items.Add($i); $i }
function Add-MHead([string]$text){ $i=New-Object System.Windows.Forms.ToolStripMenuItem($text); $i.Enabled=$false; $i.Font=$grpFont; [void]$menu.Items.Add($i) }
function Add-MSep{ [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }
$miHead=New-Object System.Windows.Forms.ToolStripMenuItem('ANTIGRAVITY'); $miHead.Enabled=$false; $miHead.Font=$grpFont; [void]$menu.Items.Add($miHead)
$miAcc=Add-Mi '✅ Принять «Accept all»' { Send-Cmd 'прими' }
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
# пункт 52: все надписи, зависящие от IDE
function Apply-IdeTexts{
  $x=Get-IdeTexts ([string]$Cfg.AgTarget) ([int]$Cfg.AgCdpPort) ([int]$Cfg.DshCdpPort) ([int]$(if($Cfg.CursorCdpPort){$Cfg.CursorCdpPort}else{9335})); $script:ideTx=$x
  $btnFwd.Text=Get-BtnPlainText $x.Fwd; $tip.SetToolTip($btnFwd,$x.FwdTip)
  $btnAgT.Text=Get-BtnPlainText $x.AgT; $tip.SetToolTip($btnAgT,$x.AgTTip)
  $tip.SetToolTip($btnLim,$x.LimTip); $chkAuto.Text=$x.Auto; $tip.SetToolTip($chkAuto,$x.AutoTip); $chkAcc.Text=$x.Acc; $tip.SetToolTip($chkAcc,$x.AccTip)
  $btnCdpA.Text=Get-BtnPlainText $x.Cdp; $tip.SetToolTip($btnCdpA,$x.CdpTip)
  $miHead.Text=$x.MenuHead; $miAcc.Text=$x.Accept
  if($script:turnView){ $tv=$script:turnView.Clone(); if($tv.Caption -like 'Ход *' -and $tv.A -eq 'active'){ $tv.Caption="Ход $($x.Name)" }; $tv.Ide=$x.Name; Set-TurnView $tv }
  try{ Update-CdpView -Force }catch{}
}

$pnlCmd=New-Object System.Windows.Forms.Panel
$pnlCmd.Dock='Bottom'; $pnlCmd.Height=40; $pnlCmd.Padding=New-Object System.Windows.Forms.Padding(8,6,8,6)
$txtCmd=New-Object System.Windows.Forms.TextBox; $txtCmd.Dock='Fill'; $txtCmd.Font=$font
$btnSend=New-Object System.Windows.Forms.Button; $btnSend.Text='Отправить'; $btnSend.Dock='Right'; $btnSend.Width=100
# 02.11 (logclear): маленькая ссылка «очистить журнал» слева от поля команды
$lnkClear=New-Object System.Windows.Forms.LinkLabel; $lnkClear.Text='очистить журнал'; $lnkClear.AutoSize=$false; $lnkClear.Width=118; $lnkClear.Dock='Left'; $lnkClear.TextAlign='MiddleLeft'
$lnkClear.Font=New-Object System.Drawing.Font('Segoe UI',8.5); $lnkClear.LinkColor=[System.Drawing.Color]::FromArgb(90,110,140); $lnkClear.ActiveLinkColor=[System.Drawing.Color]::FromArgb(40,90,170); $lnkClear.LinkBehavior='HoverUnderline'; $lnkClear.TabStop=$false
$pnlCmd.Controls.Add($txtCmd); $pnlCmd.Controls.Add($btnSend); $pnlCmd.Controls.Add($lnkClear)

$txtLog=New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock='Fill'; $txtLog.ReadOnly=$true; $txtLog.Font=$mono; $txtLog.BackColor=[System.Drawing.Color]::FromArgb(24,24,28); $txtLog.ForeColor=[System.Drawing.Color]::Gainsboro
$txtLog.WordWrap=$true; $txtLog.ScrollBars='Vertical'; $txtLog.DetectUrls=$false   # 27.10: перенос строк — журнал всегда целиком по ширине окна

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
$tfEmo=New-Object System.Drawing.Font('Segoe UI Emoji',20); $tfName=New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold); $tfCombo=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
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
    $script:tileA=New-Object System.Drawing.RectangleF([float]$xA,[float]$top,[float]$tw,[float]$th)
    $sf=New-Object System.Drawing.StringFormat; $sf.Alignment='Center'; $sf.LineAlignment='Center'
    $sfL=New-Object System.Drawing.StringFormat; $sfL.LineAlignment='Center'
    foreach($t in @(@($xG,'✨','Gemini',$v.G),@($xA,'🛠',$(if($v.Ide){[string]$v.Ide}else{'Antigravity'}),$v.A))){
      $pal=Get-TilePal $t[3]; $r=New-Object System.Drawing.RectangleF([float]$t[0],[float]$top,[float]$tw,[float]$th)
      $path=New-RoundPath $r 12
      $g.FillPath((New-Object System.Drawing.SolidBrush($pal.Fill)),$path)
      $g.DrawPath((New-Object System.Drawing.Pen($pal.Edge,$(if($t[3] -in 'active','limit'){2.5}else{1}))),$path); $path.Dispose()
      $g.DrawString($t[1],$tfEmo,(New-Object System.Drawing.SolidBrush($pal.Text)),(New-Object System.Drawing.RectangleF(($r.X+10),$r.Y,44,$r.Height)),$sf)
      if($t[0] -eq $xA){
        # пункт 53: выбор IDE — как обычный выпадающий список: рамка, имя, кнопка-стрелка справа, подсветка при наведении
        $cb=New-Object System.Drawing.RectangleF(($r.X+56),($r.Y+5),($tw-64),25); $script:comboA=$cb
        $hov=[bool]$script:comboHover; $C=[System.Drawing.Color]
        $cbFill= if($hov){ $C::FromArgb(232,240,252) } else { $C::White }; $cbEdge= if($hov){ $C::FromArgb(0,120,215) } else { $C::FromArgb(160,164,172) }
        $g.FillRectangle((New-Object System.Drawing.SolidBrush($cbFill)),$cb); $g.DrawRectangle((New-Object System.Drawing.Pen($cbEdge,1)),$cb.X,$cb.Y,$cb.Width,$cb.Height)
        $ab=New-Object System.Drawing.RectangleF(($cb.Right-22),$cb.Y,22,$cb.Height)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush($(if($hov){$C::FromArgb(204,228,247)}else{$C::FromArgb(240,240,243)}))),($ab.X+1),($ab.Y+1),($ab.Width-1),($ab.Height-1))
        $g.DrawLine((New-Object System.Drawing.Pen($cbEdge,1)),$ab.X,$ab.Y,$ab.X,$ab.Bottom)
        $g.DrawString('▼',$tfSub,(New-Object System.Drawing.SolidBrush($C::FromArgb(60,60,66))),$ab,$sf)
        $g.DrawString($t[2],$tfCombo,(New-Object System.Drawing.SolidBrush($pal.Text)),(New-Object System.Drawing.RectangleF(($cb.X+5),$cb.Y,($cb.Width-28),$cb.Height)),$sfL)
        $g.DrawString((Get-TurnTileSub $t[3]),$tfSub,(New-Object System.Drawing.SolidBrush($pal.Sub)),(New-Object System.Drawing.RectangleF(($r.X+59),($r.Y+31),($tw-62),20)),$sfL)
        continue
      }
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
# 27.10 (sendfix): подстройка под ширину окна при любом размере: высота строки состояния по переносу текста, индикаторы портов переносятся, а не обрезаются.
function Fit-Layout{
  try{
    $w=[Math]::Max(60,$pnlTop.ClientSize.Width-$pnlTop.Padding.Horizontal)
    $fl=[System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPadding -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
    $sz=[System.Windows.Forms.TextRenderer]::MeasureText([string]$lblState.Text,$lblState.Font,(New-Object System.Drawing.Size($w,0)),$fl)
    $h=[Math]::Min([int]$sz.Height,$lblState.Font.Height*4)+$pnlTop.Padding.Vertical+4
    if($pnlTop.Height -ne $h){ $pnlTop.Height=$h }
    foreach($l in $lblCdpG,$lblCdpA){ if($l.Parent){ $l.AutoSize=$true; $l.MaximumSize=New-Object System.Drawing.Size([Math]::Max(120,$l.Parent.ClientSize.Width-14),0) } }
  }catch{}
}
$form.Add_Resize({ Fit-Layout })
$pnlBtn.Add_SizeChanged({ Fit-Layout })

# ---- хвост лога ----
$script:logPos=-1
# 27.10 (colors): строки журнала раскрашиваются по уровню (Get-LogLevel). Добавляются только НОВЫЕ строки, подряд идущие одного уровня — одним куском;
# длина журнала ограничена (с головы убирается целое число строк, цвета остальных сохраняются).
$script:logPrevLevel='info'; $script:LogMax=250000; $script:LogKeep=150000
function Add-LogLines([string]$Text){
  if(-not $Text){ return }
  try{
    $lines=@($Text -split "\r?\n"); while($lines.Count -and -not [string]$lines[$lines.Count-1]){ $lines=@($lines | Select-Object -First ($lines.Count-1)) }
    if(-not $lines.Count){ return }
    $atEnd=Test-AtEnd $txtLog.SelectionStart $txtLog.TextLength
    $lv=Get-LogLevels $lines $script:logPrevLevel
    $i=0
    while($i -lt $lines.Count){
      $j=$i; $sb=New-Object System.Text.StringBuilder
      while($j -lt $lines.Count -and $lv[$j] -eq $lv[$i]){ [void]$sb.Append([string]$lines[$j]).Append("`r`n"); $j++ }
      $c=Get-LogColor $lv[$i]
      $col=[System.Drawing.Color]::FromArgb($c[0],$c[1],$c[2]); $st=$txtLog.TextLength
      $txtLog.SelectionStart=$st; $txtLog.SelectionLength=0; $txtLog.SelectionColor=$col
      $txtLog.AppendText($sb.ToString())
      # цвет ставлю и на весь добавленный кусок: после эмодзи (⚠️) RichEdit сбрасывал цвет на следующих строках того же куска
      $txtLog.Select($st,$txtLog.TextLength-$st); $txtLog.SelectionColor=$col; $i=$j
    }
    $script:logPrevLevel=$lv[$lines.Count-1]; $txtLog.SelectionStart=$txtLog.TextLength; $txtLog.SelectionLength=0; $txtLog.SelectionColor=$txtLog.ForeColor
    if($txtLog.TextLength -gt $script:LogMax){
      $cut=Get-LogTrimCount $txtLog.Text $script:LogMax $script:LogKeep
      if($cut -gt 0){ $txtLog.ReadOnly=$false; try{ $txtLog.Select(0,$cut); $txtLog.SelectedText='' } finally { $txtLog.ReadOnly=$true }; $atEnd=$true }   # в режиме ReadOnly SelectedText не удаляет
    }
    if($atEnd){ $txtLog.SelectionStart=$txtLog.TextLength; $txtLog.SelectionLength=0; $txtLog.ScrollToCaret() }
  }catch{}
}
# 02.11 (logclear): очистить окно журнала и начать новый relay_log.txt (прежний — в logs\…_cleared.txt). Воркер дописывает в новый файл сам.
function Clear-PanelLog{
  try{ if(-not $script:RenderOut){ [void](Invoke-LogArchive -Path $Cfg.LogFile -Dir (Join-Path $dir 'logs') -Keep 10 -Suffix '_cleared') } }catch{}
  $txtLog.Clear(); $script:logPos=0; $script:logPrevLevel='info'; $script:infoKey=''
}
function Load-LogTail{
  try{
    if($script:logPos -gt 0){ $len=0; try{ $len=(Get-Item -LiteralPath $Cfg.LogFile -EA Stop).Length }catch{}; if($len -lt $script:logPos){ $txtLog.Clear(); $script:logPos=0 } }   # 02.11: файл начат заново (новый запуск/очистка) — окно тоже с чистого листа
    $r=Read-LogTail -Path $Cfg.LogFile -Pos $script:logPos; $script:logPos=$r.Pos
    if($r.Text){
      Add-LogLines $r.Text
    }
  }catch{}
}
# 27.10 (sendfix): модель / проект / лимиты — строкой «ℹ» в журнал (только в окне панели, relay_log.txt не трогаю), и только когда что-то изменилось
$script:infoKey=''
function Add-InfoLog([string]$Text){
  try{
    Add-LogLines "▸ $(Get-Date -Format 'HH:mm:ss')  $Text"
  }catch{}
}
function Update-Status{
  if(-not (Worker-Alive)){
    $lblState.Text='Состояние: воркер не запущен — нажмите «Старт»'; $lblState.ForeColor=[System.Drawing.Color]::DimGray; Fit-Layout
    Set-TurnView (Get-TurnView 'off' $false (Get-IdeLabel)); return
  }
  try{
    $j=[IO.File]::ReadAllText($Cfg.StatusFile,[Text.Encoding]::UTF8) | ConvertFrom-Json; $v=Get-GuiStateView $j
    $lblState.Text=$v.State; $lblState.ForeColor=[System.Drawing.Color]::FromName($v.Color); Fit-Layout
    $ik="$($v.Model)|$($v.File)|$($v.Limits)"; if($ik -ne $script:infoKey){ $script:infoKey=$ik; Add-InfoLog "$($v.Model) | $($v.File)`r`n   $($v.Limits)" }
    $tn= if($j.turn){ [string]$j.turn } else { Get-RelayTurn -Kind ([string]$j.kind) }; Set-TurnView (Get-TurnView $tn $true $(if($j.ideName){[string]$j.ideName}else{Get-IdeLabel}))
    if($j.ide -and [string]$j.ide -ne [string]$Cfg.AgTarget -and ((Get-Date)-$script:ideAt).TotalSeconds -gt 8){ $Cfg.AgTarget=[string]$j.ide; Apply-IdeTexts }
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
$btnPause.Add_Click({ try{ New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null }catch{}; Send-Cmd 'стоп'; Set-TurnView (Get-TurnView 'stopped' $true (Get-IdeLabel)); $lblState.Text='Состояние: ⏸ Остановлен — ничего не делаю'; $lblState.ForeColor=[System.Drawing.Color]::DarkOrange })
$script:doExit={
  $r=[System.Windows.Forms.MessageBox]::Show($form,"Выключить GGskript (воркер) совсем? Из Telegram запустить снова будет нельзя — только кнопкой «Старт» здесь или ярлыком.`nЧтобы просто остановиться и слушать Telegram — кнопка «Стоп».",'GGskript',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
  if($r -eq 'Yes'){
    try{ New-Item -ItemType File $Cfg.StopFile -Force | Out-Null }catch{}
    try{ New-Item -ItemType File $Cfg.PauseFile -Force | Out-Null }catch{}   # прервать текущее действие сразу
    Write-PanelLog '⛔ Выключаю воркер GGskript…'
    $script:exitT0=Get-Date; $tm=New-Object System.Windows.Forms.Timer; $tm.Interval=1000
    $tm.Add_Tick({ param($s,$e)
      $pids=@(Get-WorkerPids)
      if(-not $pids.Count){ $s.Stop(); $s.Dispose(); Write-PanelLog '⛔ Воркер выключен.'; return }
      if(((Get-Date)-$script:exitT0).TotalSeconds -ge 8){ foreach($p in $pids){ try{ Stop-Process -Id $p -Force -EA Stop }catch{} }; $s.Stop(); $s.Dispose(); Write-PanelLog "⛔ Воркер не завершился сам за 8 с — завершил процесс ($($pids -join ', '))." }
    })
    $tm.Start()
  }
}
$miExit.Add_Click($script:doExit); $btnExit.Add_Click($script:doExit)
$btnLim.Add_Click({ Send-Cmd 'лимиты' })
# 27.10: «Сменил аккаунт» → /pc_acct → воркер сбрасывает CDP, перечитывает лимит/модель и сам продолжает. Защита от двойного клика: 5 с кнопка недоступна.
$btnAcct.Add_Click({
  Send-Cmd '/pc_acct'; $btnAcct.Enabled=$false
  $tm=New-Object System.Windows.Forms.Timer; $tm.Interval=5000
  $tm.Add_Tick({ param($s,$e) $s.Stop(); $s.Dispose(); $btnAcct.Enabled=$true })
  $tm.Start()
}); $btnStat.Add_Click({ Send-Cmd 'статус' }); $btnShot.Add_Click({ Send-Cmd 'скрин' }); $btnHelp.Add_Click({ $hp=Get-HelpDocPath $dir; if($hp){ try{ Start-Process -FilePath 'notepad.exe' -ArgumentList ('"'+$hp+'"') | Out-Null }catch{ Write-PanelLog "❌ Помощь: не удалось открыть $hp ($($_.Exception.Message))" } } else { Write-PanelLog '⚠ Помощь: нет docs\HELP.txt и README.md' }; Send-Cmd 'помощь' })
$btnAns.Add_Click({ Send-Cmd '/pc_answer' })
$btnRep.Add_Click({ if(Confirm-Gui "Отправить в Gemini заново последний отчёт агента из Downloads?`nОтвет Gemini дальше пойдёт по обычным правилам."){ Send-Cmd '/pc_togemini' } })
$btnFwd.Add_Click({ if(Confirm-Gui $script:ideTx.FwdConfirm){ Send-Cmd '/pc_toag' } })
$btnGmT.Add_Click({ $t=Show-TextInput '✨ Gemini: текст' 'Текст для Gemini. Отправлю и покажу ответ в журнале. Ctrl+Enter — отправить.'; if($t){ Send-PcText 'gemask' $t } })
$btnAgT.Add_Click({ $t=Show-TextInput $script:ideTx.AgT $script:ideTx.AgTHint; if($t){ Send-PcText 'agask' $t } })
$script:cdpAt=[datetime]::MinValue
function Update-CdpView([switch]$Force){
  if(-not $Force -and ((Get-Date)-$script:cdpAt).TotalSeconds -lt 5){ return }; $script:cdpAt=Get-Date
  foreach($x in @(@($lblCdpG,'Gemini',[int]$Cfg.CdpPort),@($lblCdpA,$script:ideTx.Short,[int]$script:ideTx.Port))){ $v=Get-PortView (Test-PortUp $x[2]) $x[1] $x[2]; $x[0].Text=$v.Text; $x[0].ForeColor=[System.Drawing.Color]::FromName($v.Color) }
}
function Write-PanelLog([string]$m){ Add-LogLines "$(Get-Date -Format 'HH:mm:ss') $m" }
$btnCdpG.Add_Click({ try{ Write-PanelLog (Start-GeminiCdpChrome ([int]$Cfg.CdpPort)) }catch{ Write-PanelLog "❌ Chrome с портом: $($_.Exception.Message)" }; Send-Cmd '/pc_cdpcheck'; Update-CdpView -Force })
$btnCdpA.Add_Click({
  if(-not (Confirm-Gui $script:ideTx.CdpConfirm)){ return }
  $form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor
  try{ Write-PanelLog $(if($Cfg.AgTarget -eq 'cursor'){ Restart-CursorCdp ([int]$(if($Cfg.CursorCdpPort){$Cfg.CursorCdpPort}else{9335})) } elseif($Cfg.AgTarget -eq 'dsharness'){ Restart-DshCdp ([int]$Cfg.DshCdpPort) } else { Restart-AgCdp ([int]$Cfg.AgCdpPort) }) }catch{ Write-PanelLog "❌ $($script:ideTx.Short) с портом: $($_.Exception.Message)" } finally { $form.Cursor=[System.Windows.Forms.Cursors]::Default }
  Send-Cmd '/pc_cdpcheck'; Update-CdpView -Force
})
# пункт 52: правая плитка индикатора — выбор IDE (только при ⏸ Стоп или когда скрипт не запущен)
$ideMenu=New-Object System.Windows.Forms.ContextMenuStrip; $ideMenu.Font=$btnFont
foreach($c in Get-IdeChoices){ $mi=New-Object System.Windows.Forms.ToolStripMenuItem([string]$c.t); $mi.Tag=[string]$c.v; $mi.Add_Click({ param($s2,$e2) Set-PanelIde ([string]$s2.Tag) }); [void]$ideMenu.Items.Add($mi) }
$ideMenu.Add_Opening({ foreach($mi in $ideMenu.Items){ $mi.Checked=([string]$mi.Tag -eq [string]$Cfg.AgTarget) } })
function Test-IdeChangeAllowed{ (-not (Worker-Alive)) -or (Test-Path -LiteralPath $Cfg.PauseFile) }
function Set-PanelIde([string]$v){
  if($v -eq $Cfg.AgTarget){ return }
  if(-not (Test-IdeChangeAllowed)){ Write-PanelLog '⛔ IDE меняю только при «⏸ Стоп».'; $tip.Show('IDE меняю только при «⏸ Стоп»',$pnlTurn,[int]$script:tileA.X,[int]($script:tileA.Bottom+2),2500); return }
  $Cfg.AgTarget=$v; $script:ideAt=Get-Date; try{ Save-SettingValue (Join-Path $dir 'relay_settings.json') 'AgTarget' $v }catch{}
  if(Worker-Alive){ Send-Cmd "ide $v" }; Apply-IdeTexts; Write-PanelLog "🛠 IDE: $(Get-IdeLabel)"
}
$pnlTurn.Cursor=[System.Windows.Forms.Cursors]::Default
$pnlTurn.Add_MouseLeave({ if($script:comboHover){ $script:comboHover=$false; $pnlTurn.Invalidate() } })
$pnlTurn.Add_MouseMove({ param($s2,$e2) $in=($script:tileA -and $script:tileA.Contains([float]$e2.X,[float]$e2.Y)); if($in -ne [bool]$script:comboHover){ $script:comboHover=$in; $pnlTurn.Invalidate() }; $c= if($in){[System.Windows.Forms.Cursors]::Hand}else{[System.Windows.Forms.Cursors]::Default}; if($pnlTurn.Cursor -ne $c){ $pnlTurn.Cursor=$c; if($in){ $tip.SetToolTip($pnlTurn,$script:ideTx.TileTip) } else { $tip.SetToolTip($pnlTurn,'') } } })
$pnlTurn.Add_MouseClick({ param($s2,$e2)
  if(-not ($script:tileA -and $script:tileA.Contains([float]$e2.X,[float]$e2.Y))){ return }
  if(-not (Test-IdeChangeAllowed)){ $tip.Show('IDE меняю только при «⏸ Стоп»',$pnlTurn,[int]$script:tileA.X,[int]($script:tileA.Bottom+2),2500); return }
  $cbx= if($script:comboA){ $script:comboA } else { $script:tileA }; $ideMenu.MinimumSize=New-Object System.Drawing.Size([int]$cbx.Width,0); $ideMenu.Show($pnlTurn,(New-Object System.Drawing.Point([int]$cbx.X,[int]$cbx.Bottom)))
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
$script:ideAt=[datetime]::MinValue; Apply-IdeTexts
if($script:RenderOut){
  $form.StartPosition='Manual'; $form.Location=New-Object System.Drawing.Point(-6000,-6000); $form.ShowInTaskbar=$false
  $lblState.Text='Состояние: работает — слежу за папкой Downloads, жду новый отчёт'; $lblState.ForeColor=[System.Drawing.Color]::ForestGreen
  # образцы всех уровней цвета (error / warn / ok / info / dim)
  Add-LogLines (@(
    '15:00:01  Новый файл: AccessLabUnified_2026-10-27_004.md',
    '15:00:02  Этап: AccessLabUnified_2026-10-27_004.md → отправлен в Gemini, жду ответ',
    '15:00:09  ✅ Accept all нажат (1 files) (CDP, без мыши)',
    "15:00:12  Отправлено в $(Get-IdeLabel) через CDP",
    '15:00:20  ⏳ Gemini сейчас генерирует ответ — жду',
    '15:00:31  ⚠️ Лимиты:',
    '• Gemini (сайт), текущее: использовано 92% (сброс в 18:00)',
    '15:00:40  ❌ ОШИБКА: Gemini/CDP (файл): чип файла не появился или загрузка не закончилась',
    '15:00:41  ⛔ лимит Argon закончен, модель переключена на «Flash-Lite»',
    '15:01:00  Лимит: модель всё ещё «Flash-Lite»',
    '15:01:00  Лимиты: проверено в 15:01; Gemini 92% | Antigravity 80%',
    '15:01:05  Аккаунт: u1|Аккаунт Google: Имя (почта); модель «Flash-Lite»; Argon: доступен в меню',
    '15:02:00  Команда с ПК: /pc_acct',
    '15:02:01  ✅ Аккаунт сменён, Argon доступен — продолжаю',
    '15:02:05  ▶️ Лимиты в норме, работа возобновлена'
  ) -join "`n")
  # GG_RENDER_W/H — размер окна снимка; GG_RENDER_LONG=1 — очень длинная строка состояния и длинные строки журнала (проверка переноса)
  if($env:GG_RENDER_W -and $env:GG_RENDER_H){ $form.Size=New-Object System.Drawing.Size([int]$env:GG_RENDER_W,[int]$env:GG_RENDER_H) }
  if($env:GG_RENDER_LONG){
    $lblState.Text=Format-ShortState "повтор после ошибки: Gemini/CDP (файл): чип файла AccessLabUnified_2026-10-27_001.md не появился или загрузка не закончилась (чипы=[ARGON_SYSTEM_PROMPT | TASKS-FIX-2026-10-27 | Ещё 2 | Посмотреть сведения об источнике])"
    $lblState.Text='Состояние: работает — '+$lblState.Text+'. Ещё одно длинное пояснение, чтобы проверить перенос строки состояния при узком окне панели управления.'
    Add-LogLines ("16:40:29  ❌ ОШИБКА: очень длинная строка журнала без обрезки — текст должен переноситься по ширине окна и не требовать горизонтальной прокрутки: AccessLabUnified_2026-10-27_001.md AccessLabUnified_2026-10-27_001.md`r`n")
  }
  $form.Show(); [System.Windows.Forms.Application]::DoEvents(); Fit-Layout
  Add-InfoLog "Модель Gemini: Argon | Проект: AccessLabUnified | Следующий файл: нет | передан: Fishka 2_2026-10-25_009.md`r`n   $(Format-GuiLimits ([pscustomobject]@{ ide=[string]$Cfg.AgTarget; ideName=(Get-IdeLabel); agH5=80; agH5Reset='18:00'; agWk=60; agWkReset='24.10' }))"
  if($env:GG_RENDER_HOVER){ $script:comboHover=$true }; Set-TurnView (Get-TurnView 'antigravity' $true (Get-IdeLabel)); $script:turnPhase=1; foreach($l in $lblCdpG,$lblCdpA){ $l.Text=(Get-PortView $true $(if($l -eq $lblCdpG){'Gemini'}else{$script:ideTx.Short}) $(if($l -eq $lblCdpG){9222}else{[int]$script:ideTx.Port})).Text; $l.ForeColor=[System.Drawing.Color]::ForestGreen }
  [System.Windows.Forms.Application]::DoEvents(); Fit-Layout; Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents(); Fit-Layout; [System.Windows.Forms.Application]::DoEvents()
  $bm=New-Object System.Drawing.Bitmap($form.Width,$form.Height); $ok=$false
  # PrintWindow рисует и RichTextBox (журнал), которого DrawToBitmap не показывает; откат — DrawToBitmap
  try{ Add-Type -Namespace GGR -Name Pw -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr h, System.IntPtr hdc, uint f);' -EA Stop
    $gx=[System.Drawing.Graphics]::FromImage($bm); $hd=$gx.GetHdc(); try{ $ok=[GGR.Pw]::PrintWindow($form.Handle,$hd,2) } finally { $gx.ReleaseHdc($hd); $gx.Dispose() } }catch{}
  if(-not $ok){ $form.DrawToBitmap($bm,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height))) }
  $bm.Save($script:RenderOut,[System.Drawing.Imaging.ImageFormat]::Png)
  $timer.Dispose(); $form.Dispose(); return
}
$lnkClear.Add_LinkClicked({ Clear-PanelLog })
$form.Add_Shown({ if(-not (Worker-Alive)){ if(-not $script:RenderOut){ try{ [void](Invoke-LogArchive -Path $Cfg.LogFile -Dir (Join-Path $dir 'logs') -Keep 10) }catch{}; $script:logPos=0 }; Start-Worker }; Load-LogTail; Update-Status; $timer.Start() })
try{ [void]$form.ShowDialog() } finally { $timer.Stop(); $timer.Dispose(); Exit-SingleInstance $mtx }
