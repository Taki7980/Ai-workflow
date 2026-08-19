param(
    [Parameter(Mandatory=$true)]
    [string]$Query,
    [int]$MaxResults = 5
)

# Brain Recall: Deterministic keyword search against the brain index
# Returns matching brain entries without any LLM tokens
# Usage: powershell -NoProfile -File brain-recall.ps1 -Query "payment outstanding cash"

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$brainDir = Join-Path $workspace 'ai-workspace\agents\brain'
$indexFile = Join-Path $brainDir 'brain-index.md'
$brainFile = Join-Path $brainDir 'brain.md'

if (-not (Test-Path -LiteralPath $indexFile)) {
    'brain_status: empty (no memories yet)'
    exit 0
}

# Split query into search terms (3+ chars)
$terms = $Query -split '\s+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique

if ($terms.Count -eq 0) {
    'brain_status: no valid search terms'
    exit 0
}

# Score each index line by keyword match count
$indexLines = Get-Content -LiteralPath $indexFile
$scored = for ($i = 0; $i -lt $indexLines.Count; $i++) {
    $line = $indexLines[$i]
    if ($line -notmatch '^\|.*\|$') { continue }
    if ($line -match '^\|[-\s|]+\|$') { continue }  # skip table separator
    if ($line -match '^\|\s*ID\s*\|') { continue }  # skip header

    $score = 0
    foreach ($term in $terms) {
        if ($line.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $score++
        }
    }
    if ($score -gt 0) {
        # Extract entry ID from first column
        $id = ($line -split '\|')[1].Trim()
        [pscustomobject]@{ Score = $score; ID = $id; Line = $line; LineNumber = $i + 1 }
    }
}

if (-not $scored) {
    'brain_status: no matches'
    exit 0
}

# Get top N matches sorted by score
$topMatches = $scored | Sort-Object @{Expression='Score';Descending=$true} | Select-Object -First $MaxResults

"brain_matches: $(@($topMatches).Count)"
''

# For each match, extract the full entry from brain.md
if (Test-Path -LiteralPath $brainFile) {
    $brainContent = Get-Content -LiteralPath $brainFile -Raw

    foreach ($match in $topMatches) {
        # Historical entries reused IDs. Match the full indexed header so each
        # duplicate ID still recalls its own lesson without rewriting history.
        $cells = $match.Line -split '\|'
        $header = "## [$($match.ID)] $($cells[2].Trim()) | $($cells[3].Trim()) | $($cells[4].Trim())"
        $pattern = "(?ms)(^$([regex]::Escape($header))\r?\n.*?)(?=\r?\n## \[|\z)"
        if ($brainContent -match $pattern) {
            "---"
            "relevance_score: $($match.Score)/$($terms.Count)"
            $Matches[1].Trim()
            ''
        }
    }
}
