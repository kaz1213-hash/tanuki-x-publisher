@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ============================================================
echo   Tanuki Windows Runner v0.5 - Standalone Self-Test
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunJob.ps1" -JobDirectory "%~dp0SELFTEST_JOB"
set "RUN_RC=%ERRORLEVEL%"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VerifyRunnerSelfTest.ps1" -RunnerRoot "%~dp0"
set "VERIFY_RC=%ERRORLEVEL%"
echo.
if exist "%~dp0FACTORY_SELFTEST_RESULT.zip" (
  echo FACTORY_SELFTEST_RESULT.zip is ready:
  echo   %~dp0FACTORY_SELFTEST_RESULT.zip
  start "" explorer.exe /select,"%~dp0FACTORY_SELFTEST_RESULT.zip"
) else (
  echo Self-test evidence package was not created.
)
echo.
if not "%RUN_RC%"=="0" exit /b %RUN_RC%
exit /b %VERIFY_RC%
