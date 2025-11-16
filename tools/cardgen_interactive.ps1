param(
  [string]$JobType,
  [string]$CardType,
  [string]$Name
)

$job  = if ($PSBoundParameters.ContainsKey('JobType') -and -not [string]::IsNullOrWhiteSpace($JobType)) { $JobType } else { Read-Host "Job Type (new/rewrite)" }
$type = if ($PSBoundParameters.ContainsKey('CardType') -and -not [string]::IsNullOrWhiteSpace($CardType)) { $CardType } else { Read-Host "Card Type (world, realm, region, biome, location, point, place-concept, concept, character, creature, faction, race, object, weapon, armor, story-object, role, class-progression, history)" }
$name = if ($PSBoundParameters.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace($Name)) { $Name } else { Read-Host "Card Name (exact title)" }

# Determine template path for the selected type so we only ask for fields present
$tplBase = '.continue/Lore Card Templates'
$templateMap = @{
  'world'             = "$tplBase/places/world.md"
  'realm'             = "$tplBase/places/realm.md"
  'region'            = "$tplBase/places/region.md"
  'biome'             = "$tplBase/places/biome.md"
  'location'          = "$tplBase/places/location.md"
  'point'             = "$tplBase/places/point.md"
  'place-concept'     = "$tplBase/places/place_concept.md"
  'concept'           = "$tplBase/concept.md"
  'character'         = "$tplBase/beings/character.md"
  'creature'          = "$tplBase/beings/creature.md"
  'faction'           = "$tplBase/beings/faction.md"
  'race'              = "$tplBase/beings/race.md"
  'object'            = "$tplBase/objects/object.md"
  'weapon'            = "$tplBase/objects/weapon.md"
  'armor'             = "$tplBase/objects/armor.md"
  'story-object'      = "$tplBase/objects/story_object.md"
  'role'              = "$tplBase/roles/class.md"
  'class-progression' = "$tplBase/roles/class_progression.md"
  'history'           = "$tplBase/history.md"
}
$templatePath = $null
if ($templateMap.ContainsKey($type)) { $templatePath = $templateMap[$type] }
$tplText = $null
if ($templatePath -and (Test-Path $templatePath)) { $tplText = Get-Content -Path $templatePath -Raw -Encoding UTF8 }
function TemplateHas([string]$label){ if (-not $tplText) { return $false } return ($tplText -match [regex]::Escape($label)) }
function TemplateHasBlock([string]$block){ if (-not $tplText) { return $false } return ($tplText -match "(?m)^\s*$([regex]::Escape($block))\s*:\s*$") }

$parent  = Read-Host "Parent id (e.g., realm:greenwood) or blank"
$seealso = Read-Host "See also ids (comma-separated) or blank"
# Only ask for Tone Keywords if present in template
$tone    = $null
if (TemplateHas('**Tone Keywords:**')) { $tone = Read-Host "Tone keywords (comma-separated) or blank" }
# Only ask for Locations of Note if present in template
$locs    = $null
if (TemplateHas('**Locations of Note:**')) { $locs = Read-Host "Locations of Note (comma-separated titles) or blank" }
# Ask for Known Links only if the template includes a Links: block
$links   = $null
if ($tplText -and ($tplText -match '(?m)^\s*Links:\s*$')) { $links = Read-Host "Known link titles (comma-separated) or blank" }
# Era/Topic bucket only for concept/history types
$bucket  = $null
if ($type -in @('history','concept')) { $bucket = Read-Host "Era/Topic bucket (History/Concept) or blank" }

