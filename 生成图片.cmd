@echo off
setlocal
set "PS=%~dp0Report.ps1"
set "TXT=%~dp0..\..\..\..\..\PBZ_Achievement_Check.txt"
if not exist "%TXT%" set "TXT=%~dp0..\..\..\..\..\..\PBZ_Achievement_Check.txt"
if not exist "%TXT%" (
  echo Report not found. Run F7 in game first.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS%" -Txt "%TXT%"
if errorlevel 1 pause