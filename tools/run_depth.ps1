# One command for the whole depth measurement (docs/depth-tools-spec.md).
#
#   powershell -File tools/run_depth.ps1            # full run
#   powershell -File tools/run_depth.ps1 -Quick     # smoke run (~2 min)
#   powershell -File tools/run_depth.ps1 -Levels L3,L4
#
# One long-lived Godot process PER LEVEL, all launched at once, then a merge
# pass that writes docs/depth-report.md and scripts/v3/discovered3.gd.
#
# Sharding is per LEVEL, not per candidate, for two reasons:
#   * Godot startup is 375 ms, ~4x one simulation run - a process per
#     candidate would be pure overhead (docs/sim-search-feasibility.md §4);
#   * Grid3's maze lives in STATICS, so one process can only hold one level's
#     geometry at a time (§3). Levels are the natural shard boundary.
# Measured sweet spot on an 8-core box is 8 processes; we have 5 levels.
#
# RUNNER HYGIENE (added after the 2026-08-12 failure, where five shards each
# wrote a 65 MB log of engine errors and none of them ever produced its JSON):
#   * every shard is watched, and KILLED the moment its output passes
#     -MaxLogMB / -MaxLogLines, with a clear message instead of a silent flood;
#   * the summary reports each shard's exit code AND whether it actually wrote
#     a fresh tools/out/depth_<ID>.json - "the process exited 0" is not the
#     same thing as "the shard produced a result".

param(
	[switch]$Quick,
	[string]$Levels = "",
	[int]$MaxLogMB = 8,
	[int]$MaxLogLines = 5000,
	[int]$MaxAttempts = 40,
	[string]$Godot = "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

if ($Levels -eq "") { $ids = @("L1", "L2", "L3", "L4", "W-1", "W-2", "W-3", "X-1") }
else { $ids = $Levels.Split(",") | ForEach-Object { $_.Trim() } }

$quickFlag = @()
if ($Quick) { $quickFlag = @("--quick") }

New-Item -ItemType Directory -Force -Path "tools\out" | Out-Null
New-Item -ItemType Directory -Force -Path "tools\out\log" | Out-Null

$t0 = Get-Date
$killBytes = $MaxLogMB * 1MB
Write-Host ("launching {0} shard(s): {1}" -f $ids.Count, ($ids -join ", "))
Write-Host ("watchdog: a shard is killed if its logs pass {0} MB or {1} lines" -f $MaxLogMB, $MaxLogLines)

function Get-LogBytes($s) {
	$n = 0
	foreach ($f in @($s.Log, $s.Err)) {
		if (Test-Path $f) { $n += (Get-Item $f).Length }
	}
	return $n
}

function Start-Shard($s) {
	$a = @("--headless", "--path", ".", "--script", "tools/run_depth.gd", "--",
			"--levels", $s.Id) + $script:quickFlag
	$s.Attempts++
	# Start-Process truncates the redirect targets, so each attempt's log
	# replaces the last one's - which is what you want to read anyway.
	$p = Start-Process -FilePath $script:Godot -ArgumentList $a -NoNewWindow -PassThru `
			-RedirectStandardOutput $s.Log -RedirectStandardError $s.Err
	$null = $p.Handle # cache the handle, or WaitForExit() returns immediately
	$s.Proc = $p
}

$shards = @()
foreach ($id in $ids) {
	$log = Join-Path $root "tools\out\log\$id.log"
	$err = "$log.err"
	if (Test-Path $log) { Remove-Item $log -Force }
	if (Test-Path $err) { Remove-Item $err -Force }
	$s = [pscustomobject]@{
		Id = $id; Proc = $null; Log = $log; Err = $err
		Json = Join-Path $root "tools\out\depth_$id.json"
		Aborted = $false; Attempts = 0; Done = $false
	}
	Start-Shard $s
	$shards += $s
}

# Poll rather than Wait-Process/WaitForExit: both have returned early here on
# redirected child processes, which silently truncates the slowest shard.
#
# RESTART ON DEATH. On this machine long-lived headless processes get killed
# from outside at unpredictable times (no crash record, no stderr, exit -1),
# which is fatal to a 20-minute search. The shard is resumable — it memoises
# every completed run to tools/out/runcache_<ID>.json and replays the identical
# deterministic trajectory on restart — so the supervisor simply relaunches any
# shard that dies without having written its result, and the search creeps
# forward across attempts. A shard that keeps dying WITHOUT making progress
# (no growth in its cache file) is given up on rather than restarted forever.
while ($true) {
	$pending = @($shards | Where-Object { -not $_.Done })
	if ($pending.Count -eq 0) { break }
	foreach ($s in $pending) {
		if (-not $s.Proc.HasExited) { continue }
		if ($s.Aborted) { $s.Done = $true; continue }
		if ($s.Proc.ExitCode -eq 0 -and (Test-Path $s.Json)) { $s.Done = $true; continue }
		if ($s.Attempts -ge $MaxAttempts) {
			Write-Warning ("shard {0} giving up after {1} attempts (last exit {2})" -f `
					$s.Id, $s.Attempts, $s.Proc.ExitCode)
			$s.Done = $true
			continue
		}
		Write-Host ("  shard {0} exited {1} without a result - relaunching (attempt {2})" -f `
				$s.Id, $s.Proc.ExitCode, ($s.Attempts + 1))
		Start-Shard $s
	}
	$alive = @($shards | Where-Object { -not $_.Done -and -not $_.Proc.HasExited })
	foreach ($s in $alive) {
		$bytes = Get-LogBytes $s
		if ($bytes -le $killBytes) { continue }
		# Only pay for a line count once the size alone looks wrong.
		$lines = 0
		foreach ($f in @($s.Log, $s.Err)) {
			if (Test-Path $f) { $lines += (Get-Content $f -ReadCount 0 | Measure-Object -Line).Lines }
		}
		if ($lines -lt $MaxLogLines) { continue }
		Write-Warning ("shard {0} ABORTED: {1:N1} MB / {2} log lines exceeds the watchdog threshold." -f `
				$s.Id, ($bytes / 1MB), $lines)
		Write-Warning ("  A runaway log usually means the engine is spewing per-message errors " +
				"(see the MessageQueue note in tools/sim_api.gd). Inspect {0}" -f $s.Log)
		$s.Aborted = $true
		Stop-Process -Id $s.Proc.Id -Force -ErrorAction SilentlyContinue
	}
	Start-Sleep -Seconds 2
}

