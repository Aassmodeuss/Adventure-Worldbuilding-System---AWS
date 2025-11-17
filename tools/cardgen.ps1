param(
    [ValidateSet('new','rewrite')]
    [string]$JobType,

    [Parameter(Mandatory=$true)]
    [ValidateSet('world','realm','region','biome','location','point','place-concept','place-feature','concept','character','creature','faction','race','object','weapon','armor','story-object','role','class-progression','history')]
    [string]$CardType,

    [Parameter(Mandatory=$true)]
    [string]$Name,

    [string]$Parent,                   # optional id (e.g., realm:greenwood)
    [string[]]$SeeAlso,                # optional ids
    [string[]]$ToneKeywords,           # optional words
    [string[]]$LocationsOfNote,        # optional titles for children/points
    [string[]]$KnownLinks,             # optional titles for links to pre-fill list fields
    [string]$EraOrTopicBucket,         # for History or Concept buckets

    # Canon Adherence: accepts internal values and user labels
    [ValidateSet('preserve-only','augment','create','strict','flexible','creative')]
    [string]$CanonAdherence,
    [string[]]$NewFacts,
    [string]$DesiredSummary,
    [hashtable]$ExtraNotes,

    [string]$Model = $env:OPENAI_MODEL, # default from env if set
    [string]$ApiKey = $env:OPENAI_API_KEY,
    [string]$Endpoint = 'https://api.openai.com/v1/chat/completions',

    [switch]$DryRun,
    [switch]$VerbosePreview,
    [switch]$AutoApply,
    [switch]$AutoIndex,
    [switch]$ForceChat,
    [switch]$Azure,
    [string]$FallbackModel = $env:OPENAI_FALLBACK_MODEL,
    [switch]$MinimalTest,
    [switch]$DebugHttp,
    [switch]$NoChatFallback
)

# --- Utility Functions ---
function Resolve-Choice {
    param(
        [string]$UserInput,
        [hashtable]$Map,
        [string]$Default
    )
    $val = if ($null -ne $UserInput) { ("$UserInput").Trim().ToLowerInvariant() } else { '' }
    if (-not $val -or $val -eq '') { return $Default }
    foreach ($key in $Map.Keys) {
        $syns = $Map[$key]
        if ($syns -isnot [System.Array]) { $syns = @($syns) }
        foreach ($s in $syns) {
            if ("$s".ToLowerInvariant() -eq $val) { return $key }
        }
    }
    return $Default
}

function Test-ResponsesApi {
    param([string]$ModelName)
    if (-not $ModelName) { return $false }
    # Use Responses API for modern models (gpt-4.1 and 4o family)
    return ($ModelName -match '^(gpt-4\.1|gpt-4o)')
}

function ConvertTo-SafeText {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    # Remove C0 control chars that can break JSON decoders
    $t = $t -replace '[\u0000-\u001F]', ' '
    # Remove surrogate range to avoid unpaired surrogate issues
    $t = $t -replace '[\uD800-\uDFFF]', ' '
    return $t
}

function ConvertTo-UnicodeEscaped {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -gt 127) {
            [void]$sb.AppendFormat("\\u{0:x4}", $code)
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

function Convert-OutputText {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    # Replace non-breaking space with normal space
    $nbsp = [char]0x00A0
    $t = $t -replace [string]$nbsp, ' '
    # Replace various dash/hyphen code points with ASCII hyphen
    $dashChars = [string]([char]0x2013) + ([char]0x2014) + ([char]0x2212) + ([char]0x2011)
    $pattern = "[{0}]" -f [regex]::Escape($dashChars)
    $t = [regex]::Replace($t, $pattern, '-')
    # Normalize smart quotes and primes by code point (safer than embedding literals)
    $smartSingles = [string]([char]0x2018) + ([char]0x2019)
    $smartDoubles = [string]([char]0x201C) + ([char]0x201D)
    $patSingles = "[{0}]" -f [regex]::Escape($smartSingles)
    $patDoubles = "[{0}]" -f [regex]::Escape($smartDoubles)
    $t = [regex]::Replace($t, $patSingles, "'")
    $t = [regex]::Replace($t, $patDoubles, '"')
    # Normalize prime and double-prime
    $primeSingle = [string]([char]0x2032)
    $primeDouble = [string]([char]0x2033)
    $t = $t -replace [regex]::Escape($primeSingle), "'"
    $t = $t -replace [regex]::Escape($primeDouble), '"'
    return $t
}

# Order-preserving dedupe for array-ish values used by list fields
function Invoke-DedupArrayPreserveOrder {
    param([object]$Val)
    $arr = @()
    if ($null -eq $Val) { return @() }
    if ($Val -is [System.Array]) { $arr = $Val }
    elseif ($Val) { $arr = @("$Val") } else { return @() }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $out = @()
    foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $norm = ("$item").Trim()
        if ($norm -eq '') { continue }
        $ci = $norm.ToLowerInvariant()
        if ($seen.Contains($ci)) { continue }
        [void]$seen.Add($ci)
        $out += $norm
    }
    return ,$out
}

function ConvertTo-Slug {
    param([string]$Text)
    $t = $Text.ToLowerInvariant()
    $t = [regex]::Replace($t,'[^a-z0-9]+','-')
    $t = [regex]::Replace($t,'^-+|-+$','')
    return $t
}

# Heuristic: does a location name look specific (proper-noun-like) vs generic?
function Test-IsSpecificLocationName {
    param([string]$Name)
    if (-not $Name) { return $false }
    $n = ("$Name").Trim()
    if ($n -eq '') { return $false }
    # Quick rejects: extremely short or punctuation-only
    if ($n.Length -lt 3) { return $false }
    if ($n -notmatch '[A-Za-z]') { return $false }
    # Normalize quotes
    $n = $n.Trim([char]34,[char]39)
    # Tokenize words (letters/numbers only)
    $pattern = "[A-Za-z][A-Za-z0-9']*"
    $tokens = [regex]::Matches($n, $pattern) | ForEach-Object { $_.Value }
    if (-not $tokens -or $tokens.Count -eq 0) { return $false }
    # Common generic words to ignore as the sole/distinctive token
    $generic = @(
        'the','a','an','old','ancient','abandoned','small','little','great','north','south','east','west',
        'upper','lower','central','outer','inner','new','old',
        'village','camp','encampment','bridge','road','trail','path','river','ford','bank','bend','forest','woods','grove',
        'clearing','cave','caves','cavern','caverns','lake','pond','hill','hills','valley','tower','gate','market','square',
        'docks','harbor','harbour','mine','mines','quarry','ruins','inn','tavern','keep','hold','fort','outpost','watchtower'
    )
    $genSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($g in $generic) { [void]$genSet.Add($g) }
    # Rule 1: if at least one token starts with uppercase and isn't a generic stopword -> specific
    foreach ($t in $tokens) {
        if ($t.Length -ge 1 -and ($t[0] -cmatch '[A-Z]')) {
            if (-not $genSet.Contains($t.ToLowerInvariant())) { return $true }
        }
    }
    # Rule 2: Single-word TitleCase like "Stormbridge" is also acceptable
    if ($tokens.Count -eq 1) {
        $w = $tokens[0]
        if ($w[0] -cmatch '[A-Z]' -and $w.Length -ge 5 -and -not $genSet.Contains($w.ToLowerInvariant())) { return $true }
    }
    # Otherwise treat as generic
    return $false
}

function Get-PackPaths {
    param([string]$Type)

    $tplBase = '.continue/Lore Card Templates'
    $prmBase = '.continue/prompts'

    $map = @{
        'world'            = @{ template = "$tplBase/places/world.md";         prompt = "$prmBase/Writing Style for World Cards.md" }
        'realm'            = @{ template = "$tplBase/places/realm.md";         prompt = "$prmBase/Writing Style for Realm Cards.md" }
        'region'           = @{ template = "$tplBase/places/region.md";        prompt = "$prmBase/Writing Style for Region Cards.md" }
        'biome'            = @{ template = "$tplBase/places/biome.md";         prompt = "$prmBase/Writing Style for Biome Cards.md" }
        'location'         = @{ template = "$tplBase/places/location.md";      prompt = "$prmBase/Writing Style for Location Cards.md" }
        'point'            = @{ template = "$tplBase/places/point.md";         prompt = "$prmBase/Writing Style for Point Cards.md" }
        'place-concept'    = @{ template = "$tplBase/places/place_concept.md"; prompt = "$prmBase/Writing Style for Place Feature Cards.md" }
        'place-feature'    = @{ template = "$tplBase/places/place_feature.md"; prompt = "$prmBase/Writing Style for Place Feature Cards.md" }
        'concept'          = @{ template = "$tplBase/concept.md";              prompt = "$prmBase/Writing Style for Concept Cards.md" }
        'character'        = @{ template = "$tplBase/beings/character.md";     prompt = "$prmBase/Writing Style for Character Cards.md" }
        'creature'         = @{ template = "$tplBase/beings/creature.md";      prompt = "$prmBase/Writing Style for Creature Cards.md" }
        'faction'          = @{ template = "$tplBase/beings/faction.md";       prompt = "$prmBase/Writing Style for Faction Cards.md" }
        'race'             = @{ template = "$tplBase/beings/race.md";          prompt = "$prmBase/Writing Style for Race Cards.md" }
        'object'           = @{ template = "$tplBase/objects/object.md";       prompt = "$prmBase/Writing Style for Object Cards.md" }
        'weapon'           = @{ template = "$tplBase/objects/weapon.md";       prompt = "$prmBase/Writing Style for Weapon Cards.md" }
        'armor'            = @{ template = "$tplBase/objects/armor.md";        prompt = "$prmBase/Writing Style for Armor Cards.md" }
        'story-object'     = @{ template = "$tplBase/objects/story_object.md"; prompt = "$prmBase/Writing Style for Story Object Cards.md" }
        'role'             = @{ template = "$tplBase/roles/class.md";          prompt = "$prmBase/Writing Style for Role Cards.md" }
        'class-progression'= @{ template = "$tplBase/roles/class_progression.md"; prompt = "$prmBase/Writing Style for Class Progression Cards.md" }
        'history'          = @{ template = "$tplBase/history.md";              prompt = "$prmBase/Writing Style for History Cards.md" }
    }

    if (-not $map.ContainsKey($Type)) { throw "Unknown card type '$Type'" }
    $pair = $map[$Type]
    if (-not (Test-Path $pair.template)) { throw "Template not found: $($pair.template)" }
    if (-not (Test-Path $pair.prompt)) { throw "Writing style prompt not found: $($pair.prompt)" }
    return $pair
}

function Get-OutputDirectory {
    param([string]$Type, [string]$EraOrTopic)

    $base = 'Lore/Lorebook'
    switch ($Type) {
        'world'         { return Join-Path $base 'Places/Worlds' }
        'realm'         { return Join-Path $base 'Places/Realm' }
        'region'        { return Join-Path $base 'Places/Regions' }
        'biome'         { return Join-Path $base 'Places/Biomes' }
        'location'      { return Join-Path $base 'Places/Locations' }
        'point'         { return Join-Path $base 'Places/Point' }
        'place-concept' { return Join-Path $base 'Places/Place Features' }
        'place-feature' { return Join-Path $base 'Places/Place Features' }
        'concept'       { if ($EraOrTopic) { return Join-Path (Join-Path $base 'Concepts') $EraOrTopic } else { return Join-Path $base 'Concepts' } }
        'character'     { return Join-Path $base 'Beings/Characters' }
        'creature'      { return Join-Path $base 'Beings/Creatures' }
        'faction'       { return Join-Path $base 'Beings/Factions' }
        'race'          { return Join-Path $base 'Beings/Races' }
        'object'        { return Join-Path $base 'Objects' }
        'weapon'        { return Join-Path $base 'Objects' }
        'armor'         { return Join-Path $base 'Objects' }
        'story-object'  { return Join-Path $base 'Objects' }
        'role'          { return Join-Path $base 'Roles and Classes' }
        'class-progression' { return Join-Path $base 'Roles and Classes' }
        'history'       { if ($EraOrTopic) { return Join-Path (Join-Path $base 'History') $EraOrTopic } else { return Join-Path $base 'History' } }
        default         { throw "No output directory mapping for '$Type'" }
    }
}

