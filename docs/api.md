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
- **Read only.** You get copies and plain values, never Forever++'s own tables. Changing one has no effect. Assigning into `ForeverPlusPlusAPI` or `v1` raises an error. The one thing you can add is a module of your own (see Plugins); you can't change Forever++'s.
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
| `GetItemScore(item)` | The item's score by the weights in use, whether or not it could be an upgrade. Nil while Upgrade Arrows is off or the client hasn't loaded the item. |
| `GetUpgradeProfile()` | The weights in use: `{ key ("MAGE:3"), class, tab, bear, guess, weights }`. `weights` maps stats in short keys (`"STR"`, `"SP"`, `"HIT"`, as in [stat-weights.md](stat-weights.md)) to their weight. `guess` is true while there are no talent points to go by. |

Scores change when gear, level, talents, weights, or Upgrade Arrows' options change. `UPGRADES_UPDATED` says when.

## Flight times

These come from Flight Timer while it's on, except `GetFlightEstimate`, which always answers. Flight points are the game's node IDs (`nodeID` from `C_TaxiMap`). A route's time is known once the player has flown it. Each direction is its own route.

| Function | Returns |
| --- | --- |
| `GetFlightTime(fromNodeID, toNodeID)` | The flight's length in seconds, or `nil` if it hasn't been flown. |
| `GetFlightEstimate(fromNodeID, toNodeID)` | Estimated seconds of the direct flight between them, from the game's own flight paths, whether flown or not, or `nil` when no direct path joins them. It answers whether or not Flight Timer is on. Added in 1.6.0. |
| `GetCurrentFlight()` | The flight underway: `{ fromNodeID, toNodeID, duration, estimate, elapsed, remaining }` in seconds. `duration` and `remaining` are `nil` the first time a route is flown; `estimate` is then Flight Timer's estimate (`nil` when it has none, and once the route has been flown). `estimate` added in 1.6.0. `nil` when not flying. |
| `GetFlightTimes()` | Every flight timed, for the account: a list of `{ fromNodeID, toNodeID, seconds }`, sorted. |
| `GetKnownFlightPoints()` | The flight points this character has learned, as Forever++ has seen them at a flight master: a set of node IDs → `true`. Forever's own map list can't say which are learned. From World Map's Points of Interest, and `nil` while it's off. |

## Waypoints and maps

The waypoint is Blizzard's own map pin, the same one `/way` and a click on the map set. It shows on the map, as the marker in the world, and on Waypoints' arrow. Spots are 0 to 1 across and down a map, as `C_Map` gives them (not 0 to 100 as `/way` takes them).

| Function | Returns |
| --- | --- |
| `SetWaypoint(map, x, y, name)` | Puts the pin on `map`, which is a map ID, a zone name (as `FindZone` reads it), or `nil` for the player's map, and tracks it. Returns `true`, or `false` and why: `"zone"` (no such zone), `"range"` (x or y outside 0 to 1), `"map"` (no pin allowed there, like inside a dungeon), or `"unavailable"`. With `name` (optional, added in 1.6.0), the pin is called that under the Waypoint arrow and on the Compass Bar; the game's own pin has no name. |
| `GetWaypoint()` | The pin's map ID and x, y, or `nil` when there's none. Since 1.6.0 a fourth value is the pin's name, when it was set with one. |
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

These come from Gathering Map, and return `nil` while it's off:

