-- English text for the map modules and the map helpers. Locales/enUS/Core.lua says how locale
-- files work.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- Instances (Lib), shown in map tooltips and panels
L.INSTANCES_LEVEL = "Level %d"
L.INSTANCES_LEVELS = "Level %d-%d" -- lowest, highest
L.INSTANCES_RANGE = "%d-%d" -- lowest, highest

-- WorldMap: one module, a part each for Points of Interest, Zone Info, Unexplored Areas, and
-- Coordinates. Each part's title heads its section in Settings, over its Enabled checkbox.
L.WORLDMAP_TITLE = "World Map"
L.WORLDMAP_DESC = "Add to the world map: points of interest, a zone info panel, unexplored areas, "
    .. "and coordinates. Each has its own Enabled checkbox below."

-- PointsOfInterest. Place names on the map come from the game, or from Data.lua.
L.POI_TITLE = "Points of Interest"
-- Smaller headers over its options in Settings
L.POI_SECTION_INSTANCES = "Dungeons and Raids"
L.POI_SECTION_TRAVEL = "Cities and Travel"
L.POI_SECTION_OTHER = "Other"
L.POI_DESC = "Show dungeons, raids, capital cities, flight masters, boats, zeppelins, spirit "
    .. "healers, and Skyborne ley lines on the world map."
L.POI_DUNGEONS = "Dungeons"
L.POI_DUNGEONS_DESC = "Dungeon entrances, with their level range colored against yours."
L.POI_RAIDS = "Raids"
L.POI_RAIDS_DESC = "Raid entrances."
L.POI_CAPITALS = "Capital Cities"
L.POI_CAPITALS_DESC = "Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, and the "
    .. "Undercity: our icons, with the city's dungeons in the tooltip (Blizzard's are then "
    .. "hidden), Blizzard's own city icons, or neither."
L.POI_CAPITALS_OURS = "Forever++"
L.POI_CAPITALS_BLIZZARD = "Blizzard"
L.POI_CAPITALS_OFF = "Off"
L.POI_FLIGHT = "Flight Masters"
L.POI_FLIGHT_DESC = "Flight masters of your faction, and ones that fly for both."
L.POI_SHIPS = "Boats"
L.POI_SHIPS_DESC = "Boat docks, with where the boat goes."
L.POI_ZEPPELINS = "Zeppelins"
L.POI_ZEPPELINS_DESC = "Zeppelin towers, with where the zeppelin goes."
L.POI_SPIRIT = "Spirit Healers"
L.POI_SPIRIT_DESC = "Spirit healers, where you can come back to life after dying."
L.POI_SIZE = "Icon Size"
L.POI_SIZE_DESC = "How big the icons are, compared with their normal size."
L.POI_WORLD = "On Continent Maps"
L.POI_WORLD_DESC = "Also show them on the continent and world maps, not just zone maps."
L.POI_OTHER_FACTION = "Other Faction"
L.POI_OTHER_FACTION_DESC = "Also show the other faction's flight masters, boats, and zeppelins."
L.POI_LEYLINES = "Ley Lines"
L.POI_LEYLINES_DESC = "Ley lines (High Order Skyborne) and elemental convergences (Windshaper "
    .. "Skyborne), saved where a Skyborne on this account got the 15-minute buff from Read Ley "
    .. "Line or Skysight. Shown to a Skyborne for their own kind, to every character, or to none."
L.POI_LEYLINES_SKYBORNE = "Skyborne"
L.POI_LEYLINES_EVERYONE = "Everyone"
L.POI_LEYLINES_OFF = "Off"
L.POI_LEYLINE_ICON = "Ley Line Icon"
L.POI_LEYLINE_ICON_DESC = "How ley lines look on the map: the blue swirl the minimap shows for "
    .. "one, or a purple orb. Elemental convergences stay an orange orb."
