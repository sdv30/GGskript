# Общая загрузка для тестов: dot-source всех lib/*.ps1 в область теста. Платформенные функции не инициализируются.
$script:V2Root = Split-Path $PSScriptRoot -Parent
$env:GG_NO_BEEP='1'   # пункт 27D: тесты не пищат динамиком ПК (раньше прогон тестов на ПК вызывал реальные [Console]::Beep)
foreach($f in 'Core','State','Platform.Win','Uia','Telegram','Gemini.Uia','Gemini.Cdp','Gemini','Antigravity','Antigravity.Cdp','Relay','Chat','Shutdown','Gui.Core'){
  $p=Join-Path $script:V2Root "lib/$f.ps1"
  if(Test-Path $p){ . $p }
}
function New-TestCfg([string]$Root){
  $d=Get-DefaultSettings -Root $Root -UserProfile $Root
  $cfg=[ordered]@{}; foreach($k in $d.Keys){ $cfg[$k]=$d[$k] }
  $cfg.Downloads=(Join-Path $Root 'Downloads'); New-Item -ItemType Directory -Force $cfg.Downloads | Out-Null
  $cfg.IgnoreBefore=''
  $cfg.IdleSec=0
  $cfg.DupAnswerWaitSec=0; $cfg.WaitAfterLastPrompt=$false   # пункт 31: старые тесты — прежнее поведение; Item31 включает явно
  $cfg.MaxReportAgeHours=0   # пункт 43: старые тесты с фиксированными датами файлов; Item43 включает явно
  $cfg.AutoDecide=$false; $cfg.AutoSendGraceSec=0   # пункт 35: старые тесты — прежнее поведение; Item35 включает явно
  $cfg
}
# Защита от побочных эффектов: функции, которые трогают буфер обмена, экран, сеть Telegram и браузер, в тестах
# заменены «заглушками-предохранителями» (в ТОЙ ЖЕ области, куда dot-source'ятся lib — иначе заглушка в script: перекрывалась настоящей функцией; исправлено в пункте 23). Тест, которому они нужны, обязан подменить их через Mock (Mock имеет приоритет).
# [GG.Native] в тестах не инициализируется, поэтому клавиатура/мышь/фокус (user32) тоже недоступны.
foreach($fn in 'Get-ClipText','Set-ClipText','Save-Clipboard','Restore-Clipboard','Save-ScreenshotJpeg','Send-Screenshot','Invoke-Tg','Invoke-TgUpload','Protect-Secret','Unprotect-Secret','Invoke-ShutdownExe','Gem-IsGenerating','Gem-PeekAnswer'){
  # сигнатура (param) сохраняется — Mock строит подмену по параметрам оригинала ($Method, $Body, $ArgList …)
  $pb=''; $orig=Get-Command $fn -CommandType Function -EA 0
  if($orig){ $pb=[System.Management.Automation.ProxyCommand]::GetParamBlock([System.Management.Automation.CommandMetadata]::new($orig)) }
  Set-Item -Path "function:$fn" -Value ([scriptblock]::Create("param($pb) throw 'ТЕСТОВЫЙ ПРЕДОХРАНИТЕЛЬ: $fn вызвана без Mock'"))
}
