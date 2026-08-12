# Run tools/run_depth.gd --tune for every level in parallel, one process each,
# and print each shard's summary lines. Level design loop only - it reads
# SEEDS_TUNE and never touches SEEDS_ASSERT.
param(
	[string]$Levels = "L1,L2,L3,L4,X-1",
	[int]$N = 200,
	[string]$Godot = "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
New-Item -ItemType Directory -Force -Path "tools\out\log" | Out-Null
$ids = $Levels.Split(",") | ForEach-Object { $_.Trim() }
$procs = @()
foreach ($id in $ids) {
	$log = Join-Path $root "tools\out\log\tune_$id.log"
	$a = @("--headless", "--path", ".", "--script", "tools/run_depth.gd", "--",
			"--tune", "--levels", $id, "--n", "$N")
	$p = Start-Process -FilePath $Godot -ArgumentList $a -NoNewWindow -PassThru `
			-RedirectStandardOutput $log -RedirectStandardError "$log.err"
	$null = $p.Handle
	$procs += [pscustomobject]@{ Id = $id; Proc = $p; Log = $log }
}
foreach ($s in $procs) { $s.Proc.WaitForExit() }
foreach ($s in $procs) {
	Write-Host ""
	Get-Content $s.Log | Where-Object { $_ -match "^(---|    |\[)" }
}
Pop-Location
