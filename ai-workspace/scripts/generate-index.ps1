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
        $beChanged = @(git -C $backend diff-tree -r --name-only --no-commit-id HEAD 2>$null | Where-Object { $_ -match '\.(go|ts|tsx|py|rs|js|java|cs)$' })
    }
    if (Test-Path "$frontend\.git") {
        $feChanged = @(git -C $frontend diff-tree -r --name-only --no-commit-id HEAD 2>$null | Where-Object { $_ -match '\.(ts|tsx|js)$' })
    }
    $totalChanged = $beChanged.Count + $feChanged.Count
    if ($totalChanged -eq 0) {
        "generate_index: incremental -- no relevant changes in last commit, indexes unchanged"
        exit 0
    }
    "generate_index: incremental -- $totalChanged changed file(s), running full rebuild"
    # Fall through to full rebuild (simpler + correct)
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
$headFrontend = "n/a"
if (Test-Path "$frontend\.git") {
    $headFrontend = (git -C $frontend rev-parse HEAD 2>$null)
}

$endpointMd = "$refs\endpoint_index.md"
$symbolMd   = "$refs\symbol_index.md"

"# Endpoint Index`nGenerated: $date`nBackend HEAD: $headBackend`nFrontend HEAD: $headFrontend`n`n## Routes`n| Method | Path | Handler | File:Line |`n|---|---|---|---|" | Out-File $endpointMd -Encoding utf8

"# Symbol Index`nGenerated: $date`nBackend HEAD: $headBackend`nFrontend HEAD: $headFrontend`n`n## Project Symbols`n| Symbol | Kind | File:Line |`n|---|---|---|" | Out-File $symbolMd -Encoding utf8

# ── GENERIC SYMBOL + ROUTE PARSER ───────────────────────────────────────────────
# Scans workspace source files for functions, classes, structs, and HTTP routes.
# Covers: Python, Rust, JS/TS, Go, Java, C#, C/C++, Ruby, PHP.
# ponytail: generic regex — ceiling is ambiguous multi-line signatures;
#   upgrade: replace with ctags or tree-sitter per-language parsers after bootstrapping.
$excludePatterns = @('node_modules', 'venv', '\.git', 'ai-workspace', '\.ai', '\.agents', 'dist', 'build', 'bin', 'obj', '__pycache__')
$sourceExts = '^\.(py|rs|js|ts|tsx|go|java|cs|cpp|h|rb|php)$'

$files = Get-ChildItem -Path $workspace -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $fp   = $_.FullName
    $skip = $false
    foreach ($p in $excludePatterns) { if ($fp -match [regex]::Escape($p)) { $skip = $true; break } }
    -not $skip -and ($_.Extension -match $sourceExts)
}

foreach ($file in $files) {
    $rel   = $file.FullName.Substring($workspace.Length + 1).Replace('\', '/')
    $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
    if (-not $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Symbol: function/class/struct across common languages
        if ($line -match '^\s*(?:def|fn|function|class|public\s+class|struct|pub\s+fn|pub\s+struct|async\s+function)\s+(\w+)') {
            $name = $matches[1]
            $kind = if ($line -match 'class') { 'Class' } elseif ($line -match 'struct') { 'Struct' } else { 'Function' }
            "| $name | $kind | $($rel):$($i+1) |" | Out-File $symbolMd -Append -Encoding utf8
        }
        # Route: common framework decorator/router patterns
        if ($line -match '(?:@(?:app|router|bp)\.(get|post|put|delete|patch)|router\.(Get|Post|Put|Delete|Patch))\s*\(\s*[''"]([^''"]+)[''"]') {
            $method = $matches[1].ToUpper()
            $path   = $matches[3]
            "| $method | $path | | $($rel):$($i+1) |" | Out-File $endpointMd -Append -Encoding utf8
        }
    }
}

"generate_index: done -- symbol_index.md + endpoint_index.md written to $refs"
