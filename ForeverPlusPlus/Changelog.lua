-- The release notes the Changelog page in Settings shows, newest first. The game can't read
-- CHANGELOG.md at the repo root, so this is the same notes as data: change both together.
-- Headings and module names come from ns.L; the notes themselves are English, like CHANGELOG.md.
-- Each release: `version`, `date`, and `sections` of `{ heading, entries }`, where an entry is a
-- line of text or `{ name, text }` (a name shown in gold before its text). Changes not released
-- yet go first, with `version = L.CHANGELOG_UNRELEASED` and no date.
local _, ns = ...

local L = ns.L

ns.changelog = {
    {
        version = L.CHANGELOG_UNRELEASED,
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.ITEMTOOLTIPS_TITLE, "Auction Prices has a Hide on Junk option that leaves "
                    .. "the auction price off gray (Poor) items. Off by default." },
                { L.PLAYERNAMEPLATES_TITLE, "Dim Other Players fades the names of players who "
                    .. "aren't in your group or guild, your friends, or recent allies (30% by "
                    .. "default, with a slider), so NPCs stand out in a busy starting zone. Your "
                    .. "target stays bright. On by default." },
                { L.PLAYERNAMEPLATES_TITLE, "Lighter Rogue Yellow shows rogues in a pale yellow, "
                    .. "so they don't look like neutral NPCs. Off by default." },
                { L.PLAYERNAMEPLATES_TITLE, "Class Icon shows a player's class icon before or "
                    .. "after their name, as the group finder's ringed icon, or Blizzard's class "
                    .. "art round or square. With the level on the same side, it can sit next to "
                    .. "the name or past the level. Off by default." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.CHANGELOG_SETTINGS, "When two options can't both work, a line under one says "
                    .. "so, with a button that goes to the other. Movable Windows says so when its "
                    .. "Reset Key and Reset Click are the same as dragging, which can't reset." },
                { L.CHANGELOG_SETTINGS, "A module with a page of its own (Console Variables, "
                    .. "Profiler, Upgrade Arrows) says on the Modules page that its page shows in "
                    .. "the sidebar, or goes away, once you pick another page. Blizzard's sidebar "
                    .. "can't be redrawn right away without breaking its Social options." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.MOVABLEWINDOWS_TITLE, "The Settings window moves too, and so do the currency "
                    .. "window, the group finder, flight maps, chat channels and chat settings, "
                    .. "guild ranks, quest details, and Help, and the world map while it isn't "
                    .. "maximized." },
                { L.QUESTNAMEPLATES_TITLE, "On the left side, quest icons no longer overlap the "
                    .. "gold dragon on elite and rare creatures' nameplates. They sit past it." },
            } },
        },
    },
    {
        version = "1.0.0",
        date = "2026-11-04",
        sections = {
            { L.CHANGELOG_ADDED, {
                "Forever++'s first full release for WoW: Forever, with everything from the "
                    .. "betas and the additions below. Thanks to everyone who tested it.",
                { L.CLASSCOLORS_TITLE, "When Blizzard's nameplates don't show players in their "
                    .. "class color, its settings say so, with a Turn On button for each of "
                    .. "Blizzard's settings: friendly players' health bars, enemy players' health "
                    .. "bars, and friendly players' names. The names line doesn't show while "
                    .. "Player Nameplates is on, since that draws its own names." },
                { L.DEBUG, "New Testing tools that show a module with made-up data, for seeing "
                    .. "or recording it without what it waits for: Flight Timer's Test Flight (the "
                    .. "bar counting down), Combat Alert's Test Alerts, Chat Levels' Test Chat "
                    .. "(made-up trade chat with levels and class colors), and Quest Nameplates' "
                    .. "Test Quest Icons (progress on every creature's nameplate)." },
                { L.MOVABLEWINDOWS_TITLE, "A new module that lets you hold the move key (Shift "
                    .. "by default) and drag Blizzard's windows, like your character, spellbook, "
                    .. "professions, friends, and bags, to put them where you want. Remember "
                    .. "Position keeps them there always, until you log out or reload, or never, "
                    .. "and Reset puts every window back. Ctrl+Right-click a window to put just "
                    .. "that one back; the click and key are options too. Off by default." },
                { L.QUESTNAMEPLATES_TITLE, "While Blizzard's enemy nameplates are off, its "
                    .. "settings say so, with a Turn On button, since quest icons need them." },
                { L.WORLDMAP_TITLE, "Coordinates has Player Coordinates, Cursor Coordinates, "
                    .. "and Tenths checkboxes. They're Blizzard's own settings, so changing one "
                    .. "here changes it in Blizzard's Interface options too. They replace the "
                    .. "\"Blizzard's map coordinates are off\" line." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.CHANGELOG_SETTINGS, "A setting you pick stays yours, even when it's the same "
                    .. "as the default. If a later version changes that default, your choice is "
                    .. "kept. Only the undo arrow, Defaults, or /fpp reset puts it back, and after "
                    .. "that you get the new default." },
                { L.CHANGELOG_SETTINGS, "A \"Blizzard's ... is off\" line with a Turn On button "
                    .. "no longer shows on a client that doesn't have that setting, and its tooltip "
                    .. "says only what doesn't work, since the button turns it on." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.CHANGELOG_SETTINGS, "Turning on a module with a page of its own (Debug, "
                    .. "Console Variables, Profiler, Upgrade Arrows) no longer makes Blizzard's "
                    .. "Social options fail with an action blocked (C_Discord.IsUserOAuthed). Its "
                    .. "page shows in the sidebar the next time you pick a Forever++ page." },
                "Edit Mode's settings box for Forever++'s frames is wide enough for the scale "
                    .. "slider's value, with room on both sides.",
                "Picking one of Forever++'s frames in Edit Mode during combat no longer gets an "
                    .. "action blocked (PlayerFrame:SetClampRectInsets()) or leaves Blizzard's Edit "
                    .. "Mode open to later errors.",
                { L.MINIMAPNODEICONS_TITLE, "Forever's own kinds of herbs and veins, like Poor "
                    .. "Copper Vein, get the icon of the one they're named after (Copper Vein) "
                    .. "right away, and a node it doesn't know learns its icon when you gather it, "
                    .. "which didn't work before." },
            } },
        },
    },
    {
        version = "1.0.0-beta.2",
        date = "2026-11-04",
        sections = {
            { L.CHANGELOG_ADDED, {
                "Other addons can read what Forever++ knows through ForeverPlusPlusAPI.v1: "
                    .. "auction prices, what disenchanting an item gives and is worth, Upgrade "
                    .. "Arrows' scores, flight times, the class, level, race, and guild of players "
                    .. "it has seen, class and level colors, dungeon and raid levels, gathering "
                    .. "skills, and each module with its options. They can set and clear the map "
                    .. "pin, and get callbacks when these change.",
            } },
        },
    },
    {
        version = "1.0.0-beta.1",
        date = "2026-11-02",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.CHATLEVELS_TITLE, "A new module that shows each player's level before their "
                    .. "name in chat, colored like a quest of that level. Forever++ remembers "
                    .. "players you group with, your guild and friends, your /who results, and "
                    .. "players you see nearby, so the level shows for players far away too. Off "
                    .. "by default." },
                { L.CLASSCOLORS_TITLE, "The new Offline Friends option (on by default) colors "
                    .. "offline friends in the friends list by the class Forever++ last saw them "
                    .. "as." },
                { L.GEARPROBE_TITLE, "A new Run button under Testing in the Debug module's "
                    .. "settings (and /fpp gearprobe) that saves what the client says about your "
                    .. "gear, its item comparison, your talents, and your stats, for the "
                    .. "developers." },
                { L.ITEMTOOLTIPS_TITLE, "The new Disenchant line (off by default) shows what "
                    .. "disenchanting green, blue, and purple gear gives on average, priced from "
                    .. "Auction Prices while that's on, or else the material it most likely "
                    .. "gives. Hold Shift for every outcome and its chance." },
                { L.ITEMTOOLTIPS_TITLE, "The new Color Stats option (on by default) shows each "
                    .. "stat on gear in its own color, including Equip: bonuses like hit and "
                    .. "spell power." },
                { L.ITEMTOOLTIPS_TITLE, "Auction Prices can use Auctionator's prices instead of "
                    .. "scanning: turn on Use Auctionator's Prices. Your own saved prices are "
                    .. "kept for when you turn it off." },
                { L.MACROS_TITLE, "A new module that makes macros shared by your characters, "
                    .. "each with its own checkbox, and deletes them when they're turned off. The "
                    .. "first is Smart Buff: it casts the buff your friendly target (or you) "
                    .. "should get from you at the best rank you know, skips buffs they already "
                    .. "have or a stronger one, buffs you instead when they can't get anything "
                    .. "from you and says why, and warns in combat when it can't change to fit a "
                    .. "new target. Off by default." },
                { L.MINIMAPBUTTON_TITLE, "The new Swap Clicks option (on by default) opens the "
                    .. "quick toggles with a click and settings with a right-click, and Error "
                    .. "Keys on Left-Click picks which click the error keys go on. Menu Side "
                    .. "opens the quick toggles to the left or right of the cursor." },
                { L.UPGRADEARROWS_TITLE, "A new module that puts Blizzard's green arrow on gear "
                    .. "that beats what you wear, judged by stat weights for your class and main "
                    .. "talent tree (or one you pick, with a Feral Bear profile for Druids). It "
                    .. "marks your bags and bank, merchants, loot and loot rolls, the best quest "
                    .. "reward, and the auction house, each with its own checkbox. A ring is "
                    .. "judged against your weaker ring and a two-hander against both hands. "
                    .. "Pick the arrow's corner, size, and padding, and show the percentage beside "
                    .. "it or in the tooltip. Options show every item's score, mark worse gear "
                    .. "with a red arrow, judge gear up to 5 levels above yours, leave profession "
                    .. "tools and the reagent bag unmarked, and hide small differences. The "
                    .. "weights start from a template per talent tree, and the Stat Weights page "
                    .. "(/fpp weights) has a slider per stat, per profile, with Import and Export "
                    .. "of Pawn strings. Off by default." },
            } },
            { L.CHANGELOG_CHANGED, {
                "Item marks, tints, and tooltip lines do much less work, so bags open more "
                    .. "smoothly while leveling.",
                { L.AUTOSTOW_TITLE, "Also puts away weapons you draw yourself, once they've been "
                    .. "out for the Delay. Pressing Sheath starts the Delay again." },
                { L.AUTOWEAPONBUFF_TITLE, "Using a stone, oil, poison, or lure from an action "
                    .. "bar puts it straight on your weapon too. Not in combat." },
                { L.CHATCOPY_TITLE, "The window looks like Forever++'s other windows." },
                { L.ITEMTOOLTIPS_TITLE, "Sell Price also shows on quest reward tooltips, so you "
                    .. "can see what each choice sells for." },
                { L.MINIMAPNODEICONS_TITLE, "Costs much less while you play: it checks the "
                    .. "minimap about once a second instead of ten times, and does nothing while "
                    .. "Find Herbs and Find Minerals are off. A new dot may take a moment longer "
                    .. "to get its icon." },
                { L.PROFILER_TITLE, "Also times work modules put off for a moment, like "
                    .. "redrawing bag marks." },
                { L.QUESTTRACKER_TITLE, "The background is a little darker by default, 40% "
                    .. "instead of 30%, unless you set its Opacity yourself." },
                { L.CHANGELOG_SETTINGS, "A module's warnings and limits sit in a gray line under "
                    .. "its description on the Modules page." },
                { L.CHANGELOG_SETTINGS, "Option names on the Modules page have more room, so "
                    .. "they wrap less, and NEW labels sit just after the checkbox." },
                { L.CHANGELOG_SETTINGS, "Console Variables, Profiler, and Debug are modules "
                    .. "under a new Tools category, off by default (on in Developer's Defaults). "
                    .. "Debug's options and buttons are in its own settings on the Modules page. "
                    .. "Turned off, a tool's page and commands go away, and Debug's options go "
                    .. "back to their defaults." },
                { L.WHISPERWINDOW_TITLE, "Shows the guild of the player you're talking to, and "
                    .. "their level, race, and class from when Forever++ last saw them." },
            } },
            { L.CHANGELOG_FIXED, {
                "An error in one module no longer breaks the Blizzard window or tooltip it "
                    .. "hooks, or other modules' changes to it.",
                "Marks, tints, and arrows on an open loot window show as soon as you turn their "
                    .. "module on.",
                "The buttons Forever++ adds beside the chat window sit below Blizzard's voice chat "
                    .. "Deafen and Mute buttons instead of on top of them.",
                "Updating from 0.8 puts Blizzard's map coordinate settings back the way you had "
                    .. "them, and gives the Quest Tracker's background and the waypoint arrow "
                    .. "today's defaults if you never changed them.",
                "Forever++'s chat messages start with the chat timestamp while timestamps are "
                    .. "on, like the game's own lines.",
                { L.ALREADYKNOWN_TITLE, "Items on a vendor's Buyback tab no longer get the marks "
                    .. "of the vendor's own items." },
                { L.ALREADYKNOWN_TITLE, "Mail in the inbox and open letters get marks again "
                    .. "after a game update broke them." },
                { L.AUTOSCREENSHOT_TITLE, "Reaching Neutral with a faction counts as a step up and "
                    .. "takes a screenshot." },
                { L.AUTOSTOW_TITLE, "No longer draws your ranged weapon when it meant to put "
                    .. "your melee weapon away." },
                { L.CHATCOPY_TITLE, "Turning Click Timestamps off no longer brings back chat lines "
                    .. "that had faded out." },
                { L.CHATFONT_TITLE, "Turning the module off gives the Communities and GM chat "
                    .. "windows their font back too." },
                { L.CHANGELOG_COMMANDS, "/fpp reset turns every module off before it wipes the "
                    .. "settings, so game settings a module changed go back to your own. In "
                    .. "combat, it waits until combat ends." },
                { L.CHANGELOG_COMMANDS, "A /fpp command whose module is off says so in chat "
                    .. "instead of opening Settings." },
                { L.FISHINGCAST_TITLE, "Changing Louder Bobber while the module is off no longer "
                    .. "changes your sound volumes." },
                { L.FLIGHTTIMER_TITLE, "Bag items and action buttons no longer get a Flight Time "
                    .. "line while the old flight map is open." },
                { L.GATHERINGTRACKING_TITLE, "Find Minerals or Find Herbs comes back on after "
                    .. "dying again: it keeps trying for a few seconds after you come back to "
                    .. "life." },
                { L.HIDEBETAFEEDBACK_TITLE, "Turning the module off always brings the feedback "
                    .. "button back." },
                { L.ITEMTOOLTIPS_TITLE, "The Auction Prices scan no longer spins forever when the "
                    .. "auction house stops answering: it asks again, then finishes with the "
                    .. "prices it has." },
                { L.ITEMTOOLTIPS_TITLE, "An auction price over 214,748 gold no longer causes an "
                    .. "error when it's saved." },
                { L.ITEMTOOLTIPS_TITLE, "The lines stay above Forever's \"Press F6\" line on items "
                    .. "like junkboxes." },
                { L.PERSISTENTCHAT_TITLE, "Chat no longer starts fading again after you leave it "
                    .. "with a gamepad." },
                { L.QUESTTRACKER_TITLE, "Turning the module on or off keeps the text size you "
                    .. "set in Edit Mode." },
                { L.CHANGELOG_SETTINGS, "The About page lists the commands of the modules that "
                    .. "are on now, not the ones that were on when it first opened." },
                { L.CHANGELOG_SETTINGS, "The About page's command list scrolls, and a long "
                    .. "description wraps instead of running off the edge." },
                { L.SOCIALBUTTON_TITLE, "Text to Speech and voice chat alerts no longer sit on top "
                    .. "of the chat buttons." },
                { L.SPELLRANKS_TITLE, "Spells in macros on your action bars get the right "
                    .. "badge." },
                { L.SPELLRANKS_TITLE, "The line about action bar spells with a higher rank shows "
                    .. "only after you learn a spell or level up, not at every login." },
                { L.SPELLRANKS_TITLE, "The warning badge sits fully inside the button's corner, "
                    .. "above its icon, border, and cooldown." },
                { L.TOOLTIPS_TITLE, "Class Color colors the class name on Russian, Korean, and "
                    .. "Chinese clients too." },
                { L.WAYPOINTS_TITLE, "The arrow sits a little lower by default and always stays "
                    .. "inside the game window. If you moved it in Edit Mode, it stays where you "
                    .. "put it." },
                { L.WHISPERWINDOW_TITLE, "A whisper you start by a player's name without their "
                    .. "surname goes to your conversation with them, and Hide Whispers in Chat "
                    .. "no longer leaves a whisper tab empty." },
                { L.WORLDMAP_TITLE, "Points of Interest no longer marks a ley line in the wrong "
                    .. "place while an older ley line buff is still on you." },
                { L.WORLDMAP_TITLE, "Unexplored Areas no longer draws straight lines over the "
                    .. "edges of explored areas." },
            } },
        },
    },
    {
        version = "0.9.0",
        date = "2026-10-14",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.ADDONSLIST_TITLE, "The new AddOn Sets option (off by default) adds a Sets "
                    .. "dropdown beside Disable All, to save which addons are on under a name and "
                    .. "turn that set back on later." },
                { L.AUTODECLINE_TITLE, "The new Guild Invites and Guild Charters options (off "
                    .. "by default) turn down guild invites and requests to sign a guild charter, "
                    .. "even from friends and guildmates." },
                { L.COMPREHENDSCROLLS_TITLE, "A new module for Mages: right-click a scroll you "
                    .. "read with Comprehension in your bags to cast Comprehend Scroll on it, "
                    .. "without opening the spellbook. Not in combat. On by default; it does "
                    .. "nothing for characters without the spell." },
                { L.COMBATALERT_TITLE, "The new Play Sound option (off by default) plays the "
                    .. "raid warning sound as you enter combat and a soft chime as you leave, for "
                    .. "when you're looking somewhere else." },
                { L.FISHINGCAST_TITLE, "The new Louder Bobber option (off by default) turns sound "
                    .. "effects up and music down while you fish, so the splash is easy to hear, "
                    .. "and puts your own volumes back after you stop, even after a reload or "
                    .. "disconnect mid-cast." },
                { L.ITEMTOOLTIPS_TITLE, "The new Repair Cost line (off by default) shows what "
                    .. "repairing damaged gear costs, on gear you wear or carry, without a "
                    .. "merchant's repair cursor." },
                { L.FLIGHTTIMER_TITLE, "The new Sound on Landing option (off by default) plays "
                    .. "the ready check sound a few seconds before you land, on a flight you've "
                    .. "taken before, so you can tab out on long flights." },
                { L.FOREVERQUESTICONS_TITLE, "The new Quest Details option (on by default) puts the "
                    .. "icon after the quest's name at the top of its details, in the quest window "
                    .. "and on the map." },
                { L.MINIMAPNODEICONS_TITLE, "A new module that puts the herb's or ore's own icon "
                    .. "on each tracking dot on the minimap while Find Herbs or Find Minerals is "
                    .. "on. Off by default. Its Tint Unusable option (off by default) turns an icon "
                    .. "red while your skill is too low to gather it, and Gray Out Trivial (off by "
                    .. "default) turns it gray once gathering it no longer raises your skill." },
                { L.NPCNAMEPLATES_TITLE, "The new Skip Pets, Skip Totems, and Skip Companions "
                    .. "options (off by default) leave players' pets and minions, totems, or "
                    .. "companions with Blizzard's own nameplate instead of a name and title." },
                { L.PROFILER_TITLE, "A new page in Settings (/fpp profile) that records how "
                    .. "much CPU each module takes, heaviest first, beside Forever++'s total CPU "
                    .. "and memory. A module made of parts folds open to show what each part "
                    .. "takes. Nothing is timed until you press Record." },
                { L.QUESTLEVELS_TITLE, "A new module that shows a quest's level before its name, "
                    .. "like the quest log's [12], in a quest giver's list and at the top of the "
                    .. "quest's details. On by default. Its Color by Difficulty option (off by "
                    .. "default) colors the level gray through red by how it compares with yours." },
                { L.QUESTTRACKER_TITLE, "The new Current Zone Only option (off by default) tracks "
                    .. "only the quests of the zone you're in, and tracks the others again when you "
                    .. "get there. The quest your map follows always shows." },
                { L.TALENTPLANNER_TITLE, "The new Level-Up Reminder option (off by default) says "
                    .. "in chat which talent your plan takes next when you gain a talent point." },
                { L.TOOLTIPS_TITLE, "The new Hide Health Bar option (off by default) hides the "
                    .. "green health bar under player and NPC tooltips." },
                { L.UNUSABLEITEMSTINT_TITLE, "The new Auction House and Loot options (off by "
                    .. "default) tint red the items you can't use in the auction house's search "
                    .. "results, and in the loot window and on loot rolls." },
                { L.WAYLAIDCRATES_TITLE, "A new module for filling Waylaid Crates. Its Waylaid "
                    .. "Crates entry in the auction house's categories lists every item your crates "
                    .. "still need, less what's already in your bags and bank." },
                { L.WAYPOINTS_TITLE, "The new Follow Selected Quest option (on by default) points "
                    .. "the arrow to the quest selected on the map instead of your map pin, and "
                    .. "back to the pin when no quest is selected. Its Show Quest Name option (on "
                    .. "by default) shows the quest's name under the distance." },
                { L.WAYPOINTS_TITLE, "The new Point to Corpse option (on by default) points the "
                    .. "arrow to your corpse while you're a ghost, ahead of a quest or your map "
                    .. "pin, and back to them once you're alive." },
                { L.WAYPOINTS_TITLE, "The new Clear Pin on Arrival option (off by default) takes "
                    .. "your map pin away once you reach it." },
                { L.WHISPERWINDOW_TITLE, "A new module that keeps whispers in a messenger "
                    .. "window of their own: your conversations on the left with unread counts, "
                    .. "and the one you pick on the right with who they are and a box to reply in. "
                    .. "Battle.net whispers and the ones you send from chat go there too, saved "
                    .. "for each character. Open it with /fpp whispers or the button beside the "
                    .. "chat window, which pulses while whispers wait. Off by default." },
                { L.WORLDMAP_TITLE, "Points of Interest's new Ley Line Icon option (Portal by "
                    .. "default) draws ley lines as the blue swirl the minimap shows for one, or "
                    .. "as the purple orb they were before." },
                { L.XPBARTEXT_TITLE, "The new Fill Bar with Ready Quests option (on by default) fills the "
                    .. "experience bar on from your XP in green with what your quests ready to turn "
                    .. "in will give, like rested XP." },
                { L.XPBARTEXT_TITLE, "The new Detailed Tooltip option (on by default) adds to the "
                    .. "bar's tooltip the XP left to level, your rested XP, the XP of your quests, "
                    .. "and your XP per hour and time to level since you logged in." },
                { L.XPBARTEXT_TITLE, "The new Green When Quests Level You option (on by default) turns off "
                    .. "the green quest XP text shown once turning those quests in would level you." },
                { L.AUTORELEASE_TITLE, "The new Skip Key option (None by default) lets you hold "
                    .. "a key while you're dead to stay where you fell." },
                { L.CHANGELOG_SETTINGS, "An option you've changed has an undo arrow at the end of "
                    .. "its row that sets it back to its default, and its tooltip says what the "
                    .. "default is." },
                { L.CHANGELOG_SETTINGS, "The Changelog page has a By Module checkbox (on by "
                    .. "default) that groups a release's notes under their modules instead of "
                    .. "Added, Changed, and Fixed." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.AUTOGOSSIP_TITLE, "Off by default for new installs, and so is Other NPCs. "
                    .. "If you already use it, it stays as you had it." },
                { L.CHARACTERWINDOW_TITLE, "With Colored Title on, the game's own \"Level 18 "
                    .. "Mage\" line at the top of the window is hidden, since the title already "
                    .. "shows your level, and your character's background fills the empty strip it "
                    .. "sat on, with the zoom and rotate buttons and your character moved up into "
                    .. "it. Your pet's line on the pet pane stays." },
                { L.AUTOWEAPONBUFF_TITLE, "An item it doesn't know yet, or a stone on a fist "
                    .. "weapon, works from a right-click too once you've put it on that kind of "
                    .. "weapon by hand, for every character." },
                { L.QUESTTRACKER_TITLE, "Fade in Combat has a Combat Opacity slider, from 0 to "
                    .. "80%, for how faint the tracker gets in combat. It starts at 30%, as before." },
                { L.WAYLAIDCRATES_TITLE, "Item Tooltips' Waylaid Crate Costs option moved here as "
                    .. "Bundle Costs, keeping your choice." },
                { L.WORLDMAP_TITLE, "Coordinates follows Blizzard's coordinate settings under "
                    .. "Gameplay > Interface instead of its own checkboxes, which turned them back on "
                    .. "at every login." },
                { L.WORLDMAP_TITLE, "Dungeon levels come from the game's dungeon finder, and "
                    .. "Forever dungeons it lists that Forever++ didn't know get their names and "
                    .. "levels in map tooltips." },
                { L.WORLDMAP_TITLE, "Zone Info shows the game's own level range for a zone when "
                    .. "it has one. Points of Interest places flight masters where a flight "
                    .. "master's map shows them and adds ones its list lacks, and Unexplored Areas "
                    .. "adds areas its art lacks once one of your characters explores them." },
                { L.QUESTTRACKER_TITLE, "Font Size is gone: Edit Mode's Text Size sets the "
                    .. "tracker's size." },
                { L.PROFTOOLTIPS_TITLE, "On a lockbox whose tooltip already says what "
                    .. "Lockpicking it needs, colors that line instead of adding a second one, and "
                    .. "remembers the skill, so a box Forever changed shows the right number." },
                { L.CHANGELOG_SETTINGS, "The Modules page has new Character, Quests, System, and "
                    .. "Units categories, listed in alphabetical order." },
                { L.CHANGELOG_SETTINGS, "Hold Shift to Skip and Hold Shift to Watch are now Skip "
                    .. "Key and Watch Key dropdowns (Shift, Ctrl, Alt, or None), like Auto Quest's." },
                { L.CHANGELOG_SETTINGS, "Options look and read the same across modules: Item "
                    .. "Tooltips' parts each have an Enabled checkbox, sliders are shorter, buttons "
                    .. "that throw away data say Clear, and modules say when a Blizzard setting "
                    .. "they need is off." },
                { L.CHANGELOG_SETTINGS, "Forever++ saves only the settings you change, so a "
                    .. "better default reaches you, and saves talent plans and learned flight points "
                    .. "for each character. Saved auction prices take about 60% less room. "
                    .. "Everything you had carries over." },
                { L.CHANGELOG_COMMANDS, "/fpp reset asks first, and module names in /fpp match "
                    .. "their titles, such as /fpp toggle BagSlotCounter." },
                { L.CHATCOPY_TITLE, "Copies everything the chat window holds. The Lines slider is "
                    .. "gone, since a window keeps only its last 128 lines." },
                { L.CHATHISTORY_TITLE, "Lines Saved goes up to 125, about all a chat window holds." },
                { L.CHATHISTORY_TITLE, "Saves each character's chat on its own, so an alt doesn't "
                    .. "log in to another character's. The first character you log in with keeps "
                    .. "the chat saved before." },
                { L.AUTOSCREENSHOT_TITLE, "Played Time on Level Up sits under Level Up and works "
                    .. "only while Level Up is on, since it's for that screenshot." },
                { L.ALREADYKNOWN_TITLE, "The Loot option also marks known items on group loot "
                    .. "rolls, before you choose Need or Greed." },
                { L.AUTOSELLJUNK_TITLE, "Keep Everything Buyable Back sells only as much junk as "
                    .. "the buyback list has room for beside what you sold yourself, so an item "
                    .. "sold by mistake stays buyable." },
                { L.AUTOGOSSIP_TITLE, "Learns which kind of NPC an option is for from the "
                    .. "window it opens, so a banker, vendor, trainer, or flight master the game "
                    .. "marks differently is picked by its own checkbox after you pick it once." },
                { L.AUTOGOSSIP_TITLE, "Also picks an NPC's one service when its other options "
                    .. "are only small talk, so weapon masters open their training." },
                { L.BAGSLOTCOUNTER_TITLE, "The count turns orange when 4 or fewer slots are free. "
                    .. "The new Color When Low option sets that number, or turns the colors off." },
                { L.CURRENCYBAR_TITLE, "With nothing to show, it says how to track currencies "
                    .. "instead of showing an empty box." },
                { L.ERRORCATCHER_TITLE, "Says on its Settings page, instead of in chat, when "
                    .. "another addon such as BugGrabber is catching Lua errors, and leaves "
                    .. "Blizzard's error window and blocked action popup to it." },
                { L.FLIGHTTIMER_TITLE, "The flight map tooltip's Flight Time line looks like the "
                    .. "Sell Price line, with the time at the right. The new Tooltip Line option "
                    .. "puts it back on one line, white or gray." },
                { L.PROFTOOLTIPS_TITLE, "Learns herbs and veins it doesn't know, and a skill "
                    .. "Forever changed, from the game's own \"Requires Herbalism\" line, so it "
                    .. "works in any language." },
                { L.MINIMAPBUTTON_TITLE, "Shift-click it, instead of Shift-right-click, to see "
                    .. "the errors, Ctrl-click it to clear this session's, and the new Alt-click "
                    .. "clears every saved error after asking. Each key is an option: Show Errors "
                    .. "Key, Clear Session Key (once Clear Key), and Clear All Key." },
                { L.MINIMAPBUTTON_TITLE, "A tidier tooltip: the version beside the title, the "
                    .. "error counts with the number at the right (this session's in red, saved "
                    .. "ones in gold), then each click's action with its click beside it in green, "
                    .. "such as Shift-Left-Click, leaving out a key set to None." },
                { L.MINIMAPBUTTON_TITLE, "The right-click menu also turns Auto Decline, Auto "
                    .. "Dismount, Auto Gossip, Auto Release, Auto Repair, Auto Screenshot, Minimap "
                    .. "Node Icons, Movable Framerate, and Skip Cinematics on and off, grouped by "
                    .. "what you're doing (Vendors and Loot, NPCs and Quests, Out in the World, and "
                    .. "Other)." },
                { L.SHORTCHANNELNAMES_TITLE, "The Style dropdown also offers initials ([LFG] for "
                    .. "LookingForGroup) and the name without its zone ([General]), alone or after "
                    .. "the number. Number and Initials ([1. LFG]) is the new default." },
                { L.SHORTCHANNELNAMES_TITLE, "The new Guild, Party, and Raid option (on by "
                    .. "default) also shortens [Guild], [Officer], [Party], [Raid], [Raid Warning], "
                    .. "and [Instance] to [GD], [O], [P], [R], [RW], and [I]." },
                "The Error Catcher and Chat Copy windows close with Escape, like Blizzard's "
                    .. "windows.",
                "Buff Timers, Waypoints, Quest Tracker, Quest Nameplates, Player and NPC "
                    .. "Nameplates, and Already Known use less CPU: they look the same and redo "
                    .. "their work only when something changed.",
            } },
            { L.CHANGELOG_FIXED, {
                { L.XPBARTEXT_TITLE, "Blizzard's own XP text no longer shows through under ours "
                    .. "after a reload." },
                { L.CLASSCOLORS_TITLE, "Hostile NPCs' health bars are red, like their names, "
                    .. "instead of sometimes yellow or green." },
                { L.CHANGELOG_COMMANDS, "/fpp toggle on a tool, such as Self Test, says it's always "
                    .. "on, instead of that it's off." },
                { L.PROFTOOLTIPS_TITLE, "Recolors the \"Requires\" line on nodes and creatures in "
                    .. "languages that number its parts (such as \"%1$s\"), which it missed "
                    .. "before." },
                { L.CHARACTERWINDOW_TITLE, "With Side Tabs on, your level shows above your "
                    .. "character again, and your pet's on the pet pane, where the game now puts "
                    .. "them." },
                { L.CHARACTERWINDOW_TITLE, "The Skills tab shows your equipped weapons' skills in "
                    .. "green right after you log in, instead of only once you change a weapon or "
                    .. "reload." },
                { L.CHARACTERWINDOW_TITLE, "Durability bars are read again each time the window "
                    .. "opens, so they're right after you log in." },
                { L.AUTODECLINE_TITLE, "Asks for your guild's roster again once your guild is "
                    .. "known after logging in, so guildmates' duels aren't declined while Allow "
                    .. "Friends and Guild is on." },
                { L.GATHERINGTRACKING_TITLE, "After logging in, waits a few more seconds for the "
                    .. "tracking list to fill before giving up on turning tracking back on." },
                "Chat Font, Persistent Chat, Short Channel Names, and Chat Copy's Click Timestamps "
                    .. "also work in whisper windows popped out into their own tab.",
                { L.PLAYERNAMEPLATES_TITLE, "Battle.net friend icons and guildmate colors update "
                    .. "as those lists change, and names on player and NPC plates get smaller again "
                    .. "when you make nameplates smaller." },
                { L.ADDONSLIST_TITLE, "Shows which addons are on for the character picked in the "
                    .. "dropdown, or for All, instead of always for you." },
                { L.ITEMTOOLTIPS_TITLE, "Auction Prices turned on with the auction house open can "
                    .. "scan it without reopening it." },
                { L.BUFFTIMERS_TITLE, "Edit Mode's example buffs and debuffs don't keep an old "
                    .. "clock." },
                { L.CLASSCOLORS_TITLE, "Turning name backgrounds off puts back the target frame's "
                    .. "own color." },
                { L.AUTOWEAPONBUFF_TITLE, "Right-clicking a stone or oil in your bags at the guild "
                    .. "bank deposits it instead of putting it on your weapon." },
                { L.AUTODECLINE_TITLE, "Allow Friends and Guild lets party invites from "
                    .. "guildmates through even before your guild roster has loaded." },
                { L.WORLDMAP_TITLE, "Points of Interest no longer causes an error each time a "
                    .. "Skyborne casts a spell in combat. A Read Ley Line or Skysight cast in "
                    .. "combat saves its spot once combat ends." },
            } },
        },
    },
    {
        version = "0.8.4",
        date = "2026-10-11",
        sections = {
            { L.CHANGELOG_FIXED, {
                { L.ITEMTOOLTIPS_TITLE, "Waylaid Crate Costs shows each bundle's price again, "
                    .. "instead of No price, which 0.8.2 broke." },
            } },
        },
    },
    {
        version = "0.8.3",
        date = "2026-10-11",
        sections = {
            { L.CHANGELOG_FIXED, {
                { L.AUTOWEAPONBUFF_TITLE, "Right-clicking a stone, oil, poison, or lure in your "
                    .. "bags puts it on your weapon again, which 0.8.2 broke." },
            } },
        },
    },
    {
        version = "0.8.2",
        date = "2026-10-11",
        sections = {
            { L.CHANGELOG_CHANGED, {
                { L.AUTOWEAPONBUFF_TITLE, "When no equipped weapon can take the item, like a "
                    .. "weightstone with only blades, it says so in red at the top of the screen "
                    .. "instead of bringing up a cursor. On by default; turn it off with Warn When "
                    .. "No Weapon Fits." },
                { L.BUFFTIMERS_TITLE, "Show Clock has an Under 1 Minute choice, for a clock only "
                    .. "on auras about to run out." },
                { L.CHARACTERWINDOW_TITLE, "The new Equipped Weapon Skills option (on by "
                    .. "default) colors the Skills tab's bars green for the weapons you have "
                    .. "equipped, instead of blue." },
                { L.CHATHISTORY_TITLE, "No longer saves whispers, so they aren't written to your "
                    .. "saved settings file." },
                { L.CONSOLEVARIABLES_TITLE, "Laid out like the Modules page: Changed, All, and the "
                    .. "game's own categories on the left, each with how many match the search, "
                    .. "and their console variables beside it with each one's help text under its "
                    .. "name. The Changed group replaces the Changed Only checkbox." },
                { L.ITEMTOOLTIPS_TITLE, "The new Waylaid Crate Costs option shows beside each "
                    .. "bundle a Waylaid Crate takes what buying it costs at the auction house, "
                    .. "from your scanned prices. It can go under each bundle instead, or be "
                    .. "turned off." },
                { L.QUESTTRACKER_TITLE, "The new Sort by Level option (off by default) lists "
                    .. "tracked quests by level, lowest or highest first, instead of in the "
                    .. "order you tracked them. It waits for combat to end." },
                { L.CHANGELOG_SETTINGS, "The Changelog page lists the releases on the left, "
                    .. "like the Modules page, with the selected one's notes beside it in larger "
                    .. "text. Releases since the version you last saw are marked NEW, and a "
                    .. "search box shows only the changes that mention what you type." },
                { L.TALENTPLANNER_TITLE, "Counts the Legacy perk Talented: with it, plans get "
                    .. "talent points from level 5 instead of 10, still 51 at most." },
                { L.WORLDMAP_TITLE, "Points of Interest draws spirit healers as a glowing spirit "
                    .. "instead of a tombstone, so they aren't mistaken for your corpse." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.ALREADYKNOWN_TITLE, "The Tint look no longer turns white the red icons of "
                    .. "merchant items you can't use, and the bags only look up items that can be "
                    .. "known, like recipes, mounts, and pets." },
                { L.AUTODECLINE_TITLE, "A friend or guildmate you let through gets Blizzard's "
                    .. "usual invite popup again instead of one showing only their name, and a "
                    .. "declined group finder invite closes its popup too." },
                { L.AUTOSCREENSHOT_TITLE, "A second shot right after another no longer shows the "
                    .. "interface with Hide Interface on, and a shot the game never reports no "
                    .. "longer stops the ones after it." },
                { L.AUTOWEAPONBUFF_TITLE, "A window over your bags no longer has its clicks taken "
                    .. "by a stone, oil, poison, or lure under it." },
                { L.BUFFTIMERS_TITLE, "Never shows a negative time, like -1:59, on an aura about to "
                    .. "go away." },
                { L.COMMANDS_TITLE, "/rl and /clear are left to another addon that has them even "
                    .. "after you've typed a slash command, and turning one on says so in chat." },
                { L.CURRENCYBAR_TITLE, "Stays on screen on smaller screens, and Reset Position puts "
                    .. "it back where it starts." },
                { L.ERRORCATCHER_TITLE, "A link or color in an error shows as plain text in its "
                    .. "chat message, and it keeps the last 100 errors with shorter stacks, so "
                    .. "its saved file stays small." },
                { L.FLIGHTTIMER_TITLE, "Turning Bar on during a flight shows the bar for the rest "
                    .. "of it." },
                { L.HIDEBETAFEEDBACK_TITLE, "Turning it off puts the quest windows' feedback alert back "
                    .. "as it was." },
                { L.HIDEFILTERRESET_TITLE, "Turning it off gives the mouse back only to the parts "
                    .. "that had it before." },
                { L.ITEMTOOLTIPS_TITLE, "Your own auction house searches keep an item's lowest "
                    .. "price instead of the last one listed." },
                { L.PLAYERNAMEPLATES_TITLE, "A player who turns hostile, like in a duel, gets "
                    .. "Blizzard's own nameplate back, health bar and all. So does an NPC that turns "
                    .. "hostile with NPC Nameplates on." },
                { L.PLAYERNAMEPLATES_TITLE, "Puts your game settings back at login if it was turned "
                    .. "off in combat just before a reload. So do NPC Nameplates, Auto Dismount, and "
                    .. "World Map's Coordinates." },
                { L.QUESTNAMEPLATES_TITLE, "An objective that needs 100 of something shows as 37/100, "
                    .. "not 37%. Creatures that showed up during a fight get their quest icon once "
                    .. "it's over." },
                { L.RECIPECOLORS_TITLE, "Turning it off clears the tint from every recipe row, not "
                    .. "only the ones on screen." },
                { L.CHANGELOG_SETTINGS, "The Modules page no longer errors when it opens on a "
                    .. "module marked NEW." },
                { L.CHANGELOG_SETTINGS, "Recommended Defaults and Developer's Defaults keep where you "
                    .. "moved things and their size in Edit Mode, and reset only the options." },
                { L.SHORTCHANNELNAMES_TITLE, "Turning it off gives channels already in chat their full "
                    .. "names again." },
                { L.SOCIALBUTTON_TITLE, "Turning it off no longer leaves Chat Copy's button above "
                    .. "the chat window." },
                { L.TALENTPLANNER_TITLE, "Refuses a shared plan with more than 51 points, which could "
                    .. "freeze the game, and a shared plan's name can't carry colors, icons, or "
                    .. "links." },
                { L.UNUSABLEITEMSTINT_TITLE, "No longer tints recipes you can learn because of the "
                    .. "item they make, such as plans for mail armor or for gear above your level." },
                { L.WAYPOINTS_TITLE, "/way is left to TomTom or another addon that has it even "
                    .. "after you've typed a slash command, and turning Waypoints on says so in "
                    .. "chat." },
                { L.WORLDMAP_TITLE, "Zone Info shows herb and ore names in your language the first "
                    .. "time, instead of in English until the map changed." },
            } },
        },
    },
    {
        version = "0.8.1",
        date = "2026-10-10",
        sections = {
            { L.CHANGELOG_FIXED, {
                { L.AUTOWEAPONBUFF_TITLE, "Puts the buff on your weapon again, since Forever "
                    .. "blocks the way it did before. Right-click a sharpening stone, weightstone, "
                    .. "oil, poison, or fishing lure in your bags and it goes straight onto your "
                    .. "weapon, main hand first as before. Not in combat, when the bags work as usual." },
                { L.CHANGELOG_SETTINGS, "Reset Seen Version on the Debug page goes back to the "
                    .. "release before the one you have, so it marks what changed in this release "
                    .. "instead of nothing." },
            } },
        },
    },
    {
        version = "0.8.0",
        date = "2026-10-10",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.TALENTPLANNER_TITLE, "New, on by default, in Interface: a Plan Talents "
                    .. "button on the talent window. Place talents freely without learning them, "
                    .. "in order, up to the points you have at a level you choose, then follow the "
                    .. "plan as you level: its next talent glows, tooltips say at which level "
                    .. "each rank comes, and hovering the line beside the button lists the plan "
                    .. "in order. A dropdown keeps several named plans, and shares or imports one "
                    .. "as a line of text." },
                { L.COMMANDS_TITLE, "New, on by default, in Interface: short slash commands, "
                    .. "each with its own checkbox. /rl reloads the UI, and /clear empties a chat "
                    .. "window. A command another addon already has is left to it." },
                { L.WAYPOINTS_TITLE, "New, on by default, in Map: /way [zone] x y puts the "
                    .. "game's map pin on a spot and tracks it (/way clear takes it away), unless "
                    .. "TomTom or another addon already has /way. The new Waypoint Arrow option "
                    .. "(on by default) shows an arrow on screen that turns toward the pin, from "
                    .. "/way or a click on the map, with how far it is. Move and resize it in Edit Mode." },
                { L.AUTOQUEST_TITLE, "New, off by default, in Automation: accepts quests and "
                    .. "turns in finished ones as you talk to quest givers, one by one down a "
                    .. "quest giver's list. It never picks a reward when there's a choice. "
                    .. "Accepting and turning in have their own checkboxes, repeatable and shared "
                    .. "quests can be left out, and holding Shift (or Ctrl, Alt, or no key) lets "
                    .. "you do it yourself." },
                { L.AUTOWEAPONBUFF_TITLE, "New, off by default, in Automation: using a "
                    .. "sharpening stone, weightstone, oil, poison, or fishing lure puts it "
                    .. "straight onto your weapon, without clicking the weapon. Main hand first; "
                    .. "the off hand when only it can take it, or when the main hand already has "
                    .. "a buff and the off hand doesn't (or its buff runs out sooner)." },
                { L.BUFFTIMERS_TITLE, "New, on by default, in Interface: the time left under "
                    .. "your buff and debuff icons as a clock, like 1:23, instead of rounded "
                    .. "minutes like 2 m. Choose under 10 minutes (the default), under an hour, "
                    .. "or always. When "
                    .. "the game hides an aura's time in combat, Blizzard's own timer shows." },
                { L.UNUSABLEITEMSTINT_TITLE, "New, on by default, in Items: tints red the items "
                    .. "you can't use, because of your class, armor or weapon skill, level, or "
                    .. "profession, in your bags, the bank, and at merchants, the way merchants "
                    .. "tint them. At merchants it only adds what the merchant doesn't already "
                    .. "tint, such as gear above your level. Bags, bank, and merchants each have "
                    .. "a checkbox." },
                { L.XPBARTEXT_TITLE, "New, on by default, in Interface: the experience bar "
                    .. "shows its numbers all the time, with the percent, your rested XP, and the "
                    .. "XP of the quests in your log that are ready to turn in (or all of them), "
                    .. "in green once turning them in would level you." },
                { L.MINIMAPBUTTON_TITLE, "New, on by default, in Interface: Forever++'s own "
                    .. "button on the minimap, in the addon compartment, or both. Click it to open "
                    .. "Forever++ settings, or right-click it for quick toggles of Fast Loot, Auto "
                    .. "Quest, Auto Sell Junk, Auto Stow, Fishing Cast, Gathering Tracking, and "
                    .. "Hide Beta Feedback. While Error Catcher is on, Shift-right-click it "
                    .. "to see the errors, and it shows how many this session caught. After a "
                    .. "fresh install it wears Blizzard's NEW label, and its first click opens the "
                    .. "About page." },
                { L.CHANGELOG_SETTINGS, "A search box at the top of the Modules page shows only "
                    .. "the modules whose name, description, or options have what you type, with "
                    .. "those options highlighted. The New checkbox beside it shows only the "
                    .. "modules marked NEW." },
                { L.CHANGELOG_SETTINGS, "The Modules page marks new modules, and new or changed "
                    .. "options, with Blizzard's NEW label until you've clicked the module, and "
                    .. "opens on the first module with a marked option." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.ITEMTOOLTIPS_TITLE, "Sell Price, Auction Prices, and Item Count are now one "
                    .. "module, Item Tooltips, in Items, with a checkbox for each. Price For and "
                    .. "Alignment are shared by all its lines, so they always line up. Your "
                    .. "choices, auction prices, and bank counts come along; Sell Price's Price "
                    .. "For and Alignment win if they differed." },
                { L.ITEMTOOLTIPS_TITLE, "Crafting Costs shows Estimated Profit, after the "
                    .. "auction house's 5% cut, and, at the top, how old the oldest auction "
                    .. "price in the totals is." },
                { L.WORLDMAP_TITLE, "Points of Interest, Zone Info, Unexplored Areas, and "
                    .. "Coordinates are now one World Map module, with a section for each in its "
                    .. "options and an Enabled checkbox at the top of each section. Your choices, "
                    .. "learned flight points, and ley lines come along." },
                { L.CLASSCOLORS_TITLE, "New Friends and Who List option (on by default) shows "
                    .. "online friends' names in the friends list and names in the who list in "
                    .. "their class color." },
                { L.CHATCOPY_TITLE, "The window shows chat lines in their chat colors, with "
                    .. "names in their class colors and links in theirs, the way they look in "
                    .. "chat. Copying still gives plain text." },
                { L.CHATCOPY_TITLE, "New Click Timestamps option (off by default): click a chat "
                    .. "line's timestamp to copy that line. Needs the game's chat timestamps "
                    .. "turned on." },
                { L.ERRORCATCHER_TITLE, "Its button is now the Minimap Button module, where a "
                    .. "click opens settings and a Shift-right-click shows the errors. Turn that "
                    .. "module off for no button. Its Clear Key option moved there too: "
                    .. "Ctrl-right-click still clears this session's errors. If you had turned "
                    .. "Error Catcher's button off, the Minimap Button goes in the addon "
                    .. "compartment instead." },
                { L.CHANGELOG_SETTINGS, "Clutch's Default is now Developer's Defaults, and the "
                    .. "welcome page's Defaults button is now Recommended Defaults, matching the "
                    .. "Defaults popup on the Modules and Debug pages." },
                { L.CHANGELOG_SETTINGS, "Forever++ in the AddOns list, /fpp, and the minimap "
                    .. "button open the Modules page. The welcome page is now the About page, "
                    .. "at the bottom of the list, with the version, links, and commands, and the "
                    .. "same Defaults button at the top right as the Modules page." },
                { L.CHANGELOG_SETTINGS, "The Modules page lists every module on the left, each "
                    .. "with its checkbox, and shows the one you click on the right: its title, "
                    .. "what it does, an Enabled checkbox, and its options and buttons. No "
                    .. "more gears or options opening inside the list. Modules with many options "
                    .. "group them under headers, and options that only matter while another is "
                    .. "on sit under it: Player Nameplates, NPC Nameplates, World Map, Quest "
                    .. "Tracker, Profession Tooltips, and Item Tooltips." },
                { L.CHANGELOG_SETTINGS, "Clearer names and descriptions for a few options: Auto "
                    .. "Quest's Skip Key, Item Tooltips' Bag and Bank Labels, Unexplored Areas' Tint "
                    .. "Strength, and Zone Info's Herbs, Ore, and Skinning." },
                { L.CHARACTERWINDOW_TITLE, "Character Frame Enhancements is now Character "
                    .. "Window, so its name fits the Modules list, and Durability Bars is now its "
                    .. "Durability Bars option instead of a module of its own (always, only when "
                    .. "worn, below 50% or 25%, or off), set to what you had." },
                { L.AUTOSCREENSHOT_TITLE, "Now listed under Automation instead of Interface." },
                { L.AUTOSCREENSHOT_TITLE, "New Played Time on Level Up option (off by default) "
                    .. "shows your /played time in chat when you level up, so it's in the "
                    .. "screenshot." },
                { L.AUTOSCREENSHOT_TITLE, "New Your Own Screenshots option (off by default), "
                    .. "under Hide Interface, hides the interface for the screenshots you take with "
                    .. "the Screenshot key (Print Screen) too, not only Auto Screenshot's. Not in "
                    .. "combat." },
                { L.POI_TITLE, "New Ley Lines option shows Skyborne ley lines and elemental "
                    .. "convergences on the map. A spot is saved when a Skyborne gets the "
                    .. "15-minute buff from Read Ley Line or Skysight there, and every character "
                    .. "on the account sees it. Shown to Skyborne for their own kind by default, "
                    .. "or to everyone, or to no one." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.CHARACTERWINDOW_TITLE, "Works with Forever's new Titles tab. Titles gets its "
                    .. "own side tab, the Pet tab opens your pet's stats again instead of Titles, "
                    .. "the titles list starts at the top and runs further down like the stats, "
                    .. "and the pet pane keeps your pet's level and loyalty. Your pet's tab also "
                    .. "comes and goes with your pet while another tab is open, and a tab you "
                    .. "can't use yet (no titles, no pet) says why when you point at it. The side "
                    .. "tabs sit as close together as Blizzard's, and get a little smaller when "
                    .. "needed, so the last one stays on the window." },
                { L.CONSOLEVARIABLES_TITLE, "An empty list says why (nothing matches the search, or "
                    .. "nothing is changed), and a row stays highlighted with its tooltip while "
                    .. "you point at its value box or Default button." },
            } },
        },
    },
    {
        version = "0.7.0",
        date = "2026-10-02",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.BESTQUESTREWARD_TITLE, "New, on by default, in Items: marks the quest reward that "
                    .. "sells to a vendor for the most with a gold coin, in the quest window and "
                    .. "the quest log." },
                { L.ITEMCOUNT_TITLE, "New, off by default, in Items: shows in an item's tooltip "
                    .. "how many you own, in your bags and in your bank." },
                { L.EASYDELETE_TITLE, "New, off by default, in Items: types DELETE for you when "
                    .. "you destroy a good item." },
                { L.MOVABLEFRAMERATE_TITLE, "New, off by default, in Interface: move and resize the "
                    .. "framerate text (Ctrl+R) in Edit Mode." },
                { L.AUCTIONPRICES_TITLE, "New Crafting Costs option shows a recipe's total cost, "
                    .. "value, and profit in the professions window. Reagent tooltips there now "
                    .. "price the amount the recipe needs, for Sell Price too." },
                { L.FISHINGCAST_TITLE, "New Combat Warning option warns you when combat starts "
                    .. "with a fishing pole equipped." },
                { L.POI_TITLE .. ", " .. L.ZONEINFO_TITLE, "Forever's new boats and skyships, "
                    .. "and the Excavation Site and City of Dalaran dungeons." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.POI_TITLE, "Forever's flight masters are named for their places, and its "
                    .. "dungeons show in your language." },
                { L.ERRORCATCHER_TITLE, "A redesigned window with a list of errors and a Copy Bug "
                    .. "Report button. Right-click the minimap button to open Forever++ settings." },
                { L.SPELLRANKS_TITLE, "\"Higher Rank Known:\" in spell tooltips now looks like "
                    .. "the other tooltip lines." },
            } },
            { L.CHANGELOG_FIXED, {
                { "Edit Mode", "The arrow keys nudge Combat Alert, Currency Bar, and Flight Timer "
                    .. "again." },
                { L.AUCTIONPRICES_TITLE, "A price's age is when the item was last seen, not the "
                    .. "last scan. Saved prices are cleared once." },
                { L.SELLPRICE_TITLE, "No more Lua error on a vendor's buyback tab." },
            } },
        },
    },
    {
        version = "0.6.0",
        date = "2026-10-01",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.QUESTTRACKER_TITLE, "New, on by default, in Interface: restyles Blizzard's "
                    .. "quest tracker with a font, size, and outline, a dark box behind it that "
                    .. "fits your quests, and fading in combat. It's still Blizzard's tracker, so "
                    .. "Edit Mode and quest items work as before." },
                { L.ERRORCATCHER_TITLE, "New, on by default, in Interface: catches Lua errors "
                    .. "and blocked actions in place of Blizzard's error popup, saves them per "
                    .. "session, and shows them in a window you can copy from (/fpp errors or the "
                    .. "minimap button). Ctrl-right-click the minimap button to clear this "
                    .. "session's errors." },
                { "Character Frame Enhancements", "New, on by default, in Interface: moves the Character "
                    .. "window's Equipment and Pet tabs to the side with the others, removes the "
                    .. "portrait and level line so the stats start at the top, and shows your "
                    .. "level and name in your class color as the title." },
                { L.FOREVERQUESTICONS_TITLE, "New, on by default, in Interface: marks quests that are "
                    .. "new to Forever with an infinity sign (or the Forever logo) after their "
                    .. "name in the quest log, the objective tracker, and quest givers' lists. "
                    .. "Idea from ForeverQuestTint." },
                { L.QUESTNAMEPLATES_TITLE, "New Party Progress option to count everyone's progress "
                    .. "added up (the default), only yours, or the party member furthest from "
                    .. "done. Creatures only a party member needs now show too." },
                { L.CLASSCOLORS_TITLE, "The Names checkbox is now a Name Color choice (Default, "
                    .. "White, or Class Color), and a new Name Backgrounds option (on by default) "
                    .. "tints the bar behind a player's name on the target and focus frames in "
                    .. "their class color." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.PERSISTENTCHAT_TITLE, "Renamed from Chat Fading, and now on by default." },
                { L.AUTOREPAIR_TITLE, "Holding Shift to skip is now an option (on by default)." },
                { L.AUTOSELLJUNK_TITLE, "Holding Shift to skip is now an option (on by default)." },
                { L.CHANGELOG_SETTINGS, "The Defaults button on the Modules and Debug pages now "
                    .. "offers Clutch's Defaults or Recommended Defaults and resets only "
                    .. "Forever++. Blizzard's All Settings reset no longer touches Forever++." },
                { L.CHANGELOG_SETTINGS, "Clutch's Default also sets Zone Info's Dungeons and "
                    .. "Fishing to Hold Detail Key." },
                { L.CHANGELOG_SETTINGS, "Combat Alert, Currency Bar, and Flight Timer are sized "
                    .. "and reset only in Edit Mode now." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.FISHINGCAST_TITLE, "Double right-click now casts Fishing." },
                { L.TOOLTIPS_TITLE, "Levels and class names are colored again, player titles "
                    .. "show, and the Target line shows the target's name instead of its level." },
                { L.FLIGHTTIMER_TITLE, "No longer draws over other windows." },
            } },
        },
    },
    {
        version = "0.5.0",
        date = "2026-10-01",
        sections = {
            { L.CHANGELOG_ADDED, {
                { "Chat Fading", "New, off by default, in Chat: keeps chat text on screen "
                    .. "instead of fading it out after a while." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.HIDEBETAFEEDBACK_TITLE, "Also hides the beta's feedback buttons on quest windows "
                    .. "(quest, gossip, and quest log), with its own checkbox." },
                { L.QUESTNAMEPLATES_TITLE, "The icon matches the objective: Blizzard's attack, pickup, "
                    .. "or interact icon for kill, item, or object objectives, and the quest icon "
                    .. "for the rest. A creature whose objective is done shows a green check "
                    .. "and its final count (8/8), unless you turn off Show Completed; the count can be "
                    .. "turned off to leave just the check." },
                { L.PLAYERNAMEPLATES_TITLE .. " and " .. L.NPCNAMEPLATES_TITLE, "On name-only plates the "
                    .. "buffs sit centered above the name instead of far off to the left. A Buffs "
                    .. "setting puts them above, before, or after the name, or back in Blizzard's "
                    .. "spot." },
                { L.PROFTOOLTIPS_TITLE, "The game's own bare \"Mining\" line under a vein is "
                    .. "replaced by \"Requires Mining (1)\" in the difficulty color instead of showing "
                    .. "both. When Blizzard already says \"Requires Mining (1)\", a bare name line "
                    .. "below it shows your skill (\"Your Mining skill: 150\")." },
                { L.CHATHISTORY_TITLE, "The \"Earlier chat\" line between old and new chat is "
                    .. "now an option, off by default." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.HIDEBETAFEEDBACK_TITLE, "The feedback box on quest windows no longer fades "
                    .. "back in." },
                { "Forever++", "An error in one module no longer stops the others from loading, "
                    .. "turning on, or turning off." },
            } },
        },
    },
    {
        version = "0.4.0",
        date = "2026-09-30",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.CHANGELOG_SETTINGS, "Defaults and Clutch's Default buttons on the welcome "
                    .. "page, each asking first. Defaults resets every module's settings; "
                    .. "Clutch's Default also turns on Fishing Cast, Skip Cinematics, Auto "
                    .. "Screenshot, Currency Bar, Hide Beta Feedback, and Short Channel Names." },
                { "Edit Mode", "Combat Alert, Currency Bar, and Flight Timer work like "
                    .. "Blizzard's own frames: click one to select it, then drag it (it snaps to "
                    .. "the screen and other frames), nudge it with the arrow keys, or use its "
                    .. "Scale slider and Reset To Default Position, also on right-click." },
                { L.CATEGORY_CHAT, "New category. Chat Copy adds a button beside the chat "
                    .. "window that opens the chat as plain text to copy. Short Channel Names "
                    .. "shows [1] instead of [1. General] (off by default). Chat History shows "
                    .. "each window's latest lines again after a logout or reload. Social Button "
                    .. "moves the Quick Join button beside the chat's other buttons. Chat Font "
                    .. "draws chat, and by default the chat input box, in Friz Quadrata or "
                    .. "another Blizzard font (not on Korean, Chinese, or Russian clients)." },
                { L.CURRENCYBAR_TITLE, "New, off by default, in Interface. A small box showing "
                    .. "your gold and, if you choose, the currencies you show on your Backpack. "
                    .. "Hover it for what this session gained or spent. Move it in Edit Mode." },
                { L.AUTODECLINE_TITLE, "Also turns down party invites, without the invite sound "
                    .. "(off by default). Duels and party invites each have their own checkbox." },
                { L.FISHINGCAST_TITLE, "New, off by default, in Automation. Double right-click "
                    .. "with a fishing pole equipped to cast Fishing." },
                { L.ADDONSLIST_TITLE, "New, in Interface. The AddOns list without category "
                    .. "headers, enabled addons first." },
                { L.SPELLRANKS_TITLE, "New, in Interface. Marks action bar spells that have a "
                    .. "higher rank you already know, and adds the best rank to the tooltip. "
                    .. "/fpp ranks lists them." },
                { L.RECIPECOLORS_TITLE, "New. Colors recipes in the professions window by your "
                    .. "chance of a skill-up, like the old trade skill window." },
                { L.QUESTNAMEPLATES_TITLE, "New. A quest icon and your progress beside the health "
                    .. "bar of creatures you need for a quest." },
                { L.ALREADYKNOWN_TITLE, "New. A green check on recipes, mounts, pets, toys, and "
                    .. "other items you already know, on merchants, the auction house, bags, "
                    .. "mail, and loot." },
                { L.COMBATALERT_TITLE, "New, off by default, in Interface. Floats \"Entering "
                    .. "Combat\" or \"Leaving Combat\" up from the middle of the screen." },
                { L.AUTOSELLJUNK_TITLE, "New, off by default. Sells your gray items when a "
                    .. "merchant opens. Hold Shift to skip it." },
                { L.FLIGHTTIMER_TITLE, "New. Times each flight you take, then counts the next "
                    .. "one down in a bar and shows the flight time on the flight map." },
                { L.PROFTOOLTIPS_TITLE, "Was Gathering Tooltips. Also shows the Lockpicking "
                    .. "skill a lockbox or locked chest needs, and lets blacksmiths see which "
                    .. "skeleton key opens it." },
                { L.ZONEINFO_TITLE, "A Detail Key shows fishing, dungeons, herbs, ore, and "
                    .. "skinning only while you hold it, and the panel can sit in a top corner "
                    .. "of the map." },
                { L.PLAYERNAMEPLATES_TITLE, "An Icon Position option puts the role, friend, and "
                    .. "recent ally icons before or after the name." },
                { L.TOOLTIPS_TITLE, "A Faction Color option colors the Horde or Alliance line on "
                    .. "a unit red or blue." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.PROFTOOLTIPS_TITLE, "Recolors Blizzard's \"Requires Mining (1)\" line "
                    .. "against your skill instead of adding a second one." },
                { L.ZONEINFO_TITLE .. " and " .. L.POI_TITLE, "Map tooltips look the same: white "
                    .. "title, gold kind of place, Horde red and Alliance blue, and each dungeon "
                    .. "or raid on one row with its icon." },
                { L.PLAYERNAMEPLATES_TITLE, "Recent allies get an icon instead of a light blue name. "
                    .. "Recent Allies is a dropdown: Off, Colored Name, or Icon." },
                { L.PLAYERNAMEPLATES_TITLE .. " and " .. L.NPCNAMEPLATES_TITLE, "Name Size is 80% by "
                    .. "default." },
                { L.SKIPCINEMATICS_TITLE, "Forget asks you to confirm first." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.POI_TITLE, "No second icon beside ours for Undercity or for dungeon and "
                    .. "raid entrances. Learned flight points show as learned again, including "
                    .. "with translated names; visit a flight master once to pick yours up." },
                { L.PLAYERNAMEPLATES_TITLE, "No more \"action blocked\" error at login." },
                { L.AUCTIONPRICES_TITLE, "Posting works while a scan runs." },
                { L.PLAYERNAMEPLATES_TITLE .. " and " .. L.NPCNAMEPLATES_TITLE, "The guild or title no "
                    .. "longer overlaps the cast bar." },
                { L.PROFTOOLTIPS_TITLE, "The skill line sits under the name, above quest lines, "
                    .. "also on minimap pins." },
            } },
        },
    },
    {
        version = "0.3.0",
        date = "2026-09-28",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.POI_TITLE, "Dungeons, raids, capitals, flight masters, boats, zeppelins, "
                    .. "and spirit healers on the world map, in a new Map category. Learned "
                    .. "flight masters show in the minimap's white." },
                { L.ZONEINFO_TITLE, "A panel on the world map with the zone's level range, who "
                    .. "holds it, its dungeons, fishing skill, and its herbs, ore, and skinning." },
                { L.UNEXPLORED_TITLE, "Shows the parts of zone maps you haven't explored yet, "
                    .. "with a tint." },
                { L.COORDS_TITLE, "Your coordinates and the cursor's in the world map's title "
                    .. "bar." },
                { L.HIDEFILTERRESET_TITLE, "Hides the reset button on the world map's filter "
                    .. "dropdown." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.CLASSCOLORS_TITLE, "Hostile NPCs' health bars are red, neutral ones yellow, "
                    .. "and tagged ones gray." },
                { L.BAGSLOTCOUNTER_TITLE, "Adds up every bag on the backpack button by default." },
                { L.AUTOSTOW_TITLE, "The delay is a slider." },
                { L.AUTORELEASE_TITLE, "The delay is a slider." },
                { L.GATHERINGTRACKING_TITLE, "Swap is a slider." },
                { L.AUCTIONPRICES_TITLE, "Red After is a slider." },
                { L.PLAYERNAMEPLATES_TITLE, "A Name Size slider." },
                { L.NPCNAMEPLATES_TITLE, "A Name Size slider." },
            } },
            { L.CHANGELOG_FIXED, {
                { L.PLAYERNAMEPLATES_TITLE, "Chinese, Korean, and Cyrillic names show again." },
                { L.NPCNAMEPLATES_TITLE, "Same fix for NPC names and titles." },
            } },
        },
    },
    {
        version = "0.2.0",
        date = "2026-09-27",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.AUTODECLINE_TITLE, "Turns down duel requests and closes the popup. Includes "
                    .. "letting friends and guildmates through, and saying in chat who was "
                    .. "declined. Off by default." },
                { L.AUTODISMOUNT_TITLE, "Gets you off your mount or stands you up when a spell, "
                    .. "flight, loot, or attack fails because you're mounted or sitting. Includes "
                    .. "separate Dismount and Stand Up options, and leaving shapeshift forms (off "
                    .. "by default)." },
                { L.AUTORELEASE_TITLE, "Releases your spirit when you die in a battleground. "
                    .. "Includes a delay, and staying put when a soulstone, reincarnation, or "
                    .. "someone else can resurrect you. Off by default." },
                { L.AUTOSCREENSHOT_TITLE, "Takes a screenshot a moment after you level up, earn an "
                    .. "achievement, or defeat a boss, so Blizzard's toast is in it. Includes "
                    .. "checkboxes for loot of a chosen quality, reputation standings, PvP ranks, "
                    .. "new titles, battleground ends, and deaths, hiding the interface for the "
                    .. "shot, and a chat line saying why. Off by default." },
                { L.BAGSLOTCOUNTER_TITLE, "How many bag slots are free, on the bag buttons. Includes "
                    .. "each bag's own count or the total on the backpack, the reagent bag on its "
                    .. "own button, added to the backpack, or hidden, counting special bags such "
                    .. "as quivers and herb bags, and the text's size and position." },
                { L.CLASSCOLORS_TITLE, "Players' health bars and names in their class color on "
                    .. "the player, target, focus, party, and target-of-target frames. Includes "
                    .. "health bars and names (off by default) separately, and a checkbox for each "
                    .. "frame." },
                { L.PROFTOOLTIPS_TITLE,"The skill a herb, ore, or skinnable beast needs, in "
                    .. "its tooltip in the world or on the minimap, colored red, orange, yellow, "
                    .. "green, or gray against your skill like trainer recipes. Herb, ore, and "
                    .. "stone items say the skill that gathers them. Includes showing it only for "
                    .. "professions you have or always, and a checkbox each for herbs, ore, "
                    .. "creatures, and items." },
                { L.SKIPCINEMATICS_TITLE, "Skips the game's cinematics and movies. Off by "
                    .. "default. Includes skipping only ones already seen on any character or "
                    .. "every one, holding Shift to watch, and a Forget button for the seen list." },
            } },
            { L.CHANGELOG_CHANGED, {
                { L.PLAYERNAMEPLATES_TITLE, "Recent allies' names in the game's light blue, instead "
                    .. "of the Name Color. Includes a checkbox to turn it off." },
                { L.CHANGELOG_SETTINGS, "Fewer entries in the sidebar. Forever++ opens on a "
                    .. "welcome page, and every module is on one Modules page, where the gear "
                    .. "beside a module shows its options under it. About is part of the welcome "
                    .. "page." },
            } },
        },
    },
    {
        version = "0.1.0",
        date = "2026-09-27",
        sections = {
            { L.CHANGELOG_ADDED, {
                { L.AUCTIONPRICES_TITLE, "Scans the auction house when you open it and shows the "
                    .. "lowest buyout in item tooltips. Includes how long ago the item was scanned "
                    .. "(colored by age), the same price options as Sell Price, /fpp scan, and a "
                    .. "Reset button and /fpp resetprices to forget saved prices." },
                { L.AUTOGOSSIP_TITLE, "Picks an NPC's only option when it has nothing else to say "
                    .. "and no quests. Includes a choice for bankers, vendors, trainers, flight "
                    .. "masters, stable masters, and other NPCs, and holding Shift to choose "
                    .. "yourself." },
                { L.AUTOREPAIR_TITLE, "Repairs your gear at merchants and says in chat what it "
                    .. "cost. Includes paying from the guild bank first, the guild bank only, or "
                    .. "your own money, a minimum cost, and holding Shift to skip it." },
                { L.AUTOSTOW_TITLE, "Puts your weapons away after combat. Includes the delay and "
                    .. "leaving them out in dungeons, raids, and battlegrounds." },
                { L.CONSOLEVARIABLES_TITLE, "A Settings page to browse, search, and change the game's "
                    .. "console variables (CVars). Includes a Changed Only filter and "
                    .. "/fpp cvar [search]." },
                { "Durability Bars", "A bar beside each item on the character window with how "
                    .. "worn it is. Includes showing bars always, only when worn, below 50%, or "
                    .. "below 25%." },
                { L.FASTLOOT_TITLE, "With auto loot on, takes everything at once. Includes a warning "
                    .. "in Settings, with a Turn On button, when Blizzard's auto loot is off." },
                { L.GATHERINGTRACKING_TITLE, "Keeps Find Minerals or Find Herbs on. Includes minerals, "
                    .. "herbs, or both, turning tracking back on after logging in, zoning, or dying, "
                    .. "and swapping between the two every few seconds." },
                { L.HIDEBETAFEEDBACK_TITLE, "Hides the beta's \"Press F6 to submit an issue\" tooltip "
                    .. "line and the bug report button, each on its own. Off by default, and only on "
                    .. "beta and PTR clients." },
                { L.NPCNAMEPLATES_TITLE, "Friendly NPCs' names with their title, and a health bar only "
                    .. "when they're hurt or in combat. Includes name color, where the level goes, "
                    .. "and when and in what color titles show." },
                { L.PLAYERNAMEPLATES_TITLE, "Friendly players' names with their guild, and a health bar "
                    .. "only when they're hurt or in combat. Includes class-colored names, where the "
                    .. "level goes, guild line and color, highlighting guildmates, and role icons "
                    .. "for group members and Battle.net icons for friends." },
                { L.SELLPRICE_TITLE, "The vendor price in item tooltips. Includes the whole stack "
                    .. "or one item (Shift shows the other), lining up with other price lines, and "
                    .. "the quantity color." },
                { L.TOOLTIPS_TITLE, "Colors unit and item tooltips. Includes borders by class, "
                    .. "reaction, or item quality, name, guild, level, and class name colors, player "
                    .. "titles, a Target line, anchoring to the cursor, and hiding unit tooltips in "
                    .. "combat." },
                { L.CHANGELOG_SETTINGS, "Forever++ in Game Menu > Options > AddOns. Includes a "
                    .. "checkbox per module grouped by category, a page per module with options, "
                    .. "Debug, Changelog, and About. Every module turns on and off without a "
                    .. "reload." },
                { L.CHANGELOG_COMMANDS, "/fpp or /forever++ opens the settings. Includes list, "
                    .. "toggle, options, set, and reset." },
            } },
        },
    },
}
