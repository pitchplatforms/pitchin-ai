<#
  install-graph-hooks.ps1 — install git hooks in the 3 pitchIN repos so the
  graphify graph auto-refreshes (in the background) after each commit / merge.

  Re-run this after a fresh clone or on a new machine — git hooks live under
  .git/hooks and are NOT version-controlled.

  Usage:  .\install-graph-hooks.ps1            # install
          .\install-graph-hooks.ps1 -Uninstall # remove the hooks
#>
param([switch]$Uninstall)

$root = "C:\Users\pitchIN-TP-09\ai"
$projects = @("pitchINAPI", "PitchinAdminWeb", "PitchinCustomerWeb") | ForEach-Object { Join-Path $root $_ }
$hooks = @("post-commit", "post-merge")

# sh hook body: launch the wrapper detached & hidden, never fail the commit.
$body = @'
#!/bin/sh
# graphify auto-refresh (non-blocking; never fails the commit)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\pitchIN-TP-09\ai\graphify-out\_refresh-hook.ps1')" >/dev/null 2>&1 || true
exit 0
'@
$body = $body -replace "`r`n", "`n"   # LF only — sh chokes on CRLF in the shebang

foreach ($p in $projects) {
    if (-not (Test-Path (Join-Path $p ".git"))) { Write-Host "skip (not a git repo): $p" -ForegroundColor Yellow; continue }
    $hookDir = Join-Path $p ".git\hooks"
    New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
    foreach ($h in $hooks) {
        $hp = Join-Path $hookDir $h
        if ($Uninstall) {
            if (Test-Path $hp) { Remove-Item $hp -Force; Write-Host "removed:   $hp" -ForegroundColor DarkYellow }
        } else {
            [System.IO.File]::WriteAllText($hp, $body, (New-Object System.Text.UTF8Encoding($false)))  # no BOM
            Write-Host "installed: $hp" -ForegroundColor Green
        }
    }
}
Write-Host ($(if ($Uninstall) { "Hooks removed." } else { "Hooks installed. A commit/merge in any of the 3 repos now refreshes graph.json in the background." }))
