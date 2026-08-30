# Stop only the processes recorded by this Boujoy Windows package instance.
# Never scan or kill by name: another local Harness/project may be running.

[CmdletBinding()]
param([string]$Root = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($Root) { $Root = $Root.Trim().TrimEnd('"') }

function Get-BoujoyStateDirectory {
    param([string]$PackageRoot)
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME "AppData\\Local" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PackageRoot.ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
    return (Join-Path $base ("Boujoy\\BoujoyHarness\\Windows\\" + $hash.Substring(0, 16)))
}

function Stop-BoujoyProcessTree {
    param(
        [int]$ProcessId,
        [Int64]$ExpectedStartTicks = 0
    )
    if ($ProcessId -le 0 -or $ExpectedStartTicks -le 0) {
        Write-Warning "Refusing to stop an unverified Boujoy process record: PID $ProcessId"
        return
    }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -eq $process) { return }
        $actualStartTicks = $process.StartTime.ToUniversalTime().Ticks
        if ($actualStartTicks -ne $ExpectedStartTicks) {
            Write-Warning "Refusing to stop PID $ProcessId because it no longer matches this Boujoy host."
            return
        }
        & taskkill.exe /PID "$ProcessId" /T /F *> $null
    } catch {
        Write-Warning ("Could not verify Boujoy PID {0}: {1}" -f $ProcessId, $_.Exception.Message)
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Boujoy package root does not exist: $Root" }
    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    $stateDirectory = Get-BoujoyStateDirectory -PackageRoot $rootPath
    $stateFile = Join-Path $stateDirectory "processes.json"
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
        Write-Output "No Boujoy Windows host is registered for this package."
        exit 0
    }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ([string]$state.root -ne $rootPath) { throw "Refusing to stop a host belonging to another package root." }
    foreach ($process in @($state.processes)) {
        Stop-BoujoyProcessTree -ProcessId ([int]$process.pid) -ExpectedStartTicks ([Int64]$process.startTicks)
    }
    if ($state.hostPid) { Stop-BoujoyProcessTree -ProcessId ([int]$state.hostPid) -ExpectedStartTicks ([Int64]$state.hostStartTicks) }
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $stateDirectory "restart.request") -Force -ErrorAction SilentlyContinue
    Write-Output "Boujoy Windows host stopped."
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
