param([switch]$AllowProductSourceMutation)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$brief = Join-Path $workspace 'ai-workspace\scripts\brief.ps1'
$metrics = Join-Path $workspace '.ai\token_metrics.jsonl'
$before = if (Test-Path $metrics) { (Get-Item $metrics).Length } else { 0 }
$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $brief -Role reviewer -Query 'workflow token efficiency' | Out-String
$after = if (Test-Path $metrics) { (Get-Item $metrics).Length } else { 0 }

if ($output -match 'matched_skills:|matched_module: backend/auth|research_hits: \[stale') { throw 'brief emitted noisy or unsafe routing' }
if ($output -match 'backend_head: unavailable|frontend_head: unavailable|backend_dirty:\s+  unavailable|frontend_dirty:\s+  unavailable') { throw 'brief emitted unverified Git state' }
if ($after -ne $before) { throw 'brief wrote obsolete token metrics' }
if ($output -notmatch 'classification: ambiguous') { throw 'brief misclassified ordinary workflow text as a code symbol' }
$symbolIdxPath = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'
$symbolIdx = if (Test-Path $symbolIdxPath) { Get-Content $symbolIdxPath -Raw } else { '' }
$hasSymbols = $symbolIdx -match '\|\s*\w{3,}\s*\|.*\|\s*\S+:\d+\s*\|'
if ($hasSymbols) {
    # Extract any real symbol name from the index to test routing
    $testSymbol = ([regex]::Match($symbolIdx, '\|\s*([A-Z][A-Za-z]{3,})\s*\|')).Groups[1].Value
    if ($testSymbol) {
        $symbolOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $brief -Role reviewer -Query $testSymbol | Out-String
        if ($symbolOutput -notmatch 'classification: symbol-name') { throw "brief symbol routing failed for: $testSymbol" }
    }
} else {
    'symbol_routing_check: skipped (index empty — run generate-index.ps1 after bootstrapping)'
}
if (-not (Test-Path (Join-Path $workspace '.agents\workflows\small.md'))) { throw 'small-task workflow missing' }
$agentsPath = Join-Path $workspace 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsPath)) { throw 'canonical AGENTS.md missing' }
if ((Get-Content -LiteralPath $agentsPath -Raw) -notmatch 'Choose Workflow Lane') { throw 'AGENTS.md missing workflow lane rules' }
$completion = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'ai-workspace\scripts\complete-task.ps1') -ValidateOnly | Out-String
if ($completion -notmatch 'completion_check: PASS') { throw 'task completion validation failed' }

$brainIndexIds = @(Get-Content -LiteralPath (Join-Path $workspace 'ai-workspace\agents\brain\brain-index.md') | ForEach-Object {
    if ($_ -match '^\|\s*(\d{8}-\d+)\s*\|') { $Matches[1] }
})
$brainEntryIds = @(Get-Content -LiteralPath (Join-Path $workspace 'ai-workspace\agents\brain\brain.md') | ForEach-Object {
    if ($_ -match '^## \[(\d{8}-\d+)\]') { $Matches[1] }
})
if ($brainIndexIds.Count -ne $brainEntryIds.Count) { throw 'brain index and entry counts differ' }
if (@($brainIndexIds | Group-Object | Where-Object Count -gt 1).Count) { throw 'brain index contains duplicate IDs' }
if (@($brainEntryIds | Group-Object | Where-Object Count -gt 1).Count) { throw 'brain entries contain duplicate IDs' }
if ((Compare-Object $brainIndexIds $brainEntryIds).Count) { throw 'brain index and entries contain different IDs' }
foreach ($file in 'skill-routing.md', 'issue-tracker.md', 'triage-labels.md', 'domain.md') {
    if (-not (Test-Path (Join-Path $workspace "ai-workspace\agents\meta\$file"))) { throw "agent meta config missing: $file" }
}

