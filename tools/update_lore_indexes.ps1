# update_lore_indexes.ps1
# Auto-generates lore category index files for Heart of the Forest
# Also validates bracket wrappers and cross-card references

$rootPath = "Lore/Lorebook"

# ==============================
# Frontmatter parsing and graph
# ==============================
# Tolerant YAML frontmatter extractor (no PS7 required). Parses minimal keys: id, type, name, parent, see_also
function Get-Frontmatter {
    param([string]$Path)
    $raw = Get-Content -Path $Path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if (-not $raw) { return $null }
    if ($raw -notmatch "(?s)^---\s*\n(.*?)\n---") { return $null }
    $fm = ([regex]"(?s)^---\s*\n(.*?)\n---").Match($raw).Groups[1].Value

    $obj = [ordered]@{ id=$null; type=$null; name=$null; parent=$null; see_also=@() }
    foreach ($line in ($fm -split "\r?\n")) {
        $trim = $line.Trim()
        if ($trim -match "^id\s*:\s*(.+)$") { $obj.id = $Matches[1].Trim() }
        elseif ($trim -match "^type\s*:\s*(.+)$") { $obj.type = $Matches[1].Trim() }
        elseif ($trim -match "^name\s*:\s*(.+)$") { $obj.name = $Matches[1].Trim() }
        elseif ($trim -match "^parent\s*:\s*(.+)$") { $obj.parent = $Matches[1].Trim() }
        elseif ($trim -match "^see_also\s*:\s*\[(.*)\]\s*$") {
            $list = $Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $obj.see_also = $list
        }
    }
    # Handle multiline YAML list for see_also
    if ($fm -match "(?ms)see_also\s*:\s*\n(\s*-\s*.+\n)+") {
        $block = ([regex]"(?ms)see_also\s*:\s*\n(\s*-\s*.+\n)+").Match($fm).Groups[0].Value
        $items = @()
        foreach ($ln in ($block -split "\r?\n")) { if ($ln -match "^\s*-\s*(.+)$") { $items += $Matches[1].Trim() } }
        if ($items.Count -gt 0) { $obj.see_also = $items }
    }
    return $obj
}

function ConvertTo-IdSafe {
    param([string]$s)
    if (-not $s) { return "_" }
    return ($s -replace "[^A-Za-z0-9_]", "_")
}

$graphNodes = @{}
$graphChildren = @{}
$graphSeeAlso = @{}

# Scan all lore cards to collect frontmatter graph data
Get-ChildItem -Path $rootPath -Recurse -Filter "*.md" | ForEach-Object {
    $fm = Get-Frontmatter -Path $_.FullName
    if ($fm -and $fm.id) {
        if ($graphNodes.ContainsKey($fm.id)) { Write-Warning "Duplicate id detected: $($fm.id) in $($_.FullName)" }
        $nodeName = $fm.name
        if (-not $nodeName -or $nodeName -eq "") { $nodeName = $_.BaseName }
        $graphNodes[$fm.id] = [ordered]@{ id=$fm.id; type=$fm.type; name=$nodeName; parent=$fm.parent; path=$_.FullName }
        if ($fm.parent) { if (-not $graphChildren.ContainsKey($fm.parent)) { $graphChildren[$fm.parent] = @() }; $graphChildren[$fm.parent] += $fm.id }
        if ($fm.see_also) { $graphSeeAlso[$fm.id] = $fm.see_also }
    }
}

# Basic parent existence check
foreach ($kv in $graphNodes.GetEnumerator()) {
    $n = $kv.Value
    if ($n.parent -and -not $graphNodes.ContainsKey($n.parent)) {
        Write-Warning "Missing parent id '$($n.parent)' for node '$($n.id)' ($($n.name))"
    }
}

# Simple cycle detection via parent walk
function Test-Cycle {
    param([string]$id)
    $seen = @{}
    $cur = $id
    for ($i=0; $i -lt 1000; $i++) {
        if (-not $graphNodes.ContainsKey($cur)) { return $false }
        $p = $graphNodes[$cur].parent
        if (-not $p) { return $false }
        if ($seen.ContainsKey($p)) { return $true }
        $seen[$p] = $true
        $cur = $p
    }
    return $true
}

