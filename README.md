# Watch Task Monitor

Watch Task Monitor runs a command in CMD or PowerShell. It shows the time the command took, the exit code and the result. It also writes one line to a log file.

Use `watch` before a command:

```cmd
watch ping 127.0.0.1 -n 4
```

## What it does

- Runs a CMD command, a Windows PowerShell command or a PowerShell 7 command.
- Shows the output of the command.
- Shows the status (`SUCCESS` or `FAILED`), the elapsed time and the exit code.
- Returns the exit code of your command. Scripts and batch files can use it.
- Writes one line for each command to a log file.

## Requirements

- Windows 10 or Windows 11.
- CMD and Windows PowerShell 5.1. Both are part of Windows.
- `curl.exe`. It is part of Windows 10 version 1803 and later.
- PowerShell 7 is optional. You need it only for `--pwsh`.

You do not need administrator rights.

## Install

1. Open CMD.
2. Copy this command, paste it in CMD and press Enter:

```cmd
curl.exe -fsSL https://raw.githubusercontent.com/SKABDULAHMED8/Watch-Task-Monitor-PS-CMD/main/install.cmd -o "%TEMP%\wtm-install.cmd" && "%TEMP%\wtm-install.cmd"
```

3. Close CMD.
4. Open a new CMD window.
5. Do the check in the next section.

The installer puts the files in `%LOCALAPPDATA%\WatchTaskMonitor`. It adds this folder to your user PATH. It does not change the system PATH.

**Note:** Read `install.cmd` and `install.ps1` before you run them. The installer runs with `-ExecutionPolicy Bypass` for this one run only. It does not change your execution policy setting.

### Install from a download

1. Download this repository as a ZIP file from GitHub.
2. Extract the ZIP file.
3. Open CMD in the extracted folder.
4. Run `install.cmd`.

## Check the install

Run this command in a new CMD window:

```cmd
watch --version
```

CMD shows the version number. If CMD shows `'watch' is not recognized`, see the Troubleshooting section.

## Use

### Run a CMD command

```cmd
watch ping 127.0.0.1 -n 4
watch dir C:\Windows
```

### Run a PowerShell command

Use `--ps` for Windows PowerShell 5.1. Use `--pwsh` for PowerShell 7.

```cmd
watch --ps "Get-Process | Select-Object -First 3"
watch --pwsh "Get-Date"
```

### Use quotes

Put the full command in one pair of quotes when it has `&`, `|`, `<`, `>` or `^`. If you do not use quotes, CMD splits the command at these characters. CMD then runs the second part by itself.

```cmd
watch "echo first & echo second"
```

### Other commands

| Command | What it does |
|---|---|
| `watch --log` | Shows the last 20 lines of the log file. |
| `watch --version` | Shows the version number. |
| `watch --help` | Shows the help text. |

## What you see

Your times and folders are different. This is an example:

```text
====================================
WATCH TASK MONITOR
Command: ping 127.0.0.1 -n 2
Shell: cmd
Started: 2026-11-13 14:30:05
Status: RUNNING
====================================

(the output of your command)

====================================
Status: SUCCESS
Elapsed: 00:00:01.052
Exit code: 0
====================================
Log: C:\Users\YourName\AppData\Local\WatchTaskMonitor\logs\commands.log
```

## Exit codes

`watch` returns the exit code of your command.

- `0` means the command was successful.
- A number that is not `0` usually means an error.

You can use the exit code in a batch file:

```cmd
watch ping 127.0.0.1 -n 2
if errorlevel 1 echo The command failed.
```

For `--ps` and `--pwsh`, the exit code is `0` when the last step is successful. It is the exit code of the program when the last step is a program that fails. In all other failure cases, it is `1`.

**Note:** An exit code of `0` does not prove that all work is done. Some programs start a background task and then stop. `watch` measures only the program that it starts.

## The log file

The log file is here:

```text
%LOCALAPPDATA%\WatchTaskMonitor\logs\commands.log
```

Each command adds one line. A line has these parts, separated by ` | `:

```text
start time | end time | status | elapsed time | exit code | shell | command
```

This is an example:

```text
2026-11-13T14:30:05 | 2026-11-13T14:30:06 | SUCCESS | 00:00:01.052 | Exit=0 | Shell=cmd | ping 127.0.0.1 -n 2
```

**Warning:** The log file stores the text of each command. Do not put passwords, tokens or API keys in a command.

The program does not delete or shorten the log file. Delete old lines by hand when the file is too large.

## Repair

Use Repair when `watch` does not work. Repair removes the program files and installs new files. Your logs stay.

```cmd
curl.exe -fsSL https://raw.githubusercontent.com/SKABDULAHMED8/Watch-Task-Monitor-PS-CMD/main/install.cmd -o "%TEMP%\wtm-install.cmd" && "%TEMP%\wtm-install.cmd" repair
```

If you have the repository on your PC, run `install.cmd repair` in its folder.

If you run the install command again, the installer shows `already installed` and changes nothing.

## Uninstall

Run this command:

```cmd
watch-uninstall
```

This removes the program files and the PATH entry. Your logs stay in `%LOCALAPPDATA%\WatchTaskMonitor\logs`.

To remove the logs also, run:

```cmd
watch-uninstall /logs
```

## Where the files are

| What | Where |
|---|---|
| Program files and logs | `%LOCALAPPDATA%\WatchTaskMonitor` |
| PATH entry | Your user PATH. The entry is `%LOCALAPPDATA%\WatchTaskMonitor`. |

`%LOCALAPPDATA%` is usually `C:\Users\YourName\AppData\Local`. Many Windows programs keep their data in this folder.

### Advanced: change the data folder

Set the variable `WATCH_TASK_MONITOR_HOME` to a folder path. `watch` then writes its log in the `logs` folder inside that folder.

## Limits

- `watch` monitors only the commands that you start with `watch`. It does not monitor other commands in Windows.
- It cannot show a progress percentage or a time remaining. A generic wrapper does not know how much work is left. Some programs show their own progress, for example `robocopy`.
- The elapsed time includes the time to start the shell.
- If you press Ctrl+C, `watch` tries to write a log line with the status `INTERRUPTED`.

## Troubleshooting

### `'watch' is not recognized`

1. Close all CMD windows.
2. Open a new CMD window.
3. Run `where watch`.

If `where watch` shows no result, run the installer again with `repair`. A CMD window that was open during the install does not have the new PATH.

### PowerShell says that scripts are disabled

`watch.cmd` starts PowerShell with `-ExecutionPolicy RemoteSigned`. Your PC can have a policy from your organization that blocks this. Run `Get-ExecutionPolicy -List` in PowerShell to see the policies. Ask your administrator before you change a policy.

### `--pwsh` shows an error

`--pwsh` needs PowerShell 7. Install PowerShell 7 or use `--ps`.

### A command with `&` runs in two parts

Put the full command in one pair of quotes. See the section Use quotes.

## Run the tests

The tests do not change your real PATH or your real AppData folder.

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

The tests also run on GitHub for each push. The workflow is in `.github/workflows/tests.yml`.

## Related article

This tool started as a tutorial. The article shows how to build a basic version step by step:

[How to Monitor CMD and PowerShell Commands on Windows: Execution Time, Logs & Exit Codes](https://amas-tech-blog.hashnode.dev/how-to-monitor-cmd-and-powershell-commands-on-windows-execution-time-logs-exit-codes)

The version in this repository is newer. It returns the exit code of your command, runs PowerShell commands, and has an installer.

## Licence

MIT. See the file `LICENSE`.