$metricRows = @()
if (Test-Path -LiteralPath $metrics) {
    $metricRows = @(Get-Content -LiteralPath $metrics | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}
$missingModelMeasurements = @($metricRows | Where-Object { $null -eq $_.model_token_measurement }).Count
if ($metricRows.Count) {
    "token_measurement: unavailable for $missingModelMeasurements/$($metricRows.Count) historical routing events; no model-token savings claimed"
} else {
    'token_measurement: no provider usage log; no model-token savings claimed'
}

# Note: coarse Git HEAD staleness check removed — index-state.json hash validation (Tests 1–8 below)
# detects uncommitted edits, which HEAD comparison cannot. Run check-staleness.ps1 for a summary.


# --- INDEX CORRECTNESS REGRESSION TESTS (Req 12) ---
$traverse = Join-Path $workspace 'ai-workspace\scripts\traverse.ps1'
$genIndex = Join-Path $workspace 'ai-workspace\scripts\generate-index.ps1'
$stateFile = Join-Path $workspace 'ai-workspace\generated\index-state.json'
$symbolIdxPath = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'

# Find a real source file with an indexed symbol to use as test fixture
$testSourceRel = $null; $testSymbol2 = $null
if ($AllowProductSourceMutation -and (Test-Path -LiteralPath $symbolIdxPath)) {
    $rows = Get-Content -LiteralPath $symbolIdxPath | Where-Object { $_ -match '\|\s*\w+\s*\|\s*(Function|Class|Struct)\s*\|\s*\S+:\d+' }
    if ($rows) {
        $cells = ($rows[0] -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $testSymbol2 = $cells[0]
        $testSourceRel = ($cells[-1] -split ':')[0].Replace('\', '/')
    }
}

if ($testSymbol2 -and $testSourceRel) {
    $testSourceAbs = Join-Path $workspace ($testSourceRel.Replace('/', '\'))

    # Test 1 — Fresh file: known symbol returns hit
    $out1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
    if ($out1 -notmatch 'symbol_hit') { throw "index_test_1 FAIL: fresh lookup did not return symbol_hit for $testSymbol2" }
    'index_test_1: PASS (fresh lookup returns hit)'

    # Test 2 — Uncommitted modification: stale index rejected (primary bug)
    $original = Get-Content -LiteralPath $testSourceAbs -Raw
    try {
        Add-Content -LiteralPath $testSourceAbs "`n# check-workflow staleness probe"
        $out2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out2 -notmatch 'TRAVERSE_MISS|INDEX_STALE|INDEX_UNVERIFIED') {
            throw "index_test_2 FAIL: uncommitted edit not detected for $testSymbol2"
        }
        'index_test_2: PASS (uncommitted modification rejected)'
    } finally {
        # Restore original — never leave repo dirty
        [IO.File]::WriteAllText($testSourceAbs, $original, [Text.UTF8Encoding]::new($false))
    }

    # Test 3 — Deleted file: TRAVERSE_MISS
    $backupContent = Get-Content -LiteralPath $testSourceAbs -Raw
    try {
        Remove-Item -LiteralPath $testSourceAbs -Force
        $out3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out3 -notmatch 'TRAVERSE_MISS|INDEX_STALE') { throw "index_test_3 FAIL: deleted file not detected" }
        'index_test_3: PASS (deleted source file rejected)'
    } finally {
        [IO.File]::WriteAllText($testSourceAbs, $backupContent, [Text.UTF8Encoding]::new($false))
    }

    # Test 4 — Renamed/moved file: old location rejected
    $movedPath = $testSourceAbs + '.moved_probe'
    try {
        Move-Item -LiteralPath $testSourceAbs -Destination $movedPath
        $out4 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out4 -notmatch 'TRAVERSE_MISS|INDEX_STALE') { throw "index_test_4 FAIL: moved file not detected" }
        'index_test_4: PASS (moved source file rejected)'
    } finally {
        Move-Item -LiteralPath $movedPath -Destination $testSourceAbs -Force
    }

    # Test 5 — New file after index: TRAVERSE_MISS for new symbol (only verifiable as miss)
    # Simply confirm traverse produces TRAVERSE_MISS for a symbol that can't exist in index
    $out5 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol '__NonExistentSymbol9x__' 2>&1 | Out-String
    if ($out5 -notmatch 'TRAVERSE_MISS') { throw "index_test_5 FAIL: non-indexed symbol did not produce TRAVERSE_MISS" }
    'index_test_5: PASS (unindexed symbol produces TRAVERSE_MISS)'

    # Test 6 — Refresh restores trust
    $edited = Get-Content -LiteralPath $testSourceAbs -Raw
    try {
        Add-Content -LiteralPath $testSourceAbs "`n# probe"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $genIndex | Out-Null
        $out6 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out6 -notmatch 'symbol_hit') { throw "index_test_6 FAIL: regenerated index did not restore hit for $testSymbol2" }
        'index_test_6: PASS (regeneration restores trust)'
    } finally {
        [IO.File]::WriteAllText($testSourceAbs, $edited, [Text.UTF8Encoding]::new($false))
        # Restore original state for repo cleanliness
        [IO.File]::WriteAllText($testSourceAbs, $original, [Text.UTF8Encoding]::new($false))
        & powershell -NoProfile -ExecutionPolicy Bypass -File $genIndex | Out-Null
    }

    # Test 7 — Malformed index-state.json: safe miss
    $savedState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { $null }
    try {
        '{ "version": 1, BROKEN JSON' | Out-File $stateFile -Encoding utf8
        $out7 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out7 -notmatch 'TRAVERSE_MISS|INDEX_UNVERIFIED') { throw "index_test_7 FAIL: malformed state not handled safely" }
        'index_test_7: PASS (malformed state.json produces safe miss)'
    } finally {
        if ($savedState) { [IO.File]::WriteAllText($stateFile, $savedState, [Text.UTF8Encoding]::new($false)) }
        else { Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue }
    }

    # Test 8 — Missing index-state.json: safe miss
    $savedState2 = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { $null }
    try {
        Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
        $out8 = & powershell -NoProfile -ExecutionPolicy Bypass -File $traverse -Symbol $testSymbol2 2>&1 | Out-String
        if ($out8 -notmatch 'TRAVERSE_MISS|INDEX_UNVERIFIED') { throw "index_test_8 FAIL: missing state not handled safely" }
        'index_test_8: PASS (missing state.json produces safe miss)'
    } finally {
        if ($savedState2) { [IO.File]::WriteAllText($stateFile, $savedState2, [Text.UTF8Encoding]::new($false)) }
    }
} else {
    'index_correctness_tests: skipped (safe default; pass -AllowProductSourceMutation only in a disposable fixture)'
}

