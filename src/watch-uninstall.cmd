@echo off
setlocal EnableDelayedExpansion
rem Removes Watch Task Monitor. Your logs stay in place.
rem To remove the logs too, run:  watch-uninstall /logs
rem This script runs install.ps1 from a copy in %TEMP%, because it deletes its own folder.
set "WTM_COPY=%TEMP%\wtm-uninstall-%RANDOM%.ps1"
copy /y "%~dp0install.ps1" "%WTM_COPY%" >nul
if errorlevel 1 (
    echo Could not copy install.ps1. Uninstall stopped.
    exit /b 1
)
set "WTM_FLAG="
if /i "%~1"=="/logs" set "WTM_FLAG=-RemoveLogs"
rem The next block is read as one unit. This lets the script delete itself safely.
(
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WTM_COPY%" -Action Uninstall %WTM_FLAG%
    set "WTM_RC=!ERRORLEVEL!"
    del "%WTM_COPY%" >nul 2>&1
    exit /b !WTM_RC!
)
