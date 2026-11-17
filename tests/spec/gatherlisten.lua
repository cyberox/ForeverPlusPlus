-- Gathering's listener: what the player gathered, worked out from the casts, the loot, the red
-- errors, and the tooltips the game sends, in the orders it sends them. The events are played by
-- hand against the library's own handlers; several cases here are ones first met in game.
local T = ...
local ns, eq, same, game = T.ns, T.eq, T.same, T.game

local SECRET = "<secret>"
game.secret = SECRET

-- The world the stubs read, changed by the cases.
local world = {
    instance = false, soft = nil, facing = 0,
    map = 1411, x = 0.5, y = 0.5,
    lootGUID = nil, loot = {},
}
local SPELL_NAMES = { [2575] = "Mining", [2576] = "Mining", [2366] = "Herb Gathering", [3365] = "Opening",
    [1804] = "Pick Lock", [7620] = "Fishing", [133] = "Fireball" }
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = game.now + delay, fn = fn } end }
C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] end }
C_Item = { GetItemInfoInstant = function(link) return tonumber((link:match("item:(%d+)"))) end }
IsInInstance = function() return world.instance end
UnitExists = function(unit) return unit == "softinteract" and world.soft ~= nil end
UnitName = function() return world.soft end
GetPlayerFacing = function() return world.facing end
GetLootSourceInfo = function() return world.lootGUID end
GetNumLootItems = function() return #world.loot end
GetLootSlotInfo = function(slot) return "icon" .. world.loot[slot][1], "name", world.loot[slot][2] end
GetLootSlotLink = function(slot) return "item:" .. world.loot[slot][1] end

