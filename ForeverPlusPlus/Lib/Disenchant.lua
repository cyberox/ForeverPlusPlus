-- What disenchanting an item gives: which items can be disenchanted, the materials it gives with
-- each one's chance and amount, and what that's worth on average at given prices. Pure rules, no
-- frames, so tests/run.lua checks them.
--
-- Which items can be disenchanted is the game's own: its brackets by quality, weapon or armor, and
-- item level, generated from the client's tables (Lib/DisenchantBrackets.lua). What a bracket
-- gives isn't in the client. The rows below are Classic Era 1.x's, written from general game
-- knowledge, UNVERIFIED on Forever, and kept only for brackets whose edges the tables confirm.
-- Every other bracket (and one whose row turns out wrong) gives what disenchanting showed in play,
-- learned for the account (Disenchant.Learn). A few items the game flags as not disenchantable
-- can't be told apart here (the flag isn't in item info).
local _, ns = ...

local ipairs, pairs, type, tonumber = ipairs, pairs, type, tonumber
local format, match, sort = string.format, string.match, table.sort

local GameData = ns.GameData

local Disenchant = {}
ns.Disenchant = Disenchant

-- Materials. Classic Era 1.x item IDs, written from general game knowledge, UNVERIFIED on
-- Forever; Self Test lists any the client doesn't have.
local function item(id, label)
    return GameData.Item(id, label)
end

local STRANGE_DUST = item(10940, "Strange Dust")
local SOUL_DUST = item(11083, "Soul Dust")
local VISION_DUST = item(11137, "Vision Dust")
local DREAM_DUST = item(11176, "Dream Dust")
local ILLUSION_DUST = item(16204, "Illusion Dust")
local LESSER_MAGIC = item(10938, "Lesser Magic Essence")
local GREATER_MAGIC = item(10939, "Greater Magic Essence")
local LESSER_ASTRAL = item(10998, "Lesser Astral Essence")
local GREATER_ASTRAL = item(11082, "Greater Astral Essence")
local LESSER_MYSTIC = item(11134, "Lesser Mystic Essence")
local GREATER_MYSTIC = item(11135, "Greater Mystic Essence")
local LESSER_NETHER = item(11174, "Lesser Nether Essence")
local GREATER_NETHER = item(11175, "Greater Nether Essence")
local LESSER_ETERNAL = item(16202, "Lesser Eternal Essence")
local GREATER_ETERNAL = item(16203, "Greater Eternal Essence")
local SMALL_GLIMMERING = item(10978, "Small Glimmering Shard")
local LARGE_GLIMMERING = item(11084, "Large Glimmering Shard")
local SMALL_GLOWING = item(11138, "Small Glowing Shard")
local LARGE_GLOWING = item(11139, "Large Glowing Shard")
local SMALL_RADIANT = item(11177, "Small Radiant Shard")
local LARGE_RADIANT = item(11178, "Large Radiant Shard")
local SMALL_BRILLIANT = item(14343, "Small Brilliant Shard")
local LARGE_BRILLIANT = item(14344, "Large Brilliant Shard")
local NEXUS_CRYSTAL = item(20725, "Nexus Crystal")

-- Enum.ItemQuality and Enum.ItemClass values, as numbers so the rules need no client.
local UNCOMMON, RARE, EPIC = 2, 3, 4
local WEAPON, ARMOR = 2, 4

-- The game's brackets: { quality, class, lowest item level, highest }.
local BRACKETS = ns.TableData and ns.TableData.disenchantBrackets or {}

-- Uncommon: { low, high, dust, essence, shard }, each { item, min, max }. Armor gives mostly dust,
-- weapons mostly essence; `chances` is { major, minor, shard } for the bracket. No row for 61-99,
-- which Forever's tables have and Classic had no such items for (the old row said 61-65).
local CHANCES = { 0.75, 0.20, 0.05 }
local UNCOMMON_ROWS = {
    { 5, 15, { STRANGE_DUST, 1, 2 }, { LESSER_MAGIC, 1, 2 }, nil, { 0.80, 0.20, 0 } },
    { 16, 20, { STRANGE_DUST, 2, 3 }, { GREATER_MAGIC, 1, 2 }, { SMALL_GLIMMERING, 1, 1 } },
    { 21, 25, { STRANGE_DUST, 4, 6 }, { LESSER_ASTRAL, 1, 2 }, { SMALL_GLIMMERING, 1, 1 },
        { 0.75, 0.15, 0.10 } },
    { 26, 30, { SOUL_DUST, 1, 2 }, { GREATER_ASTRAL, 1, 2 }, { LARGE_GLIMMERING, 1, 1 } },
    { 31, 35, { SOUL_DUST, 2, 5 }, { LESSER_MYSTIC, 1, 2 }, { SMALL_GLOWING, 1, 1 } },
    { 36, 40, { VISION_DUST, 1, 2 }, { GREATER_MYSTIC, 1, 2 }, { LARGE_GLOWING, 1, 1 } },
    { 41, 45, { VISION_DUST, 2, 5 }, { LESSER_NETHER, 1, 2 }, { SMALL_RADIANT, 1, 1 } },
    { 46, 50, { DREAM_DUST, 1, 2 }, { GREATER_NETHER, 1, 2 }, { LARGE_RADIANT, 1, 1 } },
    { 51, 55, { DREAM_DUST, 2, 5 }, { LESSER_ETERNAL, 1, 2 }, { SMALL_BRILLIANT, 1, 1 } },
    { 56, 60, { ILLUSION_DUST, 1, 2 }, { GREATER_ETERNAL, 1, 2 }, { LARGE_BRILLIANT, 1, 1 } },
}

