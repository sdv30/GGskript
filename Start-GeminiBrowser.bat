@echo off
rem GGskript (fallback launcher): separate Chromium browser for Gemini with DevTools port - GeminiTransport=cdp.
rem Default is Google Chrome (same as Start-GeminiChrome.bat). Pass "yandex" or "edge" to use Yandex Browser or Microsoft Edge.
rem Own profile per browser in %LOCALAPPDATA%\GGskript: your normal browser, tabs and logins are NOT touched.
rem Sign in to Google in this window once. Keep it open (it may be minimized or behind other windows).
rem Security: while it runs, local programs can control THIS profile via 127.0.0.1:PORT.
rem Usage: Start-GeminiBrowser.bat [port] [chrome^|yandex^|edge]   (default 9222 chrome)
setlocal
set "PORT=%~1"
if "%PORT%"=="" set "PORT=9222"
set "PREF=%~2"
if "%PREF%"=="" set "PREF=chrome"
set "BR="
if /i "%PREF%"=="yandex" goto yandex
if /i "%PREF%"=="edge" goto edge
if /i "%PREF%"=="chrome" goto chrome
echo Unknown browser "%PREF%". Use: chrome, yandex or edge.
pause
exit /b 1
:chrome
set "PROFILE=%LOCALAPPDATA%\GGskript\chrome-gemini-profile"
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BR=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BR if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BR=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined BR if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "BR=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
goto found
:yandex
set "PROFILE=%LOCALAPPDATA%\GGskript\gemini-profile"
if exist "%LOCALAPPDATA%\Yandex\YandexBrowser\Application\browser.exe" set "BR=%LOCALAPPDATA%\Yandex\YandexBrowser\Application\browser.exe"
if not defined BR if exist "%ProgramFiles%\Yandex\YandexBrowser\Application\browser.exe" set "BR=%ProgramFiles%\Yandex\YandexBrowser\Application\browser.exe"
goto found
:edge
set "PROFILE=%LOCALAPPDATA%\GGskript\edge-gemini-profile"
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "BR=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined BR if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "BR=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
goto found
:found
if not defined BR (
  echo Browser "%PREF%" not found.
  pause
  exit /b 1
)
netstat -ano | findstr /r /c:"127\.0\.0\.1:%PORT% .*LISTENING" >nul
if not errorlevel 1 (
  echo Port %PORT% is already listening - the Gemini browser is probably already running.
  timeout /t 5 >nul
  exit /b 0
)
if not exist "%PROFILE%" mkdir "%PROFILE%"
echo Starting %BR% on 127.0.0.1:%PORT% with profile %PROFILE%
start "" "%BR%" --remote-debugging-port=%PORT% --remote-debugging-address=127.0.0.1 --remote-allow-origins=http://127.0.0.1:%PORT% --user-data-dir="%PROFILE%" --no-first-run --no-default-browser-check https://gemini.google.com/app https://gemini.google.com/usage
endlocal
