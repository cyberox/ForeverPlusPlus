![Forever++](https://media.forgecdn.net/attachments/2150/393/01-hero-jpg.jpg)

# Forever++

Small improvements to the default UI for **WoW: Forever**, made to look like Blizzard's own.

Forever++ isn't a UI replacement: no new unit frames, action bars, or skins. It adds to Blizzard's own windows with Blizzard's fonts, art, and colors, so you can't tell where the game stops and the addon starts. It needs no setup and shows no popups at login. Install it and play.

- **Over 80 modules**, each one turned on or off in the game's Settings, with no `/reload`.
- **Deep customization**: most modules have their own options, all in Blizzard's Settings panel under Options > AddOns > Forever++.
- **Sensible defaults**: the changes nearly everyone wants are on; the rest are there when you want them.
- **Light**: a module that's off costs nothing.

**[Watch the 80-second trailer](https://www.youtube.com/watch?v=D_k53X4MYo0)**

## Settings

Open Game Menu > Options > AddOns > Forever++, or type `/fpp`.

- **Modules**: every module with a checkbox, grouped by category. The search box narrows the list, and New shows only what's new since you last looked. Click a module for what it does and its options.
- **Profiles**: sets of settings for different characters. Everyone starts on Default. Make more, pick which one each character uses, switch live with no reload, and Export or Import one as a line of text.
- **Changelog**: what changed in each release.

A setting you change stays changed, even if a later update changes its default; its undo arrow, or the Defaults button for everything, puts it back. When a module needs one of Blizzard's own settings on, its options say so with a Turn On button.

## Modules

Everything is on by default except where noted. Each module can be turned off, and most have more options than listed here; each option is explained in Settings.

### Automation

- **Auto Decline**: Turns down duel requests, and optionally party invites, guild invites, and guild charters, saying who asked. Friends and guildmates can be let through. Off by default.
- **Auto Dismount**: Dismounts or stands you up when a spell, flight, loot, or attack fails because you're mounted or sitting. Can also leave shapeshift forms.
- **Auto Gossip**: Picks an NPC's only option for you, so the bank, shop, trainer, or flight map opens straight away. Hold the Skip Key to choose yourself. Off by default.
- **Auto Release**: Releases your spirit when you die in a battleground, unless you can be resurrected. Off by default.
- **Auto Screenshot**: Takes a screenshot when you level up, earn an achievement, or defeat a boss, and optionally for loot, reputation, PvP ranks, and more. Can hide the interface for the shot. Off by default.
- **Auto Open Containers**: Opens clams, sacks, and unlocked lockboxes in your bags by themselves when nothing is in the way, keeping the bag slots free that you pick. Off by default.
- **Auto Repair**: Repairs your gear at any merchant who repairs and says what it cost. Hold the Skip Key to skip it.
- **Auto Sell Junk**: Sells gray items when a merchant opens and says what they sold for. Can stop at what the buyback list holds. Off by default.
- **Auto Stow**: Puts your weapons away once they've been out for a few seconds out of combat.
- **Auto Weapon Buff**: Right-clicking a sharpening stone, weightstone, oil, poison, or fishing lure puts it straight onto your weapon, main hand first. Not in combat. Off by default.
- **Comprehend Scrolls**: For Mages: right-clicking a scroll that needs Comprehension casts Comprehend Scroll on it. Not in combat.
- **Fishing Cast**: Double right-click with a fishing pole equipped to cast Fishing. Louder Bobber turns sound effects up while you fish. Never in combat. Off by default.
- **Fast Loot**: With auto loot on, takes everything at once instead of waiting for the loot window.
- **Gathering Tracking**: Keeps Find Minerals or Find Herbs on after logging in, zoning, or dying, and can swap between the two every few seconds, silently if you like.
- **Skip Cinematics**: Skips cinematics and movies you've already seen, or every one. Hold the Watch Key to watch. Off by default.
- **Auto Quest**: Accepts quests and turns in finished ones as you talk to quest givers. Never picks a reward for you, and pauses while you hold Shift. Off by default.

### Character

- **Buff Timers**: Shows the time left under buffs and debuffs as a clock (1:23) instead of rounded minutes. Can sort buffs by time left and hide tracking buffs.
- **Macros**: Makes the macros you turn on and keeps them up to date. Smart Buff casts the right buff at the best rank for your target (Might for Warriors, Wisdom for mana users, and so on), skipping buffs they already have. Off by default.
- **Spell Ranks**: Marks action bar spells that have a higher rank you already know, and names the best rank in the tooltip. `/fpp ranks` lists them.
- **XP Bar Text**: Shows your experience on the bar all the time, with the percent, rested XP, and the XP of quests ready to turn in. Its tooltip adds XP per hour and time to level.
- **Character Window**: Moves the Equipment, Titles, and Pet tabs to the side, shows your name in class color as the title, and puts a durability bar beside each item. Can color the weapon skills you have equipped.
- **Durability Warning**: Warns you once when worn gear drops below a durability you pick (25% by default), and again when it breaks: red text, and optionally a chat line and a sound.
- **Talent Planner**: Plan your talents in the talent window: click talents in order into a saved plan, see the level each point comes at, and get the next one highlighted when you have a point to spend. Keeps several plans, shares them as text, and imports builds from talentsforever.com and wowforevertalents.com.
- **Professions**: Adds to the professions window, each part with its own checkbox.
  - **Recipe Colors**: recipes colored by skill-up chance.
  - **Skill-Ups Left**: how many skill-ups before a recipe turns gray.
  - **Skill Bar**: the levels a recipe turns yellow, green, and gray at, with your skill marked.
  - **Crafting Costs**: reagent cost, value, and profit, from auction prices.
  - **Unlearned Recipes**: the recipes you don't know yet in the list, with the skill each takes and the item that teaches it.
- **Macro Icon Search**: Adds a search box to the macro icon picker, over the icons of the spells you know and the items you carry.

### Chat

- **Chat Copy**: Adds a button beside the chat window that opens the chat as text you can copy. Click Timestamps (off by default) copies a single line.
- **Chat Levels**: Shows each player's level before their name in chat, [60:Name], colored like a quest of that level. Uses the last level Forever++ saw them at. Off by default.
- **Quest Links**: Turns the plain-text quests Questie users link in chat into clickable Blizzard quest links.
- **Short Channel Names**: Shortens chat channels to [1], [G], or [LFG], and [Guild], [Party], [Raid] to [GD], [P], [R]. Off by default.
- **Chat Font**: Draws chat in another of the game's fonts, keeping its size. Not on Korean, Chinese, and Russian clients.
- **Keep Chat Visible**: Keeps chat text on screen instead of fading it out after a while.
- **Chat History**: Shows each chat window's latest lines again after a login or reload, except whispers.
- **Chat Arrow Keys**: Up and Down in the chat box bring back what you sent, and Left and Right move through the text, without holding Alt.
- **Social Button**: Moves the social (Quick Join) button down beside the chat window's other buttons.
- **Whisper Window**: Keeps whispers in a window like a messenger: conversations with unread counts on the left, the one you pick on the right, and a box to reply in. Opens from a chat button or `/fpp whispers`, and can hide whispers from chat. Off by default.

### Interface

- **Combat Alert**: Floats "Entering Combat" and "Leaving Combat" up the screen, with an optional sound. Placed in Edit Mode. Off by default.
- **Currency Bar**: Shows your gold, and optionally currencies, in a small box, with this session's gains and gold per hour in its tooltip. Placed in Edit Mode. Off by default.
- **Hide Error Messages**: Keeps the red errors that repeat while you fight (Out of range, Not enough energy) off the screen, along with their sounds. Off by default.
- **Hide Stance Bar**: Hides the stance bar. Its keys still work, and Show on Mouseover brings it back under the mouse. Off by default.
- **Loot Rolls**: Place the Need, Greed, and Pass rolls in Edit Mode, with their direction and spacing. Each roll shows the seconds left and what your group picked. Off by default.
- **Local Time**: While the clock's Use Local Time is on, the calendar and a few other realm times show in your own time.
- **Movable Windows**: Hold a key (Shift by default) and drag Blizzard's windows where you want them, by the whole window or only its title bar, and hold Ctrl and scroll to resize one. Positions and sizes are kept always, for the session, or until the window closes. Off by default.
- **Tooltips**: Colors unit and item tooltips by class, reaction, or quality, and adds player titles and who a unit is targeting. Can hide the health bar, quest lines, the unit frames' right-click hint, and the fishing bobber's tooltip.
- **Movable Framerate**: Lets you move and resize the framerate text (Ctrl+R) in Edit Mode. Off by default.

### Items

- **Already Known**: Marks recipes, mounts, pets, toys, and other items you already know with a green check on their icon, at merchants, the auction house, bags, mail, and loot.
- **Appearance Icons**: Marks gear whose appearance you haven't collected with Blizzard's transmogrifier icon, in bags, the bank, merchants, the auction house, loot, and on recipes that make it.
- **Bag Slot Counter**: Shows free bag slots on the backpack button, or each bag's own count, turning orange when few are left and red at 0.
- **Easy Delete**: Types DELETE for you when you destroy a good item, so Yes is a single click. Off by default.
- **Item Tooltips**: Adds lines to item tooltips, each with its own checkbox.
  - **Sell Price**: for the whole stack.
  - **Auction Prices**: from a scan of the auction house, or Auctionator's.
  - **Stat Colors**: each stat in its own color.
  - **Compare Crafted Gear**: a recipe that makes gear compares it with what you wear.
  - **Repair Cost**, **Item Count** across bags and bank, and **Disenchant** results and value: off by default.
- **Gathering Skill Tooltips**: Shows the skill a herb, ore, skinnable beast, or locked box needs in its tooltip, colored against your skill.
- **Waylaid Crates**: Helps fill Waylaid Crates: what each bundle costs at auction, and an auction house category listing every item your crates still need.
- **Unusable Items Tint**: Tints red the icons of items you can't use, in bags, the bank, and merchants, and optionally the auction house and loot.
- **Upgrade Arrows**: Puts Blizzard's green arrow on gear that beats what you wear, judged by stat weights for your class and talent tree, in bags, the bank, merchants, loot, quest rewards, and the auction house. Change the weights per stat with `/fpp weights`, or import and export Pawn strings ([how the defaults were worked out](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/stat-weights.md)). Off by default.

### Map

- **World Map**: Adds to the world map in four parts, each with its own checkbox.
  - **Points of Interest**: dungeons, raids, capital cities, flight masters, boats, zeppelins, spirit healers, and Skyborne ley lines. Clicking a dungeon or raid shows its map, and clicking a boat or zeppelin the map of its next stop.
  - **Zone Info**: a panel with the zone's level range, faction, dungeons, and what can be gathered and fished there.
  - **Unexplored Areas**: shows the parts of a zone you haven't explored, tinted.
  - **Coordinates**: your and the cursor's coordinates in the map's title bar.
- **Flight Timer**: Times your flights and shows a countdown bar (placed in Edit Mode) and the time on the flight map. A route you haven't flown shows an estimate, marked with ~.
- **Gathering Map**: Remembers every herb, vein, chest, and fishing pool you gather, for all your characters, and shows them on the world map and minimap. Near you on the minimap a node becomes an empty ring, so the game's tracking dot shows inside it when the node is up. Pick which nodes show on its own Settings page, forget one with Shift+right-click, and share them as text with Export and Import.
- **Hide Filter Reset**: Hides the reset button on the world map's filter dropdown.
- **Square Minimap**: Makes the minimap square, with a border in Blizzard's art (a dozen styles, or none). Minimap buttons and icons follow the square edge. Off by default.
- **Waypoints**: `/way [zone] x y [note]` puts the game's map pin on a spot (`/way 45.2 67.8`, `/way clear`, `/way share`), with an arrow on screen that points to it, your selected quest, or your corpse. TomTom's `/way` wins if it's installed.
- **Compass Bar**: A compass across the top of the screen with your selected quest, map pin, corpse, and group on it, and optionally every quest, flight masters, gathering nodes, and rares. Sized in Edit Mode. Off by default.

### Quests

- **Best Quest Reward**: Puts a gold coin on the quest reward that sells to a vendor for the most. It never picks for you.
- **Quest Tracker**: Restyles Blizzard's quest tracker without replacing it: font, a dark box behind it, fading in combat, sorting by level, and showing only the current zone's quests.
- **Forever Quest Icons**: Marks quests that are new to Forever with a Forever icon after their name, in the quest log, the tracker, and quest givers' lists.
- **Quest Levels**: Shows a quest's level before its name ([12], with a + for group quests) in a quest giver's list and the quest's details. Can color it by difficulty.
- **Quest Pins**: Needs the [QuestieDB](https://github.com/Questie/questiedb) addon. Puts a ! on the world map where each quest you can still take starts, colored by kind, and lists an NPC's quests in its tooltip. Options pick which kinds and levels show. Off by default.
- **Quest Item Sparkles**: Keeps the sparkle on quest items you can pick up in the world, even after a graphics preset turns it off. Off by default.
- **Quest Nameplates**: Shows a quest icon and your progress (3/8) beside the health bar of creatures you need for a quest, counting your party's progress if you like. With the QuestieDB addon, creatures that drop a quest's item are marked too.

### System

- **Hide Beta Feedback**: Hides the beta's "Press F6 to submit an issue" tooltip line and feedback buttons. Off by default, and only on beta and PTR clients.
- **AddOns List**: Shows the AddOns list without category headers, enabled addons first. Can search notes and save addon sets.
- **Error Catcher**: Catches Lua errors, blocked actions, and warnings quietly instead of in Blizzard's popup. `/fpp errors` lists them, with a Copy Bug Report button. Leaves Lua errors to BugGrabber when it's installed.
- **Minimap Button**: A Forever++ button on the minimap or in the addon compartment. Click it for a menu of quick toggles you can customize, or right-click for settings. It shows how many errors Error Catcher caught.
- **Slash Commands**: Adds `/rl` to reload the UI and `/clear` to empty the chat window, each with its own checkbox.
- **Console Variables**: A Settings page to browse and change the game's console variables, with a Popular group, favorites, and a padlock that keeps one at its value. Off by default.
- **Debug**: Every module's debug options and the testing tools, on a Debug page in Settings. Off by default.
- **CPU Profiler**: A Settings page that records how much CPU each module takes, with the worst frames listed as spikes. Nothing is timed until you press Record. Off by default.

### Units

- **Class Colors**: Colors players' health bars, and optionally names, by class on the unit frames, NPCs' bars by reaction, and names in the friends and who lists by class.
- **Druid Mana Bar**: Druids only: shows your mana under the energy or rage bar while in Cat or Bear Form.
- **NPC Nameplates**: Always shows friendly NPCs' names and titles, with the health bar only when they're hurt or in combat. Options for sizes, a level badge, and where buffs sit.
- **Player Nameplates**: Always shows friendly players' names and guilds, with the health bar only when they're hurt or in combat. Options for sizes, a level badge, class icons, and dimming players outside your group, guild, and friends. In dungeons and raids the game keeps Blizzard's own.
- **Simplified Dungeon Nameplates**: Turns on the game's Simplified nameplates only inside dungeons and raids, for the kinds you pick. Off by default.
- **Target Markers**: Hold a key and a ring of raid icons opens at your mouse, like the ping wheel: point at one and let go to mark your target, or hold Shift for a world marker. Works in combat. Off by default.

## Commands

- `/fpp`: Opens the Forever++ settings (`/forever++` works too).
- `/fpp list`: Lists the modules and whether each is on, and the commands (`/fpp help` too).
- `/fpp toggle <module> [option]`: Turns a module on or off, or with an option, flips that checkbox.
- `/fpp options <module>`: Lists a module's options and their values.
- `/fpp set <module> <option> [value]`: Changes an option: `on`/`off`, a choice, or a number, such as `/fpp set WorldMap dungeonSize 150`. Leave out the value to see the choices.
- `/fpp reset`: Asks, then puts every setting back to its default, clears what Forever++ saved, and reloads.
- `/fpp profiles [name]`: Lists the profiles, or with a name, switches this character to that profile (`/fpp profile` too).
- `/fpp errors`: Shows the errors Error Catcher caught.
- `/fpp weights`: Opens Upgrade Arrows' Stat Weights page.
- `/fpp ranks`: Lists the action bar spells that have a higher rank you know (Spell Ranks).
- `/fpp whispers [name]`: Opens the Whisper Window, on a conversation with that player if named.
- `/fpp questpins [hidden | unhide <id|all> | why <id>]`: Lists the quest pins this character hid, brings them back, or says why a quest is pinned or not (Quest Pins).
- `/fpp scan`: Scans the open auction house now.
- `/fpp resetprices`: Forgets the saved auction prices.
- `/fpp cvar [search]`: Opens Console Variables.
- `/fpp profiler`: Opens the CPU Profiler.
- `/fpp buffs`: Shows how Macros' Smart Buff judges your target (while Macros is on).

## Install

Get it from CurseForge or Wago. To install it by hand, unzip it into the Forever client's AddOns folder, for example `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\ForeverPlusPlus\ForeverPlusPlus.toc`, then start the game or `/reload`.

## For addon authors

Other addons can read Forever++'s auction prices, disenchant values, upgrade scores, flight times, players seen, colors, dungeon levels, and module settings, set waypoints, and add modules of their own, through `ForeverPlusPlusAPI.v1`. See the [API documentation](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/api.md).

## How it's made

Forever++ is coded with AI by a longtime WoW addon developer, and every feature is tested in the game before it ships.

## Feedback

Forever++ keeps getting updates as the game does, and ideas are always welcome. Report bugs and suggest features in [GitHub issues](https://github.com/xIGBClutchIx/ForeverPlusPlus/issues), or leave a comment here.

Source code on [GitHub](https://github.com/xIGBClutchIx/ForeverPlusPlus). MIT license.
