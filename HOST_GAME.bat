@echo off
setlocal
chcp 65001 >nul
title Chaos Stick Arena - LAN Host
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0host_game.ps1" %*
if errorlevel 1 (
  echo.
  echo HOST FAILED. Review the message above. If a server started, details are in logs.
  pause
  exit /b 1
)

