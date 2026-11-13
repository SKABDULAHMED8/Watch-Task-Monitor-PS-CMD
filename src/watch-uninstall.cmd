@echo off
rem Removes Watch Task Monitor. Your logs stay in place.
rem To remove the logs too, run:  watch-uninstall /logs
rem install.ps1 runs from a copy in %TEMP%, because it deletes the folder of this file.
set "WTM_COPY=%TEMP%\wtm-uninstall-%RANDOM%.ps1"
copy /y "%~dp0install.ps1" "%WTM_COPY%" >nul
if errorlevel 1 (
    echo Could not copy install.ps1. Uninstall stopped.
    exit /b 1
)
set "WTM_FLAG="
if /i "%~1"=="/logs" set "WTM_FLAG=-RemoveLogs"
rem "(goto) 2>nul" ends this batch file first. The part after "&" then runs without it.
rem This way Windows can delete this file, and CMD does not look for it again.
(goto) 2>nul & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WTM_COPY%" -Action Uninstall %WTM_FLAG%
