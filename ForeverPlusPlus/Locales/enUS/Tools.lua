-- English text for the tool pages. Locales/enUS/Core.lua says how locale files work.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- ConsoleVariables
L.CONSOLEVARIABLES_TITLE = "Console Variables"
L.DEBUG_DESC = "Show every module's debug options and the testing tools (Self Test, Gear Probe, "
    .. "Screenshots) on a Debug page in the Settings sidebar, and turn on their commands."
L.DEBUG_NOTICE = "Turning Debug off puts every debug option back to its default." -- a gray row atop the module
L.DEBUG_NOTICE_DESC = "So nothing set here goes on working out of sight."
L.CONSOLEVARIABLES_DESC ="Browse the game's console variables (CVars) on a page in Settings, "
    .. "change them, and lock the ones you want kept, even those the game puts back at every login."
L.CONSOLEVARIABLES_CHAT_DESC = "Say in chat when a locked console variable can't be kept at its value."
-- A gray row atop the module while it's off with console variables locked
L.CONSOLEVARIABLES_LOCKS_OFF = "Locked console variables aren't kept while this is off."
L.CONSOLEVARIABLES_LOCKS_OFF_DESC = "They go back to what the game sets, until it's on again."
L.CONSOLEVARIABLES_COMMAND = "open Console Variables, searching for [search]"
L.CONSOLEVARIABLES_NO_PAGE = "This client's Settings can't open the Console Variables page."
L.CONSOLEVARIABLES_AFTER_COMBAT = "%s changes after combat." -- CVar name
L.CONSOLEVARIABLES_REFUSED = "%s can't be changed." -- CVar name
L.CONSOLEVARIABLES_KEPT = "%s kept %s: the game didn't take %s." -- CVar name, its value, the typed one
L.CONSOLEVARIABLES_SEARCH = "Search console variables" -- gray text in the empty search box
L.CONSOLEVARIABLES_POPULAR = "Popular" -- the group of CVars players most often look for
L.CONSOLEVARIABLES_FAVORITES = "Favorites" -- the group of CVars the player starred
L.CONSOLEVARIABLES_LOCKED = "Locked" -- the group of CVars the player locked at a value
L.CONSOLEVARIABLES_CHANGED = "Changed" -- the group of CVars not at their default
L.CONSOLEVARIABLES_ALL = "All"
-- The client's own CVar categories (Enum.ConsoleCategory). Default, Gm, Reveal, and None read badly
-- to players, so they get plainer names.
L.CONSOLEVARIABLES_CATEGORY_DEBUG = "Debug"
L.CONSOLEVARIABLES_CATEGORY_GRAPHICS = "Graphics"
L.CONSOLEVARIABLES_CATEGORY_CONSOLE = "Console"
L.CONSOLEVARIABLES_CATEGORY_COMBAT = "Combat"
L.CONSOLEVARIABLES_CATEGORY_GAME = "Game"
L.CONSOLEVARIABLES_CATEGORY_DEFAULT = "General" -- Default
L.CONSOLEVARIABLES_CATEGORY_NET = "Network"
L.CONSOLEVARIABLES_CATEGORY_SOUND = "Sound"
L.CONSOLEVARIABLES_CATEGORY_GM = "Game Master" -- Gm
L.CONSOLEVARIABLES_CATEGORY_REVEAL = "Revealed" -- Reveal
L.CONSOLEVARIABLES_CATEGORY_NONE = "Other" -- None
L.CONSOLEVARIABLES_NO_MATCH = "No console variables match \"%s\"." -- the search text
L.CONSOLEVARIABLES_NONE_CHANGED = "Every console variable is at its default."
L.CONSOLEVARIABLES_NO_FAVORITES = "Click the star on a console variable to keep it here."
L.CONSOLEVARIABLES_NO_LIST = "This client doesn't list its console variables. Search for one's full "
    .. "name to find it."
