-- English text for the automation modules. Locales/enUS/Core.lua says how locale files work.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- FastLoot
L.FASTLOOT_TITLE = "Fast Loot"
L.FASTLOOT_DESC = "With auto loot on, take everything at once instead of waiting for the loot "
    .. "window."
L.FASTLOOT_BLIZZARD_OFF = "Blizzard's auto loot is off" -- a gray row under the checkbox, with a button
L.FASTLOOT_BLIZZARD_OFF_DESC = "Blizzard's auto loot is off, so only loot you take while holding "
    .. "the auto loot key (Shift) is fast."

-- AutoRepair
L.AUTOREPAIR_TITLE = "Auto Repair"
L.AUTOREPAIR_DESC = "Repair all your gear when you talk to a merchant who repairs, and say in chat "
    .. "what it cost. Hold the Skip Key (Shift) to skip it."
L.AUTOREPAIR_FUNDS = "Pay With"
L.AUTOREPAIR_FUNDS_DESC = "Whose money pays for repairs."
L.AUTOREPAIR_FUNDS_GUILD_FIRST = "Guild Bank, Then Your Own"
L.AUTOREPAIR_FUNDS_GUILD = "Guild Bank Only"
L.AUTOREPAIR_FUNDS_OWN = "Your Own Money Only"
L.AUTOREPAIR_MIN_COST = "Minimum Cost"
L.AUTOREPAIR_MIN_COST_DESC = "Only repair when it costs at least this much, so a quick stop at a "
    .. "merchant doesn't spend a few copper each time."
L.AUTOREPAIR_MIN_COST_ANY = "Any Cost"
L.AUTOREPAIR_KEY_DESC = "Hold this key as you talk to the merchant to leave your gear unrepaired."
L.AUTOREPAIR_CHAT_DESC = "Say in chat what repairs cost, or why they couldn't be paid for."
L.AUTOREPAIR_REPAIRED = "Repaired for %s." -- cost
L.AUTOREPAIR_REPAIRED_GUILD = "Repaired for %s from the guild bank." -- cost
L.AUTOREPAIR_NO_MONEY = "Not enough money to repair (%s)." -- cost
L.AUTOREPAIR_NO_GUILD_MONEY = "The guild bank can't pay for repairs (%s)." -- cost

-- AutoSellJunk
L.AUTOOPEN_TITLE = "Auto Open"
L.AUTOOPEN_DESC = "Open the containers in your bags, such as clams, sacks, and lockboxes once "
    .. "they're unlocked, by themselves. It waits out combat, stealth, casting, and any loot, "
    .. "merchant, mail, bank, trade, or auction window."
L.AUTOOPEN_FREE_SLOTS = "Keep Bag Slots Free"
L.AUTOOPEN_FREE_SLOTS_DESC = "Open nothing while fewer bag slots than this are free, so what's "
    .. "inside has somewhere to go."
L.AUTOOPEN_SPECIAL = "Open Special Containers"
L.AUTOOPEN_SPECIAL_DESC = "Also open the few containers usually left for you to decide on: raid "
    .. "and world boss sacks of gems, holiday gifts, and trunks and crates that hold a quest item, "
    .. "a recipe, or a piece of gear."
L.AUTOOPEN_CHAT_DESC = "Say in chat what was opened."
L.AUTOOPEN_OPENED = "Opened %s." -- one or more item links, each maybe with a count
L.AUTOOPEN_COUNT = "%s x%d" -- item link, how many
L.AUTOSELLJUNK_TITLE = "Auto Sell Junk"
L.AUTOSELLJUNK_DESC = "Sell the gray items in your bags when you talk to a merchant, and say in "
    .. "chat what they sold for. Hold the Skip Key (Shift) to skip it."
L.AUTOSELLJUNK_BUYBACK = "Keep Everything Buyable Back"
L.AUTOSELLJUNK_BUYBACK_DESC = "Sell only as much junk as the merchant's buyback list has room for "
    .. "beside what you sold yourself, so you can still buy back anything sold by mistake."
