param(
    [switch]$ValidateOnly,
    [ValidateSet('bug-fix','feature','pattern','decision','optimization','refactor')]
    [string]$Type,
    [string]$Keywords,
    [string]$Problem,
    [string]$Solution,
    [string]$RootCause = '',
    [string]$FailedApproaches = '',
    [string]$FilesChanged = '',
    [string]$Lesson = '',
    [string]$IncidentPath = '',
    [string]$VerifiedCommit = ''
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$handoff = Join-Path $workspace '.ai\HANDOFF.md'
$capture = Join-Path $workspace 'ai-workspace\scripts\brain-capture.ps1'
$compileIncidents = Join-Path $workspace 'ai-workspace\scripts\compile-incident-cache.ps1'

$handoffLines = @(Get-Content -LiteralPath $handoff)
$handoffText = $handoffLines -join "`n"
if ($handoffLines.Count -gt 30) { throw 'completion: HANDOFF exceeds 30 lines' }
foreach ($field in 'Goal / state', 'Changed files', 'Checks', 'Blockers', 'Exact next step') {
    if ($handoffText -notmatch [regex]::Escape($field)) { throw "completion: HANDOFF missing $field" }
}

$captureRequested = [bool]($Type -or $Keywords -or $Problem -or $Solution -or $Lesson)
if ($captureRequested) {
    foreach ($field in 'Type', 'Keywords', 'Problem', 'Solution', 'Lesson') {
        if (-not (Get-Variable -Name $field -ValueOnly)) { throw "completion: capture missing $field" }
    }
}

$incidentRequested = [bool]($IncidentPath -or $VerifiedCommit)
$incidentFile = $null
$incidentDestination = $null
$incidentContent = ''
if ($incidentRequested) {
    if (-not $IncidentPath -or -not $VerifiedCommit) { throw 'completion: incident requires IncidentPath and VerifiedCommit' }
    $openRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'ai-workspace\Obsidian\Incidents\Open')) + [IO.Path]::DirectorySeparatorChar
    $incidentFile = [IO.Path]::GetFullPath((Join-Path $workspace $IncidentPath))
    if (-not $incidentFile.StartsWith($openRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($incidentFile) -ne '.md') {
        throw 'completion: incident must be a Markdown file under Obsidian/Incidents/Open'
    }
    if (-not (Test-Path -LiteralPath $incidentFile)) { throw "completion: incident not found: $IncidentPath" }
    $incidentContent = Get-Content -LiteralPath $incidentFile -Raw
    if ($incidentContent -notmatch '(?m)^status:\s*open\s*$') { throw 'completion: incident is not open' }
    $resolvedRoot = Join-Path $workspace 'ai-workspace\Obsidian\Incidents\Resolved'
    $incidentDestination = Join-Path $resolvedRoot ([IO.Path]::GetFileName($incidentFile))
    if (Test-Path -LiteralPath $incidentDestination) { throw 'completion: resolved incident destination already exists' }
}

if ($ValidateOnly) {
    'completion_check: PASS'
    exit 0
}

if ($captureRequested) {
    $captureArgs = @{
        Type = $Type; Keywords = $Keywords; Problem = $Problem; Solution = $Solution; Lesson = $Lesson
        RootCause = $RootCause; FailedApproaches = $FailedApproaches; FilesChanged = $FilesChanged
    }
    & $capture @captureArgs
}

if ($incidentRequested) {
    $today = Get-Date -Format 'yyyy-MM-dd'
    $incidentContent = $incidentContent -replace '(?m)^status:[ \t]*open[ \t]*$', 'status: resolved'
    $incidentContent = $incidentContent -replace '(?m)^trust:[ \t]*[^\r\n]*$', 'trust: verified'
    $incidentContent = $incidentContent -replace '(?m)^reviewed:[ \t]*[^\r\n]*$', "reviewed: $today"
    $incidentContent = $incidentContent -replace '(?m)^last_verified_commit:[ \t]*[^\r\n]*$', "last_verified_commit: $VerifiedCommit"
    Move-Item -LiteralPath $incidentFile -Destination $incidentDestination
    [IO.File]::WriteAllText($incidentDestination, $incidentContent, [Text.UTF8Encoding]::new($false))
    & $compileIncidents
    "incident_resolved: $([IO.Path]::GetFileName($incidentDestination))"
}

if (-not $captureRequested -and -not $incidentRequested) { 'task_completion: no reusable capture' }

# ── INDEX REFRESH ────────────────────────────────────────────────────────────────
# Refresh after verified task completion so next lookup uses fresh index (Req 8/9).
# Runs last — existing correct index preserved if refresh fails.
$genIdx = Join-Path $workspace 'ai-workspace\scripts\generate-index.ps1'
if (Test-Path -LiteralPath $genIdx) {
    try {
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $genIdx -Incremental | Out-String
        "index_refresh: $($result.Trim())"
    } catch {
        "index_refresh_warning: incremental refresh failed -- existing index preserved. Run generate-index.ps1 manually."
    }
} else {
    'index_refresh_warning: generate-index.ps1 not found; index not refreshed'
}
