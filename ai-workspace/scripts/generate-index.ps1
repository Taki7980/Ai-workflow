param(
    [switch]$Incremental  # Only reparse files changed in last git commit; faster for hooks
)

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend   = "$workspace\backend"
$frontend  = "$workspace\frontend"
$refs      = "$workspace\ai-workspace\agents\references"

# ── INCREMENTAL MODE ────────────────────────────────────────────────────────────
# Detect which files changed in the last commit; only rebuild affected index sections.
if ($Incremental) {
    $beChanged = @()
    $feChanged = @()
    if (Test-Path "$backend\.git") {
        $beChanged = @(git -C $backend diff-tree -r --name-only --no-commit-id HEAD 2>$null | Where-Object { $_ -match '\.(go|ts|tsx)$' })
    }
    if (Test-Path "$frontend\.git") {
        $feChanged = @(git -C $frontend diff-tree -r --name-only --no-commit-id HEAD 2>$null | Where-Object { $_ -match '\.(ts|tsx)$' })
    }
    $totalChanged = $beChanged.Count + $feChanged.Count
    if ($totalChanged -eq 0) {
        "generate_index: incremental -- no relevant changes in last commit, indexes unchanged"
        exit 0
    }
    "generate_index: incremental -- $totalChanged changed file(s), running full rebuild to patch"
    # Fall through to full rebuild (simpler + correct; full rebuild ~2-5s on this codebase)
}

if (!(Test-Path $refs)) { New-Item -ItemType Directory -Force -Path $refs | Out-Null }

$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$headBackend = "Unknown"
if (Test-Path "$backend\.git") { 
    $headBackend = (git -C $backend rev-parse HEAD 2>$null) 
} else {
    $headBackend = (git -C $workspace rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $headBackend) { $headBackend = "Unknown" }
}
$headFrontend = "Unknown" 
if (Test-Path "$frontend\.git") { 
    $headFrontend = (git -C $frontend rev-parse HEAD 2>$null) 
} else {
    $headFrontend = "n/a"
}

$endpointMd = "$refs\endpoint_index.md"
$symbolMd = "$refs\symbol_index.md"

@"
# Endpoint Index
Generated: $date
Backend HEAD: $headBackend
Frontend HEAD: $headFrontend

## Backend Routes
| Method | Path | Handler | File:Line |
|---|---|---|---|
"@ | Out-File $endpointMd -Encoding utf8

@"
# Symbol Index
Generated: $date
Backend HEAD: $headBackend
Frontend HEAD: $headFrontend

## Backend Services
| Service | Method | File:Line |
|---|---|---|
"@ | Out-File $symbolMd -Encoding utf8

# Backend Routes
if (Test-Path "$backend\internal\adapter\http\handler") {
    $routeFiles = Get-ChildItem -Path "$backend\internal\adapter\http\handler" -Filter "*_handler.go" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $routeFiles) {
        $lines = Get-Content $file.FullName
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'huma\.(Register|Get|Post|Put|Delete|Patch)\s*\(' -or $lines[$i] -match 'Path:\s*"([^"]+)"') {
                $method = "ANY"
                $path = "UNKNOWN"
                if ($lines[$i] -match 'Method:\s*http\.Method([A-Z][a-z]+)') { $method = $matches[1].ToUpper() }
                elseif ($lines[$i] -match 'Method:\s*"([^"]+)"') { $method = $matches[1] }
                elseif ($lines[$i] -match 'huma\.(Get|Post|Put|Delete|Patch)') { $method = $matches[1].ToUpper() }
                if ($lines[$i] -match 'Path:\s*"([^"]+)"') { $path = $matches[1] }
                
                $rel = $file.FullName.Substring($backend.Length + 1).Replace('\', '/')
                "| $method | $path | | $($rel):$($i+1) |" | Out-File $endpointMd -Append -Encoding utf8
            }
        }
    }
}

"
## Backend Repositories
| Repository | Method | File:Line |
|---|---|---|
" | Out-File $symbolMd -Append -Encoding utf8

