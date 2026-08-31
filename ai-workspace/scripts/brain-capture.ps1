param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('bug-fix','feature','pattern','decision','optimization','refactor')]
    [string]$Type,

    [Parameter(Mandatory=$true)]
    [string]$Keywords,

    [Parameter(Mandatory=$true)]
    [string]$Problem,

    [Parameter(Mandatory=$true)]
    [string]$Solution,

    [Parameter(Mandatory=$true)]
    [string]$Evidence,

    [string]$RootCause = '',
    [string]$FailedApproaches = '',
    [string]$FilesChanged = '',
    [string]$Lesson = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Evidence)) { throw 'brain capture: Evidence cannot be blank' }

# Brain Capture: Append a new memory entry to the brain
# Deterministic file append; only its compact result reaches agent context.
# Usage: powershell -NoProfile -File brain-capture.ps1 -Type bug-fix -Keywords "payment cash outstanding" -Problem "..." -Solution "..."

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$brainDir = Join-Path $workspace 'ai-workspace\agents\brain'
$indexFile = Join-Path $brainDir 'brain-index.md'
$brainFile = Join-Path $brainDir 'brain.md'

# Ensure brain directory exists
if (-not (Test-Path -LiteralPath $brainDir)) {
    New-Item -ItemType Directory -Path $brainDir -Force | Out-Null
}

# Generate entry ID: YYYYMMDD-NNN
$date = Get-Date -Format 'yyyy-MM-dd'
$datePrefix = Get-Date -Format 'yyyyMMdd'

# Use the highest existing sequence. Historical files may contain duplicate IDs;
# counting rows would keep generating collisions.
$seqNum = 1
if (Test-Path -LiteralPath $indexFile) {
    $sequences = Select-String -Path $indexFile -Pattern "^\|\s*$datePrefix-(\d+)\s*\|" | ForEach-Object {
        [int]$_.Matches[0].Groups[1].Value
    }
    if ($sequences) { $seqNum = (($sequences | Measure-Object -Maximum).Maximum + 1) }
}
# ponytail: workflow has one writer; add a file lock only if concurrent capture is introduced.
$entryId = "$datePrefix-$($seqNum.ToString('000'))"

# Initialize index file if new
if (-not (Test-Path -LiteralPath $indexFile)) {
    @(
        '# Brain Index'
        ''
        'Keyword-searchable index of all brain entries. Use brain-recall.ps1 to search.'
        ''
        '| ID | Date | Type | Keywords |'
        '|---|---|---|---|'
    ) | Set-Content -LiteralPath $indexFile -Encoding UTF8
}

# Append to index (keywords are the searchable surface - keep them dense)
$indexEntry = "| $entryId | $date | $Type | $Keywords |"
Add-Content -LiteralPath $indexFile -Value $indexEntry -Encoding UTF8

# Initialize brain file if new
if (-not (Test-Path -LiteralPath $brainFile)) {
    @(
        '# Brain - Persistent Memory'
        ''
        'Full detailed entries. Searched via brain-index.md keywords.'
        'Newest entries at the bottom.'
        ''
    ) | Set-Content -LiteralPath $brainFile -Encoding UTF8
}

# Build the full entry
$entry = @(
    ''
    "## [$entryId] $date | $Type | $Keywords"
    ''
    "**Problem**: $Problem"
    ''
    "**Solution**: $Solution"
    ''
    "**Evidence**: $Evidence"
)

if ($RootCause) {
    $entry += ''
    $entry += "**Root cause**: $RootCause"
}

if ($FailedApproaches) {
    $entry += ''
    $entry += "**Failed approaches (skip next time)**: $FailedApproaches"
}

if ($FilesChanged) {
    $entry += ''
    $entry += "**Files changed**: $FilesChanged"
}

if ($Lesson) {
    $entry += ''
    $entry += "**Lesson**: $Lesson"
}

$entry += ''
$entry += '---'

# Append to brain file
$entry | Add-Content -LiteralPath $brainFile -Encoding UTF8

"brain_captured: $entryId ($Type) - $($Keywords.Split(' ').Count) keywords indexed"
