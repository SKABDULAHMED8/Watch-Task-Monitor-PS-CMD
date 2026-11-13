# Watch Task Monitor - tests
# No extra modules needed. Works in Windows PowerShell 5.1 and PowerShell 7.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
# The tests do not touch your real PATH or your real AppData folder.

$ErrorActionPreference = 'Stop'

$Root      = Split-Path -Parent $PSScriptRoot
$Watch     = Join-Path $Root 'src\watch.cmd'
$Installer = Join-Path $Root 'install.ps1'
$Sandbox   = Join-Path ([IO.Path]::GetTempPath()) ('wtm-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Sandbox -Force | Out-Null

$script:Passed  = 0
$script:Failed  = 0
$script:Skipped = 0
$script:Counter = 0

# ---------- helpers ----------

function Invoke-Raw {
    # Runs a program with a raw argument string. Returns Output, Error and ExitCode.
    param([string]$File, [string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Output = $out; Error = $errTask.Result; ExitCode = $p.ExitCode }
}

function New-TestHome {
    $script:Counter++
    $dir = Join-Path $Sandbox ('home' + $script:Counter)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dir
}

function Invoke-Watch {
    # $ArgLine is typed exactly as a user would type it after the word "watch".
    param([string]$ArgLine, [string]$WatchPath = $Watch)
    Invoke-Raw $env:ComSpec ('/d /s /c ""' + $WatchPath + '" ' + $ArgLine + '"')
}

function Get-LogLines($home_) {
    $log = Join-Path $home_ 'logs\commands.log'
    if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log -Encoding UTF8) } else { @() }
}

function Invoke-Installer {
    param([string]$Action = 'Install', [string]$InstallDir, [string]$PathFile, [switch]$RemoveLogs)
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $Installer + '" -Action ' + $Action +
         ' -InstallDir "' + $InstallDir + '" -PathStoreFile "' + $PathFile + '" -SourceDir "' + $Root + '"'
    if ($RemoveLogs) { $a += ' -RemoveLogs' }
    $exe = (Get-Process -Id $PID).Path
    Invoke-Raw $exe $a
}

function Assert-True($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } }
function Assert-Equal($actual, $expected, $msg) {
    if ($actual -ne $expected) { throw "FAIL: $msg`n  expected: $expected`n  actual:   $actual" }
}
function Assert-Match($text, $pattern, $msg) {
    if ($text -notmatch $pattern) { throw "FAIL: $msg`n  pattern: $pattern`n  text:    $text" }
}
function Assert-NotMatch($text, $pattern, $msg) {
    if ($text -match $pattern) { throw "FAIL: $msg`n  pattern: $pattern`n  text:    $text" }
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body, [scriptblock]$SkipIf)
    if ($SkipIf -and (& $SkipIf)) {
        $script:Skipped++
        Write-Host "SKIP  $Name" -ForegroundColor Yellow
        return
    }
    $saved = @{ H = $env:WATCH_TASK_MONITOR_HOME; L = $env:LOCALAPPDATA }
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failed++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host ("      " + ($_.Exception.Message -replace "`n", "`n      ")) -ForegroundColor Red
    }
    finally {
        $env:WATCH_TASK_MONITOR_HOME = $saved.H
        $env:LOCALAPPDATA = $saved.L
    }
}

$NoPwsh = { -not (Get-Command pwsh -ErrorAction SilentlyContinue) }

# ---------- watch: exit codes ----------

Test-Case 'watch returns 0 and prints SUCCESS for a good command' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch 'echo hello'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'hello' 'command output is shown'
    Assert-Match $r.Output 'Status: SUCCESS' 'status line'
}

Test-Case 'watch returns the exit code of the command (exit /b 3 gives 3)' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch 'exit /b 3'
    Assert-Equal $r.ExitCode 3 'exit code'
    Assert-Match $r.Output 'Status: FAILED' 'status line'
    Assert-Match $r.Output 'Exit code: 3' 'exit code line'
}

Test-Case 'a failed command is written to the log as FAILED with its exit code' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'exit /b 5' | Out-Null
    $lines = Get-LogLines $h
    Assert-Equal $lines.Count 1 'one log line'
    Assert-Match $lines[0] '\| FAILED \|' 'status in log'
    Assert-Match $lines[0] 'Exit=5' 'exit code in log'
}

# ---------- watch: quoting ----------

Test-Case 'one quoted command with & inside runs as one command' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '"echo first & echo second"'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output '(?m)^first\s*$' 'first echo'
    Assert-Match $r.Output '(?m)^second\s*$' 'second echo'
}

Test-Case 'an argument with spaces keeps its quotes (echo "two words")' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch 'echo "two words"'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'two words' 'text is shown'
}