if (Test-Path "$backend\internal\service") {
    $svcFiles = Get-ChildItem -Path "$backend\internal\service" -Filter "*.go" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $svcFiles) {
        $matchesList = Select-String -Path $file.FullName -Pattern '^func\s+\(\w+\s+\*?(\w+Service)\)\s+([A-Z]\w+)\('
        foreach ($match in $matchesList) {
            $rel = $file.FullName.Substring($backend.Length + 1).Replace('\', '/')
            "| $($match.Matches.Groups[1].Value) | $($match.Matches.Groups[2].Value) | $($rel):$($match.LineNumber) |" | Out-File $symbolMd -Append -Encoding utf8
        }
    }
}

if (Test-Path "$backend\internal\adapter\postgres") {
    $repoFiles = Get-ChildItem -Path "$backend\internal\adapter\postgres" -Filter "*.go" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $repoFiles) {
        $matchesList = Select-String -Path $file.FullName -Pattern '^func\s+\(\w+\s+\*?(\w+Repository)\)\s+([A-Z]\w+)\('
        foreach ($match in $matchesList) {
            $rel = $file.FullName.Substring($backend.Length + 1).Replace('\', '/')
            "| $($match.Matches.Groups[1].Value) | $($match.Matches.Groups[2].Value) | $($rel):$($match.LineNumber) |" | Out-File $symbolMd -Append -Encoding utf8
        }
    }
}

"
## Frontend Hooks
| Hook | Module | File:Line |
|---|---|---|
" | Out-File $symbolMd -Append -Encoding utf8

if (Test-Path "$frontend\src\modules") {
    $hookFiles = Get-ChildItem -Path "$frontend\src\modules" -Filter "*.ts" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[\\/]api[\\/]' }
    foreach ($file in $hookFiles) {
        $matchesList = Select-String -Path $file.FullName -Pattern 'export\s+(const|function)\s+(use[A-Z]\w+)'
        foreach ($match in $matchesList) {
            $rel = $file.FullName.Substring($frontend.Length + 1).Replace('\', '/')
            $mod = ($rel -split '/')[2]
            "| $($match.Matches.Groups[2].Value) | $mod | $($rel):$($match.LineNumber) |" | Out-File $symbolMd -Append -Encoding utf8
        }
    }
}

"
## Frontend Routes
| Path | Component | File:Line |
|---|---|---|
" | Out-File $symbolMd -Append -Encoding utf8

$routerFile = "$frontend\src\routes\router.tsx"
if (Test-Path $routerFile) {
    $linesList = Select-String -Path $routerFile -Pattern 'path:\s*[''"]([^''"]+)[''"]'
    foreach ($match in $linesList) {
        $rel = $routerFile.Substring($frontend.Length + 1).Replace('\', '/')
        "| $($match.Matches.Groups[1].Value) | | $($rel):$($match.LineNumber) |" | Out-File $symbolMd -Append -Encoding utf8
    }
}

# --- Generic Fallback Parser ---
# If it's not a dual Go/React project, scan the workspace root recursively for functions/classes.
if (-not (Test-Path "$backend\internal") -and -not (Test-Path "$frontend\src")) {
    "
## Project Symbols
| Symbol | Kind | File:Line |
|---|---|---|
" | Out-File $symbolMd -Append -Encoding utf8

    $excludePatterns = @('node_modules', 'venv', '\.git', 'ai-workspace', '\.ai', '\.agents', 'dist', 'build', 'bin', 'obj')
    $files = Get-ChildItem -Path $workspace -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $filePath = $_.FullName
        $exclude = $false
        foreach ($pattern in $excludePatterns) {
            if ($filePath -match [regex]::Escape($pattern)) { $exclude = $true; break }
        }
        -not $exclude -and ($_.Extension -match '^\.(py|rs|js|ts|tsx|go|java|cs|cpp|h|rb|php)$')
    }

    foreach ($file in $files) {
        $rel = $file.FullName.Substring($workspace.Length + 1).Replace('\', '/')
        $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
        if (-not $lines) { continue }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            # Match common function/class patterns in various languages
            if ($line -match '^\s*(?:def|fn|function|class|public\s+class|struct)\s+(\w+)') {
                $name = $matches[1]
                $kind = "Function"
                if ($line -match 'class') { $kind = "Class" }
                elseif ($line -match 'struct') { $kind = "Struct" }
                "| $name | $kind | $($rel):$($i+1) |" | Out-File $symbolMd -Append -Encoding utf8
            }
        }
    }
}
