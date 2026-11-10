-- English text, and the fallback for every other language: every key the addon uses is in a file
-- under Locales/enUS/. Another language gets a folder of its own (Locales/deDE/, ...) whose files
-- start the same way with its own code, set only the keys they translate, and go in the TOC after
-- these. Splitting by category, as the modules are, is a choice: one file per language works too.
-- This file has the core's own text: the Lib helpers, /fpp, and the Settings pages.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- Lib/Text.lua: lengths of time, for slider labels and price lines
L.TEXT_ONE_SECOND = "1 Second"
L.TEXT_SECONDS = "%d Seconds" -- number of seconds, more than one
L.TEXT_ONE_MINUTE = "1 Minute"
L.TEXT_MINUTES = "%d Minutes" -- minutes
L.TEXT_ONE_HOUR = "1 Hour"
L.TEXT_HOURS = "%d Hours" -- hours, more than one
L.TEXT_AGO_NOW = "just now"
L.TEXT_AGO_MINUTES = "%dm ago" -- minutes
L.TEXT_AGO_HOURS = "%dh ago" -- hours
L.TEXT_AGO_DAYS = "%dd ago" -- days
L.TEXT_YARDS = "%s yds" -- a distance; the game's own words are used when it has them

-- Lib/Fonts.lua: the game's fonts, in every font dropdown
L.FONT_FRIZQT = "Friz Quadrata"
L.FONT_ARIALN = "Arial Narrow"
L.FONT_SKURRI = "Skurri"
L.FONT_MORPHEUS = "Morpheus"

-- Lib/Frames.lua: our windows' titles
L.FRAMES_WINDOW_TITLE = "%s %s" -- the addon's name (in gray), the window's title

-- Lib/Keys.lua: modifier keys, in every key dropdown
L.KEY_SHIFT = "Shift"
L.KEY_CTRL = "Ctrl"
L.KEY_ALT = "Alt"
L.KEY_NONE = "None"
L.SKIP_KEY = "Skip Key" -- the option of every module that a held key skips

-- Core: /fpp and chat
L.ON = "on"
L.OFF = "off"
L.MODULE_STATE = "%s is %s." -- module name, on/off
L.MODULE_ALWAYS_ON = "%s is a tool and is always on." -- module title, such as Self Test
L.NO_MODULE = "no module called %s"
L.COMMAND_NEEDS_MODULE = "/fpp %s needs %s, which is off on the Modules page." -- command, title
L.SLASH_MODULES = "modules (/fpp toggle <name>, /fpp list):"
L.SLASH_OPEN = "open the settings"
L.SLASH_LIST = "list the modules and whether each is on"
L.SLASH_TOGGLE = "turn a module, or one of its checkboxes, on or off"
L.SLASH_RESET = "all settings back to defaults (reloads)"
L.RESET_CONFIRM = "Put every Forever++ setting back to its default and clear everything it saved, "
    .. "such as auction prices and flight times? This reloads the UI."
L.SLASH_OPTIONS = "list its options and their values"
L.SLASH_SET = "change one (on/off, a choice, or a number)"
L.SLASH_TAKEN = "%s already belongs to another addon, so Forever++ leaves it to that addon."

-- Core: /fpp options and /fpp set. The values typed (on, off, choice keys) stay as they are.
L.OPTIONS_HEADER = "%s is %s. Options (/fpp set %s <option> <value>):" -- module, on/off, module
L.OPTIONS_NONE = "none"
L.OPTIONS_DEBUG = ", debug"
L.SET_USAGE = "usage: /fpp set <module> <option> <value>"
L.MODULE_STATE_ALLOWED = "%s is %s (on, off)." -- module name, on/off
L.NO_OPTION = "%s has no option %s. /fpp options %s lists them." -- module, option, module
L.OPTION_STATE = "%s %s is %s." -- module, option, value
L.OPTION_STATE_ALLOWED = "%s %s is |cffffd100%s|r (%s)." -- module, option, value, allowed values
L.CHAT_MESSAGES = "Chat Messages" -- a module's checkbox for what it says in chat by itself

-- Lib/Profiles.lua: profiles, and /fpp profile
L.PROFILES_DEFAULT = "Default" -- the profile everyone starts with, which is always there
L.PROFILES_NAME_EMPTY = "A profile needs a name."
L.PROFILES_NAME_TAKEN = "There is already a profile called %s." -- name
L.PROFILES_DEFAULT_ALWAYS = "Default is always there, so it can't be renamed or deleted."
L.SLASH_PROFILE = "list the profiles, or switch this character to one"
L.PROFILES_HEADER = "profiles (/fpp profile <name> to switch):"
L.PROFILES_CHARACTERS = "%d characters" -- how many characters use a profile, more than one
L.PROFILES_ONE_CHARACTER = "1 character"
L.PROFILES_SWITCHED = "Now using the %s profile." -- profile name
L.PROFILES_AFTER_COMBAT = "Switching to the %s profile once combat ends." -- profile name
L.PROFILES_NO_SUCH = "No profile called %s. /fpp profile lists them." -- what was typed

