BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 8: разбор команд (строгий режим)' -Tag Item08 {
  It 'прежние фразы из -testparse: «<t>» -> <k>' -TestCases @(
    @{t='статус';k='status'},@{t='Что происходит?';k='status'},@{t='пауза';k='pause'},@{t='остановись на время';k='pause'},
    @{t='продолжай';k='resume'},@{t='стоп';k='stop'},@{t='выключи реле';k='exit'},@{t='прими';k='accept'},@{t='нажми принять';k='accept'},
    @{t='напиши джемини: привет';k='gemini'},@{t='Гемини, как дела';k='gemini'},@{t='/gemini тест';k='gemini'},
    @{t='напиши антигравити: запусти тесты';k='ag'},@{t='/ag тест';k='ag'},@{t='передай ответ';k='relay'},@{t='передай весь ответ';k='relay'},
    @{t='что ответил джемини';k='lastanswer'},@{t='скрин';k='shot'},@{t='покажи экран';k='shot'},@{t='помощь';k='help'},@{t='/start';k='help'},
    @{t='абракадабра';k='unknown'},@{t='лимиты';k='limits'},@{t='/stop';k='stop'},@{t='/accept';k='accept'},@{t='Стоп!';k='stop'}
  ) { (Parse-Command -Text $t -Strict $true).k | Should -Be $k }
  It 'опасные ложные срабатывания из ревью больше не срабатывают: «<t>» -> <k>' -TestCases @(
    @{t='принял, спасибо';k='unknown'},@{t='джемини завершил?';k='unknown'},@{t='какой статус у остановки?';k='status'},
    @{t='продолжай, не стоп';k='unknown'},@{t='запусти тесты';k='unknown'},@{t='не останавливайся';k='unknown'},
    @{t='Режим вывода команд на экран (ECHO) отключен.';k='unknown'},@{t='ECHO is off.';k='unknown'},@{t='на экране что-то странное';k='unknown'},
    @{t='не прими это';k='unknown'}
  ) { (Parse-Command -Text $t -Strict $true).k | Should -Be $k }
  It 'новые команды: «передай всё равно» -> force, «отправь заново» -> resendstale, «да»/«нет»' {
    (Parse-Command 'передай всё равно').k | Should -Be 'force'
    (Parse-Command 'Передай все равно').k | Should -Be 'force'
    (Parse-Command 'отправь заново').k | Should -Be 'resendstale'
    (Parse-Command 'да').k | Should -Be 'confirm'; (Parse-Command 'нет').k | Should -Be 'cancel'
  }
  It 'аргументы сохраняются: gemini/ag и «весь ответ»' {
    $c=Parse-Command "/ag  сделай X`nи Y"; $c.arg | Should -Be "сделай X`nи Y"
    (Parse-Command 'передай весь ответ').whole | Should -BeTrue
  }
  It 'StrictCommands=false — прежнее (свободное) поведение для отката' {
    (Parse-Command -Text 'принял, спасибо' -Strict $false).k | Should -Be 'accept'
    (Parse-Command -Text 'джемини завершил?' -Strict $false).k | Should -Be 'stop'
  }
  It 'команды диалога — только при активном блокирующем окне; кнопка — в исходном регистре' {
    (Parse-Command -Text 'нажми ОК' -HasDialog $false).k | Should -Not -Be 'clickdlg'
    $c=Parse-Command -Text 'нажми ОК' -HasDialog $true; $c.k | Should -Be 'clickdlg'; $c.button | Should -Be 'ОК'
    (Parse-Command -Text 'нажми принять' -HasDialog $true).k | Should -Be 'accept'
    (Parse-Command -Text 'добавь в список Закрыть' -HasDialog $true).button | Should -Be 'Закрыть'
  }
}
Describe 'Пункт 8: кнопки диалогов' -Tag Item08 {
  It 'точное сравнение: «ок» не совпадает с «Блокировать», «.» ни с чем' {
    Test-ButtonMatch 'Блокировать' 'ок' | Should -BeFalse
    Test-ButtonMatch 'OK' '.' | Should -BeFalse
    Test-ButtonMatch ' OK ' 'ok' | Should -BeTrue
    Test-ButtonMatch 'Документ' 'ок' | Should -BeFalse
    Test-ButtonMatch 'X' '' | Should -BeFalse
  }
  It 'безопасные кнопки по умолчанию: без Да/Yes/Разрешить/Allow' {
    Select-SafeButton @('Да','Нет','Разрешить') $Cfg.SafeBtnRx | Should -BeNullOrEmpty
    Select-SafeButton @('Отмена','OK') $Cfg.SafeBtnRx | Should -Be 'OK'
  }
  It 'системные окна запрещены' {
    Test-ForbiddenWindow @{title='Контроль учётных записей';proc='consent';class='x'} | Should -BeTrue
    Test-ForbiddenWindow @{title='';proc='x';class='x'} | Should -BeTrue
    Test-ForbiddenWindow @{title='Сохранить?';proc='notepad';class='#32770'} | Should -BeFalse
  }
  It 'Click-DialogButton нажимает только точное совпадение' {
    Mock Uia-FindAll { @('B1','B2') }; Mock Uia-Name { if($el -eq 'B1'){ 'Блокировать' } else { 'ОК' } }
    Mock Uia-Invoke { $script:inv=$el; $true }; Mock Start-Sleep {}
    Click-DialogButton @{h=1;title='Диалог';proc='app';class='#32770'} 'ок' | Should -BeTrue
    $script:inv | Should -Be 'B2'
    Click-DialogButton @{h=1;title='Диалог';proc='app';class='#32770'} 'кнопка' | Should -BeFalse
  }
  It 'Try-AutoClose уважает AutoCloseProcRx' {
    Mock Get-Allowlist { @([ordered]@{ titleRegex='^Диалог$'; processName='^app$'; button='ОК' }) }
    Mock Click-DialogButton { $true }; Mock Log {}; Mock Tg-Send {}
    $Cfg.AutoCloseProcRx='^other$'; Try-AutoClose @{h=1;title='Диалог';proc='app';class='#32770'} | Should -BeFalse
    $Cfg.AutoCloseProcRx=''; Try-AutoClose @{h=1;title='Диалог';proc='app';class='#32770'} | Should -BeTrue
  }
}
Describe 'Пункт 8: подтверждение /ag из Telegram (опция)' -Tag Item08 {
  BeforeEach { $script:Queue.Clear(); $script:PendingConfirm=$null; $script:Blk=@{key=$null}; Mock Tg-Send { $true }; Mock Log {} }
  It 'TgConfirmAg=false — сразу в очередь (как раньше)' { $Cfg.TgConfirmAg=$false; Handle-Command '/ag привет' 'tg'; $script:Queue.Count | Should -Be 1 }
  It 'TgConfirmAg=true — спрашивает, «да» ставит в очередь, «нет» отменяет' {
    $Cfg.TgConfirmAg=$true
    Handle-Command '/ag привет' 'tg'; $script:Queue.Count | Should -Be 0
    Should -Invoke Tg-Send -ParameterFilter { $Text -like 'Отправить в Antigravity*' }
    Handle-Command 'да' 'tg'; $script:Queue.Count | Should -Be 1; $script:Queue.Peek().arg | Should -Be 'привет'
    $script:Queue.Clear(); Handle-Command '/gemini x' 'tg'; Handle-Command 'нет' 'tg'; $script:Queue.Count | Should -Be 0
  }
  It 'команды с ПК (GUI) подтверждения не требуют' { $Cfg.TgConfirmAg=$true; Handle-Command '/ag привет' 'pc'; $script:Queue.Count | Should -Be 1 }
}
