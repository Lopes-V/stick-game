@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_web.ps1"
if errorlevel 1 (
  echo.
  echo WEB BUILD FAILED
  pause
  exit /b 1
)
echo.
echo WEB BUILD COMPLETE
pause