L.POI_LEYLINE_ICON_PORTAL = "Portal"
L.POI_LEYLINE_ICON_ORB = "Orb"
L.POI_CHAT_DESC = "Say in chat when a new ley line is saved."
L.POI_LEYLINES_FORGET = "Saved Ley Lines"
L.POI_LEYLINES_FORGET_BUTTON = "Clear"
L.POI_LEYLINES_FORGET_DESC = "Forget every ley line and elemental convergence saved on this account."
L.POI_LEYLINES_FORGET_CONFIRM = "Forget every saved ley line and elemental convergence?"
L.POI_LEYLINES_FORGET_DONE = "Saved ley lines cleared."
L.POI_LEYLINE_SAVED = "Ley line saved on the map in %s." -- a zone
L.POI_CONVERGENCE_SAVED = "Elemental convergence saved on the map in %s." -- a zone
-- Tooltips
L.POI_DUNGEON = "Dungeon"
L.POI_RAID = "Raid"
L.POI_CAPITAL = "Capital City"
L.POI_PART = "%s (%s)" -- an instance, which entrance
L.POI_MAIN_GATE = "Main Gate"
L.POI_SERVICE_GATE = "Service Gate"
L.POI_NORTH = "North"
L.POI_EAST = "East"
L.POI_WEST = "West"
L.POI_FLIGHT_MASTER = "Flight Master"
L.POI_FLIGHT_UNLEARNED = "Not learned yet"
L.POI_SHIP_TO = "Boat to %s" -- a place
L.POI_ZEPPELIN_TO = "Zeppelin to %s" -- a place
L.POI_VIA = "Stops at %s first" -- a place, on a boat's way
L.POI_SPIRIT_HEALER = "Spirit Healer"
L.POI_LEYLINE = "Ley Line"
L.POI_CONVERGENCE = "Elemental Convergence"
L.POI_LEYLINE_CAST = "Cast %s here" -- a spell

-- ZoneInfo
L.ZONEINFO_TITLE = "Zone Info"
-- Smaller headers over its options in Settings
L.ZONEINFO_SECTION_GENERAL = "General"
L.ZONEINFO_SECTION_ZONE = "Zone"
L.ZONEINFO_SECTION_PROFESSIONS = "Professions"
L.ZONEINFO_DESC = "Show a zone's level range, fishing skill, and the herbs, ore, and skinning in "
    .. "it for your professions, in a corner of the world map."
L.ZONEINFO_CORNER = "Corner"
L.ZONEINFO_CORNER_DESC = "Which corner of the world map the panel sits in. In a right corner the icons move to the right and the text lines up on the right."
L.ZONEINFO_BOTTOMLEFT = "Bottom Left"
L.ZONEINFO_BOTTOMRIGHT = "Bottom Right"
L.ZONEINFO_TOPLEFT = "Top Left"
L.ZONEINFO_TOPRIGHT = "Top Right"
L.ZONEINFO_HOVER = "On Continent Maps"
L.ZONEINFO_HOVER_DESC = "On a continent map, show the zone under the cursor."
L.ZONEINFO_HIDE_LABEL = "Hide the Map's Zone Name"
L.ZONEINFO_HIDE_LABEL_DESC = "On a continent map, hide the zone name the game shows at the top of "
    .. "the map while this panel shows the same zone. Names of dungeons and other icons still show."
L.ZONEINFO_LEVELS = "Level Range"
L.ZONEINFO_LEVELS_DESC = "The zone's level range, colored against your level like quests."
L.ZONEINFO_FISHING = "Fishing"
L.ZONEINFO_FISHING_DESC = "The Fishing skill the zone's waters need: red while yours is lower, green once "
    .. "it's enough."
L.ZONEINFO_HERBS = "Herbs"
L.ZONEINFO_HERBS_DESC = "The herbs in the zone. With Herbalism they're colored against your skill "
    .. "like Profession Tooltips."
L.ZONEINFO_ORE = "Ore"
L.ZONEINFO_ORE_DESC = "The ore in the zone. With Mining it's colored against your skill."
L.ZONEINFO_SKINNING = "Skinning"
L.ZONEINFO_SKINNING_DESC = "The Skinning the zone's beasts need, from its level range."
L.ZONEINFO_SHOW_OFF = "Off"
L.ZONEINFO_SHOW_KNOWN = "With the Profession"
L.ZONEINFO_SHOW_ALWAYS = "Always"
L.ZONEINFO_SHOW_KEY = "Hold Detail Key"
L.ZONEINFO_DETAIL_KEY = "Detail Key"
L.ZONEINFO_DETAIL_KEY_DESC = "The key that shows the rows set to Hold Detail Key while you hold it. Herbs, ore, and skinning still need the profession."
L.ZONEINFO_FACTION = "Territory"
L.ZONEINFO_FACTION_DESC = "Who holds the zone, in the colors the game uses when you enter it: green "
    .. "for your faction, red for the other, orange for contested. On the zone's name, or on a "
    .. "line of its own."
