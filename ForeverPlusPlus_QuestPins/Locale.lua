-- English text for Quest Pins, added to Forever++'s own through the plugin kit.
local L = {}

-- Quest Pins
L.QUESTPINS_TITLE = "Quest Pins"
L.QUESTPINS_DESC = "Put a pin on the world map for every quest you can pick up now, at the quest "
    .. "givers' places from the QuestieDB addon, and optionally for flight masters, innkeepers, "
    .. "trainers, and other townsfolk. Shift+click a pin to put the map pin there. Needs QuestieDB."
L.QUESTPINS_SECTION_GENERAL = "Quests"
L.QUESTPINS_SECTION_TOWNSFOLK = "Townsfolk"
L.QUESTPINS_SMALL = "Small Pins"
L.QUESTPINS_SMALL_DESC = "Draw the pins smaller."
L.QUESTPINS_ABOVE = "Levels Above You"
L.QUESTPINS_ABOVE_DESC = "Hide quests more than this many levels above you."
L.QUESTPINS_TOWN_DESC = "Pin friendly %s on the world map." -- the kind of NPC, lowercase
L.QUESTPINS_FLIGHT = "Flight Masters"
L.QUESTPINS_INN = "Innkeepers"
L.QUESTPINS_REPAIR = "Repair"
L.QUESTPINS_CLASS = "Class Trainers"
L.QUESTPINS_PROFESSION = "Profession Trainers"
L.QUESTPINS_BANKER = "Bankers"
L.QUESTPINS_STABLE = "Stable Masters"
L.QUESTPINS_MORE = "+%d more" -- how many more quests a pin has than its tooltip lists

ForeverPlusPlusAPI.v1.GetPluginKit().AddStrings(L)
