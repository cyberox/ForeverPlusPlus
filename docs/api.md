# Forever++ API for addon authors

Forever++ shares what it knows with other addons through one global, `ForeverPlusPlusAPI`. The code is [`ForeverPlusPlus/API.lua`](../ForeverPlusPlus/API.lua).

```lua
local FPP = ForeverPlusPlusAPI and ForeverPlusPlusAPI.v1
if FPP then
    local copper, seenAt = FPP.GetAuctionPrice(itemLink)
end
```

Add `## OptionalDeps: ForeverPlusPlus` to your TOC so Forever++ loads first. Then `ForeverPlusPlusAPI` is there when your files run. Saved data (players seen, which modules are on) loads at `PLAYER_LOGIN`, so read it after `IsReady()` returns true or after the `READY` callback.

## Promises

- **`v1` never breaks.** Functions and return values may be added to it, but nothing is renamed or removed and no meaning changes. A breaking change would ship as `v2`, next to `v1`.
- **Read only.** You get copies and plain values, never Forever++'s own tables. Changing one has no effect. Assigning into `ForeverPlusPlusAPI` or `v1` raises an error.
- **Calls can't break your addon.** An error inside Forever++ goes to the error handler (BugSack shows it) and the call returns `nil`. Bad input, like a table where an item belongs, also returns `nil`.
- **`nil` means unknown.** Much of this data comes from modules the player can turn off, or from what Forever++ has seen in play. Always handle `nil`.

Wherever a function takes `item`, it accepts an item ID (`4305`), an item link, an `"item:4305"` string, or an item name. A name is found in the client's item cache first, then among the items with an auction price.

Colors come back as `r, g, b` (0 to 1) plus a hex string `"ffrrggbb"`, the same form as a class color's `colorStr`.

## General

| Function | Returns |
| --- | --- |
| `GetVersion()` | The API version (`1`) and Forever++'s version, such as `"1.0.0"`. |
| `IsReady()` | Whether saved data has loaded (after `PLAYER_LOGIN`). |
| `GetProfile()` | The name of the settings profile this character uses (`"Default"` until the player makes another), and how many profiles there are. `nil` before `READY`. Which modules are on and their options follow the profile, so after `PROFILE_CHANGED` read them again. |
| `GetProfilePreset()` | The preset the profile in use is based on, as `{ name, title }`: `name` its key (`"developer"`), `title` its name in the player's language (`"Developer's Defaults"`). A profile based on a preset reads the preset's values for every setting the player hasn't set, so `IsModuleEnabled`, `GetModuleOption`, and `GetModuleInfo`'s `value` already include them. `nil` for a profile based on none, and before `READY`. Added in 1.6.0. |
| `GetPresets()` | Every preset Forever++ has, in order, as `{ name, title, description }`. Added in 1.6.0. |
| `IsModuleEnabled(name)` | Whether a module is on, by its internal name (`"ItemTooltips"`, `"ClassColors"`), or `nil` for a name Forever++ doesn't have (or doesn't offer on this client). Use it to skip something Forever++ is already showing. |
| `GetModules()` | A list of `{ name, title, category, enabled }` for every module this client gets. |
| `GetModuleInfo(name)` | One module in full: `{ name, title, description, category, enabled, locked, problem, options }`. `locked` is true for a module the game broke, which can't be turned on, so don't send the player to; `problem` is true while it has found it can't work (its name is red in Settings). Each option is `{ key, name, kind, value, default, choices, min, max }`, where `kind` is `"checkbox"`, `"dropdown"` (its `choices` are the values), or `"slider"`. The options are the ones the Modules page shows. |
| `GetModuleOption(name, key)` | One option's value as the player set it, or (unset) what the profile's preset says, or its default: what the module itself reads. `nil` for an option the module doesn't have. |
| `OpenSettings(name)` | Opens Forever++'s settings on that module, or on the Modules page when `name` is left out. Use it for a button in your addon's options that sends the player here. Returns `false` in combat. |

The API can read modules and options but can't change them: those are the player's choices. To have the player change one, open the page with `OpenSettings`.

### Old names

A module that became part of another keeps answering by its old name, with what is true now, so code written against the old name doesn't break. `GetModules` and the callbacks (`MODULE_TOGGLED`, `OPTION_CHANGED`) use only the new names; use those in new code.

