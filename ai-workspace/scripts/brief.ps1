param(
    [ValidateSet('planner', 'builder', 'reviewer')]
    [string]$Role = 'builder',
    [string]$Query = ''
)

$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'index-state.ps1')
. (Join-Path $PSScriptRoot 'math-algorithms.ps1')
$handoff = Join-Path $workspace '.ai\HANDOFF.md'
$research = Join-Path $workspace 'ai-workspace\agents\research.md'
$manifest = Join-Path $workspace 'ai-workspace\agents\domain-manifest.yaml'
$hotCache = Join-Path $workspace 'ai-workspace\generated\hot-cache.jsonl'
$incidentCache = Join-Path $workspace 'ai-workspace\generated\incident-cache.jsonl'
$symbolIndex = Join-Path $workspace 'ai-workspace\agents\references\symbol_index.md'
$endpointIndex = Join-Path $workspace 'ai-workspace\agents\references\endpoint_index.md'
# Compute search terms once for routing and cache lookup.
# Terms are >= 3 chars to avoid noise words.
$terms = @()
if ($Query.Trim()) {
    $terms = $Query -split '\s+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique
}

function GitValue([string]$repo, [string[]]$arguments) {
    # Repositories are owned by the workstation user while agents may run as
    # a sandbox account. Explicit safe.directory keeps routing truthful.
    $value = & git -c "safe.directory=$repo" -C $repo @arguments 2>$null
    if ($LASTEXITCODE -eq 0) { return ($value -join "`n").Trim() }
    return 'unavailable'
}

$backend = Join-Path $workspace 'backend'
$frontend = Join-Path $workspace 'frontend'

$backendHead = 'unavailable'
$frontendHead = 'unavailable'

if (Test-Path "$backend\.git") {
    $backendHead = GitValue $backend @('rev-parse', '--short=12', 'HEAD')
}
if (Test-Path "$frontend\.git") {
    $frontendHead = GitValue $frontend @('rev-parse', '--short=12', 'HEAD')
}

if ($backendHead -eq 'unavailable' -and $frontendHead -eq 'unavailable') {
    $rootHead = GitValue $workspace @('rev-parse', '--short=12', 'HEAD')
    if ($rootHead -ne 'unavailable') {
        $backendHead = $rootHead
        $frontendHead = 'n/a'
    } else {
        throw 'brief: Git metadata unavailable; refusing to route with unverified repository state'
    }
}

"role: $Role"
"workspace: $workspace"
"backend_head: $backendHead"
"frontend_head: $frontendHead"

if ($backendHead -ne 'n/a' -and (Test-Path "$backend\.git")) {
    'backend_dirty:'
    $dirty = GitValue $backend @('status', '--short')
    if ($dirty) { $dirty -split "`n" | ForEach-Object { "  $_" } } else { '  clean' }
}
if ($frontendHead -ne 'n/a' -and (Test-Path "$frontend\.git")) {
    'frontend_dirty:'
    $dirty = GitValue $frontend @('status', '--short')
    if ($dirty) { $dirty -split "`n" | ForEach-Object { "  $_" } } else { '  clean' }
}
if ($frontendHead -eq 'n/a') {
    'project_dirty:'
    $dirty = GitValue $workspace @('status', '--short')
    if ($dirty) { $dirty -split "`n" | ForEach-Object { "  $_" } } else { '  clean' }
}

if (Test-Path -LiteralPath $handoff) {
    'handoff:'
    $handoffLines = Get-Content -LiteralPath $handoff
    $handoffLines | ForEach-Object { "  $_" }
    if ($handoffLines.Count -gt 20) {
        "handoff_warning: $($handoffLines.Count) lines -- approaching 30-line cap; trim before build"
    }
}

# --- QUERY CLASSIFICATION (deterministic, zero model tokens) ---
$classification = 'ambiguous'
$matchedModule = ''
$matchedSymbol = ''
$routedFiles = @()
$hotCacheHit = $null

# $terms already computed above; reuse here.

