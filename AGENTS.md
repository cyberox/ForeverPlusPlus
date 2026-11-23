# AGENTS.md

Rules for anyone changing this repository, human or AI. `CLAUDE.md` imports this file; edit rules here only.

Keep this file short. It says what exists and what the rules are. The detail is in other docs, and nothing we've learned gets dropped: move it there instead.

| For | Read |
| --- | --- |
| What each `Lib/` file, `Core.lua`, and each module holds, function by function, and the CI, data, and test details | [docs/architecture.md](docs/architecture.md) |
| Every Settings rule in full, with reasons, edge cases, and examples | [docs/settings.md](docs/settings.md) |
| What we know about the Forever client, with sources | [docs/forever-api.md](docs/forever-api.md) |
| What each module does for players, and "Add a module" step by step | [README.md](README.md) |

## What Forever++ is

A World of Warcraft addon for **WoW: Forever** that adds to and changes the default UI in small, separate modules.

- It enhances Blizzard's UI. It is **not** a UI replacement: no new unit frames, action bars, or skins of the whole interface.
- Every change should look like Blizzard shipped it: Blizzard fonts, atlases, templates, colors, and spacing. A player should not be able to tell where Blizzard stops and Forever++ starts.
- Every change should be seamless: no setup, no popups at login, sensible defaults, and nothing that breaks when a module is off.

| What | Value |
| --- | --- |
| Folder / addon name | `ForeverPlusPlus` |
| Display name | `Forever++` |
| Slash commands | `/fpp`, `/forever++` |
| SavedVariables | `ForeverPlusPlusDB`, `ForeverPlusPlusPlayersDB` (players seen), and `ForeverPlusPlusCharDB` per character |
| Interface | `16001` |

## Project map

There is no build step or library folder. Plain Lua, loaded straight from the TOC; CI only zips the folder.

### Repository

| Path | What it is |
| --- | --- |
| `ForeverPlusPlus/` | The shipped addon, linked into the client's `Interface\AddOns`. |
| `README.md` | For players and contributors: the module list, install, settings, commands, and "Add a module". |
| `CHANGELOG.md` | Each release's notes, read by the release jobs. `ForeverPlusPlus/Changelog.lua` has the same notes for the game. |
| `docs/architecture.md` | The detail behind this project map: what every part of the addon holds. |
| `docs/settings.md` | The Settings rules in full. |
| `docs/forever-api.md` | What we know about the Forever client API, with sources and how sure we are. |
| `docs/api.md` | The public API for addon authors. Keep it the same as `API.lua`. |
| `docs/questiedb.md` | The QuestieDB addon's API as read from its source, how `Lib/QuestieDB.lua` uses it, and the in-game checks still to do. |
| `docs/stat-weights.md` | Upgrade Arrows' default stat weights, how each was worked out, and the sources. |
| `docs/description.md` | The project description on CurseForge and Wago. Nothing syncs it; paste it into both by hand after it changes. |
| `docs/table-survey.md` | What the client's tables hold for data kept by hand, for one build (`tools/datagen/survey.lua`). |
| `tests/` | Offline tests (see Verification and `tests/README.md`). |
| `tools/datagen/` | Generates data files from the client's database tables (see Generated data). Not shipped. |
| `.github/workflows/check.yml` | CI and releases (see Releases). |
| `.github/workflows/table-data.yml` | Regenerates the table data for a new game build and opens a pull request. |
| `.github/ISSUE_TEMPLATE/` | The bug report and feature request forms. |
| `.luarc.json` | LuaLS settings: Lua 5.1 and the known globals. |
| `.wowluarc.json` | Settings for [wowlua-ls](https://github.com/TradeSkillMaster/wowlua-ls), the WoW-aware checker: Forever flavor, and the folders it skips. |
| `LICENSE` | MIT. |

### The addon folder

Load order is the TOC's: `Core.lua`, `Commands.lua`, `Locales/`, `Data/`, `Lib/`, `Modules/`, `API.lua`, `Changelog.lua`, `Settings/`, `Init.lua`.

| Path | What it is |
| --- | --- |
| `ForeverPlusPlus.toc` | Metadata and load order. |
| `Bindings.xml` | Keys in Blizzard's Key Bindings, under Forever++ (Target Markers' ring). The game loads it by itself; it isn't in the TOC. |
| `Core.lua` | The shared `ns`: events, modules and parts, saved settings, hooks, timers, migrations, printing, and the locale table `ns.L`. |
| `Commands.lua` | `/fpp` and its subcommands, `/fpp set` and `toggle`, and the Defaults popup's resets (`ns.ApplyPreset`, `ns.UsePreset`). |
| `Locales/<language>/*.lua` | Player-facing text, a file per category. `enUS/` has every key and is the fallback; another language sets only what it translates. |
| `Data/*.lua` | Game data kept by hand, in one place so a patch's change is one edit: plain tables on `ns.Data`, with where each came from. `Instances.lua` (the dungeons and raids, and their map art), `Professions.lua` (herbs, veins, chests, pools, tools, skeleton keys), `Spells.lua` (spell IDs more than one file uses, through `ns.Data.Spell`), `Items.lua` (the containers Auto Open Containers leaves), `Buffs.lua` (Smart Buff's), `PointsOfInterest.lua` (where dungeon entrances, flight masters, boats, and spirit healers are on each zone's map), `ZoneInfo.lua` (each zone's levels, fishing skill, herbs, and ores). No logic. |
| `Lib/*.lua` | Shared services any module can use. They cost nothing until a module uses them. |
| `Modules/<Category>/` | One change each. |
| `API.lua` | The public API, `ForeverPlusPlusAPI.v1`. |
| `Changelog.lua` | The release notes as data (`ns.changelog`) for the Changelog page. An entry is `{ name, text }`, `name` a module's title (or `L.CHANGELOG_SETTINGS`, `L.CHANGELOG_COMMANDS`); a plain line goes under General. |
| `Settings/` | The Settings pages: `Settings.lua` (Modules, and what the pages share as `ns.SettingsUI`), `Profiles.lua`, `Debug.lua`, `Changelog.lua`, `About.lua`. |
| `Init.lua` | Loaded last; calls `ns.Start()` at `PLAYER_LOGIN`. |
| `Media/Icon.tga` | The addon icon (64x64, 32-bit uncompressed TGA), made from `docs/project-icon.png`. |

