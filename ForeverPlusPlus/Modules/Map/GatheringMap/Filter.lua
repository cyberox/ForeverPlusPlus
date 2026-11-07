-- Gathering Map in the world map's filter menu (the funnel at its top right): a Gathering Map title
-- and a checkbox for Herbs, Ore, Treasure, and Fishing Pools, after Blizzard's own. They're the
-- same switches as the kinds' checkboxes on the Gathering Map page, saved for each character. A
-- kind this character
-- doesn't have the profession for, with Only My Professions on, is greyed out, its tooltip saying
-- why: checking it would show nothing.
local _, ns = ...

local ipairs = ipairs

local L = ns.L
local Professions = ns.Professions

local module = ns.modules.GatheringMap
local internal = module.internal

local KINDS = internal.KINDS -- the kinds the menu lists, in order, with the skill line of each

-- Blizzard's tag for the menu (WorldMapTrackingOptionsButtonMixin:SetupMenu,
-- Blizzard_WorldMapTemplates.lua: rootDescription:SetTag).
local TAG = "MENU_WORLD_MAP_TRACKING"

local function addEntries(_, root)
    if not (module.enabled and module.db.worldMap) then
        return
    end
    local db = module.db
    root:CreateDivider()
    root:CreateTitle(L.GATHERINGMAP_TITLE)
    for _, kind in ipairs(KINDS) do
        local box = root:CreateCheckbox(kind.name, function()
            return not db.hiddenKinds[kind.kind]
        end, function()
            db.hiddenKinds[kind.kind] = not db.hiddenKinds[kind.kind] or nil
            internal.Changed(nil)
        end)
        -- Greyed while Only My Professions hides it anyway, for a character without the skill.
        local usable = not (db.onlyMine and kind.line) or Professions.Rank(kind.line) ~= nil
        if not usable and box.SetEnabled then
            box:SetEnabled(false)
            if box.SetTooltip then
                box:SetTooltip(function(tooltip)
                    GameTooltip_SetTitle(tooltip, kind.name)
                    GameTooltip_AddNormalLine(tooltip, L.GATHERINGMAP_FILTER_NO_SKILL)
                end)
            end
        end
    end
end

local added = false

---Adds the entries to the world map's filter menu, once: Blizzard's menus can't take an addition
---back, so it checks whether the module is on each time the menu opens. Probe: Menu.ModifyMenu
---is Mainline's.
function internal.EnableFilter()
    if added or not (Menu and Menu.ModifyMenu) then
        return
    end
    added = true
    Menu.ModifyMenu(TAG, addEntries)
end