L.ZONEINFO_FACTION_NAME = "Name Color"
L.ZONEINFO_FACTION_LINE = "Own Line"
L.ZONEINFO_TERRITORY = "%s Territory" -- a faction
L.ZONEINFO_CONTESTED = "Contested Territory"
L.ZONEINFO_DUNGEONS = "Dungeons"
L.ZONEINFO_DUNGEONS_DESC = "The dungeons and raids whose entrance is in the zone, with their level "
    .. "range colored against yours."
L.ZONEINFO_SIZE = "Size"
L.ZONEINFO_SIZE_DESC = "How big the panel is, compared with its normal size."
L.ZONEINFO_TITLE_LEVELS = "%s  %s" -- zone, its levels ("10-20")
L.ZONEINFO_RANGE = "%s-%s" -- lowest, highest
L.ZONEINFO_SKILL = "%s %s" -- profession, skill needed ("Fishing 55")
L.ZONEINFO_FISHING_NAME = "Fishing" -- until the client gives its own name
L.ZONEINFO_SKINNING_NAME = "Skinning"
L.ZONEINFO_LIST_SEPARATOR = ", "

-- UnexploredAreas
L.UNEXPLORED_TITLE = "Unexplored Areas"
L.UNEXPLORED_DESC = "Show the parts of zone maps you haven't explored yet, on the world map and "
    .. "the zone map."
L.UNEXPLORED_TINT = "Tint"
L.UNEXPLORED_TINT_DESC = "Tint unexplored areas so they stand apart from the ones you've "
    .. "explored. Off shows them just like explored areas."
L.UNEXPLORED_STRENGTH = "Tint Strength"
L.UNEXPLORED_STRENGTH_DESC = "How strong the tint is."
L.UNEXPLORED_COLOR = "Tint Color"
L.UNEXPLORED_COLOR_DESC = "The color of the tint."
L.UNEXPLORED_BLUE = "Blue"
L.UNEXPLORED_GRAY = "Gray"
L.UNEXPLORED_GOLD = "Gold"
L.UNEXPLORED_GREEN = "Green"
L.UNEXPLORED_RED = "Red"
L.UNEXPLORED_PURPLE = "Purple"

-- Coordinates
L.COORDS_TITLE = "Coordinates"
L.COORDS_DESC = "Show the world map's coordinates in its title bar instead of the bottom left "
    .. "corner: yours on the left, the cursor's on the right."
-- These three are Blizzard's own checkboxes, shown here too.
L.COORDS_PLAYER = "Player Coordinates"
L.COORDS_PLAYER_DESC = "Show where you are. This is Blizzard's Player Coordinates setting in its "
    .. "Interface options: changing it here changes it there too."
L.COORDS_CURSOR = "Cursor Coordinates"
L.COORDS_CURSOR_DESC = "Show where the cursor points on the map. This is Blizzard's Cursor "
    .. "Coordinates setting in its Interface options: changing it here changes it there too."
L.COORDS_TENTHS = "Tenths"
L.COORDS_TENTHS_DESC = "Show coordinates to a tenth, like 45.3, 62.8. This is Blizzard's setting "
    .. "in its Interface options: changing it here changes it there too."

-- HideFilterReset
L.HIDEFILTERRESET_TITLE = "Hide Filter Reset"
L.HIDEFILTERRESET_DESC = "Hide the reset button on the world map's filter dropdown, which shows "
    .. "whenever a filter is off."


-- FlightTimer
L.FLIGHTTIMER_TITLE = "Flight Timer"
L.FLIGHTTIMER_DESC = "Time every flight you take, then show how long a flight takes: a bar that "
    .. "counts it down as you fly, and the time on the flight map's tooltip."
L.FLIGHTTIMER_BAR = "Timer Bar"
L.FLIGHTTIMER_BAR_DESC = "A bar with the time left while you fly. Move and resize it in Edit Mode. A flight "
    .. "you haven't taken before counts up instead, and is timed for next time."
L.FLIGHTTIMER_TOOLTIP = "Flight Map Tooltip"
L.FLIGHTTIMER_TOOLTIP_DESC = "How long the flight takes, on a flight point's tooltip on the flight "
    .. "map, once you have flown it. Each route is timed on its own."
L.FLIGHTTIMER_TIME = "Flight Time:"
L.FLIGHTTIMER_TIME_LINE = "Flight Time: %s" -- a time like 2:05
L.FLIGHTTIMER_STYLE = "Tooltip Line"
L.FLIGHTTIMER_STYLE_DESC = "How the flight time looks on the tooltip."
L.FLIGHTTIMER_STYLE_DOUBLE = "Time at the Right"
L.FLIGHTTIMER_STYLE_LINE = "One Line"
L.FLIGHTTIMER_STYLE_GRAY = "One Gray Line"
L.FLIGHTTIMER_LANDING_SOUND = "Sound on Landing"
L.FLIGHTTIMER_LANDING_SOUND_DESC = "Play the ready check sound a few seconds before you land, so you "
    .. "can tab out on long flights. Only on a flight you have taken before. To hear it while "
    .. "tabbed out, turn on Sound in Background in the game's Audio settings."
