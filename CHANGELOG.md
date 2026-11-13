# Changelog

## 1.0.0 - 2026-11-13

First release of this repository. It is based on the tool in the blog article.

Changed from the article version:
- `watch` now returns the exit code of your command. Before, it always returned 0.
- New `--ps` and `--pwsh` options run PowerShell commands.
- Commands with quotes and `&` run correctly.
- The log line now has the start time, the end time, the shell and the exit code.
- The log file uses UTF-8 and is safe when two commands write at the same time.
- New installer. It puts the files in `%LOCALAPPDATA%\WatchTaskMonitor` and adds that folder to the user PATH. No administrator rights are needed.
- New `install.cmd repair` and `watch-uninstall` commands.
- New commands `watch --help`, `watch --version` and `watch --log`.
- Tests and a GitHub Actions workflow for Windows.
