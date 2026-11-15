# Settings in depth

Every rule and behavior of the Settings pages, in full. `AGENTS.md` has the short tables; this has the reasons, the edge cases, and the examples.

`Settings/` builds every page from what modules declare; modules don't create Settings UI themselves (except a `BuildPage` tool page, drawn with `ns.SettingsKit`). Details are in "Add a module" in `README.md`.

## The sidebar

- Keep the sidebar short: the top Forever++ entry is the Modules page, then Profiles, then tool pages (`BuildPage`, named by `module.pageTitle` or the title), Changelog, and About.
- A module never gets a sidebar entry for its options, and a page of a module the player turns on and off is in the sidebar only while it's on.

## The Modules page and categories

- The Modules page is the only place modules turn on and off.
- Give every module a `module.category`: `automation`, `character`, `chat`, `interface`, `items`, `map`, `quests`, `system`, or `units` (anything else lands under Other).
- The categories show in alphabetical order.
- A module's folder is usually its category but needn't be: the tool pages in `Modules/Tools/` are in `system`, Auto Quest (`Modules/Quests/`) is in `automation`, Macro Icon Search (`Modules/Interface/`) in `character`, and Movable Framerate (`Modules/System/`) in `interface`.
- It appears in the list under that category's label, sorted by `module.title`.
- Clicking it shows its title with an Enabled checkbox, its `description` (kept to four lines), notice, options, and buttons beside the list.

## Where else a module shows: quick toggles and presets

- A module says for itself where else it shows: `module.quickToggle = "loot"` (or `npcs`, `world`, `nameplates`, `gathering`, `other`) puts it in that group of the Minimap Button's quick toggles by default (the player adds any other module, or takes one out, with the Customize button in its settings, whose menu lists every module by its category from `ns.SettingsKit` and keeps their picks as the Minimap Button's data), and `module.presets = { developer = { enabled = true, options = { key = value } } }` is what each preset (`Lib/Presets.lua`; today only Developer's Defaults) does to it: `enabled` true or false, and option values that fit their options.
- A preset that extends another needs only where it differs.
- Nothing elsewhere lists modules by name.
- A profile based on a preset reads its values for whatever the player hasn't set, so anything asking whether a setting is "at its default" (the undo arrow, a profile's counts) compares with `ns.BaseValue(module, key)`, never `module.defaults[key]`.

## Tools and availability

- A tool with nothing to turn off sets `module.alwaysOn = true` and gets no checkbox.
- A module that only makes sense on some clients gives `module:IsAvailable()`.
- When that's false at login it stays off and out of Settings and `/fpp`.

## Options

