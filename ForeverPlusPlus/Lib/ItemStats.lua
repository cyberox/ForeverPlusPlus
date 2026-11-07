-- An item's stats in short keys every module can share (STR, SP, HIT, DPS, ...), read from the
-- game's stat table (C_Item.GetItemStats, which on Forever carries the Equip: effects too, as the
-- Gear Probe showed on build 70425), with its slot, item level, and level requirement; and the
-- arithmetic of a stat weight score; and which stat a line of an item's tooltip is about. An item
-- the game hasn't cached yet gives nil and its ID, so the caller can look again at
-- GET_ITEM_INFO_RECEIVED. Nothing here reads frames.
local _, ns = ...

local _G, pairs, ipairs, type, sort, tonumber, pcall = _G, pairs, ipairs, type, table.sort, tonumber, pcall
local format, gmatch, match, lower, concat = string.format, string.gmatch, string.match, string.lower, table.concat
local floor, abs = math.floor, math.abs
local C_Item, UnitStat, UnitLevel = C_Item, UnitStat, UnitLevel

local ItemStats = {}
ns.ItemStats = ItemStats

-- The game's stat keys (C_Item.GetItemStats) and ours. Retail tells melee, ranged, and spell hit
-- and crit apart by key; Forever's strings say "Hit" and "Critical Strike" for one stat each
-- (Gear Probe, build 70425), and that one stat counts for spells too (NaowhForever PR #137, in
-- game), so the plain keys give both ours, and a set of weights prices each side. Spell Power
-- is "damage and healing" on Forever (a wand's "Increases damage and healing done by magical
-- spells and effects by up to 2" read as it, Gear Probe, build 70425), so it gives healing too.
-- A key that gives more than one of ours is a list. A key not here is remembered in `unknown`
-- for debugging.
ItemStats.KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "STR",
    ITEM_MOD_AGILITY_SHORT = "AGI",
    ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT",
    ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_HEALTH_SHORT = "HEALTH",
    ITEM_MOD_MANA_SHORT = "MANA",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = { "SP", "HEAL" },
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    ITEM_MOD_HIT_RATING_SHORT = { "HIT", "SPELLHIT" },
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT",
    ITEM_MOD_CRIT_RATING_SHORT = { "CRIT", "SPELLCRIT" },
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARMORPEN",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
    ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
    RESISTANCE0_NAME = "ARMOR",
    RESISTANCE2_NAME = "RES_FIRE",
    RESISTANCE3_NAME = "RES_NATURE",
    RESISTANCE4_NAME = "RES_FROST",
    RESISTANCE5_NAME = "RES_SHADOW",
    RESISTANCE6_NAME = "RES_ARCANE",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

-- Our keys in the order a page lists them. DPS_OFF and DPS_RANGED aren't stats an item has: a
-- weight set uses them for a weapon's DPS in the off hand and the ranged slot (see `Slotted`).
ItemStats.ORDER = {
    "STR", "AGI", "STA", "INT", "SPI", "HEALTH", "MANA",
    "AP", "RAP", "HIT", "CRIT", "HASTE", "EXPERTISE", "ARMORPEN",
    "SP", "HEAL", "SPELLHIT", "SPELLCRIT", "MP5", "HP5",
    "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE",
    "DPS", "DPS_OFF", "DPS_RANGED",
    "RES_FIRE", "RES_NATURE", "RES_FROST", "RES_SHADOW", "RES_ARCANE",
}

-- The keys whose weight is per 1% chance. Forever's gear carries them as ratings ("+4 Hit" is
-- 0.4%), so Normalize turns them into percent (see RATINGS).
ItemStats.PERCENT = {
    HIT = true, CRIT = true, HASTE = true, EXPERTISE = true, SPELLHIT = true, SPELLCRIT = true,
    DODGE = true, PARRY = true, BLOCK = true,
}

