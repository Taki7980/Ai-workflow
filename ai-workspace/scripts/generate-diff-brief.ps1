param(
    [ValidateSet("backend", "frontend", "both")]
    [string]$Repo = "both",
    [switch]$Detailed
)

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$repos = @()

if ($Repo -eq "both" -or $Repo -eq "backend") { $repos += "$workspace\backend" }
if ($Repo -eq "both" -or $Repo -eq "frontend") { $repos += "$workspace\frontend" }

foreach ($r in $repos) {
    $name = Split-Path $r -Leaf
    Write-Host "=== $name ==="
    
    if (!(Test-Path "$r\.git")) {
        Write-Host "Not a git repository."
        continue
    }

    Write-Host "--- Status ---"
    git -C $r status -s
    
    Write-Host "`n--- Diff Stat (Unstaged) ---"
    git -C $r diff --stat
    
    Write-Host "`n--- Diff Stat (Staged) ---"
    git -C $r diff --staged --stat

    if ($Detailed) {
        Write-Host "`n--- Detailed Diff (Unstaged) ---"
        git -C $r diff -U3
        
        Write-Host "`n--- Detailed Diff (Staged) ---"
        git -C $r diff --staged -U3
    }
    Write-Host ""
}
