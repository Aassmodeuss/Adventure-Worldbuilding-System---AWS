# Template - Role: Class Progression

Purpose
- Use for progression frameworks for a specific role/class (tiers, abilities, and traits over time).
- Specify abilities and traits with their effects, costs, and how they advance, are learned, or mitigated.

Frontmatter
```yaml
---
# Suggested id format: class:<base-class>-progression (e.g., class:purger-progression)
id: class:example-progression
type: class
name: Example Class - Progression
see_also: [class:example]   # link the base class id if available
---
```

Card template
```markdown
[ENTRY: {Name}]

#### [Class Progression]
**Name:**  
**Summary:** 1-2 sentences defining the progression for the class and how members advance. Write this as a standalone section; do not rely on Full Description.  
**Progression Overview:** 3-6 sentences on tiers/milestones, training cadence, assessment gates, and typical time/risks between ranks.  
**Tone Keywords:** 3-5 anchors.  
**Associated Class:** exact role/class card title  
**Training Pathways:** brief list of schools/masters/ordeals (if any)  

Abilities
- For each ability, include a brief paragraph and three sub-sections.

Ability - {Ability Name}
Description: One short paragraph describing the capability and its context of use.  
Effects:
- Concrete outcomes the ability produces.  
- Quantify ranges, durations, or thresholds when known.  
Costs:
- Physical, mental, reagent, rite, sacrifice, or cooldown demands.  
- Include recovery windows if applicable.  
Progression and Learning:
- How the practitioner acquires, refines, or extends the ability.  
- Training gates, rare instruction, field tests.  

Positive Traits
- For each trait, include a brief paragraph and three sub-sections.

Positive Trait - {Trait Name}
Description: One short paragraph describing the beneficial tendency or adaptation.  
Effects:
- Practical advantages conferred.  
Costs:
- Tradeoffs or obligations that accompany the trait.  
Progression and Earning:
- How the trait is cultivated or recognized.  
- Milestones that strengthen the trait.  

Negative Traits
- For each trait, include a brief paragraph and three sub-sections.

Negative Trait - {Trait Name}
Description: One short paragraph describing the liability or risk pattern.  
Effects:
- Practical harms or constraints.  
Costs:
- Ongoing burdens or exacerbating conditions.  
Mitigation and Recovery:
- How members reduce, redirect, or recover from the trait.  
- Training, aids, rituals, or boundaries that help.  

**Potential Gameplay Hooks:** 1-3 concise bullets connecting progression tests, instruction debts, or trait management to present stakes.  


[END: {Name}]
```

Pre-save checklist
- Associated Class linked and Progression Overview present.  
- Each Ability/Positive/Negative entry includes Description, Effects, Costs, and Progression/Earning/Mitigation.  
- Hooks tie progression to actionable stakes.  
- Wrappers and Name field match exactly.

