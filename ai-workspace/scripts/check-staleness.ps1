# Staleness diagnostic: compares current file hashes against index-state.json.
# Usage: powershell -File check-staleness.ps1
# Output: fresh_files, modified_files, missing_files, new_files, index_status

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'index-state.ps1')

$state = Get-IndexState -Workspace $workspace
if ($null -eq $state) {
    'index_status: no_state -- run generate-index.ps1 first'
    exit 1
}

"index_generated: $($state.generatedAt)"
"backend_head:    $($state.backendHead)"
"frontend_head:   $($state.frontendHead)"

$excludePatterns = @('node_modules', 'venv', '\.git', 'ai-workspace', '\.ai', '\.agents', 'dist', 'build', 'bin', 'obj', '__pycache__')
$sourceExts = '^\.(py|rs|js|ts|tsx|go|java|cs|cpp|h|rb|php)$'

$currentFiles = Get-ChildItem -Path $workspace -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $fp = $_.FullName; $skip = $false
    foreach ($p in $excludePatterns) { if ($fp -match [regex]::Escape($p)) { $skip = $true; break } }
    -not $skip -and ($_.Extension -match $sourceExts)
} | ForEach-Object { $_.FullName.Substring($workspace.Length + 1).Replace('\', '/') }

$stateFiles = $state.files.PSObject.Properties.Name
$stateSet = @{}; foreach ($s in $stateFiles) { $stateSet[$s] = $true }
$currentSet = @{}; foreach ($f in $currentFiles) { $currentSet[$f] = $true }

$fresh = 0; $modified = 0; $missing = 0; $new = 0

foreach ($rel in $stateFiles) {
    $abs = Join-Path $workspace ($rel.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $abs)) { $missing++; continue }
    $cur = Get-CurrentFileHash -AbsPath $abs
    $stored = $state.files.$rel.sha256
    if ($cur -and $stored -and $cur -eq $stored.ToUpper()) { $fresh++ } else { $modified++ }
}
foreach ($rel in $currentFiles) {
    if (-not $stateSet.ContainsKey($rel)) { $new++ }
}

"fresh_files:    $fresh"
"modified_files: $modified"
"missing_files:  $missing"
"new_files:      $new"
$status = if ($modified -gt 0 -or $missing -gt 0 -or $new -gt 0) { 'stale' } else { 'fresh' }
"index_status:   $status"
