@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0RunRecovery.ps1"
exit /b %errorlevel%