L.FLIGHTTIMER_TEST = "Test Flight"
L.FLIGHTTIMER_TEST_BUTTON = "Fly"
L.FLIGHTTIMER_TEST_DESC = "Show the flight bar counting down a made-up 45 second flight, to see "
    .. "how it looks without a flight master. Nothing is learned from it."
L.FLIGHTTIMER_TEST_PLACE = "Ironforge, Dun Morogh" -- the made-up flight's destination
L.FLIGHTTIMER_RESET_TIMES = "Flight Times"
L.FLIGHTTIMER_RESET_TIMES_BUTTON = "Clear"
L.FLIGHTTIMER_RESET_TIMES_DESC = "Forget every flight time. They're timed again as you fly."
L.FLIGHTTIMER_RESET_TIMES_CONFIRM = "Forget every flight time Flight Timer has recorded?"
L.FLIGHTTIMER_RESET_TIMES_DONE = "Flight times cleared."

-- Waypoints
L.WAYPOINTS_TITLE = "Waypoints"
L.WAYPOINTS_DESC = "Put the game's map pin on a spot with /way, and follow it with an arrow on "
    .. "screen that turns toward it as you turn."
L.WAYPOINTS_WAY = "/way"
L.WAYPOINTS_WAY_DESC = "/way [zone] x y [note] puts the game's map pin on a spot and tracks it, in "
    .. "your zone or the one named, with the note under the arrow. /way share puts the pin's link "
    .. "in chat, and /way clear takes it away. Left to TomTom or another addon that already has "
    .. "/way."
L.WAYPOINTS_ARROW = "Waypoint Arrow"
L.WAYPOINTS_ARROW_DESC = "An arrow that points to your map pin, from /way or a click on the map, "
    .. "with how far it is. It goes away when you get there. Move and resize it in Edit Mode."
L.WAYPOINTS_QUEST = "Follow Selected Quest"
L.WAYPOINTS_QUEST_DESC = "While a quest is selected on the map, the arrow points to that quest "
    .. "instead of your map pin, and back to the pin when none is."
L.WAYPOINTS_QUEST_NAME = "Show Quest Name"
L.WAYPOINTS_QUEST_NAME_DESC = "Show the quest's name under the distance while the arrow points "
    .. "to a quest."
L.WAYPOINTS_QUEST_NAME_SAMPLE = "Quest Name" -- shown under the arrow in Edit Mode
L.WAYPOINTS_CORPSE = "Point to Corpse"
L.WAYPOINTS_CORPSE_DESC = "While you're a ghost, the arrow points to your corpse instead of a "
    .. "quest or your map pin, the same spot as the game's own tombstone marker, and goes back to "
    .. "them once you're alive."
L.WAYPOINTS_CORPSE_LABEL = "Your Corpse" -- shown under the arrow while it points to the corpse
L.WAYPOINTS_CLEAR_ON_ARRIVAL = "Clear Pin on Arrival"
L.WAYPOINTS_CLEAR_ON_ARRIVAL_DESC = "Takes your map pin away once you reach it. Quests and your "
    .. "corpse are left alone."
L.WAYPOINTS_USAGE = "/way [zone] x y [note], such as /way 45.2 67.8 or /way Elwynn Forest 45 67 "
    .. "Hogger. /way share puts the pin's link in chat, and /way clear takes the pin away."
L.WAYPOINTS_SET = "Waypoint set in %s at %.1f, %.1f." -- zone, x, y
L.WAYPOINTS_SET_NOTE = "Waypoint \"%s\" set in %s at %.1f, %.1f." -- the note typed, zone, x, y
L.WAYPOINTS_SHARE_NONE = "There's no map pin to share. Set one with /way or on the map."
L.WAYPOINTS_SHARE_UNAVAILABLE = "This client can't share map pins in chat."
L.WAYPOINTS_CLEARED = "Waypoint cleared."
L.WAYPOINTS_RANGE = "Coordinates go from 0 to 100."
L.WAYPOINTS_NO_ZONE = "No zone called %s." -- what was typed
L.WAYPOINTS_NO_MAP = "There's no map here. Name a zone: /way Elwynn Forest 45 67."
L.WAYPOINTS_NOT_HERE = "Can't put a waypoint on the %s map." -- zone
L.WAYPOINTS_UNAVAILABLE = "This client has no map waypoints."
L.WAYPOINTS_YARDS = "%s yds" -- a distance; the game's own words are used when it has them