-- The events Gathering listens for, kept by name so the cases can send them.
local handlers, tooltipHook = {}, nil
ns.OnUnit = function(event, _, fn) handlers[event] = fn end
ns.OffUnit = function(event) handlers[event] = nil end
ns.On = function(event, fn) handlers[event] = fn end
ns.Off = function(event) handlers[event] = nil end
ns.HasEvent = function() return true end
Enum = { TooltipDataType = { Object = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipHook = fn end }
ns.WorldMap.PlayerZonePosition = function() return world.map, world.x, world.y end
ns.WorldMap.Size = function() return 1000, 1000 end

-- Loaded again after the stubs, since the file keeps these at load. Its one data set is made a
-- second time, so GameData hands it a stand-in for the load.
local realData = ns.GameData
ns.GameData = setmetatable({ New = function(_, seed)
    return { Get = function(_, key) return seed[key] end }
end }, { __index = realData })
T.load("Lib/Gathering", ns)
ns.GameData = realData
local Gathering = ns.Gathering

local told = {}
local function listener(gather) told[#told + 1] = gather end
Gathering.Listen(listener, true)
eq(handlers.UNIT_SPELLCAST_SENT ~= nil and handlers.LOOT_READY ~= nil and tooltipHook ~= nil, true,
    "listen: the casts, the loot, and tooltips are heard once a module listens")

-- Sending the game's events.
local function sent(spellID, target, cast) handlers.UNIT_SPELLCAST_SENT(nil, "player", target, cast, spellID) end
local function succeeded(spellID, cast) handlers.UNIT_SPELLCAST_SUCCEEDED(nil, "player", cast, spellID) end
local function failed(spellID, cast) handlers.UNIT_SPELLCAST_FAILED(nil, "player", cast, spellID) end
local function loot(guid, items)
    world.lootGUID, world.loot = guid, items or {}
    handlers.LOOT_READY("LOOT_READY")
end
local function hover(text, extra)
    local lines = { { leftText = text } }
    for _, line in ipairs(extra or {}) do
        lines[#lines + 1] = { leftText = line }
    end
    tooltipHook(nil, { lines = lines })
end
-- Moves the clock on and runs the timers that have come due.
local function wait(seconds)
    game.now = game.now + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= game.now then
            due[#due + 1] = table.remove(timers, i)
        end
    end
    for i = #due, 1, -1 do
        due[i].fn()
    end
end
-- What was told since the last look, each as "name:kind", and forgets it.
local function heard()
    local list = {}
    for i, gather in ipairs(told) do
        list[i] = tostring(gather.name) .. ":" .. tostring(gather.kind)
    end
    local last = told[#told]
    told = {}
    return list, last
end
local VEIN = "GameObject-0-1-2-3-1731-0000000001"
local MOB = "Creature-0-1-2-3-299-0000000001"

-- The plain case: cast at a vein, it succeeds, its loot comes.
game.now = 100
sent(2575, "Copper Vein", "cast-1")
same(heard(), {}, "gather: nothing told while it casts")
succeeded(2575, "cast-1")
same(heard(), {}, "gather: nor at its success, before its loot")
loot(VEIN, { { 2770, 2 }, { 2835, 1 } })
local list, gather = heard()
same(list, { "Copper Vein:ore" }, "gather: told once, with its loot")
eq(gather.objectID, 1731, "gather: the world object's ID, from its GUID")
eq(#gather.items .. ":" .. gather.items[1].id .. ":" .. gather.items[1].count, "2:2770:2", "gather: what it gave")
eq(gather.mapID .. ":" .. gather.x .. ":" .. gather.y, "1411:0.5:0.5", "gather: where the player stood")
eq(gather.from, "target", "gather: named by the cast's own target")
wait(5)
same(heard(), {}, "gather: not told again when its timer runs")

-- Loot before the success (auto loot can come first).
wait(10)
sent(2366, "Peacebloom", "cast-2")
loot(VEIN, { { 2447, 1 } })
same(heard(), {}, "loot first: waits for the cast to succeed")
succeeded(2366, "cast-2")
same(heard(), { "Peacebloom:herb" }, "loot first: told at the success")

-- No loot at all (a chest already empty): told without it once the wait is up.
wait(10)
sent(3365, "Battered Chest", "cast-3")
succeeded(3365, "cast-3")
wait(1)
same(heard(), {}, "no loot: not yet")
wait(1)
list, gather = heard()
same(list, { "Battered Chest:treasure" }, "no loot: told once the wait is up")
eq(#gather.items, 0, "no loot: with nothing")

-- A gather that fails or is interrupted counts for nothing.
wait(10)
sent(2575, "Copper Vein", "cast-4")
failed(2575, "cast-4")
loot(VEIN, { { 2770, 1 } })
wait(5)
same(heard(), {}, "failed: never told, whatever loot follows")

-- A cast that isn't a gather, and someone else's.
wait(10)
sent(133, "Kobold", "cast-5")
succeeded(133, "cast-5")
loot(VEIN, { { 2770, 1 } })
wait(5)
same(heard(), {}, "other spells: a Fireball isn't a gather")
handlers.UNIT_SPELLCAST_SENT(nil, "party1", "Copper Vein", "cast-6", 2575)
handlers.UNIT_SPELLCAST_SUCCEEDED(nil, "party1", "cast-6", 2575)
wait(5)
same(heard(), {}, "other players: a party member's gather isn't the player's")

-- A higher rank of the spell is matched by its name.
wait(10)
sent(2576, "Copper Vein", "cast-7")
succeeded(2576, "cast-7")
loot(VEIN, { { 2770, 1 } })
same(heard(), { "Copper Vein:ore" }, "ranks: Journeyman Mining gathers too")

-- A creature's loot isn't the gather's.
wait(10)
sent(2575, "Copper Vein", "cast-8")
succeeded(2575, "cast-8")
loot(MOB, { { 2589, 1 } })
same(heard(), {}, "creature loot: not the vein's")
wait(2)
list, gather = heard()
same(list, { "Copper Vein:ore" }, "creature loot: the vein is told without it")
eq(#gather.items, 0, "creature loot: and without the creature's items")

-- Nothing is remembered in an instance.
wait(10)
world.instance = true
sent(2575, "Copper Vein", "cast-9")
succeeded(2575, "cast-9")
loot(VEIN, { { 2770, 1 } })
wait(5)
same(heard(), {}, "instances: a gather inside one isn't told")
world.instance = false

-- A cast ID that doesn't match is another cast; one the game hides falls back to the spell.
wait(10)
sent(2575, "Copper Vein", "cast-10")
succeeded(2575, "cast-other")
loot(VEIN, { { 2770, 1 } })
wait(5)
same(heard(), {}, "cast IDs: another cast's success isn't this gather's")
wait(10)
sent(2575, "Copper Vein", SECRET)
succeeded(2575, SECRET)
loot(VEIN, { { 2770, 1 } })
same(heard(), { "Copper Vein:ore" }, "cast IDs: a hidden one is matched by its spell")

-- A second press while the first still casts: the game refuses the second, the first finishes.
wait(10)
sent(2575, "Copper Vein", "cast-11")
wait(1)
sent(2575, "Copper Vein", "cast-12")
failed(2575, "cast-12")
succeeded(2575, "cast-11")
loot(VEIN, { { 2770, 1 } })
same(heard(), { "Copper Vein:ore" }, "second press: the first gather is still told")

-- A press between the cast ending and the loot coming: the loot is still the finished gather's.
wait(10)
sent(2366, "Peacebloom", "cast-13")
succeeded(2366, "cast-13")
sent(2366, "Peacebloom", "cast-14")
loot(VEIN, { { 2447, 2 } })
list, gather = heard()
same(list, { "Peacebloom:herb" }, "press before loot: the finished gather gets its loot")
eq(gather.items[1].count, 2, "press before loot: with what it gave")
failed(2366, "cast-14")

-- A target the cast doesn't name: the object the player faces, when it's a node.
wait(10)
world.soft = "Copper Vein"
sent(2575, SECRET, "cast-15")
succeeded(2575, "cast-15")
loot(VEIN, { { 2770, 1 } })
list, gather = heard()
same(list, { "Copper Vein:ore" }, "no target: named by the object the player faces")
eq(gather.from, "softinteract", "no target: and says so")
world.soft = "Mailbox"
wait(10)
sent(2575, nil, "cast-16")
succeeded(2575, "cast-16")
loot(VEIN, { { 2770, 1 } })
list = heard()
same(list, { "nil:ore" }, "no target: something faced that isn't a node names nothing")
world.soft = nil

-- Or the object hovered just before, used once and only within a few seconds.
wait(10)
hover("Peacebloom")
wait(2)
sent(2366, nil, "cast-17")
succeeded(2366, "cast-17")
loot(VEIN, { { 2447, 1 } })
list, gather = heard()
same(list, { "Peacebloom:herb" }, "hover: the object hovered just before names it")
eq(gather.from, "tooltip", "hover: and says so")
wait(10)
sent(2366, nil, "cast-18")
succeeded(2366, "cast-18")
loot(VEIN, { { 2447, 1 } })
same(heard(), { "nil:herb" }, "hover: used once")
wait(10)
hover("Peacebloom")
wait(6)
sent(2366, nil, "cast-19")
succeeded(2366, "cast-19")
loot(VEIN, { { 2447, 1 } })
same(heard(), { "nil:herb" }, "hover: not one from too long ago")
hover(SECRET)

-- Too low a skill: the red error names the skill and the rank, and the node is told with it.
eq(Gathering.Requirement("Requires Fishing 175"), nil, "requirement: only Herbalism and Mining")
wait(10)
sent(2575, "Tin Vein", "cast-20")
failed(2575, "cast-20")
handlers.UI_ERROR_MESSAGE(nil, 1, "Requires Mining 65")
list, gather = heard()
same(list, { "Tin Vein:ore" }, "too low: the vein is told")
eq(gather.requires, 65, "too low: with the skill it takes")
wait(10)
sent(2575, "Tin Vein", "cast-21")
failed(2575, "cast-21")
handlers.UI_ERROR_MESSAGE(nil, 1, "Requires Herbalism 65")
same(heard(), {}, "too low: another skill's error isn't this gather's")
wait(10)
sent(2575, "Tin Vein", "cast-22")
failed(2575, "cast-22")
wait(2)
handlers.UI_ERROR_MESSAGE(nil, 1, "Requires Mining 65")
same(heard(), {}, "too low: an error that comes too late isn't it")
handlers.UI_ERROR_MESSAGE(nil, 1, SECRET)
same(heard(), {}, "too low: an error the game hides is nothing")

-- Fishing: only a pool is remembered, where the line landed, 15 yards in front of the player.
local BOBBER = "GameObject-0-1-2-3-35591-0000000002"
wait(30)
sent(7620, nil, "cast-30")
succeeded(7620, "cast-30")
loot(BOBBER, { { 6291, 1 } })
wait(30)
same(heard(), {}, "fishing: a catch in open water isn't told")
-- A known pool hovered before the cast names it; the catch comes from the bobber even in a pool.
wait(10)
hover("Floating Wreckage")
world.facing = 0 -- north: the line lands toward a smaller y
sent(7620, nil, "cast-31")
succeeded(7620, "cast-31")
wait(8)
loot(BOBBER, { { 6358, 1 } })
list, gather = heard()
same(list, { "Floating Wreckage:fish" }, "fishing: a pool hovered before the cast")
eq(gather.x .. ":" .. gather.y, "0.5:0.485", "fishing: its spot is 15 yards ahead of the player")
-- Facing west and standing at the map's west edge, the spot stays on the map.
wait(30)
world.x, world.facing = 0.005, math.pi / 2
hover("Floating Wreckage")
sent(7620, nil, "cast-32")
succeeded(7620, "cast-32")
wait(5)
loot(BOBBER, { { 6358, 1 } })
list, gather = heard()
eq(gather and gather.x, 0, "fishing: a spot past the map's edge is kept on it")
world.x, world.facing = 0.5, 0
-- A cast at a pool that catches nothing says nothing about where the pool is.
wait(30)
hover("Floating Wreckage")
sent(7620, nil, "cast-33")
succeeded(7620, "cast-33")
wait(30)
same(heard(), {}, "fishing: a cast with no catch isn't told")

-- No one listening: the events stop being heard.
Gathering.Listen(listener, false)
eq(handlers.UNIT_SPELLCAST_SENT, nil, "listen: nothing is heard once no module listens")
