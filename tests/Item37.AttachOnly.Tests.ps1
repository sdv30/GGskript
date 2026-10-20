BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 37: отчёт в Gemini — только вложением через «+», без текста' -Tag Item37 {
  BeforeEach {
    Mock Log {}; $script:Tg=@(); Mock Tg-Send { $script:Tg+=[string]@($PesterBoundParameters.Values)[0]; 1 }; Mock Save-State {}
    $script:St=New-RelayState; $script:Held=@{}; $script:Adopted=@{}; $script:AutoSend=@{}; $script:SendNotBefore=@{}
    Get-ChildItem $Cfg.Downloads | Remove-Item -Force
    $p=Join-Path $Cfg.Downloads 'Arena_2026-10-20_004.md'; [IO.File]::WriteAllText($p,'отчёт агента: сделано много всего полезного'); $script:F=Get-Item $p
    Mock Wait-FileStable {}; Mock Assert-CanSendGemini { 'Argon' }; Mock Wait-GemAnswerStoppable {}; Mock Get-ModelNow { 'Argon' }
    Mock Check-OurPrompt {}; Mock Gem-LastReportPrompt { 'Arena_2026-10-20_004.md' }; Mock Gem-CopyCode { $null }
    Mock Get-WholeAnswer { @{ text='' } }; Mock Send-NoCodePrompt {}; Mock Play-Sound {}; Mock Gem-FindFile { $null }
    Mock Gem-Send { throw 'вставка текста отчёта запрещена' }
  }
  It 'Process-File отправляет файл (путь и имя), Gem-Send (текст) не вызывается' {
    Mock Gem-SendFile { @{ pBefore=1; via='uia-file' } }
    Process-File $script:F
    Should -Invoke Gem-SendFile -Times 1 -Exactly -ParameterFilter { $Path -eq $script:F.FullName -and $Name -eq 'Arena_2026-10-20_004.md' }
    Should -Invoke Gem-Send -Times 0
  }
  It 'не удалось прикрепить — ошибка и сообщение, без вставки текста, файл остаётся в очереди' {
    Mock Gem-SendFile { throw [GG.RelayNotSentException]::new('кнопка «+» не найдена') }
    { Process-File $script:F } | Should -Throw
    Should -Invoke Gem-Send -Times 0; Get-Stage 'Arena_2026-10-20_004.md' | Should -Be ''
    ($script:Tg -join "`n") | Should -Match 'не удалось прикрепить файл'
  }
  It 'чип вложения: имя элемента равно имени отчёта (с .md / без / с размером)' {
    Get-ChipReportName 'Arena_2026-10-20_003.md' | Should -Be 'Arena_2026-10-20_003.md'
    Get-ChipReportName 'Arena_2026-10-20_003' | Should -Be 'Arena_2026-10-20_003.md'
    Get-ChipReportName 'Arena_2026-10-20_003.md 12 КБ' | Should -Be 'Arena_2026-10-20_003.md'
    Get-ChipReportName 'Gemini упомянул Arena_2026-10-20_003.md в ответе' | Should -BeNullOrEmpty
  }
  It 'ручная отправка вложением: Find-FileInTexts находит по чипу, а не по упоминанию' {
    $r=Find-FileInTexts -Name 'Arena_2026-10-20_003.md' -Content '' -Texts @('ответ: см. Arena_2026-10-20_003.md','Arena_2026-10-20_003.md')
    $r.how | Should -Be 'name'; $r.index | Should -Be 1
    Find-FileInTexts -Name 'Arena_2026-10-20_003.md' -Content '' -Texts @('ответ: см. Arena_2026-10-20_003.md') | Should -BeNullOrEmpty
  }
}
