@echo off
rem Double-click to build the exes. Runs build.ps1 with PowerShell's script blocking off for this run only
rem (Windows blocks .ps1 files by default, and ones downloaded from GitHub even more).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
echo.
pause
