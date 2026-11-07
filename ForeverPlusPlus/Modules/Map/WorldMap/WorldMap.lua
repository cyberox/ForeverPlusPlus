-- World Map: what Forever++ adds to the world map, in one module with a part for each: Points of
-- Interest, Zone Info, Unexplored Areas, and Coordinates. Each part is in its own file and has its
-- own checkbox heading its section in Settings; they share nothing but this module.
local _, ns = ...

local ipairs = ipairs

local L = ns.L

local module = ns.NewModule("WorldMap", L.WORLDMAP_DESC, {
    enabled = true,
})
module.title = L.WORLDMAP_TITLE
module.category = "map"
module.developer = { options = { zoneDungeons = "key", fishing = "key" } }
module.added = "0.8.0"
module.options = {}

-- Before 0.8.0 each part was a module of its own. World Map is on if any of them was, each part's
-- checkbox is its old module's, and its options and data (learned flight points, ley lines found,
-- the player's own coordinate settings) come along.
local MOVED = {
    { "PointsOfInterest", "pointsOfInterest", { "dungeons", "dungeonSize", "dungeonsWorld", "raids",
        "raidSize", "raidsWorld", "capitals", "capitalSize", "capitalsWorld", "flightMasters",
        "flightSize", "flightMastersWorld", "ships", "shipSize", "shipsWorld", "zeppelins",
        "zeppelinSize", "zeppelinsWorld", "spiritHealers", "spiritSize", "spiritHealersWorld",
        "otherFaction", "leyLines", "leyLineSize", "leyLinesWorld", "chat", "learnedNodes",
        "leyLineSpots" } },
    { "ZoneInfo", "zoneInfo", { "corner", "hover", "hideLabel", "levels", "faction",
        zoneDungeons = "dungeons", "detailKey", "fishing", "herbs", "ore", "skinning", "scale" } },
    { "UnexploredAreas", "unexploredAreas", { "tint", "tintStrength", "tintColor" } },
    { "Coordinates", "coordinates", { "player", "cursor", "tenths", "minimap", "titleBar", "saved" } },
}

ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local db
    for _, moved in ipairs(MOVED) do
        local name, toggle, keys = moved[1], moved[2], moved[3]
        local old = saved[name]
        if old then
            if not db then
                db = saved.WorldMap or {}
                saved.WorldMap = db
                db.enabled = false
            end
            ns.MoveSettings(old, db, keys)
            db[toggle] = old.enabled ~= false
            db.enabled = db.enabled or db[toggle]
            saved[name] = nil
        end
    end
end)

-- 0.8.4's Coordinates forced Blizzard's map coordinate CVars on and kept the player's own values
-- in `saved`. 0.9.0 dropped the key without putting them back, so do it here (after the step
-- above has moved `saved` into WorldMap).
ns.Migrate(1, function(db)
    local old = db.modules and db.modules.WorldMap
    if old and type(old.saved) == "table" then
        local saved = old.saved
        old.saved = nil
        ns.CVars.RestoreAll(saved)
    end
end)

-- Each part's own shared table, by its checkbox's key, for its Data.lua.
module.internal = {}