L.AUTOSELLJUNK_KEY_DESC = "Hold this key as you talk to the merchant to leave your junk unsold."
L.AUTOSELLJUNK_CHAT_DESC = "Say in chat how many items were sold and what they sold for, and how "
    .. "many were left unsold because the buyback list was full."
L.AUTOSELLJUNK_SOLD = "Sold %d junk items for %s." -- count, money
-- count, money, how many were left
L.AUTOSELLJUNK_SOLD_FULL = "Sold %d junk items for %s. Buyback is full: %d left unsold."
L.AUTOSELLJUNK_FULL = "Buyback is full: %d junk items left unsold." -- count

-- GatheringTracking
L.GATHERINGTRACKING_TITLE = "Gathering Tracking"
L.GATHERINGTRACKING_DESC = "Keep Find Minerals or Find Herbs on: turn it back on after logging in, "
    .. "zoning, or dying, and swap between the two if you like."
L.GATHERINGTRACKING_TRACK = "Track"
L.GATHERINGTRACKING_TRACK_DESC = "Which tracking to keep on. The game tracks one at a time, so both "
    .. "take turns."
L.GATHERINGTRACKING_TRACK_BOTH = "Minerals and Herbs"
L.GATHERINGTRACKING_TRACK_MINERALS = "Minerals Only"
L.GATHERINGTRACKING_TRACK_HERBS = "Herbs Only"
L.GATHERINGTRACKING_REAPPLY = "Turn Back On"
L.GATHERINGTRACKING_REAPPLY_DESC = "After logging in, zoning, or coming back to life, turn tracking "
    .. "back on if nothing is being tracked. Turning it off yourself lasts until then."
L.GATHERINGTRACKING_SWAP = "Swap Between Both"
L.GATHERINGTRACKING_SWAP_DESC = "Swap between Find Minerals and Find Herbs while one of them is on. "
    .. "Waits during combat, casting, and flights."
L.GATHERINGTRACKING_SWAP_EVERY_NAME = "Swap Every"
L.GATHERINGTRACKING_SWAP_EVERY_DESC = "How long to wait between swaps."
L.GATHERINGTRACKING_CHAT_DESC = "Say in chat when the game stops Gathering Tracking from changing "
    .. "tracking."
L.GATHERINGTRACKING_FAILED = "Gathering Tracking couldn't change tracking: %s" -- error
L.GATHERINGTRACKING_BLOCKED = "The game blocked Gathering Tracking from changing tracking. It stops "
    .. "until /reload."

-- AutoStow
L.AUTOSTOW_TITLE = "Auto Stow"
L.AUTOSTOW_DESC = "Put your weapons away once they've been out for a few seconds out of "
    .. "combat, whether a fight left them out or you drew them yourself."
L.AUTOSTOW_DELAY = "Delay"
L.AUTOSTOW_DELAY_DESC = "How long your weapons stay out, after combat or after you draw them, "
    .. "before they're put away."
L.AUTOSTOW_OUTSIDE_ONLY = "Only Out of Instances"
L.AUTOSTOW_OUTSIDE_ONLY_DESC = "Leave your weapons out in dungeons, raids and battlegrounds, where "
    .. "the next pull is never far off."
L.AUTOSTOW_LOG = "Log Sheath State"
L.AUTOSTOW_LOG_DESC = "Print in chat, with timestamps, every change of the sheath state (1 away, "
    .. "2 melee, 3 ranged) out of combat, and every toggle Auto Stow or you make."
