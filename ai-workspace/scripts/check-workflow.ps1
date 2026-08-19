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
$symbolOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $brief -Role reviewer -Query 'GetRideOptions' | Out-String
if ($symbolOutput -notmatch 'classification: symbol-name' -or $symbolOutput -notmatch 'matched_symbol: GetRideOptions') { throw 'brief exact-symbol routing failed' }
if (-not (Test-Path (Join-Path $workspace '.agents\workflows\small.md'))) { throw 'small-task workflow missing' }
foreach ($adapter in 'AGENTS.md', 'GEMINI.md', 'RTK.md') {
    $path = Join-Path $workspace $adapter
    if (-not (Test-Path -LiteralPath $path)) { throw "project adapter missing: $adapter" }
    if ((Get-Content -LiteralPath $path).Count -gt 15) { throw "project adapter too large (>15 lines): $adapter" }
}
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

# --- INDEX STALENESS CHECK ---
$symbolIdx   = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'
$endpointIdx = Join-Path $workspace 'ai-workspace\agents\references\endpoint_index.md'
$beHead = (git -c "safe.directory=$(Join-Path $workspace 'backend')" -C (Join-Path $workspace 'backend') rev-parse --short=12 HEAD 2>$null)
$feHead = (git -c "safe.directory=$(Join-Path $workspace 'frontend')" -C (Join-Path $workspace 'frontend') rev-parse --short=12 HEAD 2>$null)
$rootHead = ''
if (-not $beHead -and -not $feHead) {
    $rootHead = (git -c "safe.directory=$workspace" -C $workspace rev-parse --short=12 HEAD 2>$null)
}
foreach ($idxPath in @($symbolIdx, $endpointIdx)) {
    if (Test-Path -LiteralPath $idxPath) {
        $idxContent = Get-Content -LiteralPath $idxPath -Raw
        $idxBe = if ($idxContent -match 'Backend HEAD:\s*(\S+)') { $Matches[1] } else { '' }
        $idxFe = if ($idxContent -match 'Frontend HEAD:\s*(\S+)') { $Matches[1] } else { '' }
        $name = [IO.Path]::GetFileName($idxPath)
        if ($beHead -and $idxBe -and -not $idxBe.StartsWith($beHead.Substring(0,[Math]::Min(12,$beHead.Length)))) {
            "index_stale: $name backend HEAD mismatch -- run generate-index.ps1"
        } elseif ($feHead -and $idxFe -and -not $idxFe.StartsWith($feHead.Substring(0,[Math]::Min(12,$feHead.Length)))) {
            "index_stale: $name frontend HEAD mismatch -- run generate-index.ps1"
        } elseif ($rootHead -and $idxBe -and -not $idxBe.StartsWith($rootHead.Substring(0,[Math]::Min(12,$rootHead.Length)))) {
            "index_stale: $name project HEAD mismatch -- run generate-index.ps1"
        } else {
            "index_fresh: $name"
        }
    }
}

'rtk_measurement: run rtk gain --history separately; shell-output savings are not model-token savings'

'workflow_check: PASS'