### Core

What `Core.lua` gives every file through `ns`:

- **Events:** `ns.On`, `ns.Off`, `ns.OnUnit` (a UNIT_* event of one or two units), `ns.HasEvent` (before an event a patch may add or drop).
- **Modules:** `ns.NewModule`, `ns.SetEnabled`, `ns.OnModuleChanged`. A module made of parts uses `module:NewPart`; `ns.PartOn` says whether one is on.
- **While a module is on:** `module:On`, `module:OnUnit`, `module:OnWhile(when, events)`, `module:Hook`, `module:HookScript`, `module:TooltipPostCall`, `module:TooltipLinePreCall`. These stop or do nothing while the module is off, and skip a target this client doesn't have.
- **Timers:** `ns.Frames.Timer(module)` and `ns.Frames.Coalesce(fn, delay, module)` are cancelled when their module turns off.
- **Settings:** `module.db`, `ns.SetOption`, `ns.ResetOption`, `ns.BaseValue`, `ns.Migrate`, `ns.MigrateCharacter`, `ns.MoveSettings`, `ns.ChangeProfile`.
- **Combat:** `ns.AfterCombat(fn)` runs it now or once combat ends.
- **Chat:** `ns.Print`, `module:Print` with `ns.ChatOption`.

### Lib

One line here says what each file is for. [docs/architecture.md](docs/architecture.md) lists what each one offers, and the file's header comment says how it works.

**Saved data and settings**