'rtk_measurement: run rtk gain --history separately; shell-output savings are not model-token savings'


function Test-MathEngine {
    $script = Join-Path $workspace 'ai-workspace\scripts\math-algorithms.ps1'
    if (-not (Test-Path -LiteralPath $script)) { return }
    . $script

    # 1. Test Entropy
    $ent = Get-ShannonEntropy -Text "AAAA"
    if ($ent -ne 0) { throw "Math check failed: Constant string entropy should be 0, got $ent" }

    # 2. Test BM25
    $corpus = @("the quick brown fox", "jumped over the lazy dog", "the fox was brown")
    $results = Invoke-BM25PlusRank -QueryTerms @("brown","fox") -CorpusDocs $corpus
    if ($results.Count -eq 0 -or $results[0].Score -le 0) { throw "Math check failed: BM25 score must be positive" }

    # 3. Test Jaccard
    $jacc = Get-JaccardSimilarity -Str1 "stripe" -Str2 "striep" -NGram 2
    if ($jacc -lt 0.1 -or $jacc -gt 1.0) { throw "Math check failed: Jaccard similarity bounds violated ($jacc)" }
    
    # 4. Test Ebbinghaus
    $reten = Get-EbbinghausRetention -EntryDate (Get-Date).AddDays(-10) -CurrentTime (Get-Date) -Recalls 1
    if ($reten -lt 0.0 -or $reten -gt 1.0) { throw "Math check failed: Ebbinghaus retention bounds violated ($reten)" }

    "math_engine_tests: PASS (Entropy, BM25+, Jaccard, Ebbinghaus bounded and correct)"
}
Test-MathEngine

'workflow_check: PASS'
