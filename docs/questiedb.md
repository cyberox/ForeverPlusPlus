# QuestieDB

How Forever++ reads the [QuestieDB](https://github.com/Questie/questiedb) addon, which has quest, NPC, item, and world object data for Forever (about 4,244 quests, 10,119 NPCs, 14,889 items, and 6,645 objects, as its own docs count them). Players install it themselves; Forever++ only calls its public API at run time, through `Lib/QuestieDB.lua` (`ns.QuestieDB`). Modules never touch it directly.

QuestieDB's licence is partly all rights reserved. **Never copy its data or code into this repository, and never commit any of its files.** Read it at run time only. A module that needs it is off by default and calls `ns.QuestieDB.Require(module)`, which gives it QuestieDB's notices in its settings.

Everything below comes from reading its source and its `docs/api.md` at commit **`d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc`** (2026-11-11, version 1.0.14, contract 4). It is **Unverified** in game: QuestieDB wasn't installed on the client when this was written. The Self Test steps at the end check it.

## Getting the library

- **A global, not LibStub.** QuestieDB sets `LibQuestieDB` as the last thing it does at load, plus the shorthand globals `QuestDB`, `NpcDB`, `ItemDB`, and `ObjectDB` (the same tables as `LibQuestieDB.Quest`, `.Npc`, `.Item`, `.Object`). We read only `LibQuestieDB`.
- **Addon name `QuestieDB`.** The repository's `QuestieDB.toc` is its "source mode" TOC (Interface list includes 16001) that reads raw data files, with Forever's files chosen by `[ExcludeLoadGameType vanilla, tbc, wrath, cata, mists]`. Its releases are "baked": `QuestieDB_Forever.toc` and a byte-identical `QuestieDB_Camelot.toc` alias in the same folder, which the client prefers over the plain TOC. Its docs say Forever's acceptance of both is still pending on their side.
- **Not load on demand.** No TOC has `LoadOnDemand`, and it has no SavedVariables. It loads with the other addons, before `PLAYER_LOGIN`, so it's there by the time our modules turn on. `ns.QuestieDB.OnReady` still handles a load-on-demand copy, in case a later packaging makes it one.
- **Ready at load.** Its data can be read as soon as it has loaded: it applies its own Corrections and picks the client's locale during its own load, and then sets the global. There is no ready event or callback. A table field's first read decodes it (CBOR through `C_EncodingUtil.DeserializeCBOR` in baked mode); name indexes are built on first use.
- Its docs ask consumers to declare `## Dependencies: QuestieDB`. We don't: it's optional for us, so we probe for the global instead. Our TOC lists it in `## OptionalDeps`, so it has loaded before our files, and `ns.QuestieDB.Require` can read its status as a module's file loads.

## Versions

- `LibQuestieDB.contractVersion` (4 at this commit) and `LibQuestieDB.minSupportedContract` (1). `LibQuestieDB.RequireContract(n)` returns `true` when `min <= n <= current`, else `false, message`.
- Contract 1 is the entity read API we use. 2 changed storage only; 3 added race, faction race, and faction ID tables under `Enum`; 4 added `Enum.classKeys` and `Enum.npcFlags`. We require 1.
- Its docs promise the range rises only for a real breaking change, and that the LuaLS type files (`src/types/`, shipped as `QuestieDB/Types`) are the contract. Release `release.json` manifests carry `questiedb.version`, `contractVersion`, and `minSupportedContract`.
- `LibQuestieDB.readMode` is `"source"` or `"baked"`; its version string is the TOC's `## Version`.

## Reading entities

Each of the four entity tables has the same surface:

| Call | Returns |
| --- | --- |
| `Get(id, field)`, `<field>(id)` | one field (by canonical name or index) |
| `GetAll(id, fields)` | the fields in order in a packed table with `n`, or nil for an unknown ID |
| `GetAllIds()`, `GetAllIds(true)` | every ID ascending, or a set; **shared, read only** |
| `Exists(id)` | whether it's there |
| `IdsByName(name)` | IDs whose name is exactly `name` in the current locale, ascending, or nil; **shared, read only**. The first call builds an index of every name of that kind (23 ms for 6,666 objects in their measurement). `BuildNameIndex()` and `BuildNameIndexAsync(n)` (inside a coroutine) build it ahead of time. |
| `GetRaw(id, field)` | base data without Corrections or localization (tooling only, uncached) |

Every table it returns is a fresh copy. The schema is `LibQuestieDB.Meta.<Kind>.keys` (field name to index), also spelled `Meta.<Kind>Meta.<kind>Keys`.

Nil rules (theirs, inherited from Questie): a number field of a known entity is `0`, never nil, for "not set"; a string is nil or a string; an empty table comes back nil, except a quest's `startedBy`, `finishedBy`, and `objectives`, which are `{}`; an unknown ID is nil for every field; a bad ID (nil, a string) is nil, not an error. Numbers inside structured values default to `0` too.

### Shapes

- **Coordinates are 0-100 percents**, grouped by **AreaTable ID** (zone or subzone), not uiMapID: `spawns = { [areaID] = { { x, y, phase? }, ... } }`. A third element is a phase ID (`LibQuestieDB.Enum.phases`), left out when 0. `{ -1, -1 }` means "somewhere inside this instance", with the dungeon's area ID as the key. Forever's data is already in Forever's map frames (their conversion from Era data, `data/Forever/conversion.json`); don't run `LibQuestieDB.EraToForever` on it, which is only for Era points of your own.
- `waypoints = { [areaID] = { { {x, y}, ... }, ... } }`: patrol paths, the same units.
- `zoneID` (NPC, object): the area it's mostly in. A quest's `zoneOrSort` is a positive area ID, or a negative quest sort (quest log category) ID.

| Kind | Fields |
| --- | --- |
| Quest | `name`, `questLevel`, `requiredLevel`, `requiredMaxLevel`, `requiredRaces`, `requiredClasses` (masks), `startedBy` (`{ npcIDs, objectIDs, itemIDs }`), `finishedBy` (`{ npcIDs, objectIDs }`), `objectives` (below), `objectivesText` (strings), `triggerEnd` (`{ text, spawns }`, an explore or event objective), `sourceItemId` (given by the starter), `preQuestGroup` (all of them done first), `preQuestSingle` (any one done first), `childQuests`, `inGroupWith`, `exclusiveTo`, `nextQuestInChain`, `parentQuest`, `breadcrumbForQuestId`, `breadcrumbs`, `zoneOrSort`, `requiredSkill` (`{ skillID, value }`), `requiredMinRep`/`requiredMaxRep` (`{ factionID, value }`), `requiredSourceItems`, `reputationReward` (pairs), `extraObjectives`, `requiredSpell`, `requiredSpecialization`, `availableUntilCompleted`, `availableStartingWith`, `requiredRanks`, `disabledByQuest`, `questFlags`, `specialFlags` |
| Npc | `name`, `subName`, `minLevel`, `maxLevel`, `rank`, `spawns`, `waypoints`, `zoneID`, `questStarts`, `questEnds`, `factionID`, `friendlyToFaction` (`"A"`, `"H"`, `"AH"`), `npcFlags` (mask, `Enum.npcFlags` with `VENDOR`, `TRAINER`, ...); `minLevelHealth`/`maxLevelHealth` are placeholders (0 and 1) |
| Item | `name`, `npcDrops`, `objectDrops`, `itemDrops` (items that contain it), `vendors` (NPCs that sell it), `questRewards`, `startQuest`, `relatedQuests`, `flags`, `foodType`, `itemLevel`, `requiredLevel`, `ammoType`, `class`, `subClass`, `teachesSpell` |
| Object | `name`, `spawns`, `waypoints`, `zoneID`, `questStarts`, `questEnds`, `factionID` |

Quest `objectives` is six groups: `[1]` creatures `{ npcID, text?, icon }`, `[2]` objects `{ objectID, text?, icon }`, `[3]` items `{ itemID, text?, icon }`, `[4]` one reputation `{ factionID, value }`, `[5]` kill credit `{ { npcIDs }, rootNpcID, text?, icon }`, `[6]` spells `{ spellID, text?, itemID }`. The text is an override of the objective's name; nil means use the entity's.

### Support data

Not entity fields: whole tables through `LibQuestieDB.Support.Get(name)`, which QuestieDB keeps for Questie's own logic modules.

- `Get("ZoneDB").private.areaIdToUiMapId` and `.areaIdToUiMapIdOverride`: **Lua source text** (`"return { [areaID] = uiMapID, ... }"`) meant for `loadstring`. The main table already maps subzones to the map of their highest mapped parent zone ("Longshore -> Westfall"); the override wins, and an override of `0` means "shown on no map". Also `uiMapIdToAreaId` (and override) and `subZoneToParentZone` the same way, and `instanceIdToAreaId` as a table. Its docs say some entries are kept only for Questie's instance entrance handling and aren't native Forever maps (their `forever-map-override-audit.md`).
- Drop chances: on Forever the data is in the support module `QuestieClassicItemDrops` (`wowheadData` and `cmangosData`, each Lua source text of `{ [itemID] = { [npcID] = percent } }`), with `QuestieItemDropCorrections` beside it. The docs name `Support.Get("DropDB")`, which here holds only correction keys; the module name we read isn't in its documented contract.
- `Get("QuestXP").db` (quest XP), `Get("QuestieDB").factionTemplate`, dungeon entrances (`{ name, altAreaIDs, parentZone, { { areaID, x, y } } }`).

## What `ns.QuestieDB` gives

| Function | Returns |
| --- | --- |
| `Status()` | `"ready"`, `"missing"` (not installed), `"off"` (installed, not on), `"waiting"` (on demand, not loaded yet), `"contract"`, or `"shape"` |
| `IsAvailable()`, `IsReady()`, `Problem()` | ready or waiting; readable now; installed but not the contract or shape we read |
| `OnReady(fn)`, `Cancel(fn)` | call `fn` once it's readable (now, or after loading an on-demand copy out of combat) |
| `Info()` | `{ status, version, contract, minContract, readMode }` for Self Test |
| `Quest(id)` | `{ id, name, level, requiredLevel, maxLevel, races, classes, areaID, uiMapID, sortID, starters = { npcs, objects, items }, finishers = { npcs, objects }, objectives, objectivesText, prerequisites = { all, any }, next, children, parent, exclusiveTo, breadcrumbFor, sourceItemID, requiredSkill = { id, value } }`; objectives as `{ kind, id, text }` with `kind` `npc`, `object`, `item`, `reputation` (`value`), `killCredit` (`ids`), or `spell` (`itemID`); `children` (the quests it unlocks) and `parent` (the quest that must be in the log first) are its `childQuests` and `parentQuest`; `tag` is the client's quest tag, not QuestieDB's (below) |
| `QuestsUnlockedBy(id)`, `QuestsLeadingTo(id)` | the other way round: the quests that list it in their `prerequisites`, and the quests whose `next` it is, ascending. The first call reads three fields of every quest once (call it out of combat) |
| `Npc(id)` | `{ id, name, subName, minLevel, maxLevel, rank, flags, friendlyTo, areaID, uiMapID, spawns, instances, questStarts, questEnds }` |
| `Item(id)` | `{ id, name, level, requiredLevel, class, subClass, npcDrops, objectDrops, containers, vendors, questRewards, startsQuest, relatedQuests, teachesSpell }` |
| `Object(id)` | `{ id, name, areaID, uiMapID, spawns, instances, questStarts, questEnds }` |
| `Ids(kind)`, `IdsByName(kind, name)` | our own copies of the ID lists (`kind` is `"Quest"`, `"Npc"`, `"Item"`, `"Object"`) |
| `UiMapID(areaID)` | the uiMapID QuestieDB's ZoneDB maps an area to, or nil |
| `DropRates(itemID)` | `{ [npcID] = percent }`: Wowhead's numbers, else CMaNGOS's, or nil |
| `QuestDrops(questID)` | `{ { itemID, name, index, npcs = { [npcID] = true } } }`: each item objective a creature drops, from the item's `npcDrops`; nil for an unknown quest |
| `Notices()` | the two gray rows for `module.notice`: needs QuestieDB (while missing or off), and the version doesn't fit (while `Problem()`) |
| `Require(module)` | for a module that needs QuestieDB, called as its file loads: its notices, a red name while it's missing, off, or the wrong version, and locked while it's missing or off |

A quest also has `flags` and `specialFlags` (QuestieDB's masks, 0 for none), `repeatable` (special flag 1, or the daily, weekly, or monthly quest flag), `raid` (quest flag 64), and `minRep` and `maxRep` (`{ id, value }`: a faction and the reputation it needs at least, or less than). Quest Pins compares those with `C_Reputation.GetFactionDataByID`'s `currentStanding`, which is unchecked on Forever.

Quest Pins (`Modules/Quests/QuestPins/`) is the first module to read it. What it assumes that still needs checking in game: the client gives the Skyborne races the IDs 95 and 96 that QuestieDB's masks give bits 33 and 34 (every whole-side quest in its Forever data, 1862 Alliance and 1599 Horde, has its side's Skyborne bit, and none has all four Classic races without it; counted from the baked rows at build commit 4dbb8244, 2026-11-15), and the holiday categories are QuestieDB's sort IDs 21, 22, 41, 364, 366, 369, 370, 374, 375, 376, 378, 402, and 404, with 365 the Ahn'Qiraj war effort.

`spawns` is a list of `{ uiMapID, x, y, areaID, phase }` with x and y 0-1 on that map, as `ns.WorldMap` uses; a spawn in an area ZoneDB maps to no map is left out. `instances` lists the area IDs of dungeons it's somewhere inside. A 0 from QuestieDB ("none") is nil in ours, and every list is there, empty when there's nothing. Each read is a new table, and nothing is cached but the zone and drop tables, which are read on first use (the drop table is large: call `DropRates` out of combat).

**Converting zones.** QuestieDB's area IDs become uiMapIDs through its own ZoneDB table (override first), and its percents divide by 100. What still needs checking in game: that each uiMapID it names is a map this client has (`C_Map.GetMapInfo`), and that a point lands where the NPC stands (Self Test prints one, and its docs list Mulgore, Eastern Plaguelands, Redridge, and Stormwind as the zones whose frames moved from Era). There's no client API from an area ID to a uiMapID, so without its table we'd have to build our own from the client's tables (`tools/datagen` could, from `UiMapAssignment`/`AreaTable`).

## What it doesn't have

- **No vendor inventories.** An item lists the NPCs that sell it (`vendors`), but not the price, the stock, or a limited supply, and there's no list of what an NPC sells (we'd have to invert every item's `vendors`). `npcFlags` says which NPCs are vendors.
- **No dungeon loot tables.** An item's `npcDrops` include bosses, and a boss's `{ -1, -1 }` spawn says which instance it's in, so dungeon loot can be worked out, but there's no table of it.
- **Drop rates aren't entity data.** They're only in the support drop tables, which aren't part of its documented contract, are Classic's numbers from Wowhead and CMaNGOS (not measured on Forever), and are corrected by Questie's own logic we don't run.
- **No quest tags.** Questie's corrected `GetQuestTagInfo` (dungeon, raid, PvP, group) and its tag corrections are in the Questie addon, not QuestieDB (checked in 1.1.2). A quest's `raid` comes from its quest flags. `Quest(id)`'s `tag` is the client's own (`ns.Quests.Tag`, from `C_QuestLog.GetQuestTagInfo`), nil until the client has the quest cached.
- No NPC health (placeholders), no item prices or stats, no quest rewards beyond `questRewards` on the item side (no reward choices or money), no quest XP per quest except through `QuestXP`.

## In game, after installing QuestieDB

1. Install QuestieDB for Forever, `/reload`, and check that `/dump LibQuestieDB.contractVersion, LibQuestieDB.readMode` prints a number and `"baked"`.
2. With the Debug module on, run the Debug page's Self Test > Run (or `/fpp selftest`), then `/reload`, and read the `== questiedb` lines in `ForeverPlusPlusDB.selfTest` in the SavedVariables file: `questiedb.addon` (status, version, contract, mode), `questiedb.counts` (expect about the counts above), and `questiedb.quest` and `questiedb.npc` PASS, the NPC's map named and its x, y matching where it stands when you go there.
3. `/run print(LibQuestieDB.Support.Get("ZoneDB") ~= nil, LibQuestieDB.Support.Get("QuestieClassicItemDrops") ~= nil)` should print `true true` (the zone and drop tables are there in baked mode too).
4. `/run print(LibQuestieDB.Npc.IdsByName and #(LibQuestieDB.Npc.IdsByName(UnitName("target")) or {}))` with an NPC targeted should print 1 or more (names match the client's language).

## Race masks that look wrong in its data

Checked 2026-11-15 against QuestieDB 1.1.1 (build commit 4dbb8244), the client's `CharBaseInfo` (which race can be which class, build 1.60.1.70938), and Wowhead's Forever quest pages (`reqrace` in each page's `g_quests` entry). Quest Pins shows what the masks say, so a race a mask leaves out sees no pin for that quest. These are QuestieDB's to fix; we ship no corrections.

- No class quest is impossible: each has a race and class pair that exists. Every class mask uses only the nine Classic class bits.
- Mage, Alliance: Wowhead has Human, Gnome, and Alliance Skyborne on 1860, 1919, 1921, 1938, 1939, and 1940; QuestieDB has Human and Gnome only. Wowhead has no race at all on 1941 and 1942 (QuestieDB: Human, Gnome). 1861 and 1920 agree, with Skyborne.
- Mage, Horde: Wowhead has Orc, Undead, and Troll on 1943, 1944, 1945, and 1959; QuestieDB has Undead and Troll only. Wowhead has no race on 1946 and 1962 (QuestieDB: Undead, Troll), and Orc, Undead, Troll on 1883 where QuestieDB has the whole Horde. 1881 and 1882 agree (Undead, Troll).
- Warlock, Horde: Wowhead has Orc and Undead on 1471 and 1473 (QuestieDB: Undead), and Orc, Undead, and Troll on 1501 and 1504 (QuestieDB: Orc), so a Troll warlock sees neither Creature of the Void nor The Binding.
- Druid and shaman: not checked on Wowhead (it asked for a human check after about thirty pages). In QuestieDB the Horde druid quests 30 and 6126 to 6130 are Tauren only while their Alliance twins 272 and 6121 to 6124 include Alliance Skyborne, and the Horde shaman totem quests 79361, 79362, 79363, 79365, and 79442 leave Horde Skyborne out. 94503 and two more Call of Water quests name Gnomes, who can't be shamans. **Unverified.**
