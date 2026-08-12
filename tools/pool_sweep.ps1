# Scaling measurement + determinism gate for the parallel evaluation pool.
#
#   powershell -File tools/pool_sweep.ps1 -Level L3 -N 640 -Chunk 4 -Step 0.25
#
# 1. DETERMINISM GATE: runs the identical candidate batch through a 1-worker
#    pool (which IS the sequential in-process path: one Godot process running
#    the candidates one after another via SimApi.run) and through an 8-worker
#    pool, then diffs the merged per-candidate results byte-for-byte. Parallelism
#    must not perturb a single bit.
# 2. SCALING SWEEP: runs the batch at 1/2/4/8/12/16 workers and prints
#    evals/s, speed-up vs 1 worker, and parallel efficiency.

param(
	[string]$Level = "L3",
	[int]$N = 640,
	[int]$Chunk = 4,
	[double]$Step = 0.25,
	[int[]]$WorkerCounts = @(1, 2, 4, 8, 12, 16),
	[string]$Godot = "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$pool = Join-Path $root "tools\pool.ps1"
$base = Join-Path $root "tools\out\pool"

function Run-Pool($workers) {
	$wd = Join-Path $base ("w{0}" -f $workers)
	& powershell -NoProfile -File $pool -Workers $workers -Level $Level -N $N -Chunk $Chunk `
		-Step $Step -WorkDir $wd -Godot $Godot | Out-Null
	return (Get-Content (Join-Path $wd "summary.json") -Raw | ConvertFrom-Json)
}

Write-Host ("=== parallel pool: level {0}, {1} candidates, chunk {2}, step {3} ===" -f $Level, $N, $Chunk, $Step)

# ---- 1. determinism gate (1 worker vs 8 workers) ----
Write-Host "`n[determinism] running 1-worker (sequential) and 8-worker pools on the same batch..."
$s1 = Run-Pool 1
$s8 = Run-Pool 8
$m1 = Get-Content (Join-Path $base "w1\merged.json") -Raw
$m8 = Get-Content (Join-Path $base "w8\merged.json") -Raw
$h1 = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($m1))) -Algorithm SHA256).Hash
$h8 = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($m8))) -Algorithm SHA256).Hash
$identical = ($m1 -eq $m8)
Write-Host ("  1-worker : {0} candidates, sha256 {1}" -f $s1.evals, $h1.Substring(0, 16))
Write-Host ("  8-worker : {0} candidates, sha256 {1}" -f $s8.evals, $h8.Substring(0, 16))
Write-Host ("  BIT-IDENTICAL parallel == sequential: {0}" -f $(if ($identical) { "PASS" } else { "FAIL" }))

# ---- 2. scaling sweep ----
Write-Host "`n[scaling] sweeping worker counts $($WorkerCounts -join ', ')..."
$rows = @()
foreach ($w in $WorkerCounts) {
	if ($w -eq 1) { $s = $s1 } elseif ($w -eq 8) { $s = $s8 } else { $s = Run-Pool $w }
	$rows += [pscustomobject]@{ workers = $w; evals_per_s = $s.evals_per_s; wall_s = $s.wall_s;
		overhead_pct = $s.overhead_pct; imbalance = $s.imbalance;
		single_core = $s.single_core_evals_per_s }
}
$base1 = ($rows | Where-Object { $_.workers -eq 1 }).evals_per_s

Write-Host ""
Write-Host "workers  evals/s  speedup  efficiency  wall_s  imbalance  overhead%"
Write-Host "-------  -------  -------  ----------  ------  ---------  ---------"
foreach ($r in $rows) {
	$sp = $r.evals_per_s / $base1
	$eff = $sp / $r.workers
	Write-Host ("{0,7}  {1,7:N2}  {2,6:N2}x  {3,9:P0}  {4,6:N1}  {5,9:N2}  {6,8:N1}" -f `
		$r.workers, $r.evals_per_s, $sp, $eff, $r.wall_s, $r.imbalance, $r.overhead_pct)
}
$peak = ($rows | Sort-Object evals_per_s -Descending | Select-Object -First 1)
Write-Host ""
Write-Host ("PEAK sustained: {0:N1} evals/s at {1} workers ({2:N2}x over 1 worker)." -f `
	$peak.evals_per_s, $peak.workers, ($peak.evals_per_s / $base1))
Write-Host ("Per-core sim rate (startup/orchestration removed): ~{0:N1} evals/s/core." -f `
	($rows | Where-Object { $_.workers -eq 1 }).single_core)

# machine-readable dump for the report
$rows | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $base "scaling.json") -Encoding utf8
Write-Host ("`n(scaling.json + per-config summary.json written under {0})" -f $base)