L.CONSOLEVARIABLES_DEFAULT = "Default"
L.CONSOLEVARIABLES_VALUE_IS = "Value: %s"
L.CONSOLEVARIABLES_DEFAULT_IS = "Default: %s"
L.CONSOLEVARIABLES_ON_OFF = "0 is usually off, 1 is usually on."
L.CONSOLEVARIABLES_ON_OFF_HINT = "0 is usually off and 1 on. If that doesn't fit, it takes other "
    .. "values: look it up."
L.CONSOLEVARIABLES_ACCOUNT = "Saved for your account."
L.CONSOLEVARIABLES_CHARACTER = "Saved for this character."
L.CONSOLEVARIABLES_READ_ONLY = "Can't be changed."
L.CONSOLEVARIABLES_SECURE = "Protected: changes wait until combat ends."
L.CONSOLEVARIABLES_NO_LOCKS = "Click the lock on a console variable to keep its value through every "
    .. "login and change."
-- Locks: a locked CVar is put back to its value at login and whenever something changes it.
L.CONSOLEVARIABLES_LOCKED_AT = "Locked at %s: put back at every login and whenever something "
    .. "changes it." -- the locked value
L.CONSOLEVARIABLES_LOCK_HINT = "Click the lock to keep this value." -- tooltip of an open lock
L.CONSOLEVARIABLES_UNLOCK_HINT = "Click the lock to stop keeping it." -- tooltip of a closed lock
L.CONSOLEVARIABLES_LOCK_STOPPED = "Not kept until you reload or log in again: it wouldn't hold."
L.CONSOLEVARIABLES_LOCK_FAILED = "%s couldn't be put back to its locked %s (it's %s). Its lock waits "
    .. "until you reload or log in again." -- CVar name, the locked value, its value now
L.CONSOLEVARIABLES_LOCK_FIGHT = "%s keeps being changed by something else. Its lock waits until you "
    .. "reload or log in again." -- CVar name
-- Popular: the section headers, then each CVar's plain name and what it does.
L.CONSOLEVARIABLES_POP_CAMERA = "Camera"
L.CONSOLEVARIABLES_POP_EFFECTS = "Screen Effects"
L.CONSOLEVARIABLES_POP_NAMEPLATES = "Nameplates"
L.CONSOLEVARIABLES_POP_MAP = "Map"
L.CONSOLEVARIABLES_POP_CHAT = "Chat"
L.CONSOLEVARIABLES_POP_COMBAT = "Combat"
L.CONSOLEVARIABLES_POP_INTERFACE = "Interface"
L.CONSOLEVARIABLES_POP_GRAPHICS = "Graphics"
L.CONSOLEVARIABLES_POP_SCREENSHOTS = "Screenshots"
L.CONSOLEVARIABLES_POP_MOUSE = "Mouse"
L.CONSOLEVARIABLES_POP_ZOOM = "Max Camera Distance"
L.CONSOLEVARIABLES_POP_ZOOM_DESC = "How far you can zoom out. Options stops at 2.0; this can go further."
L.CONSOLEVARIABLES_POP_ZOOM_SPEED = "Zoom Speed"
L.CONSOLEVARIABLES_POP_ZOOM_SPEED_DESC = "How fast the mouse wheel zooms the camera. Default 20, up to 50."
L.CONSOLEVARIABLES_POP_COLLISION = "Camera Collision"
L.CONSOLEVARIABLES_POP_COLLISION_DESC = "1 lets trees and walls get between you and the camera before it "
    .. "jumps closer; 0 jumps at once."
L.CONSOLEVARIABLES_POP_GLOW = "Screen Glow"
L.CONSOLEVARIABLES_POP_GLOW_DESC = "The soft glow over the whole screen. 0 turns it off for a sharper picture."
L.CONSOLEVARIABLES_POP_DEATH = "Death Effect"
L.CONSOLEVARIABLES_POP_DEATH_DESC = "The gray blur while you're dead. 0 turns it off."
L.CONSOLEVARIABLES_POP_PLATE_RANGE = "Nameplate Range"
L.CONSOLEVARIABLES_POP_PLATE_RANGE_DESC = "How far away nameplates show, in yards. Default 45. Saved for "
    .. "this character."
