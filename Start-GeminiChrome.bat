@echo off
rem GGskript v2: Gemini in a separate Google Chrome window with DevTools port (GeminiTransport=cdp).
rem Always Chrome (never Yandex). Own profile %LOCALAPPDATA%\GGskript\chrome-gemini-profile.
rem Security: while it runs, local programs can control THIS profile via 127.0.0.1:PORT.
rem Usage: Start-GeminiChrome.bat [port]   (default 9222)
setlocal
set "PORT=%~1"
if "%PORT%"=="" set "PORT=9222"
set "PROFILE=%LOCALAPPDATA%\GGskript\chrome-gemini-profile"
set "BR="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BR=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BR if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BR=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined BR if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "BR=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not defined BR (
  echo Google Chrome not found.
  pause
  exit /b 1
)
set "PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:"127\.0\.0\.1:%PORT% .*LISTENING"') do set "PID=%%p"
if defined PID (
  tasklist /fi "PID eq %PID%" /fo csv /nh | findstr /i "chrome.exe" >nul
  if not errorlevel 1 (
    echo Chrome for Gemini is already running on port %PORT%.
    timeout /t 5 >nul
    exit /b 0
  )
  echo Port %PORT% is busy by another program, PID %PID%:
  tasklist /fi "PID eq %PID%" /fo table /nh
  echo Close that separate GGskript browser window and run this file again.
  pause
  exit /b 1
)
if not exist "%PROFILE%" mkdir "%PROFILE%"
echo Starting Chrome on 127.0.0.1:%PORT% with profile %PROFILE%
start "" "%BR%" --remote-debugging-port=%PORT% --remote-debugging-address=127.0.0.1 --remote-allow-origins=http://127.0.0.1:%PORT% --user-data-dir="%PROFILE%" --no-first-run --no-default-browser-check https://gemini.google.com/app https://gemini.google.com/usage
endlocal
