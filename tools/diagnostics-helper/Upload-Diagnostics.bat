@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Upload-Diagnostics.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
