<#
.SYNOPSIS
  setup.ps1 — one-shot bootstrap. Run ONCE after copying this template into your project.
  Fills placeholders, generates indexes, verifies workflow integrity.

.PARAMETER ProjectName
  Human-readable project name (replaces {{PROJECT_NAME}} everywhere).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File ai-workspace/scripts/setup.ps1 -ProjectName "MyApp"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

"setup: configuring '$ProjectName' at $workspace"

# ── 1. Write PROJECT file ──────────────────────────────────────────────────────
$projectFile = Join-Path $workspace '.ai\PROJECT'
$workspace | Set-Content -LiteralPath $projectFile -Encoding UTF8
"setup: .ai/PROJECT -> $workspace"

# ── 2. Replace {{PROJECT_NAME}} placeholders ───────────────────────────────────
$targets = @(
    (Join-Path $workspace '.ai\HANDOFF.md'),
    (Join-Path $workspace 'AGENTS.md')
)
foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { continue }
    $content = Get-Content -LiteralPath $t -Raw
    $updated = $content.Replace('{{PROJECT_NAME}}', $ProjectName)
    if ($updated -ne $content) {
        [IO.File]::WriteAllText($t, $updated, [Text.UTF8Encoding]::new($false))
        "setup: filled {{PROJECT_NAME}} in $(Split-Path $t -Leaf)"
    }
}

# ── 3. Replace {{USERNAME}} in AGENTS.md ──────────────────────────────────────
$agentsMd = Join-Path $workspace 'AGENTS.md'
if (Test-Path -LiteralPath $agentsMd) {
    $content = Get-Content -LiteralPath $agentsMd -Raw
    $updated = $content.Replace('{{USERNAME}}', $env:USERNAME)
    if ($updated -ne $content) {
        [IO.File]::WriteAllText($agentsMd, $updated, [Text.UTF8Encoding]::new($false))
        "setup: filled {{USERNAME}} -> $env:USERNAME in AGENTS.md"
    }
}

# ── 4. Generate indexes ────────────────────────────────────────────────────────
"setup: generating symbol + endpoint indexes..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'ai-workspace\scripts\generate-index.ps1')

# ── 5. Run workflow integrity check ───────────────────────────────────────────
"setup: verifying workflow..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'ai-workspace\scripts\check-workflow.ps1')

""
"setup: DONE. Next steps:"
"  1. Fill ai-workspace/agents/conventions.md  (stack + commands)"
"  2. Fill ai-workspace/agents/domain-manifest.yaml  (module keywords -> files)"
"     OR: paste the AI Bootstrapper Prompt from README into your AI agent to do steps 1+2 automatically."
"  3. Run: brief.ps1 -Role planner -Query 'your first task'"