function New-FrontMatter {
    param(
        [string]$Type,
        [string]$Name,
        [string]$Parent,
        [string[]]$SeeAlso
    )
    $slug = ConvertTo-Slug -Text $Name
    $id = "$($Type):$slug"

    $yaml = @()
    $yaml += '---'
    $yaml += "id: $id"
    $yaml += "type: $Type"
    $yaml += "name: $Name"
    if ($Parent) { $yaml += "parent: $Parent" }
    if ($SeeAlso) {
        $trimmed = @($SeeAlso | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
        if ($trimmed.Count -gt 0) {
            $sa = ($trimmed) -join ', '
            $yaml += "see_also: [$sa]"
        }
    }
    $yaml += '---'
    return $yaml -join "`n"
}

function Get-SkeletonFromTemplate {
    param([string]$TemplatePath, [string]$Name)
    $raw = Get-Content -Path $TemplatePath -Raw
    # Extract the Card template code fence content
    $pattern = '```markdown([\s\S]*?)```'
    $m = [regex]::Matches($raw, $pattern)
    if ($m.Count -eq 0) { throw "Could not extract markdown card template from $TemplatePath" }
    $md = $m[0].Groups[1].Value
    $md = $md -replace '\{Name\}', [regex]::Escape($Name).Replace('\\','\')
    return $md.Trim()
}

function Get-TemplateFieldSpecs {
    param([string]$TemplateBody)
    $specs = @()
    if (-not $TemplateBody) { return $specs }
    $lines = $TemplateBody -split "`n"
    foreach ($ln in $lines) {
        $m = [regex]::Match($ln, '^\*\*(.+?):\*\*')
        if ($m.Success) {
            $label = $m.Groups[1].Value.Trim()
            $key = $label.ToLowerInvariant()
            $key = $key -replace '[^a-z0-9]+','_'
            $isList = $false
            $bullet = $false
            $extraHint = $null
            $lct = $ln.ToLowerInvariant()
            if ($lct -match 'comma-?separated' -or $lct -match '1-?\d+\s*(bullets|items)' -or $label -match 'Tone Keywords|Aligned Factions|Notable Characters|Primary Regions|Local Inhabitants|Locations of Note|Potential Gameplay Hooks') {
                $isList = $true
            }
            if ($label -eq 'Potential Gameplay Hooks') {
                $bullet = $true
                $extraHint = 'Provide generic in-world events/complications tied to the subject, not direct player quests. 1-3 concise hooks, 7-14 words each.'
            }
            if ($label -eq 'Typical Lifespan') {
                $extraHint = 'Provide numeric lifespan range (min-max years) plus 1-2 maturity milestones (e.g. adulthood age, elder recognition). Concise.'
            }
            if ($label -eq 'Aliases') {
                $extraHint = 'List 1-3 alternate tribal, historical, or exonym names if any exist; avoid speculative cross-references.'
            }
            if ($label -eq 'Locations of Note') {
                $extraHint = 'Return 1-5 unique proper-noun place names subordinate to this card. Use distinctive names (e.g., “Emberhold Archives”, “Stormbridge”), not generic terms (e.g., “old bridge”, “forest clearing”, “village”). Title-case each entry.'
            }
            # Skip Summary and Full Description here (handled separately)
            # Skip Name (deterministic from frontmatter) as well
            if ($label -ne 'Summary' -and $label -ne 'Full Description' -and $label -ne 'Name') {
                $specs += [pscustomobject]@{ label = $label; key = $key; isList = $isList; bullet = $bullet; hint = $extraHint }
            }
        }
    }
    return $specs
}

function Get-ExistingFieldValues {
    param([string]$CardText,[array]$FieldSpecs)
    $result = @{}
    if (-not $CardText) { return $result }
    $lines = $CardText -split "`n"
    for ($i=0; $i -lt $lines.Length; $i++) {
        $ln = $lines[$i]
        $m = [regex]::Match($ln,'^\*\*(.+?):\*\*\s*(.*)$')
        if (-not $m.Success) { continue }
        $label = $m.Groups[1].Value.Trim()
        $valInline = $m.Groups[2].Value.Trim()
        $spec = $FieldSpecs | Where-Object { $_.label -eq $label }
        if (-not $spec) { continue }
        $key = $spec.key
        if ($spec.bullet) {
            $bullets = @()
            if ($valInline) { $bullets += $valInline }
            $j = $i + 1
            while ($j -lt $lines.Length -and $lines[$j] -match '^\-\s+') {
                $bullets += ($lines[$j] -replace '^\-\s+','').Trim()
                $j++
            }
            if ($bullets.Count -gt 0) { $result[$key] = $bullets }
        } else {
            if ($valInline) {
                if ($spec.isList -and $valInline -match ',') {
                    $parts = $valInline.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                    $result[$key] = $parts
                } else {
                    $result[$key] = $valInline
                }
            }
        }
    }
    return $result
}

function Test-PlaceholderValue {
    param([string]$Key,[object]$Value)
    if (-not $Value) { return $true }
    $text = if ($Value -is [System.Array]) { ($Value -join ' ') } else { [string]$Value }
    $t = $text.Trim().ToLowerInvariant()
    if ($t -eq '') { return $true }
    # Generic template guidance flags
    $genericHints = @(
        'comma-separated',
        'comma separated',
        '1-3 concise bullets',
        '1–3 concise bullets',
        '3-5 anchors',
        '3–5 anchors',
        'numeric range',
        'provide',
        'write this as',
        'list',
        'array of strings',
        'common height, build, and distinguishing features',
        'where the race is common',
        'potential quests',
        'events, or interactions'
    )
    foreach ($h in $genericHints) { if ($t -like "*${h}*") { return $true } }
    # Specific allowances: 'none' is valid only for local_inhabitants; for others treat as placeholder
    if ($t -eq 'none' -or $t -eq '"none"') { return ($Key -ne 'local_inhabitants') }
    # Explicit starters for common fields
    $byKeyStartsWith = @{
        'tone_keywords' = @('3-5 anchors','3–5 anchors')
        'typical_lifespan' = @('numeric range')
        'potential_gameplay_hooks' = @('1-3 concise bullets','1–3 concise bullets')
        'stature_and_build' = @('common height')
        'primary_regions' = @('comma-separated')
        'aligned_factions' = @('comma-separated')
        'notable_characters' = @('comma-separated')
        'habitats' = @('comma-separated')
        'risk_and_countermeasures' = @('1-3 concise')
        'locations_of_note' = @('locations contained','subordinate points','biomes and major locations')
        'local_inhabitants' = @('list biome-wide','list stationed roles','none')
        'object_type' = @('consumable','device','tool','kit','artifact')
        'composition_materials' = @('key substances')
        'function_and_mechanism' = @('how it works')
        'activation_use' = @('steps or conditions')
        'maintenance_storage' = @('upkeep','handling','shelf')
        'safety_regulation' = @('hazards','restrictions','legal')
        'weapon_class' = @('melee','sidearm','rifle','launcher','heavy weapon','focus')
        'ammunition_power_source' = @('fuels','cells','charges','reagents')
        'mechanism_of_action' = @('how it produces')
        'rate_of_fire_charge' = @('sustained fire','charge time')
        'effective_range' = @('typical engagement')
        'handling_ergonomics' = @('weight','recoil','stabilization')
        'role_domain' = @('martial','arcane','divine','craft','civic')
        'typical_training' = @('how candidates are selected')
        'core_abilities' = @('concise list')
        'costs_and_limits' = @('metabolic','material','legal','moral')
        'common_equipment' = @('tools','weapons','armor','kits')
        'associated_class' = @('exact role','class card title')
        'training_pathways' = @('brief list')
    }
    if ($byKeyStartsWith.ContainsKey($Key)) {
        foreach ($prefix in $byKeyStartsWith[$Key]) { if ($t.StartsWith($prefix)) { return $true } }
    }
    # Special handling: Locations of Note must be specific proper-noun names; treat generics as placeholder
    if ($Key -eq 'locations_of_note') {
        $items = @()
        if ($Value -is [System.Array]) { $items = $Value } elseif ($Value) { $items = @("$Value") }
        # Deduplicate (case-insensitive)
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $specificCount = 0
        foreach ($raw in $items) {
            if (-not $raw) { continue }
            $norm = ("$raw").Trim()
            $keyci = $norm.ToLowerInvariant()
            if ($seen.Contains($keyci)) { continue }
            [void]$seen.Add($keyci)
            if (Test-IsSpecificLocationName -Name $norm) { $specificCount++ }
        }
        # Require at least 1 specific unique entry; otherwise it's effectively placeholder/generic
        if ($specificCount -lt 1) { return $true }
    }
    return $false
}

function Get-WritingStylePrompt {
    param([string]$PromptPath)
    return (Get-Content -Path $PromptPath -Raw)
}

function Get-AllCardFiles {
    param([string]$Root = 'Lore/Lorebook')
    return Get-ChildItem -Path $Root -Recurse -Include *.md -File
}

function Get-AllCardTitles {
    param([string]$Root = 'Lore/Lorebook')
    $files = Get-AllCardFiles -Root $Root
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($f in $files) { [void]$set.Add($f.BaseName) }
    return $set
}

function Get-ExistingLinksFromBlock {
    param([string]$CardText)
    $existing = New-Object 'System.Collections.Generic.HashSet[string]'
    $m = [regex]::Match($CardText, '(?s)\nLinks:\s*(.*?)\n\s*\[END:')
    if ($m.Success) {
        $block = $m.Groups[1].Value
        $titleMatches = [regex]::Matches($block, '\[\[(.*?)\]\]')
        foreach ($t in $titleMatches) { [void]$existing.Add($t.Groups[1].Value) }
    }
    return $existing
}

# Update the frontmatter see_also list within a full card text string
function Update-SeeAlsoInCardText {
    param(
        [string]$CardText,
        [string[]]$IdsToMerge
    )
    if (-not $CardText -or -not $IdsToMerge -or $IdsToMerge.Count -eq 0) { return $CardText }
    $ids = $IdsToMerge | Where-Object { $_ -and ($_ -is [string]) } | Select-Object -Unique
    if (-not $ids -or $ids.Count -eq 0) { return $CardText }

    $m = [regex]::Match($CardText, '(?s)^---\s*(.*?)\s*---')
    if (-not $m.Success) { return $CardText }
    $yamlBody = $m.Groups[1].Value
    $yamlLines = $yamlBody -split "`n"
    $existing = @()
    $idxSee = -1
    for ($i=0; $i -lt $yamlLines.Length; $i++) {
        $ln = $yamlLines[$i]
        if ($ln -match '^\s*see_also\s*:\s*\[(.*)\]\s*$') {
            $idxSee = $i
            $list = $Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $existing = $list
            break
        }
    }
    $mergedSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($x in $existing) { [void]$mergedSet.Add($x) }
    foreach ($x in $ids) { [void]$mergedSet.Add($x) }
    $merged = @($mergedSet | Sort-Object)
    if ($merged.Count -eq 0) { return $CardText }
    $seeLine = ('see_also: [{0}]' -f ($merged -join ', '))
    if ($idxSee -ge 0) {
        $yamlLines[$idxSee] = $seeLine
    } else {
        # insert before closing '---' (i.e., at end of yaml block)
        $yamlLines += $seeLine
    }
    $newYaml = ($yamlLines -join "`n")
    $prefix = $CardText.Substring(0, $m.Index)
    $suffixStart = $m.Index + $m.Length
    $suffix = $CardText.Substring($suffixStart)
    $rebuilt = ($prefix + '---' + "`n" + $newYaml + "`n---" + $suffix)
    return $rebuilt
}

function Get-MentionedTitlesFromBody {
    param(
        [string]$CardText,
        [System.Collections.Generic.HashSet[string]]$AllTitles,
        [string]$SelfTitle
    )
    $body = $CardText
    # remove Links block to avoid counting links themselves
    $body = [regex]::Replace($body, '(?s)\nLinks:\s*.*?\n\s*\[END:', "`n[END:")
    $found = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($title in $AllTitles) {
        if (-not $title -or $title -eq $SelfTitle) { continue }
        $pat = ('\b{0}\b' -f [regex]::Escape($title))
        if ([regex]::IsMatch($body, $pat)) { [void]$found.Add($title) }
    }
    return $found
}

function Add-LinksToCardText {
    param(
        [string]$CardText,
        [System.Collections.Generic.HashSet[string]]$TitlesToAdd
    )
    if (-not $TitlesToAdd -or $TitlesToAdd.Count -eq 0) { return $CardText }
    $lines = $CardText -split "`n"
    $linksIdx = $null
    for ($i=0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^\s*Links:\s*$') { $linksIdx = $i; break }
    }
    $insertion = @()
    foreach ($t in ($TitlesToAdd | Sort-Object)) { $insertion += ('- [[{0}]]' -f $t) }
    if ($null -ne $linksIdx) {
        # Insert after the Links: line and any immediate existing bullets; but simplest: insert just after Links:
        $before = $lines[0..$linksIdx]
        $after = $lines[($linksIdx+1)..($lines.Length-1)]
        $newLines = @()
        $newLines += $before
        $newLines += $insertion
        $newLines += $after
        return ($newLines -join "`n")
    } else {
        # Insert Links: block before [END:
        $idxEnd = $lines.Length - 1
        for ($i=0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match '^\[END:') { $idxEnd = $i; break } }
        $newLines = @()
        $newLines += $lines[0..($idxEnd-1)]
        $newLines += 'Links:'
        $newLines += $insertion
        $newLines += $lines[$idxEnd..($lines.Length-1)]
        return ($newLines -join "`n")
    }
}

# Determine if a field spec represents cross-references to other card titles
function Test-CrossRefField {
    param([pscustomobject]$Spec)
    if (-not $Spec) { return $false }
    $k = ($Spec.key + '')
    if (-not $k) { return $false }
    $k = $k.ToLowerInvariant()
    $whitelist = @(
        'aligned_factions','notable_characters','primary_regions','locations_of_note','local_inhabitants',
        'habitats','associated_class','neighboring_regions','connected_places','aligned_characters',
        'aligned_races','aligned_creatures','region','regions'
    )
    if ($whitelist -contains $k) { return $true }
    # Generic heuristics: treat anything with 'region' or 'faction' or 'character' as cross-ref
    if ($k -match 'region' -or $k -match 'faction' -or $k -match 'character' -or $k -match 'location') { return $true }
    return $false
}

# Extract unknown referenced titles from card fields based on template specs
function Get-UncreatedReferencesFromFields {
    param(
        [string]$CardText,
        [string]$TemplateBody,
        [System.Collections.Generic.HashSet[string]]$AllTitles
    )
    $result = @()
    if (-not $CardText -or -not $TemplateBody -or -not $AllTitles) { return $result }
    $specs = Get-TemplateFieldSpecs -TemplateBody $TemplateBody
    if (-not $specs -or $specs.Count -eq 0) { return $result }
    $values = Get-ExistingFieldValues -CardText $CardText -FieldSpecs $specs
    foreach ($spec in $specs) {
        if (-not (Test-CrossRefField -Spec $spec)) { continue }
        $key = $spec.key
        if (-not $values.ContainsKey($key)) { continue }
        $val = $values[$key]
        $items = @()
        if ($val -is [System.Array]) { $items = $val }
        elseif ($val) { $items = @("$val") }
        $unknowns = @()
        foreach ($raw in $items) {
            if (-not $raw) { continue }
            $t = ("$raw").Trim()
            # Strip wiki link markup or quotes if present
            $t = $t -replace '^\[\[(.*?)\]\]$','$1'
            $t = $t.Trim('"','''')
            if (-not $t) { continue }
            if (-not $AllTitles.Contains($t)) { $unknowns += $t }
        }
        if ($unknowns.Count -gt 0) {
            $result += [pscustomobject]@{ field = $spec.label; titles = ($unknowns | Select-Object -Unique) }
        }
    }
    return $result
}

# Persist a JSONL log of potential new cards to create and link
function Write-PotentialCardsLog {
    param(
        [string]$WorkspaceRoot,
        [string]$SourceName,
        [string]$SourceType,
        [string]$SourcePath,
        [array]$UnknownByField
    )
    if (-not $UnknownByField -or $UnknownByField.Count -eq 0) { return }
    $logDir = Join-Path $WorkspaceRoot 'Lore'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logPath = Join-Path $logDir 'PotentialCards.jsonl'
    $entries = @()
    foreach ($it in $UnknownByField) {
        foreach ($title in $it.titles) {
            $entries += [ordered]@{ field = $it.field; title = $title }
        }
    }
    $obj = [ordered]@{
        timestamp = ([DateTime]::UtcNow.ToString('o'))
        source    = [ordered]@{ name = $SourceName; type = $SourceType; path = $SourcePath }
        unknown   = $entries
    }
    $json = ($obj | ConvertTo-Json -Depth 6 -Compress)
    Add-Content -Path $logPath -Value $json -Encoding utf8
    Write-Host ("Logged potential cards -> {0}" -f $logPath) -ForegroundColor DarkCyan
}

function Read-FrontMatter {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content -Path $Path -Raw
    $m = [regex]::Match($raw, "(?s)^---\s*(.*?)\s*---")
    if (-not $m.Success) { return $null }
    $yaml = $m.Groups[1].Value -split "`n"
    $fm = @{}
    foreach ($line in $yaml) {
        $kv = $line.Split(":",2)
        if ($kv.Count -eq 2) {
            $key = $kv[0].Trim()
            $val = $kv[1].Trim()
            if ($key -eq 'see_also') {
                # parse [a, b, c]
                $val = $val.Trim('[',']')
                $arr = @()
                if ($val) {
                    $arr = $val.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                }
                $fm[$key] = $arr
            } else {
                $fm[$key] = $val
            }
        }
    }
    return $fm
}

function Find-CardById {
    param([string]$Id)
    if (-not $Id) { return $null }
    $files = Get-AllCardFiles
    foreach ($f in $files) {
        try {
            $fm = Read-FrontMatter -Path $f.FullName
            if ($fm -and $fm['id'] -eq $Id) { return $f.FullName }
        } catch {}
    }
    return $null
}

function Find-CardByTitle {
    param([string]$Title)
    if (-not $Title) { return $null }
    $root = 'Lore/Lorebook'
    $candidate = Get-ChildItem -Path $root -Recurse -File -Include *.md | Where-Object { $_.BaseName -eq $Title }
    if ($candidate) { return $candidate[0].FullName }
    return $null
}

function Get-FullDescriptionFromCard {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content -Path $Path -Raw
    $fm = Read-FrontMatter -Path $Path
    $name = if ($fm -and $fm['name']) { $fm['name'] } else { [IO.Path]::GetFileNameWithoutExtension($Path) }
    $type = if ($fm -and $fm['type']) { $fm['type'] } else { '' }
    $id   = if ($fm -and $fm['id'])   { $fm['id'] }   else { '' }
    $desc = $null
    foreach ($line in ($raw -split "`n")) {
        if ($line -match '^\*\*Full Description:\*\*\s*(.*)$') {
            $desc = $matches[1].Trim()
            break
        }
    }
    if (-not $desc) { return $null }
    return [ordered]@{ name = $name; type = $type; id = $id; description = $desc }
}

function Get-ParentChainContext {
    param([string]$StartParentId)
    $ctx = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $cur = $StartParentId
    while ($cur -and -not $seen.Contains($cur)) {
        $seen.Add($cur) | Out-Null
        $pPath = Find-CardById -Id $cur
        if (-not $pPath) { break }
        $info = Get-FullDescriptionFromCard -Path $pPath
        if ($info) { $ctx += $info }
        $pfm = Read-FrontMatter -Path $pPath
        $cur = if ($pfm) { $pfm['parent'] } else { $null }
    }
    return $ctx
}

function Get-LinkedCardsContext {
    param(
        [string]$SourcePath,
        [hashtable]$FrontMatter
    )
    $ctx = @()
    $titlesFromBody = @()
    $raw = Get-Content -Path $SourcePath -Raw
    $linksBlock = [regex]::Match($raw, '(?s)\nLinks:\s*(.*?)\n\s*\[END:')
    if ($linksBlock.Success) {
        $block = $linksBlock.Groups[1].Value
        $titleMatches = [regex]::Matches($block, '\[\[(.*?)\]\]')
        foreach ($m in $titleMatches) { $titlesFromBody += $m.Groups[1].Value }
    }
    $idsFromFm = @()
    if ($FrontMatter -and $FrontMatter['see_also']) { $idsFromFm = $FrontMatter['see_also'] }

    $paths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($id in $idsFromFm) {
        $p = Find-CardById -Id $id
        if ($p) { $paths.Add($p) | Out-Null }
    }
    foreach ($t in $titlesFromBody) {
        $p = Find-CardByTitle -Title $t
        if ($p) { $paths.Add($p) | Out-Null }
    }
    foreach ($p in $paths) {
        $info = Get-FullDescriptionFromCard -Path $p
        if ($info) { $ctx += $info }
    }
    return $ctx
}

function Get-ContextText {
    param(
        [array]$ParentChain,
        [array]$LinkedCards
    )
    # Reset dedup flags for this build
    $script:LinkedCardsDeduped = $false
    $script:LinkedCardsDedupedCount = 0
    if ((-not $ParentChain -or $ParentChain.Count -eq 0) -and (-not $LinkedCards -or $LinkedCards.Count -eq 0)) { return $null }
    $lines = @()
    $lines += 'CONTEXT FROM RELATED CARDS (for consistency only — do not copy or parrot):'
    if ($ParentChain -and $ParentChain.Count -gt 0) {
        $lines += 'Parent Lineage (nearest first):'
        foreach ($p in $ParentChain) {
            $desc = $p.description
            if ($desc.Length -gt 800) { $desc = $desc.Substring(0,800) }
            $lines += "- [$($p.type)] $($p.name): $desc"
        }
    }
    if ($LinkedCards -and $LinkedCards.Count -gt 0) {
        # Deduplicate: remove any linked cards that also appear in the parent chain
        $parentIds = New-Object 'System.Collections.Generic.HashSet[string]'
        $parentKeys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($p in ($ParentChain | Where-Object { $_ })) {
            if ($p.id) { $null = $parentIds.Add($p.id) }
            $key = ("{0}|{1}" -f $p.type, $p.name)
            $null = $parentKeys.Add($key)
        }
        $filteredLinks = @()
        $originalLinkedCount = $LinkedCards.Count
        foreach ($l in ($LinkedCards | Where-Object { $_ })) {
            $isDup = $false
            if ($l.id -and $parentIds.Contains($l.id)) { $isDup = $true }
            else {
                $lKey = ("{0}|{1}" -f $l.type, $l.name)
                if ($parentKeys.Contains($lKey)) { $isDup = $true }
            }
            if (-not $isDup) { $filteredLinks += $l }
        }
        if ($filteredLinks.Count -lt $originalLinkedCount) {
            $script:LinkedCardsDeduped = $true
            $script:LinkedCardsDedupedCount = $originalLinkedCount - $filteredLinks.Count
        }
        if ($filteredLinks.Count -gt 0) {
        $lines += 'Linked Cards:'
        # limit to avoid huge prompts
        $take = [Math]::Min(10, $filteredLinks.Count)
        for ($i=0; $i -lt $take; $i++) {
            $l = $filteredLinks[$i]
            $desc = $l.description
            if ($desc.Length -gt 700) { $desc = $desc.Substring(0,700) }
            $lines += "- [$($l.type)] $($l.name): $desc"
        }
        }
    }
    $lines += 'Use this as background context only. Do not restate these descriptions verbatim. Keep output grounded in SOURCE CARD and USER NOTES.'
    return ($lines -join "`n")
}

function New-RequestPayload {
    param(
        [string]$StylePrompt,
        [string]$TemplateBody,
        [string]$JobType,
        [string]$SourceCardText,
        [hashtable]$UserNotes,
        [string[]]$NewFacts,
        [string]$CanonAdherence,
        [string]$Model,
        [string]$ContextText,
        [array]$FieldSpecs,
        [switch]$FieldsOnly,
        [hashtable]$InteractiveHints,
        [switch]$IncludeSourceInFieldsOnly
    )

    $policyBlock = switch ($CanonAdherence) {
        'preserve-only' {
            @(
                'Canon Adherence: STRICT.',
                '- Do NOT add any facts not present in SOURCE CARD or USER NOTES.',
                '- Rephrase only; preserve dates, governance, hazards, tariffs, quotas, names.'
            ) -join "`n"
        }
        'augment' {
            @(
                'Canon Adherence: FLEXIBLE.',
                '- You may add minor connective details consistent with canon and USER NOTES.',
                '- Do NOT invent new entities, dates, or events unless listed under NEW FACTS AUTHORIZED.'
            ) -join "`n"
        }
        'create' {
            @(
                'Canon Adherence: CREATIVE.',
                '- You may create new lore consistent with style, tone, and setting.',
                '- Avoid contradictions and do NOT invent cross-references to unknown pages.'
            ) -join "`n"
        }
        default { 'Canon Adherence: STRICT.' }
    }

    $system = @()
    $system += 'You are a lore-writing model that strictly follows provided templates and writing style prompts.'
    if ($FieldsOnly) {
        $system += 'Only generate the requested additional fields. Do not include Summary or Full Description.'
        $system += 'Return JSON: {"fields": { <key>: value }}.'
    } else {
        $system += 'Only generate the Summary and Full Description fields unless explicitly told otherwise.'
        if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
            $system += 'Return JSON: {"summary": "...", "full_description": "...", "fields": { <key>: value } }.'
        } else {
            $system += 'Return JSON: {"summary": "...", "full_description": "..."}.'
        }
    }
    $system += $policyBlock
    if ($FieldsOnly) {
        $system += ''
        $system += 'Use concise codex tone; objective; third-person. Keep outputs compact and factual. '
    } else {
        $system += ''
        $system += "WRITING STYLE PROMPT:`n$StylePrompt"
        $system += 'Name usage: Include the card''s title name at least once in Summary and at least twice in Full Description (natural usage; avoid repetition).'
    }

    $user = @()
    $user += "JOB TYPE: $JobType"
    $canon = switch ($CanonAdherence) { 'preserve-only' { 'strict' } 'augment' { 'flexible' } 'create' { 'creative' } default { 'strict' } }
    $user += "CANON ADHERENCE: $canon"
    if ($UserNotes) {
        $user += "USER NOTES:" 
        $UserNotes.GetEnumerator() | ForEach-Object { $user += ("- {0}: {1}" -f $_.Key, ($_.Value -join ', ')) }
    }
    if ($NewFacts -and $NewFacts.Count -gt 0) {
        $user += 'NEW FACTS AUTHORIZED:'
        $NewFacts | ForEach-Object { $user += "- $_" }
    }
    if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
        $user += 'ADDITIONAL FIELDS TO FILL (write concise values; respect USER NOTES if provided):'
        foreach ($fs in $FieldSpecs) {
            $hint = if ($fs.isList) { 'array of strings' } else { 'string' }
            $line = ("- {0} ({1}) -> key: {2}" -f $fs.label, $hint, $fs.key)
            if ($fs.hint) { $line = $line + (" | Guidance: {0}" -f $fs.hint) }
            $user += $line
        }
    }
    if (-not $FieldsOnly) {
        if ($SourceCardText) {
            $src = $SourceCardText
            if ($src.Length -gt 6000) { $src = $src.Substring(0,6000) }
            $src = ConvertTo-SafeText $src
            $src = ConvertTo-UnicodeEscaped $src
            $user += "SOURCE CARD (facts to preserve):`n$src"
        }
        if ($ContextText) {
            $ctx = $ContextText
            if ($ctx.Length -gt 8000) { $ctx = $ctx.Substring(0,8000) }
            $ctx = ConvertTo-SafeText $ctx
            $ctx = ConvertTo-UnicodeEscaped $ctx
            $user += "\n$ctx"
        }
    } elseif ($IncludeSourceInFieldsOnly -and $SourceCardText) {
        $src = $SourceCardText
        if ($src.Length -gt 6000) { $src = $src.Substring(0,6000) }
        $src = ConvertTo-SafeText $src
        $src = ConvertTo-UnicodeEscaped $src
        $user += "SOURCE CARD (current text for context):`n$src"
    }
    if ($FieldsOnly) {
        if ($InteractiveHints -and $InteractiveHints.Keys.Count -gt 0) {
            $user += 'USER INTENT FOR SELECTED FIELDS:'
            foreach ($k in $InteractiveHints.Keys) {
                $hintVal = ("{0}" -f $InteractiveHints[$k])
                if ($hintVal -and $hintVal.Trim() -ne '') { $user += ("- {0}: {1}" -f $k, $hintVal) }
            }
            $user += 'If intent is provided, prefer generating replacements aligned to the hint.'
        }
        $user += 'OUTPUT: JSON with key fields only (object with the keys listed above).'
        $user += 'For array fields, return an array of strings; for text fields, return a string.'
    } else {
        if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
            $user += 'OUTPUT: JSON with keys summary, full_description, and fields (object with the keys listed above).'
            $user += 'For array fields, return an array of strings; for text fields, return a string.'
        } else {
            $user += 'OUTPUT: JSON with keys summary, full_description only.'
        }
        $user += 'Constraints: objective, concise, third-person. 1–2 sentences for Summary. 3–8 sentences for Full Description. Max 24 words per sentence. No semicolons. No metaphors.'
        $user += 'Standalone requirement: Summary and Full Description must each stand alone and be independently understandable; do not refer to each other or to "above/below".'
    }
    $user += 'JSON formatting constraint: Return strictly valid JSON. No trailing commas. Do not include newline characters within any string value; each array element must be a single line.'

    $body = @{ 
        model = $Model
        messages = @(
            @{ role = 'system'; content = ($system -join "`n") },
            @{ role = 'user';   content = ($user   -join "`n") }
        )
        temperature = 0.2
    } | ConvertTo-Json -Depth 6

    return $body
}

function New-ResponsesPayload {
    param(
        [string]$StylePrompt,
        [string]$TemplateBody,
        [string]$JobType,
        [string]$SourceCardText,
        [hashtable]$UserNotes,
        [string[]]$NewFacts,
        [string]$CanonAdherence,
        [string]$Model,
        [string]$ContextText,
        [array]$FieldSpecs,
        [switch]$FieldsOnly,
        [hashtable]$InteractiveHints,
        [switch]$IncludeSourceInFieldsOnly
    )

    # Trim and distill the style prompt to avoid oversized inputs
    # Further reduce to a concise instruction
    $styleCondensed = "Apply codex voice: objective, concise, third-person. Keep Summary 1-2 sentences; Full Description 3-8 sentences; max 24 words/sentence; no semicolons; no metaphors. Each section must stand alone (do not assume the other is read; avoid 'above/below'). Name usage: Include the card's title name at least once in Summary and at least twice in Full Description (natural usage; avoid repetition)."

    $policyBlock = switch ($CanonAdherence) {
        'preserve-only' {
            @(
                'Canon Adherence: STRICT.',
                '- Do NOT add any facts not present in SOURCE CARD or USER NOTES.',
                '- Rephrase only; preserve dates, governance, hazards, tariffs, quotas, names.'
            ) -join "`n"
        }
        'augment' {
            @(
                'Canon Adherence: FLEXIBLE.',
                '- You may add minor connective details consistent with canon and USER NOTES.',
                '- Do NOT invent new entities, dates, or events unless listed under NEW FACTS AUTHORIZED.'
            ) -join "`n"
        }
        'create' {
            @(
                'Canon Adherence: CREATIVE.',
                '- You may create new lore consistent with style, tone, and setting.',
                '- Avoid contradictions and do NOT invent cross-references to unknown pages.'
            ) -join "`n"
        }
        default { 'Canon Adherence: STRICT.' }
    }

    $systemCore = @()
    $systemCore += 'You are a lore-writing model that strictly follows provided templates and writing style prompts.'
    if ($FieldsOnly) {
        $systemCore += 'Only generate the requested additional fields. Do not include Summary or Full Description.'
        $systemCore += 'Return JSON: {"fields": { <key>: value }}.'
    } else {
        $systemCore += 'Only generate the Summary and Full Description fields unless explicitly told otherwise.'
        if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
            $systemCore += 'Return JSON: {"summary": "...", "full_description": "...", "fields": { <key>: value } }.'
        } else {
            $systemCore += 'Return JSON: {"summary": "...", "full_description": "..."}.'
        }
    }
    $systemCore += $policyBlock
    $systemCore += $styleCondensed
    $systemCore = ($systemCore -join " `n").Trim()
    $systemCore = ConvertTo-SafeText $systemCore

    $userParts = @()
    $userParts += "JOB TYPE: $JobType"
    $canon = switch ($CanonAdherence) { 'preserve-only' { 'strict' } 'augment' { 'flexible' } 'create' { 'creative' } default { 'strict' } }
    $userParts += "CANON ADHERENCE: $canon"
    if ($UserNotes) {
        $userParts += 'USER NOTES:'
        $UserNotes.GetEnumerator() | ForEach-Object { $userParts += ("- {0}: {1}" -f $_.Key, ($_.Value -join ', ')) }
    }
    if ($NewFacts -and $NewFacts.Count -gt 0) {
        $userParts += 'NEW FACTS AUTHORIZED:'
        $NewFacts | ForEach-Object { $userParts += "- $_" }
    }
    if (-not $FieldsOnly) {
        if ($SourceCardText) {
            # Limit source length to avoid oversized payloads
            $src = $SourceCardText
            if ($src.Length -gt 6000) { $src = $src.Substring(0,6000) }
            $src = ConvertTo-SafeText $src
            $src = ConvertTo-UnicodeEscaped $src
            $userParts += "SOURCE CARD (facts to preserve):`n$src"
        }
        if ($ContextText) {
            $ctx = $ContextText
            if ($ctx.Length -gt 8000) { $ctx = $ctx.Substring(0,8000) }
            $ctx = ConvertTo-SafeText $ctx
            $ctx = ConvertTo-UnicodeEscaped $ctx
            $userParts += $ctx
        }
    } elseif ($IncludeSourceInFieldsOnly -and $SourceCardText) {
        # Provide current text as context even when fields-only
        $src = $SourceCardText
        if ($src.Length -gt 6000) { $src = $src.Substring(0,6000) }
        $src = ConvertTo-SafeText $src
        $src = ConvertTo-UnicodeEscaped $src
        $userParts += "SOURCE CARD (current text for context):`n$src"
    }
    if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
        $userParts += 'ADDITIONAL FIELDS TO FILL (write concise values; respect USER NOTES if provided):'
        foreach ($fs in $FieldSpecs) {
            $hint = if ($fs.isList) { 'array of strings' } else { 'string' }
            $line = ("- {0} ({1}) -> key: {2}" -f $fs.label, $hint, $fs.key)
            if ($fs.hint) { $line = $line + (" | Guidance: {0}" -f $fs.hint) }
            $userParts += $line
        }
    }
    if ($FieldsOnly) {
        if ($InteractiveHints -and $InteractiveHints.Keys.Count -gt 0) {
            $userParts += 'USER INTENT FOR SELECTED FIELDS:'
            foreach ($k in $InteractiveHints.Keys) {
                $hintVal = ("{0}" -f $InteractiveHints[$k])
                if ($hintVal -and $hintVal.Trim() -ne '') { $userParts += ("- {0}: {1}" -f $k, $hintVal) }
            }
            $userParts += 'If intent is provided, prefer generating replacements aligned to the hint.'
        }
        $userParts += 'OUTPUT: JSON with key fields only (object with the keys listed above).'
        $userParts += 'For array fields, return an array of strings; for text fields, return a string.'
        $userParts += 'Required: Return ALL requested keys under fields; do not omit any key. If unknown, infer a plausible concise value grounded in SOURCE and CONTEXT.'
        $userParts += 'No empty strings or empty arrays. For list fields, return 1-5 items (hooks: 1-3).'
    } else {
        function Invoke-DedupArrayPreserveOrder {
            param([object]$Val)
            $arr = @()
            if ($Val -is [System.Array]) { $arr = $Val }
            elseif ($Val) { $arr = @("$Val") } else { return @() }
            $seen = New-Object 'System.Collections.Generic.HashSet[string]'
            $out = @()
            foreach ($item in $arr) {
                if (-not $item) { continue }
                $norm = ("$item").Trim()
                $ci = $norm.ToLowerInvariant()
                if ($seen.Contains($ci)) { continue }
                [void]$seen.Add($ci)
                $out += $norm
            }
            return ,$out
        }

        if ($FieldSpecs -and $FieldSpecs.Count -gt 0) {
            $userParts += 'OUTPUT: JSON with keys summary, full_description, and fields (object with the keys listed above).'
            $userParts += 'For array fields, return an array of strings; for text fields, return a string.'
            # Add a specific constraint for Potential Gameplay Hooks semantics
            $hasHooks = $false
            foreach ($fs in $FieldSpecs) { if ($fs.key -eq 'potential_gameplay_hooks') { $hasHooks = $true } }
            if ($hasHooks) { $userParts += 'For Potential Gameplay Hooks: produce generic in-world events or complications tied to the subject, not player quests; 1-3 items, concise and specific.' }
        } else {
            $userParts += 'OUTPUT: JSON with keys summary, full_description only.'
        }
        $userParts += 'Constraints: objective, concise, third-person. 1-2 sentences for Summary. 3-8 sentences for Full Description. Max 24 words per sentence. No semicolons. No metaphors.'
        $userParts += 'Standalone requirement: Summary and Full Description must each stand alone and be independently understandable; do not refer to each other or to "above/below".'
    }
    $userParts += 'JSON formatting constraint: Return strictly valid JSON. No trailing commas. Do not include newline characters within any string value; each array element must be a single line.'
    $userText = ($userParts -join " `n").Trim()
    $userText = ConvertTo-SafeText $userText
    $userText = ConvertTo-UnicodeEscaped $userText

    # Use structured role/content for the Responses API
    $inputBlocks = @(
        @{ role = 'system'; content = @(@{ type = 'input_text'; text = $systemCore }) },
        @{ role = 'user';   content = @(@{ type = 'input_text'; text = $userText   }) }
    )

    $body = @{
        model = $Model
        input = $inputBlocks
        temperature = 0.2
        max_output_tokens = 1024
    } | ConvertTo-Json -Depth 8

    return $body
}

function Invoke-Model {
    param([string]$Payload, [string]$ApiKey, [string]$Endpoint)
    if (-not $ApiKey) { throw 'API key is required. Set -ApiKey or $env:OPENAI_API_KEY' }
    if (-not $Model) { throw 'Model is required. Set -Model or $env:OPENAI_MODEL' }
    $isAzure = ($Endpoint -match 'azure\.com') -or $Azure
    if ($isAzure) {
        $headers = @{ 'api-key' = $ApiKey; 'Content-Type' = 'application/json'; 'Accept'='application/json' }
        if ($Payload) {
            try {
                # Remove top-level "model" for Azure deployment-based endpoints
                $Payload = [regex]::Replace($Payload, '"model"\s*:\s*"[^"]+",?', '', 1)
                # Clean up trailing commas after removal
                $Payload = $Payload -replace ',\s*([}\]])', '$1'
            } catch {}
        }
    } else {
        $headers = @{ 'Authorization' = "Bearer $ApiKey"; 'Content-Type' = 'application/json'; 'Accept'='application/json' }
        if ($Endpoint -match '/v1/responses') { $headers['OpenAI-Beta'] = 'responses=v1' }
    }
    if ($DebugHttp) {
        Write-Host "HTTP Endpoint: $Endpoint" -ForegroundColor DarkCyan
        $hdrDump = @{}
        foreach ($k in $headers.Keys) {
            $v = $headers[$k]
            if ($k -eq 'Authorization') { $v = ($v.Substring(0,10) + '…') }
            $hdrDump[$k] = $v
        }
        Write-Host ("Request headers: {0}" -f ($hdrDump | ConvertTo-Json -Depth 5)) -ForegroundColor DarkCyan
        if ($Payload) { Write-Host ("Payload bytes: {0}" -f ([Text.Encoding]::UTF8.GetByteCount($Payload))) -ForegroundColor DarkCyan }
    }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $headers -Body $Payload -TimeoutSec 120 -ErrorAction Stop
        return $resp
    } catch {
        $detail = $null
        $statusCode = $null
        $statusDesc = $null
        $respHeaders = $null
        try {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDesc = $_.Exception.Response.StatusDescription
                $respHeaders = @{}
                foreach ($k in $_.Exception.Response.Headers.Keys) { $respHeaders[$k] = ($_.Exception.Response.Headers[$k] -join ', ') }
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $detail = $sr.ReadToEnd(); $sr.Close()
            }
        } catch {}
        if ($DebugHttp) {
            if ($respHeaders) { Write-Host ("Response headers: {0}" -f ($respHeaders | ConvertTo-Json -Depth 5)) -ForegroundColor DarkYellow }
            if ($detail) { Write-Host "HTTP error detail:" -ForegroundColor Yellow; Write-Output $detail }
        }
        # Persist diagnostic artifacts for analysis
        try {
            $errDir = Join-Path $PSScriptRoot '.errors'
            if (-not (Test-Path $errDir)) { New-Item -ItemType Directory -Path $errDir -Force | Out-Null }
            $attempts = Join-Path $errDir 'attempts'
            if (-not (Test-Path $attempts)) { New-Item -ItemType Directory -Path $attempts -Force | Out-Null }
            $isResponses = ($Endpoint -match '/v1/responses')
            $meta = [ordered]@{ endpoint = $Endpoint; model = $Model; isResponses = $isResponses; statusCode = $statusCode; status = $statusDesc; responseHeaders = $respHeaders }
            Set-Content -Path (Join-Path $errDir 'last_openai_meta.json') -Value ($meta | ConvertTo-Json -Depth 5) -Encoding utf8
            if ($Payload) { Set-Content -Path (Join-Path $errDir 'last_openai_payload.json') -Value $Payload -Encoding utf8 }
            if ($detail) { Set-Content -Path (Join-Path $errDir 'last_openai_error.json') -Value $detail -Encoding utf8 }
            $stamp = [DateTime]::UtcNow.Ticks
            Set-Content -Path (Join-Path $attempts ("{0}_meta.json" -f $stamp)) -Value ($meta | ConvertTo-Json -Depth 5) -Encoding utf8
            if ($Payload) { Set-Content -Path (Join-Path $attempts ("{0}_payload.json" -f $stamp)) -Value $Payload -Encoding utf8 }
            if ($detail) { Set-Content -Path (Join-Path $attempts ("{0}_error.json" -f $stamp)) -Value $detail -Encoding utf8 }
        } catch {}
        # Try to parse standard OpenAI error JSON for message/code
        $apiErrMsg = $null; $apiErrCode = $null; $apiErrType = $null; $apiErrParam = $null
        try {
            if ($detail -and ($detail.Trim().StartsWith('{'))) {
                $errObj = $detail | ConvertFrom-Json
                if ($errObj.error) {
                    $apiErrMsg = $errObj.error.message
                    $apiErrCode = $errObj.error.code
                    $apiErrType = $errObj.error.type
                    $apiErrParam = $errObj.error.param
                }
            }
        } catch {}
        $msg = $($_.Exception.Message)
        if ($statusCode) { $msg = "HTTP $statusCode $statusDesc :: $msg" }
        if ($apiErrMsg) { $msg = "$msg :: $apiErrMsg (code=$apiErrCode type=$apiErrType param=$apiErrParam)" }
        elseif ($detail) { $msg = "$msg :: $detail" }
        if ($respHeaders -and $respHeaders['x-request-id']) { $msg = "$msg :: request-id=$($respHeaders['x-request-id'])" }
        throw "Model call failed: $msg"
    }
}

function Set-CardSections {
    param(
        [string]$CardText,
        [string]$Summary,
        [string]$FullDescription,
        [hashtable]$AdditionalFields
    )
    # Replace the Summary and Full Description lines/blocks
    $inLines = $CardText -split "`n"
    $outLines = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $inLines.Length; $i++) {
        $line = $inLines[$i]
        if ($line -match '^\*\*Summary:\*\*') {
            $outLines.Add("**Summary:** $Summary") | Out-Null
            continue
        }
        if ($line -match '^\*\*Full Description:\*\*') {
            $outLines.Add("**Full Description:** $FullDescription") | Out-Null
            continue
        }
        $outLines.Add($line) | Out-Null
    }
    if ($AdditionalFields -and $AdditionalFields.Keys.Count -gt 0) {
        # Map for canonical labels and bullet-preferred fields
        $labelMap = @{
            'tone keywords' = 'Tone Keywords'
            'local inhabitants' = 'Local Inhabitants'
            'aligned factions' = 'Aligned Factions'
            'notable characters' = 'Notable Characters'
            'primary regions' = 'Primary Regions'
            'stature and build' = 'Stature and Build'
            'typical lifespan' = 'Typical Lifespan'
            'locations of note' = 'Locations of Note'
            'potential gameplay hooks' = 'Potential Gameplay Hooks'
            'aliases' = 'Aliases'
        }
        $bulletFields = New-Object 'System.Collections.Generic.HashSet[string]'
        [void]$bulletFields.Add('Potential Gameplay Hooks')

        # Replace label lines, supporting bullet output for certain fields
        for ($i=0; $i -lt $outLines.Count; $i++) {
            $curr = $outLines[$i]
            $m = [regex]::Match($curr, '^\*\*(.+?):\*\*')
            if (-not $m.Success) { continue }
            $labelFound = $m.Groups[1].Value
            $targetLabel = $labelFound
            $lk = $labelFound.ToLowerInvariant()
            if ($labelMap.ContainsKey($lk)) { $targetLabel = $labelMap[$lk] }
            $keyFromLabel = $targetLabel.ToLowerInvariant() -replace '[^a-z0-9]+','_'
            if (-not $AdditionalFields.ContainsKey($keyFromLabel)) { continue }
            $val = $AdditionalFields[$keyFromLabel]
            if ($null -eq $val -or $val -eq '') { continue }
            if ($bulletFields.Contains($targetLabel) -and ($val -is [System.Array])) {
                # Clean any existing bullet lines immediately following current heading
                $purgeIdx = $i + 1
                while ($purgeIdx -lt $outLines.Count -and $outLines[$purgeIdx] -match '^\-\s+') {
                    $outLines.RemoveAt($purgeIdx)
                }
                $outLines[$i] = ("**{0}:**" -f $targetLabel)
                $insertIdx = $i + 1
                $valsUnique = Invoke-DedupArrayPreserveOrder -Val $val
                foreach ($item in $valsUnique) {
                    $outLines.Insert($insertIdx, ("- {0}" -f ("$item").Trim()))
                    $insertIdx++
                }
            } else {
                $replacement = $val
                if ($val -is [System.Array]) {
                    $valsUnique2 = Invoke-DedupArrayPreserveOrder -Val $val
                    $replacement = ($valsUnique2 -join ', ')
                }
                $outLines[$i] = ("**{0}:** {1}" -f $targetLabel, $replacement)
            }
        }
    }
    # Ensure **Name:** auto-filled if blank
    for ($i=0; $i -lt $outLines.Count; $i++) {
        if ($outLines[$i] -match '^\*\*Name:\*\*\s*$') {
            $outLines[$i] = "**Name:** $Name"
        }
    }
    return ($outLines -join "`n")
}

function Get-ExistingCardText {
    param([string]$Path)
    if (Test-Path $Path) { return Get-Content -Path $Path -Raw } else { return $null }
}

# --- Main ---
$pack = $null
if (-not $MinimalTest) {
$pack = Get-PackPaths -Type $CardType
}

if ($VerbosePreview) {
    Write-Host "Using template:" $pack.template -ForegroundColor Cyan
    Write-Host "Using style prompt:" $pack.prompt -ForegroundColor Cyan
}

if (-not $MinimalTest) {
    $slug = ConvertTo-Slug -Text $Name
    $frontmatter = New-FrontMatter -Type $CardType -Name $Name -Parent $Parent -SeeAlso $SeeAlso
    $bodyTemplate = Get-SkeletonFromTemplate -TemplatePath $pack.template -Name $Name
} else {
    $bodyTemplate = @"
[ENTRY: Test]
**Name:**  
**Summary:**  
**Full Description:**  

[END: Test]
"@.Trim()
}

if (-not $MinimalTest) {
    # Prepare output path
    $outDir = Get-OutputDirectory -Type $CardType -EraOrTopic $EraOrTopicBucket
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outPath = Join-Path $outDir ("{0}.md" -f $Name)
}

# Coerce comma-separated strings into arrays for list params
if ($SeeAlso -and $SeeAlso.Count -eq 1 -and ($SeeAlso[0] -match ',')) { $SeeAlso = $SeeAlso[0].Split(',') | ForEach-Object { $_.Trim() } }
if ($ToneKeywords -and $ToneKeywords.Count -eq 1 -and ($ToneKeywords[0] -match ',')) { $ToneKeywords = $ToneKeywords[0].Split(',') | ForEach-Object { $_.Trim() } }
if ($LocationsOfNote -and $LocationsOfNote.Count -eq 1 -and ($LocationsOfNote[0] -match ',')) { $LocationsOfNote = $LocationsOfNote[0].Split(',') | ForEach-Object { $_.Trim() } }
if ($KnownLinks -and $KnownLinks.Count -eq 1 -and ($KnownLinks[0] -match ',')) { $KnownLinks = $KnownLinks[0].Split(',') | ForEach-Object { $_.Trim() } }
if ($NewFacts -and $NewFacts.Count -eq 1 -and ($NewFacts[0] -match ',')) { $NewFacts = $NewFacts[0].Split(',') | ForEach-Object { $_.Trim() } }

# Source text for rewrite jobs
if (-not $MinimalTest) {
    $sourceCard = if ($JobType -eq 'rewrite') { Get-ExistingCardText -Path $outPath } else { $null }
    $hasExisting = [string]::IsNullOrWhiteSpace($sourceCard) -eq $false
    if ($hasExisting) {
        $hasSummaryMarker = ($sourceCard -match '^\*\*Summary:\*\*')
        $hasFullMarker    = ($sourceCard -match '^\*\*Full Description:\*\*')
        if (-not ($hasSummaryMarker -and $hasFullMarker)) {
            Write-Host 'Legacy card format detected (missing Summary/Full markers). Converting using template.' -ForegroundColor Yellow
            $hasExisting = $false
        }
    }
} else {
    $sourceCard = "**Name:** Test`n**Summary:** (to be generated)`n**Full Description:** (to be generated)"
    $hasExisting = $false
}

# Determine default canon adherence if not explicitly provided; normalize labels
if ($CanonAdherence) {
    switch ($CanonAdherence.ToLowerInvariant()) {
        'strict'   { $CanonAdherence = 'preserve-only' }
        'flexible' { $CanonAdherence = 'augment' }
        'creative' { $CanonAdherence = 'create' }
        default { }
    }
}
if (-not $CanonAdherence) {
    $canonProvided = $PSBoundParameters.ContainsKey('CanonAdherence')
    $CanonAdherence = if ($JobType -eq 'rewrite') { 'preserve-only' } else { 'augment' }
    if ($NewFacts -and $NewFacts.Count -gt 0 -and $CanonAdherence -eq 'preserve-only') { $CanonAdherence = 'augment' }
    if (-not $canonProvided -and ($VerbosePreview -or $DryRun)) {
        $label = switch ($CanonAdherence) { 'preserve-only' { 'strict' } 'augment' { 'flexible' } 'create' { 'creative' } default { 'strict' } }
        Write-Host ("Canon Adherence auto-selected: {0} ({1})" -f $label, $CanonAdherence) -ForegroundColor DarkCyan
    }
}

$useResponses = (Test-ResponsesApi -ModelName $Model) -and (-not $ForceChat)

# If using 4.1 family, default to disabling chat fallback unless explicitly allowed
if (-not $ForceChat -and $useResponses -and ($Model -match '^gpt-4\.1')) {
    if (-not $PSBoundParameters.ContainsKey('NoChatFallback')) { $NoChatFallback = $true }
}

# Build request
$style = if ($MinimalTest) { 'Write concise, objective text for Summary (1-2 sentences) and Full Description (3-8 sentences). Each must stand alone.' } else { Get-WritingStylePrompt -PromptPath $pack.prompt }
$userNotes = @{}
# Always include fixed card metadata so the model knows the subject
$userNotes['name'] = @($Name)
$userNotes['card_type'] = @($CardType)
if ($ToneKeywords) { $userNotes['tone_keywords'] = $ToneKeywords }
if ($LocationsOfNote) { $userNotes['locations_of_note'] = $LocationsOfNote }
if ($KnownLinks) { $userNotes['links'] = $KnownLinks }
if ($Parent) { $userNotes['parent'] = @($Parent) }
if ($DesiredSummary) { $userNotes['desired_summary'] = @($DesiredSummary) }
if ($ExtraNotes) {
    foreach ($k in $ExtraNotes.Keys) {
        $val = $ExtraNotes[$k]
        if ($null -ne $val -and $val -ne '') {
            if ($val -is [System.Array]) { $userNotes[$k] = @($val) }
            else { $userNotes[$k] = @("$val") }
        }
    }
}

# Build context for parent lineage and linked cards
$contextText = $null
$fieldSpecs = @()
try {
    if (-not $MinimalTest) {
        $parentId = $null
        $linked = @()
        if ($JobType -eq 'new') {
            $parentId = $Parent
        } else {
            if ($hasExisting) {
                $fm = Read-FrontMatter -Path $outPath
                if (-not $fm) { $fm = Read-FrontMatter -Path $outPath }
                if ($fm -and $fm['parent']) { $parentId = $fm['parent'] }
                $linked = Get-LinkedCardsContext -SourcePath $outPath -FrontMatter $fm
            }
        }
        $parents = if ($parentId) { Get-ParentChainContext -StartParentId $parentId } else { @() }
        $contextText = Get-ContextText -ParentChain $parents -LinkedCards $linked
    }
} catch {
    Write-Warning "Context build failed: $($_.Exception.Message)"
}
if ($MinimalTest) {
    $fieldSpecs = @()
} elseif ($JobType -eq 'new') {
    $fieldSpecs = Get-TemplateFieldSpecs -TemplateBody $bodyTemplate
} elseif ($JobType -eq 'rewrite') {
    $allSpecs = Get-TemplateFieldSpecs -TemplateBody $bodyTemplate
    $existingVals = Get-ExistingFieldValues -CardText $sourceCard -FieldSpecs $allSpecs
    $fieldSpecs = @()
    foreach ($s in $allSpecs) {
        $key = $s.key
        $has = $existingVals.ContainsKey($key)
        $val = if ($has) { $existingVals[$key] } else { $null }
        $isPlaceholder = Test-PlaceholderValue -Key $key -Value $val
        if (-not $has -or $isPlaceholder) { $fieldSpecs += $s }
    }
}

if ($useResponses) {
    $Endpoint = 'https://api.openai.com/v1/responses'
    $payload = New-ResponsesPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $contextText -FieldSpecs $fieldSpecs
} else {
    $payload = New-RequestPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $contextText -FieldSpecs $fieldSpecs
}

if ($DryRun) {
    Write-Host "DRY RUN: would call model with payload:" -ForegroundColor Yellow
    if ($script:LinkedCardsDeduped) { Write-Host "Note: Linked Cards (deduped)" -ForegroundColor DarkGray }
    Write-Output $payload
    exit 0
}

if ($VerbosePreview) {
    Write-Host "Endpoint:" $Endpoint -ForegroundColor DarkCyan
    Write-Host "Payload:" -ForegroundColor DarkCyan
    if ($script:LinkedCardsDeduped) { Write-Host "Note: Linked Cards (deduped)" -ForegroundColor DarkGray }
    Write-Output $payload
}

# Call model; on Responses 400, attempt two-pass (A: summary/full via Responses, B: fields-only via Responses)
$response = $null
$content = $null
try {
    $response = Invoke-Model -Payload $payload -ApiKey $ApiKey -Endpoint $Endpoint
} catch {
    $errMsg = $_.Exception.Message
    $isResponses = ($Endpoint -match '/v1/responses')
    if ($isResponses -and ($errMsg -match '\(400\) Bad Request')) {
        Write-Host "Responses 400 detected. Attempting two-pass flow (Responses)…" -ForegroundColor Yellow
        # Pass A: summary/full only (Responses, minimal payload)
        $EndpointA = 'https://api.openai.com/v1/responses'
        $payloadA = New-ResponsesPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $contextText -FieldSpecs @()
        $summaryA = $null; $fullA = $null
        try {
            $respA = Invoke-Model -Payload $payloadA -ApiKey $ApiKey -Endpoint $EndpointA
            $jsonTextA = $null
            if ($respA.output_text) { $jsonTextA = $respA.output_text }
            elseif ($respA.output -and $respA.output.Count -gt 0) {
                $partsA = @()
                foreach ($blk in $respA.output) {
                    if ($blk.content) { foreach ($c in $blk.content) { if ($c.text) { $partsA += $c.text } elseif ($c.output_text) { $partsA += $c.output_text } } }
                }
                $jsonTextA = ($partsA -join "`n")
            }
            if (-not $jsonTextA) { throw "No output_text in Responses API reply (pass A)" }
            $objA = $jsonTextA | ConvertFrom-Json
            $summaryA = "$($objA.summary)".Trim()
            $fullA    = "$($objA.full_description)".Trim()
        } catch {
            if ($NoChatFallback) { throw }
            # Fallback for pass A via Chat (force a Chat-capable model)
            $fb = if ($FallbackModel -and ($FallbackModel -match '^(gpt-4o)')) { $FallbackModel } else { 'gpt-4o-mini' }
            Write-Host "Pass A failed. Retrying summary/full via Chat '$fb'…" -ForegroundColor Yellow
            $EndpointA = 'https://api.openai.com/v1/chat/completions'
            $payloadA = New-RequestPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $fb -ContextText $contextText -FieldSpecs @()
            $respA = Invoke-Model -Payload $payloadA -ApiKey $ApiKey -Endpoint $EndpointA
            $objA = $respA.choices[0].message.content | ConvertFrom-Json
            $summaryA = "$($objA.summary)".Trim()
            $fullA    = "$($objA.full_description)".Trim()
        }

        # Pass B: fields-only if needed (Responses)
        $fieldsObj = @{}
        if ($fieldSpecs -and $fieldSpecs.Count -gt 0) {
            try {
                $EndpointB = 'https://api.openai.com/v1/responses'
                $payloadB = New-ResponsesPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $contextText -FieldSpecs $fieldSpecs -FieldsOnly
                $respB = Invoke-Model -Payload $payloadB -ApiKey $ApiKey -Endpoint $EndpointB
                $jsonTextB = $null
                if ($respB.output_text) { $jsonTextB = $respB.output_text }
                elseif ($respB.output -and $respB.output.Count -gt 0) {
                    $partsB = @()
                    foreach ($blk in $respB.output) {
                        if ($blk.content) { foreach ($c in $blk.content) { if ($c.text) { $partsB += $c.text } elseif ($c.output_text) { $partsB += $c.output_text } } }
                    }
                    $jsonTextB = ($partsB -join "`n")
                }
                if (-not $jsonTextB) { throw "No output_text in Responses API reply (pass B)" }
                $objB = $jsonTextB | ConvertFrom-Json
                if ($objB.PSObject.Properties.Name -contains 'fields') { $fieldsObj = $objB.fields }
            } catch {
                if ($NoChatFallback) {
                    Write-Host "Pass B failed and chat fallback disabled. Proceeding without additional fields." -ForegroundColor Yellow
                    $fieldsObj = @{}
                } else {
                    # Fallback for pass B via Chat (force a Chat-capable model)
                    $fb = if ($FallbackModel -and ($FallbackModel -match '^(gpt-4o)')) { $FallbackModel } else { 'gpt-4o-mini' }
                    Write-Host "Pass B failed. Retrying fields-only via Chat '$fb'…" -ForegroundColor Yellow
                    try {
                        $EndpointB = 'https://api.openai.com/v1/chat/completions'
                        $payloadB = New-RequestPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $fb -ContextText $contextText -FieldSpecs $fieldSpecs -FieldsOnly
                        $respB = Invoke-Model -Payload $payloadB -ApiKey $ApiKey -Endpoint $EndpointB
                        $objB = $respB.choices[0].message.content | ConvertFrom-Json
                        if ($objB.PSObject.Properties.Name -contains 'fields') { $fieldsObj = $objB.fields }
                    } catch {
                        Write-Host "Pass B Chat fallback also failed. Proceeding without additional fields." -ForegroundColor Yellow
                        $fieldsObj = @{}
                    }
                }
            }
        }

        # Build content object from two passes
        $content = [ordered]@{ summary = $summaryA; full_description = $fullA }
        if ($fieldsObj -and $fieldsObj.PSObject) { $content['fields'] = $fieldsObj }
    } else {
        throw
    }
}

# Parse JSON result when not using two-pass content
if (-not $content) {
    try {
        if ($useResponses) {
            $jsonText = $null
            if ($response.output_text) { $jsonText = $response.output_text }
            elseif ($response.output -and $response.output.Count -gt 0) {
                $parts = @()
                foreach ($blk in $response.output) {
                    if ($blk.content) {
                        foreach ($c in $blk.content) {
                            if ($c.text) { $parts += $c.text }
                            elseif ($c.output_text) { $parts += $c.output_text }
                        }
                    }
                }
                $jsonText = ($parts -join "`n")
            }
            if (-not $jsonText) { throw "No output_text in Responses API reply" }
            $content = $jsonText | ConvertFrom-Json
        } else {
            $content = $response.choices[0].message.content | ConvertFrom-Json
        }
    } catch {
        throw "Failed to parse model JSON response: $($_.Exception.Message)"
    }
}

$summary = "$($content.summary)".Trim()
$fullDesc = "$($content.full_description)".Trim()

if ($MinimalTest) {
    Write-Host "Minimal Responses test succeeded." -ForegroundColor Green
    Write-Output (@{ summary=$summary; full_description=$fullDesc } | ConvertTo-Json -Depth 4)
    exit 0
}

# Assemble card text
$baseText = if ($hasExisting) { $sourceCard } else { $bodyTemplate }
# Merge model fields with ExtraNotes (ExtraNotes has precedence)
$additional = @{}
if ($content.PSObject.Properties.Name -contains 'fields') {
    foreach ($p in $content.fields.PSObject.Properties) {
        $additional[$p.Name] = $p.Value
    }
}
if ($ExtraNotes) {
    foreach ($k in $ExtraNotes.Keys) {
        $additional[$k] = $ExtraNotes[$k]
    }
}

# Sanitize Locations of Note: keep only specific, unique names (proper-noun-like)
if ($additional.ContainsKey('locations_of_note')) {
    $vals = $additional['locations_of_note']
    $clean = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($vals -is [System.Array]) {
        foreach ($it in $vals) {
            if (-not $it) { continue }
            $norm = ("$it").Trim('"',[char]39).Trim()
            if ($norm -eq '') { continue }
            $ci = $norm.ToLowerInvariant()
            if ($seen.Contains($ci)) { continue }
            if (Test-IsSpecificLocationName -Name $norm) {
                [void]$seen.Add($ci)
                $clean += $norm
            }
        }
    } elseif ($vals) {
        $norm = ("$vals").Trim('"',[char]39).Trim()
        if (Test-IsSpecificLocationName -Name $norm) { $clean = @($norm) }
    }
    if ($clean.Count -gt 0) { $additional['locations_of_note'] = $clean }
    else { $additional.Remove('locations_of_note') | Out-Null }
}

$editedText = Set-CardSections -CardText $baseText -Summary $summary -FullDescription $fullDesc -AdditionalFields $additional

# Retry pass: detect missing or placeholder fields and request targeted fills (max 2 attempts)
try {
    $retryAttempts = 0
    $maxRetry = 2
    $templateSpecs = Get-TemplateFieldSpecs -TemplateBody $bodyTemplate
    while ($retryAttempts -lt $maxRetry) {
        $currVals = Get-ExistingFieldValues -CardText $editedText -FieldSpecs $templateSpecs
        $missingSpecs = @()
        foreach ($s in $templateSpecs) {
            $k = $s.key
            $has = $currVals.ContainsKey($k)
            $val = if ($has) { $currVals[$k] } else { $null }
            if (-not $has -or (Test-PlaceholderValue -Key $k -Value $val)) { $missingSpecs += $s }
        }
        if (-not $missingSpecs -or $missingSpecs.Count -eq 0) { break }
        # Build a Fields-only payload for just the missing keys
        if ($useResponses) {
            $EndpointRetry = 'https://api.openai.com/v1/responses'
            $payloadRetry = New-ResponsesPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $sourceCard -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $null -FieldSpecs $missingSpecs -FieldsOnly
        } else {
            $EndpointRetry = 'https://api.openai.com/v1/chat/completions'
            $payloadRetry = New-RequestPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $null -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $null -FieldSpecs $missingSpecs -FieldsOnly
        }
        $respRetry = Invoke-Model -Payload $payloadRetry -ApiKey $ApiKey -Endpoint $EndpointRetry
        $retryFields = @{}
        if ($useResponses) {
            $jsonRetry = $null
            if ($respRetry.output_text) { $jsonRetry = $respRetry.output_text }
            elseif ($respRetry.output -and $respRetry.output.Count -gt 0) {
                $partsR = @()
                foreach ($blk in $respRetry.output) { if ($blk.content) { foreach ($c in $blk.content) { if ($c.text) { $partsR += $c.text } elseif ($c.output_text) { $partsR += $c.output_text } } } }
                $jsonRetry = ($partsR -join "`n")
            }
            if ($jsonRetry) { $objR = $jsonRetry | ConvertFrom-Json; if ($objR.fields) { $retryFields = $objR.fields } }
        } else {
            $objR = $respRetry.choices[0].message.content | ConvertFrom-Json
            if ($objR.fields) { $retryFields = $objR.fields }
        }
        if ($retryFields -and $retryFields.PSObject) {
            foreach ($p in $retryFields.PSObject.Properties) { $additional[$p.Name] = $p.Value }
            $editedText = Set-CardSections -CardText $editedText -Summary $summary -FullDescription $fullDesc -AdditionalFields $additional
        }
        $retryAttempts++
    }
} catch {
    Write-Host ("Missing-fields retry skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

if ($hasExisting) {
    $finalText = $editedText
} else {
    $final = @()
    $final += $frontmatter
    $final += ''
    $final += $editedText
    $finalText = $final -join "`n"
}
# Normalize problematic punctuation and mojibake before preview/write
$finalText = Convert-OutputText $finalText

# Auto-link: add wiki links under Links: for any mentioned existing card titles
try {
    $allTitles = Get-AllCardTitles
    if (-not $allTitles) { throw 'AllTitles set was null' }
    $existingLinks = Get-ExistingLinksFromBlock -CardText $finalText
    if (-not $existingLinks) { $existingLinks = New-Object 'System.Collections.Generic.HashSet[string]' }
    $mentions = Get-MentionedTitlesFromBody -CardText $finalText -AllTitles $allTitles -SelfTitle $Name
    if (-not $mentions) { $mentions = New-Object 'System.Collections.Generic.HashSet[string]' }
    # remove already-linked titles
    $toAdd = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($t in $mentions) { if ($t -and (-not $existingLinks.Contains($t))) { [void]$toAdd.Add($t) } }
    $finalText = Add-LinksToCardText -CardText $finalText -TitlesToAdd $toAdd
    # Recompute full Links set after insertion
    $allLinkedTitles = Get-ExistingLinksFromBlock -CardText $finalText
    if (-not $allLinkedTitles) { $allLinkedTitles = New-Object 'System.Collections.Generic.HashSet[string]' }
    # Resolve linked titles to card IDs and merge into see_also (only for existing cards)
    $linkedIds = @()
    foreach ($lt in $allLinkedTitles) {
        $p = Find-CardByTitle -Title $lt
        if ($p) {
            try {
                $fmT = Read-FrontMatter -Path $p
                if ($fmT -and $fmT['id']) { $linkedIds += $fmT['id'] }
            } catch {}
        }
    }
    if ($linkedIds.Count -gt 0) { $finalText = Update-SeeAlsoInCardText -CardText $finalText -IdsToMerge $linkedIds }
    # Stage potential missing references from field values (unknown titles)
    $script:PotentialRefsForLog = Get-UncreatedReferencesFromFields -CardText $finalText -TemplateBody $bodyTemplate -AllTitles $allTitles
} catch {
    Write-Host ("Auto-linking skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}
# Preview to user
Write-Host "\n===== PREVIEW: $Name ($CardType) =====" -ForegroundColor Green
Write-Output $finalText
Write-Host "===== END PREVIEW =====\n" -ForegroundColor Green

$confirmRaw = if ($AutoApply) { 'y' } else { Read-Host 'Apply changes to file? (y/n)' }
$confirm = Resolve-Choice -UserInput $confirmRaw -Map @{ yes=@('y','yes'); no=@('n','no') } -Default 'no'
if ($confirm -ne 'yes') {
    while ($true) {
        $nextRaw = Read-Host 'Next action: [e]dit selected Card Fields or [x] exit generation? (e/x)'
        $next = Resolve-Choice -UserInput $nextRaw -Map @{ edit=@('e','edit'); exit=@('x','exit','q','quit') } -Default 'edit'
        if ($next -eq 'exit') {
            Write-Host 'Aborted by user. No changes written.' -ForegroundColor Yellow
            return
        }
        if ($next -ne 'edit') { continue }

        # Collect field specs and user selection
        $templateSpecs = Get-TemplateFieldSpecs -TemplateBody $bodyTemplate
        $names = Read-Host 'Card Fields to edit (comma-separated labels or keys)'
        $rawFields = @()
        if ($names) { $rawFields = $names.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
        $selectedSpecs = @()
        foreach ($nf in $rawFields) {
            $found = $null
            # Match by label (case-insensitive)
            $found = $templateSpecs | Where-Object { $_.label -and ($_.label.Trim().ToLowerInvariant() -eq $nf.ToLowerInvariant()) }
            if (-not $found -or $found.Count -eq 0) {
                # Match by key
                $found = $templateSpecs | Where-Object { $_.key -and ($_.key.Trim().ToLowerInvariant() -eq $nf.ToLowerInvariant()) }
            }
            if ($found) { $selectedSpecs += $found }
        }
        if (-not $selectedSpecs -or $selectedSpecs.Count -eq 0) {
            Write-Host 'No matching Card Fields found. Try again.' -ForegroundColor Yellow
            continue
        }

        $modeRaw = Read-Host 'Edit mode: [m]anual or [i]nteractive? (m/i)'
        $mode = Resolve-Choice -UserInput $modeRaw -Map @{ manual=@('m','manual'); interactive=@('i','interactive') } -Default 'interactive'
        if ($mode -eq 'manual') {
            foreach ($fs in $selectedSpecs) {
                if ($fs.isList -or $fs.bullet) {
                    $inp = Read-Host ("Enter items for '{0}' (comma-separated)" -f $fs.label)
                    $vals = @()
                    if ($inp) { $vals = $inp.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
                    $additional[$fs.key] = $vals
                } else {
                    $inp = Read-Host ("Enter text for '{0}'" -f $fs.label)
                    $additional[$fs.key] = $inp
                }
            }
        } elseif ($mode -eq 'interactive') {
            # Fields-only generation for selected specs using current edited text as source
            if (-not $ApiKey) {
                Write-Host 'Interactive mode skipped: API key not set.' -ForegroundColor Yellow
            } else {
                try {
                    # Build stripped source: remove existing values for selected fields to reduce echoing
                    $currentSource = $editedText
                    try {
                        $linesIS = $editedText -split "`n"
                        $labelsToStrip = New-Object 'System.Collections.Generic.HashSet[string]'
                        foreach ($s in $selectedSpecs) { if ($s.label) { [void]$labelsToStrip.Add($s.label) } }
                        $rebuilt = New-Object System.Collections.Generic.List[string]
                        for ($ix = 0; $ix -lt $linesIS.Length; $ix++) {
                            $lnIS = $linesIS[$ix]
                            $mIS = [regex]::Match($lnIS,'^\*\*(.+?):\*\*')
                            if ($mIS.Success) {
                                $lblIS = $mIS.Groups[1].Value
                                if ($labelsToStrip.Contains($lblIS)) {
                                    $specIS = $selectedSpecs | Where-Object { $_.label -eq $lblIS }
                                    if ($specIS -and ($specIS.bullet -or $specIS.isList)) {
                                        # Replace heading with blank value; skip following bullet lines
                                        $rebuilt.Add("**${lblIS}:**") | Out-Null
                                        $skip = $ix + 1
                                        while ($skip -lt $linesIS.Length -and $linesIS[$skip] -match '^\-\s+') { $skip++ }
                                        $ix = $skip - 1
                                        continue
                                    } else {
                                        $rebuilt.Add("**${lblIS}:**") | Out-Null
                                        continue
                                    }
                                }
                            }
                            $rebuilt.Add($lnIS) | Out-Null
                        }
                        $currentSource = ($rebuilt -join "`n")
                    } catch { Write-Host ("Strip existing field values failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
                    $appendRaw = Read-Host 'List field merge strategy: [a]ppend or [r]eplace existing content? (a/r, default=r)'
                    $appendChoice = Resolve-Choice -UserInput $appendRaw -Map @{ append=@('a','append'); replace=@('r','replace') } -Default 'replace'
                    $doAppend = ($appendChoice -eq 'append')
                    # Optional per-field hints from user
                    $hints = @{}
                    foreach ($fs in $selectedSpecs) {
                        $hintIn = Read-Host ("Optional hint for '{0}' (press Enter to skip)" -f $fs.label)
                        if ($hintIn) { $hints[$fs.key] = $hintIn }
                    }
                    if ($useResponses) {
                        $EndpointSel = 'https://api.openai.com/v1/responses'
                        $payloadSel = New-ResponsesPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $currentSource -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $null -FieldSpecs $selectedSpecs -FieldsOnly -InteractiveHints $hints -IncludeSourceInFieldsOnly
                        $respSel = Invoke-Model -Payload $payloadSel -ApiKey $ApiKey -Endpoint $EndpointSel
                        $jsonSel = $null
                        if ($respSel.output_text) { $jsonSel = $respSel.output_text }
                        elseif ($respSel.output -and $respSel.output.Count -gt 0) {
                            $partsS = @()
                            foreach ($blk in $respSel.output) { if ($blk.content) { foreach ($c in $blk.content) { if ($c.text) { $partsS += $c.text } elseif ($c.output_text) { $partsS += $c.output_text } } } }
                            $jsonSel = ($partsS -join "`n")
                        }
                        if ($jsonSel) {
                            $objS = $jsonSel | ConvertFrom-Json
                            if ($objS.fields) {
                                foreach ($p in $objS.fields.PSObject.Properties) {
                                    $newVal = $p.Value
                                    if ($doAppend -and $additional.ContainsKey($p.Name) -and ($newVal -is [System.Array])) {
                                        $existingVal = $additional[$p.Name]
                                        $merged = @()
                                        if ($existingVal -is [System.Array]) { $merged = @($existingVal + $newVal) } else { $merged = @($existingVal) + $newVal }
                                        $additional[$p.Name] = (Invoke-DedupArrayPreserveOrder -Val $merged)
                                    } else {
                                        # Replace; still dedupe arrays
                                        if ($newVal -is [System.Array]) { $additional[$p.Name] = (Invoke-DedupArrayPreserveOrder -Val $newVal) } else { $additional[$p.Name] = $newVal }
                                    }
                                }
                            }
                        }
                    } else {
                        $EndpointSel = 'https://api.openai.com/v1/chat/completions'
                        $payloadSel = New-RequestPayload -StylePrompt $style -TemplateBody $bodyTemplate -JobType $JobType -SourceCardText $currentSource -UserNotes $userNotes -NewFacts $NewFacts -CanonAdherence $CanonAdherence -Model $Model -ContextText $null -FieldSpecs $selectedSpecs -FieldsOnly -InteractiveHints $hints -IncludeSourceInFieldsOnly
                        $respSel = Invoke-Model -Payload $payloadSel -ApiKey $ApiKey -Endpoint $EndpointSel
                        $objS = $respSel.choices[0].message.content | ConvertFrom-Json
                        if ($objS.fields) {
                            foreach ($p in $objS.fields.PSObject.Properties) {
                                $newVal = $p.Value
                                if ($doAppend -and $additional.ContainsKey($p.Name) -and ($newVal -is [System.Array])) {
                                    $existingVal = $additional[$p.Name]
                                    $merged = @()
                                    if ($existingVal -is [System.Array]) { $merged = @($existingVal + $newVal) } else { $merged = @($existingVal) + $newVal }
                                    $additional[$p.Name] = (Invoke-DedupArrayPreserveOrder -Val $merged)
                                } else {
                                    if ($newVal -is [System.Array]) { $additional[$p.Name] = (Invoke-DedupArrayPreserveOrder -Val $newVal) } else { $additional[$p.Name] = $newVal }
                                }
                            }
                        }
                    }
                } catch {
                    Write-Host ("Interactive fill failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
                }
            }
        } else {
            continue
        }

        # Re-sanitize Locations of Note after edits
        if ($additional.ContainsKey('locations_of_note')) {
            $vals2 = $additional['locations_of_note']
            $clean2 = @()
            $seen2 = New-Object 'System.Collections.Generic.HashSet[string]'
            if ($vals2 -is [System.Array]) {
                foreach ($it in $vals2) {
                    if (-not $it) { continue }
                    $norm2 = ("$it").Trim('"',[char]39).Trim()
                    if ($norm2 -eq '') { continue }
                    $ci2 = $norm2.ToLowerInvariant()
                    if ($seen2.Contains($ci2)) { continue }
                    if (Test-IsSpecificLocationName -Name $norm2) { [void]$seen2.Add($ci2); $clean2 += $norm2 }
                }
            } elseif ($vals2) {
                $norm2 = ("$vals2").Trim('"',[char]39).Trim()
                if (Test-IsSpecificLocationName -Name $norm2) { $clean2 = @($norm2) }
            }
            if ($clean2.Count -gt 0) { $additional['locations_of_note'] = $clean2 } else { $additional.Remove('locations_of_note') | Out-Null }
        }

        # Rebuild edited text with new AdditionalFields
        $editedText = Set-CardSections -CardText $editedText -Summary $summary -FullDescription $fullDesc -AdditionalFields $additional

        # Rebuild final text (frontmatter + normalization + autolinking) and preview again
        if ($hasExisting) { $finalText = $editedText } else { $finalText = ($frontmatter + "`n`n" + $editedText) }
        $finalText = Convert-OutputText $finalText
        try {
            $allTitles2 = Get-AllCardTitles
            if (-not $allTitles2) { throw 'AllTitles set was null' }
            $existingLinks2 = Get-ExistingLinksFromBlock -CardText $finalText
            if (-not $existingLinks2) { $existingLinks2 = New-Object 'System.Collections.Generic.HashSet[string]' }
            $mentions2 = Get-MentionedTitlesFromBody -CardText $finalText -AllTitles $allTitles2 -SelfTitle $Name
            if (-not $mentions2) { $mentions2 = New-Object 'System.Collections.Generic.HashSet[string]' }
            $toAdd2 = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($t in $mentions2) { if ($t -and (-not $existingLinks2.Contains($t))) { [void]$toAdd2.Add($t) } }
            $finalText = Add-LinksToCardText -CardText $finalText -TitlesToAdd $toAdd2
            $allLinkedTitles2 = Get-ExistingLinksFromBlock -CardText $finalText
            if (-not $allLinkedTitles2) { $allLinkedTitles2 = New-Object 'System.Collections.Generic.HashSet[string]' }
            $linkedIds2 = @()
            foreach ($lt2 in $allLinkedTitles2) {
                $p2 = Find-CardByTitle -Title $lt2
                if ($p2) {
                    try { $fmT2 = Read-FrontMatter -Path $p2; if ($fmT2 -and $fmT2['id']) { $linkedIds2 += $fmT2['id'] } } catch {}
                }
            }
            if ($linkedIds2.Count -gt 0) { $finalText = Update-SeeAlsoInCardText -CardText $finalText -IdsToMerge $linkedIds2 }
            $script:PotentialRefsForLog = Get-UncreatedReferencesFromFields -CardText $finalText -TemplateBody $bodyTemplate -AllTitles $allTitles2
        } catch {
            Write-Host ("Auto-linking skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }

        Write-Host "\n===== PREVIEW: $Name ($CardType) =====" -ForegroundColor Green
        Write-Output $finalText
        Write-Host "===== END PREVIEW =====\n" -ForegroundColor Green

        $confirm2Raw = Read-Host 'Apply changes to file? (y/n)'
        $confirm2 = Resolve-Choice -UserInput $confirm2Raw -Map @{ yes=@('y','yes'); no=@('n','no') } -Default 'no'
        if ($confirm2 -eq 'yes') { break } else { continue }
    }
}

# Write file
$finalText | Out-File -FilePath $outPath -Encoding UTF8 -Force
Write-Host "Saved: $outPath" -ForegroundColor Cyan

# Write potential cards log, if any unknown titles were detected in cross-reference fields
try {
    if ($script:PotentialRefsForLog -and $script:PotentialRefsForLog.Count -gt 0) {
        $wsRoot = (Split-Path $PSScriptRoot -Parent)
        Write-PotentialCardsLog -WorkspaceRoot $wsRoot -SourceName $Name -SourceType $CardType -SourcePath $outPath -UnknownByField $script:PotentialRefsForLog
    }
} catch {
    Write-Host ("Potential-cards logging skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

# Optionally trigger index update
$runIndexerRaw = if ($AutoIndex) { 'y' } else { Read-Host 'Run update_lore_indexes.ps1 now? (y/n)' }
$runIndexer = Resolve-Choice -UserInput $runIndexerRaw -Map @{ yes=@('y','yes'); no=@('n','no') } -Default 'no'
if ($runIndexer -eq 'yes') {
    $wsRoot = (Split-Path $PSScriptRoot -Parent)
    $toolsScript = Join-Path $wsRoot 'tools\update_lore_indexes.ps1'
    $rootScript  = Join-Path $wsRoot 'update_lore_indexes.ps1'
    $scriptToRun = $null
    if (Test-Path $toolsScript) { $scriptToRun = $toolsScript }
    elseif (Test-Path $rootScript) { $scriptToRun = $rootScript }
    if (-not $scriptToRun) {
        Write-Warning "update_lore_indexes.ps1 not found at '$toolsScript' or '$rootScript'"
    } else {
        Write-Host ("Running indexer: {0}" -f $scriptToRun) -ForegroundColor DarkCyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$scriptToRun"
    }
}
