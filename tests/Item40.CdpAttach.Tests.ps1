BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 40: вложение через CDP — кнопка «Загрузка и инструменты», файл по backendNodeId из Page.fileChooserOpened' -Tag Item40 {
  BeforeEach {
    Mock Log {}; Mock Assert-CanSendGemini { 'Argon' }; Mock Start-Sleep {}
    $script:Conn=@{ ws=$null; nextId=0 }; Mock Connect-Cdp { $script:Conn }
    $script:Calls=New-Object System.Collections.ArrayList; $script:Prompts=1
    Mock Invoke-Cdp { [void]$script:Calls.Add(@{ m=$Method; p=$Params })
      if($Method -eq 'Page.setInterceptFileChooserDialog' -and $Params.enabled -and $Conn.events -is [System.Collections.IList]){ [void]$Conn.events.Add([pscustomobject]@{ method='Page.fileChooserOpened'; params=[pscustomobject]@{ backendNodeId=77; mode='selectMultiple' } }) }
      @{} }
    Mock Eval-Js { switch($Op){ 'ready'{ $true } 'focusClear'{ $true } 'prompts'{ $script:Prompts } 'state'{ @{ n=1 } } 'openUpload'{ 'ok' } 'clickUploadItem'{ $true }
      'chips'{ @('Arena_2026-10-20_006 MD') } 'sendEnabled'{ $true } 'inputText'{ '' } 'clickSend'{ $script:Prompts=2; $true } } }
  }
  It 'ставит файл по backendNodeId и отправляет без текста' {
    $r=GemCdp-SendFile 'C:\x\Arena_2026-10-20_006.md' 'Arena_2026-10-20_006.md'
    $r.via | Should -Be 'cdp-file'
    $set=@($script:Calls | Where-Object { $_.m -eq 'DOM.setFileInputFiles' })
    $set.Count | Should -Be 1; $set[0].p.backendNodeId | Should -Be 77
    @($script:Calls | Where-Object { $_.m -eq 'Input.insertText' }).Count | Should -Be 0
  }
  It 'JS: кнопка ищется регуляркой (кириллица без учёта регистра)' {
    $script:GemJs | Should -Match 'загрузк'
    $script:GemJs | Should -Match "aria-expanded"
  }
}
