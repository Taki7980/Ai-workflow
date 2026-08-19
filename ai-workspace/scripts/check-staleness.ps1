# Staleness checker for incident notes
# Compares related_files blob SHAs against current repo state.
# Marks stale candidates when source has changed since last_verified_commit.
# Usage: powershell -NoProfile -File check-staleness.ps1

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$incidentDir = Join-Path $workspace 'ai-workspace\Obsidian\Incidents'
$backend = Join-Path $workspace 'backend'
$frontend = Join-Path $workspace 'frontend'

if (-not (Test-Path -LiteralPath $incidentDir)) {
    "info: no Incidents directory found."
    exit 0
}

$mdFiles = Get-ChildItem -Path $incidentDir -Filter '*.md' -Recurse -ErrorAction SilentlyContinue
if ($mdFiles.Count -eq 0) {
    "info: no incident notes found."
    exit 0
}

$staleCount = 0
$checkedCount = 0
$results = @()

foreach ($file in $mdFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -notmatch '(?s)^---\s*\n(.+?)\n---') { continue }
    $frontmatter = $matches[1]

    # Extract key fields
    $lastCommit = ''
    $relatedFiles = @()
    $status = ''
    $staleCandidate = 'false'
    $noteId = ''

    foreach ($fmLine in ($frontmatter -split "`n")) {
        if ($fmLine -match '^last_verified_commit:\s*"?(\S+)"?') { $lastCommit = $matches[1].Trim('"') }
        if ($fmLine -match '^status:\s*(\S+)') { $status = $matches[1] }
        if ($fmLine -match '^id:\s*(.+)') { $noteId = $matches[1].Trim() }
        if ($fmLine -match '^\s+-\s*"?(.+\.go|.+\.ts|.+\.tsx)"?') {
            $relatedFiles += $matches[1].Trim('"')
        }
    }

    if (-not $lastCommit -or $lastCommit -eq '' -or $relatedFiles.Count -eq 0) { continue }
    $checkedCount++

    $isStale = $false
    $changedFiles = @()

    foreach ($rf in $relatedFiles) {
        # Determine which repo this file belongs to
        $repo = ''
        $relPath = ''
        if ($rf -match '^backend/(.+)') {
            $repo = $backend
            $relPath = $matches[1]
        } elseif ($rf -match '^frontend/(.+)') {
            $repo = $frontend
            $relPath = $matches[1]
        } else { continue }

        if (-not (Test-Path "$repo\.git")) { continue }

        # Check if file has changed since last_verified_commit
        $diffOutput = & git -C $repo diff --name-only "$lastCommit" HEAD -- $relPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $diffOutput) {
            $isStale = $true
            $changedFiles += $rf
        }
    }

    if ($isStale) {
        $staleCount++
        $results += [pscustomobject]@{
            Note = $file.Name
            ID = $noteId
            Status = $status
            ChangedFiles = ($changedFiles -join ', ')
        }

        # Update stale_candidate in frontmatter if not already true
        if ($staleCandidate -ne 'true') {
            $updated = $content -replace '(stale_candidate:\s*)false', '${1}true'
            if ($updated -ne $content) {
                $updated | Set-Content -LiteralPath $file.FullName -Encoding UTF8 -NoNewline
            }
        }
    }
}

"staleness_check:"
"  checked: $checkedCount notes with related_files + last_verified_commit"
"  stale: $staleCount"
if ($results.Count -gt 0) {
    'stale_notes:'
    foreach ($r in $results) {
        "  - $($r.ID) ($($r.Note)): $($r.ChangedFiles)"
    }
}
