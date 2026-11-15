# Architecture

The detail behind `AGENTS.md`'s project map: what each part of the addon holds, function by function. `AGENTS.md` has the short version and the rules; this is the reference to search when you need to know what a file offers. Keep it up to date when a Lib file gains or loses something another module could use.

## Core.lua

- The shared `ns`:
- Events (`ns.On`, `ns.Off`, `ns.OnUnit` and `module:OnUnit` for a UNIT_* event of one or two units, and `ns.HasEvent` before an event a patch may add or drop, and `module:OnWhile(when, events)` for events heard only while an option is on).
- `ns.AfterCombat`.
- Saved settings (laid out by `Lib/Store.lua`).
- Modules (`ns.NewModule`, `ns.SetEnabled`, and `module:NewPart` for a module made of parts the player turns on one by one, by a checkbox or, with `choices`, a dropdown whose "off" turns it off; `ns.PartOn` says whether one is on).
- Timers that stop when their module (or part) turns off (`ns.Frames.Timer(module)` and `ns.Frames.Coalesce(fn, delay, module)`: Core cancels them after `OnDisable`, and they don't run while it's off).
- Hooks that do nothing while a module is off (`module:Hook`, `module:HookScript`, `module:TooltipPostCall`, and `module:TooltipLinePreCall`, whose true leaves a tooltip line out; they skip a target this client doesn't have).
- `module:OnLoad()`, called once at `PLAYER_LOGIN` when its `db` is there, before it turns on.
- Migrations of saved settings (`ns.Migrate`, `ns.MigrateCharacter` for data kept per character, `ns.MoveSettings`).
- `ns.Print`.
- `module:Print` with `ns.ChatOption`.
- `ns.SetOption`, `ns.ResetOption` (back to the default, forgetting the choice), and `ns.BaseValue` (what a reset gives, through the profile's preset).
- `ns.ChangeProfile` (switching the profile in use live, turning the modules off and on again).
- `ns.OnModuleChanged` (the player turned a module on or off or changed an option, for the public API's callbacks).
- The locale table `ns.L`.

## Commands.lua

- Loaded right after `Core.lua`, since modules add to it as they load: `/fpp` (modules add subcommands with `ns.AddCommand`), `/fpp set` and `toggle` on any module's options, and the Defaults popup's resets of the profile in use only: `ns.ApplyPreset(enable, options)` (the plain defaults with those on top, based on no preset) and `ns.UsePreset(name)` (based on a preset from `Lib/Presets.lua`, which it then follows).

## Data

Game data kept by hand, loaded after the locales and before `Lib/`: plain tables on `ns.Data` and nothing else, each with a comment saying where it came from. The Lib file or module that uses a table makes the `ns.GameData` set from it, so play still teaches over it and Self Test still checks its IDs. A patch's change is an edit here.

- `Instances.lua`: `instances` (each dungeon and raid: instance ID, English name, lowest and highest level, raid flag, by a short key; `Lib/Instances.lua`) and `dungeonArt` (the old map textures of each, by the same key, with Dire Maul's and Scarlet Monastery's wings; `Lib/DungeonMaps.lua`).
- `Professions.lua`: `professionNodes` (herbs and veins: skill line, skill, item), `miningStones`, `sharedSpawns`, `treasureNodes` (chests), `fishingPools`, `fishingBobbers`, `professionTools` (`Lib/Professions.lua`, `Lib/Gathering.lua`), and `skeletonKeys` (Gathering Skill Tooltips).
- `Spells.lua`: `spells`, the spell IDs more than one file uses, read with `ns.Data.Spell("FISHING")`, which registers the ID for Self Test.
- `Items.lua`: `autoOpenKept` (Auto Open Containers).
- `Buffs.lua`: `smartBuffs` (each class's buffs), `smartBuffStronger`, `smartBuffLevels` (Macros' Smart Buff).

World Map's two big lists are still in their module: `PointsOfInterest/Data.lua` and `ZoneInfo/Data.lua`.

## Lib

Shared services any module can use, loaded before the modules. They cost nothing until a module uses them.

Generated files, in `Lib/Generated/` (never edited by hand; see Generated data): `InstanceLevels.lua`, `DisenchantBrackets.lua`, `LockboxSkills.lua`, `ComprehendScrolls.lua`, `WeaponBuffs.lua`, `TaxiRoutes.lua`.

### `Store.lua`

- `ns.Store`: the saved variables' layout and version, the steps that bring an older one up to date, and the `module.db` each module reads, through the profile in use: Default is the account's own `settings` and `data`, where they always were, and every other profile is a root of its own in `db.profiles[id]` with the same two tables (`Root`, `Roots` for all of them), and a root's `preset` the preset it's based on, which a setting the player hasn't set reads before its default (`Preset`, `SetPreset`, and `Base`, what a reset gives; a name this version lacks reads as none and stays saved).
- Which one a character uses is `ForeverPlusPlusCharDB.profile`, and the account keeps `newCharacters` and `characters`, every character seen with its profile.

### `Presets.lua`

- `ns.Presets`: named presets on top of the defaults, registered here (only Developer's Defaults, `developer`, so far) with `Register(name, { title, description, extends })`, a parent registered first so no chain loops, and each module's part declared in its own `module.presets`.
- `Value` and `Enabled` say what one says for a module's setting along its `extends` chain, nearest first (nil for nothing, a locked, always-on, or unavailable module, data, and `cvar` options), `Resolve` and `Flat` give all of it (`Flat` as `ns.ApplyPreset` takes it), `List`, `Title`, `Exists`, and `Buttons` the popup buttons, a menu once there are more than fit.

### `Profiles.lua`

- `ns.Profiles`: the profiles, made from the defaults, as a copy, or based on a preset (`CreateFromPreset`, which writes nothing into its settings), based on another or none later (`Preset`, `SetPreset`: unlinking writes what the preset gave in as the player's own first), renamed, deleted (its characters back to Default), the characters on each and setting another's for its next login, New Characters Use, and switching live with Core's `ns.ChangeProfile`, waiting out combat.
- `/fpp profiles`.

### `ProfileShare.lua`

- `ns.ProfileShare`: a profile as one line of text, compressed with `C_EncodingUtil` or plain, and pasted text checked against the modules' declared settings before it's imported.
- A profile based on a preset exports the link and the values it gives, and imports based on it, without the values it still gives, only where this version has that preset.

### `Profiler.lua`

- `ns.Profiler`: while the Profiler page records, times calls into each module's code and charges them to it.
- Core's events and hooks, Nameplates' and ItemTooltip's callbacks, and timers go through it with what ran (`CallFrom`, so a module's time splits by source), a module wraps its own OnUpdate with `Profiler.Wrap` (inside its throttle, so only real runs count), and the worst frames are kept as spikes.

### `Colors.lua`

- `ns.Colors`: colors modules share, `Colors.Code` for color codes in text, `Colors.Class` for a unit's class color, `Colors.LevelRange` for a level range against the player's, and `Colors.Faction` for Horde red and Alliance blue, and `Colors.STATS`, a color for each stat.

### `Secret.lua`

- `ns.IsReadable`, `ns.IsText` for a readable string, `ns.IsNumber` for a readable number, `ns.IsTrue` and `ns.IsTrueOrSecret` for a flag that may be secret, `ns.AurasReadable` before reading an aura, `ns.EachAura` to walk a unit's auras after it, `ns.HealthStepCurve`.

### `Money.lua`

- `ns.Money`: copper as coin text, and `ns.MoneyShort` rounded to whole gold for a narrow column.

### `Fonts.lua`

- `ns.Fonts`: the game's fonts a font dropdown offers, and whether this client's language can use them.

### `Keys.lua`

- `ns.Keys`: the Skip Key dropdown and whether its key is held.

### `Sounds.lua`

- `ns.Sounds`: Blizzard's alert sounds every Sound dropdown offers (`CHOICES`, or `Sounds()` without Off), the dropdown a module's Sound option is (`Option(key, description, extra)`, named Sound unless `extra.name` says otherwise, without Off under a `requires` checkbox), and `Play` for the one picked. A module never calls `PlaySound` for an alert the player can pick.

### `Confirm.lua`

- `ns.Confirm`: a yes/no popup before something throws data away, `ns.ConfirmChoice` and `ns.ConfirmButtons` for two or three choices beside Cancel, and `ns.Prompt`: a popup that asks for a line of text or shows one to copy, `ns.PromptName` for a name.

### `Text.lua`

- `ns.Text`: numbers with thousands separators (`Number`), font string width, tooltip lines, "3 Seconds" and "12m ago", "120 yds" (`Yards`), which of two versions is newer, text without its escape codes, the client's format strings as patterns, and a bar's text as the game's Status Text setting writes it (`StatusText`).

### `GameData.lua`

- `ns.GameData`: game data a patch can change, as sets of a seed the addon ships plus what play taught it, saved for the account.
- Single item, spell, and map IDs Self Test checks.
- Blizzard's "Requires Herbalism (75)" line read in any language.

### `Menus.lua`

- `ns.Menus`: every context menu we open goes through `Open(owner, generator, anchor)`. `generator(owner, root)` describes it as Blizzard's menus are described (`CreateTitle`, `CreateDivider`, `CreateButton`, `CreateCheckbox`, `CreateRadio`, a button's own entries as its submenu, `SetTooltip`, `SetEnabled`).
- With the controller interface off it's `MenuUtil.CreateContextMenu`. With it on (`GamepadUI`) it's a plain list of our own frames, since Blizzard's menu opened from addon code taints the controller's focus manager for the session (`docs/forever-api.md`). Ours takes the mouse, and the controller's D-pad, A, and B while it's open.
- `SetupDropdown(dropdown, generator)` takes the place of a Blizzard dropdown button's `SetupMenu`: the button, its text, and the wheel stay Blizzard's, and only what drops down is ours with the controller interface on (`OpenMenu` replaced on our own frame).
- `Describe` gives the description as plain entries, with `IsEnabled` and `IsSelected` for one. Blizzard's own menus we add entries to (the world map's filter menu) are still Blizzard's, opened by Blizzard.
- `Lib/Confirm.lua` does the same for popups: Blizzard's `StaticPopup`, or one frame of our own with the controller interface on.

### `Frames.lua`

- `ns.Frames`: whether this client has an atlas or template, the box tooltips are drawn in, Blizzard's panel button (`Button`), saving and restoring a frame's anchors (`GetPoints`, `SetPoints`), our windows with a portrait (`PortraitWindow`, which also makes one draggable, kept on screen, closed by Escape, back where the player left it from the `layout` table its module gives, and resizable with `resize`; with `Inset` and `RowTexture` for their lists), Escape closing our windows, whether the player is in combat or moving (`PlayerActivity`), red error-frame text, running something once after a burst of calls (`Coalesce`), a timer that waits for one run at a time (`Timer`), and OnUpdate a few times a second (`Throttled`, `Watcher`).

### `AddOns.lua`

- `ns.AddOns`: wait for a load-on-demand addon.

### `Errors.lua`

- `ns.Errors`: Error Catcher's counts and window, for the minimap button.

### `CVars.lua`

- `ns.CVars`: set CVars and put the player's values back, waiting out combat, `Bind` for options that mirror a CVar, `Hold` to keep one at a value, and `Same` for two values the game counts as equal.

### `Nameplates.lua`

- `ns.Nameplates`: plate added/removed/cast callbacks and Forever's plate parts.

### `PlateLabel.lua` and `FriendlyPlates.lua`

- `ns.PlateLabel`, `ns.FriendlyPlates`: the name-only friendly plates Player Nameplates and NPC Nameplates share.

### `Units.lua`

- `ns.Units`: in my group, a friend, a recent ally, a guildmate. `NpcID(guid)` is a creature's NPC ID out of its GUID.
- The player's own state, for a module that acts by itself (casts, sheathes, opens): `PlayerBusy` gives why now is a bad time ("combat", "dead", "taxi", "casting") or nil, and `PlayerCasting` whether a cast or channel is under way. An answer the game hides counts as busy, so a module waits instead of interrupting. Every module asks here, never the unit calls directly, so they all guard alike.

### `Bags.lua`

- `ns.Bags`: what's in the player's bags.
- `Each(fn, reagent)` calls `fn(bag, slot, info)` for every slot of the backpack and the four bags (the reagent bag too with `reagent`), `info` nil for an empty slot. It stops at the first `fn` that returns something and returns that.
- `FreeSlots()` counts the free slots of the bags that take anything (not a quiver's or the reagent bag's).
- `LAST` and `REAGENT` are the bag indices, the one place they're written down.
- The buttons Blizzard draws for bags are `ItemButtons`'.

### `Players.lua`

- `ns.Players`: the class, level, race, and guild of players seen in the group, guild roster, friends, who results, units, nameplates, and chat, saved for the account in a variable of its own (`ForeverPlusPlusPlayersDB`, as `ns.playersDB`) by realm name while a module uses it (`Use`, `Release`), read with `Get(guid, name)`.

### `ItemTooltip.lua`

- `ns.ItemTooltip`: price lines together at the sell price (`OnPrices`, `AddPrice`), notes about them after every price line (`OnPriceNotes`), other item lines just above them (`OnInfo`, `AddInfo`), stack counts, Shift redraws, drawing one of Blizzard's lines again with something beside it, and `ColorText` in the quantity colors.

### `ItemButtons.lua`

- `Walk(module, mark, opts)`: one walk over bags, bank, merchant, auction house, loot, and loot rolls for a module that marks items. `mark(icon, link, place, a, b)` is all the module writes: the walk hooks each window (`walk:Hook`), reads each slot's link, clears a place whose Show On checkbox (`module.db[place]`) is off, and marks again on `walk:Refresh`. Already Known, Appearance Icons, Unusable Items Tint, Upgrade Arrows, and a plugin's marks (`Lib/Plugins.lua`) all use it; a module's own places (mail, quest rewards, recipe rows) and its item-data events stay in the module.
- `ns.ItemButtons`: the item buttons in bags, at a merchant, in the auction house's browse list, the loot window, and loot rolls, the bank's shown tab (`EachBankButton`, `HookBank`), quest reward choices (`EachRewardChoice`, `RewardIcon`), hooks that redraw with them (`HookLoot` listens for LOOT_OPENED itself), and our own textures over their icons (`Overlays`, `Tint`, and `PlaceMark` to size and place one from the module's Size, Corner, and Padding), with the options every mark on an item or action button icon shares, built by `CornerOption`, `SizeOption`, `PaddingOption`, and `PlaceOption` (style, then Corner, a size in px, step 2, up to 32, then Padding 0 to 10, 1 by default; then a Show On section of places, bags, bank, merchant, auction, loot, then the module's own), and `PlaceInCorner` and `MarkSize` to put the mark there at its size, in proportion to the icon it's on (the size option is a bag icon's).

### `BagClicks.lua`

- `ns.BagClicks`: secure overlays on items in Blizzard's bags whose right-click uses an item or casts a spell on it, out of combat.

### `Prices.lua`

- `ns.Prices`: what a vendor pays for an item (`Vendor`: 0 for no sell price, nil while the item isn't loaded; a module never reads the eleventh value of the item's info itself), and auction prices and items by name, from Item Tooltips' Auction Prices while it's on, for other modules, with `AgeColor` for a price's age in the player's Scan Age Color.

### `Providers.lua`

- `ns.Providers`: what a module offers outside itself while it's on, by name, set in `OnEnable` and cleared in `OnDisable`, for `API.lua` to read without reaching into the module, with `Changed` and `OnChanged` for when it changes.

### `Disenchant.lua`

- `ns.Disenchant`: which items can be disenchanted (the game's brackets, from the generated `DisenchantBrackets.lua`), what each gives (learned in play where not known) with its chance and amount, and their average value at given prices.

### `Professions.lua`

- `ns.Professions`: `WatchWindow(module, hook, catchUp)` keeps a module's hooks on the professions window as it loads, opens, and lists its recipes, so no module listens for those events itself; the player's profession skills by skill line (and a rogue's Lockpicking), with a profession's skill and its rank's most as its window shows them (`Progress`), gathering difficulty colors, herbs and veins by name with the skill and item they give, chests by name with a locked one's Lockpicking (`Chest`, `LearnChest`), fishing pools by name and world object (`Pool`, `PoolByObject`, `LearnPool`), the kinds of node maps sort by (`KINDS`: herb, ore, treasure, fish; `Kind`, `LineKind`), veins that spawn in each other's spots (`SharesSpawn`: Silver in Tin's), the gathering skill an item comes from (`ItemSkill`), and the Skinning a creature's level needs, a recipe's yellow, green, and gray levels from its yellow and gray (`RecipeLevels`), the color they give at a skill (`LevelDifficulty`, in `DIFFICULTY`'s numbers), and their bar (`LevelBar`), and the professions window's recipe form (`RecipeForm`) and recipe rows: `EachRecipeRow`, `HookRecipeRows`, the recipe a row is about at its best known rank (`RowRecipe`, `BestRank`), and `NewRowColumn` for a column of a module's own at the rows' right end, taking space only while it's in use, with the recipe's name cut short before the columns.

### `WorldMap.lua`

- `ns.WorldMap`: the world map once its addon has loaded, map data providers, walking up the map tree (`Up`, `Root`), a map's name, a map's size in yards (`Size`), a zone by name (`FindMap`), showing another map in it out of combat (`Show`), Blizzard's map pin (`SetWaypoint`, `CanWaypoint`) and the name it was set with, since the game's pin has no label (`WaypointNote`: the icon Ctrl+clicked or the note after `/way`, while the pin stays at that spot), where the player stands, where a quest and the corpse are (`QuestPoint`, `CorpsePoint`), and how far and which way a spot is from the player, also in the next zone (`FromPlayer`), Blizzard's coordinates panel on it and the CVars behind it (`COORDS_CVARS`), and the player's side for map data.
- The filter menu (the funnel at the map's top right): `AddFilter(order, shown, build)` puts a module's entries under the one Forever++ title, after Blizzard's own, in `order` (World Map 1, Quest Pins 2, Gathering Map 3). `shown()` is asked each time the menu opens, since Blizzard's menus can't take an addition back. `FilterLayer(root, name, get, set, kinds)` is the entry for a layer of icons: a checkbox for the layer, with a checkbox per kind in a submenu that stays open while kinds are switched; a kind with `disabled` text is greyed out with that as its tooltip.

### `MapTooltip.lua`

- `ns.MapTooltip`: how every tooltip over the world map looks: white title (with its kind in gold at the right, when given), gold kind line, white details, label and value lines like the Sell Price line (`Pair`), gray notes, faction colors, no-break text, and click hints (`Hint`).

### `Instances.lua`

- `ns.Instances`: the kind of instance the player is in (`Here`: "party", "raid", "pvp", "arena", or nil in the world or while the game won't say; modules ask it instead of `IsInInstance`), and the dungeons and raids with their levels (the lowest from the generated `InstanceLevels.lua` unless kept by hand), a row for each as maps list them, and their names in the player's language.

### `MapPins.lua`

- `ns.MapPins`: layers of our own icons on the world map, through a map data provider, their art (`SetArt`: an atlas or item icon, round, tinted, ringed, or a hollow ring), and what a click on an icon does, set on its `info` (`waypoint = true` or `ctrlClick` for Ctrl+click, the game's own gesture for the map pin; `shiftClick` with Shift held; `click` for a plain left click the icon takes itself); an icon takes a click only when it has something for it, so plain clicks still reach the map; and the click hints at the bottom of an icon's tooltip, written here for every layer and shown only while Shift is held (the Ctrl+click line, and a module's `clickHint` and `shiftHint` for its own actions).
- The options every module with icons on the world map shares, each `(key, section, extra)` with `extra` adding or replacing fields as `ItemButtons`' builders do: `SizeOption` (50 to 200 percent, step 10), `OpacityOption` (10 to 100 percent, step 5), and `ContinentOption` (the On Continent Maps checkbox). The module keeps its own key and default.

### `DungeonMaps.lua`

- `ns.DungeonMaps`: an instance's map, since the client has none to open: whether one can be shown (`Has`, `Can`) and showing it (`Open`). An instance the client still has the old map art for (its texture names by instance ID, checked against the client once each) is drawn in a view of our own over the open world map, with Previous and Next for its floors and a right click to go back; Dire Maul and Scarlet Monastery are listed by wing (`Wings`). One without goes to the DungeonJournal addon when it's there, through what it leaves in reach, read when called and every call protected, never in combat.

### `Gathering.lua`

- `ns.Gathering`: the herbs, veins, chests, and fishing pools the player gathers as they gather them (and a herb or vein their skill is too low for, from the game's error), with where they stood and the loot, told to modules that `Listen`, and the item each herb and vein gives taught to `ns.Professions`.
- A map's remembered nodes, a gather within `RADIUS` yards of the same node counted again with its spot averaged (`Add`, `Nearest`, and `See` for one seen but not gathered), and nodes as a line of text to share and back (`Encode`, `Decode`, `Merge`).

### `MinimapPins.lua`

- `ns.MinimapPins`: the entries of the minimap's tracking menu (`EachTracking`), and what the minimap shows right now (`View`: the player's zone map and spot, its view radius, and its rotation) and turning zone-map spots into minimap spots and back (`ToMinimap`, `FromMinimap`), for our own icons on it, the names of the dots under the player's own mouse and where the mouse is (`MouseoverNames`, `CursorOffset`), and the minimap's gold ring around an icon (`NewRing`, `PlaceRing`), which world map pins use too, and its shape: whether an addon made it square (`Square`, from `GetMinimapShape`), and word when that changes (`ShapeChanged`, `OnShapeChanged`) to our buttons on its edge and LibDBIcon's.

### `EditMode.lua`

- `ns.EditMode`: our own frames in Blizzard's Edit Mode, looking and working like Blizzard's: a selection box that turns gold when clicked, dragging with snapping, arrow-key nudging, and a settings dialog and right-click menu with scale, the frame's own settings (dropdowns, sliders, checkboxes), and reset position, and `RegisterModule` for a frame placed from its module's x, y, and scale settings, whose options marked `editMode = true` are those settings.

### `Chat.lua`

- `ns.Chat`: the chat windows as they come and go (`EachWindow`), each line a window adds that can be read (`OnMessage`, which a module uses instead of hooking `AddMessage` itself), rewriting the lines they show (`Transform`), a chat line in its colors for an edit box, filters that hide chat lines (`AddFilter`), and the column of buttons beside the chat window, with `NewButton` in Blizzard's art, those that don't fit a short chat window listed in its speech bubble's menu instead, and `SetBadge` for what one has waiting, which the speech bubble shows while it's there.
- `QuietRefusals` keeps the yellow "Interface action failed because of an AddOn" line out of chat when it's the controller navigation refusing addon code with nothing lost (`HarmlessRefusal`, which Error Catcher skips by too); Settings calls it before it opens a page.

### `TalentPlan.lua`

- `ns.TalentPlan`: an ordered talent plan checked against Classic tree rules, the points each row needs (`RowGates`), talent points by level, plans as share strings, and build links from talentsforever.com and wowforevertalents.com read into a plan (`ParseLink`, `FromLink`), only when the game's tabs have the shape the link's numbering was written against.

### `Slash.lua`

- `ns.Slash`: slash commands a module adds and takes away live, left to another addon that already has the same one. `List` gives the ones added with help (usage, description, owner), which `ns.Commands` adds to `/fpp help` and the About page.

### `SettingsKit.lua`

- `ns.SettingsKit`: what a drawn Settings page is made of, for the Settings pages and a tool's `BuildPage`: the module categories in the Modules page's order (`CATEGORIES`, `CategoryOf`), the page title, checkboxes, buttons, undo arrows (`NewResetButton`), tooltips, stacks, a split list and pane, and the search box.

### `ItemStats.lua`

- `ns.ItemStats`: an item's stats in short keys from the game's stat table, with its slot and levels, a stat weight score, and which stat a tooltip line is about (`LineStat`).

### `Equipment.lua`

- `ns.Equipment`: the slots an item type goes in, what's worn, whether the character can use an item, the weapon type worn in a slot (`WeaponSubclass`), and the worn items an item would replace, from the client's own item comparison or the slot rules.

### `Durability.lua`

- `ns.Durability`: how whole each equipped item is (`Fraction`) and the most worn one (`Lowest`), and the warning level that makes and when a change of it should warn (`Level`, `ShouldWarn`).

### `Talents.lua`

- `ns.Talents`: the talent tabs with the points in each, and the dominant one.

### `ActionButtons.lua`

- `ns.ActionButtons`: Blizzard's action buttons, what each slot holds, and our own marks over them.

### `Spellbook.lua`

- `ns.Spellbook`: the spells the player knows by name, with every rank and its subtext, whether one is known (`IsKnown`), and the level a spell is learned at.

### `Quests.lua`

- `ns.Quests`: the quest the map and arrow follow (`Selected`), which quest Blizzard's quest windows show (`DetailsID`, `GiverID`, and `GreetingButton` with its level) and a quest's level from the quest log.
- What every module writes for a quest: `DifficultyLevel(questID, fallback)` (the game's, then the log's, then the fallback, such as QuestieDB's), `Title(questID, fallback)`, `IsElite`, and `LevelTag(questID, level)`, "[12]" or "[12+]" for a group quest. One source, so two modules can't tag the same quest differently.

### `QuestieDB.lua`

- `ns.QuestieDB`: the one place we read the separate QuestieDB addon's quest, NPC, item, and object data, at run time through its `LibQuestieDB` API and never copied into this repo (`docs/questiedb.md`): whether it's there and fits (`Status`, `IsReady`, `Problem`, `OnReady`), records as our own copies with spawns 0-1 on a uiMapID (`Quest`, `Npc`, `Item`, `Object`, `Ids`, `IdsByName`, `UiMapID`, `DropRates`, and `QuestDrops` for the creatures that drop a quest's items), every call protected, and `Notices` for a module that needs it, with `Require` to lock one off while it's missing.

### `Plugins.lua`

- `ns.Plugins`: modules another addon adds through the public API: `Register` makes one and returns a handle that takes only the fields `docs/api.md` names, checked and copied as they're set, never our module table, so how our modules are written can keep changing.
- `Kit` the read-only helpers a plugin gets. A plugin's `db`, timer (`kit.Timer`), and map layer (`kit.NewMapLayer`) are small read-only tables of its own over Store's view, `Frames.Timer`, and `MapPins.New`, never those objects; a timer, a coalesced function, and a layer are made once, before `PLAYER_LOGIN`, for a module, and do nothing while it's off.
- Three rules for everything a plugin hands over or calls: its arguments are checked where they're given (a mistake raises an error in its code), its functions are called guarded (`ns.Call`), and our work behind a call runs protected, returning nil on an error of ours. An icon a plugin adds to a layer reaches `MapPins` as a checked copy with only the fields `docs/api.md` lists.
- What a plugin shares with our modules, each a thin checked layer over the Lib file ours use: unit events (`handle:OnUnit`), item tooltip lines at the sell price (`handle:OnItemInfo`, `OnItemPrices`, `kit.ItemTooltip`), a map layer's checkbox in the map's filter menu (`NewMapLayer`'s `filter`, after ours at `FILTER_ORDER`), marks on item icons (`kit.NewItemMarks` over `ItemButtons`, placed by the module's `size`, `corner`, and `padding`), a frame in Edit Mode (`kit.EditMode.Register` over `EditMode.RegisterModule`), and the options every module fills alike (`kit.Options`, copies of what `Sounds.Option`, `Keys.Option`, `ns.ChatOption`, `ItemButtons`, and `MapPins` build). A plugin's module turning off takes its layers, marks, and Edit Mode boxes down.
- `Migrate`, which at login moves what the player saved under a plugin module's old name (`oldNames`) and old setting names (`oldKeys`), in every profile, before `Store.Prune`. It needs no layout version: a move leaves nothing to move again. An old name is only taken from a plugin, never a module that's loaded.
- `Remember`, which keeps the settings of a plugin whose addon isn't loaded this session from being cleared.

### `Taxi.lua`

- `ns.Taxi`: the open flight master's flight points, read once per frame for every module that asks, and a flight's estimated seconds (`FlightEstimate`) from the generated `TaxiRoutes.lua` at `SPEED`.

### `RealmTime.lua`

- `ns.RealmTime`: how far the player's clock is from the realm's, in quarter hours (`Offset`), and a realm time moved to the player's clock, with the days it moved (`Clock` for an hour and minute, `Date` for a CalendarTime), and `IsToday`.

## Modules

- One change each (see "Add a module" in `README.md`), in a folder for its category: `Automation`, `Character`, `Chat`, `Interface`, `Items`, `Map`, `Quests`, `System`, `Units`, and `Tools`.
- A small module is one file.
- A bigger one gets a folder of files that share `module.internal`.

What each module is, in the code's terms (what it does for players is in `README.md`):

- **Player Nameplates**
- **NPC Nameplates**
- **Quest Nameplates**
- **Druid Mana Bar**: druids only: mana in the player frame's third-bar slot while in a form without it.
- **Target Markers**: a ring of raid icons at the cursor while a key from `Bindings.xml` is held, picking by direction like the ping wheel, a world marker with Shift; secure, so it works in combat.
- **Simplified Dungeon Nameplates**: `DungeonNameplates`: the game's Simplified nameplates CVar on for the kinds picked only inside dungeons and raids, the player's own value back outside.
- **Console Variables**: a folder: the tool page, its Popular list of CVars, and its locks, which keep a CVar at the player's value at login and whenever it changes while the module is on, off by default.
- **Debug**: every module's debug options and buttons on its own page in the sidebar while it's on, drawn by `Settings/Debug.lua`, off by default; off, its page and tools' commands are gone and debug options go back to their defaults.
- **Self Test**: a Debug button, no toggle.
- **Gear Probe**: a Debug button and `/fpp gearprobe`, no toggle: what the client says about gear, item comparison, talent tabs, and stats, saved for the upgrade arrows work.
- **Screenshots**: a Debug button and `/fpp shots`, no toggle: gallery screenshots of real windows; a module adds its own scene with `module.screenshot`.
- **CPU Profiler**: `Profiler`: a tool page, off by default.
- **Fast Loot**
- **Auto Repair**
- **Auto Sell Junk**
- **Auto Open Containers**: `AutoOpen`: opens the containers in the bags by themselves, when nothing is in the way.
- **Item Tooltips**: a folder: the module and its parts, Sell Price, Repair Cost, Item Count, Disenchant, Stat Colors, Compare Crafted Gear, and Auction Prices, with its auction house scan in `Scan.lua`.
- **Waylaid Crates**: a folder: the module, Bundle Costs, and its auction house category.
- **Already Known**
- **Appearance Icons**: uncollected appearances.
- **Unusable Items Tint**
- **Upgrade Arrows**: a folder: the module and its stat weight templates.
- **Best Quest Reward**
- **Easy Delete**
- **Hide Beta Feedback**: beta/PTR only.
- **Gathering Tracking**
- **Gathering Skill Tooltips**: `ProfessionTooltips`.
- **Auto Stow**
- **Bag Slot Counter**
- **Auto Gossip**
- **Auto Quest**
- **Tooltips**
- **Auto Decline**
- **Auto Confirm**: the enchant popups answered with the C_Item call their own Yes makes, then closed.
- **Auto Release**
- **Skip Cinematics**
- **Auto Dismount**
- **Fishing Cast**
- **Auto Weapon Buff**
- **Comprehend Scrolls**
- **Auto Screenshot**
- **Professions**: a folder: the module and a part each for Recipe Colors, Skill-Ups Left, Skill Bar (the selected recipe's yellow, green, and gray levels as a bar, from the generated `Data.lua`), and Crafting Costs with Profit in Recipe List and the merchant prices it learns, and Unlearned Recipes (the open profession's recipes not known yet, added to Blizzard's own recipe list and Filter menu, with their learn skill from `Data.lua`).
- **Spell Ranks**
- **Train All**: a button of ours beside the trainer window's Train, buying one skill after each answer from the trainer.
- **Buff Timers**
- **Macros**: a folder: the module, which makes and deletes its macros and marks their buttons, and its Smart Buff macro as a part.
- **Class Colors**
- **World Map**: a folder: the module, its quick checkboxes in the world map's filter menu (`Filter.lua`), and a part each for Points of Interest (with its flight points, ley lines, and Blizzard icons in files of their own), Zone Info, Unexplored Areas, and Coordinates, with their map, zone, and map art data.
- **Flight Timer**
- **Hide Filter Reset**
- **Square Minimap**: a square mask and border in place of the round frame, saying so through `GetMinimapShape`.
- **Waypoints**: `/way` and a waypoint arrow.
- **Compass Bar**: a compass across the top of the screen, sized in Edit Mode, with the selected quest, the map pin, the corpse, the group, and, as the player picks, quests on the map, flight masters, Gathering Map's nodes through its provider, and rares on it.
- **Gathering Map**: a folder: the module, which remembers each herb, vein, chest, and fishing pool gathered for the account, its world map and minimap icons, its kinds in the world map's filter menu (`Filter.lua`), and its page of nodes to show or hide for each character.
- **Combat Alert**
- **Macro Icon Search**: a search box in the macro icon picker, over the icons of the player's spells and items.
- **Movable Windows**: drag Blizzard's windows with a key held, and resize one with a key and the mouse wheel (a frame of our own takes the wheel while the key is held, so no Blizzard frame gets a wheel handler), remembered always, for the session, or until closed.
- **Hide Stance Bar**: the stance bar faded out, its buttons not taking the mouse.
- **Hide Error Messages**: `HideErrors`: the error frame's UI_ERROR_MESSAGE heard in its place, and only the errors not hidden handed to it.
- **Loot Rolls**: the group loot rolls placed in Edit Mode, with their grow direction, spacing, and preview as Edit Mode settings, and the seconds left and roll counts on each.
- **Movable Framerate**
- **Local Time**: the calendar's and a few other realm times of day in the player's time while the clock's Use Local Time is on.
- **XP Bar Text**
- **AddOns List**
- **Error Catcher**
- **Minimap Button**: its menu of quick toggles, picked by the player with the Customize button in its settings.
- **Currency Bar**
- **Character Window**: a folder: the module, its durability bars, and equipped weapon skill colors.
- **Durability Warning**: once when worn gear drops below a durability the player picks and again when it breaks: a chat line, red error-frame text, and a sound, each an option.
- **Forever Quest Icons**
- **Quest Tracker**
- **Quest Levels**
- **Quest Item Sparkles**: keeps the CVar for the sparkle on quest items in the world on.
- **Quest Pins**: a folder: the module, its index of quest starts by map read from QuestieDB a few milliseconds a frame, the rules for which quests the player can take, its world map pins, and its NPC tooltip lines; needs QuestieDB, off by default.
- **Talent Planner**: a folder: the module, reading the tree, drawing on it, the plan bar, and the level-up reminder.
- **Slash Commands**: `Commands`: `/rl` and `/clear`.
- **Chat Copy**
- **Short Channel Names**
- **Chat Levels**
- **Quest Links**: Questie's plain-text quests in chat made Blizzard quest links.
- **Chat Font**
- **Keep Chat Visible**: `PersistentChat`: chat doesn't fade.
- **Chat History**
- **Chat Arrow Keys**: Up and Down in the chat box recall what was sent, without Alt.
- **Social Button**
- **Hide Chat Buttons**: an alpha on each chat button, faded after Blizzard's own fade calls for the chat window.
- **Hide Combat Log Tab**: the tab scaled to almost nothing while the log is docked.
- **Whisper Window**: a folder: the module and its window.

## API.lua

- The public API other addons read, the global `ForeverPlusPlusAPI.v1` (documented in `docs/api.md`): thin, read-only wrappers over `Lib/` (auction prices, disenchanting, players seen, colors, instances, gathering, the map pin, modules and their options, the profile in use) and over what modules offer through `ns.Providers` while they're on (Upgrade Arrows' scores, Flight Timer's times and flights, Waypoints' arrow target, Gathering Map's nodes, Points of Interest's learned flight points), and callbacks (`READY`, `PRICES_UPDATED`, `UPGRADES_UPDATED`, `MODULE_TOGGLED`, `OPTION_CHANGED`, `WAYPOINT_CHANGED`, `GATHERING_NODES_UPDATED`, `GATHERED`, `FLIGHT_STARTED`, `FLIGHT_ENDED`, `PROFILE_CHANGED`, fired through `ns.API.Fire`).
- It reads modules and options but never changes them: they're the player's.
- The one thing a caller adds is a module of its own (`RegisterModule` and `GetPluginKit`, through `Lib/Plugins.lua`): what a plugin may set on its handle and what the kit holds is `docs/api.md`'s Plugins section. It is marked experimental there since 1.6.0 and may still change; once the mark is gone it is part of `v1`'s promise.
- Every call is wrapped so an error of ours returns nil instead of breaking the caller, and returns copies, never our tables.
- `v1` only grows: never rename, remove, or change what a function or return value means.
- A breaking change is a `v2` beside it.
- Add a function here when `Lib/` gains data another addon could want, and to `docs/api.md` and the offline tests with it.

## Changelog.lua

- The release notes as data (`ns.changelog`) for the Changelog page, since the game can't read `CHANGELOG.md` (at the repo root).
- Keep the two the same.
- An entry is `{ name, text }` with a module's title (or `L.CHANGELOG_SETTINGS`, `L.CHANGELOG_COMMANDS`) as its name, which the page's By Module view groups by.
- A plain line goes under General.

## Settings/

- The Settings pages.
- `Settings.lua` has Modules as the top Forever++ entry (a list of the modules with a checkbox each, grouped under a label per category, and the selected one's description and options beside it), a page per module `BuildPage`, and what the other pages share (`ns.SettingsUI`).
- `Profiles.lua` the Profiles page right after it (this character's and new characters' profile, the profiles with who uses each, the preset each is based on (Based On), their characters, and Export and Import), `Debug.lua` draws the Debug module's page, and `Changelog.lua` and `About.lua` (version, link buttons, credits, the addons we work with, and the searchable commands) the rest.

## CI and releases (`check.yml`)

- On every push, checks Lua 5.1 syntax, runs `tests/run.lua`, checks ASCII and that the TOC and the files match, runs wowlua-ls (pinned, Forever flavor) and fails on any finding not in `tests/wowlua-baseline.txt`, then uploads the addon folder as a zip artifact.
- Pushing a `v*` tag also makes a GitHub release with the zip and uploads it to CurseForge (secret `CF_API_KEY`, variables `CF_PROJECT_ID` and `CF_GAME_VERSION_IDS`).
- Bump `## Version` in the TOC to match first, and add the release's notes to `CHANGELOG.md` and `Changelog.lua` (the release stops if any of those is missing).
- A tag with a suffix (`v1.2.0-beta.1`) is a pre-release on GitHub and a beta on CurseForge.
- The GitHub release and the CurseForge upload are separate jobs: re-running the release job replaces the zip and notes, but re-run the CurseForge job only when it failed, or CurseForge gets a second file.
- Wago ([addons.wago.io/addons/foreverplusplus](https://addons.wago.io/addons/foreverplusplus)) imports each GitHub release by itself (its GitHub release import, through a webhook on the repo), so nobody uploads there by hand.

## The description (`docs/description.md`)

- The project description on CurseForge and Wago.
- Nothing syncs it: CurseForge's upload API takes only files, and Wago's description is edited on its site, so paste it into both by hand after it changes.
- Its Modules and Commands sections are the README's tables as lists (without the developer-only commands).
- Keep them the same, with links that work off GitHub.

## Generated data (`tools/datagen/`)

- The generator of data files made from the client's database tables (not shipped).
- `lua5.1 tools/datagen/generate.lua [build]` downloads the tables it needs for a `wowf` build from wago.tools with curl (the latest build when none is given; `--latest` only prints it), caches them in `cache/` (ignored by git), and writes every generated file: Unexplored Areas' `Data.lua` (WorldMapOverlay, WorldMapOverlayTile, UiMapXMapArt, UiMap), Professions' `Data.lua` (SkillLineAbility, SkillLine, ItemEffect, ItemXItemEffect, ItemSparse, TradeSkillCategory: each recipe's yellow and gray levels, skill line, spell, and teaching item with its skill, and the Season of Discovery recipe categories Unlearned Recipes leaves out), `Lib/Generated/InstanceLevels.lua` (LFGDungeons, ContentTuning, Map, AreaTable: each instance's dungeon finder level), `Lib/Generated/DisenchantBrackets.lua` (ItemDisenchantLoot), `Lib/Generated/LockboxSkills.lua` (ItemSparse, Lock: each lockbox's Lockpicking), `Lib/Generated/ComprehendScrolls.lua` (ItemSparse: the items that need skill line 3012), `Lib/Generated/WeaponBuffs.lua` (ItemEffect, ItemXItemEffect, SpellEffect, SpellEquippedItems, SpellName: each item whose use puts a temporary buff on a weapon, with the mask of weapon subclasses it goes on), `Lib/Generated/TaxiRoutes.lua` (TaxiPath, TaxiPathNode: each direct flight's length and what flying through a stop saves), and `Reference.txt`, what the tables say about data kept by hand (the Map table's dungeons and raids against `Data/Instances.lua`, TaxiNodes' flight points and TaxiPathNode's transport stops in zone percent, for Points of Interest's `Data.lua`), so a new build's diff shows what to check there.
- `BUILD` is the build they came from.
- Never edit a generated file by hand: change the generator (one module per file, listed in `generators.lua`) and run it again.
- Output is sorted, so the same build gives the same bytes.
- `summary.lua` counts the entries added, removed, and changed between two copies.
- `survey.lua [build]` prints what the tables hold for data kept by hand (locks, suffixes, sets, flights, levels, recipes, factions, disenchanting) against the addon's seeds.
- `docs/table-survey.md` is its write-up for one build.

## The table data workflow (`table-data.yml`)

- Daily and by hand, compares wago.tools' latest `wowf` build with `tools/datagen/BUILD`.
- When it's newer, regenerates, runs check.yml's syntax, ASCII, and offline test checks on the result, and opens a pull request from `data/build-<build>` (one per build; an older open one is closed as superseded, and a build whose pull request was closed gets no other until its branch is deleted).
- It alone may write (`contents` and `pull-requests` on its job).
- It needs "Allow GitHub Actions to create and approve pull requests" on (Settings > Actions > General), and Check doesn't run on its branch by itself.
- An unreachable wago.tools is a warning.
- A generator error fails the run.

## The checker (`.wowluarc.json`)

- Settings for [wowlua-ls](https://github.com/TradeSkillMaster/wowlua-ls), TradeSkillMaster's WoW-aware checker: the Forever flavor, so it checks secret values, and the folders it skips.
- It learns the addon's own secret guards (`ns.IsReadable`, `ns.IsText`, `ns.IsNumber`) from their `---@secret-guard` lines in `Lib/Secret.lua`.

## Tests

- `tests/` holds the offline tests: a spec in `tests/spec/` for each area of pure-logic `Lib/` code, named for it (`store`, `talentplan`, `profileshare`, `questiedb` against a made-up stub of its API, `dungeonmaps` against a stub of DungeonJournal, and so on), Core's module lifecycle on stub frames and a stub clock (modules and parts turning on and off, `OnWhile`, dropdown parts, owned timers, `/fpp set`, presets and profiles based on one, switched live), the public API, and checks across the addon: no file writes a global the Lua rules don't allow (plainly or through `_G`), and every global it reads is Lua's or in `.luarc.json` (`globals`, from each file's bytecode), every `L.KEY` the code uses is defined in `Locales/enUS/` (`locales`), every file loads offline without making a frame, hook, timer, or event listener, and every module's settings are well formed, with defaults that fit and `requires`, `slider`, and `conflicts` naming real options (`modules`), every Lib file has a row in `AGENTS.md`'s Lib tables and a place here, and every click hint is written as Blizzard's are (`docs`), the TOC's version, `Changelog.lua`, and `CHANGELOG.md` agree (`release`), and the rules a machine can check exactly hold: each file's first line, no removed Classic globals, no `COMBAT_LOG_EVENT_UNFILTERED`, `WOW_PROJECT_ID`, `print`, and `IsInInstance` only where allowed, no tabs or trailing spaces (`rules`).
- They need only Lua 5.1, no client: `lua5.1 tests/run.lua` from the repo root (CI runs it after the syntax check), or `lua5.1 tests/run.lua store` for the specs with that in their name.
- Each spec gets a fresh copy of the addon with the real `Lib/` and `Locales/enUS/` files against stubbed WoW globals, so specs can't depend on each other.
- A Lib file that caches a global at load needs that global stubbed before it loads (`tests/lib/env.lua`, or `T.load` after the stub).
- `tests/README.md` says how to write one.
- Add a check when you change or add Lib logic that has no frames in it, a spec when you add a Lib file, and a check in the `core_*` specs (each on a fresh real Core, `T.Core()`) when you change how Core turns modules on and off.
- Don't test frame or UI code.
- CI also runs wowlua-ls (`wowlua_ls check .`, release binaries on its GitHub page) for types and secret values.
- `tests/wowlua.lua` compares its findings with `tests/wowlua-baseline.txt` and fails on a new one.
- A new finding is usually a real problem: fix it, or, when it's the checker's mistake, add it with `--update` and say why in the commit.
- Fixing one means taking it out of the baseline too (`--update` does it).
