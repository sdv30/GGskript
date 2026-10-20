# ===== GGskript v2: единый интерфейс Gemini (Gem-*), выбор транспорта uia|cdp с безопасным откатом =====
# Откат CDP -> UIA: для чтения — при любой ошибке; для отправки — ТОЛЬКО если точно не отправлено (GG.RelayNotSentException).
# Пункт 27A: откат на UIA (фокус, клавиатура) — ТОЛЬКО если CDP недоступен; один раз сообщаю в Telegram. Прочие ошибки CDP — как есть.
$script:CdpDownSaid=$false
# Без фокуса (CDP) — только если Gemini открыт через Start-GeminiChrome.bat; обычный браузер — штатно UIA.
$script:CdpDownUntil=$null   # CDP недоступен — до этого времени сразу UIA, без повторных попыток и строк в логе
function Use-GemTransport{
  param([string]$Op,[scriptblock]$Uia,[scriptblock]$Cdp,[switch]$Send)
  if($Cfg.GeminiTransport -ne 'cdp'){ return (& $Uia) }
  if($script:CdpDownUntil -and (Get-Date) -lt $script:CdpDownUntil -and $Cfg.GeminiCdpFallback){ return (& $Uia) }
  try{
    $r=& $Cdp
    if($script:CdpDownSaid){ $script:CdpDownSaid=$false; $m='✅ Gemini: CDP-браузер снова доступен — работаю без фокуса и клавиатуры.'; Log $m; try{ Tg-Send $m | Out-Null }catch{} }
    return $r
  }
  catch{
    $k=Get-ErrorKind $_
    if(-not $Cfg.GeminiCdpFallback -or (@('stop','limit','paused','stale') -contains $k)){ throw }
    if($Send -and $k -ne 'notsent'){ throw }
    if(-not (Test-CdpUnreachable $_)){ throw }
    $sec=[int]$Cfg.CdpRecheckSec; if($sec -lt 10){ $sec=10 }
    $script:CdpDownUntil=(Get-Date).AddSeconds($sec)
    if(-not $script:CdpDownSaid){
      $script:CdpDownSaid=$true
      Log "Gemini: CDP-порт $($Cfg.CdpPort) не отвечает (обычный браузер без порта отладки) — откат на UIA (работаю через окно). Проверяю CDP раз в $sec с, повторно в лог не пишу."
      try{ Tg-Send "ℹ️ Gemini: браузер запущен без порта отладки $($Cfg.CdpPort) — работаю через окно браузера (UIA: фокус, клавиатура). Это нормально для обычного Chrome/Яндекса." | Out-Null }catch{}
    }
    & $Uia
  }
}
function Gem-UiaWindow{ $h=Find-GeminiWindow; if(!$h){ throw "Окно Gemini не найдено (вкладка '$($Cfg.GeminiTitle)' в $(Get-GeminiBrowserName))" }; $h }
function Gem-IsReady{ Use-GemTransport 'проверка окна' { $h=Find-GeminiWindow; [bool]($h -and (GemUia-FindInput $h)) } { GemCdp-IsReady } }
function Gem-GetModel{ Use-GemTransport 'модель' { GemUia-GetModel (Gem-UiaWindow) } { GemCdp-GetModel } }
function Gem-Send([string]$Text,[string]$Marker){ Use-GemTransport 'отправка' { GemUia-Send $Text $Marker } { GemCdp-Send $Text $Marker } -Send }
function Gem-WaitAnswer($Ctx){
  if($Ctx -and $Ctx.via -eq 'cdp'){ return (Use-GemTransport 'ожидание ответа' { GemUia-WaitAnswer $Ctx } { GemCdp-WaitAnswer $Ctx }) }
  if($Ctx -and $Ctx.via -eq 'uia'){ return (GemUia-WaitAnswer $Ctx) }
  Use-GemTransport 'ожидание ответа' { GemUia-WaitAnswer $Ctx } { GemCdp-WaitAnswer $Ctx }
}
function Gem-CopyCode{
  $script:LastCodeLangs=@()
  $code=Use-GemTransport 'блок кода' { GemUia-CopyCode (Gem-UiaWindow) } { GemCdp-GetCode }
  if(-not $code -and $Cfg.CodeFromWholeFallback){ $w=Gem-CopyWhole; if($w){ $code=Get-MarkdownBlock $w $Cfg.CodeBlockLang $Cfg.CodeBlockPick; if($code){ Log 'Блок Markdown найден в тексте всего ответа (CodeFromWholeFallback)' } } }
  $code
}
# Отчёт — ТОЛЬКО вложением через «+» (поле ввода пустое), без вставки текста. Не удалось прикрепить — ошибка, текст не вставляю.
function Gem-SendFile([string]$Path,[string]$Name){ Use-GemTransport 'отправка файла' { GemUia-SendFile $Path $Name } { GemCdp-SendFile $Path $Name } -Send }
function Gem-IsGenerating{ Use-GemTransport 'генерация' { GemUia-IsGenerating (Gem-UiaWindow) } { [bool](Eval-Js 'state').gen } }
# Только чтение (без кликов и буфера): есть ли ответ после последнего запроса, подписи блоков, текст блока Markdown (если читается).
function Gem-PeekAnswer{ Use-GemTransport 'ответ (чтение)' { GemUia-PeekAnswer (Gem-UiaWindow) } { GemCdp-PeekAnswer } }
function Gem-CopyWhole{ Use-GemTransport 'весь ответ' { GemUia-CopyWhole (Gem-UiaWindow) } { GemCdp-GetWhole } }
function Gem-LastReportPrompt{ Use-GemTransport 'последний отчёт' { GemUia-LastReportPrompt (Gem-UiaWindow) } { GemCdp-LastReportPrompt } }
function Gem-CountPrompts{ Use-GemTransport 'число запросов' { GemUia-CountPrompts (Gem-UiaWindow) } { GemCdp-CountPrompts } }
function Gem-GetUsageText{ Use-GemTransport 'лимиты' { GemUia-GetUsageText } { GemCdp-GetUsageText } }
# Пункт 27C: есть ли файл в чате Gemini (по «Файл отчёта: имя», вложению с именем или по содержимому) -> $null | @{how;index;last}
function Gem-FindFile([string]$Name,[string]$Content){ Use-GemTransport 'поиск файла в чате' { Find-FileInTexts -Name $Name -Content $Content -Texts (GemUia-ChatTexts (Gem-UiaWindow)) } { Find-FileInTexts -Name $Name -Content $Content -Texts (GemCdp-PromptTexts) -Whole } }
function Gem-ListModels{ Use-GemTransport 'список моделей' { GemUia-ListModels (Gem-UiaWindow) } { GemCdp-ListModels } }
function Gem-SelectModel([string]$Want){ Use-GemTransport 'выбор модели' { GemUia-SelectModel (Gem-UiaWindow) $Want } { GemCdp-SelectModel $Want } }