# Additional template-aware prompts mapped into ExtraNotes
$extra = @{}
function Add-IfPrompted([string]$label,[string]$noteKey,[switch]$IsList){
  if (TemplateHas("**${label}:**")) {
    $prompt = if ($IsList) { "$label (comma-separated) or blank" } else { "$label (free text) or blank" }
    $resp = Read-Host $prompt
    if (-not [string]::IsNullOrWhiteSpace($resp)) {
      if ($IsList) { $extra[$noteKey] = @($resp.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
      else { $extra[$noteKey] = $resp.Trim() }
    }
  }
}

# Common extra fields across templates
Add-IfPrompted -label 'Aliases' -noteKey 'aliases' -IsList
Add-IfPrompted -label 'Local Inhabitants' -noteKey 'local_inhabitants' -IsList
Add-IfPrompted -label 'Aligned Factions' -noteKey 'aligned_factions' -IsList
Add-IfPrompted -label 'Notable Characters' -noteKey 'notable_characters' -IsList
Add-IfPrompted -label 'Primary Regions' -noteKey 'primary_regions' -IsList
Add-IfPrompted -label 'Typical Lifespan' -noteKey 'typical_lifespan'
Add-IfPrompted -label 'Stature and Build' -noteKey 'stature_and_build'

$policy  = Read-Host "Lore Policy (preserve-only/augment/create, default auto)"
$newfacts= Read-Host "New Facts Authorized (comma-separated) or blank"

# Desired summary input options
$desired = $null
 $mode = Read-Host "Desired summary input: (E)ditor, (F)rom file, (I)nline [default: I]"
if (-not [string]::IsNullOrWhiteSpace($mode)) { $mode = $mode.Trim().ToLower() } else { $mode = 'e' }

switch ($mode) {
  'f' { # From file path
    $path = Read-Host "Enter file path (.txt/.md)"
    if ([string]::IsNullOrWhiteSpace($path)) {
      Write-Host "No path provided; falling back to inline input." -ForegroundColor Yellow
      $desired = Read-Host "Desired direction/summary (single line) or blank"
    } elseif (-not (Test-Path $path)) {
      Write-Host ("File not found: {0}. Falling back to inline input." -f $path) -ForegroundColor Yellow
      $desired = Read-Host "Desired direction/summary (single line) or blank"
    } else {
      try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($content)) { $desired = $content.Trim() }
      } catch {
        Write-Host ("Failed to read file: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        $desired = Read-Host "Desired direction/summary (single line) or blank"
      }
    }
  }
  'e' { # Editor (Notepad)
    try {
      $temp = Join-Path $env:TEMP ("desired_summary_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
      New-Item -ItemType File -Path $temp -Force | Out-Null
      Write-Host ("Opening Notepad: {0}. Save and close to continue..." -f $temp) -ForegroundColor Cyan
      Start-Process -FilePath "notepad.exe" -ArgumentList $temp -Wait
      if (Test-Path $temp) {
        $content = Get-Content -Path $temp -Raw -Encoding UTF8
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($content)) { $desired = $content.Trim() }
      }
    } catch {
      Write-Host ("Failed to launch Notepad: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
      $desired = Read-Host "Desired direction/summary (single line) or blank"
    }
  }
  'i' { # Inline
    $desired = Read-Host "Desired direction/summary (single line) or blank"
  }
  Default { # Default to inline
    $desired = Read-Host "Desired direction/summary (single line) or blank"
  }
}
$model   = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { Read-Host "Model (e.g., gpt-4o-mini)" }
$key     = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { Read-Host "API Key" }

# Normalize policy to valid values; leave blank for auto if unrecognized
$policyNorm = $null
if (-not [string]::IsNullOrWhiteSpace($policy)) {
  $p = $policy.Trim().ToLower()
  $p = ($p -replace '[ _]+','-')
  switch ($p) {
    'preserve' { $policyNorm = 'preserve-only' }
    'preserve-only' { $policyNorm = 'preserve-only' }
    'preserveonly' { $policyNorm = 'preserve-only' }
    'augment' { $policyNorm = 'augment' }
    'aug' { $policyNorm = 'augment' }
    'enrich' { $policyNorm = 'augment' }
    'create' { $policyNorm = 'create' }
    'new' { $policyNorm = 'create' }
    'gen' { $policyNorm = 'create' }
    default { Write-Host "Unrecognized policy '$policy'. Leaving blank for auto-selection." -ForegroundColor Yellow }
  }
}

$params = @{
  JobType = $job
  CardType = $type
  Name = $name
  Parent = $parent
  SeeAlso = $seealso
  # Only include optional notes when prompted
  ToneKeywords = $tone
  LocationsOfNote = $locs
  KnownLinks = $links
  EraOrTopicBucket = $bucket
  NewFacts = $newfacts
  Model = $model
  ApiKey = $key
  VerbosePreview = $true
}
if ($policyNorm) { $params['LorePolicy'] = $policyNorm }
if ($desired) { $params['DesiredSummary'] = $desired }
if ($extra.Keys.Count -gt 0) { $params['ExtraNotes'] = $extra }

./tools/cardgen.ps1 @params