L.AUTOSTOW_LOG_LINE = "Auto Stow %.2f: %s" -- GetTime(), what happened
L.AUTOSTOW_LOG_STATE = "state %s" -- sheath state
L.AUTOSTOW_LOG_COMBAT_END = "combat ended, state %s"
L.AUTOSTOW_LOG_COMBAT_START = "combat started, not watching"
L.AUTOSTOW_LOG_TOGGLE = "toggling, state before %s"
L.AUTOSTOW_LOG_TOGGLED = "toggle took, state %s"
L.AUTOSTOW_LOG_AGAIN = "toggle changed nothing, state %s, trying once more"
L.AUTOSTOW_LOG_NO_CHANGE ="toggle changed nothing, leaving state %s until it changes"
L.AUTOSTOW_LOG_GAVE_UP = "still not away after %d toggles, leaving state %s until it changes"
L.AUTOSTOW_LOG_PLAYER = "you pressed Sheath, state %s, delay starts again"

-- AutoDismount
L.AUTODISMOUNT_TITLE = "Auto Dismount"
L.AUTODISMOUNT_DESC = "Get off your mount or stand up when something fails because you're "
    .. "mounted or sitting, like casting a spell, taking a flight, or looting."
L.AUTODISMOUNT_DISMOUNT = "Dismount"
L.AUTODISMOUNT_DISMOUNT_DESC = "Get off your mount when you cast a spell, talk to a flight master, "
    .. "or attack while mounted."
L.AUTODISMOUNT_STAND = "Stand Up"
L.AUTODISMOUNT_STAND_DESC = "Stand up when you cast a spell, loot, or attack while sitting."
L.AUTODISMOUNT_UNSHIFT = "Leave Shapeshift Form"
L.AUTODISMOUNT_UNSHIFT_DESC = "Leave a shapeshift form, like a druid's Bear or Cat Form, when you "
    .. "cast a spell that can't be cast in it."

-- AutoGossip
L.AUTOGOSSIP_TITLE = "Auto Gossip"
L.AUTOGOSSIP_DESC = "When an NPC has only one thing to say, or one service beside small talk, "
    .. "and no quests, pick it for you, so the bank, shop, trainer, or flight map opens straight "
    .. "away."
L.AUTOGOSSIP_SECTION_GENERAL = "General"
L.AUTOGOSSIP_SECTION_NPCS = "Pick For"
L.AUTOGOSSIP_BANKER = "Bankers"
L.AUTOGOSSIP_BANKER_DESC = "Open the bank."
L.AUTOGOSSIP_VENDOR = "Vendors and Repairs"
L.AUTOGOSSIP_VENDOR_DESC = "Open the shop."
L.AUTOGOSSIP_TRAINER = "Trainers"
L.AUTOGOSSIP_TRAINER_DESC = "Open the trainer's list."
L.AUTOGOSSIP_TAXI = "Flight Masters"
L.AUTOGOSSIP_TAXI_DESC = "Open the flight map."
L.AUTOGOSSIP_STABLE = "Stable Masters"
L.AUTOGOSSIP_STABLE_DESC = "Open the stable."
L.AUTOGOSSIP_OTHER = "Other NPCs"
L.AUTOGOSSIP_OTHER_DESC = "Pick the only option of any other NPC, unless the game asks you to "
    .. "read its text first."
L.AUTOGOSSIP_KEY_DESC = "Hold this key as you talk to an NPC to pick its options yourself."
L.AUTOGOSSIP_PRINT = "Print Gossip Options"
L.AUTOGOSSIP_PRINT_DESC = "Print every gossip option in chat with its icon and status, to check "
    .. "which kind of NPC it counts as."
L.AUTOGOSSIP_PRINT_HEADER = "Gossip options (title: %s):" -- NPC's title under the name
L.AUTOGOSSIP_PRINT_LINE = "  %s  icon=%s status=%s flags=%s  %s" -- id, icon, status, flags, name
L.AUTOGOSSIP_PRINT_RESULT = "  -> %s" -- the kind picked, or why not (debug codes)
L.AUTOGOSSIP_PRINT_LEARNED = "Gossip icon %s learned as %s." -- icon file ID, kind (false: ambiguous)
-- The title under a stable master's name, exactly as the game shows it.
L.AUTOGOSSIP_TITLE_STABLE = "Stable Master"

