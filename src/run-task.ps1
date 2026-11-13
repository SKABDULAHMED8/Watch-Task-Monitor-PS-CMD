# Watch Task Monitor - run-task.ps1
# Runs one command, shows the result, writes one log line,
# and returns the exit code of the command.
# Works in Windows PowerShell 5.1 and PowerShell 7.
# Normal use: start it with the "watch" command (watch.cmd). Do not call it by hand.

$Version = '1.0.0'

$DataDir = $env:WATCH_TASK_MONITOR_HOME
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $env:LOCALAPPDATA 'WatchTaskMonitor'
}
$LogDir  = Join-Path $DataDir 'logs'
$LogFile = Join-Path $LogDir 'commands.log'

function Show-Usage {
    Write-Host "Watch Task Monitor $Version"
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  watch <command>            Run a CMD command'
    Write-Host '  watch --ps <command>       Run a Windows PowerShell command'
    Write-Host '  watch --pwsh <command>     Run a PowerShell 7 command'
    Write-Host '  watch --log                Show the last 20 log lines'
    Write-Host '  watch --version            Show the version'
    Write-Host '  watch --help               Show this help'
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host '  watch ping 127.0.0.1 -n 4'
    Write-Host '  watch "echo one & echo two"'
    Write-Host '  watch --ps "Get-Process | Select-Object -First 3"'
    Write-Host ''
    Write-Host "Log file: $LogFile"
}

function ConvertTo-CommandText {
    # Puts the arguments back together as one command line.
    param([string[]]$Parts)
    if ($Parts.Count -eq 1) {
        $one = $Parts[0]
        # One argument that is a program path with spaces: keep it in quotes.
        if ($one -match '\s') {
            $isFile = $false
            try { $isFile = Test-Path -LiteralPath $one -PathType Leaf } catch { $isFile = $false }
            if ($isFile) { return '"' + $one + '"' }
        }
        return $one
    }
    $out = foreach ($p in $Parts) {
        if ($p -match '\s' -and $p -notmatch '^".*"$') { '"' + $p + '"' } else { $p }
    }
    return ($out -join ' ')
}

function Start-WatchedProcess {
    # Starts the command and waits for it. Returns the exit code.
    param([string]$ShellName, [string]$Text)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false

    if ($ShellName -eq 'cmd') {
        $psi.FileName = $env:ComSpec
        # /s keeps the quotes inside the command. The outer pair is removed by cmd.
        $psi.Arguments = '/d /s /c "' + $Text + '"'
    }
    else {
        if ($ShellName -eq 'pwsh') {
            $found = Get-Command pwsh -ErrorAction SilentlyContinue
            if (-not $found) { throw 'PowerShell 7 (pwsh) is not installed. Use --ps for Windows PowerShell.' }
            $psi.FileName = $found.Source
        }
        else {
            $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (Test-Path -LiteralPath $winPs) { $psi.FileName = $winPs } else { $psi.FileName = 'powershell.exe' }
        }
        # The command goes in as encoded text, so quotes and pipes cannot break it.
        # "$?" tells us if the last step failed. Then we pick the exit code.
        $lines = @(
            '$global:LASTEXITCODE = 0',
            $Text,
            '$wtmOk = $?',
            '$wtmCode = $LASTEXITCODE',
            'if ($wtmOk) { exit 0 }',
            'if ($wtmCode) { exit $wtmCode }',
            'exit 1'
        )
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($lines -join "`n")))
        $psi.Arguments = '-NoProfile -ExecutionPolicy RemoteSigned -EncodedCommand ' + $encoded
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Write-LogLine {
    param([string]$Line)
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Line + "`r`n")
        for ($i = 0; $i -lt 10; $i++) {
            try {
                $fs = New-Object System.IO.FileStream($LogFile, [System.IO.FileMode]::Append,
                    [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
                return $true
            }
            catch [System.IO.IOException] { Start-Sleep -Milliseconds 50 }
        }
    }
    catch { }
    return $false
}

# ---------- read the arguments ----------

$rest = @($args)

if ($rest.Count -eq 0) { Show-Usage; exit 1 }

$first = [string]$rest[0]
switch ($first) {
    { $_ -in '--help', '-h', '/?' } { Show-Usage; exit 0 }
    '--version' { Write-Host "Watch Task Monitor $Version"; exit 0 }
    '--log' {
        if (Test-Path -LiteralPath $LogFile) { Get-Content -LiteralPath $LogFile -Tail 20 -Encoding UTF8 }
        else { Write-Host 'No log yet.' }
        exit 0
    }
}

$shellName = 'cmd'
if ($first -eq '--ps')   { $shellName = 'powershell'; $rest = @($rest | Select-Object -Skip 1) }
if ($first -eq '--pwsh') { $shellName = 'pwsh';       $rest = @($rest | Select-Object -Skip 1) }

if ($rest.Count -eq 0) { Show-Usage; exit 1 }

$commandText = ConvertTo-CommandText -Parts ([string[]]$rest)
$logText = ($commandText -replace '[\r\n]+', ' ')

# ---------- run and measure ----------

$started = Get-Date
$sw      = [System.Diagnostics.Stopwatch]::StartNew()
$code    = 1
$done    = $false

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host 'WATCH TASK MONITOR' -ForegroundColor Cyan
Write-Host "Command: $commandText"
Write-Host "Shell: $shellName"
Write-Host ("Started: " + $started.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Host 'Status: RUNNING' -ForegroundColor Yellow
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''

try {
    $code = Start-WatchedProcess -ShellName $shellName -Text $commandText
    $done = $true
}
catch {
    Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
    $code = 1
    $done = $true
}
finally {
    $sw.Stop()
    $ended = Get-Date

    if (-not $done)      { $status = 'INTERRUPTED'; $code = 130; $color = 'Yellow' }
    elseif ($code -eq 0) { $status = 'SUCCESS';     $color = 'Green' }
    else                 { $status = 'FAILED';      $color = 'Red' }

    $e = $sw.Elapsed
    $elapsed = '{0:00}:{1:00}:{2:00}.{3:000}' -f [int][math]::Floor($e.TotalHours), $e.Minutes, $e.Seconds, $e.Milliseconds

    Write-Host ''
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host "Status: $status" -ForegroundColor $color
    Write-Host "Elapsed: $elapsed"
    Write-Host "Exit code: $code"
    Write-Host '====================================' -ForegroundColor Cyan

    $line = '{0} | {1} | {2} | {3} | Exit={4} | Shell={5} | {6}' -f `
        $started.ToString('yyyy-MM-ddTHH:mm:ss'), $ended.ToString('yyyy-MM-ddTHH:mm:ss'),
        $status, $elapsed, $code, $shellName, $logText
    if (Write-LogLine -Line $line) { Write-Host "Log: $LogFile" }
    else { Write-Host "Warning: could not write the log file $LogFile" -ForegroundColor Yellow }
}

exit $code
