@echo off
rem GGskript v2 (item 27B): Antigravity with DevTools port - AgTransport=cdp: text goes into the agent chat
rem without window focus, OS keyboard or clipboard.
rem FIRST close Antigravity completely (File - Exit). If it is still running, the new flag is ignored.
rem Security: while it runs, local programs can control Antigravity via 127.0.0.1:PORT.
rem Usage: Start-Antigravity-Debug.bat [port]   (default 9333)
setlocal
set "PORT=%~1"
if "%PORT%"=="" set "PORT=9333"
set "AG=%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe"
if not exist "%AG%" set "AG=%LOCALAPPDATA%\Programs\Antigravity\Antigravity.exe"
if not exist "%AG%" (
  echo Antigravity not found.
  pause
  exit /b 1
)
tasklist /fi "imagename eq Antigravity IDE.exe" 2>nul | find /i "Antigravity IDE.exe" >nul
if not errorlevel 1 (
  echo Antigravity is still running. Close it completely - File, Exit - and run this file again.
  pause
  exit /b 1
)
echo Starting %AG% with DevTools on 127.0.0.1:%PORT%
start "" "%AG%" --remote-debugging-port=%PORT% --remote-allow-origins=http://127.0.0.1:%PORT%
endlocal
