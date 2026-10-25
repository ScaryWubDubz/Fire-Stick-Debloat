@echo off
title Fire Stick Cleanup
rem Double-clicking this inside the zip runs it without the other files.
if not exist "%~dp0FireStick.ps1" (
    echo.
    echo The tool's files haven't been unzipped yet.
    echo   1. Close this window.
    echo   2. Right-click the Fire-Stick-Debloat zip file and choose "Extract All", then click Extract.
    echo   3. In the folder that opens, double-click Start-Here.bat.
    echo.
    pause
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FireStick.ps1"
echo.
pause
