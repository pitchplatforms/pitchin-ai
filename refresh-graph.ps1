<#
  refresh-graph.ps1 — rebuild the graphify knowledge graph for the 3 pitchIN projects.

  Runs the sequential (parallel=False) helper pipeline because the parallel
  extractor crashes on this machine. Re-extraction uses the warm cache, so
  unchanged files are near-instant; only changed files re-parse.

  Usage:
    .\refresh-graph.ps1          # extract -> build -> regenerate HTML map
    .\refresh-graph.ps1 -NoViz   # skip the HTML map (a bit faster)
#>
param([switch]$NoViz)

$ErrorActionPreference = "Stop"
$root = "C:\Users\pitchIN-TP-09\ai"
$out  = Join-Path $root "graphify-out"
$log  = Join-Path $out  "_refresh.log"
Set-Location $root
$env:PYTHONIOENCODING = "utf-8"

$py = (Get-Content (Join-Path $out ".graphify_python")).Trim()
if (-not (Test-Path $py)) { Write-Host "Interpreter not found: $py" -ForegroundColor Red; exit 1 }
if (Test-Path $log) { Remove-Item $log }

function Step($label, $script) {
    Write-Host "[$label] running $([IO.Path]::GetFileName($script)) ..." -ForegroundColor Cyan
    & $py $script *>> $log
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$label] FAILED (exit $LASTEXITCODE). Last lines of log:" -ForegroundColor Red
        Get-Content $log -Tail 25
        exit 1
    }
}

Step "1/3 extract" (Join-Path $out "_run_extract.py")
Step "2/3 build"   (Join-Path $out "_run_build.py")

# Drop stale hand-labels so the (optional) HTML map isn't mislabeled after IDs shift.
Remove-Item (Join-Path $out ".graphify_labels.json") -ErrorAction SilentlyContinue

if (-not $NoViz) {
    Write-Host "[3/3 viz] regenerating graph.html ..." -ForegroundColor Cyan
    & $py -m graphify export html *>> $log
}

# Integrity check (pure PowerShell): graph.json must exist, be sizeable, and not start with a null byte.
$gpath = Join-Path $out "graph.json"
$fs = [IO.File]::OpenRead($gpath)
try { $first = $fs.ReadByte(); $len = $fs.Length } finally { $fs.Close() }
if ($len -lt 100000 -or $first -eq 0) {
    Write-Host "Verification FAILED - graph.json looks corrupt (size=$len, firstByte=$first)." -ForegroundColor Red
    exit 1
}

$mb = [math]::Round($len / 1MB, 1)
$vizNote = if (-not $NoViz) { " + graph.html" } else { "" }
Write-Host "Done. graph.json ($mb MB) + GRAPH_REPORT.md updated$vizNote." -ForegroundColor Green
Write-Host "(Community names in the report/map are placeholders after a refresh - cosmetic; queries unaffected.)" -ForegroundColor DarkGray
