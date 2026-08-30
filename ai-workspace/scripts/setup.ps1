param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

& (Join-Path $PSScriptRoot 'generate-diff-brief.ps1') -ProjectName $ProjectName
