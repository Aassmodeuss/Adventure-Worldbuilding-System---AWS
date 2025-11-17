# Template - Place: World

Purpose
- Use for top-level worlds. Worlds have no parent. Other worlds may exist in parallel.
- Keep scope broad. Avoid local details that belong to realms, regions, or below.

Frontmatter (paste at top)
```yaml
---
id: world:elrune            # type:slug, kebab-case slug
type: world
name: Elrune
---
```

Card template (paste below frontmatter)
```markdown
[ENTRY: {Name}]

#### [World]
**Name:**  
**Summary:** 1-2 sentences on identity and significance. Note parallel worlds if relevant. Write this as a standalone section; do not rely on Full Description. Include the card's title name at least once.  
**Full Description:** 3-8 sentences on macro geography, movement between realms, and global forces. Do not list local peoples or settlements. Write this as a standalone section; do not rely on Summary. Include the card's title name at least twice (natural usage; avoid repetition).  
**local inhabitants:** None  
**Tone Keywords:** 3-5 anchors.  
**Locations of Note:** top-level realms only (exact card names)  
**Potential Gameplay Hooks:** 1-3 concise bullets, world-scale events, or interactions.  


[END: {Name}]
```

Pre-save checklist
- No parent in frontmatter.  
- Locations of Note only lists realms.  
- Keep Summary and Full Description high-level.  
- Validate wrappers and Names.  
- Add Links block with parallel worlds if needed.

