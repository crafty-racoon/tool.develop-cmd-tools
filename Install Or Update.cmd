@echo off
setlocal
set "PROJECT_ROOT=%CD%"
if not "%~1"=="" set "PROJECT_ROOT=%~f1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" -ProjectRoot "%PROJECT_ROOT%" %2 %3 %4 %5 %6 %7 %8 %9
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
