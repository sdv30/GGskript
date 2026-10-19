BeforeDiscovery {
  $root=Split-Path $PSScriptRoot -Parent
  $script:Files=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -eq ".ps1" -and $_.FullName -notmatch "[\\/]tools[\\/]Pester[\\/]" } | ForEach-Object { @{ Path=$_.FullName; Name=$_.FullName.Substring($root.Length+1) } })
}
Describe 'Пункт 1: синтаксис и кодировка всех .ps1' -Tag Item01 {
  It '<Name>: UTF-8 с BOM и без ошибок парсера' -TestCases $Files {
    $b=[IO.File]::ReadAllBytes($Path)
    ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue -Because 'Windows PowerShell 5.1 без BOM читает кириллицу как ANSI'
    $tok=$null; $err=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
    @($err | Where-Object { $_ }).Count | Should -Be 0
  }
}
Describe 'Пункт 1: верхний уровень скриптов не затирает $script:-переменные библиотек' -Tag Item01 {
  # ForEach-Object/Where-Object на верхнем уровне выполняются в области скрипта: `$st=...` затирал $script:St (учёт) в -check.
  It '<n>: присваивания вне функций не совпадают с $script:-переменными lib/*.ps1' -TestCases @(@{ n='GGskript.ps1' },@{ n='GGskript_gui.ps1' }) {
    $root=Split-Path $PSScriptRoot -Parent
    $libVars=@{}
    foreach($f in Get-ChildItem -LiteralPath (Join-Path $root 'lib') -File | Where-Object { $_.Extension -eq '.ps1' }){
      foreach($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName),'\$script:([A-Za-z_]\w*)')){ $libVars[$m.Groups[1].Value.ToLowerInvariant()]=1 }
    }
    $tok=$null; $err=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $n),[ref]$tok,[ref]$err)
    $bad=@($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] },$true) | Where-Object {
        $p=$_.Parent; $inFn=$false
        while($p){ if($p -is [System.Management.Automation.Language.FunctionDefinitionAst]){ $inFn=$true; break }; $p=$p.Parent }
        (-not $inFn) -and $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.IsUnqualified -and $libVars.ContainsKey($_.Left.VariablePath.UserPath.ToLowerInvariant())
      } | ForEach-Object { "$($_.Left.VariablePath.UserPath) (строка $($_.Extent.StartLineNumber))" })
    $bad | Should -BeNullOrEmpty
  }
}