- Options go in `module.options` (`{ key, name, description }`, default in `defaults`): a checkbox, a dropdown with `choices`, or a slider with `min`, `max`, `step`, and `format`.
- `requires = key` nests an option under a checkbox option (or a dropdown, on while it isn't "off"), `shown = fn(db)` shows an option's row only while it's true (one that only matters with others set a certain way, like Player Nameplates' Icon and Level), and `slider = key` puts a checkbox's slider in its row, to keep long option lists short.
- They're greyed out while the module is off, and one with `available = fn` while `fn()` is false (another addon or module it needs isn't on, or the client lacks what it needs).
- An `available` option also sets `needs`, a line saying what's missing (`L.SETTINGS_NEEDS_ADDON` with the addon's name, `L.SETTINGS_NEEDS_MODULE` with a module's title, or `L.SETTINGS_NEEDS_CLIENT`): its tooltip shows it in red under the description while the row is greyed out, so the row explains itself. Today: Dungeon Maps and Map From (DungeonJournal), Use Auctionator's Prices (Auctionator), Quest Nameplates' Item Drops (QuestieDB), Compass Bar's Gathering Nodes (Gathering Map) and Rares and Treasures (the client), and the Minimap Button's error keys (Error Catcher).
- A whole module that can't work without another addon is locked instead, with a padlock and `module.lockedText` (Quest Pins without QuestieDB, through `ns.QuestieDB.Require`).
- `editMode = true` moves one of a module with an Edit Mode frame (`ns.EditMode.RegisterModule`) into that frame's Edit Mode dialog and right-click menu, for settings about where and how the frame is laid out (Loot Rolls' grow and spacing).
- The Modules page shows a gray row saying they're in Edit Mode instead of them, and keeps what the module does.
- `debug = true` moves one to the Debug module's page (a checkbox or a dropdown only), where its `section` (`L.DEBUG_SECTION_DIAGNOSTICS` for a look at the addon's state, `_TOOLS` for a check or capture that runs, `_PREVIEWS` for made-up content that shows a module, `_LAYOUT` for guides drawn to line things up, or `_LOGGING` for printing what it does, and the same on `module.debugActions`) picks the header it sits under among every module's.
- One without goes under its module's title, after those.
- `added = "x.y.z"` (on a module or an option) is the version it first ships in, and `changed` (on an option) the version it last changed in a way players should notice.
- Either marks it NEW on the Modules page until the player has clicked its module.
- A version after the last release in `Changelog.lua` isn't released yet, so only a development copy has it: those stay marked NEW whatever was clicked, so everything added since the release shows until it ships.
- Options of a new module aren't marked.
- A checkbox with `cvar = "name"` is one of Blizzard's own settings shown among the module's: it reads and sets that CVar, saves nothing of ours, takes the client's default, and Defaults leaves it alone (Coordinates' Player Coordinates).
- Set in combat, it reads the player's choice until combat ends, when the CVar changes and the module hears of it.
- Say so in its description, and prefer it to a notice when the setting is a plain on/off the module's options would naturally include.
- An option with `conflicts = { { key, when = fn(db), text } }` gets a gray row under it while `when(db)` is true, saying it and the option `key` can't both work as set (Movable Windows' Reset Key and Reset Click matching the drag), with a button that scrolls to that option and lights it up (no button when that option is the row right above or below).
- Put it on the newer or rarer of the two, not both.
- With `module = "Name"`, `key` is another module's option and `when(db, otherDB)` gets that module's settings too (Appearance Icons' Corner against Upgrade Arrows' and Already Known's marks): the row shows only while both are on, and its button opens that module at the option.
- Settings reads the other module, so the module itself still doesn't.
- Buttons go in `module.actions`, after the options.
- One with a `section` sits at the top of that section instead, under its header (Gathering Map's Share and Forget buttons over its Chat Messages).
- React to changes in `module:OnOptionChanged(key)`.
- An option that isn't at its default gets an undo arrow at the end of its row that sets it back, so a module needs nothing for it.

## Notices, problems, and locks

- A module that silently depends on a Blizzard setting sets `module.notice`: a gray row above the module's options while that setting is off, with a button that turns it on.
- For a CVar, use `ns.CVars.OffNotice`, one notice per CVar so each gets its own button.
- Give each thing one way in: a notice's tooltip says what doesn't work, not where else to turn it on, and a description doesn't repeat a notice.
- A notice with no `button` only says why the module does less (Error Catcher while another addon catches errors), or, with no `shown`, is always there: put a module's warnings and limits (out of combat only, an estimate) in one, not in its description, as Macros does.
- `module.notice` can be a list of notices.
- A module that has found it can't work (the game stops answering what it asks) gives `module:Problem()`, true while that lasts: its name shows red in the Modules list, on or off, a notice says why, and it calls `ns.RefreshSetting(module.name)` when that changes.
- It may turn itself off then.
- A module the game has broken outright sets `module.locked = true`: Core keeps it off whatever was saved and `ns.SetEnabled` won't turn it on, its checkbox is a padlock, and Settings shows only its description and notices, none of its options or buttons, until a fix or its removal.
- It says nothing in chat about it.
- A module that can't work without the QuestieDB addon calls `ns.QuestieDB.Require(module)` as its file loads instead of setting these itself: it gets QuestieDB's notices, a red name while QuestieDB is missing, off, or the wrong version, and while it's missing or off it's locked the same way, its padlock's tooltip (`module.lockedText`) saying to get QuestieDB.

## Sliders

- Sliders use the same units and steps for the same kind of thing.
- Pixels (`L.ICONMARK_PIXELS`, "%d px") for something on an icon or frame of a known size: a mark on an item or action button icon (`ItemButtons.SizeOption`, 8 to 32 in steps of 2, scaled to the icon it's on by `MarkSize`), padding (0 to 10 in steps of 1, `ItemButtons.PaddingOption`), and minimap icons.
- A percent ("%d%%") for a size that follows something the game or the player sizes: nameplate parts (50 to 200 in steps of 10, on top of the game's nameplate size), Edit Mode scale (50 to 200 in steps of 10), a share of the text's size (Forever Quest Icons).
- Opacity is a percent in steps of 5.
- Times go through `ns.Text.Seconds`, `ns.Text.Minutes`, or `ns.Text.Hours`.

## Sections

- For a module with more than about five options, give them a `section` (an `ns.L` string).
- On the Modules page each change of section starts a header (options before the first section go under Options).
- So list options grouped in the order they should show: a general section first, the options most players change before the rare ones, and Chat Messages last.
- Nest an option that only matters while another is on with `requires`.
