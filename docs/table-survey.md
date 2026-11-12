# Client table survey

What WoW: Forever's client database tables actually hold, for replacing data the addon keeps by hand and for features built on generated data. Every number here was read from build **1.60.1.70888** (product `wowf`, the latest on 2026-11-11 and the one in `tools/datagen/BUILD`), as wago.tools publishes the tables (`https://wago.tools/db2/<Table>/csv?build=<build>`). wago.tools lists **619 tables** for this build.

Rerun the counts after a patch with `lua5.1 tools/datagen/survey.lua [build]`. It prints most of the numbers below and compares them with the addon's seeds. The examples and the flight time comparison were worked out by hand from the same cached CSVs.

Column names are wago.tools' names for this build. A few may be mislabeled for `wowf` (ContentTuning's `MinLevelSquish` and `MaxLevelSquish` always hold the same value, see 5). "In-game" below means something only the live client can settle. None of it was checked in game for this survey.

## Summary

| # | Area | Verdict | In one line (build 70888) |
| --- | --- | --- | --- |
| 1 | Locks: lockboxes and chests | PARTIAL | Every lockbox item's Lockpicking skill is there (27 items). World chests aren't linked to a lock or a name in any client table. |
| 2 | Random suffixes | PARTIAL | No ItemRandomSuffix or ItemRandomProperties table. Suffixes are ItemBonus lists, each with a name and stat allocations, and each item's possible suffixes are listed. The stat formula and the ID links and auction keys use need checking in game. |
| 3 | Item sets | PARTIAL | All 545 sets and 1505 set bonuses are there, but 391 sets have no item with a name or level (ItemSparse lacks them). |
| 4 | Taxi | USABLE | Every route with its cost and path. A direct flight takes its path length / 30 yd/s, within a second for every recent timing. Flights with stops don't fit a simple sum. |
| 5 | Areas, maps, dungeons | PARTIAL | Subzones yes. Zone level ranges no, only per-subzone exploration levels. Dungeons have one level each (the finder's minimum) and no highest level. |
| 6 | Professions | PARTIAL | Every recipe with reagents, created item, yellow and gray levels, and for 77% the item that teaches it. A trainer recipe's learn skill and every recipe's source aren't in the client. |
| 7 | Factions | USABLE | 75 reputations, Forever's new ones included. |
| 8 | Gathering nodes | EMPTY | Nothing maps a herb, vein, or pool object to its skill or item. The Lock table's skill values confirm the seed's skills, unnamed. |
| 9 | Disenchanting | PARTIAL | Brackets by quality, class, and item level (54 rows). What they give isn't in the client. The brackets show gaps in `Lib/Disenchant.lua`. |
| 10 | Other | mixed | ItemSparse covers only 19,325 of 32,008 items. DungeonEncounter lists bosses per dungeon; no table has loot by boss. SpellLevels gives spell rank levels. |

## Findings worth acting on now

These are hand-kept data the tables contradict, or gaps the tables show:

- **`Lib/Disenchant.lua` returns nothing for brackets the game has** (ItemDisenchantLoot, 70888): rare items at item level 5-10 (the code's rare rows start at 11; the table's start at 5), rare items above 65 (code ends at 65; table has 61-99), uncommon and epic items above 65 and 80 (table 61-99). Among ItemSparse's equippable items, that's 93 rare items at item level 5-10, 148 rare at 66-80, 39 uncommon at 81-99, and 235 epics at 81-99 with no Disenchant line. The code's bracket edges also differ: it has rare 11-25 as one row where the table has 5-15, 16-20, and 21-25. The table doesn't say what each bracket gives, so the new rows' materials are still a guess.
- **Random suffixes are bonus lists on Forever, not ItemRandomSuffix IDs.** `Lib/ItemButtons.lua` puts an auction row's `itemKey.itemSuffix` into the link's suffix field (`item:ID:::::::suffix`). If Forever's links carry suffixes as bonus IDs (the tables' IDs are 12688-13784), that link reaches Upgrade Arrows without the suffix's stats. This isn't proven wrong: the tables can't show what number `itemSuffix` holds. Check in game: `/dump` a browse result's `itemKey` and a bag item's link with a suffix.
- **Instances.lua's lowest levels differ from the dungeon finder's for 17 instances** (LFGDungeons -> ContentTuning, 70888), for example Uldaman 41 vs 35 and Razorfen Kraul 29 vs 24. The game's finder fixes these at run time once the player opens it, so they matter only before that. For Forever's own dungeons only The Shaper's Terrace disagrees: 58 in the seed (Group Finder, seen in game) vs 60 in the tables.
- **Zone Info's level ranges** fit the range of their subzones' exploration levels exactly in 7 of 39 zones. That isn't a definite error, since the two measure different things (see 5), but no table supports the hand values either.

