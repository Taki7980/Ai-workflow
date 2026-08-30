<#
.SYNOPSIS
  Zero-grep code traversal for the project. Reads index files only — never source code.
  Call this BEFORE any rg/grep. On miss, prints TRAVERSE_MISS and exit 1.
  Index candidates are hash-validated against current source before being trusted.

.PARAMETER Symbol
  Exact symbol name (function, type, hook). Looks up symbol_index.md.

.PARAMETER Endpoint
  Route fragment (e.g. "/rides/options" or "GET /api/v1"). Looks up endpoint_index.md.

.PARAMETER Err
  Error text / stack fragment. Looks up hot-cache.jsonl + incident-cache.jsonl.

.PARAMETER Module
  Domain keyword (e.g. "payment", "driver", "ride"). Looks up domain-manifest.yaml.

.PARAMETER Brain
  Space-separated keywords. Returns top-3 brain-index hits.

.PARAMETER Caller
  Symbol name. Finds callers/dependents in symbol_index.md.

.PARAMETER DebugIndex
  Emit verbose staleness details (default: compact output).

.EXAMPLE
  traverse.ps1 -Symbol UpdateRideState
  traverse.ps1 -Endpoint "/rides/options"
  traverse.ps1 -Err "nil pointer dereference"
  traverse.ps1 -Module "ride payment"
  traverse.ps1 -Brain "cash collection driver"
  traverse.ps1 -Caller "UpdateRideState"
#>
param(
    [string]$Symbol   = '',
    [string]$Endpoint = '',
    [string]$Err      = '',
    [string]$Module   = '',
    [string]$Brain    = '',
    [string]$Caller   = '',
    [switch]$DebugIndex
)

$workspace     = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$symbolIndex   = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'
$endpointIndex = Join-Path $workspace 'ai-workspace\agents\references\endpoint_index.md'
$manifest      = Join-Path $workspace 'ai-workspace\agents\domain-manifest.yaml'
$hotCache      = Join-Path $workspace 'ai-workspace\generated\hot-cache.jsonl'
$incidentCache = Join-Path $workspace 'ai-workspace\generated\incident-cache.jsonl'
$brainIndex    = Join-Path $workspace 'ai-workspace\agents\brain\brain-index.md'

# Load shared helper (Get-IndexState, Normalize-IndexPath, Test-IndexedFileFresh)
. (Join-Path $PSScriptRoot 'index-state.ps1')

$indexState = Get-IndexState -Workspace $workspace
$hit = $false