foreach ($kv in $graphNodes.Keys) {
    if (Test-Cycle -id $kv) { Write-Warning "Cycle detected starting at id '$kv'" }
}

# Helper: validate bracket wrappers in a file
function Test-Wrappers {
    param([string]$Path)
    $nameLine = Select-String -Path $Path -Pattern '^\*\*Name:\*\*\s*(.+)$' -SimpleMatch:$false | Select-Object -First 1
    if (-not $nameLine) { return $false }
    $name = ($nameLine.Matches[0].Groups[1].Value).Trim()
    $content = Get-Content -Path $Path -Raw -Encoding utf8
    $entryTag = "[ENTRY: $name]"
    $endTag = "[END: $name]"
    return ($content -like "*$entryTag*" -and $content -like "*$endTag*")
}

# Helper: extract referenced card names from special fields
function Get-References {
    param([string]$Path)
    $content = Get-Content -Path $Path -Raw -Encoding utf8
    $refs = @()

    # Locations of Note
    $locMatch = [regex]::Match($content, '\\*\\*Locations of Note:\\*\\*\\s*(.+)')
    if ($locMatch.Success) {
        $refs += ($locMatch.Groups[1].Value -split ',').ForEach({ $_.Trim() })
    }

    # Aligned Characters
    $charMatch = [regex]::Match($content, '\\*\\*Aligned Characters:\\*\\*\\s*(.+)')
    if ($charMatch.Success) {
        $refs += ($charMatch.Groups[1].Value -split ',').ForEach({ $_.Trim() })
    }

    return $refs | Where-Object { $_ -ne '' }
}

# Helper: extract the one-line Summary field

# Helper: extract the full lore card content between [ENTRY: Name] and [END: Name]
function Get-CardContent {
    param([string]$Path)
    $content = Get-Content -Path $Path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if (-not $content) { return $null }
    $nameLine = Select-String -Path $Path -Pattern '^\*\*Name:\*\*\s*(.+)$' -SimpleMatch:$false | Select-Object -First 1
    if (-not $nameLine) { return $null }
    $name = ($nameLine.Matches[0].Groups[1].Value).Trim()
    $entryTag = "[ENTRY: $name]"
    $endTag = "[END: $name]"
    $start = $content.IndexOf($entryTag)
    $end = $content.IndexOf($endTag)
    if ($start -lt 0 -or $end -lt 0 -or $end -le $start) { return $null }
    $card = $content.Substring($start + $entryTag.Length, $end - ($start + $entryTag.Length)).Trim()
    return $card
}

# Build a set of all card names by file base name
$allCards = @{}
Get-ChildItem -Path $rootPath -Recurse -Filter "*.md" | ForEach-Object {
    $base = $_.BaseName
    $allCards[$base] = $true
}

# Container folders to skip from index generation noise
$skipIndexDirs = @('Beings','Concepts','History','Objects','Places')

# Iterate through each category folder
Get-ChildItem -Path $rootPath -Directory | ForEach-Object {
    $folder = $_.FullName
    $categoryName = $_.Name
    if ($skipIndexDirs -contains $categoryName) { return }
    $indexFile = Join-Path $folder ("$categoryName.md")

    # Collect all .md files excluding the index file itself
    $entries = Get-ChildItem -Path $folder -Filter "*.md" | Where-Object { $_.Name -ne "$categoryName.md" }

    if ($entries.Count -gt 0) {
        $title = "# $categoryName`n`nIndex of $($categoryName.ToLower()) entries:`n"
        $links = $entries | Sort-Object Name | ForEach-Object {
            $name = $_.BaseName
            $encoded = [System.Uri]::EscapeDataString($_.Name)
            "- [$name]($encoded)"
        }

        $content = $title + "`n" + ($links -join "`n") + "`n"
        Set-Content -Path $indexFile -Value $content -Encoding utf8
        Write-Host "Updated index for $categoryName"
    }
    else {
        Write-Host "No entries found in $categoryName. Skipping."
    }
}