$searchSecs = ((Get-Date) - $t0).TotalSeconds
Write-Host ""
Write-Host ("search done in {0:N1} s" -f $searchSecs)
Write-Host ""
Write-Host "shard      exit  tries  log        json"
Write-Host "---------  ----  -----  ---------  ------------------------------"
$bad = 0
foreach ($s in $shards) {
	$code = if ($s.Aborted) { "KILL" } else { "$($s.Proc.ExitCode)" }
	$bytes = Get-LogBytes $s
	$fresh = (Test-Path $s.Json) -and ((Get-Item $s.Json).LastWriteTime -gt $t0)
	$jsonNote = if ($fresh) { "written ({0:N1} KB)" -f ((Get-Item $s.Json).Length / 1KB) }
		elseif (Test-Path $s.Json) { "STALE - not rewritten this run" }
		else { "MISSING" }
	if ($s.Aborted -or $s.Proc.ExitCode -ne 0 -or -not $fresh) { $bad++ }
	Write-Host ("{0,-9}  {1,-4}  {2,-5}  {3,7:N1} KB  {4}" -f $s.Id, $code, $s.Attempts, ($bytes / 1KB), $jsonNote)
}
if ($bad -gt 0) {
	Write-Warning ("{0} of {1} shard(s) did not produce a fresh result; the report below is incomplete." -f $bad, $shards.Count)
}
Write-Host ""

# Merge: one more process reads every tools/out/depth_*.json and writes the
# report + the watchable route-sets.
& $Godot --headless --path . --script tools/run_depth.gd -- --report
Write-Host ("TOTAL {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds)
Pop-Location
exit $bad
