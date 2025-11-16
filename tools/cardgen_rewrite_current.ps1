param(
  [Parameter(Mandatory=$true)]
  [string]$Path
)

if (-not (Test-Path $Path)) { Write-Host "No active file to rewrite: $Path"; exit 1 }

$content = Get-Content -Path $Path -Raw
# Extract YAML frontmatter between first pair of --- lines
$fmMatch = [regex]::Match($content, '(?s)^---\s*(.*?)\s*---')
if (-not $fmMatch.Success) { Write-Host 'Frontmatter not found in current file.'; exit 1 }
$fm = $fmMatch.Groups[1].Value

$typeMatch = [regex]::Match($fm, '(?m)^\s*type:\s*([^\r\n#]+)')
$nameMatch = [regex]::Match($fm, '(?m)^\s*name:\s*(.+)$')
if (-not ($typeMatch.Success -and $nameMatch.Success)) { Write-Host 'Could not read type or name from frontmatter.'; exit 1 }

$type = $typeMatch.Groups[1].Value.Trim()
$name = $nameMatch.Groups[1].Value.Trim()

# Offer interactive rewrite first
$answer = Read-Host ("Use interactive cardgen to rewrite '{0}' ({1})? (Y/N) [Y]" -f $name, $type)
if ([string]::IsNullOrWhiteSpace($answer)) { $answer = 'Y' }
$answer = $answer.Trim().ToUpperInvariant()
if ($answer -eq 'Y' -or $answer -eq 'YES') {
  Write-Host "Launching interactive cardgen with detected Type/Name..." -ForegroundColor Cyan
  ./tools/cardgen_interactive.ps1 -JobType rewrite -CardType $type -Name $name
  exit 0
}

$policyInput = Read-Host 'Lore Policy (preserve-only/augment/create, default preserve-only)'
# Normalize common variants and typos to valid ValidateSet values
if ([string]::IsNullOrWhiteSpace($policyInput)) {
  $policy = 'preserve-only'
} else {
  $p = $policyInput.Trim().ToLower()
  $p = ($p -replace '[ _]+','-')
  switch ($p) {
    'preserve' { $policy = 'preserve-only' }
    'preserve-only' { $policy = 'preserve-only' }
    'preserveonly' { $policy = 'preserve-only' }
    'augment' { $policy = 'augment' }
    'aug' { $policy = 'augment' }
    'enrich' { $policy = 'augment' }
    'create' { $policy = 'create' }
    'new' { $policy = 'create' }
    'gen' { $policy = 'create' }
    default {
      Write-Host "Unrecognized policy '$policyInput'. Using 'preserve-only'." -ForegroundColor Yellow
      $policy = 'preserve-only'
    }
  }
}
$newfacts = Read-Host 'New Facts Authorized (comma-separated) or blank'
$model = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { Read-Host 'Model (e.g., gpt-4o-mini)' }
$key = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { Read-Host 'API Key' }

./tools/cardgen.ps1 -JobType rewrite -CardType $type -Name $name -LorePolicy $policy -NewFacts $newfacts -Model $model -ApiKey $key -VerbosePreview