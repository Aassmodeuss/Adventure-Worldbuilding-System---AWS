# Lore Index

This directory contains categorized lore compiled from scenario story cards. Each Markdown file group resides within its own subfolder for clarity.

## Categories
- [Characters](./Characters/)
- [Creatures](./Creatures/)
- [History](./History/)
- [Factions](./Factions/)
- [Locations](./Locations/)
- [Magic and Corruption](./Magic%20and%20Corruption/)
- [Objects](./Objects/)
- [Races](./Races/)
- [Roles and Classes](./Roles%20and%20Classes/)
- [Weapons](./Weapons/)


Use the subfolder index to locate a specific entry. Each file name matches its lore heading for consistency.

## Index Maintenance
To automatically regenerate and alphabetize all category indexes, run the PowerShell script:
```
./tools/update_lore_indexes.ps1
```
This will scan `Lore/Lorebook/`, detect any new, renamed, or removed `.md` files, and rebuild each category's index file.