| Old name | Now |
| --- | --- |
| Module `RecipeColors` (up to 1.4.0) | The `Professions` module's Recipe Colors part. `IsModuleEnabled("RecipeColors")` is true while `Professions` is on and its `recipeColors` option is on. `GetModuleInfo("RecipeColors")` gives its part's title and description, those two as `enabled`, and only the options it had, `highlight` and `gray`, read from `Professions`; `GetModuleOption("RecipeColors", "highlight")` and `"gray"` read them too. `OpenSettings("RecipeColors")` opens `Professions`. |
| Option `crafting` of `ItemTooltips` (up to 1.4.0) | The `Professions` module's Crafting Costs part: `GetModuleOption("ItemTooltips", "crafting")` reads `GetModuleOption("Professions", "crafting")`. |

## Auction prices

Prices come from Item Tooltips' Auction Prices: Forever++'s own scans of the auction house, or Auctionator's prices when the player picks Use Auctionator's Prices. While that part is off, there are no prices.

| Function | Returns |
| --- | --- |
| `HasAuctionPrices()` | Whether there are prices to give. |
| `GetAuctionPriceSource()` | `"ForeverPlusPlus"`, `"Auctionator"`, or `nil` without prices. |
| `GetAuctionPrice(item)` | The lowest buyout for one of the item in copper, and the `time()` it was seen (`nil` when unknown). `nil` when there's no price. |

## Disenchanting

Which items can be disenchanted follows the game's own brackets, by quality, item level, and weapon or armor. What a bracket gives follows Classic's rules where the game's brackets match them, and otherwise what the player's own disenchants showed. Forever's results may differ.

| Function | Returns |
| --- | --- |
| `CanDisenchant(item)` | Whether the item can be disenchanted, even when what it gives isn't known yet. `nil` when the client hasn't loaded it yet. |
| `GetDisenchantResults(item)` | What disenchanting gives, most likely first: a list of `{ itemID, chance (0 to 1), min, max }`, with `seen` on each when it was learned from the player's disenchants (how many). `nil` when the item can't be disenchanted, what it gives isn't known yet, or the client hasn't loaded it yet (ask again after `GET_ITEM_INFO_RECEIVED`). |
| `GetDisenchantValue(item)` | The average value in copper at the auction prices, and how many results had no price (the total leaves those out). `nil` without prices or results. |

## Upgrade scores

These come from Upgrade Arrows while it's on. They use the same stat weights for the player's class and talent tree, and the same comparison against what's worn, as its arrows: a ring is compared with the weaker ring, and a two-hander with both hands. Pass an item link where you have one, since the link carries the item's suffix (like "of the Bear").

| Function | Returns |
| --- | --- |
| `HasUpgradeScores()` | Whether scores can be read (Upgrade Arrows is on). |
| `GetItemUpgradeInfo(item)` | `{ canUpgrade, isUpgrade, isDowngrade, percent, score, equippedScore }`. `percent` is how much better or worse the item is than what it would replace (`nil` against an empty slot). `canUpgrade` is false for something that can never be an upgrade: not gear, can't be used, or already worn. `nil` while Upgrade Arrows is off or the client hasn't loaded the item. `isUpgrade` uses the player's Upgrade Threshold. |
| `GetItemScore(item)` | The item's score by the weights in use, whether or not it could be an upgrade. |
| `GetUpgradeProfile()` | The weights in use: `{ key ("MAGE:3"), class, tab, bear, guess, weights }`. `weights` maps stats in short keys (`"STR"`, `"SP"`, `"HIT"`, as in [stat-weights.md](stat-weights.md)) to their weight. `guess` is true while there are no talent points to go by. |

Scores change when gear, level, talents, weights, or Upgrade Arrows' options change. `UPGRADES_UPDATED` says when.

## Flight times

These come from Flight Timer while it's on. Flight points are the game's node IDs (`nodeID` from `C_TaxiMap`). A route's time is known once the player has flown it. Each direction is its own route.

