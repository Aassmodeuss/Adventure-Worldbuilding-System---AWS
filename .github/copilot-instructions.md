# Copilot Instructions — Heart of the Forest Voyage

Purpose
- Make AI coding agents productive immediately in this repo: how content is authored, indexed, and visualized; how to run utilities; and what conventions to follow.

Big Picture
- This is a codex-style lore workspace. Markdown “cards” live under `Lore/Lorebook/**`. An indexer script validates cards and rebuilds indexes plus a clickable Mermaid graph (`Lore/Tree.md` + `Lore/Tree.html`).
- Card generation is assisted by per-type templates and writing-style prompts in `.continue/`, and PowerShell utilities under `tools/`.

Day-1 Workflows
- Update indexes once:
  ```powershell
  .\tools\update_lore_indexes.ps1
  ```
- Watch for changes (background task): use VS Code Tasks → "Watch Lore and Auto-Update Indexes". One-off: "Update Lore Indexes".
- Generate/Rewrite a card (interactive): Tasks → "CardGen: New or Rewrite (interactive)".
- Rewrite the open card: Tasks → "CardGen: Rewrite Current Card" (reads frontmatter of current file).

Authoring Rules (cards)
- Every card uses YAML frontmatter with: `id`, `type`, `name`, optional `parent`, optional `see_also` (array or list). IDs follow `type:slug` where slug is kebab-case of Name.
- Body must include exact wrapper tags: `[ENTRY: Name]` … `[END: Name]`, where `Name` matches frontmatter `name`.
- Required core fields inside the body include `**Name:**`, `**Summary:**` (1–2 sentences), and `**Full Description:**` (3–8 sentences). Many templates include `Tone Keywords` and `Potential Gameplay Hooks`.
 - Required core fields inside the body include `**Name:**`, `**Summary:**` (1–2 sentences), and `**Full Description:**` (3–8 sentences). Both Summary and Full Description must be standalone and independently understandable. Many templates include `Tone Keywords` and `Potential Gameplay Hooks`.
- Always start from the correct per-type template and style prompt:
  - Templates: `.continue/Lore Card Templates/<domain>/<type>.md`
  - Style prompts: `.continue/prompts/Writing Style for <Type> Cards.md`
  - Reference: `.continue/rules/Heart of the Forest Instructions.instructions.md`

Structure & Routing
- Output locations by `type` (from `tools/cardgen.ps1`):
  - `world→Places/Worlds`, `realm→Places/Realm`, `region→Places/Regions`, `biome→Places/Biomes`, `location→Places/Locations`, `point→Places/Point`, `place-concept→Places/Place Features`
  - `character→Beings/Characters`, `creature→Beings/Creatures`, `faction→Beings/Factions`, `race→Beings/Races`
  - `concept→Concepts[/<topic>]`, `history→History[/<era>]`, `role|class-progression→Roles and Classes`, `object|weapon|armor|story-object→Objects`
- Filenames match the display title (`Name.md`), not the slug.

Indexer & Graph
- Script: `tools/update_lore_indexes.ps1` scans `Lore/Lorebook/**` for `.md` and:
  - Rebuilds per-folder indexes (skips the category root containers).
  - Validates wrapper tags and warns if `[ENTRY: Name]` / `[END: Name]` don’t match `**Name:**`.
  - Warns on unknown cross-references in `**Locations of Note:**` and `**Aligned Characters:**` (compared to other base filenames).
  - Builds `Lore/Tree.md` Mermaid and `Lore/Tree.html` (zoomable, with tooltips from card bodies).

CardGen Utilities (PowerShell)
- Environment: set before running, or provide interactively.
  ```powershell
  $env:OPENAI_API_KEY = "<key>"
  $env:OPENAI_MODEL  = "gpt-4o-mini"  # Uses Responses API for 4.1/4o; Chat for others
  ```
- New card (non-interactive example):
  ```powershell
  .\tools\cardgen.ps1 -JobType new -CardType character -Name "Elder Rowan" -Parent realm:greenwood -Model $env:OPENAI_MODEL -ApiKey $env:OPENAI_API_KEY -AutoApply -AutoIndex
  ```
- Rewrite current open file (task): "CardGen: Rewrite Current Card". Default lore policy for rewrites is `preserve-only` unless `-NewFacts` is provided.

Conventions & Gotchas
- Keep `name` canonical; wrappers and validations depend on exact matching.
- Use `see_also` for ID-level cross-links (e.g., `faction:wardens`). Use field lists (e.g., `Locations of Note`) for title-level references (must match filenames).
- Some legacy files may lack frontmatter/wrappers; prefer converting them to the template format for proper indexing and graph inclusion.
- If execution policy errors occur, run via provided VS Code tasks (they set `-ExecutionPolicy Bypass`).

Key References
- README: project overview and authoring options — `README.md`
- Rules: `.continue/rules/Heart of the Forest Instructions.instructions.md`
- Watcher: `tools/watch_lore.ps1` (also exposed as a VS Code task)
- Graph outputs: `Lore/Tree.md`, `Lore/Tree.html`
