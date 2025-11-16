# Heart of the Forest — Unified Lore Guide

Purpose
- Provide one clear, authoritative standard for creating and editing Heart of the Forest lore.
- Keep entries readable by humans and parsable by systems, with consistent structure and cross-links.

Authoring workflow (templates + prompts)
- Always use the per-type template from .continue/Lore Card Templates.
- Always run the matching “Writing Style for … Cards” prompt from .continue/prompts to guide Summary and Full Description.
- Do not copy style rules into this document. Treat templates and prompts as the single source of truth for tone, structure, and exemplars.

Card gen packs
- Definition: A card gen pack is the pair of files for a given lore type: its per‑type template and its matching “Writing Style for … Cards” prompt.
- Usage: Always work from the pack. Paste the template into your target lore file, then run the matching Writing Style prompt to guide Summary and Full Description.
- Example: History pack — .continue/Lore Card Templates/history.md + .continue/prompts/Writing Style for History Cards.md.

Where to find templates and prompts
- Beings
  - Character: template — .continue/Lore Card Templates/beings/character.md; prompt — .continue/prompts/Writing Style for Character Cards.md
  - Creature: template — .continue/Lore Card Templates/beings/creature.md; prompt — .continue/prompts/Writing Style for Creature Cards.md
  - Faction: template — .continue/Lore Card Templates/beings/faction.md; prompt — .continue/prompts/Writing Style for Faction Cards.md
  - Race: template — .continue/Lore Card Templates/beings/race.md; prompt — .continue/prompts/Writing Style for Race Cards.md
- Places
  - World: template — .continue/Lore Card Templates/places/world.md; prompt — .continue/prompts/Writing Style for World Cards.md
  - Realm: template — .continue/Lore Card Templates/places/realm.md; prompt — .continue/prompts/Writing Style for Realm Cards.md
  - Region: template — .continue/Lore Card Templates/places/region.md; prompt — .continue/prompts/Writing Style for Region Cards.md
  - Biome: template — .continue/Lore Card Templates/places/biome.md; prompt — .continue/prompts/Writing Style for Biome Cards.md
  - Location: template — .continue/Lore Card Templates/places/location.md; prompt — .continue/prompts/Writing Style for Location Cards.md
  - Point: template — .continue/Lore Card Templates/places/point.md; prompt — .continue/prompts/Writing Style for Point Cards.md
  - Place Concept: template — .continue/Lore Card Templates/places/place_concept.md; prompt — .continue/prompts/Writing Style for Place Concept Cards.md
- History
  - Template — .continue/Lore Card Templates/history.md; prompt — .continue/prompts/Writing Style for History Cards.md
- Concepts
  - Template — .continue/Lore Card Templates/concept.md; prompt — .continue/prompts/Writing Style for Concept Cards.md
- Objects, Roles
  - Object: Armor — template — .continue/Lore Card Templates/objects/armor.md; prompt — .continue/prompts/Writing Style for Armor Cards.md
  - Object: General — template — .continue/Lore Card Templates/objects/object.md; prompt — .continue/prompts/Writing Style for Object Cards.md
  - Object: Weapon — template — .continue/Lore Card Templates/objects/weapon.md; prompt — .continue/prompts/Writing Style for Weapon Cards.md
  - Object: Story — template — .continue/Lore Card Templates/objects/story_object.md; prompt — .continue/prompts/Writing Style for Story Object Cards.md
  - Role: template — .continue/Lore Card Templates/roles/class.md; prompt — .continue/prompts/Writing Style for Role Cards.md
  - Role: Class Progression — template — .continue/Lore Card Templates/roles/class_progression.md; prompt — .continue/prompts/Writing Style for Class Progression Cards.md
  - Other Objects/Roles: use the corresponding template under .continue/Lore Card Templates/<type>/; use the matching “Writing Style” prompt if available. If absent, follow the guidance embedded in the template.






Prompt chain — how we build entries
0) Select template: choose the correct per‑type template and paste frontmatter + template into the target file. Or use the VS Code task "CardGen: New or Rewrite (interactive)" to scaffold a new file from a card gen pack.
1) Initialize: gather type, connections (standalone or linked), tone keywords, and gameplay hooks/goals.
2) Confirm context: restate the plan (e.g., “We’re making a [Type] with tone X; links to Y and Z”).
3) Generate: draft the entry using the template fields. For style and exemplars, reference the template’s “Style exemplars” section and run the matching Writing Style prompt.
4) Refine: offer changes (darker/lighter tone, expanded ties, mechanics hooks) while staying within template guidance.
5) Validate and save: run link checks and append to completed log if applicable.

Canon terms and capitalization
- Old Ones, the Spirit of the Green, the Green, Great Wolf Fenril, Raven King Corvath, Kinsoul, shifter(s), Greenwood, the Wardens, corruption (lowercase unless part of a title), Blight.

Validation tools and workflow
1) Draft to template with wrappers and matching Name.
2) Style pass: follow the per-type template and the matching Writing Style prompt.
3) Canon and link pass.
4) Run: ./tools/update_lore_indexes.ps1 — checks wrappers and warns on unknown references.
5) If breaking guidance in a template, note why and keep it consistent.

After generating or editing cards — run the indexer
- Option A: Run once from PowerShell in the repository root:
  
  powershell
  .\tools\update_lore_indexes.ps1
  
- Option B: Use VS Codium tasks (recommended)
  - Start auto-updates: Tasks > Run Task > Watch Lore and Auto-Update Indexes (runs in background)
  - Stop auto-updates: Tasks > Terminate Task > Watch Lore and Auto-Update Indexes
  - Run one-off: Tasks > Run Task > Update Lore Indexes

Quick access and files
- Task definitions: .vscode/tasks.json (edit task names or settings here)
- Watch script: tools/watch_lore.ps1 (called by the background task)
- Command Palette: “Tasks: Run Task” to start; “Tasks: Terminate Task” to stop

- What it does:
  - Scans Lore/Lorebook for .md files and updates each category index.
  - Validates [ENTRY: Name] and [END: Name] wrappers against the Name field.
  - Warns on unknown references in Locations of Note and Aligned Characters.
  - Regenerates Lore/Tree.md and Lore/Tree.html with a clickable Mermaid graph and tooltips.


Note
- This document intentionally omits detailed style rules and examples. All style, structure, and exemplar passages live in the per-type templates and the Writing Style prompts.
- If unsure which card gen pack applies, pause and ask the user which pack to use (e.g., Character, Creature, Faction, Race, World, Realm, Region, Biome, Location, Point, History, Concept, Object, Role).
- Keep the project README.md updated whenever we add or change features (new templates, prompts, tasks, or scripts).

