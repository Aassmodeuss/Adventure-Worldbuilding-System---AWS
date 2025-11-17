# Copilot Instructions — Heart of the Forest Voyage

Purpose
- Get AI coding agents productive immediately here: where lore “cards” live, how to generate/validate them, how indexes/graphs are built, and project‑specific conventions that tools expect.

Big Picture
- Codex-style lore workspace. Canonical cards live under `Lore/Lorebook/**` and are visualized via an auto-generated Mermaid graph (`Lore/Tree.md` + `Lore/Tree.html`).
- Authoring is standardized by per‑type templates and “Writing Style” prompts in `.continue/`, with PowerShell utilities in `tools/` orchestrating generation, rewrites, indexing, and hygiene.

Day‑1 Workflows
- Update indexes/graph once:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update_lore_indexes.ps1
  ```
- Watcher (auto updates): VS Code Task “Watch Lore and Auto-Update Indexes”. One‑off: “Update Lore Indexes”.
- Generate/Rewrite (interactive): Task “CardGen: New or Rewrite (interactive)”.
- Rewrite current file: Task “CardGen: Rewrite Current Card” (reads YAML frontmatter).

Authoring Rules
- Frontmatter: `id`, `type`, `name`, optional `parent`, optional `see_also`. `id = type:slug` with slug = kebab‑case of `name`.
- Wrappers: Body must include `[ENTRY: Name]` … `[END: Name]` exactly matching `name`.
- Core sections: `**Summary:**` (1–2 sentences) and `**Full Description:**` (3–8 sentences) — both must be independently understandable.
- Packs: Templates at `.continue/Lore Card Templates/<domain>/<type>.md`; style prompts at `.continue/prompts/Writing Style for <Type> Cards.md`. Unified rules: `.continue/rules/Heart of the Forest Instructions.instructions.md`.

Structure & Routing (cardgen.ps1)
- Places: `world→Places/Worlds`, `realm→Places/Realm`, `region→Places/Regions`, `biome→Places/Biomes`, `location→Places/Locations`, `point→Places/Point`, `place-feature|place-concept→Places/Place Features` (legacy alias supported).
- Beings: `character→Beings/Characters`, `creature→Beings/Creatures`, `faction→Beings/Factions`, `race→Beings/Races`.
- Concepts/History: `concept→Concepts[/<topic>]`, `history→History[/<era>]`.
- Objects/Roles: `object|weapon|armor|story-object→Objects`, `role|class-progression→Roles and Classes`.
- Filenames are display titles (`Name.md`), not slugs.

CardGen Utilities (PowerShell)
- Env:
  ```powershell
  $env:OPENAI_API_KEY = "<key>"
  $env:OPENAI_MODEL   = "gpt-4o-mini"  # Uses Responses API for 4.1/4o; Chat for others
  ```
- New card (CLI):
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cardgen.ps1 -JobType new -CardType character -Name "Elder Rowan" -Parent realm:greenwood -Model $env:OPENAI_MODEL -ApiKey $env:OPENAI_API_KEY -AutoApply -AutoIndex
  ```
- Rewrite current (interactive): Task “CardGen: Rewrite Current Card”. Canon adherence: `strict|flexible|creative` maps to `preserve-only|augment|create`. Optionally pass `-NewFacts`.

Indexer & Graph (update_lore_indexes.ps1)
- Scans `Lore/Lorebook/**`, rebuilds per‑folder indexes, validates wrappers vs `**Name:**`, warns on unknown titles in `Locations of Note`/`Aligned Characters`, and regenerates `Lore/Tree.md` + `Lore/Tree.html` with tooltips from card bodies.
- Graph edges: solid = parent/child; dotted = `see_also`. Node colors/types are pre-styled for quick scanning.

Conventions & Gotchas
- Keep `name` canonical; wrappers, filenames, and graph validation depend on exact matches.
- Use `see_also` for ID‑level links (e.g., `faction:wardens`); use field lists for title‑level references (must match filenames).
- Unknown references are logged to `Lore/PotentialCards.jsonl` (source card + field) for future card planning.
- If execution policy blocks scripts, prefer VS Code Tasks or include `-ExecutionPolicy Bypass` as shown above.

Notes for Agents
- Primary templates/prompts are under `.continue/`. Mirrored browsing copies also exist at `Lore Card Templates/` and `prompts/`, but CardGen reads from `.continue/`.
- Legacy `place-concept` routes to `Places/Place Features`. Existing content may also appear under `Places/Place Concepts`; the generator will create the mapped folder if missing.

Key References
- `README.md` — complete authoring and tooling guide, examples, and troubleshooting.
- `tools/` — `cardgen*.ps1`, `update_lore_indexes.ps1`, `watch_lore.ps1`, `fix_mojibake.ps1`, `normalize_punctuation.ps1`.
- Graph outputs: `Lore/Tree.md`, `Lore/Tree.html`.