-- Settings
-- The Modules page's groups of modules.
L.CATEGORY_AUTOMATION = "Automation"
L.CATEGORY_CHARACTER = "Character"
L.CATEGORY_CHAT = "Chat"
L.CATEGORY_INTERFACE = "Interface"
L.CATEGORY_ITEMS = "Items"
L.CATEGORY_MAP = "Map"
L.CATEGORY_QUESTS = "Quests"
L.CATEGORY_SYSTEM = "System"
L.CATEGORY_TOOLS = "Tools" -- pages for finding problems: Console Variables, Profiler, Debug
L.CATEGORY_UNITS = "Units" -- unit frames and nameplates
L.CATEGORY_OTHER = "Other"
L.DEBUG = "Debug"
L.SETTINGS_AFTER_COMBAT = "Settings open after combat."
L.MODULES = "Modules" -- the page with every module's checkbox, the top Forever++ entry
L.ABOUT = "About" -- the page with the version, links, commands, and presets
-- The selected module on the Modules page
L.SETTINGS_ENABLED = "Enabled" -- the module's own on/off checkbox, under its description
-- The tooltip of the padlock in a locked module's checkbox's place
L.SETTINGS_LOCKED = "Turned off and locked: the game broke what this module does. Its settings say more."
L.SETTINGS_OPTIONS = "Options" -- the header over its options
L.SETTINGS_NO_OPTIONS = "This module has no options."
L.SETTINGS_CONFLICT_GO = "Go to %s" -- an option's name
-- A mark on an item or action button icon (Lib/ItemButtons.lua): its corner, size, and padding,
-- the same in every module that has one.
L.ICONMARK_CORNER = "Corner"
L.ICONMARK_CORNER_TOPLEFT = "Top Left"
L.ICONMARK_CORNER_TOPRIGHT = "Top Right"
L.ICONMARK_CORNER_BOTTOMLEFT = "Bottom Left"
L.ICONMARK_CORNER_BOTTOMRIGHT = "Bottom Right"
L.ICONMARK_PIXELS = "%d px" -- a size or padding slider's value
L.ICONMARK_PADDING = "Padding"
L.ICONMARK_PADDING_DESC = "How far in from its corner the mark sits: at 2, a mark in the top left "
    .. "moves 2 pixels right and 2 down."
L.ICONMARK_SECTION_SHOW = "Show On" -- the header over the places a module marks items in
L.ICONMARK_PLACE_BAGS = "Bags"
L.ICONMARK_PLACE_BANK = "Bank"
L.ICONMARK_PLACE_MERCHANT = "Merchants"
L.ICONMARK_PLACE_AUCTION = "Auction House"
L.ICONMARK_PLACE_LOOT = "Loot"
L.ICONMARK_PLACE_MAIL = "Mail"
L.ICONMARK_PLACE_QUESTS = "Quest Rewards"
L.SETTINGS_PAGE_NOTE = "While it's on, its %s page is in the sidebar under Forever++. The page "
    .. "shows or goes away once you pick another page."
L.SETTINGS_TURN_ON = "Turn On" -- the button on a "Blizzard's ... is off" row
L.SETTINGS_RESET = "Reset to Default" -- the arrow at the end of an option's row while it's changed
L.SETTINGS_RESET_TO = "Default: %s" -- what the option goes back to
L.SETTINGS_RESET_PAIR = "%s, %s" -- a checkbox's default, then its slider's, in one row
L.SETTINGS_CHECKED = "Checked" -- a checkbox's default
L.SETTINGS_UNCHECKED = "Unchecked"
L.SETTINGS_SEARCH = "Search modules" -- gray text in the Modules page's empty search box
L.SETTINGS_NO_MATCH = "No modules match \"%s\"." -- the search text
L.SETTINGS_NEW_ONLY = "New" -- the checkbox beside the search box that lists only modules marked NEW
L.SETTINGS_NOTHING_NEW = "Nothing new." -- the Modules list while that checkbox is on and nothing is new
-- The Debug module's section headers on the Modules page, in the order they show. Modules put
-- their debug options and buttons in one with `section`.
L.DEBUG_SECTION_NEW = "What's New"
L.DEBUG_SECTION_DIAGNOSTICS = "Diagnostics"
L.DEBUG_SECTION_TOOLS = "Tools"
L.DEBUG_SECTION_PREVIEWS = "Previews"
L.DEBUG_SECTION_LAYOUT = "Layout"
L.DEBUG_SECTION_LOGGING = "Logging"
-- The Debug module's own buttons: Reset Seen Version and Reset Welcome in What's New, Copy Debug
-- Info and Print Module Events in Diagnostics, Reload UI in Tools
L.DEBUG_RESET_SEEN = "Reset Seen Version"
L.DEBUG_RESET_SEEN_BUTTON = "Reset"
L.DEBUG_RESET_SEEN_DESC = "Forget that you've seen this version, as if you just updated from the "
    .. "release before it, and open the Modules page the way a player updating would see it. Its tags go "
    .. "once you leave the page."
