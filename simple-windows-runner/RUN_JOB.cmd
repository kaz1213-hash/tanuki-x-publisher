@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ============================================================
echo   Tanuki Windows Runner v0.1
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunJob.ps1"
set "RC=%ERRORLEVEL%"
echo.
if exist "%~dp0RESULT.zip" (
  echo RESULT.zip is ready:
  echo   %~dp0RESULT.zip
) else (
  echo RESULT.zip was not created. RESULT.json should still exist.
)
echo.
pause
exit /b %RC%
