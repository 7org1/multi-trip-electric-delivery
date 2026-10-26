# watchdog2.ps1 -- finish the whole sweep unattended, then shut the machine down.
#
# PHASES
#   1  wait for the running A/B/C sweep (round-robin, adaptive, linucb)
#   2  pure      -- always random removal; the zero-information control
#   3  thompson  -- linear Thompson sampling
#   4  linucb-sched -- LinUCB with the theory-driven alpha_t
#   5  merge every mode and check determinism, then shut down
#
# WHY PHASES AND NOT ONE BIG BATCH
#   Three MATLAB processes already take the machine to 4.3 GB free; six processes took
#   it to 1.1 GB and were killed by the OS.  Each phase therefore waits until the
#   previous one has released its memory before launching.
#
# SAFETY
#   Every phase is bounded by a deadline.  If any phase overruns or its files are
#   short, the script records that and does NOT shut down: waking to a machine that is
#   still on with a written log is recoverable, waking to a machine that is off with
#   half a dataset is not.

param(
    [int]$MaxWaitPhase1Min = 300,
    [int]$MaxWaitPerPhaseMin = 200
)

$ErrorActionPreference = 'Continue'
$root   = 'C:\Users\YJZT\Desktop\route'
$myalgo = Join-Path $root 'build\08_myalgo'
$res12  = Join-Path $myalgo 'results12'
$log    = Join-Path $res12 'watchdog2.log'

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date).ToString('HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line -Encoding UTF8
}

function Rows([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $n = (Get-Content $path | Measure-Object -Line).Lines
    if ($n -le 0) { return 0 }
    return [Math]::Max(0, $n - 1)
}

function CountDone([string]$mode) {
    $c = 0
    foreach ($p in 1, 2, 3) {
        if ((Rows (Join-Path $res12 "$($mode)_part$($p).csv")) -ge 20) { $c++ }
    }
    return $c
}

function WaitPhase([string]$mode, [int]$maxMin) {
    $deadline = (Get-Date).AddMinutes($maxMin)
    while ((Get-Date) -lt $deadline) {
        $d = CountDone $mode
        if ($d -ge 3) { return $d }
        if ((Get-Process matlab -ErrorAction SilentlyContinue).Count -eq 0 -and $d -lt 3) {
            Start-Sleep -Seconds 20
            $d = CountDone $mode
            if ($d -lt 3) { return $d }
            return $d
        }
        Start-Sleep -Seconds 60
    }
    return (CountDone $mode)
}

function RunPhase([string]$mode, [int]$maxMin) {
    Log "--- phase $mode : launching ---"
    foreach ($p in 1, 2, 3) {
        $arg = "cd('$myalgo'); run_12('$mode',$p)"
        Start-Process -FilePath 'matlab' -ArgumentList @('-batch', "`"$arg`"") `
            -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 8
    }
    $d = WaitPhase $mode $maxMin
    Log "--- phase $mode : $d/3 files complete ---"
    return $d
}

New-Item -ItemType Directory -Force -Path $res12 | Out-Null
Log "watchdog2 started"

# ------------------------------------------------------------------ phase 1
Log "phase 1: waiting for the A/B/C sweep"
$deadline = (Get-Date).AddMinutes($MaxWaitPhase1Min)
while ((Get-Date) -lt $deadline) {
    $done = (CountDone 'roundrobin') + (CountDone 'adaptive')
    if ($done -ge 6) { break }
    Start-Sleep -Seconds 60
}
$done = (CountDone 'roundrobin') + (CountDone 'adaptive')
Log "phase 1 finished: $done/6 files complete"

if ($done -lt 6) {
    Log "phase 1 incomplete -- NOT starting later phases, NOT shutting down"
    exit 3
}

Start-Sleep -Seconds 30
$freeGb = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
Log "free RAM after phase 1: $freeGb GB"

# ------------------------------------------------------------------ phases 2-4
$ok = @{}
foreach ($ph in @(@('linucb', $MaxWaitPerPhaseMin),
                 @('pure', $MaxWaitPerPhaseMin),
                 @('thompson', $MaxWaitPerPhaseMin),
                 @('linucb-sched', $MaxWaitPerPhaseMin))) {
    $mode = $ph[0]; $mins = [int]$ph[1]
    Get-Process matlab -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 20
    $freeGb = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    Log "free RAM before phase $mode : $freeGb GB"
    $d = RunPhase $mode $mins
    $ok[$mode] = ($d -ge 3)
    Get-Process matlab -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15
}

# ------------------------------------------------------------------ phase 5
Log "phase 5: merging and checking determinism"
& matlab -batch "cd('$myalgo'); merge_12" *>> $log

$allOk = $true
foreach ($mode in @('linucb', 'pure', 'thompson', 'linucb-sched')) {
    if (-not $ok[$mode]) { $allOk = $false }
}

if ($allOk) {
    Log "all phases complete -- shutting down in 5 minutes (run 'shutdown /a' to cancel)"
    shutdown /s /t 300 /c "overnight sweep finished, results saved in build/08_myalgo/results12"
} else {
    Log "one or more phases incomplete -- NOT shutting down, check the CSV files"
}
Log "watchdog2 done"
