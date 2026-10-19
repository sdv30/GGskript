@echo off
chcp 65001 >nul
title GGskript
rem GGskript v2: воркер в консоли (без панели). Параметры передаются дальше, например: GGskript.bat -check
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0GGskript.ps1" %*
pause