## 1. Locks: lockboxes and chests (PARTIAL, 70888)

Tables: `Lock` (315 rows), `LockType` (23), `ItemSparse.LockID`, `GameObjects` (1,526).

An item's lock is `ItemSparse.LockID` -> `Lock.ID`. A lock has eight slots: `Type_n` 2 means "a lock type", `_Index_n` is the `LockType.ID`, and `Skill_n` is the skill it takes. LockType 1 is "Pick Lock", 2 Herbalism, 3 Mining, 19 Fishing.

27 items have a Pick Lock lock. Examples (`ItemSparse.ID`, `Display_lang`, `LockID` -> Pick Lock `Skill_0`):

| Item | Name | Lock | Lockpicking |
| --- | --- | --- | --- |
| 4632 | Ornate Bronze Lockbox | 5 | 1 |
| 4634 | Iron Lockbox | 24 | 70 |
| 4638 | Reinforced Steel Lockbox | 62 | 225 |
| 16885 | Heavy Junkbox | 599 | 250 |
| 12033 | Thaurissan Family Jewels | 600 | 275 |

All are Classic's values. Forever adds 227937 Puzzle Box (175) and test items (241233 "[DNT] Super Strong Lockbox" 305, 24282 Rogue's Diary 5000).

World chests are server-side objects. The client's `GameObjects` holds only client-placed objects: 1,521 of its rows are `TypeID` 5 (signposts and doodads), plus 3 meeting stones and 2 farms, and only 4 names contain chest, vein, deposit, or school (mine signs). So no table links "Battered Chest" to a lock. The Lock table's Pick Lock skills (1 25 35 45 50 55 70 75 100 110 125 150 160 175 200 225 250 255 275 280 300 305) include the chests' locks, but without names.

Against `Lib/Professions.lua`'s `treasureNodes` seed: its 13 chests are all `true` (no skill), so there's nothing to compare. **Absent**: the tables can't replace it, and can't fill in a chest's Lockpicking. The game's "Requires Lockpicking (N)" tooltip line remains the source.

## 2. Random suffixes (PARTIAL, 70888)

`ItemRandomProperties` and `ItemRandomSuffix` **don't exist** for `wowf` (wago.tools returns HTTP 400 for both on this build, and neither is in its table list). Forever does random suffixes the Retail way, as item bonus lists:

- A suffix is a bonus list: the `ItemBonus` rows with that `ParentItemBonusListID`. A `Type` 5 row names it (`Value_0` -> `ItemNameDescription.Description_lang`). Each `Type` 2 row is one stat: `Value_0` is the stat (the `ITEM_MOD` numbering: 3 Agility, 4 Strength, 5 Intellect, 6 Spirit, 7 Stamina, 12 defense, 38 attack power, 41/42 healing, 45 spell power, 51-56 resistances, 84-89 school damage) and `Value_1` its allocation in 1/10000.
- 345 bonus lists have a name, 344 of them with stats. They carry 50 distinct names, from "of Agility" to "of the Wolf" (and "Test"), with IDs 12688 to 13784.
- Which suffixes an item can roll: `ItemXBonusTree` (`ItemID` -> `ItemBonusTreeID`, 2,049 items) -> `ItemBonusTreeNode` rows with that `ParentItemBonusTreeID` -> `ChildItemBonusListID`.
- Amounts, the Retail formula (**not checked on Forever**): `RandPropPoints` row for the item's `ItemLevel` (300 rows), column `Good_n` / `Superior_n` / `Epic_n` by quality, `n` by slot (0 head, chest, legs, two-hand; 1 shoulder, waist, feet, hands, trinket; 2 wrist, neck, finger, back, off hand, shield; 3 one-hand; 4 ranged), times the allocation / 10000, rounded.

Examples:

| Bonus list | Name | Stats (`Value_0`, `Value_1`) |
| --- | --- | --- |
| 12688 | of Intellect | 5 (Int), 6000 |
| 12691 | of the Owl | 5 (Int), 3000; 6 (Spi), 3000 |
| 12718 | of the Eagle | 5 (Int), 6666; 7 (Sta), 6666 |
| 13190 | of the Monkey | 3 (Agi), 3666; 7 (Sta), 3666 |
| 13056 | of Healing | 42, 6233; 41, 18700 |

