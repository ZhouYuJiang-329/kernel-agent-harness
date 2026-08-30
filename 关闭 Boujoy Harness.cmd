@echo off
setlocal
set "LOCALAPPDATA=%~dp0.state"
set "ROOT=%~dp0"
rem Strip the trailing backslash so -Root "%ROOT%" does not end with an
rem escaped quote (\" becomes a literal " in the argument).
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Stop-Boujoy.ps1" -Root "%ROOT%"
if errorlevel 1 pause