| Function | Returns |
| --- | --- |
| `GetGatheringMaps()` | The zone map IDs (C_Map's `uiMapID`) with remembered nodes, lowest first. |
| `GetGatheringNodes(mapID)` | The nodes remembered on a zone map, for the whole account, whatever the character shows or hides: a list of `{ name, kind, x, y, timesGathered, lastGathered, loot }`. `kind` is `"herb"`, `"ore"`, `"treasure"`, or `"fish"`. `x` and `y` run from 0 to 1 across the map. `timesGathered` is 0 for a node seen or tried but not gathered yet, and `lastGathered` is a `time()`, or `nil` then. `loot` is what it has given in all, item ID → count. An empty list for a map without any. |

## Recipes and zones

| Function | Returns |
| --- | --- |
| `GetRecipeLevels(skillLineAbilityID)` | The skill a recipe turns yellow, green, and gray at, from the client's tables: `{ yellow, green, gray, skillLine }`. Takes the `skillLineAbilityID` of the recipe's info (`C_TradeSkillUI.GetRecipeInfo`). `nil` for a recipe the tables don't have, or while Professions is off. |
| `GetZoneInfo(mapID)` | What Zone Info knows of a zone: `{ minLevel, maxLevel, fishing, fishingCoast, herbs, ores, side }`. The levels are `nil` for a city. `fishing` is the Fishing skill its water needs, and `fishingCoast` its coast's when that needs more. `herbs` and `ores` are lists of item IDs. `side` is `"A"`, `"H"`, or `"C"` for contested. `nil` for a map that isn't a zone it knows, or while World Map's Zone Info is off. |

## Talents

Forever keeps Classic's three talent trees inside the Mainline talent system, so the game has no "spec" to ask for.

| Function | Returns |
| --- | --- |
| `GetTalentTabs()` | The player's talent trees in order, as a list of `{ index, name, spent }`, and the `index` of the one with the most points (the first wins a tie). `nil` while the game has no talent data yet. |

## Plugins

An addon can add a module of its own to Forever++. It shows on the Modules page with its options, follows profiles, and turns on and off like a built-in one. This is the one place the API takes something from you; it still never lets you change Forever++'s own modules.

**Experimental in 1.6.0.** Plugins are new, and `RegisterModule`, `GetPluginKit`, the handle, and the kit may still change in a later release, unlike the rest of `v1`. The changelog will say when they do, and when they're settled.

List `## Dependencies: ForeverPlusPlus` in your TOC, and register while your files load. After `PLAYER_LOGIN` it is too late: Forever++ reads every module's saved settings once, then.

```lua
local FPP = ForeverPlusPlusAPI.v1
local kit = FPP.GetPluginKit()
local module = FPP.RegisterModule("MyAddonThing", "What it does, in a sentence or two.",
    { size = 20, loud = true }, "MyAddon")
module.title = "My Thing"
module.category = "map"
module.options = {
    { key = "size", name = "Size", description = "How big it is.", min = 10, max = 40, step = 2 },
    { key = "loud", name = "Loud", description = "Whether it's loud." },
}
local timer = kit.Timer(module) -- made here, once, not in OnEnable
function module:OnEnable()
    self:On("PLAYER_LEVEL_UP", function(event, level)
        timer:Start(2, function() ... end)
    end)
end
function module:OnDisable() ... end
function module:OnOptionChanged(key) ... end
```

What you get is always a small table of your own, never one of Forever++'s: the handle, its `db`, a timer, a map layer, a set of item marks, an option. Each has only what is listed here and can't be changed. Three rules hold throughout:

- **A mistake of yours raises an error in your code**, naming it: a wrong type, a missing argument, a field that isn't listed. So a typo shows up at once.
- **Your functions are called guarded.** An error in one goes to the error handler and what called it carries on.
- **An error of Forever++'s returns `nil`**, as everywhere in `v1`.

A module that is off does nothing: its events, timers, tooltip lines, map layers, marks on items, and frames in Edit Mode stop when it turns off, and none can be started until it is on again.

| Function | Returns |
| --- | --- |
| `RegisterModule(name, description, defaults, addon)` | A handle on a new module, or `nil` (with the reason sent to the error handler) for a mistake: a name another module has, a name that isn't letters, digits, and underscores, defaults that aren't a table, or a call after `PLAYER_LOGIN`. Start `name` with your addon's name so no two plugins meet. `defaults` holds each setting and its default, under text keys: true or false, text, or a number; `enabled` is false unless you give it, so the player turns the module on. A default that is a table is data the module collects, saved apart from settings: plain values and tables of them (up to 8 deep), nothing else. Forever++ copies the defaults, so changing your table later has no effect. `addon` (optional) is your addon's folder name, shown on the module's page. |
| `GetPluginKit()` | A read-only table of helpers, below. |

**The handle** is not Forever++'s own module table. It takes only what is listed here, checks it as you set it, and raises an error for anything else, so a typo shows up at once.

| You set | What it is |
| --- | --- |
| `title`, `category`, `added` | Its name on the Modules page; its group there (`automation`, `character`, `chat`, `interface`, `items`, `map`, `quests`, `system`, `units`; anything else lands under Other); and the version of your addon it first shipped in, which marks it NEW. |
| `quickToggle` | Puts it in a group of the Minimap Button's quick toggles by default: `loot`, `npcs`, `world`, `nameplates`, `gathering`, or `other`. The player can add or remove any module there themselves. |
| `oldKeys`, `oldNames` | What you renamed, set before `PLAYER_LOGIN`, so the player keeps what they saved. `oldKeys` is `{ newKey = "oldKey" }` for a setting or data key of your defaults; `oldNames` lists the names this module had before. At login the saved values move to the new names in every profile, where the new one isn't set yet and the value is of the new default's type. An old module name is only taken from a plugin, never from one of Forever++'s modules or one that is loaded. Keep them for as long as players may update from the old version. |
| `options` | A list of options, set before `PLAYER_LOGIN`. Each has a `key` (one of your defaults, not `enabled`) and a `name`, and may have a `description`, a `section` (a header), `requires` (another option's key it's nested under), `shown` (`fn(db)`, whether its row shows), and `added`. It's a checkbox when its default is true or false, a dropdown with `choices` (`{ { value, name }, ... }`, the default one of them), or a slider with `min`, `max` (the default between them), and optionally `step` (above 0) and `format` (such as `"%d%%"`, taking the one number). `slider = key` on a checkbox puts that slider in its row. `editMode = true` moves it from the Modules page into the Edit Mode dialog of the frame you registered with the kit's `EditMode.Register`. Options can't be nested in a ring (`requires` leading back to itself). Other fields are ignored. The kit's `Options` make the ones every module has alike. |
| `actions` | Buttons after the options: `{ name, button, fn }`, optionally `description`, `section`, and `confirm` (a question asked first). |
| `notice` | Gray rows above the options, one or a list: `{ text }`, optionally `description` and `shown` (`fn()`). Forever++ adds one of its own saying the module comes from another addon. |
| `perCharacter` | `{ key = true }` for data (table defaults) kept for each character on its own, set before `PLAYER_LOGIN`. |
| `OnEnable`, `OnDisable`, `OnOptionChanged` | Called with the handle when the module turns on, turns off (undo what `OnEnable` did), and when one of its options changes (with the option's key). Every module turns on and off live, with no reload. |
| `IsAvailable`, `Problem` | `IsAvailable` returning false at login keeps the module off and out of the list. `Problem` returning true shows its name in red; say why in a notice. |

| You read or call | What it is |
| --- | --- |
| `name`, `enabled` | Its name, and whether it's on. |
| `db` | Its saved settings and data, from `PLAYER_LOGIN` on (`nil` before): `module.db.size`. Reading gives the default for what the player hasn't set; assigning saves, and assigning `nil` puts the default back. It holds only the keys of your `defaults`, each taking a value of its default's type (a number that isn't infinite); anything else raises an error. `db.enabled` can be read but not set: turning the module on and off is the player's. It follows the player's profile. |
| `module:On(event, fn)` | Calls `fn(event, ...)` for a game event while the module is on. Call it from `OnEnable`: it stops by itself when the module turns off, and while the module is off it listens to nothing. Returns true when it listens, false while the module is off or for an event this client doesn't have. |
| `module:OnUnit(event, units, fn)` | As `module:On`, for a unit event of one or two units (`{ "player" }`, `{ "player", "target" }`): the game then sends it for no other unit, which costs far less than hearing every unit's. `fn(event, unit, ...)`. |
| `module:OnItemInfo(fn)`, `module:OnItemPrices(fn)` | `fn(tooltip, data)` on every item tooltip while the module is on, where Forever++ puts its own lines: facts about the item just above the sell price, and prices with it. Add lines there with the kit's `ItemTooltip`, so yours sit with Forever++'s. Call it from `OnEnable`; asking again with the same `fn` changes nothing. |
| `module:Hook(target, method, fn)`, `module:HookScript(frame, script, fn)` | A `hooksecurefunc` or `HookScript` that is made once and does nothing while the module is off. `target` is a table, or left out for a global function's name (`module:Hook("Name", fn)`). A frame or function that isn't there is skipped. |
| `module:TooltipPostCall(kind, fn)` | `fn(tooltip, data)` after the game fills in a tooltip of one kind (`Enum.TooltipDataType.Item`), while the module is on. |
| `module:Print(message)` | A chat line, unless the player turned off an option of yours with the key `chat`. Nothing before `PLAYER_LOGIN`. |

**The kit.** `Timer`, `Coalesce`, `NewMapLayer`, and `NewItemMarks` each take your module and are called once, while your files load, with the result kept in a local: after `PLAYER_LOGIN` they raise an error. One made in `OnEnable` would be made again every time the module turned on.

| Helper | What it does |
| --- | --- |
| `AfterCombat(fn)` | Runs `fn` now, or once combat ends: for moving or showing protected frames. |
| `Timer(module)` | A timer that waits for one run at a time: `timer:Start(seconds, fn)` (in place of the run waiting), `timer:Cancel()`, `timer:IsPending()`. It's cancelled when the module turns off, and `Start` does nothing and returns false while the module is off. |
| `Coalesce(fn, delay, module)` | A function that runs `fn` once, `delay` seconds after the first call to it (the next frame when `delay` is left out), however often it's called before then: for events that come in bursts. A second function it returns drops a run that is waiting. Nothing is queued while the module is off. |
| `HasEvent(event)` | Whether this client has a game event, before listening for one a patch may add or drop. |
| `IsReadable(value)`, `IsText(value)`, `IsNumber(value)` | Whether a value isn't secret, and is a string or a number. Unit health, names, and auras can be secret in combat; check before comparing or joining them. |
| `NewMapLayer(fill, module, filter)` | A layer of icons on the world map, with `:Enable()` (true while it shows), `:Disable()`, and `:Refresh()`. Call `layer:Enable()` in `OnEnable`; the layer comes off the map by itself when the module turns off. `fill(mapID, add)` runs each time the map shows a map and calls `add(x, y, info)` for each icon; `add` works only while `fill` runs. The icon's fields are below. `filter` (optional) gives the layer a checkbox in the world map's filter menu, under the Forever++ title with Forever++'s own: `{ name, key, kinds }`, where `key` is one of your defaults that is true or false, and `kinds` (optional) is a list of `{ name, key }` for a submenu of checkboxes, each a true or false default too. The layer then shows only while `key` is on. Checking one there is the same as changing the option in Settings: it's saved, and you hear of it in `OnOptionChanged`. Call `layer:Enable()` again when `key` changes from Settings; it shows or hides the layer to match. Read your kinds' settings in `fill`. |
| `NewItemMarks(test, module, look)` | A mark of yours in the corner of item icons, in the bags, the bank, a merchant's window, the auction house's browse list, the loot window, and loot rolls, with `:Enable()` (true, or false while the module is off), `:Disable()`, and `:Refresh()`. `test(link, place)` says whether an item gets the mark: `link` is its item link and `place` is `bags`, `bank`, `merchant`, `auction`, or `loot`. `look` is `{ atlas }` or `{ texture }`, with an optional `color` (`{ r, g, b }`). Call `marks:Enable()` in `OnEnable`, and `marks:Refresh()` when what `test` answers has changed. The mark follows these settings where your defaults have them, and the kit's `Options` make their options: `size` (pixels on a bag icon; 14 without it), `corner` (`TOPLEFT` without it), `padding` (1 without it), and a true or false default named after a place, which turns the marks off there. You never get Blizzard's buttons or the mark's texture. |
| `ItemTooltip.AddInfo(tooltip, label, text, color, align)`, `ItemTooltip.AddPrice(tooltip, data, label, copper, align)`, `ItemTooltip.ItemID(data)` | Lines for a function given to `module:OnItemInfo` or `module:OnItemPrices`, written as Forever++ writes its own: a white `Label:` and a value. `AddInfo`'s `text` is text or a number, in `color` (`"white"` unless given: `"gray"`, `"white"`, `"gold"`, or `{ r, g, b }`). `AddPrice` shows `copper` for one item as coins, times the stack's size. `align` is `"right"` (the value at the tooltip's edge, the default) or `"inline"`. `ItemID` is the tooltip's item, or `nil`. |
| `EditMode.Register(module, frame, label, apply, onChange)`, `EditMode.Place(frame, x, y)`, `EditMode.IsActive()` | Puts a frame of your own in Blizzard's Edit Mode, selected, dragged, nudged, and sized like Blizzard's. Your defaults need `x` and `y` (its offset from the middle of the screen) and `scale` (a percent from 50 to 200). Forever++ saves where the player drags it to `db.x` and `db.y` and the dialog's Scale slider to `db.scale`, then calls `apply()`, where you place and size the frame from them (`EditMode.Place(frame, db.x, db.y)` keeps it on the screen). Options marked `editMode = true` show in the frame's dialog. `onChange(active)` (optional) is called as Edit Mode opens and closes, to show a sample. Call `Register` in `OnEnable`, once the frame is made: it returns false while the module is off, and the frame leaves Edit Mode by itself when the module turns off. Not for a protected frame or one of Blizzard's. |
| `Options.Sound(key, description, requires)`, `PlaySound(sound)` | A Sound dropdown named and filled as Forever++'s are, for a default such as `"raidwarning"`; with `requires` (a checkbox option's key that turns the sound on), it has no Off. `PlaySound(db.sound)` plays what was picked, on the Master channel. |
| `Options.Key(key, name, description)`, `IsKeyDown(key)` | A dropdown of Shift, Ctrl, Alt, and None, for a default such as `"shift"`, and whether the key picked is held (`IsKeyDown(db.skipKey)`; never for None). |
| `Options.Chat(description)` | The Chat Messages checkbox `module:Print` follows. Its key is `chat`, so give your defaults `chat = true`. |
| `Options.MarkCorner(description)`, `Options.MarkSize(name, description)`, `Options.MarkPadding()`, `Options.MarkPlace(place, description)` | The options a mark on items has: its corner (key `corner`, default such as `"TOPLEFT"`), its size in pixels (key `size`, 8 to 32), its padding (key `padding`, 0 to 10), and a checkbox for a place (key `bags`, `bank`, `merchant`, `auction`, or `loot`). `NewItemMarks` follows them. |
| `Options.MapIconSize(key)`, `Options.MapIconOpacity(key)`, `Options.MapOnContinents(key)` | The options a layer of map icons has: a size from 50 to 200 percent, an opacity from 10 to 100 percent, and whether the icons show on continent maps. They only make the option; use the setting in your `fill`. |
| `Tooltip.Note(text)`, `Tooltip.Detail(text)`, `Tooltip.Pair(label, value)` | Lines for an icon's `lines`: gray, white, and a label with its value at the right edge. A plain string is a gold line. |
| `SetWaypoint(mapID, x, y, name)`, `IsContinent(mapInfo, cosmic)` | Blizzard's map pin on a map ID, with an optional name, answering as `v1.SetWaypoint` does (true, or false and why); and whether a `C_Map.GetMapInfo` result is a continent or the world. |
| `QuestieDB` | The QuestieDB addon's quest, NPC, item, and object data in Forever++'s shapes, read only: `Status`, `IsAvailable`, `IsReady`, `OnReady`, `Cancel`, `Ids`, `IdsByName`, `Quest`, `Npc`, `Item`, `Object`, and `UiMapID`. [questiedb.md](questiedb.md) has each one's shape. Nothing is there unless the player has QuestieDB installed. `OnReady(fn)` isn't tied to your module: `Cancel(fn)` it in `OnDisable`. |

**An icon** is `add(x, y, info)`: `x` and `y` from 0 to 1 across the map, and `info` a table Forever++ reads these from and copies. A field of the wrong type raises an error in your `fill`; other fields are ignored, so `info` can carry your own.

| Field | What it is |
| --- | --- |
| `atlas`, or `texture` | Its art: an atlas name, or a texture's path or file ID. One of them is needed. |
| `size` | In pixels on screen, kept between 4 and 128. Needed. |
| `title`, `kind` | The tooltip's first line, and optionally what the icon is, in gold at the right edge. `title` is needed. |
| `lines` | The tooltip's other lines: a list, or `fn(info)` giving one, called with your `info` as the tooltip shows. Each is a string or a `Tooltip` line; anything else is left out. |
| `color`, `alpha`, `desaturated`, `round` | A tint (`{ r, g, b }`), see-through (0 to 1), gray, and drawn round. |
| `waypoint`, or `ctrlClick` | `waypoint = true`: Ctrl+click puts the game's map pin on the icon's spot, as the game's own Ctrl+click does. `ctrlClick` is `fn(pin)` in its place. |
| `shiftClick`, `shiftHint` | `fn(pin, button)` for a click with Shift held, and the words for what it does. |
| `click`, `clickHint` | `fn(pin, button)` for a plain left click, and the words for it. Without it, icons let plain clicks through to the map. |

A click's `pin` is a table of `x`, `y`, `mapID`, and `info` (your own table, as you gave it), not the icon's frame. While Shift is held, an icon's tooltip ends with what clicks do on it; Forever++ writes those lines from the hints.

A plugin's settings are saved with Forever++'s. They are kept when your addon is turned off or missing for a while; settings and options you drop from `defaults` are cleared. The player-facing text is yours: the handle takes plain strings, in whatever language you choose.

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
