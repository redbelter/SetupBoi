@echo off
rem SetupBoi - double-click friendly launcher (self-elevates via setup.ps1)
title SetupBoi
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
