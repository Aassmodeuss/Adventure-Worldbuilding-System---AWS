param(
    [Parameter(Mandatory=$true)][string]$CardPath,
    [Parameter(Mandatory=$true)][ValidateSet('world','realm','region','biome','location','point','place-concept','place-feature','concept','character','creature','faction','race','object','weapon','armor','story-object','role','class-progression','history')][string]$CardType,
    [Parameter(Mandatory=$true)][string[]]$Fields,
    [string]$Model = $env:OPENAI_MODEL,
    [string]$ApiKey = $env:OPENAI_API_KEY,
    [string]$FallbackModel = $env:OPENAI_FALLBACK_MODEL,
    [switch]$VerboseRaw,
    [hashtable]$Hints,
    [string]$HintPairs,
    [switch]$ForceChat,
    [switch]$StripExisting,
    [switch]$DryRun
)

if (-not (Test-Path $CardPath)) { throw "CardPath not found: $CardPath" }
$rawCard = Get-Content -Path $CardPath -Raw

# Parse HintPairs into Hints hashtable if provided and Hints not directly supplied
if (-not $Hints -and $HintPairs) {
    $Hints = @{}
    $pairs = $HintPairs -split '\|\|'
    foreach ($pair in $pairs) {
        if (-not $pair) { continue }
        $kv = $pair.Split('=',2)
        if ($kv.Count -eq 2) {
            $k = $kv[0].Trim().ToLowerInvariant() -replace '[^a-z0-9_]+','_'
            $v = $kv[1].Trim()
            if ($k -and $v) { $Hints[$k] = $v }
        }
    }
}

function ConvertTo-SafeText { param([string]$Text) if (-not $Text) { return $Text }; $Text -replace '[\u0000-\u001F]',' ' }
function ConvertTo-UnicodeEscaped { param([string]$Text); if (-not $Text) { return $Text }; $sb=New-Object System.Text.StringBuilder; foreach($ch in $Text.ToCharArray()){ $code=[int][char]$ch; if($code -gt 127){ [void]$sb.AppendFormat("\\u{0:x4}",$code) } else { [void]$sb.Append($ch) } }; $sb.ToString() }
function Convert-OutputText { param([string]$Text); if (-not $Text){return $Text}; $nbsp=[char]0x00A0; $t=$Text -replace [string]$nbsp,' '; $dashChars=[string]([char]0x2013)+([char]0x2014)+([char]0x2212)+([char]0x2011); $pattern="[{0}]" -f [regex]::Escape($dashChars); $t=[regex]::Replace($t,$pattern,'-'); $smartSingles=[string]([char]0x2018)+([char]0x2019); $smartDoubles=[string]([char]0x201C)+([char]0x201D); $t=[regex]::Replace($t,"[{0}]" -f [regex]::Escape($smartSingles),"'"); $t=[regex]::Replace($t,"[{0}]" -f [regex]::Escape($smartDoubles),'"'); $t -replace [regex]::Escape([string]([char]0x2032)),'"' }
function Invoke-DedupArrayPreserveOrder { param([object]$Val); $arr=@(); if ($Val -is [System.Array]) { $arr=$Val } elseif ($Val) { $arr=@("$Val") } else { return @() }; $seen=New-Object 'System.Collections.Generic.HashSet[string]'; $out=@(); foreach($item in $arr){ if (-not $item){continue}; $norm=("$item").Trim(); if($norm -eq ''){continue}; $ci=$norm.ToLowerInvariant(); if($seen.Contains($ci)){continue}; $seen.Add($ci)|Out-Null; $out+=$norm }; ,$out }

function Test-ResponsesApi { param([string]$ModelName) if (-not $ModelName) { return $false }; return ($ModelName -match '^(gpt-4\.1|gpt-4o)') }