Test-Case 'a program path that has spaces works when it is the only argument' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $dir = Join-Path $Sandbox 'folder with spaces'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $bat = Join-Path $dir 'seven.cmd'
    Set-Content -LiteralPath $bat -Value '@exit /b 7' -Encoding ASCII
    $r = Invoke-Watch ('"' + $bat + '"')
    Assert-Equal $r.ExitCode 7 'exit code'
}

# ---------- watch: PowerShell mode ----------

Test-Case '--ps runs a PowerShell command and logs Shell=powershell' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--ps "Get-Date"'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match ((Get-LogLines $h)[0]) 'Shell=powershell' 'shell in log'
}

Test-Case '--ps returns 1 when a cmdlet fails' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--ps "Get-Item C:\no\such\path"'
    Assert-Equal $r.ExitCode 1 'exit code'
    Assert-Match ((Get-LogLines $h)[0]) '\| FAILED \|' 'status in log'
}

Test-Case '--ps returns the exit code of a native program' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--ps "cmd /c exit 4"'
    Assert-Equal $r.ExitCode 4 'exit code'
}

Test-Case '--ps handles quotes and pipes' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--ps "''a b'', ''c'' | ForEach-Object { $_.ToUpper() }"'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'A B' 'first item'
    Assert-Match $r.Output '(?m)^C\s*$' 'second item'
}

Test-Case '--pwsh runs a command in PowerShell 7' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--pwsh "Get-Date"'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match ((Get-LogLines $h)[0]) 'Shell=pwsh' 'shell in log'
} $NoPwsh

# ---------- watch: help, version, log ----------

Test-Case 'no arguments prints usage and returns 1' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch ''
    Assert-Equal $r.ExitCode 1 'exit code'
    Assert-Match ($r.Output + $r.Error) 'Usage' 'usage text'
}

Test-Case '--help prints usage and returns 0' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--help'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'Usage' 'usage text'
}

Test-Case '--version prints a version number' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    $r = Invoke-Watch '--version'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output '\d+\.\d+\.\d+' 'version'
}

Test-Case '--log shows earlier entries' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'echo marker-one' | Out-Null
    $r = Invoke-Watch '--log'
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'echo marker-one' 'old entry'
}

# ---------- watch: log file ----------

Test-Case 'log line has start time, end time, status, elapsed time, exit code, shell and command' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'echo hi' | Out-Null
    $lines = Get-LogLines $h
    Assert-Equal $lines.Count 1 'one log line'
    $pattern = '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d \| \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d \| SUCCESS \| \d+:\d\d:\d\d\.\d{3} \| Exit=0 \| Shell=cmd \| echo hi$'
    Assert-Match $lines[0] $pattern 'log line format'
}

Test-Case 'every run adds one log line' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'echo one' | Out-Null
    Invoke-Watch 'echo two' | Out-Null
    Assert-Equal (Get-LogLines $h).Count 2 'two log lines'
}

Test-Case 'log file is UTF-8 without a byte order mark' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'echo hi' | Out-Null
    $bytes = [IO.File]::ReadAllBytes((Join-Path $h 'logs\commands.log'))
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True (-not $hasBom) 'file starts with a BOM'
}

Test-Case 'elapsed time is measured (ping -n 2 takes about 1 second)' {
    $h = New-TestHome; $env:WATCH_TASK_MONITOR_HOME = $h
    Invoke-Watch 'ping 127.0.0.1 -n 2' | Out-Null
    $line = (Get-LogLines $h)[0]
    Assert-Match $line '\| 00:00:0[1-9]\.\d{3} \|' 'elapsed is at least 1 second'
}

Test-Case 'default data folder is LOCALAPPDATA\WatchTaskMonitor' {
    $fake = New-TestHome
    $env:WATCH_TASK_MONITOR_HOME = $null
    $env:LOCALAPPDATA = $fake
    Invoke-Watch 'echo hi' | Out-Null
    Assert-True (Test-Path (Join-Path $fake 'WatchTaskMonitor\logs\commands.log')) 'log is under LOCALAPPDATA'
}

# ---------- installer ----------

