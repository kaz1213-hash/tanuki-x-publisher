@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ============================================================
echo   Tanuki Windows Runner v0.2
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunJob.ps1"
set "RC=%ERRORLEVEL%"
echo.
if exist "%~dp0RESULT.zip" (
  echo RESULT.zip is ready:
  echo   %~dp0RESULT.zip
  start "" explorer.exe /select,"%~dp0RESULT.zip"
) else (
  echo RESULT.zip was not created. RESULT.json should still exist.
  if exist "%~dp0RESULT.json" start "" explorer.exe /select,"%~dp0RESULT.json"
)
echo.
exit /b %RC%