| File | `ns` | For |
| --- | --- | --- |
| `Store.lua` | `Store` | The saved variables' layout and version, the steps that bring an old one up to date, and the `module.db` each module reads through the profile in use. |
| `Presets.lua` | `Presets` | Named presets on top of the defaults (today only Developer's Defaults, `developer`), each module's part declared in its own `module.presets`. |
| `Profiles.lua` | `Profiles` | Profiles: made, copied, based on a preset, renamed, deleted, and switched live. |
| `ProfileShare.lua` | `ProfileShare` | A profile as one line of text, and pasted text checked before it's imported. |
| `GameData.lua` | `GameData` | Game data a patch can change: a seed the addon ships plus what play taught it, and single IDs Self Test checks. |
| `CVars.lua` | `CVars` | Setting CVars and putting the player's values back, waiting out combat (`Set`, `Restore`, `Bind`, `Hold`, `OffNotice`). |
| `Providers.lua` | `Providers` | What a module offers outside itself while it's on, by name, for `API.lua`. |
| `Plugins.lua` | `Plugins` | Modules another addon adds through the public API: a checked handle, never our module table. |
| `Players.lua` | `Players` | The class, level, race, and guild of players seen, saved in `ForeverPlusPlusPlayersDB` while a module uses it. |
| `Prices.lua` | `Prices` | Auction prices and items by name, from Item Tooltips' Auction Prices, and what a vendor pays (`Vendor`). |

**Values and text**

| File | `ns` | For |
| --- | --- | --- |
| `Secret.lua` | `IsReadable`, `IsText`, `IsNumber`, `IsTrue`, `IsTrueOrSecret`, `AurasReadable`, `EachAura`, `HealthStepCurve` | Guards for values that may be secret, and a curve that turns secret health into a widget value. |
| `Colors.lua` | `Colors` | Shared colors: color codes, class, level range, a level's difficulty (`Difficulty`), faction, and one per stat. |
| `Text.lua` | `Text` | Numbers, durations ("3 Seconds", "12m ago"), yards, version compare, and stripping escape codes. |
| `Money.lua` | `Money`, `MoneyShort` | Copper as coin text. |
| `Fonts.lua` | `Fonts` | The game's fonts a font dropdown offers. |
| `Keys.lua` | `Keys` | The Skip Key dropdown and whether its key is held. |
| `Gamepad.lua` | `Gamepad` | The controller interface: whether it's on (`On`), the notices of a module it hides or limits, its buttons by where they sit (`BUTTON`), reading one and a press of one (`Down`, `Press`), how the player's controller labels one, and click hints written for it. |
| `Sounds.lua` | `Sounds` | The alert sounds every Sound dropdown offers, the dropdown itself (`Option`), and playing one. |
| `RealmTime.lua` | `RealmTime` | Realm time moved to the player's clock. |
| `Slash.lua` | `Slash` | Slash commands a module adds and takes away live. |
| `Profiler.lua` | `Profiler` | Times calls into each module's code while the Profiler page records. |
| `Errors.lua` | `Errors` | Error Catcher's counts and window, for the minimap button. |
| `AddOns.lua` | `AddOns` | Waiting for a load-on-demand addon, and this character's addons as a set to save and put back (`States`, `Changes`, `Apply`). |

**Frames and windows**

| File | `ns` | For |
| --- | --- | --- |
| `Frames.lua` | `Frames` | Atlas and template checks, Blizzard's panel button, saved anchors, our portrait windows, Escape to close, `Coalesce`, `Timer`, `Throttled`. |
| `Menus.lua` | `Menus` | A context menu at the cursor (`Open`): Blizzard's, or a list of our own while the controller interface is on (`Gamepad.On`), where Blizzard's opened by an addon breaks the controller's focus. A dropdown's menu goes through `SetupDropdown`. Never `MenuUtil.CreateContextMenu` or a dropdown's `SetupMenu` directly. |
| `Confirm.lua` | `Confirm`, `ConfirmChoice`, `ConfirmButtons`, `Prompt`, `PromptName`, `ClosePopup` | Yes/no popups, ones with two or three choices, and text popups: Blizzard's, or a frame of our own while the controller interface is on. `ClosePopup` closes one of Blizzard's own, and leaves it up with the controller interface on. Never `StaticPopup_Show` or `StaticPopup_Hide` directly. |
| `EditMode.lua` | `EditMode` | Our own frames in Blizzard's Edit Mode, looking and working like Blizzard's (`RegisterModule`), and Blizzard's own layouts (`Layouts`, `SetLayout`). |
| `SettingsKit.lua` | `SettingsKit` | What a drawn Settings page is made of, for the Settings pages and a tool's `BuildPage`. |
| `Chat.lua` | `Chat` | The chat windows, rewriting and filtering their lines, and the column of buttons beside them (`NewButton`, `SetBadge`). |
| `ActionButtons.lua` | `ActionButtons` | Blizzard's action buttons, what each slot holds, and our marks over them. |
| `StatusBars.lua` | `StatusBars` | Blizzard's experience and reputation bars: the Solid Bar option that takes the divider lines off one, and a font string of ours over each bar of a kind for a module's own bar text (`Texts`). |

**Items**

| File | `ns` | For |
| --- | --- | --- |
| `ItemTooltip.lua` | `ItemTooltip` | Our lines on item tooltips, kept together at the sell price (`OnInfo`, `OnPrices`, `AddInfo`, `AddPrice`). |
| `Bags.lua` | `Bags` | Walking every slot of the player's bags (`Each`), the free slots, and which bag is the reagent bag. |
| `ItemButtons.lua` | `ItemButtons` | The item buttons in bags, bank, merchant, auction house, loot, and rolls, our marks on them, one walk over all of those for a module that marks items (`Walk`), and the options every mark shares. |
| `BagClicks.lua` | `BagClicks` | Secure overlays on bag items whose right-click uses an item or casts on it. |
| `ItemStats.lua` | `ItemStats` | An item's stats in short keys, and a stat weight score. |
| `Equipment.lua` | `Equipment` | Slots, what's worn, whether the character can use an item, and what an item would replace. |
| `Durability.lua` | `Durability` | How whole each equipped item is, and when a drop should warn. |
| `Disenchant.lua` | `Disenchant` | Which items disenchant, into what, and their average value. |
| `NewItems.lua` | `NewItems` | Which items Classic never had (`Has`). |

**Character**

| File | `ns` | For |
| --- | --- | --- |
| `Professions.lua` | `Professions` | Profession skills, gathering nodes by name, recipe levels and their bar, and the professions window's recipe rows. |
| `Spellbook.lua` | `Spellbook` | The spells the player knows, with every rank. |
| `Talents.lua` | `Talents` | The talent tabs and the points in each. |
| `TalentPlan.lua` | `TalentPlan` | An ordered talent plan checked against the tree's rules, share strings, and build links. |
| `Units.lua` | `Units` | Who a unit is: in my group, a friend, a recent ally, a guildmate. And whether the player is busy (`PlayerBusy`, `PlayerCasting`), for a module that acts by itself. |

**Nameplates**

| File | `ns` | For |
| --- | --- | --- |
| `Nameplates.lua` | `Nameplates` | Plate added, removed, and cast callbacks, and Forever's plate parts. |
| `PlateLabel.lua`, `FriendlyPlates.lua` | `PlateLabel`, `FriendlyPlates` | The name-only friendly plates Player Nameplates and NPC Nameplates share. |

**Maps and the world**

| File | `ns` | For |
| --- | --- | --- |
| `WorldMap.lua` | `WorldMap` | The world map, the map tree, map names and sizes, Blizzard's map pin and its name, where the player, a quest, and the corpse are, and our one group in its filter menu (`AddFilter`). |
| `MapTooltip.lua` | `MapTooltip` | How every tooltip over the world map looks. |
| `MapPins.lua` | `MapPins` | Layers of our own icons on the world map, and what a click on one does (Ctrl+click for the map pin, as the game's own). |
| `MinimapPins.lua` | `MinimapPins` | What the minimap shows, zone-map spots as minimap spots, its gold ring, its shape, and its tracking menu (`EachTracking`). |
| `Instances.lua` | `Instances` | The dungeons and raids with their levels and names, and the kind of instance the player is in (`Here`). |
| `DungeonMaps.lua` | `DungeonMaps` | A dungeon's map over the world map, drawn from the old map art the client still has, or opened in the DungeonJournal addon when it has none. |
| `Gathering.lua` | `Gathering` | What the player gathers as they gather it, a map's remembered nodes, and nodes as shareable text. |
| `Taxi.lua` | `Taxi` | The open flight master's flight points, and a flight's estimated time. |
| `Quests.lua` | `Quests` | Which quest Blizzard's quest windows show, a quest's level and tag, and whether it's a group quest. |
| `QuestieDB.lua` | `QuestieDB` | The one place we read the separate QuestieDB addon, at run time (`Require` for a module that needs it). |

**Generated**, in `Lib/Generated/` (never edit by hand): `InstanceLevels.lua`, `DisenchantBrackets.lua`, `LockboxSkills.lua`, `ComprehendScrolls.lua`, `WeaponBuffs.lua`, `TaxiRoutes.lua`, `NewItems.lua`, `ExplorableMaps.lua`.

### Modules

- The module list, and what each does for players, is the table in `README.md`. What each is in the code's terms is in [docs/architecture.md](docs/architecture.md).
- A module is in `Modules/<Category>/`: `Automation`, `Character`, `Chat`, `Interface`, `Items`, `Map`, `Quests`, `System`, `Units`, or `Tools`. A small module is one file. A bigger one gets a folder of files that share `module.internal`.
- A module made of parts (World Map, Item Tooltips, Professions, Waylaid Crates, Macros) has a file per part in its folder.
- A few module names differ from their titles: `AutoOpen` (Auto Open Containers), `DungeonNameplates` (Simplified Dungeon Nameplates), `HideErrors` (Hide Error Messages), `ProfessionTooltips` (Gathering Skill Tooltips), `PersistentChat` (Keep Chat Visible), `Commands` (Slash Commands), `Profiler` (CPU Profiler).
- Self Test, Gear Probe, and Screenshots have no toggle: each is a button on the Debug page and a `/fpp` command while Debug is on. A module adds its own screenshot scene with `module.screenshot`.

### The public API

`API.lua` sets the global `ForeverPlusPlusAPI.v1`, documented in `docs/api.md`: thin wrappers over `Lib/` and `ns.Providers`, and callbacks. [docs/architecture.md](docs/architecture.md#apilua) has what it covers.

- It reads modules and options but never changes them: they're the player's. The one thing a caller adds is a module of its own (`RegisterModule`, `GetPluginKit`, through `Lib/Plugins.lua`), experimental since 1.6.0.
- Every call is wrapped, so an error of ours returns nil instead of breaking the caller. It returns copies, never our tables.
- `v1` only grows: never rename, remove, or change what a function or return value means. A breaking change is a `v2` beside it.
- Add a function when `Lib/` gains data another addon could want, and add it to `docs/api.md` and the offline tests too.

### Releases

`check.yml` checks every push (Lua 5.1 syntax, `tests/run.lua`, ASCII, the TOC against the files, and wowlua-ls against `tests/wowlua-baseline.txt`) and uploads the addon folder as a zip artifact. Pushing a `v*` tag also makes a GitHub release and a CurseForge upload, and Wago imports the GitHub release by itself. [docs/architecture.md](docs/architecture.md#ci-and-releases-checkyml) has the jobs, their secrets, and pre-releases.

- Before tagging, bump `## Version` in the TOC to match, and add the release's notes to `CHANGELOG.md` and `Changelog.lua`. The release stops if any of those is missing.
- Re-running the release job replaces the zip and notes. Re-run the CurseForge job only when it failed, or CurseForge gets a second file.

### Generated data

`lua5.1 tools/datagen/generate.lua [build]` downloads the tables a `wowf` build needs from wago.tools and writes every generated file: Unexplored Areas' and Professions' `Data.lua`, the eight files in `Lib/Generated/`, and `Reference.txt` (what the tables say about data kept by hand, so a new build's diff shows what to check). [docs/architecture.md](docs/architecture.md#generated-data-toolsdatagen) has what each comes from, `summary.lua` and `survey.lua`, and the `table-data.yml` workflow that regenerates for a new build and opens a pull request.

- **Never edit a generated file by hand.** Change the generator (one module per file, listed in `generators.lua`) and run it again.
- `BUILD` is the build they came from. Output is sorted, so the same build gives the same bytes.

## The client

- Client folder: `D:\BattleNet\World of Warcraft\_forever_\` (product `wowf`, version 1.60.1).
- `Interface\AddOns\ForeverPlusPlus` there is a link to `ForeverPlusPlus/` in this repo, so edits show up after `/reload`.
- **Treat the client folder as read only.** Never create, edit, or delete anything in it, including `WTF`, `Logs`, `Cache`, and other addons. Reading is fine.
- Useful things to read there:
  - `Logs\FrameXML.log`: Lua and XML load errors.
  - `Interface\AddOns\*`: other Forever addons show which APIs work on this client.
  - `WTF\Account\*\SavedVariables\ForeverPlusPlus.lua`: what the addon saved.

## How Forever differs from Classic

Forever is a Classic+ game (level 60 content) that runs the **modern Mainline (12.x "Midnight") client and UI**, not the Classic Era API. Assume Retail APIs and Retail rules, then check.

- **Detecting Forever.** `WOW_PROJECT_ID` is `WOW_PROJECT_CAMELOT` (18) since build 70170. Don't use it to detect Forever. If a difference matters, use the interface number from `GetBuildInfo()` (range `[16000, 17000)`, never "starts with 1": Classic Era is 11509), or better, probe for the API.
- **Classic-only globals are gone:** `GetItemInfo`, `GetSpellInfo`, `UnitAura`, `SetDesaturation`, and similar. Use `C_Item`, `C_Spell`, `C_UnitAuras`, `C_Container`, `C_AddOns`, `C_Timer`.
- **The UI is Mainline's:** Edit Mode, the Settings panel, the `Menu` / `MenuUtil` context menus (`Menu.ModifyMenu` to add to Blizzard's), `TooltipDataProcessor.AddTooltipPostCall`, `MicroMenu`, `AddonCompartmentFrame`, `ChatFrameUtil`, `BackdropTemplate`.
- **Secret values apply** (`issecretvalue`, `C_Secrets`). Unit health, power, identity, auras, cooldowns, and casts can come back secret, mostly in combat and instances.
  - Never compare, test (`if v then`), do arithmetic on, concatenate, `#`, or use as a table key a value that might be secret.
  - Pass it straight to widget setters (`SetText`, `SetValue`, `SetMinMaxValues`).
  - Don't read state back from Blizzard widgets (`GetText`, `GetValue`, `IsShown`, sizes) and branch on it.
- **`COMBAT_LOG_EVENT_UNFILTERED` never fires for addons.** There is `C_DamageMeter` instead.
- **`UnitName` returns a surname**, not a realm, as its second value. Don't treat it as a realm.
- **Talents and specs** go through `C_SpecializationInfo`.
- **One plain TOC.** Ship `ForeverPlusPlus.toc` with no suffixes; this addon targets Forever only.
- **It is a beta.** APIs appear, change, and break between patches. Probe (`if C_Foo and C_Foo.Bar then`) instead of assuming, and when something only works on Forever, say so in a comment.

When unsure whether an API exists, check it in game (`/dump C_Foo`, `/api`) or find an installed Forever addon that uses it. Don't guess from Classic Era or old Retail documentation. [docs/forever-api.md](docs/forever-api.md) has the evidence behind this section; keep the rules here short and record the detail there.

## Working rules

- Keep changes scoped to the request. Don't reformat or revert unrelated code.
- One module per change the player can see. A module must work, and be removable, on its own.
- Plumbing that a second module could want goes in `Lib/`, not inside a module. Modules never reach into each other; they share only `Lib/`, `Core.lua`, and `Commands.lua`.
- Default to on only for changes nearly everyone wants; otherwise `enabled = false`.
- When replacing behavior, delete the old path: no shims or renamed-key fallbacks in module code. Rename or drop a setting freely; the core clears settings for modules and options that no longer exist, and a dropdown whose saved value isn't a choice any more goes back to its default.
- Add a new file to the TOC, after `Core.lua` and `Commands.lua` and before `Init.lua`: `Locales/` first (`enUS/` before other languages), then `Data/`, then `Lib/`, then `Modules/`.
- Record things learned about the Forever client in `docs/forever-api.md`, tagged with how you know. Promote a fact to "How Forever differs from Classic" only when it changes how code must be written.

**Docs to update with a change:**

- A module added, removed, or changed in what it does or its default: its row in `README.md`, and the same text in `docs/description.md`. Keep a row to a sentence or two; options are explained in Settings.
- Commands or install steps: `README.md` and `docs/description.md` (which leaves out the developer-only commands).
- A new `Lib/` file, or one that gains something another module could use: a row in the Lib tables above, and its section in `docs/architecture.md`.
- A new module, or one whose structure changes: its line in `docs/architecture.md`.
- A new Settings rule or option field: the tables under Settings here, and the full rule in `docs/settings.md`.
- The description has no New section; what's new is in the changelog.

**Game data a patch can change** (item, spell, map, and quest IDs, node and NPC names, the skill something needs) goes through `ns.GameData`, not a bare table.

- Read it from the game where an API or tooltip line says it.
- Otherwise ship it as a seed with `ns.GameData.New(name, seed, { kind = "item" })` and `set:Learn` what play shows, so a patch mends itself instead of breaking the module.
- A seed kept by hand is a table in `Data/` (`ns.Data.<name>`), not in the Lib file or module that uses it. That file makes the `ns.GameData` set from it. Never keep the same list or ID in two places.
- A lone ID gets `ns.GameData.Spell(id, "Name")` (or `Item`, `Map`), which Self Test checks. One that a second file needs goes in `Data/Spells.lua` and is read with `ns.Data.Spell("KEY")`.
- Say where a seed came from (build and source) in a comment, beside the data.
**Migrations.** When a release renames or merges a module or setting the player chose, or one holding data they built up, migrate it.

- `ns.Migrate(version, fn)`, in the module that now owns it, moves the old saved values at login, before the core clears them.
- The saved file has a layout version (`Lib/Store.lua`), so each step runs once: give a new step the next version and raise `Store.VERSION` to it.
- Move values in every profile: `for _, root in ipairs(ns.Store.Roots(db))`, each with `root.settings` and `root.data` (`Store.Rename` already does). Data kept per character uses `ns.MigrateCharacter`.
- Only migrate from what a release shipped, not from unreleased work. A dropped setting needs nothing.
- Keep every migration, so a player updating from any older release keeps their settings.
- Dropping data that holds the player's own CVar values (a `saved` table) needs a step that puts them back first.

## Lua rules

- Lua 5.1. ASCII only in `.lua` and `.toc` files. Four-space indents, LF endings (`.editorconfig`).
- Start every file with `local addonName, ns = ...` (or `local _, ns = ...`). Modules share state through `ns`, never `_G`.
- Cache hot globals as file-level locals: `local pairs, CreateFrame = pairs, CreateFrame`.
- Annotate public functions with LuaLS `---@param` / `---@return`. Match the comment style of `Core.lua`: short, plain, and saying why.

**Globals.** The addon sets only these. Add any new client global you read to `.luarc.json`; the `globals` spec fails on a read that isn't Lua's or listed there, and on a write that isn't one of these.

| Global | Why |
| --- | --- |
| `ForeverPlusPlusDB`, `ForeverPlusPlusPlayersDB`, `ForeverPlusPlusCharDB` | Saved variables. |
| `ForeverPlusPlusAPI` | The public API, set only by `API.lua`. |
| `SLASH_FOREVERPLUSPLUS*`, `SlashCmdList.FOREVERPLUSPLUS*` | `/fpp`, and commands a module adds only while its option is on (`/way`, `/rl`). |
| `ForeverPlusPlusScreenshotButton`, `ForeverPlusPlusSmartBuffButton`, `ForeverPlusPlusMarkerButton` | Buttons a key binding or `/click` needs by name. |
| `BINDING_HEADER_FOREVERPLUSPLUS`, `BINDING_NAME_CLICK ...` | Blizzard's Key Bindings reads them. |
| `ForeverPlusPlusErrorCatcher`, `ForeverPlusPlusChatCopy`, `ForeverPlusPlusWhisperWindow` | Windows Escape closes; `UISpecialFrames` holds names (`ns.Frames.CloseOnEscape`). |
| `GetMinimapShape` | Set by Square Minimap only while it squares the minimap and no other addon defines it. |

**Events and lifecycle**

- Use `ns.On` / `ns.Off` for events, not a new frame per module. For events a module listens to while it's on, use `self:On(event, fn)`; they stop by themselves when it turns off.
- A module that is off costs nothing: no frames, hooks, events, or `OnUpdate` until `OnEnable`.
- Every module turns on and off live, with no `/reload`: `OnDisable` undoes what `OnEnable` did. A module that only uses `self:On`, `self:OnWhile`, `self:Hook`, and timers given the module needs no `OnDisable`.
- A hook can't be removed, so add it with `self:Hook` / `self:HookScript`, which hook once and do nothing while the module is off. A hook made another way checks `module.enabled` itself.
- For events heard only while an option is on, declare them once at file load with `module:OnWhile(key, { EVENT = fn })` (or a function of `db` for `key`). A handler given to `OnWhile` mustn't also be added with `module:On`.

**Saved settings**

- Read settings from `module.db`, which reads the defaults passed to `ns.NewModule` for anything the player hasn't set.
- What the player sets is saved even when it equals the default, so changing a default in a later release never overrides their choice. Only a reset forgets it (`ns.ResetOption`, the undo arrow, Defaults, `module.db[key] = nil`).
- Code that puts a setting back by itself (a reset button, an invalid value) sets it to nil, never to the default.
- A default that is a table is data the module collects (prices, times): saved apart from settings and never reset by Defaults.
  - List a data key in `module.perCharacter` to save it for each character on its own.
  - List it in `module.perProfile` when it's a choice like a setting that each profile keeps its own of (Movable Windows' positions).
- Settings and `perProfile` data follow the profile in use. A switch turns the modules off and on again, so a module mustn't keep a reference to its settings or profile data past `OnDisable`.

**Text**

- Every player-facing string is `ns.L.KEY`, with the English in `Locales/enUS/` (the file for the module's category). Prefix a module's keys with its name (`FRIENDLYPLATES_...`).
- Use `%s` placeholders instead of joining pieces, since word order differs between languages.
- Player-facing text goes through `ns.Print` and stays short.
- Anything a module says in chat by itself (not in reply to a command) goes through `module:Print`, with `chat = true` in its defaults and `ns.ChatOption(description)` in `module.options`, so the player gets a Chat Messages checkbox.

## Touching Blizzard's UI

The goal is to add to Blizzard frames without tainting or breaking them.

- **Hook, don't replace:** `hooksecurefunc(obj, "Method", fn)`, `frame:HookScript("OnShow", fn)`. Never `SetScript` on a Blizzard object and never overwrite a Blizzard function or mixin method.
- **Never write fields onto Blizzard frames.** Keep per-frame state in a weak-keyed table (`setmetatable({}, { __mode = "k" })`).
- **Add your own regions and child frames** instead of changing Blizzard's. To hide Blizzard art, prefer `SetAlpha(0)` over `Hide()` / `SetParent`.
- **Calling Blizzard's own functions taints.** One of Blizzard's functions or mixin methods runs in our tainted call, so whatever it touches becomes ours. Call one only when nothing else does the job, never one that moves, shows, or sets up Blizzard's frames in combat, and check the source first.
- **Protected frames in combat.** Don't move, resize, reparent, show, or hide action buttons, unit frames, or anything secure in combat. Wrap the change in `ns.AfterCombat(fn)`.
- **Load-on-demand windows.** Many Blizzard windows are `Blizzard_*` addons. Hook them after they load: check `C_AddOns.IsAddOnLoaded` and otherwise wait for `ADDON_LOADED` with that name.
- **Look native:** `GameFontNormal` and related font objects, Blizzard atlases (`SetAtlas`), and Blizzard templates (`UIPanelButtonTemplate`, `UICheckButtonTemplate`, `BackdropTemplate` with Blizzard's own backdrop info), not custom art or fonts.
- **Options live in Blizzard's Settings panel,** not a custom window.

**Tooltip lines** we add look like Blizzard's Sell Price line:

- A white `Label:` on the left and its value at the right edge (`AddDoubleLine`), with details about the value in gray.
- Color carries meaning only (difficulty, age, class, faction), never decoration. Icons are Blizzard's art at text height (`|A:atlas:0:0|a`).
- On item tooltips, go through `ns.ItemTooltip`: facts with `OnInfo` and `AddInfo`, prices with `OnPrices` and `AddPrice`, so our lines sit together at the sell price.
- Recoloring Blizzard's own line beats adding a second one.

**Icons on the world map** all behave alike, through `ns.MapPins`:

- Ctrl+click puts the map pin on the icon (`waypoint = true`, or `ctrlClick`), as the game's own Ctrl+click does. Never another key for a waypoint.
- A module's own action on an icon is Shift+right-click (`shiftClick`), or a plain click (`click`) when the icon opens something.
- A module's entries in the map's filter menu go through `ns.WorldMap.AddFilter`, under the one Forever++ title. A layer of icons is one checkbox with its kinds in a submenu (`FilterLayer`). Never `Menu.ModifyMenu` on that menu directly.
- Click hints show only while Shift is held, and `ns.MapPins` writes them. A module gives the words for its own action (`shiftHint`, `clickHint`) and never adds hint lines or a hints option itself.

**Click hints**, on any tooltip, are written as Blizzard's own instruction lines are: green (`GREEN_FONT_COLOR`), in angle brackets, the keys and the click as separate words with no hyphen or plus, no full stop, one click to a line. `<Ctrl click to set a map pin>`, `<Shift right click to forget this node>` (the client's own: `<Ctrl click directly on the map>`, `<Right click for Frame Settings>`). On a map tooltip use `ns.MapTooltip.Hint`. Prose in Settings descriptions keeps "Ctrl+click". A tooltip that is a legend of several clicks (the Minimap Button's) lists the action on the left and the click in green on the right, with the same words: "Click", "Right click", "Shift click", "Drag".

## Settings

`Settings/` builds every page from what modules declare. Modules don't create Settings UI themselves, except a `BuildPage` tool page drawn with `ns.SettingsKit`. "Add a module" in `README.md` has the step-by-step, and [docs/settings.md](docs/settings.md) has every rule below in full.

### Pages

- Keep the sidebar short: Modules (the top Forever++ entry), Profiles, tool pages (`BuildPage`, named by `module.pageTitle` or the title), Changelog, About.
- A module never gets a sidebar entry for its options. A tool page of a module the player turns on and off is in the sidebar only while it's on.
- The Modules page is the only place modules turn on and off. It lists them under their category, sorted by `module.title`. Clicking one shows its Enabled checkbox, `description` (kept to four lines), notices, options, and buttons.
- Give every module a `module.category`: `automation`, `character`, `chat`, `interface`, `items`, `map`, `quests`, `system`, or `units`. It's usually its folder but needn't be: the tools in `Modules/Tools/` are in `system`, Auto Quest in `automation`, Macro Icon Search in `character`, Movable Framerate in `interface`.

### What a module declares

| Field | What it does |
| --- | --- |
| `module.quickToggle = "loot"` | Puts it in that group of the Minimap Button's quick toggles by default (`loot`, `npcs`, `world`, `nameplates`, `gathering`, `other`). |
| `module.presets = { developer = { enabled, options } }` | What each preset does to it. Nothing elsewhere lists modules by name. |
| `module.alwaysOn = true` | A tool with nothing to turn off; no checkbox. |
| `module:IsAvailable()` | False at login keeps it off and out of Settings and `/fpp`. |
| `module.added = "x.y.z"` | The version it first ships in; marks it NEW. |
| `module.notice` | A gray row above its options (see Notices). |
| `module:Problem()` | True while it can't work: its name shows red. |
| `module.locked = true` | The game broke it outright: kept off, a padlock for a checkbox. |
| `module.actions` | Buttons after the options. One with a `section` sits at the top of that section. |
| `module:OnOptionChanged(key)` | Called when an option changes. |

A profile based on a preset reads the preset's values for whatever the player hasn't set. So anything asking whether a setting is "at its default" compares with `ns.BaseValue(module, key)`, never `module.defaults[key]`.

### Options

An option is `{ key, name, description }` in `module.options`, with its default in the defaults table. It is a checkbox, a dropdown with `choices`, or a slider with `min`, `max`, `step`, and `format`. Options are greyed out while the module is off, and one that isn't at its default gets an undo arrow by itself.

| Field | What it does |
| --- | --- |
| `requires = key` | Nests it under a checkbox option (or a dropdown, on while it isn't `"off"`). |
| `slider = key` | Puts a checkbox's slider in its row. |
| `shown = fn(db)` | Shows its row only while true. |
| `available = fn` | Greyed out while `fn()` is false (another addon, module, or client API it needs isn't there). Always give it `needs`. |
| `needs = text` | What an `available` option needs, shown in red in its tooltip while it's greyed out (`L.SETTINGS_NEEDS_ADDON`, `L.SETTINGS_NEEDS_MODULE`, `L.SETTINGS_NEEDS_CLIENT`). |
| `section` | The header it sits under (see Sections). |
| `added`, `changed` | The version it first shipped or last changed in; marks it NEW. Options of a new module aren't marked. |
| `cvar = "name"` | A checkbox that is one of Blizzard's own settings: it reads and sets that CVar and saves nothing of ours. Say so in its description. |
| `editMode = true` | Moves it into the module's Edit Mode dialog, for where and how its frame is laid out. |
| `debug = true` | Moves it to the Debug page (a checkbox or dropdown only), under its `section`. |
| `conflicts = { { key, when = fn(db), text } }` | A gray row under it while it and option `key` can't both work as set. With `module = "Name"`, `key` is another module's option. Put it on the newer or rarer of the two. |

- **NEW marks** stay until the player has clicked the module. A version after the last release in `Changelog.lua` isn't released yet, so those stay marked whatever was clicked.
- **Debug sections** are `L.DEBUG_SECTION_DIAGNOSTICS` (a look at the addon's state), `_TOOLS` (a check or capture that runs), `_PREVIEWS` (made-up content), `_LAYOUT` (guides), and `_LOGGING` (printing what it does). `module.debugActions` takes the same.
- **A `cvar` option** set in combat reads the player's choice until combat ends. Prefer it to a notice when the setting is a plain on/off the module's options would naturally include.

### Notices, problems, and locks

- **Notice:** a module that silently depends on a Blizzard setting sets `module.notice`, a gray row with a button that turns the setting on. For a CVar, use `ns.CVars.OffNotice`, one notice per CVar. `module.notice` can be a list.
- A notice with no `button` only says why the module does less. One with no `shown` is always there: put a module's warnings and limits (out of combat only, an estimate) in one, not in its description.
- Give each thing one way in: a notice's tooltip says what doesn't work, not where else to turn it on, and a description doesn't repeat a notice.
- **Problem:** a module that has found it can't work gives `module:Problem()`, with a notice saying why, and calls `ns.RefreshSetting(module.name)` when that changes.
- **Locked:** `module.locked = true` keeps it off whatever was saved. Settings shows only its description and notices. It says nothing in chat about it.
- **QuestieDB:** a module that needs it calls `ns.QuestieDB.Require(module)` as its file loads instead of setting these itself.

### Sliders

Use the same units and steps for the same kind of thing.

| Kind | Unit | Range |
| --- | --- | --- |
| A mark on an item or action button icon | px (`L.ICONMARK_PIXELS`), `ItemButtons.SizeOption` | 8 to 32, step 2 |
| Padding | px, `ItemButtons.PaddingOption` | 0 to 10, step 1 |
| Nameplate parts, Edit Mode scale | `%d%%` | 50 to 200, step 10 |
| Icons on the world map | `MapPins.SizeOption`, `OpacityOption`, `ContinentOption` | 50 to 200, step 10; opacity 10 to 100 |
| Opacity | `%d%%` | step 5 |
| Times | `ns.Text.Seconds`, `Minutes`, `Hours` | |

Pixels are for something on an icon or frame of a known size. A percent is for a size that follows something the game or the player sizes.

### Sections

For a module with more than about five options, give them a `section` (an `ns.L` string). Each change of section starts a header, and options before the first section go under Options. List options in the order they should show: a general section first, the options most players change before the rare ones, and Chat Messages last.

## Git

- Conventional Commits, lowercase: `type(scope): summary`, for example `feat(tooltip): show item level on gear`. Scopes: `core`, a module name in lowercase, `docs`, `toc`.
- Never commit SavedVariables, zips, or anything from the client folder.
- "Commit" means verify, stage, commit, and confirm a clean tree. Don't push unless asked.

## Verification

`tests/` holds the offline tests. They need only Lua 5.1, no client:

```
lua5.1 tests/run.lua          # every spec
lua5.1 tests/run.lua store    # the specs with that in their name
```

- A spec in `tests/spec/` covers each area of pure-logic `Lib/` code, Core's module lifecycle on stub frames and a stub clock, and the public API.
- Checks across the addon:
  - `globals`: no file writes a global the Lua rules don't allow, and every global it reads is Lua's or in `.luarc.json`.
  - `locales`: every `L.KEY` the code uses is defined in `Locales/enUS/`.
  - `docs`: every Lib file has a row in the Lib tables here and a place in `docs/architecture.md`, and every click hint is written as Blizzard's are.
  - `modules`: every file loads offline, makes no frame, hook, timer, or event listener as it loads, and every module's settings are well formed.
  - `release`: the TOC's version, `Changelog.lua`, and `CHANGELOG.md` agree.
  - `rules`: each file's first line, no removed Classic globals, no `COMBAT_LOG_EVENT_UNFILTERED`, `WOW_PROJECT_ID`, `print`, and `IsInInstance` only where allowed, no tabs or trailing spaces.
- Each spec gets a fresh copy of the addon with the real `Lib/` and `Locales/enUS/` files against stubbed WoW globals, so specs can't depend on each other. A Lib file that caches a global at load needs that global stubbed before it loads. `tests/README.md` says how to write one.
- What to add: a check when you change or add Lib logic that has no frames in it, a spec when you add a Lib file, and a check in the `core_*` specs (each on a fresh real Core, `T.Core()`) when you change how Core turns modules on and off. Don't test frame or UI code.
- CI also runs wowlua-ls (`wowlua_ls check .`) for types and secret values. `tests/wowlua.lua` compares its findings with `tests/wowlua-baseline.txt` and fails on a new one. A new finding is usually a real problem: fix it, or, when it's the checker's mistake, add it with `--update` and say why in the commit. Fixing one means taking it out of the baseline too (`--update` does it).

Before calling a change done:

1. Run `tests/run.lua`, and check syntax where a Lua 5.1 interpreter or LuaLS is available (`luac -p` on changed files). With wowlua-ls at hand, run `wowlua_ls check . > out.txt 2>&1` and `lua tests/wowlua.lua out.txt` too.
2. In the Forever client: `/reload`, then check `/fpp` lists the module, toggle it off and on, and check BugSack and `Logs\FrameXML.log` for errors.
3. For anything that touches unit, aura, cast, or combat data, also test in combat, where secret values apply.
4. Report exactly what was checked. Name every step that still needs someone in the live client, and never claim in-game testing that didn't happen.
