@echo off
setlocal EnableExtensions
set "PAYLOAD_COMMIT=d7623baa2b58a21013fd89a54349d48c8cf0b2bf"
set "WORK=%LOCALAPPDATA%\TanukiFactory\CockpitRC3Final_d7623baa"
set "ARCHIVE=%TEMP%\TanukiCockpitRC3Final_d7623baa.zip"

echo ============================================================
echo   Tanuki Windows Factory - Clinic Cockpit RC3 Final
echo   Self-contained canonical package lane
echo   Exact payload: %PAYLOAD_COMMIT%
echo ============================================================
echo.

if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" >nul 2>nul
if errorlevel 1 goto BOOTSTRAP_FAIL

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/kaz1213-hash/tanuki-x-publisher/archive/%PAYLOAD_COMMIT%.zip' -OutFile '%ARCHIVE%'; Expand-Archive -LiteralPath '%ARCHIVE%' -DestinationPath '%WORK%' -Force"
if errorlevel 1 goto BOOTSTRAP_FAIL

for /f "delims=" %%F in ('powershell.exe -NoLogo -NoProfile -Command "$f=@(Get-ChildItem -LiteralPath '%WORK%' -Filter 'START_COCKPIT_RC3_FINAL.cmd' -File -Recurse); if($f.Count -ne 1){exit 21}; $f[0].FullName"') do set "LAUNCHER=%%F"
if not defined LAUNCHER goto BOOTSTRAP_FAIL

call "%LAUNCHER%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" exit /b 0

echo.
echo The Factory stopped safely. No debugging is required from you.
echo The payload already captured privacy-bounded evidence.
pause
exit /b %RC%

:BOOTSTRAP_FAIL
echo.
echo The one-click bootstrap could not start the Factory payload.
echo No PowerShell, Git, or log inspection is required from you.
pause
exit /b 90
