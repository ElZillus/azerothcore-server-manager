@echo off
title AzerothCore 1-Klick-Installer
cd /d "%~dp0"

:: Adminrechte anfordern (fuer winget / Visual Studio Build Tools noetig)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administratorrechte werden angefordert...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AzerothCore-Installer.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Der Installer wurde mit einem Fehler beendet.
    pause
)