L.CONSOLEVARIABLES_POP_PLATE_SPACING = "Nameplate Spacing"
L.CONSOLEVARIABLES_POP_PLATE_SPACING_DESC = "How far apart stacked nameplates sit. Lower packs them "
    .. "closer. Default 1.1."
L.CONSOLEVARIABLES_POP_PLATE_FAR = "Far Nameplate Opacity"
L.CONSOLEVARIABLES_POP_PLATE_FAR_DESC = "How faded far nameplates are, 0 to 1. Default 0.6; 1 never fades."
L.CONSOLEVARIABLES_POP_PLATE_HIDDEN = "Hidden Unit Opacity"
L.CONSOLEVARIABLES_POP_PLATE_HIDDEN_DESC = "How faded the nameplates of units behind walls are, 0 to 1. "
    .. "Default 0.4."
L.CONSOLEVARIABLES_POP_PLATE_TARGET = "Target Nameplate Size"
L.CONSOLEVARIABLES_POP_PLATE_TARGET_DESC = "How much bigger your target's nameplate is. Default 1.2; 1 is "
    .. "the same size."
L.CONSOLEVARIABLES_POP_PLATE_SIMPLIFIED = "Simplified Nameplate Size"
L.CONSOLEVARIABLES_POP_PLATE_SIMPLIFIED_DESC = "How big simplified nameplates are. Default 0.3. The "
    .. "game can put it back to its default at login, so lock it to keep yours."
L.CONSOLEVARIABLES_POP_PLATE_TOTEMS = "Enemy Totem Nameplates"
L.CONSOLEVARIABLES_POP_PLATE_TOTEMS_DESC = "1 shows nameplates on enemy totems, so you can find and "
    .. "target them."
L.CONSOLEVARIABLES_POP_PLATE_PETS = "Enemy Pet Nameplates"
L.CONSOLEVARIABLES_POP_PLATE_PETS_DESC = "1 shows nameplates on enemy players' pets."
L.CONSOLEVARIABLES_POP_COMBO = "Combo Point Position"
L.CONSOLEVARIABLES_POP_COMBO_DESC = "Where combo points show: 1 on your target's frame, 2 on yours."
L.CONSOLEVARIABLES_POP_FOG_END = "Fog Distance"
L.CONSOLEVARIABLES_POP_FOG_END_DESC = "How far away the distance fog is thickest. Default 1600; raise "
    .. "it with View Distance."
L.CONSOLEVARIABLES_POP_FOG_START = "Fog Start"
L.CONSOLEVARIABLES_POP_FOG_START_DESC = "How far away the distance fog begins. Default 800."
L.CONSOLEVARIABLES_POP_GRASS = "Grass Density"
L.CONSOLEVARIABLES_POP_GRASS_DESC = "How thick grass and ground clutter are. Default 16; higher costs "
    .. "frames."
L.CONSOLEVARIABLES_POP_GRASS_DIST = "Grass Distance"
L.CONSOLEVARIABLES_POP_GRASS_DIST_DESC = "How far away grass is drawn. Default 70."
L.CONSOLEVARIABLES_POP_ROTATE = "Rotate Minimap"
L.CONSOLEVARIABLES_POP_ROTATE_DESC = "1 turns the minimap with you, so up is the way you face."
L.CONSOLEVARIABLES_POP_MAP_FADE = "World Map Fade"
L.CONSOLEVARIABLES_POP_MAP_FADE_DESC = "1 fades the world map while you move. 0 keeps it solid."
L.CONSOLEVARIABLES_POP_CHAT_SCROLL = "Chat Mouse Wheel"
L.CONSOLEVARIABLES_POP_CHAT_SCROLL_DESC = "1 scrolls chat with the mouse wheel."
L.CONSOLEVARIABLES_POP_LOOT_SPAM = "Full Loot Rolls"
L.CONSOLEVARIABLES_POP_LOOT_SPAM_DESC = "1 shows every player's roll in chat; 0 only the winner."
L.CONSOLEVARIABLES_POP_QUEUE = "Spell Queue Window"
L.CONSOLEVARIABLES_POP_QUEUE_DESC = "How early you can queue your next spell, in milliseconds, 0 to 400. "
    .. "Default 400."
