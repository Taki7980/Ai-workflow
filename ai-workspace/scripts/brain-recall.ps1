param(
    [Parameter(Mandatory=$true)]
    [string]$Query,
    [int]$MaxResults = 5
)

# Brain Recall: Probabilistic BM25+ & Cognitive Memory Activation Search
# Mathematical grounding:
#   - Robertson-Spärck Jones Okapi BM25+ ranking
#   - Ebbinghaus memory retention decay R(t) = exp(-delta_t / (tau * (1 + ln(1 + R_m))))
# Zero LLM tokens required.

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$brainDir = Join-Path $workspace 'ai-workspace\agents\brain'
$indexFile = Join-Path $brainDir 'brain-index.md'
$brainFile = Join-Path $brainDir 'brain.md'
$mathScript = Join-Path $PSScriptRoot 'math-algorithms.ps1'

if (Test-Path -LiteralPath $mathScript) {
    . $mathScript
}

if (-not (Test-Path -LiteralPath $indexFile)) {
    'brain_status: empty (no memories yet)'
    exit 0
}

# Tokenize query using semantic tokenizer
$queryTerms = if (Get-Command Get-Tokens -ErrorAction SilentlyContinue) {
    Get-Tokens -Text $Query
} else {
    @($Query -split '\s+' | Where-Object { $_.Length -ge 2 } | ForEach-Object { $_.ToLower() } | Select-Object -Unique)
}

if ($queryTerms.Count -eq 0) {
    'brain_status: no valid search terms'
    exit 0
}

$indexLines = Get-Content -LiteralPath $indexFile
$entries = @()
$corpusDocTokens = @()
$termDocFreq = @{}

# Phase 1: Parse table entries and build corpus statistics
for ($i = 0; $i -lt $indexLines.Count; $i++) {
    $line = $indexLines[$i]
    if ($line -notmatch '^\|.*\|$') { continue }
    if ($line -match '^\|[-\s|]+\|$') { continue }  # skip table separator
    if ($line -match '^\|\s*ID\s*\|') { continue }  # skip header
    if ($line -match 'empty — entries are added') { continue }

    $cells = $line -split '\|' | ForEach-Object { $_.Trim() }
    # Format: | ID | Date | Type | Keywords |
    if ($cells.Count -lt 5) { continue }
    $id = $cells[1]
    $dateStr = $cells[2]
    $type = $cells[3]
    $kwStr = $cells[4]

    $docTokens = if (Get-Command Get-Tokens -ErrorAction SilentlyContinue) {
        Get-Tokens -Text "$type $kwStr"
    } else {
        @("$type $kwStr" -split '\s+' | Where-Object { $_.Length -ge 2 } | ForEach-Object { $_.ToLower() })
    }

    # Update Document Frequencies
    $seenInDoc = @{}
    foreach ($tok in $docTokens) {
        if (-not $seenInDoc.ContainsKey($tok)) {
            $seenInDoc[$tok] = $true
            if ($termDocFreq.ContainsKey($tok)) { $termDocFreq[$tok]++ } else { $termDocFreq[$tok] = 1 }
        }
    }

    $corpusDocTokens += ,$docTokens
    $entries += [pscustomobject]@{
        ID = $id
        DateStr = $dateStr
        Type = $type
        Keywords = $kwStr
        Line = $line
        Tokens = $docTokens
        LineNumber = $i + 1
    }
}

$corpusCount = $entries.Count
if ($corpusCount -eq 0) {
    'brain_status: empty (no entries)'
    exit 0
}

# Calculate average document length
$totalTokens = 0
foreach ($d in $corpusDocTokens) { $totalTokens += $d.Count }
$avgDocLen = [Math]::Max(1.0, ([double]$totalTokens / [double]$corpusCount))

# Phase 2: Compute BM25+ and Cognitive Retention Score
$scored = for ($i = 0; $i -lt $entries.Count; $i++) {
    $entry = $entries[$i]
    $docTokens = $entry.Tokens

    # BM25+ relevance
    $bm25 = if (Get-Command Get-BM25PlusScore -ErrorAction SilentlyContinue) {
        Get-BM25PlusScore -QueryTerms $queryTerms -DocTokens $docTokens -AvgDocLength $avgDocLen -CorpusDocFreq $termDocFreq -CorpusDocCount $corpusCount
    } else {
        # Fallback term count
        $cnt = 0
        foreach ($q in $queryTerms) { if ($docTokens -contains $q) { $cnt++ } }
        [double]$cnt
    }

    if ($bm25 -gt 0) {
        # Cognitive Retention factor
        $retention = 1.0
        if (Get-Command Get-EbbinghausRetention -ErrorAction SilentlyContinue) {
            $entryDate = [DateTime]::MinValue
            if ([DateTime]::TryParse($entry.DateStr, [ref]$entryDate)) {
                $retention = Get-EbbinghausRetention -EntryDate $entryDate -ReinforcementCount 1 -TauDays 60.0
            }
        }

        $compositeScore = [Math]::Round(($bm25 * $retention), 4)
        [pscustomobject]@{
            ID = $entry.ID
            CompositeScore = $compositeScore
            BM25Score = $bm25
            Retention = [Math]::Round($retention, 3)
            Line = $entry.Line
            Entry = $entry
        }
    }
}

if (-not $scored -or $scored.Count -eq 0) {
    'brain_status: no matches'
    exit 0
}

# Rank top matches
$topMatches = @($scored | Sort-Object @{Expression='CompositeScore';Descending=$true}, @{Expression='BM25Score';Descending=$true} | Select-Object -First $MaxResults)

"brain_matches: $($topMatches.Count) (ranked via BM25+ and Ebbinghaus decay)"
''

# Phase 3: Extract entries from brain.md
if (Test-Path -LiteralPath $brainFile) {
    $brainContent = Get-Content -LiteralPath $brainFile -Raw

    foreach ($match in $topMatches) {
        $cells = $match.Line -split '\|'
        $header = "## [$($match.ID)] $($cells[2].Trim()) | $($cells[3].Trim()) | $($cells[4].Trim())"
        $pattern = "(?ms)(^$([regex]::Escape($header))\r?\n.*?)(?=\r?\n## \[|\z)"
        if ($brainContent -match $pattern) {
            "---"
            "relevance_composite: $($match.CompositeScore) (BM25+: $($match.BM25Score), Retention: $($match.Retention))"
            $Matches[1].Trim()
            ''
        }
    }
}
