@echo off
title Fire Stick Cleanup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FireStick.ps1"
echo.
pause