-- Rare, weapons and armor alike: { low, high, outcomes }. The old 11-25 row is split at the
-- tables' edges (16-20, 21-25); their 5-15 starts lower than it did, so it's learned. So is 61-99
-- (the old row was 56-65).
local RARE_ROWS = {
    { 16, 20, { { SMALL_GLIMMERING, 1, 1, 1 } } },
    { 21, 25, { { SMALL_GLIMMERING, 1, 1, 1 } } },
    { 26, 30, { { LARGE_GLIMMERING, 1, 1, 1 } } },
    { 31, 35, { { SMALL_GLOWING, 1, 1, 1 } } },
    { 36, 40, { { LARGE_GLOWING, 1, 1, 1 } } },
    { 41, 45, { { SMALL_RADIANT, 1, 1, 1 } } },
    { 46, 50, { { LARGE_RADIANT, 1, 1, 1 } } },
    { 51, 55, { { SMALL_BRILLIANT, 1, 1, 1 } } },
    { 56, 60, { { LARGE_BRILLIANT, 0.995, 1, 1 }, { NEXUS_CRYSTAL, 0.005, 1, 1 } } },
}

-- Epic, weapons and armor alike. 61-99 is learned (the old row was 61-80).
local EPIC_ROWS = {
    { 40, 45, { { SMALL_RADIANT, 1, 2, 4 } } },
    { 46, 50, { { LARGE_RADIANT, 1, 2, 4 } } },
    { 51, 55, { { SMALL_BRILLIANT, 1, 2, 4 } } },
    { 56, 60, { { NEXUS_CRYSTAL, 1, 1, 1 } } },
}

-- What disenchanting showed, by bracket (Disenchant.Key): { n = disenchants counted, [material
-- item ID] = "times:min:max" }, how many of them gave it and the fewest and most it gave.
local learned = GameData.New("disenchant", {}, { label = "Disenchanting" })

---The game's bracket an item falls in: { quality, class (2 weapon, 4 armor), lowest item level,
---highest }, or nil when its quality and item level can't be disenchanted.
---@param quality number Enum.ItemQuality: 2 Uncommon, 3 Rare, 4 Epic
---@param itemLevel number
---@param isWeapon boolean
---@return table|nil
function Disenchant.Bracket(quality, itemLevel, isWeapon)
    if type(itemLevel) ~= "number" then
        return nil
    end
    local class = isWeapon and WEAPON or ARMOR
    for _, bracket in ipairs(BRACKETS) do
        if bracket[1] == quality and bracket[2] == class and itemLevel >= bracket[3]
            and itemLevel <= bracket[4] then
            return bracket
        end
    end
end

---A bracket's key in what's learned, such as "3:4:61".
---@param bracket table from Bracket
---@return string
function Disenchant.Key(bracket)
    return format("%d:%d:%d", bracket[1], bracket[2], bracket[3])
end

local function outcome(material, chance)
    return { item = material[1], chance = chance, min = material[2], max = material[3] }
end

-- The hand-kept row for exactly this bracket's edges, or nil.
local function handRow(rows, bracket)
    for _, entry in ipairs(rows) do
        if entry[1] == bracket[3] and entry[2] == bracket[4] then
            return entry
        end
    end
end

-- What the hand-kept rows say a bracket gives, or nil when they don't know it.
local function fromRows(bracket)
    local isWeapon = bracket[2] == WEAPON
    if bracket[1] == UNCOMMON then
        local entry = handRow(UNCOMMON_ROWS, bracket)
        if not entry then
            return nil
        end
        local chances = entry[6] or CHANCES
        local major, minor = entry[3], entry[4] -- armor: dust first
        if isWeapon then
            major, minor = minor, major
        end
        local list = { outcome(major, chances[1]), outcome(minor, chances[2]) }
        if entry[5] and chances[3] > 0 then
            list[3] = outcome(entry[5], chances[3])
        end
        return list
    end
    local entry = handRow(bracket[1] == RARE and RARE_ROWS or bracket[1] == EPIC and EPIC_ROWS or {}, bracket)
    if not entry then
        return nil
    end
    local list = {}
    for i, each in ipairs(entry[3]) do
        list[i] = { item = each[1], chance = each[2], min = each[3], max = each[4] }
    end
    return list
