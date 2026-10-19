BeforeAll { . (Join-Path $PSScriptRoot '_Load.ps1') }

Describe 'Пункт 1: настройки по умолчанию' -Tag Item01 {
  It 'содержат все ключи исходного $Cfg с теми же значениями' {
    $d=Get-DefaultSettings -Root 'R' -UserProfile 'U'
    $d.PollSec | Should -Be 3; $d.StableSec | Should -Be 3; $d.GeminiTitle | Should -Be 'Gemini'
    $d.GeminiInputX | Should -Be 0.75; $d.GeminiInputY | Should -Be 0.86; $d.GeminiTimeoutSec | Should -Be 900
    $d.GeminiQuietSec | Should -Be 8; $d.AgInputX | Should -Be 0.38; $d.AgInputY | Should -Be 0.93
    $d.CodeBlockLang | Should -Be 'Markdown'; $d.CodeBlockPick | Should -Be 'last'; $d.ModelMustContain | Should -Be 'Argon'
    $d.AcceptAllEverySec | Should -Be 12; $d.AgQueueWaitSec | Should -Be 30; $d.QuotaEveryMin | Should -Be 10
    $d.GeminiWebThreshold | Should -Be 90; $d.AgThreshold | Should -Be 10; $d.AgGroup | Should -Be 'Gemini Models'
    $d.IgnoreBefore | Should -Be '2026-10-18 00:00'
    @($d.AgProcess) | Should -Be @('Antigravity IDE','Antigravity')
    $d.Downloads | Should -Be (Join-Path 'U' 'Downloads')
  }
  It 'новые опции по умолчанию сохраняют старый транспорт (uia)' {
    $d=Get-DefaultSettings -Root 'R' -UserProfile 'U'
    $d.GeminiTransport | Should -Be 'uia'; $d.AgTransport | Should -Be 'uia'
  }
  It 'шаблон имени принимает 3+ цифры и прежние имена' {
    $d=Get-DefaultSettings -Root 'R' -UserProfile 'U'
    'MyProject_2026-10-18_001.md' | Should -Match $d.Pattern
    'SEOdemo_site_2026-10-17_004.md' | Should -Match $d.Pattern
    'X_2026-10-18_1000.md' | Should -Match $d.Pattern
    'X_2026-10-18_01.md' | Should -Not -Match $d.Pattern
    'X_2026-10-18_001.md.tmp' | Should -Not -Match $d.Pattern
  }
}

Describe 'Пункт 1: Merge-Settings' -Tag Item01 {
  BeforeAll { $script:D=Get-DefaultSettings -Root 'R' -UserProfile 'U' }
  It 'без файла возвращает дефолты' {
    $r=Merge-Settings -Defaults $D -OverridePath (Join-Path $TestDrive 'none.json')
    $r.Cfg.PollSec | Should -Be 3; $r.Warnings.Count | Should -Be 0
  }
  It 'применяет известные ключи из JSON и пропускает неизвестные' {
    $p=Join-Path $TestDrive 's.json'
    '{"PollSec":5,"GeminiTransport":"cdp","Foo":1,"_comment":"x","AgProcess":"Antigravity"}' | Set-Content -LiteralPath $p -Encoding UTF8
    $r=Merge-Settings -Defaults $D -OverridePath $p
    $r.Cfg.PollSec | Should -Be 5; $r.Cfg.GeminiTransport | Should -Be 'cdp'
    @($r.Cfg.AgProcess) | Should -Be @('Antigravity')
    $r.Cfg.Contains('Foo') | Should -BeFalse
    ($r.Warnings -join ';') | Should -Match "Foo"
  }
  It 'отвергает неверные типы, регэкспы, значения перечислений' {
    $r=Merge-Settings -Defaults $D -Override ([ordered]@{ PollSec='abc'; RestoreFocus='yes'; RxCode='('; AgTransport='telepathy'; Pattern='^x$' })
    $r.Cfg.PollSec | Should -Be 3; $r.Cfg.RestoreFocus | Should -BeTrue
    $r.Cfg.RxCode | Should -Be $D.RxCode; $r.Cfg.AgTransport | Should -Be 'uia'; $r.Cfg.Pattern | Should -Be $D.Pattern
    $r.Warnings.Count | Should -Be 5
  }
  It 'битый JSON — предупреждение и дефолты' {
    $p=Join-Path $TestDrive 'bad.json'; '{ PollSec: ' | Set-Content -LiteralPath $p
    $r=Merge-Settings -Defaults $D -OverridePath $p
    $r.Cfg.PollSec | Should -Be 3; ($r.Warnings -join ';') | Should -Match 'Не удалось прочитать'
  }
  It 'пример relay_settings.example.json валиден и не даёт предупреждений' {
    $p=Join-Path $V2Root 'relay_settings.example.json'
    Test-Path $p | Should -BeTrue
    $r=Merge-Settings -Defaults $D -OverridePath $p
    $r.Warnings.Count | Should -Be 0
  }
}

Describe 'Пункт 1: типизированные исключения и Get-ErrorKind' -Tag Item01 {
  It '<t> -> <k>' -TestCases @(
    @{ t='GG.RelayStopException'; k='stop' }, @{ t='GG.RelayLimitException'; k='limit' }, @{ t='GG.RelayStaleException'; k='stale' },
    @{ t='GG.RelayNoCodeException'; k='nocode' }, @{ t='GG.RelayPausedException'; k='paused' }, @{ t='GG.RelayNotSentException'; k='notsent' }
  ) {
    $e = if($t -eq 'GG.RelayStopException'){ New-Object $t } else { New-Object $t 'x' }
    try{ throw $e }catch{ Get-ErrorKind $_ | Should -Be $k }
  }
  It 'распознаёт исключение, обёрнутое в MethodInvocationException/скриптблок' {
    try{ & { throw [GG.RelayStopException]::new() } }catch{ Get-ErrorKind $_ | Should -Be 'stop' }
    $inner=[GG.RelayLimitException]::new('m'); $outer=New-Object System.Management.Automation.MethodInvocationException('wrap',$inner)
    Get-ErrorKind $outer | Should -Be 'limit'
  }
  It 'старые строковые сигналы тоже понимает' {
    foreach($p in @(@('STOP','stop'),@('LIMIT','limit'),@('OLDANSWER','stale'),@('NOCODE','nocode'))){ try{ throw $p[0] }catch{ Get-ErrorKind $_ | Should -Be $p[1] } }
  }
  It 'обычная ошибка -> error' { try{ throw 'что-то сломалось' }catch{ Get-ErrorKind $_ | Should -Be 'error' } }
}
Describe 'Пункт 1: PSModulePath для Windows PowerShell 5.1, запущенного из pwsh 7' -Tag Item01 {
  It 'убирает пути модулей PS7 и добавляет системный путь Windows PowerShell' {
    $in='C:\Users\u\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Users\u\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules'
    $r=Get-RepairedPSModulePath $in 'C:\WINDOWS\System32\WindowsPowerShell\v1.0'
    $r | Should -Be 'C:\Users\u\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
  }
  It 'обычный путь 5.1 не меняет (без дублей системного пути)' {
    $in='C:\Users\u\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\'
    Get-RepairedPSModulePath $in 'C:\WINDOWS\System32\WindowsPowerShell\v1.0' | Should -Be $in
  }
  It 'пустой путь — только системный' { Get-RepairedPSModulePath '' 'C:\PS' | Should -Be 'C:\PS\Modules' }
}