L.CONSOLEVARIABLES_POP_STOP_ATTACK = "Stop Attack on Retarget"
L.CONSOLEVARIABLES_POP_STOP_ATTACK_DESC = "1 stops your auto attack when you change target."
L.CONSOLEVARIABLES_POP_TEXT_SIZE = "Combat Text Size"
L.CONSOLEVARIABLES_POP_TEXT_SIZE_DESC = "How big the floating combat numbers are. Default 1."
L.CONSOLEVARIABLES_POP_ERRORS = "Show Lua Errors"
L.CONSOLEVARIABLES_POP_ERRORS_DESC = "1 pops up the game's window when an addon has an error."
L.CONSOLEVARIABLES_POP_COMPARE = "Always Compare Items"
L.CONSOLEVARIABLES_POP_COMPARE_DESC = "1 shows what you wear beside an item's tooltip without holding Shift."
L.CONSOLEVARIABLES_POP_PUSH_SPELLS = "New Spells on Action Bar"
L.CONSOLEVARIABLES_POP_PUSH_SPELLS_DESC = "1 puts spells you learn on your action bars by themselves. "
    .. "Saved for this character."
L.CONSOLEVARIABLES_POP_LOOT_RATE = "Auto Loot Speed"
L.CONSOLEVARIABLES_POP_LOOT_RATE_DESC = "Milliseconds between items as auto loot takes them. Lower is "
    .. "faster. Default 150."
L.CONSOLEVARIABLES_POP_FARCLIP = "View Distance"
L.CONSOLEVARIABLES_POP_FARCLIP_DESC = "How far away the world is drawn. Default 1000; higher costs frames."
L.CONSOLEVARIABLES_POP_WEATHER = "Weather"
L.CONSOLEVARIABLES_POP_WEATHER_DESC = "How much rain and snow you see, 0 (none) to 3. Default 2."
L.CONSOLEVARIABLES_POP_SHOT_QUALITY = "Screenshot Quality"
L.CONSOLEVARIABLES_POP_SHOT_QUALITY_DESC = "1 to 10, higher is sharper and bigger. Default 3."
L.CONSOLEVARIABLES_POP_SHOT_FORMAT = "Screenshot Format"
L.CONSOLEVARIABLES_POP_SHOT_FORMAT_DESC = "jpeg (small files), png, or tga (no loss, big files)."
L.CONSOLEVARIABLES_POP_RAW_MOUSE = "Raw Mouse Input"
L.CONSOLEVARIABLES_POP_RAW_MOUSE_DESC = "1 reads the mouse directly, which can stop the cursor jumping "
    .. "when you let go of the camera."

-- SelfTest
L.SELFTEST_TITLE = "Self Test"
L.SELFTEST_DESC = "Probe the client APIs Forever++ depends on and save what they do, for debugging."
L.SELFTEST_COMMAND = "run the self test, then /reload to save its log"
L.SELFTEST_BUTTON = "Run"
L.SELFTEST_BUTTON_DESC = "Probe the client APIs Forever++ relies on, then record flights, deaths and "
    .. "other events until you /reload. The results are saved to Forever++'s SavedVariables file."
L.SELFTEST_DONE = "Self test wrote %d lines. Type /reload to save them." -- number of lines
L.SELFTEST_GAMEDATA = "Learned Game Data"
L.SELFTEST_GAMEDATA_BUTTON = "Forget"
L.SELFTEST_GAMEDATA_DESC = "Forget the item, spell, and map facts Forever++ learned in play, going back "
    .. "to what it ships with. They're learned again as you play."
L.SELFTEST_GAMEDATA_CONFIRM = "Forget all game data Forever++ learned in play?"
L.SELFTEST_GAMEDATA_DONE = "Learned game data forgotten."