| Function | Returns |
| --- | --- |
| `GetFlightTime(fromNodeID, toNodeID)` | The flight's length in seconds, or `nil` if it hasn't been flown. |
| `GetCurrentFlight()` | The flight underway: `{ fromNodeID, toNodeID, duration, elapsed, remaining }` in seconds. `duration` and `remaining` are `nil` the first time a route is flown. `nil` when not flying. |
| `GetFlightTimes()` | Every flight timed, for the account: a list of `{ fromNodeID, toNodeID, seconds }`, sorted. |
| `GetKnownFlightPoints()` | The flight points this character has learned, as Forever++ has seen them at a flight master: a set of node IDs → `true`. Forever's own map list can't say which are learned. From World Map's Points of Interest, and `nil` while it's off. |

## Waypoints and maps

The waypoint is Blizzard's own map pin, the same one `/way` and a click on the map set. It shows on the map, as the marker in the world, and on Waypoints' arrow. Spots are 0 to 1 across and down a map, as `C_Map` gives them (not 0 to 100 as `/way` takes them).

| Function | Returns |
| --- | --- |
| `SetWaypoint(map, x, y)` | Puts the pin on `map`, which is a map ID, a zone name (as `FindZone` reads it), or `nil` for the player's map, and tracks it. Returns `true`, or `false` and why: `"zone"` (no such zone), `"range"` (x or y outside 0 to 1), `"map"` (no pin allowed there, like inside a dungeon), or `"unavailable"`. |
| `GetWaypoint()` | The pin's map ID and x, y, or `nil` when there's none. |
| `ClearWaypoint()` | Takes the pin away. |
| `GetWaypointTarget()` | What Waypoints' arrow points at: `{ kind, mapID, x, y, title, yards }`. `kind` is `"pin"`, `"quest"` (the quest selected on the map, with its `title`), or `"corpse"`. `yards` is `nil` when the game can't say how far. `nil` while there's nothing to point at, or while Waypoints or its Arrow is off. |
| `FindZone(name)` | A zone's map ID from its name in the player's language, matched without caring about case or spaces. An exact name wins, then a zone whose name starts with it. `"#1429"` is a map ID. |
| `GetPlayerPosition()` | The player's map ID and x, y, or `nil` when the game can't say, as in a dungeon. |

## Players seen