-- MinimapNodeIcons
L.MINIMAPNODEICONS_TITLE = "Minimap Node Icons"
L.MINIMAPNODEICONS_DESC = "Put the herb's or ore's own icon on each tracking dot on the minimap "
    .. "while Find Herbs or Find Minerals is on. A node it doesn't know gets its icon once you "
    .. "gather it."
L.MINIMAPNODEICONS_SIZE = "Icon Size"
L.MINIMAPNODEICONS_SIZE_DESC = "How big the icons are on the minimap."
L.MINIMAPNODEICONS_BORDER = "Round Border"
L.MINIMAPNODEICONS_BORDER_DESC = "A gold ring around each icon, like the minimap's tracking button."
L.MINIMAPNODEICONS_LEVELS = "Gray Other Levels"
L.MINIMAPNODEICONS_LEVELS_DESC = "Show a node's icon in gray when the minimap does, as for a node "
    .. "above or below you, like in a cave."
L.MINIMAPNODEICONS_TINT = "Tint Unusable"
L.MINIMAPNODEICONS_TINT_DESC = "Tint a node's icon red while your skill is too low to gather it."
L.MINIMAPNODEICONS_GRAY = "Gray Out Trivial"
L.MINIMAPNODEICONS_GRAY_DESC = "Show a node's icon in gray once gathering it no longer raises your "
    .. "skill."
L.MINIMAPNODEICONS_DETAIL = "Scan Detail"
L.MINIMAPNODEICONS_DETAIL_DESC = "How closely the minimap is checked for dots. Higher finds dots "
    .. "that sit close together, but takes more of your computer's time."
L.MINIMAPNODEICONS_DETAIL_LOW = "Low"
L.MINIMAPNODEICONS_DETAIL_MEDIUM = "Medium"
L.MINIMAPNODEICONS_DETAIL_HIGH = "High"
L.MINIMAPNODEICONS_CHAT_DESC = "Say in chat when the game stops Minimap Node Icons from checking "
    .. "the minimap."
L.MINIMAPNODEICONS_FAILED = "Minimap Node Icons couldn't check the minimap: %s" -- error
-- The gray notice above the module's options (shown always; it has no button).
L.MINIMAPNODEICONS_NOTICE = "Not fully accurate, and uses more CPU than other modules."
L.MINIMAPNODEICONS_NOTICE_DESC = "The game lists its tracking dots nowhere an addon can read, so "
    .. "this module asks the minimap what is under many spots, several times a second. That "
    .. "takes more of your computer's time than other modules, and an icon can sit a little off "
    .. "its dot or go missing for a moment. Icons update only out of combat, while your cursor "
    .. "isn't on the minimap. This should improve over time with optimizations and changes."
-- Shown once it found the minimap no longer answers its probes, as since the game's patch of
-- November 7, 2026 (build 70862).
L.MINIMAPNODEICONS_BROKEN = "The game stopped answering this module's scans, so it can't find the dots."
L.MINIMAPNODEICONS_BROKEN_DESC = "Since the game's update of November 7, 2026, the minimap only says "
    .. "what's under your own mouse, so scanning it finds nothing and the module has stopped. It "
    .. "checks again after each /reload, so it starts working again by itself if a later update "
    .. "brings this back. Gathering Map still remembers what you gather and the dots you point at."