if ($terms.Count -gt 0) {
    $queryLower = $Query.ToLower()

    # 1. Error-signature detection
    # Stack trace markers, exception names, HTTP status codes, file:line patterns
    $errorPatterns = @(
        '(?:panic|fatal|error|exception|SQLSTATE|runtime error)',
        '(?:HTTP\s*[45]\d\d|status\s*(?:code\s*)?[45]\d\d)',
        '(?:\w+\.go:\d+|\w+\.ts:\d+|\w+\.tsx:\d+)',
        '(?:nil pointer|undefined is not|cannot read propert)',
        '(?:ErrNoRows|sql\.Err|UNIQUE constraint|violates|42P01|23502|42703)',
        '(?:500 Internal|404 Not Found|401 Unauthorized|403 Forbidden|422)'
    )
    foreach ($pat in $errorPatterns) {
        if ($Query -match $pat) {
            $classification = 'error-signature'
            break
        }
    }

    # 2. Check hot-cache for error-signature match
    if ($classification -eq 'error-signature') {
        $cacheLines = @()
        foreach ($cachePath in @($hotCache, $incidentCache)) {
            if (Test-Path -LiteralPath $cachePath) {
                $cacheLines += Select-String -Path $cachePath -Pattern '.' | ForEach-Object { $_.Line }
            }
        }
        foreach ($line in $cacheLines) {
            if (-not $line.Trim()) { continue }
            $score = 0
            foreach ($term in $terms) {
                if ($line.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $score++ }
            }
            if ($score -ge 2 -or ($score -ge 1 -and $terms.Count -eq 1)) {
                $hotCacheHit = $line
                break
            }
        }
    }

    # 3. Exact symbol detection. Match complete index cells so short acronyms
    # and ordinary capitalized words cannot hit unrelated substrings.
    # Hash-validate before classifying — brief must not trust stale index rows (Req 5).
    if ($classification -eq 'ambiguous') {
        $symbolCandidates = [regex]::Matches($Query, '\b(?:use[A-Z][A-Za-z0-9]*|[A-Z][A-Za-z0-9]{2,})\b') |
            ForEach-Object { $_.Value } | Select-Object -Unique
        $indexLines = @()
        foreach ($indexPath in @($symbolIndex, $endpointIndex)) {
            if (Test-Path -LiteralPath $indexPath) { $indexLines += Get-Content -LiteralPath $indexPath }
        }
        $briefIndexState = Get-IndexState -Workspace $workspace
        foreach ($candidate in $symbolCandidates) {
            $found = @($indexLines | Where-Object {
                $cells = $_ -split '\|' | ForEach-Object { $_.Trim() }
                $cells -contains $candidate
            })
            if ($found) {
                foreach ($row in $found) {
                    $cells = $row -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                    $rel = Normalize-IndexPath ($cells[-1])
                    if ($rel -and (Test-IndexedFileFresh -State $briefIndexState -RelPath $rel -Workspace $workspace)) {
                        $classification = 'symbol-name'
                        $matchedSymbol = $candidate
                        break
                    }
                }
                if ($matchedSymbol) { break }
            }
        }
    }

    # 4. Module-name detection via manifest keywords
    if ($classification -eq 'ambiguous' -and (Test-Path -LiteralPath $manifest)) {
        # Parse YAML keywords sections (lightweight: find keyword lines under each module)
        $currentSection = ''  # backend or frontend
        $currentModule = ''
        $inKeywords = $false
        $bestScore = 0
        $bestModule = ''
        $bestSection = ''

        foreach ($mLine in (Get-Content -LiteralPath $manifest)) {
            if ($mLine -match '^(backend|frontend):') {
                $currentSection = $matches[1]
                $currentModule = ''
                $inKeywords = $false
                continue
            }
            if ($mLine -match '^\s{2}(\S[^:]+):$' -and $mLine -notmatch '^\s{2}(keywords|docs|handlers|services|domain|adapters|tests|modules|shared|routes|hot_symbols):') {
                $currentModule = $matches[1].Trim()
                $inKeywords = $false
                continue
            }
            if ($mLine -match '^\s{4}keywords:') {
                $inKeywords = $true
                continue
            }
            if ($inKeywords -and $mLine -match '^\s{6}-\s*"?(.+?)"?\s*$') {
                $keyword = $matches[1].Trim('"').Trim()
                # exact substring match in query
                if ($queryLower.Contains($keyword.ToLower())) {
                    $kwScore = $keyword.Split(' ').Count  # multi-word matches score higher
                    if ($kwScore -gt $bestScore) {
                        $bestScore = $kwScore
                        $bestModule = $currentModule
                        $bestSection = $currentSection
                    }
                }
            }
            if ($inKeywords -and $mLine -match '^\s{4}\w' -and $mLine -notmatch '^\s{6}-') {
                $inKeywords = $false
            }
        }

        if ($bestModule) {
            $classification = 'module-name'
            $matchedModule = "$bestSection/$bestModule"

            # Extract routed files from manifest for this module
            $capture = $false
            $captureSection = ''
            foreach ($mLine in (Get-Content -LiteralPath $manifest)) {
                if ($mLine -match "^\s{2}${bestModule}:" -and $captureSection -eq $bestSection) {
                    $capture = $true
                    continue
                }
                if ($mLine -match "^(backend|frontend):") {
                    $captureSection = $matches[1]
                    if ($capture) { break }
                    continue
                }
                if ($capture -and $mLine -match '^\s{2}\S' -and $mLine -notmatch "^\s{2}${bestModule}:") {
                    break
                }
                if ($capture -and $mLine -match '^\s{6}-\s*"(.+)"') {
                    $candidate = $matches[1]
                    # Only add file paths (contain / or \); hot_symbols have no path separator
                    if ($candidate -match '[/\\]') { $routedFiles += $candidate }
                }
            }
        }
    }

    # 5. Route-path detection
    if ($classification -eq 'ambiguous') {
        if ($Query -match '(?:GET|POST|PUT|DELETE|PATCH)\s+/api/' -or $Query -match '/api/v\d+/') {
            $classification = 'route-path'
        }
    }

    # Output classification
    ''
    "classification: $classification"
    if ($matchedModule) { "matched_module: $matchedModule" }
    if ($matchedSymbol) { "matched_symbol: $matchedSymbol" }
    if ($routedFiles.Count -gt 0) {
        'routed_files:'
        $routedFiles | Select-Object -First 15 | ForEach-Object { "  - $_" }
    }
    if ($hotCacheHit) {
        'hot_cache_hit:'
        "  $hotCacheHit"
    }
}