# ==============================
# Mermaid graph export (partial trees tolerated)
# ==============================
$mermaid = @()
$mermaid += '```mermaid'
$mermaid += '%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 80, "rankSpacing": 150}, "theme": "dark", "themeVariables": {"background": "#181a20", "primaryColor": "#23272f", "edgeColor": "#e2e8f0", "fontFamily": "Segoe UI, Roboto, sans-serif", "fontSize": "16px", "nodeTextColor": "#e2e8f0", "lineColor": "#e2e8f0", "secondaryColor": "#23272f", "tertiaryColor": "#23272f"}}}%%'
$mermaid += 'flowchart TD'

# Define classes for node types
$typeClassMap = @{
  'world' = 'world';
  'realm' = 'realm';
  'region' = 'region';
  'biome' = 'biome';
  'location' = 'location';
  'point' = 'point';
  'faction' = 'faction';
  'character' = 'character';
    'creature' = 'creature';
  'concept' = 'concept';
    'place-concept' = 'placeConcept';
    'place-feature' = 'placeConcept';
  'history' = 'history';
  'object' = 'object';
  'class' = 'role';
  'race' = 'race'
}

# Mermaid class definitions (colors)
$mermaid += '  classDef world fill:#2b6cb0,stroke:#1a4369,color:#ffffff;'
$mermaid += '  classDef realm fill:#d69e2e,stroke:#b7791f,color:#1a202c;'
$mermaid += '  classDef region fill:#38a169,stroke:#276749,color:#ffffff;'
$mermaid += '  classDef biome fill:#dd6b20,stroke:#9c4221,color:#ffffff;'
$mermaid += '  classDef location fill:#06b6d4,stroke:#0891b2,color:#ffffff;'
$mermaid += '  classDef point fill:#805ad5,stroke:#553c9a,color:#ffffff;'
$mermaid += '  classDef faction fill:#22c55e,stroke:#15803d,color:#ffffff;'
$mermaid += '  classDef character fill:#d53f8c,stroke:#97266d,color:#ffffff;'
$mermaid += '  classDef creature fill:#3b82f6,stroke:#1d4ed8,color:#ffffff;'
$mermaid += '  classDef concept fill:#cbd5e0,stroke:#a0aec0,color:#1a202c;'
$mermaid += '  classDef placeConcept fill:#f472b6,stroke:#be185d,color:#ffffff;'
$mermaid += '  classDef history fill:#ecc94b,stroke:#b7791f,color:#1a202c;'
$mermaid += '  classDef object fill:#38b2ac,stroke:#2c7a7b,color:#1a202c;'
$mermaid += '  classDef role fill:#4a5568,stroke:#2d3748,color:#ffffff;'
$mermaid += '  classDef race fill:#c53030,stroke:#9b2c2c,color:#ffffff;'

# Add node scaling CSS for larger nodes (20% wider, 50% taller)
# Removed custom rectWidth/rectHeight init (was causing edge label misalignment)

# Inline style fallback for renderers that ignore classDef inside subgraphs
$typeStyleMap = @{
  'world'         = @{ fill = '#2b6cb0'; stroke = '#1a4369'; color = '#ffffff' };
    'realm'         = @{ fill = '#d69e2e'; stroke = '#b7791f'; color = '#1a202c' };
  'region'        = @{ fill = '#38a169'; stroke = '#276749'; color = '#ffffff' };
  'biome'         = @{ fill = '#dd6b20'; stroke = '#9c4221'; color = '#ffffff' };
    'location'      = @{ fill = '#06b6d4'; stroke = '#0891b2'; color = '#ffffff' };
    'point'         = @{ fill = '#805ad5'; stroke = '#553c9a'; color = '#ffffff' };
    'faction'       = @{ fill = '#22c55e'; stroke = '#15803d'; color = '#ffffff' };
  'character'     = @{ fill = '#d53f8c'; stroke = '#97266d'; color = '#ffffff' };
    'creature'      = @{ fill = '#3b82f6'; stroke = '#1d4ed8'; color = '#ffffff' };
  'concept'       = @{ fill = '#cbd5e0'; stroke = '#a0aec0'; color = '#1a202c' };
    'place-concept' = @{ fill = '#f472b6'; stroke = '#be185d'; color = '#ffffff' };
    'place-feature' = @{ fill = '#f472b6'; stroke = '#be185d'; color = '#ffffff' };
  'event'         = @{ fill = '#ecc94b'; stroke = '#b7791f'; color = '#1a202c' };
  'object'        = @{ fill = '#38b2ac'; stroke = '#2c7a7b'; color = '#1a202c' };
  'class'         = @{ fill = '#4a5568'; stroke = '#2d3748'; color = '#ffffff' };
    'race'          = @{ fill = '#c53030'; stroke = '#9b2c2c'; color = '#ffffff' }
}

