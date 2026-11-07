-- Macros' Smart Buff: one macro that casts the buff your friendly target (or you, with no friendly
-- target) should get from you, at the best rank you know that they can take. Each class has its
-- own buffs in the order it prefers them, and some go only to those who use mana (Arcane
-- Intellect, Blessing of Wisdom) or only to those who don't (Blessing of Might); for yourself,
-- a Paladin's or Druid's talent tree decides. With every buff that suits them on, they get one they
-- may not use, but never one that would replace one of yours. A buff they already have, from
-- anyone, is skipped unless it's about to run out or is someone else's lower rank, and so is one
-- whose stronger version they have (a Greater Blessing, Prayer of Fortitude, Arcane Brilliance,
-- Gift of the Wild). A Blessing is skipped when they have one of yours already,
-- since each Paladin's Blessings replace each other. When they can't get anything from you, it
-- buffs you instead; with nothing left for either, its buttons show a red X over your class's buff.
--
-- The macro is rewritten out of combat whenever the target, an aura, a rank, or the talents
-- change. In combat it can't be, and auras can't be read either: a new target there gets what the
-- macro last held, and when that's the wrong buff for them, the buttons show a warning and the
-- game's red error text says so.
local _, ns = ...

local ipairs, pairs, format, huge = ipairs, pairs, string.format, math.huge
local sort, concat = table.sort, table.concat
local tonumber, tostring, min = tonumber, tostring, math.min
local UnitClass, UnitLevel, UnitExists, UnitCanAssist = UnitClass, UnitLevel, UnitExists, UnitCanAssist
local UnitIsDeadOrGhost, UnitIsUnit, InCombatLockdown = UnitIsDeadOrGhost, UnitIsUnit, InCombatLockdown
local UnitName, CreateFrame = UnitName, CreateFrame
local GetTime, C_Spell = GetTime, C_Spell
local UnitPowerType, Enum = UnitPowerType, Enum

local L = ns.L
local Frames, Spellbook, Talents = ns.Frames, ns.Spellbook, ns.Talents
local readable, isTrue = ns.IsReadable, ns.IsTrue

local macros = ns.modules.Macros
local internal = macros.internal
local module = macros:NewPart({
    key = "smartBuff", name = L.MACROS_SMARTBUFF, description = L.MACROS_SMARTBUFF_DESC,
    section = L.MACROS_SMARTBUFF,
}, {
    smartBuff = true,
    smartBuffRecast = 50, -- percent of a buff's full length left below which it counts as missing
})

module:AddOptions({
    {
        key = "smartBuffRecast", name = L.MACROS_SMARTBUFF_RECAST,
        description = L.MACROS_SMARTBUFF_RECAST_DESC,
        min = 0, max = 90, step = 5,
        format = function(value) return L.MACROS_SMARTBUFF_RECAST_FORMAT:format(value) end,
    },
})

local NAME = L.MACROS_SMARTBUFF_MACRO -- the macro's name, at most 16 letters
local BUTTON_NAME = "ForeverPlusPlusSmartBuffButton" -- a global name, since /click needs one
local DELAY = 0.1 -- seconds to wait for a burst of changes to settle