# --- RESEARCH CACHE — emit hits even when stale; label them so agent can verify only what it uses ---
if ($terms.Count -gt 0 -and (Test-Path -LiteralPath $research)) {
    $lines = Get-Content -LiteralPath $research
    $cachedBackendMatch = $lines | Select-String '^backend_head:\s*(\S+)' | Select-Object -First 1
    $cachedFrontendMatch = $lines | Select-String '^frontend_head:\s*(\S+)' | Select-Object -First 1
    $cachedBackendHead = if ($cachedBackendMatch) { $cachedBackendMatch.Matches.Groups[1].Value } else { '' }
    $cachedFrontendHead = if ($cachedFrontendMatch) { $cachedFrontendMatch.Matches.Groups[1].Value } else { '' }
    $isStale = -not ($cachedBackendHead -eq $backendHead -and $cachedFrontendHead -eq $frontendHead)
    if ($isStale) {
        'research_stale: true -- run generate-index.ps1 to refresh; research hits suppressed'
    } else {
        $resMatches = for ($index = 0; $index -lt $lines.Count; $index++) {
            $score = 0
            foreach ($term in $terms) {
                if ($lines[$index].IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $score++ }
            }
            if ($score -gt 0) {
                [pscustomobject]@{ Score = $score; LineNumber = $index + 1; Line = $lines[$index] }
            }
        }
        $topRes = $resMatches | Sort-Object @{Expression='Score';Descending=$true}, LineNumber | Select-Object -First 6
        if ($topRes) {
            'research_hits:'
            $topRes | ForEach-Object { "  L$($_.LineNumber): $($_.Line.Trim())" }
        }
    }
}

