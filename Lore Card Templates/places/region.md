# Template - Place: Region

Purpose
- Use for sub-areas within a realm (e.g., Westwood).  
- Define key biomes and movement corridors.

Frontmatter
```yaml
---
id: region:westwood
type: region
name: Westwood
parent: realm:greenwood
see_also: []
---
```

Card template
```markdown
[ENTRY: {Name}]

#### [Region]
**Name:**  
**Summary:** Region identity and role within the realm. Write this as a standalone section; do not rely on Full Description. Include the card's title name at least once.  
**Full Description:** 3-8 sentences on terrain, dominant biomes, key routes, and broad hazards. Avoid naming specific settlements unless essential. Write this as a standalone section; do not rely on Summary. Include the card's title name at least twice (natural usage; avoid repetition).  
**local inhabitants:** None  
**Tone Keywords:** 3-5 anchors.  
**Locations of Note:** biomes and major locations within this region  
**Potential Gameplay Hooks:** 1-3 concise bullets describing potential interactions, quests, or story events within this region.  


[END: {Name}]
```

Pre-save checklist
- Parent points to its realm.  
- Locations of Note list biomes and major locations only.  
- No local inhabitants here unless a region-wide, recurring hazard is truly specific.