L.DEBUG_RESET_WELCOME = "Reset Welcome"
L.DEBUG_RESET_WELCOME_BUTTON = "Reset"
L.DEBUG_RESET_WELCOME_DESC = "Show the welcome again as on a fresh install: the NEW tag on the "
    .. "Minimap Button, which opens the About page once. Keeps all your settings."
L.DEBUG_RESET_WELCOME_DONE = "The welcome shows again. Click the Minimap Button to see it."
L.DEBUG_INFO = "Copy Debug Info"
L.DEBUG_INFO_BUTTON = "Copy"
L.DEBUG_INFO_DESC = "Show one line to copy into a bug report: the Forever++ version, the client "
    .. "build, and the modules that are on."
L.DEBUG_INFO_PROMPT = "Press Ctrl+C to copy the debug info."
-- Forever++ version, game version, build, interface, locale, module count, module names
L.DEBUG_INFO_LINE = "Forever++ %s | Client %s (%s), interface %s, %s | Modules on (%d): %s"
L.DEBUG_EVENTS = "Print Module Events"
L.DEBUG_EVENTS_BUTTON = "Print"
L.DEBUG_EVENTS_DESC = "Print in chat the events each module listens to and how many hooks it has "
    .. "made, to check that a module that's off listens to nothing. Hooks stay once made but do "
    .. "nothing while their module is off."
L.DEBUG_EVENTS_LINE = "%s (%s): %d events: %s; %d hooks" -- module title, On/Off, count, names, hooks
L.DEBUG_EVENTS_CLEAN = "No module that's off is listening to events."
L.DEBUG_EVENTS_LEAKS = "%d modules are off but still listening to events (in red)."
L.DEBUG_RELOAD = "Reload UI"
L.DEBUG_RELOAD_BUTTON = "Reload"
L.DEBUG_RELOAD_DESC = "Reload the interface, like /rl, to load changes to the addon's files."

-- Settings: the Profiles page
L.PROFILES = "Profiles"
L.PROFILES_USES = "%s Uses" -- a character's name, before the dropdown of its profile
L.PROFILES_USES_TITLE = "This Character's Profile"
L.PROFILES_USES_DESC = "The profile %s uses. What you change in Forever++ saves to it, for every "
    .. "character that uses it." -- character
L.PROFILES_NEW_CHARACTERS = "New Characters Use"
L.PROFILES_NEW_CHARACTERS_DESC = "The profile a character starts on the first time it logs in."
L.PROFILES_NEW = "New Profile"
L.PROFILES_NEW_DESC = "Make a profile, as a copy of the one selected or from the defaults."
L.PROFILES_NEW_ASK = "Name the new profile."
L.PROFILES_NEW_FROM = "Make %s as a copy of %s, or from the defaults?" -- new name, selected profile
L.PROFILES_COPY_OF = "Copy of %s" -- a profile
L.PROFILES_FROM_DEFAULTS = "From Defaults"
L.PROFILES_IN_USE = "In use by this character"
L.PROFILES_SUMMARY = "%d modules on, %d settings changed from their defaults."
L.PROFILES_USED_BY = "Used by %s." -- character names
L.PROFILES_UNUSED = "No character uses it."
L.PROFILES_USE = "Use on This Character"
L.PROFILES_USE_DESC = "Switches %s to %s right away, with no reload." -- character, profile
L.PROFILES_RENAME = "Rename"
L.PROFILES_RENAME_DESC = "Give %s another name." -- profile
L.PROFILES_RENAME_ASK = "Rename %s to:" -- profile
L.PROFILES_DELETE = "Delete"
L.PROFILES_DELETE_DESC = "Delete %s. Characters using it go back to Default." -- profile
L.PROFILES_DELETE_ASK = "Delete %s? Characters using it go back to Default." -- profile
L.PROFILES_CHARACTERS_HEADER = "Characters"
L.PROFILES_CHARACTER_LINE = "Level %d %s" -- level, class
L.PROFILES_THIS_CHARACTER = "this character"
L.PROFILES_USES_OTHER = "uses %s" -- the profile another character uses
L.PROFILES_CHECK_DESC = "Check to have %s use %s." -- character, profile
L.PROFILES_UNCHECK_DESC = "Uncheck to put %s back on Default." -- character
L.PROFILES_ON_DEFAULT_DESC = "Every character uses a profile. To move %s off Default, check it on "
    .. "another profile." -- character
