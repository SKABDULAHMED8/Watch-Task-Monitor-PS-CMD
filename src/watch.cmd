@echo off
rem Watch Task Monitor launcher.
rem Sends all arguments to run-task.ps1 and returns the exit code of your command.
powershell.exe -NoProfile -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0run-task.ps1" %*
exit /b %ERRORLEVEL%