-- AutoDecline
L.AUTODECLINE_TITLE = "Auto Decline"
L.AUTODECLINE_DESC = "Turn down duel requests, and optionally party invites, guild invites, and "
    .. "guild charters, as they arrive, so the popup never gets in your way."
L.AUTODECLINE_DUELS = "Duels"
L.AUTODECLINE_DUELS_DESC = "Turn down duel requests."
L.AUTODECLINE_PARTY_INVITES = "Party Invites"
L.AUTODECLINE_PARTY_INVITES_DESC = "Also turn down party invites."
L.AUTODECLINE_GUILD_INVITES = "Guild Invites"
L.AUTODECLINE_GUILD_INVITES_DESC = "Also turn down guild invites, even from friends."
L.AUTODECLINE_GUILD_CHARTERS = "Guild Charters"
L.AUTODECLINE_GUILD_CHARTERS_DESC = "Also turn down requests to sign a guild charter, even from "
    .. "friends. Your own charter still opens."
L.AUTODECLINE_ALLOW_FRIENDS = "Allow Friends and Guild"
L.AUTODECLINE_ALLOW_FRIENDS_DESC = "Let duels and party invites from your friends, Battle.net "
    .. "friends, and guildmates through."
L.AUTODECLINE_CHAT_DESC = "Say in chat whose duel, invite, or charter was turned down."
L.AUTODECLINE_DECLINED = "Declined a duel from %s." -- player name
L.AUTODECLINE_DECLINED_INVITE = "Declined a party invite from %s." -- player name
L.AUTODECLINE_DECLINED_GUILD_INVITE = "Declined a guild invite from %s." -- player name
L.AUTODECLINE_DECLINED_CHARTER = "Declined a guild charter from %s." -- player name
L.AUTODECLINE_SOMEONE = "someone"

-- AutoRelease
L.AUTORELEASE_TITLE = "Auto Release"
L.AUTORELEASE_DESC = "Release your spirit when you die in a battleground, unless you can "
    .. "resurrect yourself or someone is resurrecting you."
L.AUTORELEASE_DELAY = "Delay"
L.AUTORELEASE_DELAY_DESC = "How long after dying to wait before releasing."
L.AUTORELEASE_NOW = "Right Away"
L.AUTORELEASE_KEY_DESC = "Hold this key while you're dead to stay where you fell."
L.AUTORELEASE_CHAT_DESC = "Say in chat when your spirit was released, or why it wasn't."
L.AUTORELEASE_RELEASED = "Released your spirit."
L.AUTORELEASE_SELF_RES = "Didn't release: you can resurrect yourself."
L.AUTORELEASE_RES_OFFER = "Didn't release: someone is resurrecting you."

-- SkipCinematics
L.SKIPCINEMATICS_TITLE = "Skip Cinematics"
L.SKIPCINEMATICS_DESC = "Skip the game's cinematics and movies, every one or only ones you've "
    .. "already seen."
L.SKIPCINEMATICS_SKIP = "Skip"
L.SKIPCINEMATICS_SKIP_DESC = "Which cinematics and movies to skip. Seen ones count across all your "
    .. "characters."
L.SKIPCINEMATICS_SKIP_SEEN = "Only Seen"
L.SKIPCINEMATICS_SKIP_ALL = "All"
L.SKIPCINEMATICS_KEY = "Watch Key"
L.SKIPCINEMATICS_KEY_DESC = "Hold this key as a cinematic or movie starts to let it play."
L.SKIPCINEMATICS_CHAT_DESC = "Say in chat when a cinematic or movie is skipped."
L.SKIPCINEMATICS_SKIPPED_CINEMATIC = "Skipped a cinematic."
L.SKIPCINEMATICS_SKIPPED_MOVIE = "Skipped a movie."
L.SKIPCINEMATICS_RESET = "Seen Cinematics"
L.SKIPCINEMATICS_RESET_BUTTON = "Clear"
L.SKIPCINEMATICS_RESET_DESC = "Forget which cinematics and movies you've seen, so each plays once "
    .. "more."
