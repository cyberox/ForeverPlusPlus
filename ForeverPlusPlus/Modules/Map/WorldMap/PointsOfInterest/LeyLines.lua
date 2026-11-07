-- Points of Interest's Skyborne ley lines and elemental convergences: saving where a cast found
-- one, drawing the saved ones, and the button that forgets them.
local _, ns = ...

local ipairs, pairs, format, abs = ipairs, pairs, string.format, math.abs
local C_Spell, C_Timer, GetTime = C_Spell, C_Timer, GetTime
local UnitRace, InCombatLockdown = UnitRace, InCombatLockdown

local L = ns.L
local MapTooltip = ns.MapTooltip

local internal = ns.modules.WorldMap.internal.pointsOfInterest
local module = internal.module
local KINDS, atlasOf, linesOf = internal.KINDS, internal.atlasOf, internal.linesOf
local zoneName, translate, percent = internal.zoneName, internal.translate, internal.percent

-- The module's only button. This is the last part in the TOC, so it sits right under the ley lines.
ns.modules.WorldMap.actions = {
    {
        name = L.POI_LEYLINES_FORGET,
        button = L.POI_LEYLINES_FORGET_BUTTON,
        description = L.POI_LEYLINES_FORGET_DESC,
        confirm = L.POI_LEYLINES_FORGET_CONFIRM,
        fn = function()
            module.db.leyLineSpots = {}
            if module.enabled then
                internal.refresh()
            end
            ns.Print(L.POI_LEYLINES_FORGET_DONE)
        end,
    },
}

-- Ley lines -----------------------------------------------------------------------------------
-- Skyborne racials: High Order Skyborne (Alliance) cast Read Ley Line on a ley line, Windshapers
-- (Horde) cast Skysight on an elemental convergence, and get a 15-minute buff there instead of a
-- few seconds. The server places them: the client's tables don't have them and Wowhead lists them
-- without a place (2026-10-03, build 70205). So a spot is saved where a cast gave the long buff.

-- Each kind and the side whose Skyborne use it.
local SKYBORNE = { leyline = { side = "A" }, convergence = { side = "H" } }

-- The casts and the buffs they give, spell ID -> kind. The seed is from the client's SpellName,
-- SpellMisc, and SpellEffect tables (wago.tools, build 70205); a patch's new IDs are learned in
-- play: a cast that a fresh 15-minute buff of a known one follows, and the buff a known cast gives.
local CASTS = ns.GameData.New("skyborneCasts", {
    [1259705] = "leyline", -- Read Ley Line
    [1259686] = "convergence", -- Skysight
}, { kind = "spell", label = "Skyborne casts" })
local BUFFS = ns.GameData.New("skyborneBuffs", {
    [1259691] = "leyline", -- Energized
    [1259688] = "convergence", -- Elemental Blessing
}, { kind = "spell", label = "Skyborne buffs" })

-- The kind each Skyborne race ID (ChrRaces) uses: 95 High Order, 96 Windshaper. Both share the
-- race file "Skyborne", which decides; the IDs are only for a side the client won't say.
local RACES = ns.GameData.New("skyborneRaces", { [95] = "leyline", [96] = "convergence" },
    { label = "Skyborne races" })

local function spellName(id)
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or nil
end

-- The name of a spell of this kind in `set` that this client has, or nil.
local function nameOf(set, kindName)
    for id, kind in set:Pairs() do
        if kind == kindName then
            local name = spellName(id)
            if name then
                return name
            end
        end
    end
end

-- The kind this character uses, or nil when it isn't Skyborne. With `learn`, a side that decided
-- it is remembered for the race ID.
function internal.ownKind(learn)
    local _, raceFile, raceID = UnitRace("player")
    if raceFile ~= "Skyborne" then
        return nil
    end
    local side = ns.WorldMap.PlayerSide()
    for kindName, skyborne in pairs(SKYBORNE) do
        if skyborne.side == side then
            if learn then
                RACES:Learn(raceID, kindName)
            end
            return kindName
        end
    end
    return RACES:Get(raceID)
end
local ownKind = internal.ownKind

-- Whether saved spots of this kind show, on a continent map (`world`) or a zone map.
local function showsSpot(kindName, world)
    local db = module.db
    if db.leyLines == "off" or (world and not db.leyLinesWorld) then
        return false
    end
    return db.leyLines == "everyone" or kindName == ownKind()
end

local function spotInfo(kindName, fromMap)
    local kindInfo, skyborne = KINDS[kindName], SKYBORNE[kindName]
    local cast = nameOf(CASTS, kindName)
    -- Ley Line Icon picks the minimap's portal or the ball; convergences are always a ball.
    local look = module.db.leyLineIcon == "portal" and kindInfo.portal or kindInfo
    return {
        atlas = atlasOf(look),
        size = look.pixels * module.db[kindInfo.size] / 100,
        title = kindName == "leyline" and L.POI_LEYLINE or L.POI_CONVERGENCE,
        lines = linesOf(MapTooltip.Side(skyborne.side), MapTooltip.Detail(zoneName(fromMap)),
            cast and MapTooltip.Note(format(L.POI_LEYLINE_CAST, cast))),
    }
end

