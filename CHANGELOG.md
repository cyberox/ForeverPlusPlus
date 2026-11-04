# Changelog

What changed in each release of Forever++. The same notes show in game under Settings > AddOns > Forever++ > Changelog, from [`ForeverPlusPlus/Changelog.lua`](ForeverPlusPlus/Changelog.lua); change both together.

## Unreleased

### Added

- Other addons can read what Forever++ knows through `ForeverPlusPlusAPI.v1`: auction prices, what disenchanting an item gives and is worth, the class, level, race, and guild of players it has seen, class and level colors, dungeon and raid levels, gathering skills, and which modules are on, with a callback when prices change. See [docs/api.md](docs/api.md).

## 1.0.0-beta.1 (2026-11-02)

### Added

- **Chat Levels**: a new module that shows each player's level before their name in chat, colored like a quest of that level. Forever++ remembers players you group with, your guild and friends, your `/who` results, and players you see nearby, so the level shows for players far away too. Off by default.
- **Class Colors**: the new Offline Friends option (on by default) colors offline friends in the friends list by the class Forever++ last saw them as.
- **Gear Probe**: a new Run button under Testing in the Debug module's settings (and `/fpp gearprobe`) that saves what the client says about your gear, its item comparison, your talents, and your stats, for the developers.
- **Item Tooltips**: the new Disenchant line (off by default) shows what disenchanting green, blue, and purple gear gives on average, priced from Auction Prices while that's on, or else the material it most likely gives. Hold Shift for every outcome and its chance.
- **Item Tooltips**: the new Color Stats option (on by default) shows each stat on gear in its own color, including Equip: bonuses like hit and spell power.
- **Item Tooltips**: Auction Prices can use Auctionator's prices instead of scanning: turn on Use Auctionator's Prices. Your own saved prices are kept for when you turn it off.
- **Macros**: a new module that makes macros shared by your characters, each with its own checkbox, and deletes them when they're turned off. The first is Smart Buff: it casts the buff your friendly target (or you) should get from you at the best rank you know, skips buffs they already have or a stronger one, buffs you instead when they can't get anything from you and says why, and warns in combat when it can't change to fit a new target. Off by default.
- **Minimap Button**: the new Swap Clicks option (on by default) opens the quick toggles with a click and settings with a right-click, and Error Keys on Left-Click picks which click the error keys go on. Menu Side opens the quick toggles to the left or right of the cursor.
- **Upgrade Arrows**: a new module that puts Blizzard's green arrow on gear that beats what you wear, judged by stat weights for your class and main talent tree (or one you pick, with a Feral Bear profile for Druids). It marks your bags and bank, merchants, loot and loot rolls, the best quest reward, and the auction house, each with its own checkbox. A ring is judged against your weaker ring and a two-hander against both hands. Pick the arrow's corner, size, and padding, and show the percentage beside it or in the tooltip. Options show every item's score, mark worse gear with a red arrow, judge gear up to 5 levels above yours, leave profession tools and the reagent bag unmarked, and hide small differences. The weights start from a template per talent tree, and the Stat Weights page (`/fpp weights`) has a slider per stat, per profile, with Import and Export of Pawn strings. Off by default.

### Changed

