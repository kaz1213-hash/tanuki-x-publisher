@echo off
rem STAGED ONLY - not Windows-qualified or approved for Director handoff.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0ApplyVerifiedRecovery.ps1"
exit /b %errorlevel%
