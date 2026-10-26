# watchdog.ps1 -- finish tonight's sweep unattended, then shut the machine down.
#
# PHASES
#   1. wait for the three round-robin + adaptive jobs to finish
#         each writes 20 rows (4 instances x 5 seeds) into results12/
#   2. run three LinUCB jobs, one per part
#   3. merge everything and check determinism
#   4. shut down
#
# WHY A WATCHDOG AND NOT A SINGLE matlab CALL
#   Three MATLAB processes already hold most of the RAM (4.3 GB free with three
#   running, 1.1 GB with six).  Launching the LinUCB phase now would put six on the
#   machine at once and risk an out-of-memory kill, which would lose the night's
#   work.  This waits for the first phase to release its memory instead.
#
#   Every phase is bounded by a deadline.  If a phase overruns, the script records
#   the failure and does NOT shut down -- waking up to a machine that is off and
#   holds half a dataset is worse than waking up to one that is on.

param(
    [int]$MaxWaitPhase1Min = 300,
    [int]$MaxWaitPhase2Min = 200
)

$ErrorActionPreference = 'Stop'
$root    = 'C:\Users\YJZT\Desktop\route'
$myalgo  = Join-Path $root 'build\08_myalgo'
$res12   = Join-Path $myalgo 'results12'
$log     = Join-Path $res12 'watchdog.log'

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date).ToString('HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Output $line
}

function Rows([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $n = (Get-Content $path | Measure-Object -Line).Lines
    if ($n -le 0) { return 0 }
    return [Math]::Max(0, $n - 1)
}

New-Item -ItemType Directory -Force -Path $res12 | Out-Null
Log "watchdog started"

# ------------------------------------------------------------------ phase 1
Log "phase 1: waiting for round-robin + adaptive (expect 20 rows per file)"
$deadline = (Get-Date).AddMinutes($MaxWaitPhase1Min)
while ((Get-Date) -lt $deadline) {
    $done = 0
    foreach ($m in 'roundrobin', 'adaptive') {
        foreach ($p in 1, 2, 3) {
            $f = Join-Path $res12 "$($m)_part$($p).csv"
            if ((Rows $f) -ge 20) { $done++ }
        }
    }
    if ($done -ge 6) { break }
    if ((Get-Process matlab -ErrorAction SilentlyContinue).Count -eq 0) {
        Log "  no MATLAB running but only $done/6 files complete -- stopping, not shutting down"
        exit 2
    }
    Start-Sleep -Seconds 60
}
$done = 0
foreach ($m in 'roundrobin', 'adaptive') {
    foreach ($p in 1, 2, 3) {
        if ((Rows (Join-Path $res12 "$($m)_part$($p).csv")) -ge 20) { $done++ }
    }
}
Log "phase 1 finished: $done/6 files complete"

if ($done -lt 6) {
    Log "phase 1 incomplete -- will not start phase 2 and will not shut down"
    exit 3
}

# make sure the memory is actually back
Start-Sleep -Seconds 30
$freeGb = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
Log "free RAM before phase 2: $freeGb GB"

# ------------------------------------------------------------------ phase 2
Log "phase 2: launching LinUCB on the three parts"
$jobs = @()
foreach ($p in 1, 2, 3) {
    $arg = "cd('$myalgo'); run_12('linucb',$p)"
    $jobs += Start-Process -FilePath 'matlab' -ArgumentList @('-batch', "`"$arg`"") `
                 -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 5
}
Log "  launched $($jobs.Count) processes"

$deadline = (Get-Date).AddMinutes($MaxWaitPhase2Min)
while ((Get-Date) -lt $deadline) {
    $done2 = 0
    foreach ($p in 1, 2, 3) {
        if ((Rows (Join-Path $res12 "linucb_part$($p).csv")) -ge 20) { $done2++ }
    }
    if ($done2 -ge 3) { break }
    if ((Get-Process matlab -ErrorAction SilentlyContinue).Count -eq 0) { break }
    Start-Sleep -Seconds 60
}

$done2 = 0
foreach ($p in 1, 2, 3) {
    if ((Rows (Join-Path $res12 "linucb_part$($p).csv")) -ge 20) { $done2++ }
}
Log "phase 2 finished: $done2/3 files complete"

Get-Process matlab -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# ------------------------------------------------------------------ phase 3
Log "phase 3: merging and checking determinism"
& matlab -batch "cd('$myalgo'); merge_12" *>> $log

# ------------------------------------------------------------------ phase 4
if ($done2 -ge 3) {
    Log "all three schedulers complete -- shutting down in 5 minutes (shutdown /a to cancel)"
    shutdown /s /t 300 /c "LinUCB sweep finished, results saved"
} else {
    Log "LinUCB incomplete ($done2/3) -- NOT shutting down, check the results"
}
Log "watchdog done"
