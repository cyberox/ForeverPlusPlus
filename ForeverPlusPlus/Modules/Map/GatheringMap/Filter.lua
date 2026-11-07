-- Gathering Map in the world map's filter menu (the funnel at its top right) and the minimap's
-- tracking menu (the magnifying glass): a Gathering Map title and a checkbox for Herbs, Ore,
-- Treasure, and Fishing Pools, after Blizzard's own. They're the same switches as the kinds'
-- checkboxes on the Gathering Map page, saved for each character. A kind this character doesn't
-- have the profession for, with Only My Professions on, isn't listed: it would show nothing.
local _, ns = ...

local ipairs = ipairs

local L = ns.L
local Professions = ns.Professions

local module = ns.modules.GatheringMap
local internal = module.internal

-- The kinds the menu lists, in order, with the skill line that gathers each. Anyone can open a
-- chest.
local KINDS = {
    { kind = "herb", name = L.GATHERINGMAP_PAGE_HERBS, line = Professions.HERBALISM },
    { kind = "ore", name = L.GATHERINGMAP_PAGE_ORE, line = Professions.MINING },
    { kind = "treasure", name = L.GATHERINGMAP_PAGE_TREASURE },
    { kind = "fish", name = L.GATHERINGMAP_PAGE_FISH, line = Professions.FISHING },
}

-- Blizzard's tags for the menus: the world map's filter (WorldMapTrackingOptionsButtonMixin:
-- SetupMenu, Blizzard_WorldMapTemplates.lua) and the minimap's tracking menu
-- (MiniMapTrackingButtonMixin:OnLoad, Blizzard_Minimap/Mainline/Minimap.lua; `forever` branch).
local WORLD_TAG, MINIMAP_TAG = "MENU_WORLD_MAP_TRACKING", "MENU_MINIMAP_TRACKING"

-- The entries for a menu, while the module and that map's icons (`mapKey`) are on.
local function entries(mapKey)
    return function(_, root)
        if not (module.enabled and module.db[mapKey]) then
            return
        end
        local db = module.db
        root:CreateDivider()
        root:CreateTitle(L.GATHERINGMAP_TITLE)
        for _, kind in ipairs(KINDS) do
            -- A kind this character can't gather isn't offered while Only My Professions hides it
            -- anyway; anyone opens chests.
            if not (db.onlyMine and kind.line) or Professions.Rank(kind.line) ~= nil then
                root:CreateCheckbox(kind.name, function()
                    return not db.hiddenKinds[kind.kind]
                end, function()
                    db.hiddenKinds[kind.kind] = not db.hiddenKinds[kind.kind] or nil
                    internal.Changed(nil)
                end)
            end
        end
    end
end

local added = false

---Adds the entries to the world map's filter and the minimap's tracking menu, once: Blizzard's
---menus can't take an addition back, so each checks whether the module is on when it opens.
---Probe: Menu.ModifyMenu is Mainline's.
function internal.EnableFilter()
    if added or not (Menu and Menu.ModifyMenu) then
        return
    end
    added = true
    Menu.ModifyMenu(WORLD_TAG, entries("worldMap"))
    Menu.ModifyMenu(MINIMAP_TAG, entries("minimap"))
end
