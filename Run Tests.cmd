@echo off
setlocal
set "PROJECT_ROOT=%CD%"
if defined DEVELOP_CMD_PROJECT_ROOT set "PROJECT_ROOT=%DEVELOP_CMD_PROJECT_ROOT%"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-TestOperations.ps1" -ProjectRoot "%PROJECT_ROOT%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