end

-- A learned tally's materials: item ID -> times, min, max.
local function parse(text)
    if type(text) ~= "string" then
        return nil
    end
    local times, low, high = match(text, "^(%d+):(%d+):(%d+)$")
    return tonumber(times), tonumber(low), tonumber(high)
end

-- What play showed a bracket gives, most often first, each with `seen` (how many disenchants it
-- comes from); nil before any.
local function fromPlay(bracket)
    local tally = learned:Get(Disenchant.Key(bracket))
    local n = type(tally) == "table" and tonumber(tally.n)
    if not n or n < 1 then
        return nil
    end
    local list = {}
    for id, text in pairs(tally) do
        local times, low, high = parse(text)
        if type(id) == "number" and times then
            list[#list + 1] = { item = id, chance = times / n, min = low, max = high, seen = n }
        end
    end
    if not list[1] then
        return nil
    end
    sort(list, function(a, b)
        if a.chance ~= b.chance then
            return a.chance > b.chance
        end
        return a.item < b.item
    end)
    return list
end

-- Whether play showed a material the rows don't give, which proves the rows wrong.
local function contradicts(rows, played)
    local known = {}
    for _, each in ipairs(rows) do
        known[each.item] = true
    end
    for _, each in ipairs(played) do
        if not known[each.item] then
            return true
        end
    end
    return false
end

---What disenchanting an item gives, most likely first: a list of { item, chance (0 to 1), min,
---max }, with `seen` on each when it's from play (how many disenchants it comes from). Nil when
---its quality and item level give nothing, or give something not known yet (see Bracket).
---@param quality number Enum.ItemQuality: 2 Uncommon, 3 Rare, 4 Epic
---@param itemLevel number
---@param isWeapon boolean
---@return table|nil
function Disenchant.Outcomes(quality, itemLevel, isWeapon)
    local bracket = Disenchant.Bracket(quality, itemLevel, isWeapon)
    if not bracket then
        return nil
    end
    local rows, played = fromRows(bracket), fromPlay(bracket)
    if rows and not (played and contradicts(rows, played)) then
        return rows
    end
    return played
end

---Whether an item can be disenchanted, from its item info: an Uncommon, Rare, or Epic weapon or
---armor piece, not a shirt or tabard, in one of the game's brackets. Can't see the flag a few
---items carry that stops it. Returns its outcomes (nil while they aren't known yet) and its
---bracket (nil when it can't be disenchanted).
---@param classID number
---@param quality number
---@param equipLoc string|nil such as "INVTYPE_BODY"
---@param itemLevel number
---@return table|nil outcomes
---@return table|nil bracket
function Disenchant.ForItem(classID, quality, equipLoc, itemLevel)
    if classID ~= WEAPON and classID ~= ARMOR then
        return nil
    end
    if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then
        return nil
    end
    local bracket = Disenchant.Bracket(quality, itemLevel, classID == WEAPON)
    if not bracket then
        return nil
    end
    return Disenchant.Outcomes(quality, itemLevel, classID == WEAPON), bracket
end

---Remembers what one disenchant of an item in `bracket` gave, for the account.
---@param bracket table from Bracket
---@param items table a list of { id = material item ID, count = how many }
---@return boolean changed whether it was counted
function Disenchant.Learn(bracket, items)
    if type(bracket) ~= "table" or type(items) ~= "table" or not items[1] then
        return false
    end
    local key = Disenchant.Key(bracket)
    local before = learned:Get(key)
    local tally = {}
    if type(before) == "table" then
        for k, v in pairs(before) do
            tally[k] = v
        end
    end
    -- One disenchant: a material's amounts added up, should it fill two slots.
    local got = {}
    for _, each in ipairs(items) do
        local id, count = each.id, each.count
        if type(id) ~= "number" or type(count) ~= "number" or count < 1 then
            return false
        end
        got[id] = (got[id] or 0) + count
    end
    tally.n = (tonumber(tally.n) or 0) + 1
    for id, count in pairs(got) do
        local times, low, high = parse(tally[id])
        if times then
            tally[id] = format("%d:%d:%d", times + 1, count < low and count or low,
                count > high and count or high)
        else
            tally[id] = format("%d:%d:%d", 1, count, count)
        end
    end
    learned:Learn(key, tally)
    return true
end

---What the outcomes are worth on average, in copper: each one's chance times its average amount
---times its price. `priceFn(itemID)` gives one item's price or nil. Also returns how many
---outcomes had no price; the total leaves them out.
---@param outcomes table from Outcomes
---@param priceFn fun(itemID: number): number|nil
---@return number total
---@return number missing
function Disenchant.Value(outcomes, priceFn)
    local total, missing = 0, 0
    for _, each in ipairs(outcomes) do
        local price = priceFn(each.item)
        if price then
            total = total + each.chance * (each.min + each.max) / 2 * price
        else
            missing = missing + 1
        end
    end
    return total, missing
end