-- Ratings: our key, the game's combat rating it is (a CR_* global), and how many points of it
-- make 1% at level 60 when the client can't say: Forever's level 60 table as wowsims/forever PR
-- #571 and foreverdb.net/stats give it (hit 10, crit 14, haste 10, expertise 10, dodge 12,
-- parry 15, block 5), matching NaowhForever PR #137 (a ring with 4 hit showed 0.4% in game).
-- The client's own conversion wins whenever it answers. Defense isn't here: Forever's string
-- reads "Increases defense skill by %s", points of skill as in Classic.
local RATINGS = {
    HIT = { "CR_HIT_MELEE", 10 },
    SPELLHIT = { "CR_HIT_SPELL", 10 },
    CRIT = { "CR_CRIT_MELEE", 14 },
    SPELLCRIT = { "CR_CRIT_SPELL", 14 },
    HASTE = { "CR_HASTE_MELEE", 10 },
    EXPERTISE = { "CR_EXPERTISE", 10 },
    DODGE = { "CR_DODGE", 12 },
    PARRY = { "CR_PARRY", 15 },
    BLOCK = { "CR_BLOCK", 5 },
}

-- What one rating point gives in percent, asked of the client: the game's own conversion for a
-- value where it has one, else the player's rating and what it gives now.
local function clientRate(index)
    local fn = _G.GetCombatRatingBonusForCombatRatingValue
    if type(fn) == "function" then
        local ok, value = pcall(fn, index, 100)
        if ok and ns.IsNumber(value) and value > 0 then
            return value / 100
        end
    end
    local rating, bonus = _G.GetCombatRating, _G.GetCombatRatingBonus
    if type(rating) == "function" and type(bonus) == "function" then
        local okR, points = pcall(rating, index)
        local okB, given = pcall(bonus, index)
        if okR and okB and ns.IsNumber(points) and ns.IsNumber(given) and points > 0 and given > 0 then
            return given / points
        end
    end
    return nil
end

local ratingLevel, ratingRates -- the level the rates were read at, and our key -> per point

---What one rating point of each of our rating keys gives in percent, from the client where it
---answers and Forever's level 60 table otherwise, read again when the level changes.
---@return table rates our key -> per point
---@return table sources our key -> "client" or "seed"
function ItemStats.RatingRates()
    local level = UnitLevel and UnitLevel("player")
    if ratingRates and level == ratingLevel then
        return ratingRates, ratingRates.sources
    end
    ratingLevel, ratingRates = level, { sources = {} }
    for key, rating in pairs(RATINGS) do
        local index = _G[rating[1]]
        local rate = ns.IsNumber(index) and clientRate(index)
        ratingRates[key] = rate or 1 / rating[2]
        ratingRates.sources[key] = rate and "client" or "seed"
    end
    return ratingRates, ratingRates.sources
end

local unknown = {} -- a game key KEYS lacks -> true, once met

---The game's stat table in our keys, numbers only, ratings as percent; keys we don't know are
---remembered for `Unknown`. Two game keys that mean the same stat add up.
---@param raw table? C_Item.GetItemStats's table
---@return table stats our key -> value
function ItemStats.Normalize(raw)
    local stats = {}
    if type(raw) ~= "table" then
        return stats
    end
    local rates = ItemStats.RatingRates()
    local function add(ours, value)
        stats[ours] = (stats[ours] or 0) + value * (rates[ours] or 1)
    end
    for key, value in pairs(raw) do
        if ns.IsReadable(key) and ns.IsNumber(value) then
            local ours = ItemStats.KEYS[key]
            if type(ours) == "table" then
                for _, each in ipairs(ours) do
                    add(each, value)
                end
            elseif ours then
                add(ours, value)
            elseif type(key) == "string" then
                unknown[key] = true
            end
        end
    end
    return stats
end

