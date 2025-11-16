# Heart of the Forest Voyage — Lore Authoring & Tooling Guide

## 1. Overview
Heart of the Forest Voyage is a codex-style lore workspace. Content lives in Markdown "cards" with standardized frontmatter, wrappers, and typed templates. Tooling automates: card scaffolding, rewriting, index generation, Mermaid graph visualization, and text hygiene.

## Repo Sharing (Tooling‑Only)
- Purpose: this repository is configured to share tooling only. All lore content under `Lore/**` and outlines are ignored from version control; directory structure is preserved via `.gitkeep` files.
- Graph outputs (`Lore/Tree.md`, `Lore/Tree.html`) and the unknown‑reference log are also ignored; the indexer regenerates them as needed. No placeholders required.
- To publish this repo:
	1) Create a new empty remote (e.g., GitHub).
	2) Add and push:
		 ```powershell
		 git remote add origin <YOUR_EMPTY_REPO_URL>
		 git branch -M main
		 git push -u origin main
		 ```
	3) Consumers can clone and immediately run the tasks/utilities; they will generate local lore and graph artifacts that remain untracked.

## 2. Core Concepts
- **Card Gen Pack:** Per‑type template + matching "Writing Style" prompt under `.continue/`.
- **Frontmatter Keys:** `id`, `type`, `name`, optional `parent`, optional `see_also` (array or list). `id = type:slug` (slug is kebab-case of Name).
- **Wrappers:** Body must start with `[ENTRY: Name]` and end with `[END: Name]` exactly matching `name`.
- **Core Sections:** Each card includes `**Summary:**` (1–2 sentences) and `**Full Description:**` (3–8 sentences). Both sections must stand alone and be independently understandable (avoid references like “as above/below”).
- **Lore Tree:** Auto-generated graph (`Lore/Tree.md`, `Lore/Tree.html`) showing hierarchy (parent → child) and `see_also` dotted links.

## 3. Supported Card Types
Beings: `character`, `creature`, `faction`, `race`
Places: `world`, `realm`, `region`, `biome`, `location`, `point`, `place-concept`
Conceptual: `concept`, `history` (with era buckets)
Objects & Roles: `object`, `weapon`, `armor`, `story-object`, `role`, `class-progression`

## 4. Folder Structure (Essentials)
- `Lore/Lorebook/` — canonical cards by category (subfolders per type). History & Concept may have bucket subfolders.
- `.continue/Lore Card Templates/` — per-type templates.
- `.continue/prompts/` — "Writing Style for <Type> Cards" guides (model shaping prompts; fill all template fields).
- `.continue/rules/Heart of the Forest Instructions.instructions.md` — unified lore guidance.
- `tools/` — PowerShell utilities (`cardgen.ps1`, `cardgen_interactive.ps1`, `cardgen_rewrite_current.ps1`, `update_lore_indexes.ps1`, `watch_lore.ps1`, `fix_mojibake.ps1`).
- `.vscode/tasks.json` — tasks for card generation and index maintenance.

## 5. Environment Setup
Set your API credentials (example OpenAI):
```powershell
$env:OPENAI_API_KEY = "<key>"
$env:OPENAI_MODEL   = "gpt-4o-mini"
```
Models matching `gpt-4.1` or `gpt-4o*` use the Responses API automatically; others default to Chat.

## 6. Card Generation Methods
### A. Interactive Task (Recommended)
Run VS Code Task: `CardGen: New or Rewrite (interactive)` → answer prompts → preview → apply.

### B. Rewrite Existing Card
Open the target card; run task `CardGen: Rewrite Current Card` ⇒ choose lore policy:
- `preserve-only` (default): only refine wording, keep facts.
- `augment`: may extend details within tone and constraints.
- `create`: broader expansion (use sparingly).
Optional `New Facts Authorized` supplies specific new canonical points.

### C. Direct CLI Usage
Example new character:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cardgen.ps1 -JobType new -CardType character -Name "Elder Rowan" -Parent realm:greenwood -ToneKeywords calm,ancient -Model $env:OPENAI_MODEL -ApiKey $env:OPENAI_API_KEY -AutoApply -AutoIndex
```
Key parameters (from `cardgen.ps1`):
- `JobType`: `new|rewrite`
- `CardType`: one of supported types
- `Name`: display title (used for filename & wrappers)
- `Parent`: parent id (`type:slug`)
- `SeeAlso`: array of ids
- `ToneKeywords`: style guidance tokens
- `LocationsOfNote`, `KnownLinks`: pre-fill list/title fields
- `EraOrTopicBucket`: for `history` or `concept` folder routing
- `LorePolicy`: rewrite mode (`preserve-only|augment|create`)
- `NewFacts`: explicit new canonical facts when rewriting
- `AutoApply`: skip manual confirmation
- `AutoIndex`: run indexer after save

### D. Interactive Script (Direct)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cardgen_interactive.ps1
```

## 7. Authoring Workflow (Manual Path)
1. Pick correct template from `.continue/Lore Card Templates/<domain>/<type>.md`.
2. Paste frontmatter + template into new file in the correct folder.
3. Add wrappers `[ENTRY: Name]` / `[END: Name]`.
4. Run matching "Writing Style" prompt to fill all fields (Summary, Full Description, hooks, etc.).
5. Add `parent` and `see_also` ids as needed.
6. Save; run indexer task (or rely on watcher).

