@echo off
setlocal
title X47 Windows 11
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-X47Windows.ps1" %*
if errorlevel 1 (
  echo.
  echo The kit reported an error. Scroll up or open logs\*.log
  pause
  exit /b 1
)
echo.
pause
