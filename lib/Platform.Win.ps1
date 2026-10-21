# ===== GGskript v2: Platform.Win — всё, что зависит от Windows (user32, буфер, DPI, мьютекс, DPAPI) =====
# Функции только объявляются; Initialize-Platform вызывается из GGskript.ps1. В тестах эти функции подменяются Mock.

function Initialize-Platform{
  if(-not ('GG.Native' -as [type])){
    Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
namespace GG {
public static class Native {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint msg,UIntPtr w,IntPtr l,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,int f,int e);
 [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool f);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h,int a,out RECT r,int size);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
 [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO l);
 [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
 [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
 [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h,out uint m);
 [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h,uint m);
 public static List<IntPtr> TopWindows(){ var l=new List<IntPtr>(); EnumWindows((h,p)=>{ if(IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
 public static uint IdleMs(){ var i=new LASTINPUTINFO(); i.cbSize=(uint)Marshal.SizeOf(i); if(!GetLastInputInfo(ref i)) return 0; return (uint)Environment.TickCount - i.dwTime; }
 public static string Title(IntPtr h){ var s=new StringBuilder(512); GetWindowTextW(h,s,512); return s.ToString(); }
 public static string ClassOf(IntPtr h){ var s=new StringBuilder(256); GetClassNameW(h,s,256); return s.ToString(); }
}}
"@
  }
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $script:PlatformReady=$true
}

# ---------- DPI ----------
# Per-Monitor V2 (Windows 10 1703+), иначе system-aware как раньше. Возвращает 'pmv2' | 'system' | 'none'.
# Адаптеры к WinAPI (в тестах подменяются Mock).
function Dpi-SetPerMonitorV2{ [GG.Native]::SetProcessDpiAwarenessContext([IntPtr](-4)) }
function Dpi-SetSystemAware{ [GG.Native]::SetProcessDPIAware() }
function Get-DwmBounds($h){ $r=New-Object GG.Native+RECT; if([GG.Native]::DwmGetWindowAttribute([IntPtr]$h,9,[ref]$r,16) -eq 0){ @{L=$r.L;T=$r.T;R=$r.R;B=$r.B} } }
function Get-RawWindowRect($h){ $r=New-Object GG.Native+RECT; [void][GG.Native]::GetWindowRect([IntPtr]$h,[ref]$r); @{L=$r.L;T=$r.T;R=$r.R;B=$r.B} }
# Per-Monitor V2 (Windows 10 1703+), иначе System DPI aware, иначе — без DPI-осведомлённости.
function Initialize-Dpi{
  try{ if(Dpi-SetPerMonitorV2){ return 'pmv2' } }catch{}
  try{ if(Dpi-SetSystemAware){ return 'system' } }catch{}
  'none'
}
# Видимые границы окна без DWM-тени; запасной вариант — GetWindowRect. Возвращает @{L;T;R;B}.
function Get-WindowBounds($h){
  try{ $d=Get-DwmBounds $h; if($d -and $d.R -gt $d.L -and $d.B -gt $d.T){ return $d } }catch{}
  Get-RawWindowRect $h
}

# ---------- Окна ----------
function Get-ForegroundHandle{ [GG.Native]::GetForegroundWindow() }
function Set-ForegroundHandle($h){ [void][GG.Native]::SetForegroundWindow([IntPtr]$h) }
# Все видимые верхние окна в Z-порядке: @{h;title;class;pid;proc}
function Get-TopWindows{
  $procs=@{}; foreach($p in Get-Process -EA 0){ $procs[[uint32]$p.Id]=$p.ProcessName }
  foreach($h in [GG.Native]::TopWindows()){
    $pp=[uint32]0; [void][GG.Native]::GetWindowThreadProcessId($h,[ref]$pp)
    [pscustomobject]@{ h=$h; title=[GG.Native]::Title($h); class=[GG.Native]::ClassOf($h); pid=$pp; proc=[string]$procs[$pp] }
  }
}
function Get-WindowInfo($h){
  $pp=[uint32]0; [void][GG.Native]::GetWindowThreadProcessId([IntPtr]$h,[ref]$pp)
  $pn=''; try{ $pn=(Get-Process -Id $pp -EA Stop).ProcessName }catch{}
  [pscustomobject]@{ h=$h; title=[GG.Native]::Title([IntPtr]$h); class=[GG.Native]::ClassOf([IntPtr]$h); pid=$pp; proc=$pn }
}

# ---------- Активность пользователя и фокус ----------
function Get-IdleMs{ [GG.Native]::IdleMs() }
function Test-ModifiersDown{ foreach($vk in 0x10,0x11,0x12,0x5B,0x5C){ if([GG.Native]::GetAsyncKeyState($vk) -band 0x8000){ return $true } }; $false }

function Activate-Window($h){ Assert-Running 'переключение окна';
  $h=[IntPtr]$h
  if([GG.Native]::IsIconic($h)){ [void][GG.Native]::ShowWindow($h,9); Start-Sleep -Milliseconds 400 }
  for($i=0;$i -lt 5;$i++){
    $fg=[GG.Native]::GetForegroundWindow(); $pp=[uint32]0
    $t1=[GG.Native]::GetWindowThreadProcessId($fg,[ref]$pp); $t2=[GG.Native]::GetCurrentThreadId()
    $att=$false; if($fg -ne [IntPtr]::Zero -and $t1 -ne 0 -and $t1 -ne $t2){ $att=[GG.Native]::AttachThreadInput($t2,$t1,$true) }
    try{
      $k=[int]$Cfg.ActivateKey
      if($k -gt 0 -and $i -gt 0){ [GG.Native]::keybd_event([byte]$k,0,0,0); [GG.Native]::keybd_event([byte]$k,0,2,0) }   # 27D: клавиша-разблокировка — только если первая попытка без неё не сработала
      [void][GG.Native]::BringWindowToTop($h); [void][GG.Native]::SetForegroundWindow($h)
    } finally { if($att){ [void][GG.Native]::AttachThreadInput($t2,$t1,$false) } }
    Start-Sleep -Milliseconds 400
    if([GG.Native]::GetForegroundWindow() -eq $h){ return }
  }
  if(Get-Command Note-Blocking -EA 0){ Note-Blocking }
  throw 'Не удалось вывести окно на передний план'
}

# Ждёт, пока пользователь не трогает мышь/клавиатуру IdleSec секунд (но не дольше IdleMaxWaitSec). Возвращает $true, если ждал.
function Wait-UserIdle{
  param([int]$Sec=$Cfg.IdleSec,[int]$MaxWaitSec=$Cfg.IdleMaxWaitSec)
  if($Sec -le 0){ return $false }
  $t0=Get-Date; $waited=$false; $logged=$false
  while((Get-IdleMs) -lt ($Sec*1000)){
    $waited=$true
    if(-not $logged){ Log "Жду, пока пользователь не будет трогать мышь/клавиатуру $Sec сек…"; $logged=$true }
    if(((Get-Date)-$t0).TotalSeconds -ge $MaxWaitSec){ Log "Пользователь активен дольше $MaxWaitSec сек — продолжаю"; break }
    Nap 1
  }
  $waited
}
# Выполняет $Body с окном $h на переднем плане; фокус возвращается в finally (даже при исключении).
function Invoke-WithFocus{
  param($h,[scriptblock]$Body,[switch]$NoIdleWait)
  if(-not $NoIdleWait){ [void](Wait-UserIdle) }
  $prev=Get-ForegroundHandle
  $script:FocusDepth=[int]$script:FocusDepth+1   # пока >0 — фоновые действия (Accept all во время ожидания) не запускаются
  try{ Activate-Window $h; & $Body }
  finally{
    $script:FocusDepth=[Math]::Max(0,[int]$script:FocusDepth-1)
    if($Cfg.RestoreFocus -and $prev -and ([IntPtr]$prev -ne [IntPtr]::Zero) -and ([IntPtr]$prev -ne [IntPtr]$h)){ try{ Set-ForegroundHandle $prev }catch{} }
  }
}

# ---------- Пункт 38: «Стоп» прерывает любое действие сразу ----------
# Проверка перед каждым кликом, клавишей, записью в буфер, UIA-нажатием и CDP-командой.
# В воркере ($script:GGWorker) смотрим ещё и файл PAUSE: панель ставит его мгновенно, даже посреди операции.
function Test-StopNow{
  if($script:Paused){ return $true }
  if($script:GGWorker -and $Cfg -and $Cfg.PauseFile){ try{ return [IO.File]::Exists([string]$Cfg.PauseFile) }catch{} }
  $false
}
function Assert-Running([string]$ctx='действие'){ if(Test-StopNow){ throw [GG.RelayPausedException]::new("СТОП — $ctx прервано") } }
# ---------- Клавиатура и мышь ----------
function Wait-ModifiersUp([int]$MaxMs=3000){ $t0=Get-Date; while((Test-ModifiersDown) -and ((Get-Date)-$t0).TotalMilliseconds -lt $MaxMs){ Start-Sleep -Milliseconds 100 } }
function KeyDown([int]$vk){ Assert-Running 'нажатие клавиши'; [GG.Native]::keybd_event([byte]$vk,0,0,0) }
function KeyUp([int]$vk){ [GG.Native]::keybd_event([byte]$vk,0,2,0) }
function Send-Key([int]$vk){ KeyDown $vk; try{ Start-Sleep -Milliseconds 30 } finally { KeyUp $vk }; Start-Sleep -Milliseconds 80 }
function Send-Ctrl([int]$vk){ Wait-ModifiersUp; KeyDown 0x11; try{ Start-Sleep -Milliseconds 30; Send-Key $vk } finally { KeyUp 0x11 }; Start-Sleep -Milliseconds 150 }
function Paste{ Send-Ctrl 0x56 }
function ClearField{ Send-Ctrl 0x41; Send-Key 0x2E }
function PressEnter{ Wait-ModifiersUp; Send-Key 0x0D }
# ---------- Зависшие окна ----------
function Test-WindowHung($h){ try{ [bool][GG.Native]::IsHungAppWindow([IntPtr]$h) }catch{ $false } }
# WM_NULL с SMTO_ABORTIFHUNG: $false — окно не обработало сообщение за TimeoutMs (поток окна занят/завис)
function Test-WindowPing($h,[int]$TimeoutMs=2000){ try{ $r=[UIntPtr]::Zero; [GG.Native]::SendMessageTimeout([IntPtr]$h,0,[UIntPtr]::Zero,[IntPtr]::Zero,0x0002,[uint32]$TimeoutMs,[ref]$r) -ne [IntPtr]::Zero }catch{ $true } }
function Test-ProcessResponding($ProcessId){ try{ [bool](Get-Process -Id $ProcessId -EA Stop).Responding }catch{ $null } }
function PressEsc{ Wait-ModifiersUp; Send-Key 0x1B }
function ClickAt($x,$y){
  Assert-Running 'клик мышью'
  $p=[System.Windows.Forms.Cursor]::Position
  [void][GG.Native]::SetCursorPos([int]$x,[int]$y); Start-Sleep -Milliseconds 150
  [GG.Native]::mouse_event(2,0,0,0,0); [GG.Native]::mouse_event(4,0,0,0,0); Start-Sleep -Milliseconds 300
  if($Cfg.RestoreFocus){ [void][GG.Native]::SetCursorPos($p.X,$p.Y) }
}
function ClickRel($h,$fx,$fy){ $r=Get-WindowBounds $h; ClickAt ($r.L+($r.R-$r.L)*$fx) ($r.T+($r.B-$r.T)*$fy) }

# ---------- Буфер обмена ----------
function Get-ClipSeq{ [GG.Native]::GetClipboardSequenceNumber() }
function Get-ClipText{ for($i=0;$i -lt 10;$i++){ try{ return [System.Windows.Forms.Clipboard]::GetText() }catch{ Start-Sleep -Milliseconds 300 } }; throw 'Буфер обмена занят (чтение)' }
function Set-ClipText([string]$Text){
  Assert-Running 'запись в буфер обмена'
  $do=New-Object System.Windows.Forms.DataObject
  $do.SetText($Text,[System.Windows.Forms.TextDataFormat]::UnicodeText)
  if($Cfg.ClipExcludeHistory){
    # не попадать в журнал Win+V и облачный буфер (документированные форматы Windows)
    $do.SetData('ExcludeClipboardContentFromMonitorProcessing',(New-Object IO.MemoryStream (,[byte[]](0))))
    $do.SetData('CanIncludeInClipboardHistory',(New-Object IO.MemoryStream (,[byte[]](0,0,0,0))))
    $do.SetData('CanUploadToCloudClipboard',(New-Object IO.MemoryStream (,[byte[]](0,0,0,0))))
  }
  for($i=0;$i -lt 10;$i++){ try{ [System.Windows.Forms.Clipboard]::SetDataObject($do,$true); return }catch{ Start-Sleep -Milliseconds 300 } }
  throw 'Буфер обмена занят'
}
# Снимок буфера: копия всех форматов, которые удалось прочитать (картинки, файлы, текст).
function Save-Clipboard{
  try{
    $src=[System.Windows.Forms.Clipboard]::GetDataObject(); if(!$src){ return $null }
    $copy=New-Object System.Windows.Forms.DataObject; $n=0
    foreach($f in $src.GetFormats($false)){ try{ $d=$src.GetData($f,$false); if($null -ne $d){ $copy.SetData($f,$d); $n++ } }catch{} }
    if($n){ $copy } else { $null }
  }catch{ $null }
}
function Restore-Clipboard($Saved){
  if($null -eq $Saved){ try{ [System.Windows.Forms.Clipboard]::Clear() }catch{}; return }
  for($i=0;$i -lt 10;$i++){ try{ [System.Windows.Forms.Clipboard]::SetDataObject($Saved,$true); return }catch{ Start-Sleep -Milliseconds 300 } }
  Log 'Не удалось восстановить буфер обмена пользователя'
}
# Выполняет $Body, а затем возвращает пользователю его буфер (если RestoreClipboard).
function Use-TempClipboard([scriptblock]$Body){
  $saved=$null; if($Cfg.RestoreClipboard){ $saved=Save-Clipboard }
  try{ & $Body } finally { if($Cfg.RestoreClipboard){ Restore-Clipboard $saved } }
}

# ---------- Единственный экземпляр ----------
function Enter-SingleInstance([string]$Name){
  $created=$false
  $m=New-Object System.Threading.Mutex($true,$Name,[ref]$created)
  if($created){ return $m }
  try{ if($m.WaitOne(0)){ return $m } }catch [System.Threading.AbandonedMutexException]{ return $m }
  $m.Dispose(); $null
}
function Exit-SingleInstance($Mutex){ if($Mutex){ try{ $Mutex.ReleaseMutex() }catch{}; $Mutex.Dispose() } }
function Test-InstanceRunning([string]$Name){
  $m=$null
  if(-not [System.Threading.Mutex]::TryOpenExisting($Name,[ref]$m)){ return $false }
  try{ if($m.WaitOne(0)){ $m.ReleaseMutex(); return $false }; return $true }
  catch [System.Threading.AbandonedMutexException]{ try{ $m.ReleaseMutex() }catch{}; return $false }
  finally{ $m.Dispose() }
}

# ---------- DPAPI (секреты) ----------
function Protect-Secret([string]$Plain){ ConvertTo-SecureString $Plain -AsPlainText -Force | ConvertFrom-SecureString }
function Unprotect-Secret([string]$Blob){
  $s=ConvertTo-SecureString ($Blob.Trim())
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try{ [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}

# ---------- Консоль ----------
function Disable-QuickEdit{
  try{ $h=[GG.Native]::GetStdHandle(-10); $m=[uint32]0; if([GG.Native]::GetConsoleMode($h,[ref]$m)){ [void][GG.Native]::SetConsoleMode($h,(($m -band (-bnot 0x40)) -bor 0x80)) ; return $true } }catch{}
  $false
}

# ---------- Скриншот ----------
# $Rect = @{L;T;R;B} — область (например, окно диалога) или $null — весь виртуальный экран. Возвращает путь к JPEG.
function Save-ScreenshotJpeg($Rect){
  if($Rect){ $x=$Rect.L; $y=$Rect.T; $w=[Math]::Max(1,$Rect.R-$Rect.L); $hh=[Math]::Max(1,$Rect.B-$Rect.T) }
  else { $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $x=$b.Left; $y=$b.Top; $w=$b.Width; $hh=$b.Height }
  $bmp=New-Object System.Drawing.Bitmap $w,$hh; $g=$null; $sm=$null
  $f=Join-Path $env:TEMP ("relay_screen_{0}.jpg" -f [guid]::NewGuid().ToString('N'))
  try{
    $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($x,$y,0,0,$bmp.Size)
    if($bmp.Width -gt 2560){ $k=2560/$bmp.Width; $sm=New-Object System.Drawing.Bitmap $bmp,([int]($bmp.Width*$k)),([int]($bmp.Height*$k)); $sm.Save($f,[System.Drawing.Imaging.ImageFormat]::Jpeg) }
    else { $bmp.Save($f,[System.Drawing.Imaging.ImageFormat]::Jpeg) }
  } finally { if($g){ $g.Dispose() }; if($sm){ $sm.Dispose() }; $bmp.Dispose() }
  $f
}

# ---------- Пункт 23: выключение компьютера ----------
# Единственная точка вызова shutdown.exe (в тестах — Mock; предохранитель в tests/_Load.ps1). -> @{ code; out }
function Invoke-ShutdownExe([string[]]$ArgList){
  if(Get-Module Pester){ throw 'ТЕСТ: вызов shutdown.exe под Pester запрещён (нужен Mock Invoke-ShutdownExe)' }   # вторая защита от выключения ПК тестами
  $exe=Join-Path $env:WINDIR 'System32\shutdown.exe'
  $out=& $exe @ArgList 2>&1
  @{ code=[int]$LASTEXITCODE; out=((@($out) | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}
