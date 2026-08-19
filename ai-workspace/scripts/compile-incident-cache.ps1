# Compile incident cache from Obsidian incident notes
# Scans Obsidian/Incidents/ for markdown files with frontmatter and outputs compact JSONL.
# Bridges: Obsidian (editorial truth) -> JSONL (hot lookup path)
# Usage: powershell -NoProfile -File compile-incident-cache.ps1

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$incidentDir = Join-Path $workspace 'ai-workspace\Obsidian\Incidents'
$outputDir = Join-Path $workspace 'ai-workspace\generated'
$outputFile = Join-Path $outputDir 'incident-cache.jsonl'

if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $incidentDir)) {
    "info: Incidents directory not found at $incidentDir. Creating empty cache."
    '' | Set-Content -LiteralPath $outputFile -Encoding UTF8
    exit 0
}

$mdFiles = Get-ChildItem -Path $incidentDir -Filter '*.md' -Recurse -ErrorAction SilentlyContinue

if ($mdFiles.Count -eq 0) {
    "info: no incident notes found. Creating empty cache."
    '' | Set-Content -LiteralPath $outputFile -Encoding UTF8
    exit 0
}

$jsonLines = @()

foreach ($file in $mdFiles) {
    $fileLines = @(Get-Content -LiteralPath $file.FullName)
    if ($fileLines.Count -lt 3) { continue }
    $fileLines[0] = $fileLines[0].TrimStart([char]0xFEFF)
    if ($fileLines[0].Trim() -ne '---') { continue }
    $frontmatterEnd = 0
    for ($lineIndex = 1; $lineIndex -lt $fileLines.Count; $lineIndex++) {
        if ($fileLines[$lineIndex].Trim() -eq '---') { $frontmatterEnd = $lineIndex; break }
    }
    if ($frontmatterEnd -eq 0) { continue }
    $frontmatter = $fileLines[1..($frontmatterEnd - 1)] -join "`n"
    $content = $fileLines -join "`n"
    
    # Parse frontmatter fields (simple line-by-line)
    $fields = @{}
    $currentKey = ''
    $currentList = @()
    $inList = $false
    
    foreach ($fmLine in ($frontmatter -split "`n")) {
        $fmLine = $fmLine.TrimEnd()
        
        if ($fmLine -match '^(\w[\w_-]*)\s*:\s*(.*)$') {
            # Save previous list if we were in one
            if ($inList -and $currentKey) {
                $fields[$currentKey] = $currentList
            }
            
            $currentKey = $matches[1]
            $value = $matches[2].Trim()
            
            if ($value -eq '' -or $value -eq '[]') {
                $inList = $true
                $currentList = @()
            } else {
                $inList = $false
                $fields[$currentKey] = $value.Trim('"').Trim("'")
            }
        } elseif ($inList -and $fmLine -match '^\s+-\s*(.+)$') {
            $currentList += $matches[1].Trim().Trim('"').Trim("'")
        }
    }
    if ($inList -and $currentKey) {
        $fields[$currentKey] = $currentList
    }
    # Skip if no kind or no id
    if (-not $fields['kind'] -or -not $fields['id']) { continue }
    
    # Build compact JSONL entry
    $entry = [ordered]@{
        id = $fields['id']
        kind = $fields['kind']
        status = if ($fields['status']) { $fields['status'] } else { 'unknown' }
        trust = if ($fields['trust']) { $fields['trust'] } else { 'draft' }
        title = if ($fields['title']) { $fields['title'] } else { '' }
        module = if ($fields['module']) { $fields['module'] } else { '' }
        subsystem = if ($fields['subsystem']) { $fields['subsystem'] } else { '' }
        error_signature = if ($fields['error_signature']) { $fields['error_signature'] } else { '' }
        error_signature_hash = if ($fields['error_signature_hash']) { $fields['error_signature_hash'] } else { '' }
        related_files = @($fields['related_files'] | Where-Object { $_ })
        related_tests = @($fields['related_tests'] | Where-Object { $_ })
        fix_summary = ''  # extracted from body if needed
        last_verified_commit = if ($fields['last_verified_commit']) { $fields['last_verified_commit'] } else { '' }
        stale_candidate = if ($fields['stale_candidate'] -eq 'true') { $true } else { $false }
        obsidian_note = "obsidian://open?vault=Obsidian&file=$([uri]::EscapeDataString($file.FullName.Substring($incidentDir.Length + 1).Replace('\', '/').Replace('.md', '')))"
        source_file = $file.FullName.Substring($workspace.Length + 1).Replace('\', '/')
    }
    
    # Try to extract fix summary from body
    if ($content -match '(?ms)#\s*Fix\s*\n(.+?)(?=\n#|\z)') {
        $fixText = $matches[1].Trim()
        if ($fixText.Length -gt 200) { $fixText = $fixText.Substring(0, 200) + '...' }
        $entry.fix_summary = $fixText
    }
    
    $jsonLines += ($entry | ConvertTo-Json -Compress -Depth 3)
}

if ($jsonLines.Count -gt 0) {
    $jsonLines | Set-Content -LiteralPath $outputFile -Encoding UTF8
} else {
    '' | Set-Content -LiteralPath $outputFile -Encoding UTF8 -NoNewline
}

"compiled: $($jsonLines.Count) incident notes -> $outputFile"
