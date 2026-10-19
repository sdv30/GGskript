@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
set "CMD="
set /p "CMD=Команда для GGskript: "
if not defined CMD goto :eof
rem echo( и отложенное раскрытие: спецсимволы в тексте команды не исполняются
>>"%~dp0commands.txt" echo(!CMD!
echo Отправлено: !CMD!
timeout /t 2 >nul