Forever++ saves the class, level, race, and guild of the other players it sees, for the whole account: your group, your guild roster, friends, `/who` results, units you target or mouse over, nameplates, and chat. It learns while a module that uses this data is on (Chat Levels, Class Colors' Offline Friends, Whisper Window). What's already saved can be read either way. Players not seen for 60 days are dropped.

| Function | Returns |
| --- | --- |
| `GetPlayerInfo(name, guid)` | `{ class, className, level, race, guild, lastSeen }`. `class` is the token (`"MAGE"`), `className` and `race` are localized, and `lastSeen` is a `time()`. Any field can be `nil`. Returns `nil` for someone never seen. `name` may include a surname (`"Bob-Surname"`). `guid` is optional and tells apart players with the same name on different realms. |
| `GetPlayerClassColor(name, guid)` | Their class color, from the class last seen. |

Levels are the last ones seen, so they can be behind. Check `lastSeen`.

## Colors

| Function | Returns |
| --- | --- |
| `GetClassColor(classToken)` | A class's color (`"MAGE"`). |
| `GetLevelColor(low, high)` | A level or level range against the player's level, colored like a quest: red or orange above you, yellow while you're in it, green or gray once you've outleveled it. Leave out `high` for a single level. |

## Dungeons and raids

| Function | Returns |
| --- | --- |
| `GetInstances()` | Every dungeon and raid, lowest level first: a list of `{ key, instanceID, name, englishName, minLevel, maxLevel, isRaid }`. `name` is in the player's language. The levels follow the dungeon finder once it has listed them, and Forever's own dungeons are included. |
| `GetInstanceInfo(instance)` | One of them, by instance ID or by name (in the player's language or English), or `nil`. |

## Gathering

| Function | Returns |
| --- | --- |
| `GetGatheringNode(name)` | A herb or vein by the name the world shows: `{ skillLine (182 Herbalism, 186 Mining), skill, itemID }`. A field is `nil` until it's known. |
| `GetItemGatheringSkill(item)` | The skill line and skill of the lowest herb or vein that gives an item. |
| `GetSkinningSkill(level)` | The Skinning skill needed for a creature of that level. |
| `GetWorldNodeInfo(name)` | Any node by the name the world shows: a herb or vein, a treasure chest, or a fishing pool, as `{ kind, skillLine, skill, itemID, lockpicking }`. `kind` is `"herb"`, `"ore"`, `"treasure"`, or `"fish"`; `lockpicking` is what a locked chest takes. A field is `nil` until it's known, and the whole is `nil` for a name that isn't a node. Learned in play, so Forever's own nodes fill in. |
| `GetFishingPoolByObject(objectID)` | The fishing pool a world object ID (from its GUID) was seen as, by name, or `nil`. |
| `GetProfessionSkill(skillLine)` | The player's skill in a profession: `{ rank, level, max, name }`. `rank` counts gear and racial bonuses, `level` is what the profession window shows, and `max` is the most its rank allows. Takes 633 for a rogue's Lockpicking. `nil` without the profession. |

## Talents

Forever keeps Classic's three talent trees inside the Mainline talent system, so the game has no "spec" to ask for.

| Function | Returns |
| --- | --- |
| `GetTalentTabs()` | The player's talent trees in order, as a list of `{ index, name, spent }`, and the `index` of the one with the most points (the first wins a tie). `nil` while the game has no talent data yet. |

These come from Gathering Map, and return `nil` while it's off:

| Function | Returns |
| --- | --- |
| `GetGatheringMaps()` | The zone map IDs (C_Map's `uiMapID`) with remembered nodes, lowest first. |
| `GetGatheringNodes(mapID)` | The nodes remembered on a zone map, for the whole account, whatever the character shows or hides: a list of `{ name, kind, x, y, timesGathered, lastGathered, loot }`. `kind` is `"herb"`, `"ore"`, `"treasure"`, or `"fish"`. `x` and `y` run from 0 to 1 across the map. `timesGathered` is 0 for a node seen or tried but not gathered yet, and `lastGathered` is a `time()`, or `nil` then. `loot` is what it has given in all, item ID → count. An empty list for a map without any. |

## Callbacks

```lua
FPP.RegisterCallback("PRICES_UPDATED", function(event)
    -- redraw your prices
end, myAddon)
FPP.UnregisterCallback("PRICES_UPDATED", myAddon)
```

`RegisterCallback(event, fn, owner)` calls `fn(event, ...)` each time the event happens. Each owner holds one function per event. Pass your addon's table as `owner`, or leave it out and the function is its own owner. An error in your callback goes to the error handler and doesn't stop the other callbacks. An unknown event name is reported the same way.

| Event | When |
| --- | --- |
| `READY` | Saved data has loaded. Fires once, after `PLAYER_LOGIN`. |
| `PRICES_UPDATED` | Auction prices changed: new prices were seen while browsing or scanning, they were reset, or their source changed (Auction Prices turned on or off, or the switch to or from Auctionator). Fires at most once a second. |
| `UPGRADES_UPDATED` | Upgrade scores changed: gear, level, talents, weights, Upgrade Arrows' options, or it turned on or off. Fires at most twice a second. |
| `MODULE_TOGGLED` | `name, enabled`: the player turned a module on or off. Modules turning on at login don't fire it. |
| `OPTION_CHANGED` | `name, key, value`: the player changed one of a module's options. |
| `WAYPOINT_CHANGED` | The map pin was set, moved, or cleared, by anyone. Forever++ only listens for this once something registers for it. |
| `GATHERING_NODES_UPDATED` | Gathering Map's remembered nodes changed: a gather, a forget, an import, or it turned on or off. Fires at most twice a second. |
| `GATHERED` | `gather`: the player gathered a herb, vein, chest, or fishing pool (only a real gather, not a failed or interrupted cast), or tried a herb or vein too high for their skill. `gather` is `{ name, kind, skillLine, mapID, x, y, objectID, items, requires }`: where they stood on the zone's map (for a pool, where the line landed), `items` as `{ id, count }` each, and `requires` the skill it takes when it was too high (then `items` is empty). Works whether or not Gathering Map is on. Forever++ only listens for this once something registers for it. |
| `FLIGHT_STARTED` | `fromNodeID, toNodeID`: a flight took off. While Flight Timer is on. |
| `FLIGHT_ENDED` | `fromNodeID, toNodeID, seconds`: it landed, and how long it took. |
| `PROFILE_CHANGED` | `name`: this character switched to another settings profile, or the one it uses was renamed or replaced by an import. Modules the switch turned on or off also fire `MODULE_TOGGLED`; options that changed with it don't fire `OPTION_CHANGED`, so read again what you need. |
