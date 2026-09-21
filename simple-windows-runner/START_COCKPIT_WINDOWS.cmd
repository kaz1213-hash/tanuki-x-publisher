@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist "%~dp0JOB\job.json" (
  echo JOB\job.json is missing.
  exit /b 20
)
call "%~dp0RUN_JOB.cmd"
exit /b %ERRORLEVEL%
