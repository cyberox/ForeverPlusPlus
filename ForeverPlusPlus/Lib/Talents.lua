-- The player's talent tabs and where their points are. Forever's talents are Classic trees on the
-- trait system: one CamelotCombat config with one tree, whose display groups are the tabs, and
-- C_Traits.GetGroupCurrencyInfo says what's spent in each (a tab with nothing spent is left out
-- of its answer). C_SpecializationInfo can't tell the tabs apart here: it names the class and
-- counts no points (docs/forever-api.md, Talents). Nothing is cached, so read on a change.
local _, ns = ...

local ipairs, type, sort = ipairs, type, table.sort
local C_ClassTalents, C_Traits = C_ClassTalents, C_Traits

local Talents = {}
ns.Talents = Talents

local readable = ns.IsReadable

-- The points spent in a display group, 0 when the game lists none.
local function spentIn(configID, groupID)
    local ok, result = pcall(C_Traits.GetGroupCurrencyInfo, configID, { groupID })
    local entry = ok and type(result) == "table" and result[1]
    local currency = entry and type(entry.currencyInfos) == "table" and entry.currencyInfos[1]
    local spent = currency and currency.spent
    return ns.IsNumber(spent) and spent or 0
end

---The player's talent tabs in order: `{ index, groupID, name, order, spent }` each, or nil
---while the client has no talent data yet (early at login, or a client without trait trees).
---@return table[]?
function Talents.Tabs()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits
        and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID
        and C_Traits.GetGroupCurrencyInfo) then
        return nil
    end
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetConfigInfo(configID)
    local trees = info and readable(info.treeIDs) and info.treeIDs
    local treeID = type(trees) == "table" and trees[1]
    if not treeID then
        return nil
    end
    local tabs = {}
    for _, group in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
        if type(group) == "table" and readable(group.groupID) then
            tabs[#tabs + 1] = {
                groupID = group.groupID,
                name = ns.IsText(group.displayName) and group.displayName or "",
                order = readable(group.orderIndex) and group.orderIndex or 0,
                spent = spentIn(configID, group.groupID),
            }
        end
    end
    if #tabs == 0 then
        return nil
    end
    sort(tabs, function(a, b)
        return a.order < b.order
    end)
    for i, tab in ipairs(tabs) do
        tab.index = i
    end
    return tabs
end

---The tab with the most points, and the points spent in all. The first tab in order wins a tie.
---Nil while there's no talent data.
---@return table? tab
---@return number total
function Talents.Dominant()
    local tabs = Talents.Tabs()
    if not tabs then
        return nil, 0
    end
    local best, total = nil, 0
    for _, tab in ipairs(tabs) do
        total = total + tab.spent
        if not best or tab.spent > best.spent then
            best = tab
        end
    end
    return best, total
end
