# ===== GGskript v2: сохранить токен Telegram-бота в зашифрованном виде (Windows DPAPI) =====
# Файл tg_token.dpapi расшифровывается ТОЛЬКО под этой учётной записью Windows на этом ПК.
#   powershell -ExecutionPolicy Bypass -File Set-TgToken.ps1              — ввести токен вручную (ввод скрыт)
#   powershell -ExecutionPolicy Bypass -File Set-TgToken.ps1 -FromConfig  — взять telegram_token из relay_config.json
#   добавьте -RemovePlain, чтобы удалить telegram_token из relay_config.json после сохранения (делается копия .bak)
# Рекомендация: если токен когда-либо попадал в чужие руки/переписку — перевыпустите его у @BotFather (/revoke) и сохраните новый.
param([switch]$FromConfig,[switch]$RemovePlain,[string]$Root=$PSScriptRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\Core.ps1'); Repair-PSModulePath
foreach($f in 'State','Platform.Win'){ . (Join-Path $PSScriptRoot "lib\$f.ps1") }
$Cfg=(Merge-Settings -Defaults (Get-DefaultSettings -Root $Root) -OverridePath (Join-Path $Root 'relay_settings.json')).Cfg
$c=(Read-JsonWithBackup $Cfg.ConfigFile).Data
if($FromConfig){
  if(-not $c -or -not $c.telegram_token){ Write-Host 'В relay_config.json нет telegram_token.'; exit 1 }
  $plain=[string]$c.telegram_token
} else {
  $sec=Read-Host 'Вставьте токен бота (ввод скрыт)' -AsSecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try{ $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
$plain=$plain.Trim()
if($plain -notmatch '^\d+:[\w-]{20,}$'){ Write-Host 'Это не похоже на токен Telegram (формат 123456:ABC...). Ничего не сохранено.'; exit 1 }
Write-AtomicText -Path $Cfg.TokenFile -Text (Protect-Secret $plain) -NoBom
if((Unprotect-Secret ([IO.File]::ReadAllText($Cfg.TokenFile))) -ne $plain){ Write-Host 'Проверка расшифровки не прошла!'; exit 1 }
Write-Host "Токен сохранён в $($Cfg.TokenFile) (DPAPI)."
if($RemovePlain -and $c -and $c.telegram_token){
  $c.Remove('telegram_token'); Write-AtomicText -Path $Cfg.ConfigFile -Text ($c | ConvertTo-Json -Depth 6)
  Write-Host 'telegram_token удалён из relay_config.json (прежняя версия — relay_config.json.bak; удалите её вручную после проверки).'
} elseif($c -and $c.telegram_token){ Write-Host 'Не забудьте удалить telegram_token из relay_config.json (или запустите с -RemovePlain).' }
