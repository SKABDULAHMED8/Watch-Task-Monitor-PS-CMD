@echo off
setlocal
rem Watch Task Monitor installer.
rem   install.cmd           Install
rem   install.cmd repair    Remove the old files and install fresh files
rem   install.cmd uninstall Remove Watch Task Monitor
rem If the other files are not next to this file, they are downloaded first.

set "WTM_ACTION=Install"
if /i "%~1"=="repair" set "WTM_ACTION=Repair"
if /i "%~1"=="uninstall" set "WTM_ACTION=Uninstall"

set "WTM_BASE=https://raw.githubusercontent.com/SKABDULAHMED8/Watch-Task-Monitor-PS-CMD/main"
set "WTM_SRC=%~dp0"
set "WTM_TMP="

if exist "%WTM_SRC%install.ps1" if exist "%WTM_SRC%src\run-task.ps1" if exist "%WTM_SRC%src\watch.cmd" if exist "%WTM_SRC%src\watch-uninstall.cmd" goto run

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo curl.exe was not found. It comes with Windows 10 version 1803 and later.
    echo Download the project from GitHub instead, then run install.cmd from the folder.
    exit /b 1
)

set "WTM_TMP=%TEMP%\wtm-setup-%RANDOM%"
mkdir "%WTM_TMP%\src" >nul 2>&1
echo Downloading Watch Task Monitor...
curl.exe -fsSL "%WTM_BASE%/install.ps1" -o "%WTM_TMP%\install.ps1" || goto download_failed
curl.exe -fsSL "%WTM_BASE%/src/run-task.ps1" -o "%WTM_TMP%\src\run-task.ps1" || goto download_failed
curl.exe -fsSL "%WTM_BASE%/src/watch.cmd" -o "%WTM_TMP%\src\watch.cmd" || goto download_failed
curl.exe -fsSL "%WTM_BASE%/src/watch-uninstall.cmd" -o "%WTM_TMP%\src\watch-uninstall.cmd" || goto download_failed
set "WTM_SRC=%WTM_TMP%\"

:run
rem The folder name must not end with a backslash inside quotes. This removes it.
set "WTM_SRC_ARG=%WTM_SRC:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WTM_SRC_ARG%\install.ps1" -Action %WTM_ACTION% -SourceDir "%WTM_SRC_ARG%"
set "WTM_RC=%ERRORLEVEL%"
if defined WTM_TMP rmdir /s /q "%WTM_TMP%" >nul 2>&1
exit /b %WTM_RC%

:download_failed
echo Download failed. Check your internet connection and try again.
if defined WTM_TMP rmdir /s /q "%WTM_TMP%" >nul 2>&1
exit /b 1
