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

$policyInput = Read-Host 'Canon Adherence (strict/flexible/creative; s/f/c) [auto]'
# Normalize inputs to internal policy values (preserve-only/augment/create); leave $policy $null for auto
if ([string]::IsNullOrWhiteSpace($policyInput)) {
  $policy = $null
} else {
  $p = $policyInput.Trim().ToLower()
  $p = ($p -replace '[ _]+','-')
  switch ($p) {
    # strict
    's' { $policy = 'preserve-only' }
    'strict' { $policy = 'preserve-only' }
    'preserve' { $policy = 'preserve-only' }
    'preserve-only' { $policy = 'preserve-only' }
    'preserveonly' { $policy = 'preserve-only' }
    # flexible
    'f' { $policy = 'augment' }
    'flex' { $policy = 'augment' }
    'flexible' { $policy = 'augment' }
    'augment' { $policy = 'augment' }
    'aug' { $policy = 'augment' }
    'enrich' { $policy = 'augment' }
    # creative
    'c' { $policy = 'create' }
    'creative' { $policy = 'create' }
    'create' { $policy = 'create' }
    'new' { $policy = 'create' }
    'gen' { $policy = 'create' }
    default {
      Write-Host "Unrecognized value '$policyInput'. Leaving blank for auto-selection." -ForegroundColor Yellow
      $policy = $null
    }
  }
}
$newfacts = Read-Host 'New Facts Authorized (comma-separated) or blank'
$model = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { Read-Host 'Model (e.g., gpt-4o-mini)' }
$key = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { Read-Host 'API Key' }

$params = @{
  JobType = 'rewrite'
  CardType = $type
  Name = $name
  NewFacts = $newfacts
  Model = $model
  ApiKey = $key
  VerbosePreview = $true
}
if ($policy) { $params['CanonAdherence'] = $policy }
./tools/cardgen.ps1 @params