# Explicit node emission without subgraph wrappers for cleaner labels
foreach ($node in $graphNodes.Values) {
    $sid = ConvertTo-IdSafe $node.id
    $label = $(
        $labelTypeMap = @{
            'world'='World'; 'realm'='Realm'; 'region'='Region'; 'biome'='Biome';
            'location'='Location'; 'point'='Point'; 'faction'='Faction'; 'character'='Character'; 'creature'='Creature';
            'concept'='Concept'; 'place-concept'='Place Feature'; 'place-feature'='Place Feature'; 'history'='History'; 'object'='Object';
            'class'='Role'; 'race'='Race'
        }
        $typeLabel = $labelTypeMap[$node.type]
        if (-not $typeLabel) {
            $typeLabel = ($node.type -replace '-', ' ')
            $ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
            $typeLabel = $ti.ToTitleCase($typeLabel.ToLowerInvariant())
        }
        $displayName = $node.name
        if (-not $displayName -or $displayName -eq '') {
            $displayName = [IO.Path]::GetFileNameWithoutExtension($node.path)
            $displayName = ($displayName -replace '[_-]', ' ').Trim()
            $displayName = ($displayName -replace '\\s{2,}', ' ')
            $ti2 = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
            $displayName = $ti2.ToTitleCase($displayName.ToLowerInvariant())
        }
        "{0}: {1}" -f $typeLabel, $displayName
    )
    $placeTypes = @('world','realm','region','biome','location','point','place-concept','place-feature')
    if ($placeTypes -contains $node.type) {
        # Stadium shape for all place nodes
        $mermaid += ('  {0}(["{1}"])' -f $sid, $label)
    } else {
        # Default rectangle for non-place nodes
        $mermaid += ('  {0}["{1}"]' -f $sid, $label)
    }
    if ($typeClassMap.ContainsKey($node.type)) { $mermaid += ('  class {0} {1}' -f $sid, $typeClassMap[$node.type]) }
}

# Emit parent -> child edges (solid)
foreach ($kv in $graphNodes.GetEnumerator()) {
    $id = $kv.Key; $n = $kv.Value
    if ($n.parent) {
        $pSid = ConvertTo-IdSafe $n.parent
        $cSid = ConvertTo-IdSafe $id
        $mermaid += ('  {0} --> {1}' -f $pSid, $cSid)
    }
}

# Apply inline styles after all nodes and edges
foreach ($n in $graphNodes.Values) {
    if ($typeStyleMap.ContainsKey($n.type)) {
        $sid = ConvertTo-IdSafe $n.id
    $st = $typeStyleMap[$n.type]
    $mermaid += ('  style {0} fill:{1},stroke:{2},color:{3}' -f $sid, $st.fill, $st.stroke, $st.color)
  }
}

# Emit see_also edges (dotted) with toggle
$includeSeeAlso = $true
$seeAlsoLabel = $false  # set to $true to restore "see also" labels
if ($includeSeeAlso) {
    foreach ($kv in $graphSeeAlso.GetEnumerator()) {
        $from = ConvertTo-IdSafe $kv.Key
        foreach ($to in $kv.Value) {
            $tSid = ConvertTo-IdSafe $to
            if ($seeAlsoLabel) {
                $mermaid += ('  {0} -. "see also" .-> {1}' -f $from, $tSid)
            } else {
                # Unlabeled dotted edge for cleaner alignment
                $mermaid += ('  {0} -.-> {1}' -f $from, $tSid)
            }
        }
    }
}
$mermaid += '```'

$treePath = Join-Path -Path "Lore" -ChildPath "Tree.md"
$mermaidText = ($mermaid -join "`n")
Set-Content -Path $treePath -Value $mermaidText -Encoding utf8
Write-Host ("Generated Mermaid graph at {0}" -f $treePath)