-- The saved spots that fall on the map being drawn, from whichever map each was saved on.
function internal.addSpots(mapID, world, add)
    for fromMap, spots in pairs(module.db.leyLineSpots) do
        for _, spot in ipairs(spots) do
            if SKYBORNE[spot[1]] and showsSpot(spot[1], world) then
                local x, y = spot[2] / 100, spot[3] / 100
                if fromMap ~= mapID then
                    x, y = translate(fromMap, mapID, x, y)
                end
                if x then
                    add(x, y, spotInfo(spot[1], fromMap))
                end
            end
        end
    end
end

-- Saving ley lines ----------------------------------------------------------------------------

-- How close (in percent of the map) a spot is to a saved one of its kind to be the same.
local SAME_SPOT = 2

-- A buff at least this long (seconds) is the one a spot gives; elsewhere it's 15 or 30 seconds.
local LONG = 600

-- How long (seconds) around a cast a buff may start and still be the one it gave, for lag.
local FRESH = 1

-- The player's long buffs: for each, its spell ID, whether it's a known buff of this kind (by ID,
-- or by name: the 15-minute Energized is in the client's tables, the 15-minute Elemental Blessing
-- isn't, only the 30-second one, so it's taken to share the name), and whether it started with
-- the cast at `castTime`. Secret aura fields are skipped; the caller checks ns.AurasReadable
-- first, and a read that throws anyway ends the scan.
local function longBuffs(kindName, castTime)
    local found = {}
    local names = {}
    for id, kind in BUFFS:Pairs() do
        local name = kind == kindName and spellName(id)
        if name then
            names[name] = true
        end
    end
    ns.EachAura("player", "HELPFUL", function(aura)
        local id, name, duration, expires = aura.spellId, aura.name, aura.duration,
            aura.expirationTime
        if ns.IsReadable(id) and ns.IsReadable(name) and ns.IsReadable(duration)
            and ns.IsReadable(expires) and id and duration and duration >= LONG then
            found[#found + 1] = {
                id = id,
                known = BUFFS:Get(id) == kindName or (name and names[name]) or false,
                fresh = expires and expires - duration >= castTime - FRESH or false,
            }
        end
    end)
    return found
end

-- Saves `where` (the player's map and spot at the cast) as a spot of this kind, unless one is
-- already saved there.
local function saveSpot(kindName, where)
    local mapID, x, y = where[1], where[2], where[3]
    if not mapID then
        return -- afterCast, the only caller, has checked the module is on
    end
    x, y = percent(x), percent(y)
    local all = module.db.leyLineSpots
    local spots = all[mapID] or {}
    for _, spot in ipairs(spots) do
        if spot[1] == kindName and abs(spot[2] - x) < SAME_SPOT and abs(spot[3] - y) < SAME_SPOT then
            return
        end
    end
    spots[#spots + 1] = { kindName, x, y }
    all[mapID] = spots
    module:Print(format(kindName == "leyline" and L.POI_LEYLINE_SAVED or L.POI_CONVERGENCE_SAVED,
        zoneName(mapID)))
    internal.refresh()
end

-- After a cast, once its buff is on: a known cast with a known long buff saves the spot. A known
-- cast whose fresh long buff isn't known teaches that buff, and any other cast that a fresh known
-- long buff follows teaches the cast (a patch's new IDs); both save the spot too. A cast right
-- after a known one teaches nothing, since the buff is the known cast's.
-- While auras are secret (in combat) reading them throws, so a known cast waits for combat to
-- end, with the spot it was cast on; any other cast is skipped, as it's only for learning.
local lastKnownCast = 0
local waiting -- the latest known cast waiting for combat to end, or nil

local function afterCast(spellID, castTime, where)
    local kindName = CASTS:Get(spellID)
    local knownCast = kindName ~= nil
    if not knownCast and castTime - lastKnownCast < 2 * FRESH + 1 then
        return
    end
    kindName = kindName or ownKind()
    if not (module.enabled and kindName) then
        return
    end
    if not ns.AurasReadable() then
        if knownCast and InCombatLockdown() then
            local first = not waiting
            waiting = { spellID, castTime, where }
            if first then
                ns.AfterCombat(function()
                    local cast = waiting
                    waiting = nil
                    -- Still secret out of combat (an instance): give up rather than wait more.
                    if ns.AurasReadable() then
                        afterCast(cast[1], cast[2], cast[3])
                    end
                end)
            end
        end
        return
    end
    local learnBuff
    for _, buff in ipairs(longBuffs(kindName, castTime)) do
        -- Fresh only: an old 15-minute buff from a real convergence says nothing about here.
        if buff.known and buff.fresh then
            if not knownCast then
                CASTS:Learn(spellID, kindName)
            end
            saveSpot(kindName, where)
            return
        elseif knownCast and buff.fresh then
            learnBuff = buff.id
        end
    end
    if learnBuff then
        BUFFS:Learn(learnBuff, kindName)
        saveSpot(kindName, where)
    end
end

function internal.onCast(_, unit, _, spellID)
    if not (ns.IsReadable(unit) and ns.IsReadable(spellID)) or unit ~= "player" or not spellID then
        return
    end
    local castTime = GetTime()
    if CASTS:Get(spellID) then
        lastKnownCast = castTime
    end
    -- Where the cast was, in case its buff can only be read after combat, when they've moved on.
    local where = { ns.WorldMap.PlayerPosition() }
    -- The buff lands after the cast; give the server a moment.
    -- Not once World Map has been turned off in that second.
    C_Timer.After(1, function()
        if module.enabled then
            afterCast(spellID, castTime, where)
        end
    end)
end
