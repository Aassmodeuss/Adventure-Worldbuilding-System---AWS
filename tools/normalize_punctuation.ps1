param(
    [string[]]$Paths = @('Lore/Lorebook', '.continue/Lore Card Templates'),
    [string[]]$Extensions = @('.md'),
    [switch]$DryRun,
    [switch]$ReportOnly
)

function Normalize-Text {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    # NBSP -> space
    $nbsp = [char]0x00A0
    $t = $t -replace [string]$nbsp, ' '
    # Dashes/hyphens to ASCII '-'
    $dashChars = [string]([char]0x2010) + ([char]0x2011) + ([char]0x2012) + ([char]0x2013) + ([char]0x2014) + ([char]0x2212)
    $t = [regex]::Replace($t, "[{0}]" -f [regex]::Escape($dashChars), '-')
    # Smart single/double quotes to straight
    $smartSingles = [string]([char]0x2018) + ([char]0x2019)
    $smartDoubles = [string]([char]0x201C) + ([char]0x201D)
    $t = [regex]::Replace($t, "[{0}]" -f [regex]::Escape($smartSingles), "'")
    $t = [regex]::Replace($t, "[{0}]" -f [regex]::Escape($smartDoubles), '"')
    # Prime symbols to straight equivalents
    $t = $t -replace [regex]::Escape([string]([char]0x2032)), "'"
    $t = $t -replace [regex]::Escape([string]([char]0x2033)), '"'
    # Ellipsis to three dots
    $t = $t -replace [regex]::Escape([string]([char]0x2026)), '...'
    return $t
}

function Has-TargetChars {
    param([string]$Text)
    if (-not $Text) { return $false }
    $pattern = '[\u00A0\u2010\u2011\u2012\u2013\u2014\u2212\u2018\u2019\u201C\u201D\u2032\u2033\u2026]'
    return [regex]::IsMatch($Text, $pattern)
}

$allFiles = @()
foreach ($p in $Paths) {
    if (-not (Test-Path $p)) { continue }
    $allFiles += Get-ChildItem -Path $p -Recurse -File | Where-Object { $Extensions -contains ([System.IO.Path]::GetExtension($_.FullName)) }
}

$scanned = 0
$changed = 0
$flagged = 0

foreach ($f in $allFiles) {
    $scanned++
    $orig = Get-Content -Path $f.FullName -Raw -Encoding UTF8
    if (-not $orig) { continue }
    if (-not (Has-TargetChars -Text $orig)) { continue }
    $flagged++
    if ($ReportOnly) {
        Write-Host ("Flagged: {0}" -f $f.FullName) -ForegroundColor Yellow
        continue
    }
    $norm = Normalize-Text -Text $orig
    if ($norm -ne $orig) {
        if ($DryRun) {
            Write-Host ("Would normalize: {0}" -f $f.FullName) -ForegroundColor DarkYellow
        } else {
            Set-Content -Path $f.FullName -Value $norm -Encoding UTF8
            Write-Host ("Normalized: {0}" -f $f.FullName) -ForegroundColor Green
        }
        $changed++
    }
}

if ($ReportOnly) {
    Write-Host ("Scanned: {0}; Flagged: {1}" -f $scanned, $flagged) -ForegroundColor Cyan
} else {
    Write-Host ("Scanned: {0}; Changed: {1}" -f $scanned, $changed) -ForegroundColor Cyan
}
