```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 80, "rankSpacing": 150}, "theme": "dark", "themeVariables": {"background": "#181a20", "primaryColor": "#23272f", "edgeColor": "#e2e8f0", "fontFamily": "Segoe UI, Roboto, sans-serif", "fontSize": "16px", "nodeTextColor": "#e2e8f0", "lineColor": "#e2e8f0", "secondaryColor": "#23272f", "tertiaryColor": "#23272f"}}}%%
flowchart TD
  classDef world fill:#2b6cb0,stroke:#1a4369,color:#ffffff;
  classDef realm fill:#d69e2e,stroke:#b7791f,color:#1a202c;
  classDef region fill:#38a169,stroke:#276749,color:#ffffff;
  classDef biome fill:#dd6b20,stroke:#9c4221,color:#ffffff;
  classDef location fill:#06b6d4,stroke:#0891b2,color:#ffffff;
  classDef point fill:#805ad5,stroke:#553c9a,color:#ffffff;
  classDef faction fill:#22c55e,stroke:#15803d,color:#ffffff;
  classDef character fill:#d53f8c,stroke:#97266d,color:#ffffff;
  classDef creature fill:#3b82f6,stroke:#1d4ed8,color:#ffffff;
  classDef concept fill:#cbd5e0,stroke:#a0aec0,color:#1a202c;
  classDef placeConcept fill:#f472b6,stroke:#be185d,color:#ffffff;
  classDef history fill:#ecc94b,stroke:#b7791f,color:#1a202c;
  classDef object fill:#38b2ac,stroke:#2c7a7b,color:#1a202c;
  classDef role fill:#4a5568,stroke:#2d3748,color:#ffffff;
  classDef race fill:#c53030,stroke:#9b2c2c,color:#ffffff;
  World_terra(["World: Terra"])
  class World_terra world
  Faction_wolf_pack["Faction: Wolf Pack"]
  class Faction_wolf_pack faction
  faction_glen_riders["Faction: Glen Riders"]
  class faction_glen_riders faction
  region_the_sea_of_glass(["Region: The Sea of Glass"])
  class region_the_sea_of_glass region
  realm_americana(["Realm: Americana"])
  class realm_americana realm
  realm_americana --> region_the_sea_of_glass
  World_terra --> realm_americana
  style World_terra fill:#2b6cb0,stroke:#1a4369,color:#ffffff
  style Faction_wolf_pack fill:#22c55e,stroke:#15803d,color:#ffffff
  style faction_glen_riders fill:#22c55e,stroke:#15803d,color:#ffffff
  style region_the_sea_of_glass fill:#38a169,stroke:#276749,color:#ffffff
  style realm_americana fill:#d69e2e,stroke:#b7791f,color:#1a202c
  Faction_wolf_pack -.-> region_the_sea_of_glass
  faction_glen_riders -.-> region_the_sea_of_glass
```