# --- BRAIN RECALL (inlined — saves a second script invocation at session start) ---
if ($terms.Count -gt 0) {
    $brainIndex = Join-Path $workspace 'ai-workspace\agents\brain\brain-index.md'
    if (Test-Path -LiteralPath $brainIndex) {
        $brainLines = Get-Content -LiteralPath $brainIndex
        $brainScored = for ($bi = 0; $bi -lt $brainLines.Count; $bi++) {
            $bl = $brainLines[$bi]
            if ($bl -notmatch '^\|.*\|$') { continue }
            if ($bl -match '^\|[-\s|]+\|$' -or $bl -match '^\|\s*ID\s*\|') { continue }
            $bs = 0
            foreach ($term in $terms) {
                if ($bl.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $bs++ }
            }
            if ($bs -gt 0) { [pscustomobject]@{ Score = $bs; Line = $bl } }
        }
        $topBrain = $brainScored | Sort-Object @{Expression='Score';Descending=$true} | Select-Object -First 3
        if ($topBrain) {
            'brain_hits: (read ai-workspace/agents/brain/brain.md section [ID] for full entry)'
            $topBrain | ForEach-Object { "  $($_.Line)" }
        }
    }
}

# --- ROUTING ADVICE ---
''
switch ($classification) {
    'error-signature' {
        if ($hotCacheHit) {
            'next: hot-cache hit found. Apply documented fix. Skip traversal.'
        } else {
            'next: no hot-cache match. Check brain_hits above, then quick-fix, then root-cause-analysis.'
        }
    }
    'module-name' {
        'next: module matched. Open only routed_files above. Use symbol-index for specific symbols.'
    }
    'route-path' {
        'next: route detected. Search endpoint_index.md first, then open matched handler.'
    }
    'symbol-name' {
        'next: symbol detected. Use symbol-index lookup. Do not grep source.'
    }
    default {
        'next: ambiguous. Use brain_hits if relevant; otherwise search only named task scope.'
    }
}

# --- NEXT-PHASE PROMPT (copy verbatim to next tool) ---
''
'--- NEXT PROMPT ---'
switch ($Role) {
    'planner' {
        'build phase: read .ai/HANDOFF.md and continue'
        '  (if plan needs refinement: reviewer role: read .ai/HANDOFF.md and refine plan)'
    }
    'builder' {
        'review phase: read .ai/HANDOFF.md and continue'
    }
    'reviewer' {
        'If verified: run ai-workspace/scripts/complete-task.ps1'
        'If findings: repair -> brief.ps1 -Role reviewer -> re-review'
        'If loop >1 repair: stop and report to user'
    }
}

# --- SESSION CAPSULE (crash recovery: next agent reads generated/last-session.md) ---
$capsuleDir = Join-Path $workspace 'ai-workspace\generated'
if (-not (Test-Path -LiteralPath $capsuleDir)) { New-Item -ItemType Directory -Force -Path $capsuleDir | Out-Null }
$capsule = Join-Path $capsuleDir 'last-session.md'
$nextPrompt = switch ($Role) {
    'planner'  { 'build phase: read .ai/HANDOFF.md and continue' }
    'builder'  { 'review phase: read .ai/HANDOFF.md and continue' }
    'reviewer' { 'If verified: run complete-task.ps1. If findings: repair -> re-review' }
    default    { '' }
}
@"
# Last Session Capsule
generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
role: $Role
query: $Query
backend_head: $backendHead
frontend_head: $frontendHead
classification: $classification
matched_module: $matchedModule
matched_symbol: $matchedSymbol
next_prompt: $nextPrompt
routed_files:
$( if ($routedFiles.Count -gt 0) { ($routedFiles | Select-Object -First 10 | ForEach-Object { "  - $_" }) -join "`n" } else { '  none' } )
"@ | Set-Content -LiteralPath $capsule -Encoding UTF8