# ── Validate a set of raw index rows, return only fresh ones ───────────────────
# Hash only the candidate files — not the whole repo (Req 14).
function Select-FreshRows {
    param([string[]]$Rows, [string]$Kind)
    $valid = @(); $stale = 0
    foreach ($row in $Rows) {
        # Extract file:line from last pipe cell
        $cells = $row -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $fileCell = $cells[-1]   # last non-empty cell, e.g. "backend/ride/service.go:142"
        $rel = Normalize-IndexPath $fileCell
        if (-not $rel) { $stale++; continue }
        $fresh = Test-IndexedFileFresh -State $indexState -RelPath $rel -Workspace $workspace
        if ($fresh) {
            $valid += $row
        } else {
            $stale++
            if ($DebugIndex) {
                $reason = if ($null -eq $indexState) { 'INDEX_UNVERIFIED: no index-state.json' }
                          elseif (-not (Test-Path (Join-Path $workspace ($rel.Replace('/', '\'))))) { "INDEX_STALE: source missing: $rel" }
                          else { "INDEX_STALE: $rel" }
                "$reason" | Write-Host
            }
        }
    }
    return $valid, $stale
}

# ── Symbol lookup ──────────────────────────────────────────────────────────────
if ($Symbol) {
    if (Test-Path -LiteralPath $symbolIndex) {
        $rows = @(Get-Content -LiteralPath $symbolIndex |
                Where-Object { $_ -match '\|' -and $_ -notmatch '^[\|\s\-]+$' } |
                Where-Object {
                    ($_ -split '\|' | ForEach-Object { $_.Trim() }) -contains $Symbol
                })
        if (-not $rows) {
            # Partial match fallback
            $rows = @(Get-Content -LiteralPath $symbolIndex |
                    Where-Object { $_ -like "*$Symbol*" -and $_ -match '\|' -and $_ -notmatch '^[\|\s\-]+$' })
        }
        if ($rows) {
            $valid, $stale = Select-FreshRows -Rows ($rows | Select-Object -First 5) -Kind 'symbol'
            if ($valid) {
                "symbol_hit:"
                $valid | Select-Object -First 3 | ForEach-Object { "  $_" }
                if ($stale -gt 0) { "stale_candidates_discarded: $stale" }
                $hit = $true
            } else {
                # All candidates stale
                $rel = Normalize-IndexPath (($rows[0] -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })[-1])
                if ($null -eq $indexState) {
                    "INDEX_UNVERIFIED: $rel"
                    "TRAVERSE_MISS: index freshness could not be verified."
                } else {
                    "INDEX_STALE: $rel"
                    "TRAVERSE_MISS: stale index entry rejected; use targeted source search."
                }
                exit 1
            }
        }
    }
}

# ── Endpoint lookup ────────────────────────────────────────────────────────────
if ($Endpoint) {
    if (Test-Path -LiteralPath $endpointIndex) {
        $rows = @(Get-Content -LiteralPath $endpointIndex |
                Where-Object { $_ -like "*$Endpoint*" -and $_ -match '\|' -and $_ -notmatch '^[\|\s\-]+$' })
        if ($rows) {
            $valid, $stale = Select-FreshRows -Rows ($rows | Select-Object -First 7) -Kind 'endpoint'
            if ($valid) {
                "endpoint_hit:"
                $valid | Select-Object -First 5 | ForEach-Object { "  $_" }
                if ($stale -gt 0) { "stale_candidates_discarded: $stale" }
                $hit = $true
            } else {
                $rel = Normalize-IndexPath (($rows[0] -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })[-1])
                if ($null -eq $indexState) {
                    "INDEX_UNVERIFIED: $rel"
                    "TRAVERSE_MISS: index freshness could not be verified."
                } else {
                    "INDEX_STALE: $rel"
                    "TRAVERSE_MISS: stale index entry rejected; use targeted source search."
                }
                exit 1
            }
        }
    }
}

# ── Error/hot-cache lookup ─────────────────────────────────────────────────────
# Caches are historical knowledge, not navigational indexes — no hash validation needed (Req 16).
if ($Err) {
    $terms = $Err -split '\s+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique
    $cacheLines = @()
    foreach ($cachePath in @($hotCache, $incidentCache)) {
        if (Test-Path -LiteralPath $cachePath) { $cacheLines += Get-Content -LiteralPath $cachePath }
    }
    $scored = foreach ($line in $cacheLines) {
        if (-not $line.Trim()) { continue }
        $score = 0
        foreach ($t in $terms) {
            if ($line.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $score++ }
        }
        if ($score -ge 1) { [pscustomobject]@{ Score = $score; Line = $line } }
    }
    $top = $scored | Sort-Object @{Expression='Score';Descending=$true} | Select-Object -First 2
    if ($top) {
        "error_cache_hit:"
        $top | ForEach-Object { "  [$($_.Score) terms] $($_.Line.Substring(0, [Math]::Min(200,$_.Line.Length)))" }
        $hit = $true
    }
}

# ── Module lookup ──────────────────────────────────────────────────────────────
# Module manifest routes to directories, not specific files — no per-file hash needed (Req 16).
if ($Module) {
    if (Test-Path -LiteralPath $manifest) {
        $queryLower  = $Module.ToLower()
        $currentSection = ''; $currentModule = ''; $inKeywords = $false
        $bestScore = 0; $bestModule = ''; $bestSection = ''

        foreach ($mLine in (Get-Content -LiteralPath $manifest)) {
            if ($mLine -match '^(backend|frontend):') { $currentSection = $Matches[1]; $currentModule = ''; $inKeywords = $false; continue }
            if ($mLine -match '^\s{2}(\S[^:]+):$' -and $mLine -notmatch '^\s{2}(keywords|docs|handlers|services|domain|adapters|tests|modules|shared|routes|hot_symbols):') {
                $currentModule = $Matches[1].Trim(); $inKeywords = $false; continue
            }
            if ($mLine -match '^\s{4}keywords:') { $inKeywords = $true; continue }
            if ($inKeywords -and $mLine -match '^\s{6}-\s*"?(.+?)"?\s*$') {
                $kw = $Matches[1].Trim('"').Trim()
                if ($queryLower.Contains($kw.ToLower())) {
                    $kwScore = $kw.Split(' ').Count
                    if ($kwScore -gt $bestScore) { $bestScore = $kwScore; $bestModule = $currentModule; $bestSection = $currentSection }
                }
            }
            if ($inKeywords -and $mLine -match '^\s{4}\w' -and $mLine -notmatch '^\s{6}-') { $inKeywords = $false }
        }

        if ($bestModule) {
            "module_hit: $bestSection/$bestModule"
            $capture = $false; $captureSection = ''
            foreach ($mLine in (Get-Content -LiteralPath $manifest)) {
                if ($mLine -match "^(backend|frontend):") { $captureSection = $Matches[1]; if ($capture) { break }; continue }
                if ($mLine -match "^\s{2}${bestModule}:$" -and $captureSection -eq $bestSection) { $capture = $true; continue }
                if ($capture -and $mLine -match '^\s{2}\S' -and $mLine -notmatch "^\s{2}${bestModule}:") { break }
                if ($capture -and $mLine -match '^\s{6}-\s*"(.+)"') {
                    $candidate = $Matches[1]
                    if ($candidate -match '[/\\]') { "  file: $candidate" }
                }
            }
            $hit = $true
        }
    }
}

# ── Brain lookup ───────────────────────────────────────────────────────────────
# Brain is historical knowledge — no hash validation (Req 16).
if ($Brain) {
    $terms = $Brain -split '\s+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique
    if (Test-Path -LiteralPath $brainIndex) {
        $brainLines = Get-Content -LiteralPath $brainIndex
        $scored = foreach ($bl in $brainLines) {
            if ($bl -notmatch '^\|.*\|$') { continue }
            if ($bl -match '^\|[-\s|]+\|$' -or $bl -match '^\|\s*ID\s*\|') { continue }
            $bs = 0
            foreach ($t in $terms) { if ($bl.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $bs++ } }
            if ($bs -gt 0) { [pscustomobject]@{ Score = $bs; Line = $bl } }
        }
        $top = $scored | Sort-Object @{Expression='Score';Descending=$true} | Select-Object -First 3
        if ($top) {
            "brain_hit: (read ai-workspace/agents/brain/brain.md [ID] for full entry)"
            $top | ForEach-Object { "  $($_.Line)" }
            $hit = $true
        }
    }
}

# ── Caller lookup ──────────────────────────────────────────────────────────────
if ($Caller) {
    $callerRows = @()
    if (Test-Path -LiteralPath $symbolIndex) {
        $callerRows += Get-Content -LiteralPath $symbolIndex |
            Where-Object { $_ -like "*$Caller*" -and $_ -match '\|' -and $_ -notmatch '^[\|\s\-]+$' }
    }
    if (Test-Path -LiteralPath $endpointIndex) {
        $callerRows += Get-Content -LiteralPath $endpointIndex |
            Where-Object { $_ -like "*$Caller*" -and $_ -match '\|' -and $_ -notmatch '^[\|\s\-]+$' }
    }
    if ($callerRows.Count -gt 0) {
        $valid, $stale = Select-FreshRows -Rows ($callerRows | Select-Object -First 7) -Kind 'caller'
        if ($valid) {
            "caller_hit: rows referencing '$Caller' (check handler/service column for callers)"
            $valid | Select-Object -First 5 | ForEach-Object { "  $_" }
            if ($stale -gt 0) { "stale_candidates_discarded: $stale" }
            $hit = $true
        }
    }
}

# ── Miss ───────────────────────────────────────────────────────────────────────
if (-not $hit) {
    "TRAVERSE_MISS: no index hit for query. Use targeted rg next."
    exit 1
}