L.PROFILES_FORGET_HINT = "Right-click to forget this character."
L.PROFILES_FORGET_ASK = "Forget %s? It leaves this list until it logs in again." -- character
L.PROFILES_NOTE = "A profile is which modules are on, their settings, where you put Forever++'s "
    .. "frames in Edit Mode and windows with Movable Windows, and the Minimap Button's quick toggles. "
    .. "Auction prices, gathering nodes, players seen, and what each character keeps of its own, "
    .. "such as talent plans, aren't part of it."
L.PROFILES_MODULES_NOTE = "Profile: %s" -- beside the Modules page's title, with more than one
L.DEFAULTS_ASK_PROFILE = "Put the %s profile's Forever++ settings back to defaults? Every character "
    .. "using it changes too. The rest of the game's settings stay as they are." -- profile

-- Settings: Changelog page. The notes themselves are in Changelog.lua.
L.CHANGELOG = "Changelog"
L.CHANGELOG_RELEASE = "%s (%s)" -- version, date
L.CHANGELOG_UNRELEASED = "Unreleased"
L.CHANGELOG_SEARCH = "Search changes" -- gray text in the Changelog page's empty search box
L.CHANGELOG_BY_MODULE = "By Module" -- checkbox that groups a release's notes under their modules
L.CHANGELOG_GENERAL = "General" -- heading, with By Module on, for notes about no one module
L.CHANGELOG_NO_MATCH ="No changes match \"%s\"." -- the search text
L.CHANGELOG_ONE_CHANGE = "1 change"
L.CHANGELOG_CHANGES = "%d changes" -- how many entries a release has
L.CHANGELOG_ADDED = "Added"
L.CHANGELOG_CHANGED = "Changed"
L.CHANGELOG_FIXED = "Fixed"
L.CHANGELOG_REMOVED = "Removed"
L.CHANGELOG_SETTINGS = "Settings"
L.CHANGELOG_COMMANDS = "Commands"

-- Settings: the About page
L.HOME_WELCOME = "Welcome to %s" -- addon title
L.HOME_TAGLINE = "Small additions and changes to the default UI for WoW Forever."
L.HOME_VERSION = "Version %s by %s" -- version, author
L.HOME_THANKS = "Thanks to %s" -- the contributors, each as HOME_CREDIT, joined by commas
L.HOME_CREDIT = "%s (%s)" -- contributor's name, what they added
L.HOME_INTRO = "Each module is one small change to Blizzard's interface, made to look like it "
    .. "shipped with the game. Turn them on and off on the Modules page, and click one there to "
    .. "see what it does and its options. Settings are saved for your whole account, and the "
    .. "Profiles page gives characters sets of their own."
L.HOME_MODULES_ON = "%d of %d modules on" -- on, total
L.HOME_DEFAULTS = "Defaults"
-- The popup of the Defaults button at the top right of the Modules, Changelog, and About pages
L.DEFAULTS_ASK = "Put all Forever++ settings back to defaults? This replaces your current "
    .. "Forever++ settings. The rest of the game's settings stay as they are."
L.DEFAULTS_DEVELOPER = "Developer's Defaults"
L.DEFAULTS_RECOMMENDED = "Recommended Defaults"
L.HOME_GAME_BUILD = "Game %s (build %s, interface %s)" -- version, build, interface
L.HOME_LINKS = "Links"
L.HOME_WEBSITE = "Website"
L.HOME_ISSUES = "Feedback"
L.HOME_COPY = "Select the link and press Ctrl+C to copy it."
L.HOME_REQUESTS = "Want something changed or a new feature? Ask for it at the link above."
L.HOME_COMMANDS = "Commands"

-- Edit Mode dialog for our own frames (Lib/EditMode.lua)
L.EDITMODE_SCALE = "Scale"
L.EDITMODE_CLICK_TO_EDIT = "Click To Edit"
L.EDITMODE_RESET_POSITION = "Reset To Default Position"
L.SETTINGS_EDIT_MODE_NOTE = "Where it sits and how it's laid out are in Edit Mode: press Escape, "
    .. "pick Edit Mode, then click it." -- a gray row on a module with Edit Mode settings
L.SETTINGS_EDIT_MODE_NOTE_DESC = "Its place, scale, and layout settings are in its Edit Mode dialog and "
    .. "its right-click menu there, beside the frame they change."
