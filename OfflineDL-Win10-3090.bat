@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OfflineDL-Win10-3090.ps1" %*
set EXITCODE=%ERRORLEVEL%
if "%1"=="" pause
exit /b %EXITCODE%
