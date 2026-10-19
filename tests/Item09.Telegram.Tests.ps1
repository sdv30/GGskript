BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
  $script:FakeTok='123456789:AAFakeTokenForTestsOnly_abcdefghij'
}
Describe 'Пункт 9: токен (DPAPI) и конфиг' -Tag Item09 {
  BeforeEach { Remove-Item $Cfg.TokenFile,$Cfg.ConfigFile,"$($Cfg.ConfigFile).bak" -EA 0; $script:TokenWarned=$false; Mock Log {} }
  It 'берёт токен из tg_token.dpapi, если файл есть (открытый текст не нужен)' {
    [IO.File]::WriteAllText($Cfg.TokenFile,'BLOB'); Mock Unprotect-Secret { if($Blob -eq 'BLOB'){ $script:FakeTok } }
    Get-TgToken @{ telegram_token='plain' } | Should -Be $script:FakeTok
    Should -Invoke Log -Times 0 -ParameterFilter { $m -like '*открытым текстом*' }
  }
  It 'нет DPAPI-файла — берёт из конфига и предупреждает один раз' {
    Get-TgToken @{ telegram_token='plain' } | Should -Be 'plain'; Get-TgToken @{ telegram_token='plain' } | Out-Null
    Should -Invoke Log -Times 1 -Exactly -ParameterFilter { $m -like '*открытым текстом*' }
  }
  It 'DPAPI-файл не расшифровывается — откат на конфиг с записью в лог' {
    [IO.File]::WriteAllText($Cfg.TokenFile,'BAD'); Mock Unprotect-Secret { throw 'ключ не тот' }
    Get-TgToken @{ telegram_token='plain' } | Should -Be 'plain'
    Should -Invoke Log -ParameterFilter { $m -like '*не удалось расшифровать*' }
  }
  It 'нет ни того, ни другого — $null, Telegram выключен' { Get-TgToken @{} | Should -BeNullOrEmpty }
  It 'relay_config.example.json — валидный JSON без токена' {
    $j=Get-Content (Join-Path $PSScriptRoot '..\relay_config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $j.telegram_token | Should -BeNullOrEmpty; $j.PSObject.Properties.Name | Should -Contain 'chat_id'
  }
  It 'Set-TgToken.ps1 -FromConfig -RemovePlain: шифрует, проверяет, убирает токен из конфига, chat_id остаётся' {
    [IO.File]::WriteAllText($Cfg.ConfigFile,(@{ telegram_token=$script:FakeTok; telegram_username='u'; chat_id='42' } | ConvertTo-Json))
    Mock Protect-Secret { 'ENC:'+$Plain }; Mock Unprotect-Secret { $Blob -replace '^ENC:','' }; Mock Write-Host {}
    & (Join-Path $PSScriptRoot '..\Set-TgToken.ps1') -FromConfig -RemovePlain -Root $TestDrive
    [IO.File]::ReadAllText($Cfg.TokenFile) | Should -Be ('ENC:'+$script:FakeTok)
    $c=Get-Content $Cfg.ConfigFile -Raw | ConvertFrom-Json
    $c.PSObject.Properties.Name | Should -Not -Contain 'telegram_token'; $c.chat_id | Should -Be '42'
    Test-Path "$($Cfg.ConfigFile).bak" | Should -BeTrue
  }
  It 'Set-TgToken.ps1 отказывается сохранять мусор вместо токена' {
    [IO.File]::WriteAllText($Cfg.ConfigFile,(@{ telegram_token='не токен' } | ConvertTo-Json)); Mock Write-Host {}; Mock Protect-Secret { 'x' }
    & (Join-Path $PSScriptRoot '..\Set-TgToken.ps1') -FromConfig -Root $TestDrive
    Test-Path $Cfg.TokenFile | Should -BeFalse
  }
  It 'Resolve-ChatId: находит личный чат нужного пользователя и сохраняет атомарно' {
    [IO.File]::WriteAllText($Cfg.ConfigFile,'{"telegram_username":"Me"}')
    Mock Invoke-Tg { [pscustomobject]@{ result=@(
      [pscustomobject]@{ message=[pscustomobject]@{ from=[pscustomobject]@{username='other';id=5}; chat=[pscustomobject]@{id=5} } },
      [pscustomobject]@{ message=[pscustomobject]@{ from=[pscustomobject]@{username='me';id=77}; chat=[pscustomobject]@{id=77} } }) } }
    $c=Load-TgCfg; Resolve-ChatId $c | Should -Be '77'
    (Get-Content $Cfg.ConfigFile -Raw | ConvertFrom-Json).chat_id | Should -Be '77'
  }
}
Describe 'Пункт 9: единый отправитель Tg-Send / Notify' -Tag Item09 {
  BeforeEach { $script:TgToken='t'; $script:TgChat='1'; $script:LastTg=@{}; $script:LogReplies=$false; $script:sent=@(); Mock Log {}; Mock Invoke-Tg { $script:sent+=$Body.text } }
  It 'без токена ничего не отправляет' { $script:TgToken=$null; Tg-Send 'x' | Should -BeFalse; Should -Invoke Invoke-Tg -Times 0 }
  It 'длинный текст режется на части ≤ 4000' { Tg-Send ('a'*9000) | Should -BeTrue; $script:sent.Count | Should -Be 3; ($script:sent | ForEach-Object Length | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 4000 }
  It 'Notify: префикс, дедуп 10 минут, -Force обходит дедуп' {
    Notify 'ошибка'; Notify 'ошибка'; $script:sent.Count | Should -Be 1; $script:sent[0] | Should -Be 'GGskript: ошибка'
    Notify 'ошибка' -Force; $script:sent.Count | Should -Be 2
  }
  It 'ошибка сети не роняет, возвращает false и пишет в лог' { Mock Invoke-Tg { throw 'нет сети' }; Tg-Send 'x' | Should -BeFalse; Should -Invoke Log -ParameterFilter { $m -like '*не удалось отправить*' } }
  It 'токен не попадает в лог при ошибке' { $script:TgToken=$script:FakeTok; Mock Invoke-Tg { throw 'boom' }; Tg-Send 'x' | Out-Null; Should -Invoke Log -Times 0 -ParameterFilter { $m -like "*$($script:FakeTok)*" } }
}
Describe 'Пункт 9: Poll-Tg' -Tag Item09 {
  BeforeEach { $script:TgToken='t'; $script:TgChat='77'; $script:TgOffset=0; $script:TgBackoffUntil=$null; $script:StartUnix=1000; $script:cmds=@(); Mock Log {}; Mock Handle-Command { $script:cmds+=$Text } }
  It 'принимает только свой чат и новые сообщения, сохраняет offset' {
    Mock Invoke-Tg { [pscustomobject]@{ result=@(
      [pscustomobject]@{ update_id=10; message=[pscustomobject]@{ text='старое'; date=999; chat=[pscustomobject]@{id=77}; from=[pscustomobject]@{id=77} } },
      [pscustomobject]@{ update_id=11; message=[pscustomobject]@{ text='чужое'; date=2000; chat=[pscustomobject]@{id=5}; from=[pscustomobject]@{id=5;username='x'} } },
      [pscustomobject]@{ update_id=12; message=[pscustomobject]@{ text='статус'; date=2000; chat=[pscustomobject]@{id=77}; from=[pscustomobject]@{id=77} } }) } }
    Poll-Tg
    $script:cmds | Should -Be @('статус'); $script:TgOffset | Should -Be 13
    [IO.File]::ReadAllText($Cfg.TgOffsetFile) | Should -Be '13'
  }
  It 'нет сети — пауза 30 с без повторных запросов' {
    Mock Invoke-Tg { throw 'нет сети' }
    Poll-Tg; Poll-Tg; Poll-Tg
    Should -Invoke Invoke-Tg -Times 1 -Exactly
    $script:TgBackoffUntil | Should -BeGreaterThan (Get-Date).AddSeconds(25)
  }
}
Describe 'Пункт 9: скриншоты блок-окна' -Tag Item09 {
  BeforeEach { Mock Log {}; Mock Tg-Send { $true }; Mock Send-Screenshot {} }
  It 'ScreenshotMode=dialog: диалог — снимок только области окна' {
    $Cfg.ScreenshotMode='dialog'; $r=@{x=1;y=2;w=300;h=200}
    Notify-Block @{ title='Сохранить?'; proc='notepad'; class='#32770'; buttons=@('Да','Нет'); rect=$r; area=0.05 }
    Should -Invoke Send-Screenshot -Times 1 -ParameterFilter { $Rect.w -eq 300 }
    Should -Invoke Tg-Send -Times 0
  }
  It 'ScreenshotMode=dialog: обычное окно (редактор во весь экран) — только текст, без снимка' {
    $Cfg.ScreenshotMode='dialog'
    Notify-Block @{ title='secret.txt - Блокнот'; proc='notepad'; class='Notepad'; buttons=@(); rect=@{x=0;y=0;w=1920;h=1080}; area=0.95 }
    Should -Invoke Send-Screenshot -Times 0; Should -Invoke Tg-Send -Times 1
  }
  It 'ScreenshotMode=off — никогда не снимает; full — весь экран (прежнее поведение)' {
    $Cfg.ScreenshotMode='off'; Notify-Block @{ title='Д'; proc='a'; class='#32770'; buttons=@('OK'); rect=@{w=1}; area=0.01 }
    Should -Invoke Send-Screenshot -Times 0
    $Cfg.ScreenshotMode='full'; Notify-Block @{ title='Д'; proc='a'; class='X'; buttons=@(); area=0.9 }
    Should -Invoke Send-Screenshot -Times 1 -ParameterFilter { $null -eq $Rect }
  }
  It 'снимок не удался — отправляет текст' { $Cfg.ScreenshotMode='dialog'; Mock Send-Screenshot { throw 'нет' }; Notify-Block @{ title='Д'; proc='a'; class='#32770'; buttons=@('OK'); rect=@{w=1}; area=0.01 }; Should -Invoke Tg-Send -Times 1 }
  It 'Test-LooksLikeDialog: <n>' -TestCases @(
    @{n='класс #32770';i=@{class='#32770';buttons=@()};e=$true},
    @{n='маленькое окно с кнопками';i=@{class='X';buttons=@('OK','Отмена');area=0.1};e=$true},
    @{n='большое окно';i=@{class='X';buttons=@('OK');area=0.8};e=$false},
    @{n='без кнопок';i=@{class='X';buttons=@();area=0.1};e=$false},
    @{n='много кнопок (приложение)';i=@{class='X';buttons=@(1..20);area=0.2};e=$false}
  ) { Test-LooksLikeDialog $i | Should -Be $e }
}