## 8. Indexing & Graph
Run once:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update_lore_indexes.ps1
```
Or start watcher (background auto updates):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\watch_lore.ps1
```
Indexer actions:
- Rebuilds per-folder index files.
- Validates wrappers vs `**Name:**`.
- Warns on unknown titles in special fields (e.g., Locations of Note, Aligned Characters).
- Regenerates graph + HTML with tooltips containing card content.
 - Graph styling: solid lines = parent/child; dotted lines = `see_also` links (no labels). A legend is embedded in `Lore/Tree.html`.
 - Node colors: `race` nodes are red, `realm` nodes are yellow, and `point` nodes are purple for quick visual scanning.

## 9. Validation & Quality
- Ensure `id` slug matches canonical Name (kebab-case, no spaces, punctuation stripped).
- Keep deltas: child cards should not duplicate parent descriptive blocks.
- `see_also` uses ids (`type:slug`); field lists (e.g., Locations of Note) use titles matching filenames.
- On rewrite, only introduce new lore when `LorePolicy` permits or via `NewFacts` list.
- Use tone keywords sparingly (2–5 meaningful tokens).

## 10. Tasks Reference
| Task | Purpose |
|------|---------|
| Update Lore Indexes | Manual one-off run of indexer & graph rebuild |
| Watch Lore and Auto-Update Indexes | Background watcher (debounced) |
| CardGen: New or Rewrite (interactive) | Guided creation / rewrite, multi-field input |
| CardGen: Rewrite Current Card | Rewrite open file using its frontmatter |

## 11. Utilities (tools/)
- `cardgen.ps1` — core generator / rewriter (params & automation).
- `cardgen_interactive.ps1` — prompt-driven new/rewrite front-end.
- `cardgen_rewrite_current.ps1` — rewrite currently open file.
- `update_lore_indexes.ps1` — index + Mermaid graph builder.
- `watch_lore.ps1` — file watcher triggering indexer (debounced).
- `fix_mojibake.ps1` — sanitation / encoding diagnostics & repair (run with `-ReportOnly` first).
 - `normalize_punctuation.ps1` — normalizes smart quotes, dashes, and non-breaking spaces. Run with `-DryRun` to preview.

## 12. Troubleshooting
- Wrappers missing: Add `[ENTRY: Name]` / `[END: Name]` exactly matching `**Name:**`.
- Unknown reference warnings: Ensure titles match existing filenames (without extension) or convert legacy cards to template format.
- Graph stale: Run the indexer or start the watcher.
- Execution policy errors: Always include `-ExecutionPolicy Bypass` or use VS Code tasks.
- Unicode / mojibake: Run `powershell -File .\tools\fix_mojibake.ps1 -ReportOnly` then apply fixes if needed.
 - "Frontmatter not found in current file": Ensure YAML frontmatter is the first block in the file, delimited by `---` … `---`, and includes `id`, `type`, and `name`. Save the file, then rerun `CardGen: Rewrite Current Card`.
 - Template path not found (interactive): Confirm the per-type template exists under `.continue/Lore Card Templates/<domain>/<type>.md` and the style prompt under `.continue/prompts/`. Then rerun the interactive task.

## 13. Style & Prompts
All narrative style, voice, and field coverage is defined in per-type templates and their "Writing Style" prompts. Do not duplicate style rules here—update the template or prompt instead.

## 14. Maintenance Checklist
When adding a new card type or field:
1. Create template under `.continue/Lore Card Templates/<domain>/<type>.md`.
2. Add matching style prompt under `.continue/prompts/`.
3. Extend type mappings in `cardgen.ps1` (`ValidateSet`, template/prompt map, output directory switch).
4. Update this README and unified rules file.
5. Test: interactive generation + index rebuild.

## 15. Quick Start Summary
```powershell
# 1. Set environment
$env:OPENAI_API_KEY = "<key>"; $env:OPENAI_MODEL = "gpt-4o-mini"

# 2. Generate a card interactively
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cardgen_interactive.ps1

# 3. Or CLI new card
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cardgen.ps1 -JobType new -CardType location -Name "Ash Hollow" -Parent biome:emberwild -ToneKeywords haunted,whispering -AutoApply -AutoIndex -Model $env:OPENAI_MODEL -ApiKey $env:OPENAI_API_KEY

# 4. Start watcher (optional)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\watch_lore.ps1
```

Internal use only.

## 16. Advanced Features
- **Unknown Reference Logger:** When saving a generated/rewritten card, cross-reference fields (e.g., Primary Regions, Aligned Factions, Notable Characters, Locations of Note) are scanned. Any entries that do not match existing card titles are logged to `Lore/PotentialCards.jsonl` as JSON Lines with the source card and field.

	Example line:
	```json
	{"timestamp":"2025-11-16T06:01:23.456Z","source":{"name":"Goblin","type":"race","path":"Lore/Lorebook/Beings/Races/Goblin.md"},"unknown":[{"field":"Primary Regions","title":"Central Plains"},{"field":"Notable Characters","title":"Elder Marik"}]}
	```
	Tips: Grep or filter this file to create stubs or plan future cards.

- **Auto-Linking + see_also Mirroring:** The generator scans the card body for mentions of existing card titles and adds them under a `Links:` block as `- [[Title]]`. Known links are resolved to card IDs and merged into frontmatter `see_also: [type:slug, …]` to feed the graph. Keep field lists (like Primary Regions) using display titles; keep `see_also` using IDs.

- **Graph Legend & Colors:** `Lore/Tree.html` includes a legend. Parent/child edges are solid; `see_also` edges are dotted (no labels for layout stability). Node colors: `race`=red, `realm`=yellow, `point`=purple.

- **Strict JSON + Two-Pass Generation:** For modern models, the generator uses the Responses API with strict JSON parsing. On certain errors, it falls back to a two-pass flow (Summary/Full first; then fields-only) to stabilize rewrites while keeping Summary/Full independently understandable.
