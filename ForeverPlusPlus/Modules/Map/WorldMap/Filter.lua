-- World Map in the world map's filter menu (the funnel at its top right), under the Forever++
-- title: a Points of Interest checkbox for the part, with a submenu of a checkbox for each kind of
-- icon (as every layer of icons has there), then the Unexplored Areas and Zone Info parts. Each is
-- the same switch as its option in Settings. Sizes, continent maps, and the rest stay in Settings,
-- to keep the menu short. Ley lines aren't here: most characters can't see them.
local _, ns = ...

local ipairs = ipairs

local L = ns.L

local module = ns.modules.WorldMap

-- Points of Interest's kinds, by their option keys: a list of keys is one checkbox for all of
-- them, on while any is. A key that's a dropdown (Capital Cities: ours, Blizzard's, or off) is on
-- while it isn't "off", and turning it on gives `on`.
local KINDS = {
    { name = L.POI_DUNGEONS, keys = { "dungeons" } },
    { name = L.POI_RAIDS, keys = { "raids" } },
    { name = L.POI_CAPITALS, keys = { "capitals" }, on = "ours" },
    { name = L.POI_FLIGHT, keys = { "flightMasters" } },
    { name = L.WORLDMAP_FILTER_TRAVEL, keys = { "ships", "zeppelins", "trams" } },
    { name = L.POI_SPIRIT, keys = { "spiritHealers" } },
}

-- The parts the menu turns on and off, by their checkbox keys.
local PARTS = {
    { name = L.UNEXPLORED_TITLE, key = "unexploredAreas" },
    { name = L.ZONEINFO_TITLE, key = "zoneInfo" },
}

local function anyOn(keys)
    for _, key in ipairs(keys) do
        local value = module.db[key]
        if value and value ~= "off" then
            return true
        end
    end
    return false
end

-- Through Core, as the Modules page sets options, so parts turn on and off and Settings follows.
for _, kind in ipairs(KINDS) do
    kind.get = function()
        return anyOn(kind.keys)
    end
    kind.set = function(on)
        for _, key in ipairs(kind.keys) do
            if kind.on then
                ns.SetOption(module.name, key, on and kind.on or "off")
            else
                ns.SetOption(module.name, key, on)
            end
        end
    end
end

local function addEntries(root)
    ns.WorldMap.FilterLayer(root, L.POI_TITLE, function()
        return ns.PartOn(module, "pointsOfInterest")
    end, function(on)
        ns.SetOption(module.name, "pointsOfInterest", on)
    end, KINDS)
    for _, part in ipairs(PARTS) do
        root:CreateCheckbox(part.name, function()
            return ns.PartOn(module, part.key)
        end, function()
            ns.SetOption(module.name, part.key, not ns.PartOn(module, part.key))
        end)
    end
end

-- First under the Forever++ title (Lib/WorldMap's AddFilter), while World Map is on.
ns.WorldMap.AddFilter(1, function()
    return module.enabled and true or false
end, addEntries)