L.SKIPCINEMATICS_RESET_CONFIRM = "Forget which cinematics and movies you've seen?"
L.SKIPCINEMATICS_RESET_DONE = "Seen cinematics cleared."
L.SKIPCINEMATICS_PRINT = "Print Cinematic Keys"
L.SKIPCINEMATICS_PRINT_DESC = "Print each cinematic's or movie's key in chat as it starts, with "
    .. "whether it was seen and skipped."
L.SKIPCINEMATICS_PRINT_LINE = "Cinematic %s: seen=%s skip=%s" -- key (movie ID or map:subzone), seen, skip


-- FishingCast
L.FISHINGCAST_TITLE = "Fishing Cast"
L.FISHINGCAST_DESC = "Double right-click in the world with a fishing pole equipped to cast Fishing."
L.FISHINGCAST_SPEED = "Double-Click Speed"
L.FISHINGCAST_SPEED_DESC = "How quickly the second right-click must follow the first."
L.FISHINGCAST_MS = "%d ms" -- milliseconds
L.FISHINGCAST_COMBAT = "Combat Warning"
L.FISHINGCAST_COMBAT_DESC = "Warn once when combat starts while a fishing pole is equipped."
L.FISHINGCAST_COMBAT_TEXT = "You have a fishing pole equipped."
L.FISHINGCAST_LOUDER = "Louder Bobber"
L.FISHINGCAST_LOUDER_DESC = "While you fish, turn sound effects up and music down so the splash is easy to hear. Your own volumes come back after you stop."


-- AutoWeaponBuff
L.AUTOWEAPONBUFF_TITLE = "Auto Weapon Buff"
L.AUTOWEAPONBUFF_DESC = "Right-click a sharpening stone, weightstone, oil, poison, or lure in your bags, or use one from an "
    .. "action bar, to put it straight on your weapon: the main hand, or the off hand when only "
    .. "it fits."
L.AUTOWEAPONBUFF_NOTICE = "Works only out of combat." -- a gray row atop the module
L.AUTOWEAPONBUFF_NOTICE_DESC = "The game doesn't let addons change what a bag or action bar click "
    .. "does in combat, so until combat ends they work as Blizzard's do."
L.AUTOWEAPONBUFF_WARN = "Warn When No Weapon Fits"
L.AUTOWEAPONBUFF_WARN_DESC = "When no equipped weapon can take the item, like a weightstone with "
    .. "only blades, say so in red at the top of the screen instead of bringing up a cursor."
L.AUTOWEAPONBUFF_WARN_TEXT = "No equipped weapon can take %s." -- item name
L.AUTOWEAPONBUFF_WARN_TEXT_ANY = "No equipped weapon can take that."
L.AUTOWEAPONBUFF_PRINT = "Print Weapon Checks"
L.AUTOWEAPONBUFF_PRINT_DESC = "Print in chat, each time you use a weapon buff from your bags or a bar, "
    .. "which kind of item it is and which weapon slot was picked, and each time it learns a weapon "
    .. "an item goes on."
-- debug codes: item link, item kind (sharp, blunt, melee, pole, learned), slot picked (16, 17, or nil)
L.AUTOWEAPONBUFF_PRINT_LINE = "Weapon buff: %s kind=%s -> slot %s" -- item link or name, kind, slot
L.AUTOWEAPONBUFF_LEARNED_LINE = "Weapon buff learned: %s goes on %s." -- item name, weapon type

-- ComprehendScrolls
L.COMPREHENDSCROLLS_TITLE = "Comprehend Scrolls"
L.COMPREHENDSCROLLS_DESC = "Right-click a Mage's scroll in your bags to cast Comprehend Scroll on "
    .. "it, without opening the spellbook first."