function Get-PackPaths { param([string]$Type)
    $tplBase = '.continue/Lore Card Templates'
    $prmBase = '.continue/prompts'
    $map = @{ 'world'=@{template="$tplBase/places/world.md";prompt="$prmBase/Writing Style for World Cards.md"};
        'realm'=@{template="$tplBase/places/realm.md";prompt="$prmBase/Writing Style for Realm Cards.md"};
        'region'=@{template="$tplBase/places/region.md";prompt="$prmBase/Writing Style for Region Cards.md"};
        'biome'=@{template="$tplBase/places/biome.md";prompt="$prmBase/Writing Style for Biome Cards.md"};
        'location'=@{template="$tplBase/places/location.md";prompt="$prmBase/Writing Style for Location Cards.md"};
        'point'=@{template="$tplBase/places/point.md";prompt="$prmBase/Writing Style for Point Cards.md"};
        'place-concept'=@{template="$tplBase/places/place_concept.md";prompt="$prmBase/Writing Style for Place Feature Cards.md"};
        'place-feature'=@{template="$tplBase/places/place_feature.md";prompt="$prmBase/Writing Style for Place Feature Cards.md"};
        'concept'=@{template="$tplBase/concept.md";prompt="$prmBase/Writing Style for Concept Cards.md"};
        'character'=@{template="$tplBase/beings/character.md";prompt="$prmBase/Writing Style for Character Cards.md"};
        'creature'=@{template="$tplBase/beings/creature.md";prompt="$prmBase/Writing Style for Creature Cards.md"};
        'faction'=@{template="$tplBase/beings/faction.md";prompt="$prmBase/Writing Style for Faction Cards.md"};
        'race'=@{template="$tplBase/beings/race.md";prompt="$prmBase/Writing Style for Race Cards.md"};
        'object'=@{template="$tplBase/objects/object.md";prompt="$prmBase/Writing Style for Object Cards.md"};
        'weapon'=@{template="$tplBase/objects/weapon.md";prompt="$prmBase/Writing Style for Weapon Cards.md"};
        'armor'=@{template="$tplBase/objects/armor.md";prompt="$prmBase/Writing Style for Armor Cards.md"};
        'story-object'=@{template="$tplBase/objects/story_object.md";prompt="$prmBase/Writing Style for Story Object Cards.md"};
        'role'=@{template="$tplBase/roles/class.md";prompt="$prmBase/Writing Style for Role Cards.md"};
        'class-progression'=@{template="$tplBase/roles/class_progression.md";prompt="$prmBase/Writing Style for Class Progression Cards.md"};
        'history'=@{template="$tplBase/history.md";prompt="$prmBase/Writing Style for History Cards.md"}; }
    if (-not $map.ContainsKey($Type)) { throw "Unknown card type $Type" }
    $pair = $map[$Type]; if (-not (Test-Path $pair.template)) { throw "Template missing: $($pair.template)" }; if (-not (Test-Path $pair.prompt)) { throw "Prompt missing: $($pair.prompt)" }; return $pair
}

