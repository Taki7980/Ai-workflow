# The index is an acceleration structure, not the source of truth.
# Never return an index hit unless the referenced source file still matches
# the content snapshot used to generate that entry.

function Get-IndexState {
    param([string]$Workspace)
    $path = Join-Path $Workspace 'ai-workspace\generated\index-state.json'
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $state = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($state.version -ne 1) { return $null }  # unsupported version → safe miss
        return $state
    } catch { return $null }
}

function Normalize-IndexPath {
    param([string]$RawPath)
    # Extract relative path from file:line notation, normalize to forward slashes
    $p = ($RawPath -split ':')[0].Trim()
    return $p.Replace('\', '/')
}

function Get-CurrentFileHash {
    param([string]$AbsPath)
    try {
        $h = Get-FileHash -LiteralPath $AbsPath -Algorithm SHA256 -ErrorAction Stop
        return $h.Hash.ToUpper()
    } catch { return $null }
}

function Test-IndexedFileFresh {
    <#
    .SYNOPSIS
      Returns $true if the file at $RelPath still matches the hash in $State.
      Returns $false (safe miss) for any error, missing file, or hash mismatch.
    #>
    param(
        $State,          # result of Get-IndexState, may be $null
        [string]$RelPath,  # normalized forward-slash relative path
        [string]$Workspace
    )
    if ($null -eq $State) { return $false }
    $stored = $State.files.$RelPath
    if (-not $stored -or -not $stored.sha256) { return $false }
    # Resolve to native path for filesystem access
    $abs = Join-Path $Workspace ($RelPath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $abs)) { return $false }
    $current = Get-CurrentFileHash -AbsPath $abs
    if (-not $current) { return $false }
    return ($current -eq $stored.sha256.ToUpper())
}