Test-Case 'install copies the program files and adds one PATH entry' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path1.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing;D:\Other' -Encoding ASCII
    $r = Invoke-Installer -InstallDir $dir -PathFile $pathFile
    Assert-Equal $r.ExitCode 0 ('installer exit code. Output: ' + $r.Output + $r.Error)
    foreach ($f in 'run-task.ps1', 'watch.cmd', 'watch-uninstall.cmd', 'install.ps1') {
        Assert-True (Test-Path (Join-Path $dir $f)) "$f is installed"
    }
    $path = (Get-Content -LiteralPath $pathFile -Raw).Trim()
    Assert-Match $path 'C:\\Existing' 'old entry kept'
    Assert-Match $path 'D:\\Other' 'old entry kept'
    $count = @($path.Split(';') | Where-Object { $_.TrimEnd('\') -ieq $dir.TrimEnd('\') }).Count
    Assert-Equal $count 1 'install folder is in PATH once'
}

Test-Case 'the installed watch command works' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path2.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing' -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    $env:WATCH_TASK_MONITOR_HOME = $dir
    $r = Invoke-Watch 'echo installed-ok' (Join-Path $dir 'watch.cmd')
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'installed-ok' 'output'
}

Test-Case 'a second install says "already installed" and changes nothing' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path3.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing' -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    Add-Content -LiteralPath (Join-Path $dir 'run-task.ps1') -Value '# my-marker'
    $before = Get-Content -LiteralPath $pathFile -Raw
    $r = Invoke-Installer -InstallDir $dir -PathFile $pathFile
    Assert-Equal $r.ExitCode 0 'exit code'
    Assert-Match $r.Output 'already installed' 'message'
    Assert-Match (Get-Content -LiteralPath (Join-Path $dir 'run-task.ps1') -Raw) 'my-marker' 'file was not replaced'
    Assert-Equal (Get-Content -LiteralPath $pathFile -Raw) $before 'PATH is unchanged'
}

Test-Case 'an existing PATH entry with a trailing slash or other letter case is not added again' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path4.txt'
    Set-Content -LiteralPath $pathFile -Value ('C:\Existing;' + $dir.ToUpper() + '\') -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    $parts = @((Get-Content -LiteralPath $pathFile -Raw).Trim().Split(';') | Where-Object { $_ })
    Assert-Equal $parts.Count 2 'PATH still has two entries'
}

Test-Case 'repair installs fresh files, keeps the logs and does not duplicate PATH' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path5.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing' -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    Add-Content -LiteralPath (Join-Path $dir 'run-task.ps1') -Value '# my-marker'
    New-Item -ItemType Directory -Path (Join-Path $dir 'logs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'logs\commands.log') -Value 'keep me' -Encoding ASCII
    $r = Invoke-Installer -Action Repair -InstallDir $dir -PathFile $pathFile
    Assert-Equal $r.ExitCode 0 ('exit code. Output: ' + $r.Output + $r.Error)
    Assert-NotMatch (Get-Content -LiteralPath (Join-Path $dir 'run-task.ps1') -Raw) 'my-marker' 'file was replaced'
    Assert-Match (Get-Content -LiteralPath (Join-Path $dir 'logs\commands.log') -Raw) 'keep me' 'log kept'
    $parts = @((Get-Content -LiteralPath $pathFile -Raw).Trim().Split(';') | Where-Object { $_ })
    Assert-Equal $parts.Count 2 'PATH has two entries'
}

Test-Case 'uninstall removes the program files and the PATH entry but keeps the logs' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path6.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing;D:\Other' -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir 'logs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'logs\commands.log') -Value 'keep me' -Encoding ASCII
    $r = Invoke-Installer -Action Uninstall -InstallDir $dir -PathFile $pathFile
    Assert-Equal $r.ExitCode 0 ('exit code. Output: ' + $r.Output + $r.Error)
    Assert-True (-not (Test-Path (Join-Path $dir 'watch.cmd'))) 'watch.cmd removed'
    Assert-True (-not (Test-Path (Join-Path $dir 'run-task.ps1'))) 'run-task.ps1 removed'
    Assert-True (Test-Path (Join-Path $dir 'logs\commands.log')) 'log kept'
    $path = (Get-Content -LiteralPath $pathFile -Raw).Trim()
    Assert-Equal $path 'C:\Existing;D:\Other' 'PATH is back to the old value'
}

Test-Case 'uninstall -RemoveLogs removes the whole folder' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path7.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing' -Encoding ASCII
    Invoke-Installer -InstallDir $dir -PathFile $pathFile | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir 'logs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'logs\commands.log') -Value 'x' -Encoding ASCII
    Invoke-Installer -Action Uninstall -InstallDir $dir -PathFile $pathFile -RemoveLogs | Out-Null
    Assert-True (-not (Test-Path $dir)) 'folder removed'
}

Test-Case 'uninstall when nothing is installed does not fail' {
    $dir = Join-Path (New-TestHome) 'WatchTaskMonitor'
    $pathFile = Join-Path $Sandbox 'path8.txt'
    Set-Content -LiteralPath $pathFile -Value 'C:\Existing' -Encoding ASCII
    $r = Invoke-Installer -Action Uninstall -InstallDir $dir -PathFile $pathFile
    Assert-Equal $r.ExitCode 0 'exit code'
}

# ---------- summary ----------

Remove-Item -LiteralPath $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}  Skipped: {2}" -f $script:Passed, $script:Failed, $script:Skipped)
if ($script:Failed -gt 0) { exit 1 }
exit 0
