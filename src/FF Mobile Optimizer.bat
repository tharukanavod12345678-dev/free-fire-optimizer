@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title FF Mobile Optimizer - Free Fire for Android
cd /d "%~dp0"

rem ============================================================
rem   FF Mobile Optimizer launcher
rem   Keep this file in the SAME folder as FFMobileOptimizer.ps1
rem   No administrator rights needed on the PC.
rem ============================================================

if not exist "%~dp0FFMobileOptimizer.ps1" (
    echo.
    echo   [ERROR] FFMobileOptimizer.ps1 was not found next to this .bat
    echo           Put both files in the same folder and try again.
    echo.
    pause
    exit /b 1
)

rem ---- Prefer PowerShell 7, fall back to Windows PowerShell -------------
set "PSEXE=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PSEXE=pwsh.exe"

echo.
echo   FF Mobile Optimizer  ^(using %PSEXE%^)
echo   ------------------------------------------------
echo   Make sure on the phone:
echo     1. Settings ^> About phone ^> tap "Build number" 7 times
echo     2. Developer options ^> USB debugging = ON
echo     3. Connect the USB cable, choose "File transfer"
echo     4. Accept the "Allow USB debugging?" popup
echo.
pause
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0FFMobileOptimizer.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo   Finished with exit code %RC%.
echo   --- window closes when you press a key ---
pause >nul
endlocal