L.COMPREHENDSCROLLS_NOTICE = "Works only out of combat." -- a gray row atop the module
L.COMPREHENDSCROLLS_NOTICE_DESC = "The game doesn't let addons change what a bag click does in "
    .. "combat, so until combat ends a right-click works as Blizzard's does."

-- AutoScreenshot
L.AUTOSCREENSHOT_TITLE = "Auto Screenshot"
L.AUTOSCREENSHOT_DESC = "Take a screenshot when you level up, earn an achievement, or defeat a "
    .. "boss, and at other moments worth keeping."
L.AUTOSCREENSHOT_SECTION_GENERAL = "General"
L.AUTOSCREENSHOT_SECTION_EVENTS = "Take a Screenshot When"
L.AUTOSCREENSHOT_HIDE_UI = "Hide Interface"
L.AUTOSCREENSHOT_HIDE_UI_DESC = "Hide the interface for the screenshot, the way Alt-Z does. Not in "
    .. "combat, where the game doesn't allow it."
L.AUTOSCREENSHOT_HIDE_OWN = "Your Own Screenshots"
L.AUTOSCREENSHOT_HIDE_OWN_DESC = "Also hide the interface for the screenshots you take with the "
    .. "Screenshot key (Print Screen), even with every moment below off. Not in combat."
L.AUTOSCREENSHOT_CHAT_DESC = "Say in chat why a screenshot was taken."
L.AUTOSCREENSHOT_PLAYED_TIME = "Played Time on Level Up"
L.AUTOSCREENSHOT_PLAYED_TIME_DESC = "Show your /played time in chat when you level up, so it's in "
    .. "the screenshot."
L.AUTOSCREENSHOT_TAKEN = "Screenshot taken: %s." -- the checkbox's name, such as Level Up
L.AUTOSCREENSHOT_LEVEL_UP = "Level Up"
L.AUTOSCREENSHOT_LEVEL_UP_DESC = "When you reach a new level."
L.AUTOSCREENSHOT_ACHIEVEMENT = "Achievement"
L.AUTOSCREENSHOT_ACHIEVEMENT_DESC = "When you earn an achievement you didn't already have on another "
    .. "character."
L.AUTOSCREENSHOT_LOOT = "Loot"
L.AUTOSCREENSHOT_LOOT_DESC = "When you receive an item of the quality below or better."
L.AUTOSCREENSHOT_LOOT_QUALITY = "Loot Quality"
L.AUTOSCREENSHOT_LOOT_QUALITY_DESC = "The lowest item quality that takes a screenshot."
L.AUTOSCREENSHOT_QUALITY_RARE = "Rare"
L.AUTOSCREENSHOT_QUALITY_EPIC = "Epic"
L.AUTOSCREENSHOT_QUALITY_LEGENDARY = "Legendary"
L.AUTOSCREENSHOT_BOSS_KILL = "Boss Kill"
L.AUTOSCREENSHOT_BOSS_KILL_DESC = "When your group defeats a dungeon or raid boss."
L.AUTOSCREENSHOT_REPUTATION = "Reputation"
L.AUTOSCREENSHOT_REPUTATION_DESC = "When you reach Friendly, Honored, Revered, or Exalted with a "
    .. "faction."
L.AUTOSCREENSHOT_PVP_RANK = "PvP Rank"
L.AUTOSCREENSHOT_PVP_RANK_DESC = "When you reach a new PvP rank."
L.AUTOSCREENSHOT_NEW_TITLE = "New Title"
L.AUTOSCREENSHOT_NEW_TITLE_DESC = "When you earn a new title."
L.AUTOSCREENSHOT_BATTLEGROUND = "Battleground Ends"
L.AUTOSCREENSHOT_BATTLEGROUND_DESC = "When a battleground ends, with the scoreboard up."
L.AUTOSCREENSHOT_DEATH = "Death"
L.AUTOSCREENSHOT_DEATH_DESC = "When you die."
