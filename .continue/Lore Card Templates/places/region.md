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
**Summary:** Region identity and role within the realm. Write this as a standalone section; do not rely on Full Description.  
**Full Description:** 3-8 sentences on terrain, dominant biomes, key routes, and broad hazards. Avoid naming specific settlements unless essential. Write this as a standalone section; do not rely on Summary.  
**local inhabitants:** None  
**Tone Keywords:** 3-5 anchors.  
**Locations of Note:** biomes and major locations within this region  
**Potential Gameplay Hooks:** 1-3 concise bullets, region-scale tasks.  


[END: {Name}]
```

Pre-save checklist
- Parent points to its realm.  
- Locations of Note list biomes and major locations only.  
- No local inhabitants here unless a region-wide, recurring hazard is truly specific.

