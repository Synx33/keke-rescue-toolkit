@echo off
title USB Rescue Toolkit Creator
echo =============================================
echo  USB Rescue Toolkit Creator v2.0
echo  UEFI Boot ^| Offline ^| Multi-Tool
echo =============================================
echo.

:: Check for admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Please right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Running PowerShell script...
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "try { & '%~dp0Create-PasswordResetUSB.ps1' } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host $_.ScriptStackTrace -ForegroundColor Yellow }"

echo.
echo =============================================
echo Script finished. Press any key to close.
pause >nul
