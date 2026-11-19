-- Which items are new in Forever: ones Classic never had, from the game's own item table less
-- Classic's (Lib/Generated/NewItems.lua, runs of item IDs). An item changed from Classic's but
-- with the same ID isn't new here: only the ID is compared. Nothing here reads frames.
local _, ns = ...

local type, floor = type, math.floor

local NewItems = {}
ns.NewItems = NewItems

---Whether Classic never had this item. An ID above every one the game had when the list was
---made is new too, so a patch's items count before the list is made again.
---@param itemID number?
---@return boolean
function NewItems.Has(itemID)
    local data = ns.TableData
    local runs = data and data.newItems
    if type(itemID) ~= "number" or not runs then
        return false
    end
    if itemID > (data.newItemsHighest or itemID) then
        return true
    end
    -- The runs are pairs, first then last, in order: find the last run that starts at or before it.
    local low, high = 1, #runs / 2
    while low <= high do
        local middle = floor((low + high) / 2)
        if itemID < runs[middle * 2 - 1] then
            high = middle - 1
        elseif itemID > runs[middle * 2] then
            low = middle + 1
        else
            return true
        end
    end
    return false
end
