-- Talents: the player's talent tabs from the trait system (Forever's Classic trees: one config,
-- one tree, its display groups the tabs), in order with the points spent in each, and the
-- dominant tab. Upgrade Arrows picks its stat weights by that tab.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

game.secret = "<secret>"
local config = 7
local groups = {
    { groupID = 30, displayName = "Frost", orderIndex = 3 },
    { groupID = 10, displayName = "Arcane", orderIndex = 1 },
    { groupID = 20, displayName = "Fire", orderIndex = 2 },
    { groupID = "<secret>", displayName = "Hidden", orderIndex = 4 },
}
local spent = { [10] = 11, [20] = 0, [30] = 31 }
local broken = false
C_ClassTalents = { GetActiveConfigID = function() return config end }
C_Traits = {
    GetConfigInfo = function(id) return id == 7 and { treeIDs = { 900 } } or nil end,
    GetGroupDisplayInfoByTreeID = function(tree) return tree == 900 and groups or nil end,
    -- A tab with nothing spent isn't in the answer, and the call can error.
    GetGroupCurrencyInfo = function(_, ids)
        if broken then
            error("no data")
        end
        local points = spent[ids[1]]
        if not points or points == 0 then
            return {}
        end
        return { { currencyInfos = { { spent = points } } } }
    end,
}
T.load("Lib/Talents") -- it caches C_ClassTalents and C_Traits
local Talents = ns.Talents

local tabs = Talents.Tabs()
eq(tabs and #tabs, 3, "talents: a tab per display group, a secret one left out")
local names = {}
for i, tab in ipairs(tabs or {}) do
    names[i] = tab.index .. tab.name .. tab.spent
end
eq(table.concat(names, ","), "1Arcane11,2Fire0,3Frost31", "talents: in order, with the points in each")
local best, total = Talents.Dominant()
eq(best and best.name, "Frost", "talents: the tab with the most points")
eq(total, 42, "talents: and every point spent")

spent[30] = 11
eq((Talents.Dominant()).name, "Arcane", "talents: a tie goes to the first tab")
broken = true
best, total = Talents.Dominant()
eq(best and best.index == 1 and total, 0, "talents: a call that errors counts as nothing spent")
broken = false

config = 8 -- no config info yet, early at login
eq(Talents.Tabs(), nil, "talents: nothing before the client has the config")
best, total = Talents.Dominant()
eq(best == nil and total, 0, "talents: no dominant tab then")
config = 7
groups = {}
eq(Talents.Tabs(), nil, "talents: nothing for a tree without groups")