---The game's stat keys met so far that aren't mapped, sorted, for debugging.
---@return string[]
function ItemStats.Unknown()
    local list = {}
    for key in pairs(unknown) do
        list[#list + 1] = key
    end
    sort(list)
    return list
end

-- Reading items ---------------------------------------------------------------------------------

local cache, cacheLevel = {}, nil -- link -> info, and the level it was read at (ratings change)

---What an item link is: `{ id, slot (INVTYPE_*, or ""), classID, subclassID, level, minLevel,
---stats }`, kept per link (which carries suffix and enchant). Nil while the game hasn't cached
---the item, with its ID as a second value so the caller can look again at GET_ITEM_INFO_RECEIVED
---(the data is asked for); nil alone for something that isn't an item.
---@param link string
---@return table? info
---@return number? itemID when the item isn't cached yet
function ItemStats.Get(link)
    if not ns.IsText(link, true) then
        return nil
    end
    local level = UnitLevel and UnitLevel("player")
    if level ~= cacheLevel then
        cache, cacheLevel = {}, level
    end
    local info = cache[link]
    if info then
        return info
    end
    if not (C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfo) then
        return nil
    end
    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not (ns.IsNumber(itemID)) then
        return nil
    end
    local name, _, _, level, minLevel = C_Item.GetItemInfo(link)
    if not ns.IsText(name, true) then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil, itemID
    end
    local raw = C_Item.GetItemStats and C_Item.GetItemStats(link)
    info = {
        id = itemID,
        slot = ns.IsText(equipLoc) and equipLoc or "",
        classID = ns.IsReadable(classID) and classID or nil,
        subclassID = ns.IsReadable(subclassID) and subclassID or nil,
        level = ns.IsNumber(level) and level or 0,
        minLevel = ns.IsNumber(minLevel) and minLevel or 0,
        stats = ItemStats.Normalize(ns.IsReadable(raw) and raw or nil),
    }
    cache[link] = info
    return info
end

-- Scoring ---------------------------------------------------------------------------------------

-- The weapon slots whose DPS a weight set prices apart from a main hand's.
local DPS_KEYS = {
    INVTYPE_WEAPONOFFHAND = "DPS_OFF",
    INVTYPE_RANGED = "DPS_RANGED",
    INVTYPE_RANGEDRIGHT = "DPS_RANGED",
    INVTYPE_THROWN = "DPS_RANGED",
}

---An item's stats with its DPS under the key its slot prices (DPS_OFF for an off-hand weapon,
---DPS_RANGED for a ranged one, DPS otherwise), so one weight set scores every weapon.
---@param stats table
---@param slot string INVTYPE_*
---@return table stats the same table when nothing changes
function ItemStats.Slotted(stats, slot)
    local key = DPS_KEYS[slot]
    if not (key and stats.DPS) then
        return stats
    end
    local copy = {}
    for k, v in pairs(stats) do
        copy[k] = v
    end
    copy[key] = copy.DPS
    copy.DPS = nil
    return copy
end

---A stat weight score: each stat times its weight, added up. A stat without a weight counts
---nothing.
---@param stats table our key -> value
---@param weights table our key -> weight
---@return number
function ItemStats.Score(stats, weights)
    local total = 0
    for key, value in pairs(stats) do
        local weight = weights[key]
        if weight and weight ~= 0 then
            total = total + value * weight
        end
    end
    return total
end

---Whether a score beats the score of what it would replace by more than `threshold` percent, and
---by how much. Against nothing (an empty slot, rival 0) anything with a score is an upgrade, and
---the percentage is nil, since there's nothing to be a percentage of.
---@param score number
---@param rival number
---@param threshold? number percent, 0 by default
---@return boolean upgrade
---@return number? percent
function ItemStats.Compare(score, rival, threshold)
    if rival <= 0 then
        return score > 0, nil
    end
    local percent = (score - rival) / rival * 100
    return percent > (threshold or 0), percent
end

-- Weight strings -----------------------------------------------------------------------------------
-- The Pawn-format string sims and gear sites publish weights in, and players paste between
-- addons: `( Pawn: v1: "Name": Class=Mage, Spec=Frost, Intellect=0.35, SpellPower=1, ... )`. A
-- public text format, read and written here in our own keys; nothing of that addon's is used.

-- Our keys and the string's stat names. Reading also takes the other names sims use for them.
local STRING_NAMES = {
    STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
    HEALTH = "Health", MANA = "Mana", AP = "Ap", RAP = "Rap", HIT = "HitRating", CRIT = "CritRating",
    HASTE = "HasteRating", EXPERTISE = "ExpertiseRating", ARMORPEN = "ArmorPenetration",
    SP = "SpellPower", HEAL = "Healing", SPELLHIT = "SpellHitRating", SPELLCRIT = "SpellCritRating",
    MP5 = "Mp5", HP5 = "Hp5", ARMOR = "Armor", DEF = "Defense", DODGE = "DodgeRating",
    PARRY = "ParryRating", BLOCK = "BlockRating", BLOCKVALUE = "BlockValue", DPS = "Dps",
    DPS_OFF = "OffHandDps", DPS_RANGED = "RangedDps", RES_FIRE = "FireResist",
    RES_NATURE = "NatureResist", RES_FROST = "FrostResist", RES_SHADOW = "ShadowResist",
    RES_ARCANE = "ArcaneResist",
}
local STRING_KEYS = {} -- a lowercased string name -> our key
for key, name in pairs(STRING_NAMES) do
    STRING_KEYS[lower(name)] = key
