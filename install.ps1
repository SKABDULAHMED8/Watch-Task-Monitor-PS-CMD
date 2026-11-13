# Watch Task Monitor - install.ps1
# Installs, repairs or removes Watch Task Monitor for the current user.
# No administrator rights are needed.
#
#   Install   Copy the files to %LOCALAPPDATA%\WatchTaskMonitor and add that folder to your PATH.
#   Repair    Remove the program files and copy fresh ones. Your logs stay.
#   Uninstall Remove the program files and the PATH entry. Your logs stay unless you use -RemoveLogs.
#
# Normal use: run install.cmd. It calls this script.
# -PathStoreFile is for the tests only. It keeps the PATH value in a file instead of the registry.

param(
    [ValidateSet('Install', 'Repair', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WatchTaskMonitor'),
    [string]$SourceDir = $PSScriptRoot,
    [string]$PathStoreFile,
    [switch]$RemoveLogs
)

$ErrorActionPreference = 'Stop'

$DefaultDir   = Join-Path $env:LOCALAPPDATA 'WatchTaskMonitor'
$ProgramFiles = @('run-task.ps1', 'watch.cmd', 'watch-uninstall.cmd', 'install.ps1')

# ---------- PATH helpers ----------

function Get-UserPath {
    if ($PathStoreFile) {
        if (Test-Path -LiteralPath $PathStoreFile) { return (Get-Content -LiteralPath $PathStoreFile -Raw).Trim() }
        return ''
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    try {
        return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    finally { $key.Close() }
}

function Set-UserPath([string]$Value) {
    if ($PathStoreFile) {
        [System.IO.File]::WriteAllText($PathStoreFile, $Value)
        return
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        # ExpandString keeps entries like %USERPROFILE%\bin working.
        $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    finally { $key.Close() }
    Send-EnvironmentChange
}

function Send-EnvironmentChange {
    # Tells Windows that the environment changed, so new windows get the new PATH.
    try {
        Add-Type -Namespace WatchTaskMonitor -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
        $result = [UIntPtr]::Zero
        [WatchTaskMonitor.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero,
            'Environment', 2, 5000, [ref]$result) | Out-Null
    }
    catch { }
}

function ConvertTo-PathKey([string]$Entry) {
    [Environment]::ExpandEnvironmentVariables($Entry.Trim()).TrimEnd('\').ToLowerInvariant()
}

function Test-InPath([string]$PathValue, [string]$Dir) {
    $want = ConvertTo-PathKey $Dir
    foreach ($e in $PathValue.Split(';')) {
        if ($e.Trim() -and (ConvertTo-PathKey $e) -eq $want) { return $true }
    }
    return $false
}

function Add-ToUserPath([string]$Dir) {
    $current = Get-UserPath
    if (Test-InPath $current $Dir) { return $false }
    # Use %LOCALAPPDATA% in the default case. The entry then follows a moved profile.
    $entry = $Dir
    if ((ConvertTo-PathKey $Dir) -eq (ConvertTo-PathKey $DefaultDir)) { $entry = '%LOCALAPPDATA%\WatchTaskMonitor' }
    $parts = @($current.Split(';') | Where-Object { $_.Trim() })
    $parts += $entry
    Set-UserPath ($parts -join ';')
    return $true
}

function Remove-FromUserPath([string]$Dir) {
    $current = Get-UserPath
    if (-not (Test-InPath $current $Dir)) { return $false }
    $want = ConvertTo-PathKey $Dir
    $parts = @($current.Split(';') | Where-Object { $_.Trim() -and (ConvertTo-PathKey $_) -ne $want })
    Set-UserPath ($parts -join ';')
    return $true
}

# ---------- file helpers ----------

function Test-Installed {
    (Test-Path -LiteralPath (Join-Path $InstallDir 'run-task.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $InstallDir 'watch.cmd')) -and
    (Test-InPath (Get-UserPath) $InstallDir)
}

function Remove-ProgramFiles {
    foreach ($f in $ProgramFiles) {
        $p = Join-Path $InstallDir $f
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}

function Copy-ProgramFiles {
    $srcDir = Join-Path $SourceDir 'src'
    $map = [ordered]@{
        'run-task.ps1'        = Join-Path $srcDir 'run-task.ps1'
        'watch.cmd'           = Join-Path $srcDir 'watch.cmd'
        'watch-uninstall.cmd' = Join-Path $srcDir 'watch-uninstall.cmd'
        'install.ps1'         = Join-Path $SourceDir 'install.ps1'
    }
    foreach ($name in $map.Keys) {
        if (-not (Test-Path -LiteralPath $map[$name])) {
            throw "Source file not found: $($map[$name])"
        }
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    foreach ($name in $map.Keys) {
        $dest = Join-Path $InstallDir $name
        Copy-Item -LiteralPath $map[$name] -Destination $dest -Force
        # A file from a browser download can be blocked. This clears the block.
        try { Unblock-File -LiteralPath $dest } catch { }
    }
}

# ---------- actions ----------

try {
    switch ($Action) {

        'Install' {
            if (Test-Installed) {
                Write-Host "Watch Task Monitor is already installed in:"
                Write-Host "  $InstallDir"
                Write-Host 'Nothing was changed. To install fresh files, run: install.cmd repair'
                exit 0
            }
            Copy-ProgramFiles
            Add-ToUserPath $InstallDir | Out-Null
            Write-Host 'Watch Task Monitor is installed.'
            Write-Host "  Files and logs: $InstallDir"
            Write-Host ''
            Write-Host 'Close this window and open a new CMD window. Then run:'
            Write-Host '  watch --help'
        }

        'Repair' {
            Remove-ProgramFiles
            Copy-ProgramFiles
            Add-ToUserPath $InstallDir | Out-Null
            Write-Host 'Watch Task Monitor is repaired. Fresh files are in:'
            Write-Host "  $InstallDir"
            Write-Host 'Your logs were not changed.'
            Write-Host ''
            Write-Host 'Close this window and open a new CMD window. Then run:'
            Write-Host '  watch --help'
        }

        'Uninstall' {
            # Leave the folder first, so Windows can delete it.
            try { Set-Location -LiteralPath ([IO.Path]::GetTempPath()) } catch { }
            $hadPath = Remove-FromUserPath $InstallDir
            $hadFiles = $false
            foreach ($f in $ProgramFiles) {
                if (Test-Path -LiteralPath (Join-Path $InstallDir $f)) { $hadFiles = $true }
            }
            Remove-ProgramFiles
            if ($RemoveLogs -and (Test-Path -LiteralPath $InstallDir)) {
                Remove-Item -LiteralPath $InstallDir -Recurse -Force
            }
            elseif ((Test-Path -LiteralPath $InstallDir) -and -not (Get-ChildItem -LiteralPath $InstallDir -Force)) {
                Remove-Item -LiteralPath $InstallDir -Force
            }
            if (-not $hadPath -and -not $hadFiles) {
                Write-Host 'Watch Task Monitor is not installed. Nothing was removed.'
            }
            else {
                Write-Host 'Watch Task Monitor is removed.'
                if (-not $RemoveLogs -and (Test-Path -LiteralPath $InstallDir)) {
                    Write-Host "Your logs are still in: $InstallDir"
                    Write-Host 'To remove them too, run: watch-uninstall /logs'
                }
            }
        }
    }
    exit 0
}
catch {
    Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