-- Screenshots
L.SCREENSHOTS_TITLE = "Screenshots"
L.SCREENSHOTS_DESC = "Take screenshots of Forever++ in the game's own windows, one after another, "
    .. "for its pages and posts."
L.SCREENSHOTS_COMMAND = "take a screenshot of each scene, or of one (tooltip, minimap, map, bags, "
    .. "character, skills, talents, whispers, settings), or of the screen as it is after a wait"
L.SCREENSHOTS_BUTTON = "Take"
L.SCREENSHOTS_BUTTON_DESC = "Take a screenshot of each Forever++ scene in turn: it shows an item "
    .. "tooltip, the minimap button's tooltip, the Whisper Window with a made-up conversation, and "
    .. "Settings itself, and asks you to open the world "
    .. "map, your bags, the character window, the Skills tab, and talents in plan mode, taking each "
    .. "picture once "
    .. "it's ready. "
    .. "Modules a picture shows are on just for its shot. Keep the mouse over an empty part of the "
    .. "screen."
L.SCREENSHOTS_START = "Taking %d screenshots. Keep the mouse over an empty part of the screen, and "
    .. "open each window when asked." -- number
L.SCREENSHOTS_CLOSE_SETTINGS = "Close Settings to start."
L.SCREENSHOTS_OPEN = "Open %s." -- scene name
L.SCREENSHOTS_OPEN_KEY = "Open %s (%s)." -- scene name, its key
L.SCREENSHOTS_NOT_OPENED = "it wasn't opened"
L.SCREENSHOTS_NOT_READY = "it wasn't ready in time"
L.SCREENSHOTS_CLOSE_FIRST = "Close %s first." -- what's in the way
L.SCREENSHOTS_YOUR_BAGS = "your bags"
L.SCREENSHOTS_PLAN_TALENTS = "Click Plan Talents at the bottom of the talent window."
L.SCREENSHOTS_WAIT = "Taking a screenshot in %d seconds." -- seconds
L.SCREENSHOTS_DONE = "Took %d screenshots. They're in the game's Screenshots folder." -- number
L.SCREENSHOTS_SKIPPED = "Skipped %s: %s." -- scene name, why
L.SCREENSHOTS_STOPPED = "Screenshots stopped for combat. Everything goes back after it."
L.SCREENSHOTS_COMBAT = "Screenshots can't be taken in combat."
L.SCREENSHOTS_BUSY = "Screenshots are already being taken."
L.SCREENSHOTS_UNKNOWN = "There's no scene called \"%s\". Scenes: %s." -- what was typed, the list
L.SCREENSHOTS_FAILED = "the game couldn't save it"
L.SCREENSHOTS_NO_WINDOW = "its window didn't open"
L.SCREENSHOTS_NO_SKILLS = "this client has no Skills tab"
L.SCREENSHOTS_NO_BUTTON = "the minimap button isn't on the minimap"
L.SCREENSHOTS_NO_MODULE = "this client doesn't have %s" -- module name
L.SCREENSHOTS_SCENE_MAP = "World Map"
L.SCREENSHOTS_SCENE_TOOLTIP = "Item Tooltip"
L.SCREENSHOTS_SCENE_BAGS = "Bags"
L.SCREENSHOTS_SCENE_CHARACTER = "Character Window"
L.SCREENSHOTS_SCENE_SKILLS = "the Character Window's Skills tab"
L.SCREENSHOTS_SCENE_TALENTS = "Talents"
L.SCREENSHOTS_SCENE_SETTINGS = "Settings"
L.SCREENSHOTS_SCENE_WHISPERS = "Whisper Window"
L.SCREENSHOTS_SCENE_MINIMAP = "Minimap Button"
L.SCREENSHOTS_SCENE_SCREEN = "Screen"

