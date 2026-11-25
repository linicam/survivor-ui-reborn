@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Upload-Diagnostics.ps1" -SelfTest
echo.
echo Self-test finished with exit code %ERRORLEVEL%.
pause
exit /b %ERRORLEVEL%
