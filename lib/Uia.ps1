# ===== GGskript v2: Uia — тонкая обёртка над UI Automation (Windows). В тестах подменяется Mock. =====
function Initialize-Uia{
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $script:UIA=[System.Windows.Automation.AutomationElement]
  $script:CT=[System.Windows.Automation.ControlType]
  $script:Desc=[System.Windows.Automation.TreeScope]::Descendants
}
function Uia-Root($h){ $script:UIA::FromHandle([IntPtr]$h) }
function Uia-Cond([string]$ControlType,[string]$Name){
  $c=@()
  if($ControlType){ $c+=New-Object System.Windows.Automation.PropertyCondition($script:UIA::ControlTypeProperty,($script:CT::$ControlType)) }
  if($Name){ $c+=New-Object System.Windows.Automation.PropertyCondition($script:UIA::NameProperty,$Name) }
  if($c.Count -eq 0){ return [System.Windows.Automation.Condition]::TrueCondition }
  if($c.Count -eq 1){ return $c[0] }
  New-Object System.Windows.Automation.AndCondition([System.Windows.Automation.Condition[]]$c)
}
# Поиск потомков: точное имя/тип — условием UIA (быстро), регэксп — фильтром.
function Uia-FindAll{
  param($Root,[string]$ControlType,[string]$Name,[string]$NameRx)
  if(-not $Root -or $Root.GetType().FullName -ne 'System.Windows.Automation.AutomationElement'){ $Root=Uia-Root $Root }
  # UiaPerfAnd=$false — откат на прежний способ: искать по типу, имя сравнивать в PowerShell
  if($Name -and $Cfg -and $Cfg.Contains('UiaPerfAnd') -and -not $Cfg.UiaPerfAnd){ $NameRx='^'+[regex]::Escape($Name)+'$'; $Name='' }
  $r=$Root.FindAll($script:Desc,(Uia-Cond $ControlType $Name))
  if($NameRx){ @($r | Where-Object { $_.Current.Name -match $NameRx }) } else { @($r) }
}
function Uia-FindFirst{
  param($Root,[string]$ControlType,[string]$Name)
  if(-not $Root -or $Root.GetType().FullName -ne 'System.Windows.Automation.AutomationElement'){ $Root=Uia-Root $Root }
  $Root.FindFirst($script:Desc,(Uia-Cond $ControlType $Name))
}
function Uia-Name($el){ try{ [string]$el.Current.Name }catch{ '' } }
function Uia-Class($el){ try{ [string]$el.Current.ClassName }catch{ '' } }
function Uia-CtlType($el){ try{ ([string]$el.Current.ControlType.ProgrammaticName) -replace '^ControlType\.','' }catch{ '' } }
function Uia-IsOffscreen($el){ try{ [bool]$el.Current.IsOffscreen }catch{ $true } }
function Uia-Rect($el){ try{ $r=$el.Current.BoundingRectangle; @{L=[int]$r.Left;T=[int]$r.Top;R=[int]$r.Right;B=[int]$r.Bottom} }catch{ $null } }
function Uia-Focused{ $script:UIA::FocusedElement }
function Uia-Focus($el){ try{ $el.SetFocus(); $true }catch{ $false } }
function Uia-IsFocused($el){
  try{ $f=$script:UIA::FocusedElement; if(!$f){ return $false }
    if([System.Windows.Automation.Automation]::Compare($f,$el)){ return $true }
    # фокус может быть на дочернем элементе поля (contenteditable)
    $w=[System.Windows.Automation.TreeWalker]::RawViewWalker; $e=$f
    for($i=0;$i -lt 4 -and $e;$i++){ $e=$w.GetParent($e); if($e -and [System.Windows.Automation.Automation]::Compare($e,$el)){ return $true } }
    $false }catch{ $false }
}
function Uia-GetText($el){
  if(!$el){ return '' }
  try{ $v=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value; if($v){ return $v } }catch{}
  try{ $t=$el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1); if($t){ return $t } }catch{}
  ''
}
function Uia-Invoke($el){ try{ $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $true }catch{ $false } }
function Uia-ScrollIntoView($el){ if(!$el){ return }; try{ $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() }catch{}; Start-Sleep -Milliseconds 500 }
function Uia-Select($el){ try{ $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $true }catch{ $false } }
function Uia-Parent($el){ try{ [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($el) }catch{ $null } }
# Клик по центру видимого элемента; сначала InvokePattern (без мыши), если PreferInvoke.
function Uia-ClickEl($el,[switch]$PreferInvoke){
  if(!$el){ return $false }
  if($PreferInvoke -and (Uia-Invoke $el)){ return $true }
  if(Uia-IsOffscreen $el){ return (Uia-Invoke $el) }
  $r=Uia-Rect $el; if(!$r -or ($r.R -le $r.L)){ return (Uia-Invoke $el) }
  ClickAt (($r.L+$r.R)/2) (($r.T+$r.B)/2); $true
}
function Uia-IsEnabled($el){ try{ [bool]$el.Current.IsEnabled }catch{ $false } }
function Uia-ExpandState($el){ try{ [string]$el.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState }catch{ '' } }
function Uia-Expand($el){ try{ $el.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); $true }catch{ $false } }
function Uia-Collapse($el){ try{ $el.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); $true }catch{ $false } }
# Значение ValuePattern; $null — шаблон не поддерживается (тогда можно читать TextPattern).
function Uia-GetValue($el){ if(!$el){ return $null }; try{ [string]$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ $null } }
