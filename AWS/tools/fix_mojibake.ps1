param(
    [string]$Path = "Lore/Lorebook",
    [switch]$DryRun,
    [switch]$ReportOnly
)

Write-Host "Scanning '$Path' for mojibake sequences..." -ForegroundColor Cyan

function Test-Mojibake {
    param([string]$s)
    if (-not $s) { return $false }
    # Heuristics: look for codepoints commonly appearing in mojibake (Ã == U+00C3, â == U+00E2, € == U+20AC)
    return ($s -match '\u00C3' -or $s -match '\u00E2' -or $s -match '\u20AC')
}

function Get-MojibakeMatches {
    param([string]$Text)
    if (-not $Text) { return @() }
    $pattern = '(\u00C3.|\u00E2[\u0080-\u00BF]{1,2}|\u00C2[\u0080-\u00BF]|\u20AC)'
    $rx = [regex]::new($pattern)
    $lines = $Text -split "\r?\n"
    $results = @()
    for ($i=0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrEmpty($line)) { continue }
        $m = $rx.Matches($line)
        if ($m.Count -gt 0) {
            $snippet = $line
            if ($snippet.Length -gt 220) { $snippet = $snippet.Substring(0,220) + '…' }
            $results += [pscustomobject]@{ Line = $i+1; Matches = ($m.Value | Select-Object -Unique -Join ', '); Text = $snippet }
        }
    }
    return $results
}

$files = Get-ChildItem -Path $Path -Recurse -Filter '*.md'
$changed = 0
$examined = 0

foreach ($f in $files) {
    $examined++
    $orig = Get-Content -Path $f.FullName -Raw -Encoding utf8
    if ([string]::IsNullOrEmpty($orig)) { continue }
    if (-not (Test-Mojibake -s $orig)) { continue }

    if ($ReportOnly) {
        $hits = Get-MojibakeMatches -Text $orig
        if ($hits.Count -gt 0) {
            Write-Host ("File: {0}" -f $f.FullName) -ForegroundColor Cyan
            foreach ($h in $hits) {
                Write-Host ("  [L{0}] {1}" -f $h.Line, $h.Text) -ForegroundColor Yellow
                Write-Host ("       Matches: {0}" -f $h.Matches) -ForegroundColor DarkGray
            }
        }
        continue
    }

    # Attempt recode fix: treat current text as cp1252 bytes, decode as UTF-8
    try {
        $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($orig)
        $fixed = [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        continue
    }

    if ($fixed -and $fixed -ne $orig) {
        if ($DryRun) {
            Write-Host ("Would fix: {0}" -f $f.FullName) -ForegroundColor Yellow
        } else {
            Set-Content -Path $f.FullName -Value $fixed -Encoding utf8
            Write-Host ("Fixed: {0}" -f $f.FullName) -ForegroundColor Green
        }
        $changed++
    }
}

if (-not $ReportOnly) {
    Write-Host ("Examined: {0} files; Fixed: {1} files" -f $examined, $changed) -ForegroundColor Cyan
} else {
    Write-Host ("Examined: {0} files; Reported suspicious lines above." -f $examined) -ForegroundColor Cyan
}