# Also write a zoomable HTML export for browser viewing
# Strip the mermaid fences to get the inner graph code
$inner = $mermaidText -replace '(?s)^```mermaid\s*','' -replace '\s*```$',''

# Build a mapping of node id -> Summary for tooltips

# Build a mapping of node id -> full lore card content for tooltips
$cardMap = @{}
${labelCardMap} = @{}
foreach ($node in $graphNodes.Values) {
    try {
        $card = Get-CardContent -Path $node.path
        if ($card -and $card -ne '') {
            $sid = ConvertTo-IdSafe $node.id
            $cardMap[$sid] = $card
            try {
                $label = $(
                    $labelTypeMap = @{
                        'world'='World'; 'realm'='Realm'; 'region'='Region'; 'biome'='Biome';
                        'location'='Location'; 'point'='Point'; 'faction'='Faction'; 'character'='Character'; 'creature'='Creature';
                        'concept'='Concept'; 'place-concept'='Place Feature'; 'place-feature'='Place Feature'; 'history'='History'; 'object'='Object';
                        'class'='Role'; 'race'='Race'
                    }
                    $typeLabel = $labelTypeMap[$node.type]
                    if (-not $typeLabel) {
                        $typeLabel = ($node.type -replace '-', ' ')
                        $ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
                        $typeLabel = $ti.ToTitleCase($typeLabel.ToLowerInvariant())
                    }
                    $displayName = $node.name
                    if (-not $displayName -or $displayName -eq '') {
                        $displayName = [IO.Path]::GetFileNameWithoutExtension($node.path)
                        $displayName = ($displayName -replace '[_-]', ' ').Trim()
                        $displayName = ($displayName -replace '\\s{2,}', ' ')
                        $ti2 = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
                        $displayName = $ti2.ToTitleCase($displayName.ToLowerInvariant())
                    }
                    "{0}: {1}" -f $typeLabel, $displayName
                )
                if ($label -and $label -ne '') { ${labelCardMap}[$label] = $card }
            } catch {}
        }
    } catch { }
}
$cardJson = ($cardMap | ConvertTo-Json -Depth 5)
${labelCardJson} = (${labelCardMap} | ConvertTo-Json -Depth 5)

 $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Lore Tree</title>
