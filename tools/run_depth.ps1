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
	[string]$Godot = "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

if ($Levels -eq "") { $ids = @("L1", "L2", "L3", "L4", "X-1") }
else { $ids = $Levels.Split(",") | ForEach-Object { $_.Trim() } }

$quickFlag = @()
if ($Quick) { $quickFlag = @("--quick") }

New-Item -ItemType Directory -Force -Path "tools\out" | Out-Null
New-Item -ItemType Directory -Force -Path "tools\out\log" | Out-Null

$t0 = Get-Date
$killBytes = $MaxLogMB * 1MB
Write-Host ("launching {0} shard(s): {1}" -f $ids.Count, ($ids -join ", "))
Write-Host ("watchdog: a shard is killed if its logs pass {0} MB or {1} lines" -f $MaxLogMB, $MaxLogLines)

$shards = @()
foreach ($id in $ids) {
	$args = @("--headless", "--path", ".", "--script", "tools/run_depth.gd", "--",
			"--levels", $id) + $quickFlag
	$log = Join-Path $root "tools\out\log\$id.log"
	$err = "$log.err"
	$json = Join-Path $root "tools\out\depth_$id.json"
	if (Test-Path $log) { Remove-Item $log -Force }
	if (Test-Path $err) { Remove-Item $err -Force }
	$p = Start-Process -FilePath $Godot -ArgumentList $args -NoNewWindow -PassThru `
			-RedirectStandardOutput $log -RedirectStandardError $err
	$null = $p.Handle # cache the handle, or WaitForExit() returns immediately
	$shards += [pscustomobject]@{
		Id = $id; Proc = $p; Log = $log; Err = $err; Json = $json; Aborted = $false
	}
}

function Get-LogBytes($s) {
	$n = 0
	foreach ($f in @($s.Log, $s.Err)) {
		if (Test-Path $f) { $n += (Get-Item $f).Length }
	}
	return $n
}

# Poll rather than Wait-Process/WaitForExit: both have returned early here on
# redirected child processes, which silently truncates the slowest shard.
while ($true) {
	$alive = @($shards | Where-Object { -not $_.Proc.HasExited })
	if ($alive.Count -eq 0) { break }
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
Write-Host "shard      exit  log        json"
Write-Host "---------  ----  ---------  ------------------------------"
$bad = 0
foreach ($s in $shards) {
	$code = if ($s.Aborted) { "KILL" } else { "$($s.Proc.ExitCode)" }
	$bytes = Get-LogBytes $s
	$fresh = (Test-Path $s.Json) -and ((Get-Item $s.Json).LastWriteTime -gt $t0)
	$jsonNote = if ($fresh) { "written ({0:N1} KB)" -f ((Get-Item $s.Json).Length / 1KB) }
		elseif (Test-Path $s.Json) { "STALE - not rewritten this run" }
		else { "MISSING" }
	if ($s.Aborted -or $s.Proc.ExitCode -ne 0 -or -not $fresh) { $bad++ }
	Write-Host ("{0,-9}  {1,-4}  {2,7:N1} KB  {3}" -f $s.Id, $code, ($bytes / 1KB), $jsonNote)
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