Worked through the formula: 20039 Dark Iron Boots (item level 70, epic, feet, `Epic_1` = 38) "of the Monkey" gives 13.93, so about +14 Agility and +14 Stamina. 10504 Green Lens (49, rare, head, `Superior_0` = 28) "of Magic" (45, 9945) gives about +28 spell power.

What's missing: only 391 of the 2,049 items with a bonus tree have an `ItemSparse` row (item level, quality, slot). In game that doesn't matter, since `C_Item.GetItemInfo` gives all three. The formula and its rounding need one check against a real tooltip. **Which number auction keys and links use isn't in the tables**: whether `itemKey.itemSuffix` is the bonus list ID, an old suffix ID, or a negative one. See the in-game check under "Findings worth acting on now".

## 3. Item sets (PARTIAL, 70888)

`ItemSet` (545 rows: `Name_lang`, `ItemID_0`..`ItemID_16`) and `ItemSetSpell` (1,505 rows: `ItemSetID`, `Threshold` pieces, `SpellID`). The bonus text is `Spell.Description_lang`, with `$s1` filled from `SpellEffect`.

- 154 sets have at least one item in `ItemSparse`. All of them need level 60 or less (highest `RequiredLevel` 60).
- 391 sets have no item in `ItemSparse`. 387 of those have their items in `Item` (class and slot only). This includes Classic's dungeon and raid sets: 181 Magister's Regalia, 189 Battlegear of Valor, 201 Arcanist Regalia, 209 Battlegear of Might.
- Forever's own sets are there: 1576 Battleplate of Might, 1663 Nightslayer Battlearmor, 1719 Immoveable Might, 1720 Unstoppable Might, 2136 Defias Enforcer's Garb.

Examples: 142 Stormshroud Armor (4 items, required 57): 2 pieces 18979 "Lightning", 3 pieces 23863 "Revitalize", 4 pieces 9142 "Attack Power 14". 2096 Lieutenant Commander's Thunderfist (6 items, required 55): 2 pieces 14047 (`Description_lang` "Increases damage and healing done by magical spells and effects by up to $s1."), 4 pieces 22804, 6 pieces 14467 "+$s1 Stamina.".

A set tooltip in game can name each item through `C_Item`, so "which sets exist and what they give" is usable. "Items' levels and names offline" isn't.

## 4. Taxi (USABLE, 70888)

`TaxiNodes` (101 rows), `TaxiPath` (328: `FromTaxiNode`, `ToTaxiNode`, `Cost`), `TaxiPathNode` (10,965: `PathID`, `NodeIndex`, `ContinentID`, `Loc_0..2`, `Delay`). 314 paths run between two known nodes and have points; 286 have a cost above 0. Costs look like copper (110, 330, 630, ...). Whether that's what the flight master charges wasn't checked; the game gives the cost at run time anyway.

**Flight duration from path length**: the sum of distances between consecutive path points on one continent, compared with the times Flight Timer saved in the client's `WTF\Account\*\SavedVariables\ForeverPlusPlus.lua` (read, not changed):

- The account last saved 2026-11-11: all 12 direct flights took 29.7-30.0 yd/s. For example Stormwind > Ironforge (nodes 2 > 6) is 7,757 yd and took 259 s, which is 258.6 at 30 yd/s. Stormwind > Booty Bay is 7,318 yd in 244 s, and Ironforge > Stormwind 6,310 yd in 211 s.
- The account last saved 2026-10-20: 13 of 24 direct flights at 29.7-30.0 yd/s, and 11 at 35.5-36.0 yd/s (exactly 1.2 times as fast), all in the Eastern Kingdoms around Stormwind. The same pairs take 30 yd/s on the newer account. Probably an older build or a speed bonus at the time; not known which.
- Flights with stops: 3 of the 12 timed ones (all Kalimdor: Rut'theran > Astranaar 261 s, Stonetalon Peak > Ratchet 436 s, Ratchet > Rut'theran 516 s) match the summed legs of the shortest route to the second. The Eastern Kingdoms ones through Ironforge were 8-13% shorter than the summed legs (Menethil > Stormwind 260 s against 299 s). The game skips the landing at each stop, or routes differently; the tables don't say which.