-- Its rows on the Profiler page, after "Minimap Node Icons: ".
L.MINIMAPNODEICONS_PART_VIEW = "reading your spot"
L.MINIMAPNODEICONS_PART_FOLLOW = "following dots"
L.MINIMAPNODEICONS_PART_FIND = "finding new dots"
L.MINIMAPNODEICONS_PART_ASK = "asking the game"
L.MINIMAPNODEICONS_PART_DRAW = "drawing icons"
L.MINIMAPNODEICONS_COMMAND = "Check what Minimap Node Icons sees on the minimap right now."
L.MINIMAPNODEICONS_HERE_START = "Point at a dot on the minimap; reading it in %d seconds." -- seconds
L.MINIMAPNODEICONS_HERE_NONE = "Nothing under the cursor. Point at a dot and try again."
-- name, cursor right and up of the minimap's center, zoom level
L.MINIMAPNODEICONS_HERE_CURSOR = "%s: cursor at %.1f, %.1f. Zoom %d."
L.MINIMAPNODEICONS_HERE_COLOR = "Name color: %s, %s, %s. Gray: %s." -- red, green, blue, yes/no
-- icon right and up of the minimap's center, then where the dot answered last
L.MINIMAPNODEICONS_HERE_ICON = "Its icon is at %.1f, %.1f; it last answered at %.1f, %.1f."
-- trail right and up, standing still (yes/no)
L.MINIMAPNODEICONS_HERE_LAG = "Trail while moving: %.1f, %.1f. Standing still: %s."
L.MINIMAPNODEICONS_HERE_MISSED = "No icon for it yet."
-- /fpp nodes probe: which ways of probing a spot still read the dot there.
L.MINIMAPNODEICONS_PROBE_START = "Point at a dot on the minimap and hold still; reading it in %d seconds." -- seconds
L.MINIMAPNODEICONS_PROBE_MOVE = "Got %s at %.0f, %.0f. Now move the mouse off the minimap; probing in %d seconds." -- name, x, y, seconds
L.MINIMAPNODEICONS_PROBE_API = "API: SetUsingSoftCursor %s, UpdateMouseoverAtPoint %s, UpdateBlips %s, GamePadEnable %s, scale %.2f." -- yes/no x3, CVar, scale
L.MINIMAPNODEICONS_PROBE_RESULT = "%s: %s" -- way, what it read
L.MINIMAPNODEICONS_PROBE_NOTHING = "nothing"
L.MINIMAPNODEICONS_PROBE_ERROR = "error: %s"
L.MINIMAPNODEICONS_PROBE_DONE = "Done. Paste these lines to the developer."
L.MINIMAPNODEICONS_PROBE_SOFT = "1 soft cursor, screen pixels, read now"
L.MINIMAPNODEICONS_PROBE_PLAIN = "2 no soft cursor, screen pixels, read now"
L.MINIMAPNODEICONS_PROBE_UNITS = "3 soft cursor, UI units, read now"
L.MINIMAPNODEICONS_PROBE_BLIPS = "4 soft cursor, after UpdateBlips, read now"
L.MINIMAPNODEICONS_PROBE_NEXT = "5 soft cursor kept on, read next frame"
L.MINIMAPNODEICONS_PROBE_LATER = "6 soft cursor kept on, read after 0.2 s"
L.MINIMAPNODEICONS_PROBE_HOVER = "7 soft cursor off, point left there, read after 0.2 s"
L.MINIMAPNODEICONS_REPORT_UNAVAILABLE = "This client can't check the minimap for nodes."
L.MINIMAPNODEICONS_REPORT_COMBAT = "Can't check the minimap in combat."
L.MINIMAPNODEICONS_REPORT_YES = "yes"
L.MINIMAPNODEICONS_REPORT_NO = "no"
-- tracking on (yes/no), position readable (yes/no), minimap width, minimap units per 100 yards
L.MINIMAPNODEICONS_REPORT_STATE = "Tracking on: %s. Position: %s. Minimap: %d wide, %s per 100 yards."
-- space name, names found, nodes known among them, the first few names
L.MINIMAPNODEICONS_REPORT_SPACE = "%s: %d names, %d nodes known: %s"
L.MINIMAPNODEICONS_REPORT_NONE = "none"
L.MINIMAPNODEICONS_REPORT_SAVED = "Using %s from now on." -- space name
L.MINIMAPNODEICONS_REPORT_NOTHING = "No node found. Stand near a herb or vein with tracking on, "
    .. "and keep the cursor off the minimap."
L.MINIMAPNODEICONS_CLEAR = "Learned Nodes"
L.MINIMAPNODEICONS_CLEAR_BUTTON = "Clear"
L.MINIMAPNODEICONS_CLEAR_DESC = "Forget the herbs and veins learned in game, with their icons "
    .. "and skills (Profession Tooltips uses them too). They're learned again as you see and "
    .. "gather them."
L.MINIMAPNODEICONS_CLEAR_CONFIRM = "Forget every herb and vein Forever++ has learned?"
L.MINIMAPNODEICONS_CLEAR_DONE = "Learned herbs and veins cleared."

-- GatheringMap
L.GATHERINGMAP_TITLE = "Gathering Map"
L.GATHERINGMAP_DESC = "Remember every herb and vein you gather, for all your characters, and show "
    .. "them on the world map and the minimap. Gathering one again moves its icon closer to where "
    .. "it really is."
