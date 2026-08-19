# Compile hot-cache from lessons-learned.md
# Parses structured entries and outputs JSONL for zero-token error-signature lookup.
# Usage: powershell -NoProfile -File compile-hot-cache.ps1

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$lessonsFile = Join-Path $workspace 'ai-workspace\agents\lessons-learned.md'
$outputDir = Join-Path $workspace 'ai-workspace\generated'
$outputFile = Join-Path $outputDir 'hot-cache.jsonl'

if (-not (Test-Path -LiteralPath $lessonsFile)) {
    "error: lessons-learned.md not found at $lessonsFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$lines = Get-Content -LiteralPath $lessonsFile
$entries = @()
$current = $null

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    # Entry header: ### [YYYY-MM-DD] Description | repo: xxx | severity: xxx
    if ($line -match '^\s*###\s+\[(\d{4}-\d{2}-\d{2})\]\s+(.+?)\s*\|\s*repo:\s*(\S+)\s*\|\s*severity:\s*(\S+)') {
        if ($current) { $entries += $current }
        $current = @{
            date = $matches[1]
            title = $matches[2].Trim()
            repo = $matches[3]
            severity = $matches[4]
            symptom = ''
            root_cause = ''
            solution = ''
            keywords = ''
        }
        continue
    }

    if ($current) {
        if ($line -match '^\s*-\s+\*\*Symptom\*\*:\s*(.+)') { $current.symptom = $matches[1].Trim() }
        if ($line -match '^\s*-\s+\*\*Root Cause\*\*:\s*(.+)') { $current.root_cause = $matches[1].Trim() }
        if ($line -match '^\s*-\s+\*\*Solution\*\*:\s*(.+)') { $current.solution = $matches[1].Trim() }
        if ($line -match '^\s*-\s+\*\*Keywords\*\*:\s*(.+)') { $current.keywords = $matches[1].Trim() }
    }
}
if ($current) { $entries += $current }

# Generate JSONL
$jsonLines = @()
foreach ($entry in $entries) {
    if (-not $entry.symptom) { continue }

    # Generate error_signature_hash from symptom text
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($entry.symptom.ToLower().Trim())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    $shortHash = "sha256:$($hash.Substring(0, 16))"

    # Split keywords into array
    $kwArray = @()
    if ($entry.keywords) {
        $kwArray = ($entry.keywords -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    $obj = [ordered]@{
        id = "LL-$($entry.date)"
        kind = 'lesson'
        status = 'resolved'
        title = $entry.title
        severity = $entry.severity
        repo = $entry.repo
        error_signature = $entry.symptom
        error_signature_hash = $shortHash
        keywords = $kwArray
        root_cause = $entry.root_cause
        fix_summary = $entry.solution
        source = 'lessons-learned.md'
    }

    $jsonLines += ($obj | ConvertTo-Json -Compress -Depth 3)
}

# Write output
$jsonLines | Set-Content -LiteralPath $outputFile -Encoding UTF8

"compiled: $($jsonLines.Count) entries -> $outputFile"
