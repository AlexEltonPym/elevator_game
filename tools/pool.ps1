# Coordinator for ONE run of the candidate-granularity parallel evaluation pool.
#
#   powershell -File tools/pool.ps1 -Workers 8 -Level L3 -N 640 -Chunk 4 -Step 0.25
#
# Spawns N long-lived Godot workers (tools/pool_worker.gd), each of which pays
# the ~375 ms engine startup ONCE and then work-steals candidates from a shared
# claim-file queue until it is drained (dynamic load balancing). This script is
# the coordinator only: it builds the queue, launches the workers, waits, and
# aggregates timing + per-candidate stats. It changes nothing in the sim.
#
# Writes into -WorkDir:
#   queue/  taken/            the claim-file queue (one marker per chunk)
#   out/w<i>.json             each worker's results + timing
#   merged.json               {seed -> "served|lost|score|avg_wait|result"} over ALL workers
#   summary.json              one aggregate record (throughput, balance, overhead)
# and prints the summary as a single JSON line on stdout (for the sweep driver).

param(
	[int]$Workers = 8,
	[string]$Level = "L3",
	[string]$Strategy = "thesis",
	[int]$N = 640,
	[int]$Chunk = 4,
	[double]$Step = 0.25,
	[string]$WorkDir = "",
	[string]$Godot = "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($WorkDir -eq "") { $WorkDir = Join-Path $root "tools\out\pool" }

# Fresh work dirs every run.
$queue = Join-Path $WorkDir "queue"
$taken = Join-Path $WorkDir "taken"
$outd  = Join-Path $WorkDir "out"
$logd  = Join-Path $WorkDir "log"
foreach ($d in @($WorkDir, $queue, $taken, $outd, $logd)) {
	if (Test-Path $d) { Remove-Item $d -Recurse -Force }
	New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# One empty marker per chunk. The filename "c<start>" carries the chunk's first
# candidate index; the worker derives the end from -N and -Chunk.
$nChunks = [math]::Ceiling($N / $Chunk)
for ($s = 0; $s -lt $N; $s += $Chunk) {
	New-Item -ItemType File -Path (Join-Path $queue ("c{0}" -f $s)) | Out-Null
}

# Godot wants forward-slash absolute paths for DirAccess / rename_absolute.
$fq = $queue.Replace("\", "/")
$ft = $taken.Replace("\", "/")

$procs = @()
$t0 = Get-Date
for ($i = 0; $i -lt $Workers; $i++) {
	$fout = ($outd.Replace("\", "/")) + ("/w{0}.json" -f $i)
	$a = @("--headless", "--path", ".", "--script", "tools/pool_worker.gd", "--",
		"--worker", "$i", "--queue", $fq, "--taken", $ft, "--out", $fout,
		"--level", $Level, "--strategy", $Strategy, "--step", "$Step",
		"--base", "500000", "--n", "$N", "--chunk", "$Chunk")
	$log = Join-Path $logd ("w{0}.log" -f $i)
	$err = Join-Path $logd ("w{0}.err" -f $i)
	$p = Start-Process -FilePath $Godot -ArgumentList $a -NoNewWindow -PassThru `
		-WorkingDirectory $root -RedirectStandardOutput $log -RedirectStandardError $err
	$null = $p.Handle   # cache handle so HasExited is reliable
	$procs += $p
}

# Poll to completion (redirected children have returned early from WaitForExit).
while ($true) {
	$alive = @($procs | Where-Object { -not $_.HasExited })
	if ($alive.Count -eq 0) { break }
	Start-Sleep -Milliseconds 150
}
$wall = ((Get-Date) - $t0).TotalSeconds

# Aggregate every worker's results.
$merged = @{}          # seed -> stat string
$busyUs = 0.0
$tickUs = 0.0
$claims = @()
$perWorker = @()
$dupes = 0
foreach ($p in $procs) { if ($p.ExitCode -ne 0) { Write-Warning ("worker exited {0}" -f $p.ExitCode) } }
foreach ($f in (Get-ChildItem $outd -Filter "w*.json")) {
	$j = Get-Content $f.FullName -Raw | ConvertFrom-Json
	$busyUs += [double]$j.busy_us
	$tickUs += [double]$j.tick_us
	$claims += [int]$j.claims
	$perWorker += [pscustomobject]@{ worker = $j.worker; n = $j.n_done; claims = $j.claims;
		busy_s = [math]::Round($j.busy_us / 1e6, 2); wall_s = [math]::Round($j.wall_us / 1e6, 2) }
	foreach ($seed in $j.results.PSObject.Properties.Name) {
		if ($merged.ContainsKey($seed)) { $dupes++ }
		$merged[$seed] = $j.results.$seed
	}
}

$evals = $merged.Count
$evalsPerSec = if ($wall -gt 0) { $evals / $wall } else { 0 }
$busyPerSec  = if ($busyUs -gt 0) { $evals / ($busyUs / 1e6) } else { 0 }   # per busy-core-second
$overheadPct = if ($busyUs -gt 0) { 100.0 * ($busyUs - $tickUs) / $busyUs } else { 0 }
# Load balance: max/min candidates any worker did (1.0 = perfect).
$counts = @($perWorker | ForEach-Object { $_.n })
$imbalance = if (($counts | Measure-Object -Minimum).Minimum -gt 0) {
	($counts | Measure-Object -Maximum).Maximum / ($counts | Measure-Object -Minimum).Minimum } else { 0 }

# Persist merged per-candidate results (sorted by seed) for the determinism diff.
$mergedSorted = [ordered]@{}
foreach ($k in ($merged.Keys | Sort-Object { [int]$_ })) { $mergedSorted[$k] = $merged[$k] }
($mergedSorted | ConvertTo-Json -Compress) | Set-Content -Path (Join-Path $WorkDir "merged.json") -Encoding utf8

$summary = [ordered]@{
	workers = $Workers; level = $Level; n = $N; chunk = $Chunk; step = $Step
	evals = $evals; expected = $N; dupes = $dupes; wall_s = [math]::Round($wall, 3)
	evals_per_s = [math]::Round($evalsPerSec, 2)
	busy_core_s_per_eval = [math]::Round($busyUs / 1e6 / [math]::Max(1, $evals), 4)
	single_core_evals_per_s = [math]::Round($busyPerSec, 2)
	overhead_pct = [math]::Round($overheadPct, 2)
	imbalance = [math]::Round($imbalance, 3)
	per_worker = $perWorker
}
($summary | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $WorkDir "summary.json") -Encoding utf8

if ($evals -ne $N) { Write-Warning ("expected {0} evals, got {1} (dupes {2}) - queue accounting bug" -f $N, $evals, $dupes) }

# One compact JSON line on stdout for the sweep driver to capture.
[pscustomobject]@{ workers = $Workers; evals = $evals; wall_s = [math]::Round($wall, 3);
	evals_per_s = [math]::Round($evalsPerSec, 2); overhead_pct = [math]::Round($overheadPct, 2);
	imbalance = [math]::Round($imbalance, 3); dupes = $dupes } | ConvertTo-Json -Compress