L.GATHERINGMAP_ONLY_MINE = "Only My Professions"
L.GATHERINGMAP_ONLY_MINE_DESC = "Show herbs only on a character with Herbalism and ore only on one "
    .. "with Mining. Each character shows what it can gather, from the same nodes."
L.GATHERINGMAP_ONLY_TRACKING = "Only While Tracking"
L.GATHERINGMAP_ONLY_TRACKING_DESC = "Show herbs only while Find Herbs is on and ore only while Find "
    .. "Minerals is on. With Gathering Tracking swapping between the two, they come and go with it."
L.GATHERINGMAP_SIGHTINGS = "Remember Nodes Seen"
L.GATHERINGMAP_SIGHTINGS_DESC = "With Minimap Node Icons on, also remember the herbs and veins it "
    .. "finds on the minimap, so they show here before you gather them. Gathering them later counts "
    .. "them too."
L.GATHERINGMAP_FORGET_ZONE = "Nodes in This Zone"
L.GATHERINGMAP_FORGET_ALL = "All Nodes"
L.GATHERINGMAP_FORGET_BUTTON = "Forget"
L.GATHERINGMAP_FORGET_ZONE_DESC = "Forget every node remembered in the zone you're in, for all your "
    .. "characters. To forget one node, Shift+right-click its icon on the minimap or world map."
L.GATHERINGMAP_FORGET_ALL_DESC = "Forget every node remembered in every zone, for all your characters."
L.GATHERINGMAP_FORGET_ZONE_CONFIRM = "Forget every node remembered in the zone you're in?"
L.GATHERINGMAP_FORGET_ALL_CONFIRM = "Forget every node Gathering Map remembers, in every zone?"
L.GATHERINGMAP_FORGOT = "Forgot %d nodes." -- count
L.GATHERINGMAP_FORGOT_ONE = "Forgot %s." -- node name
L.GATHERINGMAP_FORGET_HINT = "Shift+right-click to forget it."
L.GATHERINGMAP_JUST = "Just Gathered"
L.GATHERINGMAP_JUST_DESC = "How a node you gathered lately shows while it's likely still gone: as "
    .. "an empty ring, its icon in gray, a small dot in its kind's color, not at all, or as usual."
L.GATHERINGMAP_JUST_RING = "Empty Ring"
L.GATHERINGMAP_JUST_GRAY = "Gray Icon"
L.GATHERINGMAP_JUST_DOT = "Small Dot"
L.GATHERINGMAP_JUST_HIDE = "Hidden"
L.GATHERINGMAP_JUST_SHOW = "As Usual"
L.GATHERINGMAP_JUST_MINUTES = "For"
L.GATHERINGMAP_JUST_MINUTES_DESC = "How long after you gather a node it shows that way."
L.GATHERINGMAP_NEAR = "Show Nodes As"
L.GATHERINGMAP_NEAR_DESC = "How remembered nodes show on the minimap. Only the game's own gold dot "
    .. "says whether a node is there right now, so an empty ring leaves room for it: the dot shows "
    .. "inside the ring when the node is up, and the ring is empty when it's gone. The game draws "
    .. "its dots out to about the minimap's edge, so rings everywhere work at any distance; or rings "
    .. "(or nothing) only near you, and the node's icon farther out."
L.GATHERINGMAP_NEAR_ALL = "Empty Rings"
L.GATHERINGMAP_NEAR_RING = "Empty Rings Near You"
L.GATHERINGMAP_NEAR_HIDE = "Hidden Near You"
L.GATHERINGMAP_NEAR_SHOW = "Icons"
L.GATHERINGMAP_NEAR_YARDS = "Within"
L.GATHERINGMAP_NEAR_YARDS_DESC = "How close a node is to count as near you; farther out it shows its icon."
L.GATHERINGMAP_YARDS = "%d yd" -- yards
L.GATHERINGMAP_NEAR_ALPHA_DESC = "How solid the empty rings are."
L.GATHERINGMAP_AWAY = "%d yards away" -- yards
L.GATHERINGMAP_NEAR_NOTE = "Remembered spot; the game's own dot shows whether it's there now."
L.GATHERINGMAP_TOOLTIPS = "Minimap Tooltips"
L.GATHERINGMAP_TOOLTIPS_DESC = "Show a node's tooltip when you point at its icon on the minimap."
L.GATHERINGMAP_JUST_ALPHA_DESC = "How solid a node you just gathered is, on top of the map's own opacity."
-- Smaller headers over its options in Settings
L.GATHERINGMAP_SECTION_LOOK = "Look"
L.GATHERINGMAP_SECTION_MINIMAP = "Minimap"
L.GATHERINGMAP_SECTION_WORLDMAP = "World Map"
L.GATHERINGMAP_ICON = "Icon Style"
L.GATHERINGMAP_ICON_DESC = "Show each node as the icon of what it gives, like Copper Ore for a Copper "
    .. "Vein, or as a circle in its kind's color: green for herbs, orange for ore. A node whose "
    .. "item isn't known yet is a circle either way."
