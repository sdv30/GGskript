BeforeAll {
  . (Join-Path $PSScriptRoot '_Load.ps1')
  $script:Cfg=New-TestCfg $TestDrive; $Cfg=$script:Cfg
}
Describe 'Пункт 59: сверка блока с IDE — не по общей шапке промпта' -Tag Item59 {
  BeforeEach { $Cfg.ContentKeyChars=120; $Cfg.ContentKeyMin=20 }
  It 'короткий текст — как раньше, целиком' {
    Test-TextInBody 'Hello unique world token 12345 abcdef' 'prefix Hello unique world token 12345 abcdef suffix' | Should -BeTrue
    Test-TextInBody 'Hello unique world token 12345 abcdef' 'other text only' | Should -BeFalse
  }
  It 'общая шапка ROLE без уникальной середины/хвоста — НЕ считает «уже есть»' {
    $head='markdown ROLE & OBJECTIVE: You are a Junior-to-Mid Python Developer working under a strict Senior Tech Lead on the Escalator project. '
    $a=$head + ('AAA_UNIQUE_BLOCK_A_' * 30) + ' END_A_TAIL_MARKER_999'
    $b=$head + ('BBB_UNIQUE_BLOCK_B_' * 30) + ' END_B_TAIL_MARKER_888'
    # в «теле IDE» лежит только блок B (другой ответ с той же шапкой)
    Test-TextInBody $a $b | Should -BeFalse
    Test-TextInBody $b $b | Should -BeTrue
  }
  It 'полный блок на странице — ЕСТЬ (mid и tail совпали)' {
    $block='ROLE OBJECTIVE shared header text for prompts. ' + ('unique_payload_xyz_' * 40) + ' final_tail_signature_42'
    Test-TextInBody $block ("noise `n$block`n more") | Should -BeTrue
  }
}

Describe 'Пункт 59: чип файла Gemini с укороченным именем' -Tag Item59 {
  It 'полное имя и укороченное «Eskalator_…-10-23_007» — совпадают' {
    Test-ChipMatchesName 'Eskalator_2026-10-23_007.md' 'Eskalator_2026-10-23_007.md' | Should -BeTrue
    Test-ChipMatchesName 'Eskalator_...-10-23_007' 'Eskalator_2026-10-23_007.md' | Should -BeTrue
    Test-ChipMatchesName 'Eskalator_…-10-23_007' 'Eskalator_2026-10-23_007.md' | Should -BeTrue
    Test-ChipMatchesName 'Arena_2026-10-23_049' 'Eskalator_2026-10-23_007.md' | Should -BeFalse
  }
}