- Item marks, tints, and tooltip lines do much less work, so bags open more smoothly while leveling.
- **Auto Stow**: also puts away weapons you draw yourself, once they've been out for the Delay. Pressing Sheath starts the Delay again.
- **Auto Weapon Buff**: using a stone, oil, poison, or lure from an action bar puts it straight on your weapon too. Not in combat.
- **Chat Copy**: the window looks like Forever++'s other windows.
- **Item Tooltips**: Sell Price also shows on quest reward tooltips, so you can see what each choice sells for.
- **Minimap Node Icons**: costs much less while you play: it checks the minimap about once a second instead of ten times, and does nothing while Find Herbs and Find Minerals are off. A new dot may take a moment longer to get its icon.
- **Profiler**: also times work modules put off for a moment, like redrawing bag marks.
- **Quest Tracker**: the background is a little darker by default, 40% instead of 30%, unless you set its Opacity yourself.
- **Settings**: a module's warnings and limits sit in a gray line under its description on the Modules page.
- **Settings**: option names on the Modules page have more room, so they wrap less, and NEW labels sit just after the checkbox.
- **Settings**: Console Variables, Profiler, and Debug are modules under a new Tools category, off by default (on in Developer's Defaults). Debug's options and buttons are in its own settings on the Modules page. Turned off, a tool's page and commands go away, and Debug's options go back to their defaults.
- **Whisper Window**: shows the guild of the player you're talking to, and their level, race, and class from when Forever++ last saw them.

### Fixed

- An error in one module no longer breaks the Blizzard window or tooltip it hooks, or other modules' changes to it.
- Marks, tints, and arrows on an open loot window show as soon as you turn their module on.
- The buttons Forever++ adds beside the chat window sit below Blizzard's voice chat Deafen and Mute buttons instead of on top of them.
- Updating from 0.8 puts Blizzard's map coordinate settings back the way you had them, and gives the Quest Tracker's background and the waypoint arrow today's defaults if you never changed them.
- Forever++'s chat messages start with the chat timestamp while timestamps are on, like the game's own lines.
- **Already Known**: items on a vendor's Buyback tab no longer get the marks of the vendor's own items.
- **Already Known**: mail in the inbox and open letters get marks again after a game update broke them.
- **Auto Screenshot**: reaching Neutral with a faction counts as a step up and takes a screenshot.
- **Auto Stow**: no longer draws your ranged weapon when it meant to put your melee weapon away.
- **Chat Copy**: turning Click Timestamps off no longer brings back chat lines that had faded out.
- **Chat Font**: turning the module off gives the Communities and GM chat windows their font back too.
- **Commands**: `/fpp reset` turns every module off before it wipes the settings, so game settings a module changed go back to your own. In combat, it waits until combat ends.
- **Commands**: a `/fpp` command whose module is off says so in chat instead of opening Settings.
- **Fishing Cast**: changing Louder Bobber while the module is off no longer changes your sound volumes.
- **Flight Timer**: bag items and action buttons no longer get a Flight Time line while the old flight map is open.
- **Gathering Tracking**: Find Minerals or Find Herbs comes back on after dying again: it keeps trying for a few seconds after you come back to life.
- **Hide Beta Feedback**: turning the module off always brings the feedback button back.
- **Item Tooltips**: the Auction Prices scan no longer spins forever when the auction house stops answering: it asks again, then finishes with the prices it has.
- **Item Tooltips**: an auction price over 214,748 gold no longer causes an error when it's saved.
- **Item Tooltips**: the lines stay above Forever's "Press F6" line on items like junkboxes.
- **Persistent Chat**: chat no longer starts fading again after you leave it with a gamepad.
- **Quest Tracker**: turning the module on or off keeps the text size you set in Edit Mode.
- **Settings**: the About page lists the commands of the modules that are on now, not the ones that were on when it first opened.
- **Settings**: the About page's command list scrolls, and a long description wraps instead of running off the edge.
- **Social Button**: Text to Speech and voice chat alerts no longer sit on top of the chat buttons.
- **Spell Ranks**: spells in macros on your action bars get the right badge.
- **Spell Ranks**: the line about action bar spells with a higher rank shows only after you learn a spell or level up, not at every login.
- **Spell Ranks**: the warning badge sits fully inside the button's corner, above its icon, border, and cooldown.
- **Tooltips**: Class Color colors the class name on Russian, Korean, and Chinese clients too.
- **Waypoints**: the arrow sits a little lower by default and always stays inside the game window. If you moved it in Edit Mode, it stays where you put it.
- **Whisper Window**: a whisper you start by a player's name without their surname goes to your conversation with them, and Hide Whispers in Chat no longer leaves a whisper tab empty.
- **World Map**: Points of Interest no longer marks a ley line in the wrong place while an older ley line buff is still on you.
- **World Map**: Unexplored Areas no longer draws straight lines over the edges of explored areas.

## 0.9.0 (2026-10-14)

### Added

- **AddOns List**: the new AddOn Sets option (off by default) adds a Sets dropdown beside Disable All, to save which addons are on under a name and turn that set back on later.
- **Auto Decline**: the new Guild Invites and Guild Charters options (off by default) turn down guild invites and requests to sign a guild charter, even from friends and guildmates.
- **Comprehend Scrolls**: a new module for Mages: right-click a scroll you read with Comprehension in your bags to cast Comprehend Scroll on it, without opening the spellbook. Not in combat. On by default; it does nothing for characters without the spell.
- **Combat Alert**: the new Play Sound option (off by default) plays the raid warning sound as you enter combat and a soft chime as you leave, for when you're looking somewhere else.
- **Fishing Cast**: the new Louder Bobber option (off by default) turns sound effects up and music down while you fish, so the splash is easy to hear, and puts your own volumes back after you stop, even after a reload or disconnect mid-cast.
- **Item Tooltips**: the new Repair Cost line (off by default) shows what repairing damaged gear costs, on gear you wear or carry, without a merchant's repair cursor.
- **Flight Timer**: the new Sound on Landing option (off by default) plays the ready check sound a few seconds before you land, on a flight you've taken before, so you can tab out on long flights.
- **Forever Quest Icons**: the new Quest Details option (on by default) puts the icon after the quest's name at the top of its details, in the quest window and on the map.
- **Minimap Node Icons**: a new module that puts the herb's or ore's own icon on each tracking dot on the minimap while Find Herbs or Find Minerals is on. Off by default. Its Tint Unusable option (off by default) turns an icon red while your skill is too low to gather it, and Gray Out Trivial (off by default) turns it gray once gathering it no longer raises your skill.
- **NPC Nameplates**: the new Skip Pets, Skip Totems, and Skip Companions options (off by default) leave players' pets and minions, totems, or companions with Blizzard's own nameplate instead of a name and title.
- **Profiler**: a new page in Settings (`/fpp profile`) that records how much CPU each module takes, heaviest first, beside Forever++'s total CPU and memory. A module made of parts folds open to show what each part takes. Nothing is timed until you press Record.
- **Quest Levels**: a new module that shows a quest's level before its name, like the quest log's [12], in a quest giver's list and at the top of the quest's details. On by default. Its Color by Difficulty option (off by default) colors the level gray through red by how it compares with yours.
- **Quest Tracker**: the new Current Zone Only option (off by default) tracks only the quests of the zone you're in, and tracks the others again when you get there. The quest your map follows always shows.
- **Talent Planner**: the new Level-Up Reminder option (off by default) says in chat which talent your plan takes next when you gain a talent point.
- **Tooltips**: the new Hide Health Bar option (off by default) hides the green health bar under player and NPC tooltips.
- **Unusable Items Tint**: the new Auction House and Loot options (off by default) tint red the items you can't use in the auction house's search results, and in the loot window and on loot rolls.
- **Waylaid Crates**: a new module for filling Waylaid Crates. Its Waylaid Crates entry in the auction house's categories lists every item your crates still need, less what's already in your bags and bank.
- **Waypoints**: the new Follow Selected Quest option (on by default) points the arrow to the quest selected on the map instead of your map pin, and back to the pin when no quest is selected. Its Show Quest Name option (on by default) shows the quest's name under the distance.
- **Waypoints**: the new Point to Corpse option (on by default) points the arrow to your corpse while you're a ghost, ahead of a quest or your map pin, and back to them once you're alive.
- **Waypoints**: the new Clear Pin on Arrival option (off by default) takes your map pin away once you reach it.
- **Whisper Window**: a new module that keeps whispers in a messenger window of their own: your conversations on the left with unread counts, and the one you pick on the right with who they are and a box to reply in. Battle.net whispers and the ones you send from chat go there too, saved for each character. Open it with `/fpp whispers` or the button beside the chat window, which pulses while whispers wait. Off by default.
- **World Map**: Points of Interest's new Ley Line Icon option (Portal by default) draws ley lines as the blue swirl the minimap shows for one, or as the purple orb they were before.
- **XP Bar Text**: the new Fill Bar with Ready Quests option (on by default) fills the experience bar on from your XP in green with what your quests ready to turn in will give, like rested XP.
- **XP Bar Text**: the new Detailed Tooltip option (on by default) adds to the bar's tooltip the XP left to level, your rested XP, the XP of your quests, and your XP per hour and time to level since you logged in.
- **XP Bar Text**: the new Green When Quests Level You option (on by default) turns off the green quest XP text shown once turning those quests in would level you.
- **Auto Release**: the new Skip Key option (None by default) lets you hold a key while you're dead to stay where you fell.
- **Settings**: an option you've changed has an undo arrow at the end of its row that sets it back to its default, and its tooltip says what the default is.
- **Settings**: the Changelog page has a By Module checkbox (on by default) that groups a release's notes under their modules instead of Added, Changed, and Fixed.

### Changed

- **Auto Gossip**: off by default for new installs, and so is Other NPCs. If you already use it, it stays as you had it.
- **Character Window**: with Colored Title on, the game's own "Level 18 Mage" line at the top of the window is hidden, since the title already shows your level, and your character's background fills the empty strip it sat on, with the zoom and rotate buttons and your character moved up into it. Your pet's line on the pet pane stays.
- **Auto Weapon Buff**: an item it doesn't know yet, or a stone on a fist weapon, works from a right-click too once you've put it on that kind of weapon by hand, for every character.
- **Quest Tracker**: Fade in Combat has a Combat Opacity slider, from 0 to 80%, for how faint the tracker gets in combat. It starts at 30%, as before.
- **Waylaid Crates**: Item Tooltips' Waylaid Crate Costs option moved here as Bundle Costs, keeping your choice.
- **World Map**: Coordinates follows Blizzard's coordinate settings under Gameplay > Interface instead of its own checkboxes, which turned them back on at every login.
- **World Map**: dungeon levels come from the game's dungeon finder, and Forever dungeons it lists that Forever++ didn't know get their names and levels in map tooltips.
- **World Map**: Zone Info shows the game's own level range for a zone when it has one. Points of Interest places flight masters where a flight master's map shows them and adds ones its list lacks, and Unexplored Areas adds areas its art lacks once one of your characters explores them.
- **Quest Tracker**: Font Size is gone: Edit Mode's Text Size sets the tracker's size.
- **Profession Tooltips**: on a lockbox whose tooltip already says what Lockpicking it needs, colors that line instead of adding a second one, and remembers the skill, so a box Forever changed shows the right number.
- **Settings**: the Modules page has new Character, Quests, System, and Units categories, listed in alphabetical order.
- **Settings**: Hold Shift to Skip and Hold Shift to Watch are now Skip Key and Watch Key dropdowns (Shift, Ctrl, Alt, or None), like Auto Quest's.
- **Settings**: options look and read the same across modules: Item Tooltips' parts each have an Enabled checkbox, sliders are shorter, buttons that throw away data say Clear, and modules say when a Blizzard setting they need is off.
- **Settings**: Forever++ saves only the settings you change, so a better default reaches you, and saves talent plans and learned flight points for each character. Saved auction prices take about 60% less room. Everything you had carries over.
- **Commands**: `/fpp reset` asks first, and module names in `/fpp` match their titles, such as `/fpp toggle BagSlotCounter`.
- **Chat Copy**: copies everything the chat window holds. The Lines slider is gone, since a window keeps only its last 128 lines.
- **Chat History**: Lines Saved goes up to 125, about all a chat window holds.
- **Chat History**: saves each character's chat on its own, so an alt doesn't log in to another character's. The first character you log in with keeps the chat saved before.
- **Auto Screenshot**: Played Time on Level Up sits under Level Up and works only while Level Up is on, since it's for that screenshot.
- **Already Known**: the Loot option also marks known items on group loot rolls, before you choose Need or Greed.
- **Auto Sell Junk**: Keep Everything Buyable Back sells only as much junk as the buyback list has room for beside what you sold yourself, so an item sold by mistake stays buyable.
- **Auto Gossip**: learns which kind of NPC an option is for from the window it opens, so a banker, vendor, trainer, or flight master the game marks differently is picked by its own checkbox after you pick it once.
- **Auto Gossip**: also picks an NPC's one service when its other options are only small talk, so weapon masters open their training.
- **Bag Slot Counter**: the count turns orange when 4 or fewer slots are free. The new Color When Low option sets that number, or turns the colors off.
- **Currency Bar**: with nothing to show, it says how to track currencies instead of showing an empty box.
- **Error Catcher**: says on its Settings page, instead of in chat, when another addon such as BugGrabber is catching Lua errors, and leaves Blizzard's error window and blocked action popup to it.
- **Flight Timer**: the flight map tooltip's Flight Time line looks like the Sell Price line, with the time at the right. The new Tooltip Line option puts it back on one line, white or gray.
- **Profession Tooltips**: learns herbs and veins it doesn't know, and a skill Forever changed, from the game's own "Requires Herbalism" line, so it works in any language.
- **Minimap Button**: Shift-click it, instead of Shift-right-click, to see the errors, Ctrl-click it to clear this session's, and the new Alt-click clears every saved error after asking. Each key is an option: Show Errors Key, Clear Session Key (once Clear Key), and Clear All Key.
- **Minimap Button**: a tidier tooltip: the version beside the title, the error counts with the number at the right (this session's in red, saved ones in gold), then each click's action with its click beside it in green, such as Shift-Left-Click, leaving out a key set to None.
- **Minimap Button**: the right-click menu also turns Auto Decline, Auto Dismount, Auto Gossip, Auto Release, Auto Repair, Auto Screenshot, Minimap Node Icons, Movable Framerate, and Skip Cinematics on and off, grouped by what you're doing (Vendors and Loot, NPCs and Quests, Out in the World, and Other).
- **Short Channel Names**: the Style dropdown also offers initials ([LFG] for LookingForGroup) and the name without its zone ([General]), alone or after the number. Number and Initials ([1. LFG]) is the new default.
- **Short Channel Names**: the new Guild, Party, and Raid option (on by default) also shortens [Guild], [Officer], [Party], [Raid], [Raid Warning], and [Instance] to [GD], [O], [P], [R], [RW], and [I].
- The Error Catcher and Chat Copy windows close with Escape, like Blizzard's windows.
- Buff Timers, Waypoints, Quest Tracker, Quest Nameplates, Player and NPC Nameplates, and Already Known use less CPU: they look the same and redo their work only when something changed.

### Fixed

- **XP Bar Text**: Blizzard's own XP text no longer shows through under ours after a reload.
- **Class Colors**: hostile NPCs' health bars are red, like their names, instead of sometimes yellow or green.
- **Commands**: `/fpp toggle` on a tool, such as Self Test, says it's always on, instead of that it's off.
- **Profession Tooltips**: recolors the "Requires" line on nodes and creatures in languages that number its parts (such as "%1$s"), which it missed before.
- **Character Window**: with Side Tabs on, your level shows above your character again, and your pet's on the pet pane, where the game now puts them.
- **Character Window**: the Skills tab shows your equipped weapons' skills in green right after you log in, instead of only once you change a weapon or reload.
- **Character Window**: durability bars are read again each time the window opens, so they're right after you log in.
- **Auto Decline**: asks for your guild's roster again once your guild is known after logging in, so guildmates' duels aren't declined while Allow Friends and Guild is on.
- **Gathering Tracking**: after logging in, waits a few more seconds for the tracking list to fill before giving up on turning tracking back on.
- Chat Font, Persistent Chat, Short Channel Names, and Chat Copy's Click Timestamps also work in whisper windows popped out into their own tab.
- **Player Nameplates**: Battle.net friend icons and guildmate colors update as those lists change, and names on player and NPC plates get smaller again when you make nameplates smaller.
- **AddOns List**: shows which addons are on for the character picked in the dropdown, or for All, instead of always for you.
- **Item Tooltips**: Auction Prices turned on with the auction house open can scan it without reopening it.
- **Buff Timers**: Edit Mode's example buffs and debuffs don't keep an old clock.
- **Class Colors**: turning name backgrounds off puts back the target frame's own color.
- **Auto Weapon Buff**: right-clicking a stone or oil in your bags at the guild bank deposits it instead of putting it on your weapon.
- **Auto Decline**: Allow Friends and Guild lets party invites from guildmates through even before your guild roster has loaded.
- **World Map**: Points of Interest no longer causes an error each time a Skyborne casts a spell in combat. A Read Ley Line or Skysight cast in combat saves its spot once combat ends.

## 0.8.4 (2026-10-11)

### Fixed

- **Item Tooltips**: Waylaid Crate Costs shows each bundle's price again, instead of No price, which 0.8.2 broke.

## 0.8.3 (2026-10-11)

### Fixed

- **Auto Weapon Buff**: right-clicking a stone, oil, poison, or lure in your bags puts it on your weapon again, which 0.8.2 broke.

## 0.8.2 (2026-10-11)

### Changed

- **Auto Weapon Buff**: when no equipped weapon can take the item, like a weightstone with only blades, it says so in red at the top of the screen instead of bringing up a cursor. On by default; turn it off with Warn When No Weapon Fits.
- **Buff Timers**: Show Clock has an Under 1 Minute choice, for a clock only on auras about to run out.
- **Character Window**: the new Equipped Weapon Skills option (on by default) colors the Skills tab's bars green for the weapons you have equipped, instead of blue.
- **Chat History**: no longer saves whispers, so they aren't written to your saved settings file.
- **Console Variables**: laid out like the Modules page: Changed, All, and the game's own categories on the left, each with how many match the search, and their console variables beside it with each one's help text under its name. The Changed group replaces the Changed Only checkbox.
- **Item Tooltips**: the new Waylaid Crate Costs option shows beside each bundle a Waylaid Crate takes what buying it costs at the auction house, from your scanned prices. It can go under each bundle instead, or be turned off.
- **Quest Tracker**: the new Sort by Level option (off by default) lists tracked quests by level, lowest or highest first, instead of in the order you tracked them. It waits for combat to end.
- **Settings**: the Changelog page lists the releases on the left, like the Modules page, with the selected one's notes beside it in larger text. Releases since the version you last saw are marked NEW, and a search box shows only the changes that mention what you type.
- **Talent Planner**: counts the Legacy perk Talented: with it, plans get talent points from level 5 instead of 10, still 51 at most.
- **World Map**: Points of Interest draws spirit healers as a glowing spirit instead of a tombstone, so they aren't mistaken for your corpse.

### Fixed

- **Already Known**: the Tint look no longer turns white the red icons of merchant items you can't use, and the bags only look up items that can be known, like recipes, mounts, and pets.
- **Auto Decline**: a friend or guildmate you let through gets Blizzard's usual invite popup again instead of one showing only their name, and a declined group finder invite closes its popup too.
- **Auto Screenshot**: a second shot right after another no longer shows the interface with Hide Interface on, and a shot the game never reports no longer stops the ones after it.
- **Auto Weapon Buff**: a window over your bags no longer has its clicks taken by a stone, oil, poison, or lure under it.
- **Buff Timers**: never shows a negative time, like -1:59, on an aura about to go away.
- **Commands**: `/rl` and `/clear` are left to another addon that has them even after you've typed a slash command, and turning one on says so in chat.
- **Currency Bar**: stays on screen on smaller screens, and Reset Position puts it back where it starts.
- **Error Catcher**: a link or color in an error shows as plain text in its chat message, and it keeps the last 100 errors with shorter stacks, so its saved file stays small.
- **Flight Timer**: turning Bar on during a flight shows the bar for the rest of it.
- **Hide Beta Feedback**: turning it off puts the quest windows' feedback alert back as it was.
- **Hide Filter Reset**: turning it off gives the mouse back only to the parts that had it before.
- **Item Tooltips**: your own auction house searches keep an item's lowest price instead of the last one listed.
- **Player Nameplates**: a player who turns hostile, like in a duel, gets Blizzard's own nameplate back, health bar and all. So does an NPC that turns hostile with NPC Nameplates on.
- **Player Nameplates**: puts your game settings back at login if it was turned off in combat just before a reload. So do NPC Nameplates, Auto Dismount, and World Map's Coordinates.
- **Quest Nameplates**: an objective that needs 100 of something shows as 37/100, not 37%. Creatures that showed up during a fight get their quest icon once it's over.
- **Recipe Colors**: turning it off clears the tint from every recipe row, not only the ones on screen.
- **Settings**: the Modules page no longer errors when it opens on a module marked NEW.
- **Settings**: Recommended Defaults and Developer's Defaults keep where you moved things and their size in Edit Mode, and reset only the options.
- **Short Channel Names**: turning it off gives channels already in chat their full names again.
- **Social Button**: turning it off no longer leaves Chat Copy's button above the chat window.
- **Talent Planner**: refuses a shared plan with more than 51 points, which could freeze the game, and a shared plan's name can't carry colors, icons, or links.
- **Unusable Items Tint**: no longer tints recipes you can learn because of the item they make, such as plans for mail armor or for gear above your level.
- **Waypoints**: `/way` is left to TomTom or another addon that has it even after you've typed a slash command, and turning Waypoints on says so in chat.
- **World Map**: Zone Info shows herb and ore names in your language the first time, instead of in English until the map changed.

## 0.8.1 (2026-10-10)

### Fixed

- **Auto Weapon Buff**: puts the buff on your weapon again, since Forever blocks the way it did before. Right-click a sharpening stone, weightstone, oil, poison, or fishing lure in your bags and it goes straight onto your weapon, main hand first as before. Not in combat, when the bags work as usual.
- **Settings**: Reset Seen Version on the Debug page goes back to the release before the one you have, so it marks what changed in this release instead of nothing.

## 0.8.0 (2026-10-10)

### Added

- **Talent Planner** (new, on by default, in Interface): a Plan Talents button on the talent window. Place talents freely without learning them, in order, up to the points you have at a level you choose, then follow the plan as you level: its next talent glows, tooltips say at which level each rank comes, and hovering the line beside the button lists the plan in order. A dropdown keeps several named plans, and shares or imports one as a line of text.
- **Commands** (new, on by default, in Interface): short slash commands, each with its own checkbox. `/rl` reloads the UI, and `/clear` empties a chat window. A command another addon already has is left to it.
- **Waypoints** (new, on by default, in Map): `/way [zone] x y` puts the game's map pin on a spot and tracks it (`/way clear` takes it away), unless TomTom or another addon already has `/way`. The new Waypoint Arrow option (on by default) shows an arrow on screen that turns toward the pin, from `/way` or a click on the map, with how far it is. Move and resize it in Edit Mode.
- **Auto Quest** (new, off by default, in Automation): accepts quests and turns in finished ones as you talk to quest givers, one by one down a quest giver's list. It never picks a reward when there's a choice. Accepting and turning in have their own checkboxes, repeatable and shared quests can be left out, and holding Shift (or Ctrl, Alt, or no key) lets you do it yourself.
- **Auto Weapon Buff** (new, off by default, in Automation): using a sharpening stone, weightstone, oil, poison, or fishing lure puts it straight onto your weapon, without clicking the weapon. Main hand first; the off hand when only it can take it, or when the main hand already has a buff and the off hand doesn't (or its buff runs out sooner).
- **Buff Timers** (new, on by default, in Interface): the time left under your buff and debuff icons as a clock, like 1:23, instead of rounded minutes like 2 m. Choose under 10 minutes (the default), under an hour, or always. When the game hides an aura's time in combat, Blizzard's own timer shows.
- **Unusable Items Tint** (new, on by default, in Items): tints red the items you can't use, because of your class, armor or weapon skill, level, or profession, in your bags, the bank, and at merchants, the way merchants tint them. At merchants it only adds what the merchant doesn't already tint, such as gear above your level. Bags, bank, and merchants each have a checkbox.
- **XP Bar Text** (new, on by default, in Interface): the experience bar shows its numbers all the time, with the percent, your rested XP, and the XP of the quests in your log that are ready to turn in (or all of them), in green once turning them in would level you.
- **Minimap Button** (new, on by default, in Interface): Forever++'s own button on the minimap, in the addon compartment, or both. Click it to open Forever++ settings, or right-click it for quick toggles of Fast Loot, Auto Quest, Auto Sell Junk, Auto Stow, Fishing Cast, Gathering Tracking, and Hide Beta Feedback. While Error Catcher is on, Shift-right-click it to see the errors, and it shows how many this session caught. After a fresh install it wears Blizzard's NEW label, and its first click opens the About page.
- **Settings**: a search box at the top of the Modules page shows only the modules whose name, description, or options have what you type, with those options highlighted. The New checkbox beside it shows only the modules marked NEW.
- **Settings**: the Modules page marks new modules, and new or changed options, with Blizzard's NEW label until you've clicked the module, and opens on the first module with a marked option.

### Changed

- **Item Tooltips**: Sell Price, Auction Prices, and Item Count are now one module, Item Tooltips, in Items, with a checkbox for each. Price For and Alignment are shared by all its lines, so they always line up. Your choices, auction prices, and bank counts come along; Sell Price's Price For and Alignment win if they differed.
- **Item Tooltips**: Crafting Costs shows Estimated Profit, after the auction house's 5% cut, and, at the top, how old the oldest auction price in the totals is.
- **World Map**: Points of Interest, Zone Info, Unexplored Areas, and Coordinates are now one World Map module, with a section for each in its options and an Enabled checkbox at the top of each section. Your choices, learned flight points, and ley lines come along.
- **Class Colors**: new Friends and Who List option (on by default) shows online friends' names in the friends list and names in the who list in their class color.
- **Chat Copy**: the window shows chat lines in their chat colors, with names in their class colors and links in theirs, the way they look in chat. Copying still gives plain text.
- **Chat Copy**: new Click Timestamps option (off by default): click a chat line's timestamp to copy that line. Needs the game's chat timestamps turned on.
- **Error Catcher**: its button is now the Minimap Button module, where a click opens settings and a Shift-right-click shows the errors. Turn that module off for no button. Its Clear Key option moved there too: Ctrl-right-click still clears this session's errors. If you had turned Error Catcher's button off, the Minimap Button goes in the addon compartment instead.
- **Settings**: Clutch's Default is now Developer's Defaults, and the welcome page's Defaults button is now Recommended Defaults, matching the Defaults popup on the Modules and Debug pages.
- **Settings**: Forever++ in the AddOns list, `/fpp`, and the minimap button open the Modules page. The welcome page is now the About page, at the bottom of the list, with the version, links, and commands, and the same Defaults button at the top right as the Modules page.
- **Settings**: the Modules page lists every module on the left, each with its checkbox, and shows the one you click on the right: its title, what it does, an Enabled checkbox, and its options and buttons. No more gears or options opening inside the list. Modules with many options group them under headers, and options that only matter while another is on sit under it: Player Nameplates, NPC Nameplates, World Map, Quest Tracker, Profession Tooltips, and Item Tooltips.
- **Settings**: clearer names and descriptions for a few options: Auto Quest's Skip Key, Item Tooltips' Bag and Bank Labels, Unexplored Areas' Tint Strength, and Zone Info's Herbs, Ore, and Skinning.
- **Character Window**: Character Frame Enhancements is now Character Window, so its name fits the Modules list, and Durability Bars is now its Durability Bars option instead of a module of its own (always, only when worn, below 50% or 25%, or off), set to what you had.
- **Auto Screenshot**: now listed under Automation instead of Interface.
- **Auto Screenshot**: new Played Time on Level Up option (off by default) shows your `/played` time in chat when you level up, so it's in the screenshot.
- **Auto Screenshot**: new Your Own Screenshots option (off by default), under Hide Interface, hides the interface for the screenshots you take with the Screenshot key (Print Screen) too, not only Auto Screenshot's. Not in combat.
- **Points of Interest**: new Ley Lines option shows Skyborne ley lines and elemental convergences on the map. A spot is saved when a Skyborne gets the 15-minute buff from Read Ley Line or Skysight there, and every character on the account sees it. Shown to Skyborne for their own kind by default, or to everyone, or to no one.

### Fixed

- **Character Window**: works with Forever's new Titles tab. Titles gets its own side tab, the Pet tab opens your pet's stats again instead of Titles, the titles list starts at the top and runs further down like the stats, and the pet pane keeps your pet's level and loyalty. Your pet's tab also comes and goes with your pet while another tab is open, and a tab you can't use yet (no titles, no pet) says why when you point at it. The side tabs sit as close together as Blizzard's, and get a little smaller when needed, so the last one stays on the window.
- **Console Variables**: an empty list says why (nothing matches the search, or nothing is changed), and a row stays highlighted with its tooltip while you point at its value box or Default button.

## 0.7.0 (2026-10-02)

### Added

- **Best Quest Reward** (new, on by default, in Items): marks the quest reward that sells to a vendor for the most with a gold coin, in the quest window and the quest log.
- **Item Count** (new, off by default, in Items): shows in an item's tooltip how many you own, in your bags and in your bank.
- **Easy Delete** (new, off by default, in Items): types DELETE for you when you destroy a good item.
- **Movable Framerate** (new, off by default, in Interface): move and resize the framerate text (Ctrl+R) in Edit Mode.
- **Auction Prices**: new Crafting Costs option shows a recipe's total cost, value, and profit in the professions window. Reagent tooltips there now price the amount the recipe needs, for Sell Price too.
- **Fishing Cast**: new Combat Warning option warns you when combat starts with a fishing pole equipped.
- **Points of Interest** and **Zone Info**: Forever's new boats and skyships, and the Excavation Site and City of Dalaran dungeons.

### Changed

- **Points of Interest**: Forever's flight masters are named for their places, and its dungeons show in your language.
- **Error Catcher**: a redesigned window with a list of errors and a Copy Bug Report button. Right-click the minimap button to open Forever++ settings.
- **Spell Ranks**: "Higher Rank Known:" in spell tooltips now looks like the other tooltip lines.

### Fixed

- **Edit Mode**: the arrow keys nudge Combat Alert, Currency Bar, and Flight Timer again.
- **Auction Prices**: a price's age is when the item was last seen, not the last scan. Saved prices are cleared once.
- **Sell Price**: no more Lua error on a vendor's buyback tab.

## 0.6.0 (2026-10-01)

### Added

- **Quest Tracker** (new, on by default, in Interface): restyles Blizzard's quest tracker with a font, size, and outline, a dark box behind it that fits your quests, and fading in combat. It's still Blizzard's tracker, so Edit Mode and quest items work as before.
- **Error Catcher** (new, on by default, in Interface): catches Lua errors and blocked actions in place of Blizzard's error popup, saves them per session, and shows them in a window you can copy from (`/fpp errors` or the minimap button). Ctrl-right-click the minimap button to clear this session's errors.
- **Character Frame Enhancements** (new, on by default, in Interface): moves the Character window's Equipment and Pet tabs to the side with the others, removes the portrait and level line so the stats start at the top, and shows your level and name in your class color as the title.
- **Forever Quest Icons** (new, on by default, in Interface): marks quests that are new to Forever with an infinity sign (or the Forever logo) after their name in the quest log, the objective tracker, and quest givers' lists. Idea from ForeverQuestTint.
- **Quest Nameplates**: new Party Progress option to count everyone's progress added up (the default), only yours, or the party member furthest from done. Creatures only a party member needs now show too.
- **Class Colors**: the Names checkbox is now a Name Color choice (Default, White, or Class Color), and a new Name Backgrounds option (on by default) tints the bar behind a player's name on the target and focus frames in their class color.

### Changed

- **Persistent Chat**: renamed from Chat Fading, and now on by default.
- **Auto Repair** and **Auto Sell Junk**: holding Shift to skip is now an option (on by default).
- **Settings**: the Defaults button on the Modules and Debug pages now offers Clutch's Defaults or Recommended Defaults and resets only Forever++. Blizzard's All Settings reset no longer touches Forever++.
- **Settings**: Clutch's Default also sets Zone Info's Dungeons and Fishing to Hold Detail Key.
- **Settings**: Combat Alert, Currency Bar, and Flight Timer are sized and reset only in Edit Mode now.

### Fixed

- **Fishing Cast**: double right-click now casts Fishing.
- **Tooltips**: levels and class names are colored again, player titles show, and the Target line shows the target's name instead of its level.
- **Flight Timer**: no longer draws over other windows.

## 0.5.0 (2026-10-01)

### Added

- **Chat Fading** (new, off by default, in Chat): keeps chat text on screen instead of fading it out after a while.

### Changed

- **Hide Beta Feedback**: also hides the beta's feedback buttons on quest windows (quest, gossip, and quest log), with its own checkbox.
- **Quest Nameplates**: the icon matches the objective: Blizzard's attack, pickup, or interact icon for kill, item, or object objectives, and the quest icon for the rest. A creature whose objective is done shows a green check and its final count (8/8), unless you turn off Show Completed, and the count can be turned off to leave just the check.
- **Player Nameplates and NPC Nameplates**: on name-only plates the buffs sit centered above the name instead of far off to the left. A Buffs setting puts them above, before, or after the name, or back in Blizzard's spot.
- **Profession Tooltips**: the game's own bare "Mining" line under a vein is replaced by "Requires Mining (1)" in the difficulty color instead of showing both. When Blizzard already says "Requires Mining (1)", a bare name line below it shows your skill ("Your Mining skill: 150").
- **Chat History**: the "Earlier chat" line between old and new chat is now an option, off by default.

### Fixed

- **Hide Beta Feedback**: the feedback box on quest windows no longer fades back in.
- **Forever++**: an error in one module no longer stops the others from loading, turning on, or turning off.

## 0.4.0 (2026-09-30)

### Added

- **Settings**: Defaults and Clutch's Default buttons on the welcome page, each asking first. Defaults resets every module's settings; Clutch's Default also turns on Fishing Cast, Skip Cinematics, Auto Screenshot, Currency Bar, Hide Beta Feedback, and Short Channel Names.
- **Edit Mode**: Combat Alert, Currency Bar, and Flight Timer work like Blizzard's own frames: click one to select it, then drag it (it snaps to the screen and other frames), nudge it with the arrow keys, or use its Scale slider and Reset To Default Position, also on right-click.
- **Chat** (new category): **Chat Copy** adds a button beside the chat window that opens the chat as plain text to copy. **Short Channel Names** shows [1] instead of [1. General] (off by default). **Chat History** shows each window's latest lines again after a logout or reload. **Social Button** moves the Quick Join button beside the chat's other buttons. **Chat Font** draws chat, and by default the chat input box, in Friz Quadrata or another Blizzard font (not on Korean, Chinese, or Russian clients).
- **Currency Bar** (new, off by default, in Interface): a small box showing your gold and, if you choose, the currencies you show on your Backpack. Hover it for what this session gained or spent. Move it in Edit Mode.
- **Auto Decline**: also turns down party invites, without the invite sound (off by default). Duels and party invites each have their own checkbox.
- **Fishing Cast** (new, off by default, in Automation): double right-click with a fishing pole equipped to cast Fishing.
- **AddOns List** (new, in Interface): the AddOns list without category headers, enabled addons first.
- **Spell Ranks** (new, in Interface): marks action bar spells that have a higher rank you already know, and adds the best rank to the tooltip. `/fpp ranks` lists them.
- **Recipe Colors** (new): colors recipes in the professions window by your chance of a skill-up, like the old trade skill window.
- **Quest Nameplates** (new): a quest icon and your progress beside the health bar of creatures you need for a quest.
- **Already Known** (new): a green check on recipes, mounts, pets, toys, and other items you already know, on merchants, the auction house, bags, mail, and loot.
- **Combat Alert** (new, off by default, in Interface): floats "Entering Combat" or "Leaving Combat" up from the middle of the screen.
- **Auto Sell Junk** (new, off by default): sells your gray items when a merchant opens. Hold Shift to skip it.
- **Flight Timer** (new): times each flight you take, then counts the next one down in a bar and shows the flight time on the flight map.
- **Profession Tooltips** (was Gathering Tooltips): also shows the Lockpicking skill a lockbox or locked chest needs, and lets blacksmiths see which skeleton key opens it.
- **Zone Info**: a Detail Key shows fishing, dungeons, herbs, ore, and skinning only while you hold it, and the panel can sit in a top corner of the map.
- **Player Nameplates**: an Icon Position option puts the role, friend, and recent ally icons before or after the name.
- **Tooltips**: a Faction Color option colors the Horde or Alliance line on a unit red or blue.

### Changed

- **Profession Tooltips**: recolors Blizzard's "Requires Mining (1)" line against your skill instead of adding a second one.
- **Zone Info** and **Points of Interest**: map tooltips look the same: white title, gold kind of place, Horde red and Alliance blue, and each dungeon or raid on one row with its icon.
- **Player Nameplates**: recent allies get an icon instead of a light blue name. Recent Allies is a dropdown: Off, Colored Name, or Icon.
- **Player Nameplates** and **NPC Nameplates**: Name Size is 80% by default.
- **Skip Cinematics**: Forget asks you to confirm first.

### Fixed

- **Points of Interest**: no second icon beside ours for Undercity or for dungeon and raid entrances. Learned flight points show as learned again, including with translated names; visit a flight master once to pick yours up.
- **Player Nameplates**: no more "action blocked" error at login.
- **Auction Prices**: posting works while a scan runs.
- **Player Nameplates** and **NPC Nameplates**: the guild or title no longer overlaps the cast bar.
- **Profession Tooltips**: the skill line sits under the name, above quest lines, also on minimap pins.

## 0.3.0 (2026-09-28)

### Added

- **Points of Interest**: dungeons, raids, capitals, flight masters, boats, zeppelins, and spirit healers on the world map, in a new Map category. Learned flight masters show in the minimap's white.
- **Zone Info**: a panel on the world map with the zone's level range, who holds it, its dungeons, fishing skill, and its herbs, ore, and skinning.
- **Unexplored Areas**: shows the parts of zone maps you haven't explored yet, with a tint.
- **Coordinates**: your coordinates and the cursor's in the world map's title bar.
- **Hide Filter Reset**: hides the reset button on the world map's filter dropdown.

### Changed

- **Class Colors**: hostile NPCs' health bars are red, neutral ones yellow, and tagged ones gray.
- **Bag Slot Counter**: adds up every bag on the backpack button by default.
- **Auto Stow**: the delay is a slider.
- **Auto Release**: the delay is a slider.
- **Gathering Tracking**: Swap is a slider.
- **Auction Prices**: Red After is a slider.
- **Player Nameplates**: a Name Size slider.
- **NPC Nameplates**: a Name Size slider.

### Fixed

- **Player Nameplates**: Chinese, Korean, and Cyrillic names show again.
- **NPC Nameplates**: same fix for NPC names and titles.

## 0.2.0 (2026-09-27)

### Added

- **Auto Decline**: turns down duel requests and closes the popup. Includes letting friends and guildmates through, and saying in chat who was declined. Off by default.
- **Auto Dismount**: gets you off your mount or stands you up when a spell, flight, loot, or attack fails because you're mounted or sitting. Includes separate Dismount and Stand Up options, and leaving shapeshift forms (off by default).
- **Auto Release**: releases your spirit when you die in a battleground. Includes a delay, and staying put when a soulstone, reincarnation, or someone else can resurrect you. Off by default.
- **Auto Screenshot**: takes a screenshot a moment after you level up, earn an achievement, or defeat a boss, so Blizzard's toast is in it. Includes checkboxes for loot of a chosen quality, reputation standings, PvP ranks, new titles, battleground ends, and deaths, hiding the interface for the shot, and a chat line saying why. Off by default.
- **Bag Slot Counter**: how many bag slots are free, on the bag buttons. Includes each bag's own count or the total on the backpack, the reagent bag on its own button, added to the backpack, or hidden, counting special bags such as quivers and herb bags, and the text's size and position.
- **Class Colors**: players' health bars and names in their class color on the player, target, focus, party, and target-of-target frames. Includes health bars and names (off by default) separately, and a checkbox for each frame.
- **Gathering Tooltips**: the skill a herb, ore, or skinnable beast needs, in its tooltip in the world or on the minimap, colored red, orange, yellow, green, or gray against your skill like trainer recipes. Herb, ore, and stone items say the skill that gathers them. Includes showing it only for professions you have or always, and a checkbox each for herbs, ore, creatures, and items.
- **Skip Cinematics**: skips the game's cinematics and movies. Off by default. Includes skipping only ones already seen on any character or every one, holding Shift to watch, and a Forget button for the seen list.

### Changed

- **Player Nameplates**: recent allies' names in the game's light blue, instead of the Name Color. Includes a checkbox to turn it off.
- **Settings**: fewer entries in the sidebar. Forever++ opens on a welcome page, and every module is on one Modules page, where the gear beside a module shows its options under it. About is part of the welcome page.

## 0.1.0 (2026-09-27)

### Added

- **Auction Prices**: scans the auction house when you open it and shows the lowest buyout in item tooltips. Includes how long ago the item was scanned (colored by age), the same price options as Sell Price, `/fpp scan`, and a Reset button and `/fpp resetprices` to forget saved prices.
- **Auto Gossip**: picks an NPC's only option when it has nothing else to say and no quests. Includes a choice for bankers, vendors, trainers, flight masters, stable masters, and other NPCs, and holding Shift to choose yourself.
- **Auto Repair**: repairs your gear at merchants and says in chat what it cost. Includes paying from the guild bank first, the guild bank only, or your own money, a minimum cost, and holding Shift to skip it.
- **Auto Stow**: puts your weapons away after combat. Includes the delay and leaving them out in dungeons, raids, and battlegrounds.
- **Console Variables**: a Settings page to browse, search, and change the game's console variables (CVars). Includes a Changed Only filter and `/fpp cvar [search]`.
- **Durability Bars**: a bar beside each item on the character window with how worn it is. Includes showing bars always, only when worn, below 50%, or below 25%.
- **Fast Loot**: with auto loot on, takes everything at once. Includes a warning in Settings, with a Turn On button, when Blizzard's auto loot is off.
- **Gathering Tracking**: keeps Find Minerals or Find Herbs on. Includes minerals, herbs, or both, turning tracking back on after logging in, zoning, or dying, and swapping between the two every few seconds.
- **Hide Beta Feedback**: hides the beta's "Press F6 to submit an issue" tooltip line and the bug report button, each on its own. Off by default, and only on beta and PTR clients.
- **NPC Nameplates**: friendly NPCs' names with their title, and a health bar only when they're hurt or in combat. Includes name color, where the level goes, and when and in what color titles show.
- **Player Nameplates**: friendly players' names with their guild, and a health bar only when they're hurt or in combat. Includes class-colored names, where the level goes, guild line and color, highlighting guildmates, and role icons for group members and Battle.net icons for friends.
- **Sell Price**: the vendor price in item tooltips. Includes the whole stack or one item (Shift shows the other), lining up with other price lines, and the quantity color.
- **Tooltips**: colors unit and item tooltips. Includes borders by class, reaction, or item quality, name, guild, level, and class name colors, player titles, a Target line, anchoring to the cursor, and hiding unit tooltips in combat.
- **Settings**: Forever++ in Game Menu > Options > AddOns. Includes a checkbox per module grouped by category, a page per module with options, Debug, Changelog, and About. Every module turns on and off without a reload.
- **Commands**: `/fpp` or `/forever++` opens the settings. Includes `list`, `toggle`, `options`, `set`, and `reset`.
