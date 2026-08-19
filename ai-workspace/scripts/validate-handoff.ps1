<#
.SYNOPSIS
  Pre-task HANDOFF validator. Run BEFORE starting build phase.
  Fails fast on missing fields, line-cap breach, or placeholder text.
  Also checks index freshness so agents don't traverse stale data.

.EXAMPLE
  powershell -File ai-workspace/scripts/validate-handoff.ps1
  powershell -File ai-workspace/scripts/validate-handoff.ps1 -Fix  # show template
#>
param([switch]$Fix)

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$handoff   = Join-Path $workspace '.ai\HANDOFF.md'
$symbolIdx = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'
$epIdx     = Join-Path $workspace 'ai-workspace\agents\references\endpoint_index.md'

if ($Fix) {
    "--- HANDOFF TEMPLATE ---"
    Get-Content -LiteralPath (Join-Path $workspace 'ai-workspace\templates\handoff-template.md')
    exit 0
}

$pass = $true

# ── File existence ──────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $handoff)) {
    "HANDOFF_FAIL: .ai/HANDOFF.md not found"
    $pass = $false
} else {
    $lines = Get-Content -LiteralPath $handoff
    $text  = $lines -join "`n"

    # ── Line cap ────────────────────────────────────────────────────────────────
    if ($lines.Count -gt 30) {
        "HANDOFF_FAIL: $($lines.Count) lines -- cap is 30; trim before proceeding"
        $pass = $false
    } elseif ($lines.Count -gt 20) {
        "HANDOFF_WARN: $($lines.Count) lines -- approaching 30-line cap"
    }

    # ── Required fields ─────────────────────────────────────────────────────────
    $required = @('Goal / state', 'Changed files', 'Checks', 'Blockers', 'Exact next step')
    foreach ($field in $required) {
        if ($text -notmatch [regex]::Escape($field)) {
            "HANDOFF_FAIL: missing required field '$field'"
            $pass = $false
        }
    }

    # ── Placeholder detection ───────────────────────────────────────────────────
    $placeholders = @('\[what you are', '\[file:line', '\[numbered list', '\[list every', '\[one sentence')
    foreach ($ph in $placeholders) {
        if ($text -match $ph) {
            "HANDOFF_FAIL: unfilled placeholder detected -- replace all [...] fields"
            $pass = $false
            break
        }
    }

    # ── Blockers field sanity ────────────────────────────────────────────────────
    if ($text -match 'Blockers.*TBD') {
        "HANDOFF_WARN: Blockers contains TBD -- resolve or document before build"
    }
}

# ── Index freshness ─────────────────────────────────────────────────────────────
function Get-RepoHead([string]$repo) {
    if (Test-Path "$repo\.git") {
        $v = git -c "safe.directory=$repo" -C $repo rev-parse --short=12 HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { return $v }
    }
    return ''
}
$beHead = Get-RepoHead (Join-Path $workspace 'backend')
$feHead = Get-RepoHead (Join-Path $workspace 'frontend')
$rootHead = ''
if (-not $beHead -and -not $feHead) {
    $rootHead = Get-RepoHead $workspace
}

foreach ($idxPath in @($symbolIdx, $epIdx)) {
    if (Test-Path -LiteralPath $idxPath) {
        $c    = Get-Content -LiteralPath $idxPath -Raw
        $idxBe = if ($c -match 'Backend HEAD:\s*(\S+)')  { $Matches[1] } else { '' }
        $idxFe = if ($c -match 'Frontend HEAD:\s*(\S+)') { $Matches[1] } else { '' }
        $name  = [IO.Path]::GetFileName($idxPath)
        $stale = $false
        if ($beHead -and $idxBe -and -not $idxBe.StartsWith($beHead.Substring(0, [Math]::Min(12,$beHead.Length)))) { $stale = $true }
        elseif ($feHead -and $idxFe -and -not $idxFe.StartsWith($feHead.Substring(0, [Math]::Min(12,$feHead.Length)))) { $stale = $true }
        elseif ($rootHead -and $idxBe -and -not $idxBe.StartsWith($rootHead.Substring(0, [Math]::Min(12,$rootHead.Length)))) { $stale = $true }
        if ($stale) { "INDEX_WARN: $name is stale -- run generate-index.ps1 before traversal" }
        else        { "index_ok: $name" }
    }
}

# ── Result ──────────────────────────────────────────────────────────────────────
if ($pass) {
    'HANDOFF_VALID: all required fields present, line cap ok'
} else {
    "Run: powershell -File ai-workspace/scripts/validate-handoff.ps1 -Fix  to see template"
    exit 1
}
