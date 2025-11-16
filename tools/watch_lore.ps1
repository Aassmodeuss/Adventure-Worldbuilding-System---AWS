# watch_lore.ps1
# Watches the Lore/Lorebook directory for changes and runs update_lore_indexes.ps1 automatically with debounce.

param(
    [string]$Path = "Lore/Lorebook"
)

# Ensure a single watcher instance via named mutex (avoids duplicate tasks)
try {
    $globalName = 'Global/HotF_WatchLore'
    $script:mutex = New-Object System.Threading.Mutex($false, $globalName)
    $acquired = $script:mutex.WaitOne(0)
    if (-not $acquired) {
        Write-Host "Watcher already running (mutex: $globalName). Exiting." -ForegroundColor Yellow
        return
    }
} catch {
    Write-Warning "Mutex setup failed: $_"
}

Write-Host "Watching '$Path' for changes... Press Ctrl+C to stop." -ForegroundColor Cyan

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = (Resolve-Path $Path)
$fsw.Filter = "*.md"
$fsw.IncludeSubdirectories = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::DirectoryName
$fsw.EnableRaisingEvents = $true

$timer = New-Object System.Timers.Timer
$timer.Interval = 1500
$timer.AutoReset = $false

$script:isRunning = $false

$eventDebounce = {
    try {
        $timer.Stop(); $timer.Start()
    } catch {
        Write-Warning $_
    }
}

# When the timer elapses (no more events within Interval), run the indexer once
$onElapsed = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
    if ($script:isRunning) { return }
    $script:isRunning = $true
    try {
        $fsw.EnableRaisingEvents = $false
        & "$PSScriptRoot/update_lore_indexes.ps1"
    } catch {
        Write-Warning $_
    } finally {
        $fsw.EnableRaisingEvents = $true
        $script:isRunning = $false
    }
}

$onChange = Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $eventDebounce
$onCreate = Register-ObjectEvent -InputObject $fsw -EventName Created -Action $eventDebounce
$onDelete = Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action $eventDebounce
$onRename = Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $eventDebounce

# Debounce initial events
$timer.Start()

# Keep script alive; dispose resources and event subscriptions on termination (Ctrl+C)
try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    try {
        if ($timer) { $timer.Stop(); $timer.Dispose() }
        foreach ($sub in @($onElapsed,$onChange,$onCreate,$onDelete,$onRename)) {
            if ($sub) {
                try { Unregister-Event -SourceIdentifier $sub.SourceIdentifier -ErrorAction SilentlyContinue } catch {}
                $sub.Action = $null
            }
        }
        if ($fsw) { $fsw.EnableRaisingEvents = $false; $fsw.Dispose() }
        if ($script:mutex) { $script:mutex.ReleaseMutex() | Out-Null; $script:mutex.Dispose() }
    } catch {}
}
