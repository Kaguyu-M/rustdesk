@echo off
:: Double-click: relaunch elevated, then run lancer.ps1
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lancer.ps1"