-- Each buff's first rank (build 70374, Classic's IDs); the spellbook gives the rest by name. Made
-- only so Self Test checks the client still has them.
ns.GameData.New("smartBuffSpells", {
    [19740] = "Blessing of Might",
    [19742] = "Blessing of Wisdom",
    [20217] = "Blessing of Kings",
    [1243] = "Power Word: Fortitude",
    [14752] = "Divine Spirit",
    [588] = "Inner Fire",
    [1459] = "Arcane Intellect",
    [7302] = "Ice Armor",
    [168] = "Frost Armor",
    [1126] = "Mark of the Wild",
    [467] = "Thorns",
    [16864] = "Omen of Clarity",
    [706] = "Demon Armor",
    [687] = "Demon Skin",
    [324] = "Lightning Shield",
    [6673] = "Battle Shout",
    [19506] = "Trueshot Aura",
    -- Stronger versions that count as having the buff (Classic's IDs, first rank).
    [25782] = "Greater Blessing of Might",
    [25894] = "Greater Blessing of Wisdom",
    [25898] = "Greater Blessing of Kings",
    [21562] = "Prayer of Fortitude",
    [27681] = "Prayer of Spirit",
    [23028] = "Arcane Brilliance",
    [21849] = "Gift of the Wild",
}, { kind = "spell", label = L.MACROS_SMARTBUFF })

-- The level of buffs the game doesn't give a learned level for, since a talent isn't learned from a
-- trainer (Classic's spell levels; Forever refused Kings on a level 7 on 2026-10-20). A buff
-- can go on someone up to 10 levels below it.
local LEVELS = ns.GameData.New("smartBuffLevels", {
    [20217] = 20, -- Blessing of Kings
}, { kind = "spell", label = L.MACROS_SMARTBUFF })

-- Each class's buffs, the one it prefers first. `who` is who can get it: "any", "mana" (those who
-- use mana), "physical" (those who don't, or a Paladin or Druid of a melee tree), or "self". Of a
-- `group`, a unit holds one from each caster: a Paladin's Blessings, a Mage's or Warlock's armor.
-- `stronger` are buffs that count as having it: its group version, from anyone.
local BUFFS = {
    PALADIN = {
        -- Kings first: 10% of every stat beats Might or Wisdom once it's learned.
        { id = 20217, who = "any", group = "blessing", stronger = { 25898 } },
        { id = 19740, who = "physical", group = "blessing", stronger = { 25782 } },
        { id = 19742, who = "mana", group = "blessing", stronger = { 25894 } },
    },
    PRIEST = {
        { id = 1243, who = "any", stronger = { 21562 } },
        { id = 14752, who = "mana", stronger = { 27681 } },
        { id = 588, who = "self" },
    },
    MAGE = {
        { id = 1459, who = "mana", stronger = { 23028 } },
        { id = 7302, who = "self", group = "armor" },
        { id = 168, who = "self", group = "armor" },
    },
    DRUID = {
        { id = 1126, who = "any", stronger = { 21849 } },
        { id = 467, who = "physical" },
        { id = 16864, who = "self" },
    },
    WARLOCK = {
        { id = 706, who = "self", group = "armor" },
        { id = 687, who = "self", group = "armor" },
    },
    SHAMAN = { { id = 324, who = "self" } },
    WARRIOR = { { id = 6673, who = "self" } },
    HUNTER = { { id = 19506, who = "self" } },
}

-- Classes that don't use mana; anyone else gets the mana buffs.
local PHYSICAL = { WARRIOR = true, ROGUE = true }
-- For yourself, the talent trees that make a hybrid physical, and what an untalented one is.
local OWN_TREES = {
    PALADIN = { physical = { [2] = true, [3] = true }, untalented = "physical" },
    DRUID = { physical = { [2] = true }, untalented = "mana" },
}

local playerClass
local ranks -- spell name -> its known ranks (Lib/Spellbook.lua), or nil until read
local incomplete = false
local written -- what the macro holds: { target = cast or false, self = cast or false }
local lastBody -- the text refresh last wrote, so our own edit's UPDATE_MACROS is let pass
local checkTimer = Frames.Timer(module)
local button -- ours, clicked by the macro (explain)

local function classOf(unit)
    local _, class = UnitClass(unit)
    return readable(class) and class or nil
end

local function nameOf(id)
    local name = C_Spell.GetSpellName(id)
    return ns.IsText(name, true) and name or nil
end

local function spellName(entry)
    return nameOf(entry.id)
end

-- Whether the class has buffs for others, so the macro aims at a friendly target at all.
local function givesOthers()
    for _, entry in ipairs(BUFFS[playerClass] or {}) do
        if entry.who ~= "self" then
            return true
        end
    end
    return false
end

-- Whether the unit uses mana, by its class.
local function usesMana(unit, isSelf)
    local class = isSelf and playerClass or classOf(unit)
    if class then
        return not PHYSICAL[class]
    end
    -- A class we can't read (secret, mostly in combat): its power type, and no mana buffs without it.
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local power = UnitPowerType(unit)
    return readable(power) and power == mana or false
end

-- "physical" or "mana": what kind of buffs the unit wants. For yourself as a hybrid, your talents.
local function kindOf(unit, isSelf)
    local trees = isSelf and OWN_TREES[playerClass]
    if trees then
        local tab, total = Talents.Dominant()
        if not tab or total == 0 then
            return trees.untalented
        end
        return trees.physical[tab.index] and "physical" or "mana"
    end
    return usesMana(unit, isSelf) and "mana" or "physical"
end

local function fits(entry, kind, isSelf)
    if entry.who == "self" then
        return isSelf
    end
    return entry.who == "any" or entry.who == kind
end

-- The unit's buffs by name: { mine = cast by you, left = seconds left or huge, length = its full
-- length or 0, rank = its rank or nil }. Nil while auras can't be read (in combat, mostly), so
-- nothing counts as there.
local function aurasOf(unit)
    if not ns.AurasReadable() then
        return nil
    end
    local found, now = {}, GetTime()
    local listed = ns.EachAura(unit, "HELPFUL", function(aura)
        local name, expires, source = aura.name, aura.expirationTime, aura.sourceUnit
        if ns.IsText(name, true) then
            local left = readable(expires) and tonumber(expires) or 0
            local length = readable(aura.duration) and tonumber(aura.duration) or 0
            local id = aura.spellId
            found[name] = {
                rank = readable(id) and id and Spellbook.Rank(id) or nil,
                -- Only your own cast: isFromPlayerOrPlayerPet is true for any player's, not just yours.
                mine = ns.IsText(source, true) and isTrue(UnitIsUnit(source, "player")),
                left = left > 0 and left - now or huge,
                length = length,
            }
        end
    end)
    return listed and found or nil
end

-- The level a rank is learned at, or nil when neither the game nor LEVELS says.
local function spellLevel(id)
    local learned = Spellbook.LevelLearned(id)
    if learned and learned > 0 then
        return learned
    end
    return LEVELS:Get(id)
end

-- The best rank of `name` you know the unit can take ({ id, rank, subtext }): a buff's rank can go
-- on someone up to 10 levels below the level it's learned at. Nil, "low" when every rank is too
-- high for them, so another buff goes first instead of one the game refuses.
local function bestRank(name, unit)
    local list = ranks and ranks[name]
    if not (list and #list > 0) then
        return nil
    end
    local level = UnitLevel(unit)
    level = readable(level) and tonumber(level) or 0
    if level <= 0 then
        return list[#list] -- a level we can't read: the best, and the game says if it's too high
    end
    for i = #list, 1, -1 do
        local learned = spellLevel(list[i].id)
        if not learned or learned - 10 <= level then
            return list[i]
        end
    end
    return nil, "low"
end

-- The macro text that casts that rank. A spell without ranks (Blessing of Kings) is cast by its
-- name alone: its subtext, if any, isn't a rank /cast understands.
local function castText(name, unit)
    local best = bestRank(name, unit)
    if not best then
        return nil
    end
    if best.rank > 0 and best.subtext ~= "" then
        return format("%s(%s)", name, best.subtext)
    end
    return name
end

-- What the unit should get from you: the macro text that casts it, or nil when there's nothing
-- left to give. With `auras`, buffs they have are skipped; the second result is when the soonest
-- of those runs low (seconds from now), to look again then.
local function pick(unit, isSelf, auras, trace)
    local list = BUFFS[playerClass]
    if not list then
        return nil
    end
    local kind = kindOf(unit, isSelf)
    local percent = (module.db.smartBuffRecast or 0) / 100
    local soonest = huge
    local function live(aura)
        -- A share of the buff's own length, so one setting fits 5 and 30 minute buffs alike; one
        -- without a length never runs low.
        local margin = aura and aura.length > 0 and aura.length * percent or 0
        if aura and aura.left > margin then
            soonest = min(soonest, aura.left - margin)
            return aura
        end
        return nil
    end
    -- The unit's aura that counts as the entry's buff, and its name: the buff itself by its exact
    -- name, unless someone else's lower rank (yours goes over it), or a stronger version from
    -- anyone (a Greater Blessing, a Prayer).
    local function has(entry)
        local name = spellName(entry)
        if not (name and auras) then
            return nil
        end
        local aura = auras[name]
        if aura and not aura.mine and aura.rank then
            local best = bestRank(name, unit)
            if best and best.rank > aura.rank then
                aura = nil
            end
        end
        if live(aura) then
            return aura, name
        end
        for _, id in ipairs(entry.stronger or {}) do
            local stronger = nameOf(id)
            if stronger and live(auras[stronger]) then
                return auras[stronger], stronger
            end
        end
        return nil
    end
    -- A group the unit has one of yours from (a Greater Blessing too) is full: another would
    -- replace it. Unless yours doesn't suit them (Might on a caster): then one that does goes over it.
    local full = {}
    for _, entry in ipairs(list) do
        if entry.group then
            local aura, matched = has(entry)
            if aura and aura.mine then
                full[entry.group] = { name = matched, suits = fits(entry, kind, isSelf) }
            end
        end
    end
    -- The buffs that suit them first. Nothing that suits them: a buff they may not use, but never
    -- one that would replace one of yours (a full group), and never a mana buff for someone
    -- without mana. A caster with Wisdom from another Paladin gets your Might; a Rogue never gets
    -- Wisdom.
    local mana = usesMana(unit, isSelf)
    local cast, blocked -- what to cast, or the first buff that suits them they already have
    for pass = 1, 2 do
        for _, entry in ipairs(list) do
            local suits = fits(entry, kind, isSelf)
            local wanted = pass == 1 and suits or pass == 2 and not suits and entry.who ~= "self"
                and (entry.who ~= "mana" or mana)
            local name = wanted and spellName(entry)
            if name then
                local _, matched = has(entry)
                local held = entry.group and full[entry.group]
                if held and (pass == 2 or held.suits) then
                    matched = matched or held.name
                end
                if not matched then
                    cast = castText(name, unit)
                elseif pass == 1 then
                    blocked = blocked or matched
                end
            end
            if cast then
                break
            end
        end
        if cast then
            break
        end
    end
    if trace then
        trace.kind, trace.mana, trace.full, trace.cast = kind, mana, full, cast
        for _, entry in ipairs(list) do
            local name = spellName(entry)
            local aura, matched = has(entry)
            local best, low
            if name then
                best, low = bestRank(name, unit)
            end
            trace[#trace + 1] = { name = name or tostring(entry.id), rank = best and best.rank,
                low = low, matched = matched, mine = aura and aura.mine, suits = fits(entry, kind, isSelf) }
        end
    end
    return cast, soonest, blocked
end

-- Whether the target is someone the macro buffs: a friendly unit other than you, alive.
local function friendlyTarget()
    -- Unit identity can be secret; unknown counts as you, so the macro buffs you (its fallback).
    return UnitExists("target") and not ns.IsTrueOrSecret(UnitIsUnit("target", "player"))
        and isTrue(UnitCanAssist("player", "target")) and not isTrue(UnitIsDeadOrGhost("target"))
end

-- Your class's first buff you know, for the macro's icon when it has nothing to cast: the button
-- keeps that buff's icon under its red X instead of a question mark.
local function iconSpell()
    for _, entry in ipairs(BUFFS[playerClass] or {}) do
        local name = spellName(entry)
        if name and ranks and ranks[name] then
            return name
        end
    end
    return nil
end

-- The macro: the target's buff on a friendly target that can get one, else yours on you. Each
-- press clicks our button first, which says on screen why it can't buff them.
local function body(target, own)
    local click = "\n/click " .. BUTTON_NAME
    if target then
        return format("#showtooltip%s\n/cast [@target,help,nodead] %s%s", click, target,
            own and format("; [@player] %s", own) or "")
    end
    if own then
        return format("#showtooltip%s\n/cast [@player] %s", click, own)
    end
    local icon = iconSpell()
    return (icon and format("#showtooltip %s", icon) or "#showtooltip") .. click
end

-- Says on screen why the macro can't buff your target (or you), when it's pressed.
local function explain()
    if not module.enabled then
        return
    end
    local own = written and written.self
    -- Only a friendly, living target is someone to buff. An enemy, a dead one, or none: the macro
    -- buffs you, so it says something only when you have everything.
    if givesOthers() and friendlyTarget() then
        local auras = aurasOf("target") -- nil in combat: then only "can't use them" is known
        local cast, _, blocked = pick("target", false, auras)
        if cast then
            return -- it buffs them
        end
        local name = UnitName("target")
        name = ns.IsText(name, true) and name or L.MACROS_SMARTBUFF_TARGET
        if blocked then -- the buff that suits them most, already on them
            local text = own and L.MACROS_SMARTBUFF_HAS_SELF or L.MACROS_SMARTBUFF_HAS
            Frames.ErrorMessage(format(text, name, blocked))
            return
        end
        local text
        if pick("target", false, nil) then -- what they'd get if they had none of your buffs
            text = own and L.MACROS_SMARTBUFF_HAS_ALL_SELF or L.MACROS_SMARTBUFF_HAS_ALL
        else
            text = own and L.MACROS_SMARTBUFF_CANT_SELF or L.MACROS_SMARTBUFF_CANT
        end
        Frames.ErrorMessage(format(text, name))
    elseif not own then
        Frames.ErrorMessage(L.MACROS_SMARTBUFF_NOTHING)
    end
end

local refresh

local function lookAgain(seconds)
    if seconds < huge then
        checkTimer:Start(seconds + 0.5, function() refresh() end)
    else
        checkTimer:Cancel()
    end
end

-- In combat: the macro can't change, so say when it now casts the wrong thing.
-- Only on a target change: auras can't be read, so a check for the same target would wrongly
-- count the buffs it already has as missing.
local function checkInCombat()
    if not written then
        return
    end
    local state
    if givesOthers() and friendlyTarget() then
        -- The macro casts its target buff on whoever is targeted now, or yours on you without one,
        -- so only a wrong buff for them is stale.
        local should = pick("target", false, nil)
        if should and should ~= (written.target or nil) then
            state = "stale"
            Frames.ErrorMessage(L.MACROS_SMARTBUFF_STALE)
        end
    end
    if not state and not written.target and not written.self then
        state = "none"
    end
    internal.Mark(NAME, state)
end

function refresh(targetChanged)
    if not module.enabled or not playerClass then
        return
    end
    if InCombatLockdown() then
        if targetChanged then
            checkInCombat()
        end
        return
    end
    if not internal.Ready() then
        return
    end
    if not ranks then
        local complete
        ranks, complete = Spellbook.Ranks()
        incomplete = not complete
    end
    local target, soonTarget = nil, huge
    if givesOthers() and friendlyTarget() then
        target, soonTarget = pick("target", false, aurasOf("target"))
    end
    local own, soonOwn = pick("player", true, aurasOf("player"))
    local text = body(target, own)
    if internal.Write(NAME, text) then
        lastBody = text
        written = { target = target or false, self = own or false }
        internal.Mark(NAME, not (target or own) and "none" or nil)
    end
    lookAgain(min(soonTarget or huge, soonOwn or huge))
end

local queue = Frames.Coalesce(refresh, DELAY, module)

-- Deleted or edited by hand: made again. Our own EditMacro fires this too, and needs nothing.
local function onMacros()
    if not (lastBody and internal.Holds(NAME, lastBody)) then
        queue()
    end
end

local function onTarget()
    if InCombatLockdown() then
        refresh(true) -- the warning has to come with the target, not after a wait
    else
        queue()
    end
end

local AURA_UNITS = { "player", "target" }

local function onAura()
    queue()
end

local function onSpells()
    ranks = nil
    queue()
end

local function onLoaded()
    if incomplete then
        ranks = nil
        queue()
    end
end

function module:OnReady()
    queue()
end

function module:OnEnable()
    if not (Spellbook.Available() and C_Spell.GetSpellName) then
        return
    end
    -- Now, not once it's written: turned off and on in combat, the delete waiting for combat to end
    -- would otherwise empty the macro's action bar slots.
    internal.Want(NAME)
    playerClass = classOf("player")
    ranks, written, lastBody = nil, nil, nil
    -- A plain button, not a secure one: it only shows text, so a click in combat is fine, and the
    -- /cast after it in the macro still works. Made once; it does nothing while the part is off.
    if not button then
        button = CreateFrame("Button", BUTTON_NAME)
        button:SetScript("OnClick", explain)
    end
    self:On("PLAYER_TARGET_CHANGED", onTarget)
    self:OnUnit("UNIT_AURA", AURA_UNITS, onAura)
    self:OnUnit("UNIT_LEVEL", AURA_UNITS, onAura)
    self:On("SPELLS_CHANGED", onSpells)
    self:On("LEARNED_SPELL_IN_SKILL_LINE", onSpells)
    self:On("PLAYER_LEVEL_UP", onSpells)
    self:On("SPELL_DATA_LOAD_RESULT", onLoaded)
    self:On("PLAYER_REGEN_ENABLED", queue)
    self:On("UPDATE_MACROS", onMacros)
    if ns.HasEvent("TRAIT_CONFIG_UPDATED") then
        self:On("TRAIT_CONFIG_UPDATED", queue)
    end
    queue()
end

function module:OnDisable()
    written, ranks, lastBody = nil, nil, nil
    internal.Delete(NAME)
end

function module:OnOptionChanged(key)
    if key == "smartBuffRecast" then
        queue()
    end
end

-- /fpp buffs: how Smart Buff judges your friendly target (or you), to find why it picks what it does.
ns.AddCommand("buffs", "", L.MACROS_SMARTBUFF_COMMAND, function()
    if not (module.enabled and playerClass) then
        ns.Print(L.MACROS_SMARTBUFF_DIAG_OFF)
        return
    end
    if not ranks then
        ranks = Spellbook.Ranks()
    end
    local unit = givesOthers() and friendlyTarget() and "target" or "player"
    local isSelf = unit == "player"
    local auras = aurasOf(unit)
    local trace = {}
    pick(unit, isSelf, auras, trace)
    local name = UnitName(unit)
    name = ns.IsText(name, true) and name or unit
    ns.Print(format(L.MACROS_SMARTBUFF_DIAG_UNIT, name, classOf(unit) or "?", trace.kind or "?",
        trace.mana and L.MACROS_SMARTBUFF_DIAG_MANA or L.MACROS_SMARTBUFF_DIAG_NO_MANA))
    for _, line in ipairs(trace) do
        local state = line.matched
            and format(line.mine and L.MACROS_SMARTBUFF_DIAG_HAS_MINE or L.MACROS_SMARTBUFF_DIAG_HAS,
                line.matched)
            or L.MACROS_SMARTBUFF_DIAG_MISSING
        ns.Print(format(L.MACROS_SMARTBUFF_DIAG_BUFF, line.name,
            line.low and L.MACROS_SMARTBUFF_DIAG_TOO_LOW
                or line.rank == 0 and L.MACROS_SMARTBUFF_DIAG_NO_RANKS
                or line.rank and format(L.MACROS_SMARTBUFF_DIAG_RANK, line.rank)
                or L.MACROS_SMARTBUFF_DIAG_UNKNOWN,
            line.suits and L.MACROS_SMARTBUFF_DIAG_SUITS or L.MACROS_SMARTBUFF_DIAG_FALLBACK, state))
    end
    for group, held in pairs(trace.full or {}) do
        -- Yours that doesn't suit them is replaced only when the macro casts something now.
        local text = held.suits and L.MACROS_SMARTBUFF_DIAG_FULL
            or trace.cast and L.MACROS_SMARTBUFF_DIAG_REPLACE or L.MACROS_SMARTBUFF_DIAG_KEEP
        ns.Print(format(text, group, held.name))
    end
    ns.Print(format(L.MACROS_SMARTBUFF_DIAG_CASTS, trace.cast or L.MACROS_SMARTBUFF_DIAG_NOTHING))
    if not auras then
        ns.Print(L.MACROS_SMARTBUFF_DIAG_NO_AURAS)
        return
    end
    local names = {}
    for aura in pairs(auras) do
        names[#names + 1] = aura
    end
    sort(names)
    ns.Print(format(L.MACROS_SMARTBUFF_DIAG_AURAS, #names > 0 and concat(names, ", ")
        or L.MACROS_SMARTBUFF_DIAG_NOTHING))
end, "Macros")

macros.actions = {
    {
        name = L.MACROS_SMARTBUFF_PICKUP, button = L.MACROS_PICKUP_BUTTON,
        description = L.MACROS_SMARTBUFF_PICKUP_DESC,
        fn = function()
            internal.Pickup(NAME, function()
                ranks = nil
                refresh()
            end)
        end,
    },
}