function Get-SkeletonFromTemplate { param([string]$TemplatePath,[string]$Name)
    $raw = Get-Content -Path $TemplatePath -Raw
    $m=[regex]::Matches($raw,'```markdown([\s\S]*?)```')
    if ($m.Count -eq 0) { throw "No markdown code fence in template $TemplatePath" }
    $md=$m[0].Groups[1].Value; $md=$md -replace '\{Name\}',[regex]::Escape($Name).Replace('\\','\'); return $md.Trim()
}

function Get-TemplateFieldSpecs { param([string]$TemplateBody)
    $specs=@(); if (-not $TemplateBody) { return $specs }
    foreach($ln in ($TemplateBody -split "`n")) {
        $m=[regex]::Match($ln,'^\*\*(.+?):\*\*'); if (-not $m.Success) { continue }
        $label=$m.Groups[1].Value.Trim(); if ($label -in @('Summary','Full Description','Name')) { continue }
        $key=$label.ToLowerInvariant() -replace '[^a-z0-9]+','_'
        $isList=$false; $bullet=$false; $hint=$null
        $lct=$ln.ToLowerInvariant()
        if ($lct -match 'comma-?separated' -or $label -match 'Tone Keywords|Aligned Factions|Notable Characters|Primary Regions|Locations of Note|Potential Gameplay Hooks|Typical Lifespan') { $isList=$true }
        if ($label -eq 'Potential Gameplay Hooks') { $bullet=$true; $hint='Provide generic in-world events/complications; 1-3 concise hooks.' }
        $specs += [pscustomobject]@{ label=$label; key=$key; isList=$isList; bullet=$bullet; hint=$hint }
    }
    return $specs
}

function Get-ExistingFieldValues { param([string]$CardText,[array]$FieldSpecs)
    $result=@{}; if (-not $CardText) { return $result }
    $lines=$CardText -split "`n"
    for($i=0;$i -lt $lines.Length;$i++) {
        $ln=$lines[$i]; $m=[regex]::Match($ln,'^\*\*(.+?):\*\*\s*(.*)$'); if (-not $m.Success) { continue }
        $label=$m.Groups[1].Value.Trim(); $valInline=$m.Groups[2].Value.Trim(); $spec=$FieldSpecs | Where-Object { $_.label -eq $label }; if (-not $spec) { continue }
        $key=$spec.key
        if ($spec.bullet) {
            $bullets=@(); if ($valInline) { $bullets += $valInline }
            $j=$i+1; while($j -lt $lines.Length -and $lines[$j] -match '^\-\s+') { $bullets += ($lines[$j] -replace '^\-\s+','').Trim(); $j++ }
            if ($bullets.Count -gt 0) { $result[$key]=$bullets }
        } else {
            if ($valInline) {
                if ($spec.isList -and $valInline -match ',') { $parts=$valInline.Split(',') | % { $_.Trim() } | ? { $_ }; $result[$key]=$parts }
                else { $result[$key]=$valInline }
            }
        }
    }
    return $result
}

function New-RequestPayload {
    param(
        [array]$FieldSpecs,
        [string]$SourceCardText,
        [string]$Model,
        [hashtable]$Hints,
        [switch]$IncludeSource
    )
    $system=@(); $system+='You are a lore-writing model.'; $system+='Return JSON {"fields": {<key>: value}}.'
    $user=@(); $user+='FIELDS TO FILL:'; foreach($fs in $FieldSpecs){ $hint = if ($fs.isList) { 'array of strings' } else { 'string' }; $line = "- {0} ({1}) -> key: {2}" -f $fs.label,$hint,$fs.key; if ($fs.hint){ $line+=" | Guidance: $($fs.hint)" }; $user += $line }
    if ($Hints -and $Hints.Keys.Count -gt 0){ $user += 'USER INTENT:'; foreach($k in $Hints.Keys){ $user += "- $($k): $($Hints[$k])" } }
    if ($IncludeSource -and $SourceCardText){ $src=$SourceCardText; if($src.Length -gt 6000){ $src=$src.Substring(0,6000) }; $src=ConvertTo-SafeText $src; $src=ConvertTo-UnicodeEscaped $src; $user+="SOURCE CARD:\n$src" }
    $user += 'OUTPUT: JSON with key fields only.'
    $user += 'Do not repeat existing identical values; attempt refinement.'
    $user += 'Array fields: 1-5 concise items; hooks: 1-3.'
    $user += 'Valid JSON only.'
    $body=@{ model=$Model; messages=@( @{role='system';content=($system -join "`n")}, @{role='user';content=($user -join "`n")} ); temperature=0.3 } | ConvertTo-Json -Depth 6
    return $body
}

function New-ResponsesPayload {
    param(
        [array]$FieldSpecs,
        [string]$SourceCardText,
        [string]$Model,
        [hashtable]$Hints,
        [switch]$IncludeSource
    )
    $systemCore=@(); $systemCore+='You are a lore-writing model.'; $systemCore+='Return JSON {"fields": {<key>: value}}.'; $systemCore=''+($systemCore -join ' ')
    $userParts=@(); $userParts+='FIELDS TO FILL:'; foreach($fs in $FieldSpecs){ $hint = if ($fs.isList) { 'array of strings' } else { 'string' }; $line = "- {0} ({1}) -> key: {2}" -f $fs.label,$hint,$fs.key; if ($fs.hint){ $line+=" | Guidance: $($fs.hint)" }; $userParts += $line }
    if ($Hints -and $Hints.Keys.Count -gt 0){ $userParts += 'USER INTENT:'; foreach($k in $Hints.Keys){ $userParts += "- $($k): $($Hints[$k])" } }
    if ($IncludeSource -and $SourceCardText){ $src=$SourceCardText; if($src.Length -gt 6000){ $src=$src.Substring(0,6000) }; $src=ConvertTo-SafeText $src; $src=ConvertTo-UnicodeEscaped $src; $userParts+="SOURCE CARD:\n$src" }
    $userParts += 'OUTPUT: JSON with key fields only.'
    $userParts += 'Do not repeat existing identical values; attempt refinement.'
    $userParts += 'Array fields: 1-5 concise items; hooks: 1-3.'
    $userParts += 'Valid JSON only.'
    $userText=($userParts -join ' '); $userText=ConvertTo-SafeText $userText; $userText=ConvertTo-UnicodeEscaped $userText
    $inputBlocks=@( @{role='system';content=@(@{type='input_text';text=$systemCore})}, @{role='user';content=@(@{type='input_text';text=$userText})} )
    $body=@{ model=$Model; input=$inputBlocks; temperature=0.3; max_output_tokens=800 } | ConvertTo-Json -Depth 8
    return $body
}

function Invoke-Model { param([string]$Payload,[string]$Endpoint,[string]$ApiKey)
    $headers=@{ 'Authorization'="Bearer $ApiKey"; 'Content-Type'='application/json'; 'Accept'='application/json' }
    if ($Endpoint -match '/v1/responses'){ $headers['OpenAI-Beta']='responses=v1' }
    $resp=Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $headers -Body $Payload -TimeoutSec 120
    return $resp
}

# Build field specs from template for matching
$pack = Get-PackPaths -Type $CardType
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($CardPath)
$templateBody = Get-SkeletonFromTemplate -TemplatePath $pack.template -Name $baseName
$specs = Get-TemplateFieldSpecs -TemplateBody $templateBody

# Match requested field labels/keys
$requested=@()
foreach($fRaw in $Fields){
    foreach ($f in ($fRaw -split ',')) {
        $needle=$f.Trim().ToLowerInvariant()
        if (-not $needle) { continue }
        $found = $specs | Where-Object { $_.label.ToLowerInvariant() -eq $needle -or $_.key.ToLowerInvariant() -eq $needle }
        if ($found){ $requested += $found }
        else { Write-Warning "Field not found in template: $f" }
    }
}
if (-not $requested -or $requested.Count -eq 0){ throw 'No valid fields matched.' }

$existingValues = Get-ExistingFieldValues -CardText $rawCard -FieldSpecs $specs

# Optionally strip existing values for requested fields
if ($StripExisting) {
    try {
        $linesSE = $rawCard -split "`n"
        $labelsSE = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($r in $requested) { if ($r.label) { [void]$labelsSE.Add($r.label) } }
        $rebuiltSE = New-Object System.Collections.Generic.List[string]
        for ($sx=0; $sx -lt $linesSE.Length; $sx++) {
            $lnSE = $linesSE[$sx]
            $mSE = [regex]::Match($lnSE,'^\*\*(.+?):\*\*')
            if ($mSE.Success) {
                $lblSE = $mSE.Groups[1].Value
                if ($labelsSE.Contains($lblSE)) {
                    $specSE = $requested | Where-Object { $_.label -eq $lblSE }
                    if ($specSE -and ($specSE.bullet -or $specSE.isList)) {
                        $rebuiltSE.Add("**$lblSE:**") | Out-Null
                        $skipSE = $sx + 1
                        while ($skipSE -lt $linesSE.Length -and $linesSE[$skipSE] -match '^\-\s+') { $skipSE++ }
                        $sx = $skipSE - 1
                        continue
                    } else {
                        $rebuiltSE.Add("**$lblSE:**") | Out-Null
                        continue
                    }
                }
            }
            $rebuiltSE.Add($lnSE) | Out-Null
        }
        $rawCard = ($rebuiltSE -join "`n")
        Write-Host 'Stripped existing selected field values from source card.' -ForegroundColor DarkYellow
    } catch { Write-Warning "StripExisting failed: $($_.Exception.Message)" }
}

# Build payload
$useResponses = (Test-ResponsesApi -ModelName $Model) -and (-not $ForceChat)
if (-not $ApiKey) { throw 'API key required.' }
$endpoint = if ($useResponses) { 'https://api.openai.com/v1/responses' } else { 'https://api.openai.com/v1/chat/completions' }

if ($DryRun){
    if ($useResponses){ $payload = New-ResponsesPayload -FieldSpecs $requested -SourceCardText $rawCard -Model $Model -Hints $Hints -IncludeSource }
    else { $payload = New-RequestPayload -FieldSpecs $requested -SourceCardText $rawCard -Model $Model -Hints $Hints -IncludeSource }
    Write-Host 'DRY RUN payload:' -ForegroundColor Yellow
    Write-Output $payload
    exit 0
}

$payload = if ($useResponses) { New-ResponsesPayload -FieldSpecs $requested -SourceCardText $rawCard -Model $Model -Hints $Hints -IncludeSource } else { New-RequestPayload -FieldSpecs $requested -SourceCardText $rawCard -Model $Model -Hints $Hints -IncludeSource }

# Debug directory
$dbgDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lore/.debug'
if (-not (Test-Path $dbgDir)) { New-Item -ItemType Directory -Path $dbgDir -Force | Out-Null }
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$payloadPath = Join-Path $dbgDir ("interactive_${stamp}_payload.json")
Set-Content -Path $payloadPath -Value $payload -Encoding utf8
Write-Host "Saved payload -> $payloadPath" -ForegroundColor DarkCyan

# Invoke model
Write-Host "Calling model ($endpoint) for fields: $($requested.label -join ', ')" -ForegroundColor Cyan
$resp = Invoke-Model -Payload $payload -Endpoint $endpoint -ApiKey $ApiKey

# Extract JSON text
$jsonText = $null
if ($useResponses){
    if ($resp.output_text){ $jsonText = $resp.output_text }
    elseif ($resp.output -and $resp.output.Count -gt 0){
        $parts=@(); foreach($blk in $resp.output){ if ($blk.content){ foreach($c in $blk.content){ if ($c.text){ $parts += $c.text } elseif ($c.output_text){ $parts += $c.output_text } } } }
        $jsonText = ($parts -join "`n")
    }
} else {
    $jsonText = $resp.choices[0].message.content
}
if (-not $jsonText) { throw 'No JSON text returned from model.' }
$responsePath = Join-Path $dbgDir ("interactive_${stamp}_response_raw.txt")
Set-Content -Path $responsePath -Value $jsonText -Encoding utf8
Write-Host "Saved raw response -> $responsePath" -ForegroundColor DarkCyan

# Parse fields
$fieldsObj = $null
try { $parsed = $jsonText | ConvertFrom-Json; if ($parsed.PSObject.Properties.Name -contains 'fields'){ $fieldsObj = $parsed.fields } else { $fieldsObj = $parsed } } catch { Write-Warning "Failed to parse JSON: $($_.Exception.Message)" }
if (-not $fieldsObj) { throw 'Parsed fields object was null.' }

# Diff
$diffReport = @()
foreach($req in $requested){
    $k=$req.key
    $old = if ($existingValues.ContainsKey($k)) { $existingValues[$k] } else { '(missing)' }
    $new = if ($fieldsObj.PSObject.Properties.Name -contains $k) { $fieldsObj.$k } else { '(not returned)' }
    if ($new -is [System.Array]) { $new = Invoke-DedupArrayPreserveOrder -Val $new }
    if ($old -is [System.Array]) { $old = Invoke-DedupArrayPreserveOrder -Val $old }
    $changed = ($new -ne $old)
    $diffReport += [pscustomobject]@{ field=$req.label; key=$k; changed=$changed; old=$old; new=$new }
}

$diffPath = Join-Path $dbgDir ("interactive_${stamp}_diff.json")
($diffReport | ConvertTo-Json -Depth 6) | Set-Content -Path $diffPath -Encoding utf8
Write-Host "Saved diff -> $diffPath" -ForegroundColor DarkCyan

Write-Host "\nField Change Summary:" -ForegroundColor Green
foreach($r in $diffReport){
    $oldFmt = if ($r.old -is [System.Array]) { ($r.old -join '; ') } else { $r.old }
    $newFmt = if ($r.new -is [System.Array]) { ($r.new -join '; ') } else { $r.new }
    Write-Host ("- {0} ({1}): CHANGED={2}" -f $r.field,$r.key,$r.changed) -ForegroundColor White
    if ($VerboseRaw){
        Write-Host ("  Old: {0}" -f $oldFmt) -ForegroundColor DarkGray
        Write-Host ("  New: {0}" -f $newFmt) -ForegroundColor DarkGray
    }
}

Write-Host "\nTo inspect artifacts: open $dbgDir" -ForegroundColor Yellow
