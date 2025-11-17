param(
    [string]$Root = 'Lore/Lorebook',
    [switch]$Apply,
    [switch]$Aggressive,
    [string[]]$Include = @('*.md'),
    [string[]]$Exclude = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Root)) {
    Write-Host "Root not found: $Root" -ForegroundColor Yellow
    exit 1
}

# Define replacement tiers
$safeReplacements = @(
    @{ pattern = 'headings/fields'; replacement = 'Card Fields'; isRegex = $false },
    @{ pattern = 'headings and fields'; replacement = 'Card Fields'; isRegex = $false },
    @{ pattern = 'fields present'; replacement = 'Card Fields present'; isRegex = $false }
)

$aggressiveReplacements = @(
    # Enable with -Aggressive; broader language alignment that may affect prose
    @{ pattern = '\bPlace Concept\b'; replacement = 'Place Feature'; isRegex = $true }
)

$replacements = @($safeReplacements)
if ($Aggressive) { $replacements += $aggressiveReplacements }

# Gather files
$incl = if ($Include -and $Include.Count -gt 0) { $Include } else { @('*.md') }
$files = Get-ChildItem -Path $Root -Recurse -File -Include $incl | Where-Object {
    $ok = $true
    foreach ($ex in $Exclude) { if ([IO.Path]::GetFileName($_.FullName) -like $ex) { $ok = $false; break } }
    $ok
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No files found under $Root with include patterns: $($incl -join ', ')" -ForegroundColor Yellow
    exit 0
}

$changed = 0
$scanned = 0

foreach ($f in $files) {
    $scanned++
    $raw = Get-Content -Path $f.FullName -Raw
    $orig = $raw

    foreach ($rep in $replacements) {
        if ($rep.isRegex) {
            $raw = [regex]::Replace($raw, $rep.pattern, $rep.replacement)
        } else {
            $raw = $raw -replace [regex]::Escape($rep.pattern), [System.Text.RegularExpressions.Regex]::Escape($rep.replacement).Replace('\\','\\')
            # Correct double-escaped backslashes in replacement
            $raw = $raw -replace '\\\\', '\\'
        }
    }

    if ($raw -ne $orig) {
        $changed++
        Write-Host ("Would update: {0}" -f $f.FullName) -ForegroundColor Cyan
        if ($Apply) {
            Set-Content -Path $f.FullName -Value $raw -Encoding UTF8
            Write-Host ("Applied: {0}" -f $f.FullName) -ForegroundColor Green
        }
    }
}

if ($Apply) {
    Write-Host ("Harmonization complete. Files changed: {0}/{1}" -f $changed, $scanned) -ForegroundColor Green
} else {
    Write-Host ("Dry-run complete. Files that would change: {0}/{1}" -f $changed, $scanned) -ForegroundColor Yellow
    Write-Host "Re-run with -Apply to write changes. Add -Aggressive to include broader wording (e.g., 'Place Concept' -> 'Place Feature')." -ForegroundColor DarkYellow
}
