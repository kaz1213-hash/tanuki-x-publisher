@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo   Tanuki Windows Factory - Clinic Cockpit RC3 Final Canary
echo   One click: Windows Candidate gate + final visual launch
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunJob.ps1" -JobDirectory "jobs\clinic-cockpit-rc3"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto PASS
echo.
echo Factory did not reach PASS. No debugging is required from you.
echo Safe evidence is already in RESULT.zip beside this launcher.
echo.
pause
exit /b %RC%
:PASS
echo.
echo Windows Candidate PASS. The exact final app is being launched automatically.
echo Final touch: visually confirm the dedicated UKE and ChatGPT top-level tabs.
exit /b 0
