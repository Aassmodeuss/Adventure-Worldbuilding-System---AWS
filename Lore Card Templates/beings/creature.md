# Template - Being: Creature

Purpose
- Use for non-sapient or semi-sapient fauna and flora threats (e.g., Shadow Panther, Leechvines).  
- Describe adaptation, behavior, sensory cues, risks, and practical countermeasures.

Frontmatter (optional parent)
```yaml
---
id: creature:shadow-panther
type: creature
name: Shadow Panther
parent: biome:shadowlands      # optional: primary habitat for breadcrumbing
see_also: [concept:forsaken-lands]   # optional
---
```

Card template
```markdown
[ENTRY: {Name}]

#### [Creature]
**Name:**  
**Aliases:**  
**Summary:** 1-2 sentences on identity, habitat tier, and why it matters. Write this as a standalone section; do not rely on Full Description. Include the card's title name at least once.  
**Full Description:** 4-10 sentences on sensory cues, behavior patterns, movement and hunting/defense, diet, adaptations, and limits. Note any Blight influence when relevant. Write this as a standalone section; do not rely on Summary. Include the card's title name at least twice (natural usage; avoid repetition).  
**Tone Keywords:** 3-5 anchors.  
**Habitats:** comma-separated biome/location card names where it is a recurring resident hazard  
**Risk and Countermeasures:** 1-3 concise lines naming practical signs to watch for and effective responses  
**Potential Gameplay Hooks:** 1-3 concise bullets, potential quests, events, or interactions involving this creature.  


[END: {Name}]
```


Pre-save checklist
- Parent set only if a single primary habitat is clear; otherwise omit and rely on Habitats.  
- Habitats list uses exact card names and aligns with local-inhabitant rules for those places.  
- Summary and Full Description avoid lore repeated at higher tiers.  
- Wrappers and Name field match exactly.