L.GATHERINGMAP_ICON_ITEM = "Item Icon"
L.GATHERINGMAP_ICON_CIRCLE = "Circle"
L.GATHERINGMAP_SHAPE = "Icon Shape"
L.GATHERINGMAP_SHAPE_DESC = "Draw an item icon round, like the minimap's own, or square, like in your bags."
L.GATHERINGMAP_SHAPE_ROUND = "Round"
L.GATHERINGMAP_SHAPE_SQUARE = "Square"
L.GATHERINGMAP_RING = "Gold Ring"
L.GATHERINGMAP_RING_DESC = "Put the minimap's gold ring around each round icon."
L.GATHERINGMAP_MINIMAP = "Show on Minimap"
L.GATHERINGMAP_MINIMAP_DESC = "Show the nodes near you on the minimap."
L.GATHERINGMAP_WORLDMAP = "Show on World Map"
L.GATHERINGMAP_WORLDMAP_DESC = "Show the nodes of the zone the world map shows."
L.GATHERINGMAP_SIZE = "Icon Size"
L.GATHERINGMAP_MINIMAP_SIZE_DESC = "How big each icon is on the minimap."
L.GATHERINGMAP_MAP_SIZE_DESC = "How big each icon is on the world map, at any zoom."
L.GATHERINGMAP_ALPHA = "Opacity"
L.GATHERINGMAP_ALPHA_DESC = "How solid the icons are. Lower lets the map show through."
L.GATHERINGMAP_CONTINENTS = "Continent Maps"
L.GATHERINGMAP_CONTINENTS_DESC = "Also show every zone's nodes on its continent's map, smaller."
L.GATHERINGMAP_LOG = "Log Gathers"
L.GATHERINGMAP_LOG_DESC = "Print in chat each gather Gathering Map hears of: the node, what named "
    .. "it, the world object's ID, where you stood, and whether it was saved."
-- node, kind, what named it (target, softinteract, tooltip, none), object ID, where, result
L.GATHERINGMAP_LOG_LINE = "Gathering Map: %s (%s, from %s, object %s) at %s: %s"
-- Each step of hearing a gather, logged too
L.GATHERINGMAP_TRACE_CAST = "Gathering Map: cast %s at %s (gathers: %s)" -- spell and ID, target, kind or -
L.GATHERINGMAP_TRACE_SUCCESS = "Gathering Map: cast done, spell %s; the gather's: %s" -- spell ID, yes/no
L.GATHERINGMAP_TRACE_FAILED = "Gathering Map: the gather's cast failed, spell %s" -- spell ID
L.GATHERINGMAP_TRACE_LOOT = "Gathering Map: loot from %s, %s items, %s" -- source GUID, count, when
L.GATHERINGMAP_LOG_NEW = "a new node"
L.GATHERINGMAP_LOG_ONCE = "gathered once"
L.GATHERINGMAP_LOG_AGAIN = "gathered %d times" -- count, more than one
L.GATHERINGMAP_LOG_KIND = "not saved: not a kind it remembers"
L.GATHERINGMAP_LOG_UNNAMED = "not saved: nothing named it"
L.GATHERINGMAP_LOG_NOWHERE = "not saved: no spot on a map"
-- Kinds of node, the gold line under a node's name on the map
L.GATHERINGMAP_KIND_HERB = "Herb"
L.GATHERINGMAP_KIND_ORE = "Ore"
L.GATHERINGMAP_KIND_TREASURE = "Treasure"
L.GATHERINGMAP_KIND_FISH = "Fishing Pool"
-- A node's tooltip
L.GATHERINGMAP_GATHERED_ONCE = "Gathered once"
L.GATHERINGMAP_GATHERED = "Gathered %d times" -- count, more than one
L.GATHERINGMAP_LAST = "Last gathered %s" -- "3h ago"
L.GATHERINGMAP_SEEN = "Seen on the minimap, not gathered yet"
L.GATHERINGMAP_ALSO = "Also spawns %s (gathered %d)" -- another vein's name, its gathers here