end
for name, key in pairs({ spelldamage = "SP", meleedps = "DPS", mainhanddps = "DPS", crit = "CRIT",
    hit = "HIT", spellcrit = "SPELLCRIT", spellhit = "SPELLHIT", haste = "HASTE", expertise = "EXPERTISE",
    dodge = "DODGE", parry = "PARRY", block = "BLOCK", attackpower = "AP", rangedattackpower = "RAP",
    healingpower = "HEAL", manaregen = "MP5", healthregen = "HP5", defenserating = "DEF",
    armorpenetrationrating = "ARMORPEN", bonusarmor = "ARMOR" }) do
    STRING_KEYS[name] = key
end

-- A weight as the string writes it: up to two decimals, no trailing zeros.
local function weightText(value)
    return ns.Text.Decimal(value, 2)
end

---A profile's weights as a Pawn-format string, stats in ItemStats.ORDER, zero weights left out.
---@param name string the scale's name
---@param class string the class token, such as "MAGE"
---@param spec string the tree's name
---@param weights table our key -> weight
---@return string
function ItemStats.WeightString(name, class, spec, weights)
    local parts = {}
    local className = lower(class or "")
    className = className:sub(1, 1):upper() .. className:sub(2)
    parts[#parts + 1] = "Class=" .. className
    parts[#parts + 1] = "Spec=" .. (spec or "")
    for _, key in ipairs(ItemStats.ORDER) do
        local weight = weights[key]
        if type(weight) == "number" and weight ~= 0 then
            parts[#parts + 1] = STRING_NAMES[key] .. "=" .. weightText(weight)
        end
    end
    local title = (name or ""):gsub('"', "")
    return format('( Pawn: v1: "%s": %s )', title, concat(parts, ", "))
end

---The weights in a Pawn-format string, in our keys, with the scale's name and the stat names
---we don't know (skipped). Nil and "format" when the text isn't such a string.
---@param text string
---@return table? weights our key -> weight
---@return string? nameOrReason the scale's name, or why it couldn't be read
---@return string[]? unknown the stat names skipped
function ItemStats.ParseWeightString(text)
    if type(text) ~= "string" then
        return nil, "format"
    end
    local name, body = match(text, '^%s*%(%s*[Pp][Aa][Ww][Nn]%s*:%s*[Vv]1%s*:%s*"([^"]*)"%s*:%s*(.-)%s*%)%s*$')
    if not body then
        return nil, "format"
    end
    local weights, unknown, any = {}, {}, false
    for pair in gmatch(body, "[^,]+") do
        local key, value = match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key then
            local lowered = lower(key)
            if lowered == "class" or lowered == "spec" then
                any = true
            else
                local ours = STRING_KEYS[lowered]
                local number = tonumber(value)
                if ours and number then
                    weights[ours] = number
                    any = true
                else
                    unknown[#unknown + 1] = key
                end
            end
        end
    end
    if not any then
        return nil, "format"
    end
    sort(unknown)
    return weights, name, unknown
end

-- The player's conversions ------------------------------------------------------------------------
-- What one point of an attribute gives this character, from the functions Forever's character
-- sheet writes its stat tooltips with (Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua):
-- attack power per Strength and Agility, crit and dodge per Agility, spell crit per Intellect,
-- health per Stamina, mana per Intellect. Read for the player only; nil where the client can't
-- say (an attribute of 0, a missing function, or a secret value).

-- A global function's number, or nil.
local function callNumber(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if ok and ns.IsNumber(value) then
        return value
    end
    return nil
end

-- The player's total of an attribute (1 Strength to 5 Spirit), or nil.
local function total(stat)
    if not UnitStat then
        return nil
    end
    local ok, _, value = pcall(UnitStat, "player", stat)
    if ok and ns.IsNumber(value) and value > 0 then
        return value
    end
    return nil
end

-- Per point: the game's answer for `amount` points, divided.
local function perPoint(name, stat, amount)
    local value = callNumber(name, stat, amount)
    return value and value / amount or nil
end

-- Percent per point: the game's chance (0 to 1) for all the player's points of a stat, as the
-- character sheet asks for it (`fn(stat, points)`, times 100), divided by them. `noArgs` for a
-- function that reads the player's own attribute itself (GetDodgeChanceFromAttribute()).
local function percentPerOwnPoint(name, stat, noArgs)
    local points = total(stat)
    if not points then
        return nil
    end
    local value
    if noArgs then
        value = callNumber(name)
    else
        value = callNumber(name, stat, points)
    end
    return value and value * 100 / points or nil
end

---What one point of each attribute gives this character now: `AP_STR`, `AP_AGI`, `RAP_AGI`,
---`CRIT_AGI` (percent), `DODGE_AGI` (percent), `SPELLCRIT_INT` (percent), `HEALTH_STA`,
---`MANA_INT`, `ARMOR_AGI`, `BLOCKVALUE_STR`. A rate the client can't give is left out.
---@return table rates
function ItemStats.PlayerRates()
    local rates = {}
    rates.AP_STR = perPoint("GetAttackPowerForStat", 1, 100)
    rates.AP_AGI = perPoint("GetAttackPowerForStat", 2, 100)
    rates.RAP_AGI = perPoint("GetRangedAttackPowerForStat", 2, 100)
    -- The character sheet calls these with the stat and its points and shows them times 100
    -- (Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua); called with the stat alone,
    -- the first two raise "bad argument #2" (Gear Probe, build 70425).
    rates.CRIT_AGI = percentPerOwnPoint("GetCritChanceFromStat", 2)
    rates.DODGE_AGI = percentPerOwnPoint("GetDodgeChanceFromAttribute", 2, true)
    rates.SPELLCRIT_INT = percentPerOwnPoint("GetSpellCritChanceFromStat", 4)
    rates.HEALTH_STA = callNumber("UnitHPPerStamina", "player")
    local manaPerInt = _G.MANA_PER_INTELLECT
    rates.MANA_INT = type(manaPerInt) == "number" and manaPerInt or nil
    rates.ARMOR_AGI = 2 -- the game's flat rule, as the character sheet's Agility tooltip says
    -- Strength's shield block value, as the sheet's Strength tooltip works it out.
    local perBlock = _G.BLOCK_VALUE_PER_STRENGTH
    rates.BLOCKVALUE_STR = type(perBlock) == "number" and perBlock > 0 and 1 / perBlock or nil
    return rates
end

local function round(value)
    return floor(value * 100 + 0.5) / 100
end

---The attribute weights that follow from a set of weights and the player's rates: Strength from
---attack power and block value, Agility from attack power, crit, dodge, and armor, Stamina from health, and
---Intellect from spell crit and mana. Spirit isn't derived: its regen counts only outside the
---five-second rule, which is a judgment, not a conversion. Only the attributes whose rates are
---all there are returned.
---@param weights table our key -> weight (the roots: AP, RAP, CRIT, DODGE, ARMOR, BLOCKVALUE, HEALTH, SPELLCRIT, MANA)
---@param rates table from ItemStats.PlayerRates
---@return table derived STR, AGI, STA, INT -> weight, for those that could be
function ItemStats.DeriveAttributes(weights, rates)
    local function w(key)
        return weights[key] or 0
    end
    local derived = {}
    if rates.AP_STR then
        derived.STR = round(rates.AP_STR * w("AP") + (rates.BLOCKVALUE_STR or 0) * w("BLOCKVALUE"))
    end
    if rates.AP_AGI and rates.CRIT_AGI and rates.DODGE_AGI then
        derived.AGI = round(rates.AP_AGI * w("AP") + (rates.RAP_AGI or 0) * w("RAP")
            + rates.CRIT_AGI * w("CRIT") + rates.DODGE_AGI * w("DODGE") + (rates.ARMOR_AGI or 0) * w("ARMOR"))
    end
    if rates.HEALTH_STA then
        derived.STA = round(rates.HEALTH_STA * w("HEALTH"))
    end
    if rates.SPELLCRIT_INT and rates.MANA_INT then
        derived.INT = round(rates.SPELLCRIT_INT * w("SPELLCRIT") + rates.MANA_INT * w("MANA"))
    end
    return derived
end

-- Tooltip lines ---------------------------------------------------------------------------------

-- Our key for a game key; a folded one (hit for melee and spells) gives its first.
local function ourKey(gameKey)
    local ours = ItemStats.KEYS[gameKey]
    if type(ours) == "table" then
        return ours[1]
    end
    return ours
end

-- Keys an Equip: line can carry. The five attributes, armor, and resistances always have a
-- "+6 Spirit" line of their own, so a number that matches one of them isn't the Equip: line's.
local EQUIP_KEYS = {
    AP = true, RAP = true, SP = true, HEAL = true, HIT = true, CRIT = true, HASTE = true,
    SPELLHIT = true, SPELLCRIT = true, MP5 = true, HP5 = true, EXPERTISE = true, ARMORPEN = true,
    DEF = true, DODGE = true, PARRY = true, BLOCK = true, BLOCKVALUE = true,
}

local linePatterns, lineNames -- { pattern, key } from the client's long strings; short name -> key

-- Built from the client's strings the first time a line is read, so they match in any language:
-- each short key's long string ("%c%s Spirit", "Increases your hit by %s.") as a pattern, and
-- each short name ("Spirit", "Fire Resistance") for a "+6 <name>" line no long string fits.
local function buildLinePatterns()
    linePatterns, lineNames = {}, {}
    for gameKey in pairs(ItemStats.KEYS) do
        local key = ourKey(gameKey)
        local long = _G[(gameKey:gsub("_SHORT$", ""))]
        if key ~= "DPS" and gameKey:find("_SHORT$") and type(long) == "string" then
            local pattern = ns.Text.FormatPattern((long:gsub("%%c", "\2")))
            pattern = "^" .. pattern:gsub("\2", "[%%+%%-]") .. "$"
            -- A string with a format we don't turn into a pattern (%.1f) would throw: skip it.
            if pcall(match, "", pattern) then
                linePatterns[#linePatterns + 1] = { pattern, key }
            end
        end
        local short = _G[gameKey]
        if key ~= "DPS" and type(short) == "string" and short ~= "" then
            lineNames[short] = key
        end
    end
    -- Longest first, so "Increases your hit by %s." can't win over a longer string it's part of.
    sort(linePatterns, function(a, b)
        return #a[1] > #b[1]
    end)
end

-- The one Equip: key among the item's stats whose value is a number in the line (raw, or as
-- percent for a rating), or nil when none or more than one is.
local function equipKeyByNumber(text, raw)
    if type(raw) ~= "table" then
        return nil
    end
    local numbers = {}
    for number in gmatch(text, "%d+%.?%d*") do
        numbers[#numbers + 1] = tonumber(number)
    end
    if #numbers == 0 then
        return nil
    end
    local rates = ItemStats.RatingRates()
    local found
    for gameKey, value in pairs(raw) do
        local key = ns.IsReadable(gameKey) and ns.IsNumber(value) and ourKey(gameKey)
        if key and EQUIP_KEYS[key] then
            local percent = rates[key] and value * rates[key]
            for _, number in ipairs(numbers) do
                if number == value or (percent and abs(number - percent) < 0.05) then
                    if found and found ~= key then
                        return nil
                    end
                    found = key
                end
            end
        end
    end
    return found
end

---Which stat a line of an item's tooltip is about, in our keys: "+6 Spirit" and the like by the
---client's own strings, and an Equip: line by those or, when its wording is a spell's ("Increases
---damage and healing done by magical spells and effects by up to 2."), by its number among the
---item's stats. Nil for any other line. The second value is the text after "Equip: " on an
---Equip: line.
---@param text string the line's text without escape codes (Text.Plain)
---@param raw table? the item's C_Item.GetItemStats table, for Equip: lines
---@return string? key
---@return string? effect
function ItemStats.LineStat(text, raw)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    if not linePatterns then
        buildLinePatterns()
    end
    local equip = _G.ITEM_SPELL_TRIGGER_ONEQUIP
    local effect
    if type(equip) == "string" and equip ~= "" and text:sub(1, #equip) == equip then
        effect = text:sub(#equip + 1):gsub("^%s+", "")
    end
    local body = effect or text
    for _, entry in ipairs(linePatterns) do
        if match(body, entry[1]) then
            return entry[2], effect
        end
    end
    if effect then
        local key = equipKeyByNumber(effect, raw)
        return key, key and effect or nil
    end
    local name = match(text, "^[%+%-]%d+%s+(.+)$")
    return name and lineNames[name] or nil
end
