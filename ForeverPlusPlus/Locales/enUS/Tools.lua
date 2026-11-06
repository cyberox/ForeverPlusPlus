-- English text for the tool pages. Locales/enUS/Core.lua says how locale files work.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- ConsoleVariables
L.CONSOLEVARIABLES_TITLE = "Console Variables"
L.DEBUG_DESC = "Show every module's debug options and the testing tools (Self Test, Gear Probe, "
    .. "Screenshots) below, and turn on their commands."
L.DEBUG_NOTICE = "Turning Debug off puts every debug option back to its default." -- a gray row atop the module
L.DEBUG_NOTICE_DESC = "So nothing set here goes on working out of sight."
L.CONSOLEVARIABLES_DESC ="Browse the game's console variables (CVars) on a page in Settings, and "
    .. "change them."
L.CONSOLEVARIABLES_COMMAND = "open Console Variables, searching for [search]"
L.CONSOLEVARIABLES_NO_PAGE = "This client's Settings can't open the Console Variables page."
L.CONSOLEVARIABLES_AFTER_COMBAT = "%s changes after combat." -- CVar name
L.CONSOLEVARIABLES_REFUSED = "%s can't be changed." -- CVar name
L.CONSOLEVARIABLES_SEARCH = "Search console variables" -- gray text in the empty search box
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
    .. "map, your bags, the character window, and talents in plan mode, taking each picture once "
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
L.PROFILER_TITLE = "Profiler"
L.PROFILER_DESC = "See how much CPU each module takes, on a page in Settings, to find what's slow."
L.PROFILER_COMMAND = "open the Profiler page"
L.PROFILER_NO_PAGE = "This client's Settings can't open the Profiler page."
L.PROFILER_RECORD = "Record"
L.PROFILER_STOP = "Stop"
L.PROFILER_RESET = "Clear"
L.PROFILER_IDLE = "Press Record and play as usual. The modules that take the most CPU rise to the top."
L.PROFILER_RECORDING = "Recording for %s." -- time, such as 1:23
L.PROFILER_STOPPED = "Recorded %s." -- time, such as 1:23
L.PROFILER_ADDON_CPU = "All of Forever++: %.3f ms a frame lately, %.1f ms at most." -- ms, ms
L.PROFILER_ADDON_MEMORY = "Memory: %.1f MB." -- megabytes
L.PROFILER_MODULE = "Module"
L.PROFILER_PER_SECOND = "ms a second"
L.PROFILER_PEAK = "Worst frame (ms)"
L.PROFILER_CALLS = "Calls a second"
L.PROFILER_SHARED = "Shared code" -- time in Forever++'s libraries not traced to one module
L.PROFILER_OWN = "everything else" -- under a module's parts: its time outside them
L.PROFILER_EMPTY = "Nothing recorded yet."
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