-- Profiler
L.PROFILER_TITLE = "CPU Profiler"
L.PROFILER_DESC = "See how much CPU each module takes, on a page in Settings, to find what's slow."
L.PROFILER_COMMAND = "open the Profiler page"
L.PROFILER_NO_PAGE = "This client's Settings can't open the Profiler page."
L.PROFILER_RECORD = "Record"
L.PROFILER_STOP = "Stop"
L.PROFILER_RESET = "Clear"
L.PROFILER_IDLE = "Press Record and play as usual. The modules that take the most CPU rise to the top."
L.PROFILER_RECORDING = "Recording for %s." -- time, such as 1:23
L.PROFILER_STOPPED = "Recorded %s." -- time, such as 1:23
L.PROFILER_ADDON_CPU = "Forever++: %.3f ms a frame, %.1f ms at most." -- ms, ms, lately
L.PROFILER_ADDON_MEMORY = "Memory: %.1f MB" -- megabytes
L.PROFILER_MODULE = "Module"
L.PROFILER_PER_SECOND = "ms a second"
L.PROFILER_PEAK = "Worst frame (ms)"
L.PROFILER_CALLS = "Calls a second"
L.PROFILER_SHARED = "Shared code" -- time in Forever++'s libraries not traced to one module
L.PROFILER_OWN = "everything else" -- under a module's parts: its time outside them
L.PROFILER_EMPTY = "Nothing recorded yet."
-- What a module's time went to, under it on the page, for paths with no name of their own (events
-- and hooks show their own names, such as BAG_UPDATE or GameTooltip:Show).
L.PROFILER_SOURCE_UPDATE = "Updates (OnUpdate)"
L.PROFILER_SOURCE_DELAYED = "Delayed runs"
L.PROFILER_SOURCE_TIMER = "Timers"
L.PROFILER_SOURCE_TOOLTIP = "Item tooltip lines"
L.PROFILER_SOURCE_PLATE_ADDED = "Nameplate added"
L.PROFILER_SOURCE_PLATE_REMOVED = "Nameplate removed"
L.PROFILER_SOURCE_PLATE_CAST = "Nameplate cast bar"
L.PROFILER_SOURCES = "By source" -- the header over a module's sources
L.PROFILER_SPIKES = "Spikes: frames Forever++ took over %d ms in" -- ms
L.PROFILER_NO_SPIKES = "None yet."
L.PROFILER_SPIKE = "%s  %.1f ms  %s" -- time into the recording, ms, who: "1:12  21.5 ms  World Map, OnShow"
L.PROFILER_SPIKE_COMBAT = "in combat"
L.PROFILER_MEMORY_GROWTH = "(%+.1f KB a second)" -- KB a second while recording, signed; after the memory
L.PROFILER_COPY = "Copy"
L.PROFILER_COPY_PROMPT = "Press Ctrl+C to copy the results."
L.PROFILER_COPY_LINE = "Forever++ %s profile, %s recorded" -- version, time
L.PROFILER_COUNTED = "Counted, not timed: a stopwatch around each of thousands a second would cost "
    .. "more than the call." -- a part's tooltip on the Profiler page
L.PROFILER_NOTE = "Only Forever++'s own code is timed, and timing it adds a little cost of its own "
    .. "while recording. Memory can only be read for the whole addon, not for each module."

-- Gear Probe
L.GEARPROBE_TITLE = "Gear Probe"
L.GEARPROBE_DESC = "Read what this client says about your gear, talent tabs, and stats, for "
    .. "working on Upgrade Arrows."
L.GEARPROBE_COMMAND = "probe your gear, bags, talents, and stats, then /reload to save the log"
L.GEARPROBE_BUTTON = "Run"
L.GEARPROBE_BUTTON_DESC = "Read the stats of what you wear and of the gear in your bags, the "
    .. "game's own item comparison, your talent tabs, and your stats, and save it for the "
    .. "developers. Open your bags first, with a piece of gear in them that has an Equip: hit, "
    .. "crit, or spell power line. Type /reload afterwards to save the log."
L.GEARPROBE_DONE = "Gear probe wrote %d lines, with %d pieces of gear from your bags. Type /reload "
    .. "to save them." -- number of lines, number of bag items
L.GEARPROBE_NO_GEAR = "No weapons or armor were found in your bags, so the comparison wasn't tried."
