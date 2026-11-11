-- Durability: how worn the player's equipped items are, for Character Window's durability bars
-- and Durability Warning, and the plain decision of when a warning is due.
--
-- GetInventoryItemDurability is about the player's own gear, which isn't among the values the
-- client makes secret (unit health, auras, casts, cooldowns), but anything it returns is checked
-- with ns.IsNumber first, so a value that ever comes back secret counts as unknown instead of
-- breaking a comparison.
local _, ns = ...

local GetInventoryItemDurability = GetInventoryItemDurability

local Durability = {}
ns.Durability = Durability

-- The equipped item slots (INVSLOT_HEAD through INVSLOT_TABARD). Slots whose item has no
-- durability, or no item, answer nil and are skipped.
local FIRST_SLOT, LAST_SLOT = 1, 19

---How whole the item in an equipped slot is, from 0 (broken) to 1, or nil when the slot is empty,
---its item has no durability, or the client doesn't say.
---@param slot number an inventory slot id
---@return number?
function Durability.Fraction(slot)
    if not GetInventoryItemDurability then
        return nil
    end
    local current, maximum = GetInventoryItemDurability(slot)
    if not (ns.IsNumber(current) and ns.IsNumber(maximum)) or maximum <= 0 then
        return nil
    end
    return current / maximum
end

---The most worn equipped item: its fraction (0 to 1) and slot, or nil when nothing worn has
---durability.
---@return number? fraction
---@return number? slot
function Durability.Lowest()
    local lowest, lowestSlot
    for slot = FIRST_SLOT, LAST_SLOT do
        local fraction = Durability.Fraction(slot)
        if fraction and (not lowest or fraction < lowest) then
            lowest, lowestSlot = fraction, slot
        end
    end
    return lowest, lowestSlot
end

-- The warning levels, from least to most urgent.
local RANK = { ok = 0, low = 1, broken = 2 }

---The warning level of the most worn item: "broken" at 0 (when `broken` is true; otherwise it is
---only "low"), "low" below `threshold`, and "ok" above it or when nothing worn has durability.
---@param lowest number? the most worn item's fraction, from Durability.Lowest
---@param threshold number a fraction from 0 to 1
---@param broken boolean? whether a broken item is a level of its own
---@return string level "ok", "low", or "broken"
function Durability.Level(lowest, threshold, broken)
    if not lowest then
        return "ok"
    end
    if lowest <= 0 and broken then
        return "broken"
    end
    if lowest < threshold or lowest <= 0 then
        return "low"
    end
    return "ok"
end

---Whether going from level `last` to `now` should warn: only when it gets worse, so a warning
---comes once per drop below the threshold (and once more when something breaks), and again only
---after a repair has brought it back up. `last` nil is "ok".
---@param last string? the level last seen
---@param now string
---@return boolean
function Durability.ShouldWarn(last, now)
    return (RANK[now] or 0) > (RANK[last or "ok"] or 0)
end
