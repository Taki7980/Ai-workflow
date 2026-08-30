param(
    [switch]$Incremental  # Only reparse files changed since last index-state.json; faster for hooks
)

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend   = "$workspace\backend"
$frontend  = "$workspace\frontend"
$refs      = "$workspace\ai-workspace\agents\references"
$genDir    = "$workspace\ai-workspace\generated"
. (Join-Path $PSScriptRoot 'index-state.ps1')

if (!(Test-Path $refs))    { New-Item -ItemType Directory -Force -Path $refs    | Out-Null }
if (!(Test-Path $genDir))  { New-Item -ItemType Directory -Force -Path $genDir  | Out-Null }

$date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$headBackend = 'Unknown'
if (Test-Path "$backend\.git") {
    $headBackend = (git -C $backend rev-parse HEAD 2>$null)
} else {
    $h = (git -C $workspace rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $h) { $headBackend = $h }
}
$headFrontend = 'n/a'
if (Test-Path "$frontend\.git") {
    $headFrontend = (git -C $frontend rev-parse HEAD 2>$null)
}

$excludePatterns = @('node_modules', 'venv', '\.git', 'ai-workspace', '\.ai', '\.agents', 'dist', 'build', 'bin', 'obj', '__pycache__')
$sourceExts = '^\.(py|rs|js|ts|tsx|go|java|cs|cpp|h|rb|php)$'

$files = Get-ChildItem -Path $workspace -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $fp   = $_.FullName
    $skip = $false
    foreach ($p in $excludePatterns) { if ($fp -match [regex]::Escape($p)) { $skip = $true; break } }
    -not $skip -and ($_.Extension -match $sourceExts)
}

# ── INCREMENTAL MODE ────────────────────────────────────────────────────────────
# Use stored file hashes (not git diff-tree) to detect working-tree changes.
# ponytail: changed sets use full rebuild; add row-level merging only when measured rebuild cost requires it.
$prevState = Get-IndexState -Workspace $workspace
if ($Incremental -and $null -ne $prevState) {
    $unchanged = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($workspace.Length + 1).Replace('\', '/')
        if (Test-IndexedFileFresh -State $prevState -RelPath $rel -Workspace $workspace) {
            $unchanged++
        }
    }
    $previousCount = @($prevState.files.PSObject.Properties).Count
    $changed = $files.Count - $unchanged + [Math]::Max(0, $previousCount - $files.Count)
    if ($changed -eq 0 -and $previousCount -eq $files.Count) {
        "generate_index: incremental -- all $unchanged file(s) unchanged, indexes current"
        exit 0
    }
    "generate_index: incremental -- $changed changed / $unchanged unchanged, rebuilding"
}

# ── GENERATE TO TEMP FILES (atomic) ────────────────────────────────────────────
$runId       = [Guid]::NewGuid().ToString('N')
$endpointTmp = "$genDir\endpoint_index.$runId.tmp"
$symbolTmp   = "$genDir\symbol_index.$runId.tmp"
$stateTmp    = "$genDir\index-state.$runId.tmp"
$endpointMd  = "$refs\endpoint_index.md"
$symbolMd    = "$refs\symbol_index.md"
$statePath   = "$genDir\index-state.json"

"# Endpoint Index`nGenerated: $date`nBackend HEAD: $headBackend`nFrontend HEAD: $headFrontend`n`n## Routes`n| Method | Path | Handler | File:Line |`n|---|---|---|---|" | Out-File $endpointTmp -Encoding utf8
"# Symbol Index`nGenerated: $date`nBackend HEAD: $headBackend`nFrontend HEAD: $headFrontend`n`n## Project Symbols`n| Symbol | Kind | File:Line |`n|---|---|---|" | Out-File $symbolTmp -Encoding utf8

# ── PARSE SOURCE FILES ───────────────────────────────────────────────────────────
# ponytail: generic regex — ceiling is ambiguous multi-line signatures;
#   upgrade: replace with ctags or tree-sitter per-language parsers after bootstrapping.
$fileHashes = [ordered]@{}

foreach ($file in $files) {
    $rel   = $file.FullName.Substring($workspace.Length + 1).Replace('\', '/')
    # Hash every file that participates in indexing (for index-state.json)
    $hash = Get-CurrentFileHash -AbsPath $file.FullName
    if ($hash) { $fileHashes[$rel] = @{ sha256 = $hash } }

    $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
    if (-not $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*(?:def|fn|function|class|public\s+class|struct|pub\s+fn|pub\s+struct|async\s+function)\s+(\w+)') {
            $name = $matches[1]
            $kind = if ($line -match 'class') { 'Class' } elseif ($line -match 'struct') { 'Struct' } else { 'Function' }
            "| $name | $kind | $($rel):$($i+1) |" | Out-File $symbolTmp -Append -Encoding utf8
        }
        if ($line -match '(?:@(?:app|router|bp)\.(get|post|put|delete|patch)|router\.(Get|Post|Put|Delete|Patch))\s*\(\s*[''"]([^''"]+)[''"]') {
            $method = $matches[1].ToUpper()
            $path   = $matches[3]
            "| $method | $path | | $($rel):$($i+1) |" | Out-File $endpointTmp -Append -Encoding utf8
        }
    }
}

# ── WRITE index-state.json ───────────────────────────────────────────────────────
$stateObj = [ordered]@{
    version     = 1
    generatedAt = (Get-Date -Format 'o')
    backendHead = $headBackend
    frontendHead= $headFrontend
    files       = $fileHashes
}
$stateJson = $stateObj | ConvertTo-Json -Depth 4 -Compress:$false
# Validate before committing
$stateJson | ConvertFrom-Json | Out-Null   # throws if malformed

$stateJson | Out-File $stateTmp -Encoding utf8

# ── ATOMIC REPLACE (all-or-nothing) ─────────────────────────────────────────────
Move-Item -LiteralPath $symbolTmp   -Destination $symbolMd   -Force
Move-Item -LiteralPath $endpointTmp -Destination $endpointMd -Force
Move-Item -LiteralPath $stateTmp    -Destination $statePath  -Force

"generate_index: done -- symbol_index.md + endpoint_index.md + index-state.json written ($($fileHashes.Count) files hashed)"