<style>
    html, body { height: 100%; margin: 0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; background: #181a20; color: #e2e8f0; }
    .container { padding: 12px; height: 100vh; box-sizing: border-box; }
    .mermaid { position: relative; width: 100%; height: calc(100vh - 40px); overflow: visible; background: #181a20; }
    .mermaid svg { height: 100% !important; background: #181a20 !important; }
    /* Compact toolbar top-right */
    #toolbar { position: fixed; top: 8px; right: 8px; z-index: 10000; background: rgba(32,32,40,0.92); border: 1px solid #23272f; border-radius: 4px; padding: 4px 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.15); font-size: 12px; color: #e2e8f0; }
    #toolbar button { font-size: 12px; padding: 2px 6px; line-height: 1.1; cursor: pointer; background: #23272f; color: #e2e8f0; border: 1px solid #374151; }
    #toolbar label { font-size: 12px; margin-left: 6px; cursor: pointer; color: #e2e8f0; }
    #legend { position: fixed; bottom: 8px; left: 8px; z-index: 10000; background: rgba(32,32,40,0.92); border: 1px solid #23272f; border-radius: 4px; padding: 6px 8px; box-shadow: 0 2px 6px rgba(0,0,0,0.15); font-size: 12px; color: #e2e8f0; max-width: 220px; }
    #legend h4 { margin: 0 0 4px 0; font-size: 12px; font-weight: 600; letter-spacing: .5px; color: #cbd5e0; }
    #legend ul { list-style: none; padding: 0; margin: 0; }
    #legend li { display: flex; align-items: center; gap: 6px; margin: 2px 0; }
    #legend svg { flex-shrink: 0; }
    .edgeIcon path { stroke: #e2e8f0; }
    .edgeIconParent path { stroke-width:2; stroke:#e2e8f0; }
    .edgeIconSeeAlso path { stroke-width:2; stroke:#e2e8f0; stroke-dasharray:4 4; }
    /* Hide built-in svg-pan-zoom control icons and variants */
    .svg-pan-zoom-control, .svg-pan-zoom-control-background, g.svg-pan-zoom-control, .svg-pan-zoom_buttons { display: none !important; }
    /* Make node label text ignore pointer events so tooltips show reliably */
    .mermaid svg .node text, .mermaid svg g.node text, .mermaid svg g.node tspan, .mermaid svg text, .mermaid svg tspan {
        pointer-events: none !important;
        cursor: inherit !important;
        fill: #e2e8f0 !important;
    }
    /* Tooltip styling */
    #tooltip { position: fixed; max-width: 380px; background: rgba(17,24,39,0.95); color: #fff; padding: 6px 8px; border-radius: 4px; font-size: 12px; line-height: 1.3; border: 1px solid #374151; box-shadow: 0 2px 8px rgba(0,0,0,0.25); pointer-events: none; display: none; z-index: 10001; }
</style>
<script>
    // Injected full lore card mapping for tooltips
    window.__cardMap = $cardJson;
    window.__labelCardMap = ${labelCardJson};
</script>
<!-- Load pan/zoom library first so setup can bind immediately -->
<script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
<script>
    // Define setupPanZoom and attachTitles before Mermaid runs
    window.setupPanZoom = function() {
        var svg = document.querySelector('.mermaid svg, svg.mermaid');
        if (!(svg && window.svgPanZoom)) return;
        var panZoom = window.svgPanZoom(svg, { controlIconsEnabled: false, fit: true, center: true, zoomScaleSensitivity: 0.3, contain: false });

        var invert = false;
        var zin = document.getElementById('zin');
        var zout = document.getElementById('zout');
        var fitBtn = document.getElementById('fit');
        var reset = document.getElementById('reset');
        var invertChk = document.getElementById('invert');

        if (zin) zin.addEventListener('click', function(){ panZoom.zoomBy(1.2); });
        if (zout) zout.addEventListener('click', function(){ panZoom.zoomBy(0.8333); });
        if (fitBtn) fitBtn.addEventListener('click', function(){ panZoom.fit(); panZoom.center(); });
        if (reset) reset.addEventListener('click', function(){ panZoom.reset(); panZoom.fit(); panZoom.center(); });
        window.addEventListener('resize', function(){ panZoom.resize(); panZoom.fit(); panZoom.center(); });
        if (invertChk) invertChk.addEventListener('change', function(){ invert = invertChk.checked; });

        var container = document.querySelector('.mermaid');
        if (container) {
            container.addEventListener('wheel', function(e){
                if (e.ctrlKey) return;
                e.preventDefault();
                var delta = e.deltaY || e.wheelDelta || 0;
                var factor = (delta > 0 ? 0.9 : 1.1);
                if (invert) factor = (delta > 0 ? 1.1 : 0.9);
                var pt = { x: e.clientX, y: e.clientY };
                panZoom.zoomAtPointBy(factor, pt);
            }, { passive: false });
        }

        window.addEventListener('keydown', function(e){
            if (e.key === '+' || e.key === '=') { panZoom.zoomBy(1.2); }
            if (e.key === '-' || e.key === '_') { panZoom.zoomBy(0.8333); }
            if (e.key === '0') { panZoom.fit(); panZoom.center(); }
        });
    };

    window.attachTitles = function() {
        var svg = document.querySelector('.mermaid svg, svg.mermaid');
        var map = (window.__cardMap || {});
        var labelMap = (window.__labelCardMap || {});
        if (!svg) return;

        function getCardForGroup(g){
            if (!g) return null;
            if (g.id && Object.prototype.hasOwnProperty.call(map, g.id)) return map[g.id];
            if (g.id) {
                var keys = Object.keys(map || {});
                var k = keys.find(function(x){ return (g.id || '').indexOf(x) !== -1; });
                if (k && map[k]) return map[k];
            }
            try {
                var parts = [];
                var tspans = g.querySelectorAll('text, tspan');
                if (tspans && tspans.length) {
                    for (var i=0; i<tspans.length; i++){ parts.push(tspans[i].textContent || ''); }
                } else {
                    parts.push(g.textContent || '');
                }
                var raw = parts.join('').replace(/\s+/g,' ').trim();
                if (raw && Object.prototype.hasOwnProperty.call(labelMap, raw)) return labelMap[raw];
            } catch(e){}
            return null;
        }

        var groups = svg.querySelectorAll('g[class*="node"], g.node');
        for (var i=0; i<groups.length; i++) {
            var g = groups[i];
            var card = getCardForGroup(g);
            if (!card) continue;
            try {
                var existing = g.querySelector('title');
                if (!existing) {
                    var t = document.createElementNS('http://www.w3.org/2000/svg', 'title');
                    t.textContent = card;
                    g.insertBefore(t, g.firstChild);
                }
            } catch(e){}
        }
    };
</script>
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: false, theme: 'base', flowchart: { curve: 'basis', nodeSpacing: 80, rankSpacing: 150 } });
  await mermaid.run({ querySelector: '.mermaid' });
    if (window.setupPanZoom) window.setupPanZoom();
    if (window.attachTitles) window.attachTitles();
    // Force pointer-events: none on all text/tspan inside g.node so tooltips show everywhere
    const svgEl = document.querySelector('.mermaid svg');
    if (svgEl) {
        const nodes = svgEl.querySelectorAll('g.node');
        nodes.forEach(g => {
            g.querySelectorAll('text, tspan').forEach(t => {
                t.style.cursor = 'inherit';
                t.style.pointerEvents = 'none';
            });
        });
        // Preserve original viewBox to keep edge labels centered.
    }
</script>
</head>
<body>
  <div class="container">
        <div id="toolbar" role="toolbar" aria-label="Diagram controls">
            <button id="zin" title="Zoom In" aria-label="Zoom In">+</button>
            <button id="zout" title="Zoom Out" aria-label="Zoom Out">−</button>
            <button id="fit" title="Fit to Screen" aria-label="Fit">Fit</button>
            <button id="reset" title="Reset View" aria-label="Reset">Reset</button>
            <label title="Invert Scroll Zoom" aria-label="Invert Scroll Zoom"><input type="checkbox" id="invert" /> Invert Scroll Zoom</label>
        </div>
        <div id="legend" aria-label="Legend">
            <h4>Legend</h4>
            <ul>
                <li>
                    <svg class="edgeIcon edgeIconParent" width="38" height="10" viewBox="0 0 38 10" aria-hidden="true"><path d="M2 5 L32 5" fill="none"/><path d="M32 5 L26 2 L26 8 Z" fill="#e2e8f0"/></svg>
                    <span>Parent relationship (solid)</span>
                </li>
                <li>
                    <svg class="edgeIcon edgeIconSeeAlso" width="38" height="10" viewBox="0 0 38 10" aria-hidden="true"><path d="M2 5 L32 5" fill="none"/><path d="M32 5 L26 2 L26 8 Z" fill="#e2e8f0"/></svg>
                    <span>See Also (cross-reference)</span>
                </li>
            </ul>
        </div>
    <div class="mermaid">
$inner
    </div>
  </div>
</body>
</html>
"@

$treeHtmlPath = Join-Path -Path "Lore" -ChildPath "Tree.html"
Set-Content -Path $treeHtmlPath -Value $html -Encoding utf8
Write-Host ("Generated Mermaid HTML at {0}" -f $treeHtmlPath)

Write-Host "`nLore index update complete!"

# ============================================================
# USAGE GUIDE
# ============================================================
# To run the script from PowerShell:
# 1. Open PowerShell in the repository root directory.
# 2. Execute the following command:
#      .\tools\update_lore_indexes.ps1
#
# The script will:
#  - Scan all subfolders within Lore/Lorebook.
#  - Identify every .md file except the folder’s own index file.
#  - Overwrite or generate the index file (e.g., Factions.md, Races.md).
#  - Validate [ENTRY: Name] and [END: Name] wrappers match the Name field.
#  - Warn on missing or unknown names referenced in Locations of Note or Aligned Characters.
#
# Notes:
#  - Special characters and spaces in file names are automatically URL encoded.
#  - Run this whenever new lore entries are added, renamed, or removed.
#  - No existing entries are modified—only the *_index.md* files are updated.
# ============================================================