So a generated table of direct flight times (path length / 30) would give Flight Timer a time before the first flight. Flights with stops still need timing. Flight Timer keeps no seed today (only learned times), so there's nothing hand-kept to compare. Points of Interest's flight points were already compared with TaxiNodes by `reference.lua` (`tools/datagen/Reference.txt`), which found them the same in 70888. Forever's new nodes are there too, for example 3276 Farholde Keep, Riverglades.

## 5. Areas, maps, dungeons (PARTIAL, 70888)

Tables: `AreaTable` (1,404 rows), `UiMap` (60), `UiMapAssignment` (61), `Map` (80), `MapDifficulty` (142), `LFGDungeons` (76), `ContentTuning` (100).

**Subzones: USABLE.** `AreaTable.ParentAreaID` gives each zone's subzones, for example Elwynn Forest (12): 18 Crystal Lake, 9 Northshire Valley. 189 areas have no parent. A zone map's area is `UiMapAssignment` (`UiMapID` -> `AreaID`).

**Zone level ranges: absent.** `UiMap.ContentTuningID` is 0 on all 60 maps, and `AreaTable.ContentTuningID` is set on only 28 areas, all dungeons. What exists is `AreaTable.ExplorationLevel` on 706 subzones (0 on the zones themselves). Against Zone Info's `Data.lua` ranges, the range of a zone's subzone levels:

| Zone (map) | Zone Info | Subzones' range | Median |
| --- | --- | --- | --- |
| Elwynn Forest (1429) | 1-10 | 5-10 | 8 |
| Redridge Mountains (1433) | 15-25 | 15-25 | 20 |
| Duskwood (1431) | 18-30 | 10-30 | 25 |
| Stranglethorn Vale (1434) | 30-45 | 30-50 | 40 |
| Dustwallow Marsh (1445) | 35-45 | 36-61 | 36 |

Over all 39 zones with levels: 7 exact, 13 more within 2 levels at both ends, 19 further off, usually from one odd subzone (Dun Morogh's goes to 56). **Differs**: the tables can't replace the ranges as they stand. A rule (trimmed range or median) could suggest them but wouldn't match. Zone Info's fishing skills and herb and ore lists are **absent** from every table.

**Dungeon levels: one number each.** `LFGDungeons` has 30 dungeons and raids (`TypeID` 0), 3 battlegrounds (5), and 43 zones (4, all on one empty tuning). `ContentTuningID` -> `ContentTuning.MinLevelSquish` gives a level, with `MaxLevelSquish` always the same value. `LfgMinLevel` / `LfgMaxLevel` are 0 except Ruins of Lordaeron's 27. The dungeon's area (`AreaTable.ContentTuningID`) has the same tuning. Against `Lib/Instances.lua`'s lowest level (by finder name, the map's area, or the area's name): **13 same, 17 differ, 5 absent**. Same: Ragefire, Wailing Caverns, Zul'Gurub, Molten Core, Blackwing Lair, and Forever's Hall of Thanes 13, Drowned City 35, Krol'dok 40, Alcaz 48, Blackmaw 55, Ruins of Lordaeron 15, Excavation Site 26, Dalaran 28. Differ (seed vs tables): Deadmines 17/16, Shadowfang 22/18, Blackfathom 24/22, Stockade 22/23, Gnomeregan 29/25, Razorfen Kraul 29/24, Scarlet 34/30, Razorfen Downs 37/34, Uldaman 41/35, Zul'Farrak 44/42, Maraudon 46/42, BRD 52/48, Blackrock Spire 55/53, Dire Maul 56/54, Stratholme 58/55, Scholomance 58/57, Shaper's Terrace 58/60. Absent: AQ20, AQ40, Naxxramas, and Onyxia's Lair and Sunken Temple (the finder has them as "Onyxia" 60 and "Sunken Temple" 45, names the survey's match misses). **The highest level is absent** from every table. The instance IDs are in `Map` (`InstanceType` 1 and 2), which `Reference.txt` already checks.

## 6. Professions (PARTIAL, 70888)

Tables: `SkillLine` (154), `SkillLineAbility` (7,853), `SpellName` (32,482), `SpellEffect` (43,508), `SpellReagents` (3,319), `ItemEffect` (12,693), `ItemXItemEffect` (12,679), `TradeSkillCategory` (216). Jewelcrafting (755) and Inscription (773) aren't in SkillLine.

How it links up:

- A recipe is a `SkillLineAbility` row: `SkillLine`, `Spell`, `TrivialSkillLineRankLow` (yellow) and `TrivialSkillLineRankHigh` (gray), which Professions' `Data.lua` already uses.
- Reagents: `SpellReagents` by `SpellID` (`Reagent_n`, `ReagentCount_n`).
- Created item: `SpellEffect` `Effect` 24 with `EffectItemType`.
- The item that teaches it: an `ItemEffect` with `TriggerType` 6, whose `SpellID` is the recipe itself (alongside a `TriggerType` 0 "Learning" spell 402265), joined through `ItemXItemEffect`.

| Profession | Recipes | With reagents | Taught by an item | Item named (ItemSparse) |
| --- | --- | --- | --- | --- |
| Blacksmithing | 527 | 507 | 423 | 377 |
| Leatherworking | 616 | 592 | 510 | 475 |
| Alchemy | 212 | 196 | 151 | 139 |
| Tailoring | 486 | 471 | 376 | 349 |
| Engineering | 295 | 275 | 203 | 172 |
| Enchanting | 273 | 262 | 195 | 170 |
| Cooking | 141 | 133 | 119 | 116 |
| First Aid | 40 | 32 | 17 | 16 |

Examples:

- 2335 Swiftness Potion: taught by 2555 Recipe: Swiftness Potion (`RequiredSkillRank` 60), yellow 90, gray 130.
- 2158 Fine Leather Boots: taught by 2406 Pattern: Fine Leather Boots (65), yellow 95, gray 125.
- 12716 Goblin Mortar: taught by 221337 (no ItemSparse row), reagents 10559 x2, 3860 x4, 10505 x5, 10558, 7068, creates 10577, yellow 225, gray 245.
- 1225762 Specklefin Feast (Forever's): taught by 239021 Carrie's Cookbook, reagents 4603 x12, 12184 x4, 6362 x3, 239017, creates 238641, yellow 290, gray 310.

What's missing for "recipes you don't know yet":

- **The learn skill.** `SkillLineAbility.MinSkillLineRank` is 1 for nearly every recipe (all of Leatherworking's 616). For a recipe an item teaches, the item's `ItemSparse.RequiredSkillRank` is the learn skill (it equals `MinSkillLineRank` in only 10 of 1,830 cases). For trainer recipes, the learn skill and cost are server data, **absent**.
- **The source.** Which trainer, vendor, or drop: absent. `CollectableSourceVendorSparse` lists 174 vendors with positions, but no recipe items among its 1,181 items.
- About 12% of item-taught recipes have no `ItemSparse` row, so no item name offline (in game, `C_Item` names them).
- The ability list includes old and test entries ("Deprecated Recipe: ...") and Forever's Blueprints (1262980 Greenhouse, 1262975 Rock Garden). A list for players needs filtering, for example to recipes whose item or spell the game knows.

## 7. Factions (USABLE, 70888)

`Faction` (253 rows; 75 with `ReputationIndex` other than -1, which makes them reputations), `FactionTemplate` (454). `ParentFactionID` gives the headers (469 Alliance, 67 Horde, 169 Steamwheedle Cartel, 891/892 Alliance and Horde Forces).

Examples: 72 Stormwind (parent 469), 21 Booty Bay (169), 529 Argent Dawn, 270 Zandalar Tribe, 909 Darkmoon Faire. Forever's own: 2586 Azeroth Commerce Authority, 2587 Durotar Supply and Logistics, 2641 Emerald Wardens, 2719 Cenarion Scouts, 2740 Kirin Tor, 2765 Guardians of Hyjal, 2787 Earthen Ring, 2798 Darkspear Raiders, 2799 Theramore Expeditionary Force, 2826 Brotherhood of the Horse, 2827 Powderfuse (169). Needs filtering: the old profession pseudo-factions (46 Blacksmithing - Armorsmithing, ...), 2800 PvP Rank Points, 2802 Legacy Track, 2807 DNT Test Reputation.

## 8. Gathering nodes (EMPTY, 70888)

No client table maps a herb, vein, or fishing pool object to its skill or item. Herbs, veins, and pools are server objects, like chests (see 1).

What exists: the Lock table's skill values. Herbalism locks: 0 1 15 25 50 70 75 85 100 115 120 125 (x2) 130 140 150 160 170 185 195 205 210 215 220 230 235 245 250 260 270 280 285 290 300. Mining: 1 25 50 65 75 (x2) 100 125 (x2) 150 155 175 230 (x2) 245 275 300 305 310. Fishing: 25 50 100 175 250 375. Every skill in `Lib/Professions.lua`'s `professionNodes` seed is among them: **27 of 27 herb skills and 11 of 11 vein skills**. But they have no names, so the seed's names and items (and the fishing pools' names) **can't be replaced**. `ItemSalvageLoot` group 124 lists all 28 of the seed's herb items, among 129 trade goods, as a salvage list, not a node mapping.

## 9. Disenchanting (PARTIAL, 70888)

`ItemDisenchantLoot` (54 rows: `Class` 2 weapon or 4 armor, `Quality`, `MinLevel`, `MaxLevel` item level, `SkillRequired`, `Subclass` -1, `ExpansionID` -2). It names brackets only. What each bracket gives (the loot) is server data, **absent**.

Brackets, the same for weapons and armor:

| Quality | Table (item level) | `Lib/Disenchant.lua` | Compare |
| --- | --- | --- | --- |
| Uncommon | 5-15, 16-20, 21-25, 26-30, 31-35, 36-40, 41-45, 46-50, 51-55, 56-60, 61-99 | same, but last 61-65 | 10 of 11 same; last row stops at 65 |
| Rare | 5-15, 16-20, 21-25, 26-30, ..., 56-60, 61-99 | 11-25, 26-30, ..., 51-55, 56-65 | 6 of 11 same; no 5-10; 11-25 is one row; stops at 65 |
| Epic | 40-45, 46-50, 51-55, 56-60, 61-99 | same, but last 61-80 | 4 of 5 same; stops at 80 |

`SkillRequired` is 0 on every row (the code has no skill gate either: same). See "Findings worth acting on now" for the items this leaves without a Disenchant line.

## 10. Other (70888)

- **ItemSparse is partial.** `Item` has 32,008 rows, but `ItemSparse` (names, item level, required level, sell price, set, lock, bonding) has 19,325. 12,683 items have only class and slot, including many Classic items (Arcanist Regalia's 16802 has none). Anything generated from ItemSparse covers about 60% of items. In game, `C_Item` fills in the rest. Whether wago.tools' CSV leaves out hotfixed or encrypted rows the client gets later couldn't be checked. `ItemSearchName` (6,649) is smaller still.
- **Sell prices and required levels**: `ItemSparse.SellPrice` set on 11,919 items, `RequiredLevel` above 0 on 9,976. Examples: 202 Thick Cloth Shoes sells for 342, needs 17, item level 22; 209 Dirty Leather Pants 12, 1, 5. USABLE where the row exists, but the game already shows these.
- **Spell learn levels**: `SpellLevels` (13,072 rows: `SpellID`, `BaseLevel`, `SpellLevel`, `MaxLevel`). Fireball ranks 133/143/145/8400/25306 are levels 1/6/12/24/60, and Arcane Intellect 1459/10157 levels 1/56, as on Classic's trainers. USABLE for "a new rank at level N" (Spell Ranks).
- **Bosses**: `DungeonEncounter` (376 rows on 47 maps, `Name_lang`, `MapID`, `OrderIndex`). Examples: Deadmines (36) 8 bosses from Rhahk'Zor, Molten Core (409) 11 from Lucifron, and Forever's Hall of Thanes (3065): Faldrim Anvilmar, Plunder, Infurnus, Durgen Dirgehammer. USABLE for boss lists. **Loot by boss is in no client table**: `JournalEncounter`, `JournalEncounterItem`, and `JournalInstance` don't exist for `wowf`, and `CreatureDifficultyTreasure` wasn't checked.
- `AreaPOI` (372 rows: towns, graveyards, and other named spots with positions; 147 on Kalimdor, 120 on the Eastern Kingdoms). `QuestV2` (6,626) holds IDs only, with no names, levels, or givers (QuestieDB stays the source). `Creature` (189) holds only companions and other client creatures, not NPCs. `CollectableSourceVendorSparse` (3,568 rows) gives 174 vendors' positions for 1,181 collectable items, mostly gear appearances.

## Not checked

- Anything in the live client. In particular: the suffix formula against a tooltip, what `itemKey.itemSuffix` and a suffixed link contain, whether TaxiPath's cost is what's charged, and why the October flight times ran at 36 yd/s.
- Whether wago.tools' CSVs include hotfixed rows, and so whether ItemSparse's missing 12,683 items are really absent from the client or only from the export.
- `CreatureDifficultyTreasure`, `Vignette` (2 rows), `UIMapPinInfo`, `QuestPOIBlob`/`QuestPOIPoint`, `ExpectedStat`, and the many tables not listed above. The full list for the build is cached in `tools/datagen/cache/<build>/tables.txt` after a survey run.
- The game's route choice for flights with stops.
