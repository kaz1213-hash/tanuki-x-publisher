@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ============================================================
echo   Tanuki Windows Runner v0.5 - Standalone Self-Test
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunJob.ps1" -JobDirectory "%~dp0SELFTEST_JOB"
set "RC=%ERRORLEVEL%"
echo.
if exist "%~dp0RESULT.zip" (
  echo RESULT.zip is ready:
  echo   %~dp0RESULT.zip
  start "" explorer.exe /select,"%~dp0RESULT.zip"
)
echo.
exit /b %RC%
