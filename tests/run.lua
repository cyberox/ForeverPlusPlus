-- Offline tests for the pure-logic Lib code. Plain Lua 5.1, no WoW client: run from the repo root
-- with `lua tests/run.lua`. Each Lib file is loaded the way the client does (with the addon name
-- and a shared `ns`), against a few stubbed WoW globals. No frame or UI code is tested here, except
-- Core's module lifecycle near the end, on stub frames.
local ADDON = "ForeverPlusPlus"

-- Stubs -----------------------------------------------------------------------------------------

local player = { level = 30, faction = "Horde" }

UnitLevel = function()
    return player.level
end
UnitFactionGroup = function()
    return player.faction
end
GetQuestDifficultyColor = function(level)
    -- Marks the level asked about, so tests can tell which one the code picked.
    return { r = level, g = 0, b = 0 }
end
QuestDifficultyColors = { difficult = { r = "difficult", g = 0, b = 0 } }
FACTION_ALLIANCE, FACTION_HORDE = "Alliance", "Horde"
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 } }
-- The Lib files cache these globals at load, so the stubs are fixed and read a table.
local game = { secret = nil, zoneNames = {} }
issecretvalue = function(value)
    return value == game.secret
end
GetRealZoneText = function(id)
    return game.zoneNames[id] or ""
end
game.cachedItems = {}
C_Item = {
    -- An ID, or a table of the whole answer (id, type, subtype, equip location, ...).
    GetItemInfoInstant = function(name)
        local item = game.cachedItems[name]
        if type(item) == "table" then
            return unpack(item)
        end
        return item
    end,
}
-- What the player wears (Lib/Equipment.lua): slot -> link.
game.worn = {}
game.dualWield = false
GetInventoryItemLink = function(_, slot)
    return game.worn[slot]
end
CanDualWield = function()
    return game.dualWield
end
game.now = 0
GetTime = function()
    return game.now
end
game.clock = 0
time = function()
    return game.clock
end
-- Marks the number it's given, so tests can tell Text.Number went through it.
BreakUpLargeNumbers = function(n)
    return "big:" .. n
end

local ns = {}
ns.NewLocale = function()
    return ns.L
end
ns.L = {}
ns.Call = function(fn, ...)
    return fn(...)
end

local function load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk(ADDON, ns)
end

for _, file in ipairs({ "Core", "Map" }) do
    load("ForeverPlusPlus/Locales/enUS/" .. file .. ".lua")
end
ITEM_MIN_SKILL = "Requires %s (%d)"
for _, file in ipairs({ "Secret", "Colors", "Text", "GameData", "WorldMap", "Instances", "Chat",
    "TalentPlan", "Errors", "Prices", "Disenchant", "Store", "Keys", "Professions", "ItemStats", "Equipment",
    "Talents", "Quests", "Taxi" }) do
    load("ForeverPlusPlus/Lib/" .. file .. ".lua")
end

-- Harness ---------------------------------------------------------------------------------------

local failures, count = 0, 0

local function eq(got, want, what)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(("FAIL %s: got %s, wanted %s"):format(what, tostring(got), tostring(want)))
    end
end

-- Colors ----------------------------------------------------------------------------------------

eq(ns.Colors.Code(1, 0, 0), "|cffff0000", "Code red")
eq(ns.Colors.Code(0.5, 0.5, 0.5), "|cff808080", "Code rounds")
eq(ns.Colors.Text({ r = 0, g = 1, b = 0 }, "hi"), "|cff00ff00hi|r", "Text wraps")
eq(ns.Colors.Faction("H"), ns.Colors.Faction("H"), "Faction stable")
eq(ns.Colors.Faction("A").b > ns.Colors.Faction("A").r, true, "Alliance is blue")
eq(ns.Colors.Faction("H").r > ns.Colors.Faction("H").b, true, "Horde is red")
eq(ns.Colors.Faction("?"), ns.Colors.Faction(nil), "unknown side is neutral")
eq(ns.Colors.ClassToken(nil), nil, "no class token, no color")

player.level = 10 -- below the range: colored by its low end
eq(ns.Colors.LevelRange(20, 30).r, 20, "range above you uses low")
player.level = 25 -- inside
eq(ns.Colors.LevelRange(20, 30).r, "difficult", "range you are in")
player.level = 40 -- outleveled: two below the top
eq(ns.Colors.LevelRange(20, 30).r, 28, "outleveled uses high - 2")
eq(ns.Colors.LevelRange(29, 30).r, 29, "outleveled never goes under low")

-- Text ------------------------------------------------------------------------------------------

eq(ns.Text.Number(12345), "big:12345", "Number uses the client's separators")
eq(ns.Text.Clock(0), "0:00", "Clock zero")
eq(ns.Text.Clock(42), "0:42", "Clock seconds")
eq(ns.Text.Clock(725), "12:05", "Clock minutes")
eq(ns.Text.Clock(41.6), "0:42", "Clock rounds")
eq(ns.Text.Clock(3599.6), "1:00:00", "Clock rounds up to an hour")
eq(ns.Text.Clock(3725), "1:02:05", "Clock hours")
eq(ns.Text.Clock(-0.6), "0:00", "Clock never goes below zero")
eq(ns.Text.Seconds(1), "1 Second", "one second")
eq(ns.Text.Seconds(5), "5 Seconds", "seconds")
eq(ns.Text.Hours(1), "1 Hour", "one hour")
eq(ns.Text.Hours(12), "12 Hours", "hours")
eq(ns.Text.NewerVersion("0.8.0", "0.7.0"), true, "newer version")
eq(ns.Text.NewerVersion("0.10.0", "0.9.2"), true, "newer version by number, not text")
eq(ns.Text.NewerVersion("0.7.0", "0.7.0"), false, "same version")
eq(ns.Text.NewerVersion("0.7", "0.7.0"), false, "missing part is zero")
eq(ns.Text.NewerVersion("0.7.0", "0"), true, "anything after 0")
eq(ns.Text.NewerVersion("1.0.0", "1.0.0-beta.1"), true, "release after its pre-release")
eq(ns.Text.NewerVersion("1.0.0-beta.1", "1.0.0"), false, "pre-release before its release")
eq(ns.Text.NewerVersion("1.0.0-beta.2", "1.0.0-beta.1"), true, "later pre-release")
eq(ns.Text.NewerVersion("1.0.0-beta.1", "0.10.0"), true, "pre-release after the last release")
eq(ns.Text.NewerVersion("1.0.0-beta.1", "1.0.0-beta.1"), false, "same pre-release")
eq(ns.Text.Ago(5), "just now", "ago now")
eq(ns.Text.Ago(60), "1m ago", "ago minute")
eq(ns.Text.Ago(3599), "59m ago", "ago last minute")
eq(ns.Text.Ago(3600), "1h ago", "ago hour")
eq(ns.Text.Ago(86400 * 2 + 5), "2d ago", "ago days")
eq(ns.Text.Plain("|cffff0000red|r text"), "red text", "plain color")
eq(ns.Text.Plain("|cnCOLOR:named|r"), "named", "plain named color")
eq(ns.Text.Plain("|Hplayer:Bob:1|h[Bob]|h: hi"), "[Bob]: hi", "plain link keeps its text")
eq(ns.Text.Plain("a |TInterface\\Icon:0|t b |A:Raid:14:14|a c"), "a  b  c", "plain textures")
eq(ns.Text.Plain("100||"), "100|", "plain escaped pipe")
eq(ns.Text.Plain("Requires Mining (75)"), "Requires Mining (75)", "plain text without codes is kept")
eq(ns.Text.Plain("a||rb ||cffffffffc |cff00ff00d|r"), "a|rb |cffffffffc d",
    "plain escaped pipe before a code letter")

local function matches(formatString, text, capture)
    return text:match("^" .. ns.Text.FormatPattern(formatString, capture) .. "$")
end
eq(matches("Requires %s (%d)", "Requires Mining (75)", true), "Mining", "format pattern captures")
eq(select(2, matches("Requires %s (%d)", "Requires Mining (75)", true)), "75",
    "format pattern captures numbers")
eq(matches("%2$s from %1$s.", "Axe from Bob.", true), "Axe", "format pattern reordered")
eq(matches("Collected (%d/%d)", "Collected (1/3)") ~= nil, true, "format pattern without captures")
eq(matches("Collected (%d/%d)", "Collected (a/3)"), nil, "format pattern %d needs digits")
eq(matches("Press %s to submit", "Press [F1] to submit") ~= nil, true, "format pattern escapes")

local split = ns.Text.Split("short one", 20)
eq(#split, 1, "split leaves a short message whole")
eq(split[1], "short one", "split short text")
split = ns.Text.Split("aaaa bbbb cccc dddd", 10)
eq(#split, 2, "split long text in two")
eq(split[1], "aaaa bbbb", "split between words")
eq(split[2], "cccc dddd", "split rest")
split = ns.Text.Split("abcdefghijkl", 5)
eq(split[1], "abcde", "split a long word at the limit")
eq(#split, 3, "split a long word in pieces")
local link = "|cff1eff00|Hitem:123|h[Sword]|h|r"
split = ns.Text.Split("buy " .. link .. " now", 35) -- the link is 33 bytes
eq(split[1], "buy", "split keeps a link whole")
eq(split[2], link, "split puts the link in one piece")
eq(split[3], "now", "split after the link")
split = ns.Text.Split("buy " .. link, 20)
eq(split[2], link, "split keeps a link longer than the limit whole")
for i, piece in ipairs(ns.Text.Split(("word "):rep(200), 255)) do
    eq(#piece <= 255, true, "split piece " .. i .. " fits")
end

-- Secret ----------------------------------------------------------------------------------------

eq(ns.IsReadable(5), true, "readable without issecretvalue")
game.secret = "secret"
eq(ns.IsReadable("secret"), false, "secret is unreadable")
eq(ns.IsText("a"), true, "text")
eq(ns.IsText(""), true, "empty text")
eq(ns.IsText("", true), false, "empty text when it must not be")
eq(ns.IsText(5), false, "a number isn't text")
eq(ns.IsText(nil), false, "nil isn't text")
eq(ns.IsText("secret"), false, "secret isn't text")
eq(ns.IsNumber(5), true, "a number")
eq(ns.IsNumber("5"), false, "text isn't a number")
game.secret = 7
eq(ns.IsNumber(7), false, "a secret number isn't readable")
game.secret = "secret"
eq(ns.IsTrue(true), true, "true is true")
eq(ns.IsTrue(false), false, "false isn't true")
eq(ns.IsTrue("secret"), false, "secret isn't surely true")
eq(ns.IsTrueOrSecret(false), false, "false is off")
eq(ns.IsTrueOrSecret(nil), false, "nil is off")
eq(ns.IsTrueOrSecret("secret"), true, "secret may be true")
game.secret = nil

-- WorldMap --------------------------------------------------------------------------------------

local WorldMap = ns.WorldMap
eq(WorldMap.IsContinent({ mapType = 2 }), true, "continent")
eq(WorldMap.IsContinent({ mapType = 1 }), true, "world")
eq(WorldMap.IsContinent({ mapType = 3 }), false, "zone")
eq(WorldMap.IsContinent({ mapType = 0 }), false, "cosmic off by default")
eq(WorldMap.IsContinent({ mapType = 0 }, true), true, "cosmic when asked")
eq(WorldMap.IsContinent(nil), false, "no info")

-- A map tree: Azeroth (world) > Kalimdor (continent) > Durotar (zone) > a cave (dungeon).
local maps = {
    [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
    [12] = { mapID = 12, name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1411] = { mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 12 },
    [9001] = { mapID = 9001, name = "Cave", mapType = 4, parentMapID = 1411 },
}
local here = { mapID = 1411, x = 0.25, y = 0.75 }
C_Map = {
    GetMapInfo = function(id)
        return maps[id]
    end,
    GetBestMapForUnit = function()
        return here.mapID
    end,
    GetPlayerMapPosition = function(id)
        return id == here.mapID and { x = here.x, y = here.y } or nil
    end,
}
local walked = {}
for mapID in WorldMap.Up(9001) do
    walked[#walked + 1] = mapID
end
eq(table.concat(walked, ","), "9001,1411,12", "Up stops at the continent")
walked = {}
for mapID in WorldMap.Up(947) do
    walked[#walked + 1] = mapID
end
eq(table.concat(walked, ","), "947", "Up from the world is just the world")
walked = {}
for mapID, info in WorldMap.Up(5) do
    walked[#walked + 1] = mapID .. (info and "" or "?")
end
eq(table.concat(walked, ","), "5?", "Up stops at a map without info")
eq(WorldMap.Up(nil)(), nil, "Up from no map")
eq(WorldMap.Root(9001), 947, "Root")
eq(WorldMap.Root(5), nil, "Root of an unknown map")
eq(WorldMap.MapName(1411, "?"), "Durotar", "MapName")
eq(WorldMap.MapName(5, "?"), "?", "MapName fallback")
local id, x, y = WorldMap.PlayerPosition()
eq(id == 1411 and x == 0.25 and y == 0.75, true, "PlayerPosition on the player's map")
eq(WorldMap.PlayerPosition(12), nil, "PlayerPosition off the map")
game.secret = 0.25
eq(WorldMap.PlayerPosition(), nil, "PlayerPosition while secret")
game.secret = nil
C_Map = nil
eq(WorldMap.PlayerSide(), "H", "Horde side")
player.faction = "Alliance"
eq(WorldMap.PlayerSide(), "A", "Alliance side")
player.faction = "Pandaren"
eq(WorldMap.PlayerSide(), nil, "neutral side")
eq(WorldMap.SideName("A"), "Alliance", "side name")
eq(WorldMap.SideName("X"), nil, "unknown side name")

-- Toward: on a 1000 by 500 yard map, from the middle.
local function near(got, want, what)
    eq(math.abs(got - want) < 1e-9, true, what .. " (" .. tostring(got) .. ")")
end
local yards, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.5, 0.3)
near(yards, 100, "north distance")
near(angle, 0, "north is 0")
yards, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.4, 0.5)
near(yards, 100, "west distance uses width")
near(angle, math.pi / 2, "west is a quarter turn left")
_, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.5, 0.7)
near(angle, math.pi, "south is half a turn")
_, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.6, 0.5)
near(angle, 3 * math.pi / 2, "east is three quarters")
yards = WorldMap.Toward(1000, 500, 0.2, 0.2, 0.2, 0.2)
near(yards, 0, "same spot")

-- Instances -------------------------------------------------------------------------------------

local Instances = ns.Instances
local ids = {}
for key, inst in pairs(Instances.byKey) do
    eq(type(inst[2]) == "string" and inst[2] ~= "", true, key .. " has an English name")
    eq(inst[3] <= inst[4], true, key .. " levels in order")
    if inst[1] then
        eq(ids[inst[1]], nil, key .. " instance id is unique")
        ids[inst[1]] = key
    end
end

player.level = 30
eq(Instances.Name(Instances.byKey.mc), "Molten Core", "name falls back to English")
game.zoneNames[409] = "Kern des Feuers"
eq(Instances.Name(Instances.byKey.mc), "Kern des Feuers", "name from the game")
eq(Instances.Name(Instances.byKey.brd), "Blackrock Depths", "empty game name falls back")
game.zoneNames[409] = nil

eq(Instances.ByName("molten core"), Instances.byKey.mc, "ByName is case-insensitive")
eq(Instances.ByName("Nowhere"), nil, "ByName unknown")
eq(Instances.ByName(nil), nil, "ByName nil")

ns.Colors.LevelRange = function()
    return nil
end
eq(Instances.Levels(Instances.byKey.mc), "Level 60", "single level")
eq(Instances.Levels(Instances.byKey.brd), "Level 52-60", "level range")
eq(Instances.Levels(Instances.byKey.brd, true), "52-60", "compact range")
eq(Instances.Levels(Instances.byKey.mc, true), "60", "compact single")
eq(Instances.Icon(Instances.byKey.mc, 14), "|A:Raid:14:14|a", "raid icon")
eq(Instances.Icon(Instances.byKey.brd, 14), "|A:Dungeon:14:14|a", "dungeon icon")


-- Chat.Colored, Chat.Uncolor, and offsets between them
local Chat = ns.Chat
eq(Chat.Colored("hi", 1, 0, 0), "|cffff0000hi|r", "colored line")
eq(Chat.Colored("hi"), "hi", "colored without a color")
eq(Chat.Colored("[|cff00ff00Bob|r]: hi", 0, 0, 1),
    "|cff0000ff[|r|cff00ff00Bob|r|cff0000ff]: hi|r", "colored keeps a name's color apart from the line's")
eq(Chat.Colored("|Hplayer:Bob|h[|cff00ff00Bob|r]|h: |cnIQ4:|Hitem:1|h[Axe]|h|r", 1, 1, 1),
    "|cffffffff[|r|cff00ff00Bob|r|cffffffff]: |r|cnIQ4:[Axe]|r|cffffffff|r",
    "colored keeps link colors apart from the line's")
ITEM_QUALITY_COLORS = { [4] = { r = 1, g = 0.5, b = 0 } }
eq(Chat.Colored("|cnIQ4:[Axe]|r |cnIQ9:[Odd]|r"), "|cffff8000[Axe]|r |cnIQ9:[Odd]|r",
    "colored turns item quality into a color code")
ITEM_QUALITY_COLORS = nil
eq(Chat.Colored("|Hplayer:Bob|h[Bob]|h |TIcon:0|tx", 1, 1, 1), "|cffffffff[Bob] x|r",
    "colored drops links and textures")
eq(Chat.Colored("a||rb", 1, 1, 1), "|cffffffffa||rb|r", "colored keeps an escaped pipe")
-- Chat.TimestampFormat and Chat.Stamp, as Blizzard's chat setting and BetterDate give them
eq(Chat.Stamp(), "", "no stamp while chat timestamps are off")
time, date = function() return 0 end, function(fmt) return "D(" .. fmt .. ")" end
ChatFrameUtil = { GetTimestampFormat = function() return "[%H:%M] " end }
eq(Chat.TimestampFormat(), "[%H:%M] ", "timestamp format from the chat setting")
eq(Chat.Stamp(), "D([%H:%M] )", "stamp without BetterDate")
TimeUtil = { BetterDate = function(fmt, t) return "B(" .. fmt .. t .. ")" end }
eq(Chat.Stamp(), "B([%H:%M] 0)", "stamp through BetterDate, like Blizzard's")
ChatFrameUtil.GetTimestampFormat = function() return nil end
eq(Chat.TimestampFormat(), nil, "timestamps off")
eq(Chat.Stamp(), "", "no stamp while off")
ChatFrameUtil, TimeUtil, time, date = nil, nil, nil, nil
local colored = "|cffff0000ab|cnRED:cd|r||e|r"
eq(Chat.Uncolor(colored), "abcd|e", "uncolor")
eq(Chat.Uncolor(Chat.Colored("[|cff00ff00Bob|r]: 5||6", 1, 0, 0)), "[Bob]: 5|6", "uncolor colored")
eq(Chat.PlainOffset(colored, 0), 0, "plain offset start")
eq(Chat.PlainOffset(colored, 12), 2, "plain offset after ab")
eq(Chat.PlainOffset(colored, 5), 0, "plain offset inside a code")
eq(Chat.PlainOffset(colored, #colored), 6, "plain offset end")
eq(Chat.ColoredOffset(colored, 0), 0, "colored offset start")
eq(Chat.ColoredOffset(colored, 2), 12, "colored offset after ab")
eq(Chat.ColoredOffset(colored, 3), 20, "colored offset after a code")
eq(Chat.ColoredOffset(colored, 5), 25, "colored offset after an escaped pipe")
eq(Chat.ColoredOffset(colored, 6), 26, "colored offset end, before the last code")

-- Chat.TimestampPattern
local function stamp(format, line)
    local _, finish = line:find(Chat.TimestampPattern(format))
    return finish and line:sub(1, finish)
end
eq(stamp("%I:%M ", "09:41 [Bob]: hi"), "09:41 ", "timestamp hours and minutes")
eq(stamp("[%H:%M:%S] ", "[21:05:09] hi"), "[21:05:09] ", "timestamp in brackets")
eq(stamp("%I:%M %p ", "9:41 PM hi"), "9:41 PM ", "timestamp with AM or PM")
eq(stamp("%I:%M ", "|Haddon:x|h09:41 |h hi"), nil, "timestamp not inside a link")
eq(stamp("%H:%M ", "[Bob]: 12:30 tonight"), nil, "timestamp only at the start")

-- TalentPlan ------------------------------------------------------------------------------------

local Plan = ns.TalentPlan
-- Two tabs. Tab 1: a (5 ranks, row 0), b (3, row 1, needs 5), c (1, row 1, needs a maxed).
-- Tab 2: d (5, row 0), e (1, row 0, needs d or a maxed: Sufficient edges).
local talents = {
    nodes = {
        a = { max = 5, tab = 1, req = 0, prereqs = {} },
        b = { max = 3, tab = 1, req = 5, prereqs = {} },
        c = { max = 1, tab = 1, req = 5, prereqs = { { id = "a", required = true } } },
        d = { max = 5, tab = 2, req = 0, prereqs = {} },
        e = { max = 1, tab = 2, req = 0, prereqs = { { id = "d" }, { id = "a" } } },
    },
    order = { "a", "d", "e", "b", "c" },
}

local picks = {}
eq(Plan.Add(talents, picks, "b", 10), false, "row 1 needs 5 points in the tab")
eq(select(2, Plan.Add(talents, picks, "b", 10)), "tier", "tier reason")
for _ = 1, 4 do
    Plan.Add(talents, picks, "a", 10)
end
eq(select(2, Plan.Add(talents, picks, "c", 10)), "tier", "4 points aren't 5")
eq(select(2, Plan.Add(talents, picks, "e", 10)), "prereq", "sufficient edge unmet")
eq(Plan.Add(talents, picks, "a", 10), true, "fifth rank")
eq(select(2, Plan.Add(talents, picks, "a", 10)), "max", "no sixth rank")
eq(Plan.Add(talents, picks, "c", 10), true, "prerequisite maxed")
eq(Plan.Add(talents, picks, "e", 10), true, "any sufficient edge is enough")
eq(#picks, 7, "seven points")
eq(select(2, Plan.Add(talents, picks, "d", 7)), "points", "no points left at the cap")

eq(select(2, Plan.Remove(talents, picks, "a")), "needed", "c and e need the fifth a")
eq(Plan.Remove(talents, picks, "e"), true, "remove the last point")
eq(Plan.Remove(talents, picks, "c"), true, "then c")
eq(Plan.Remove(talents, picks, "a"), true, "then a is free")
eq(#picks, 4, "four points left")
eq(select(2, Plan.Remove(talents, picks, "d")), "none", "nothing in d")
eq(select(2, Plan.Remove(talents, { "a", "a", "d" }, "d", 2)), "none", "remove looks under the cap")

local counts, tabs, bad, why = Plan.Simulate(talents, { "a", "b" })
eq(bad, 2, "simulate finds the bad point")
eq(why, "tier", "and why")
eq(counts.a, 1, "counts before it")
eq(tabs[1], 1, "tab points before it")
eq(select(3, Plan.Simulate(talents, { "a", "b" }, 1)), nil, "limit stops before it")

local order = Plan.FromRanks(talents, { a = 5, c = 1, e = 1, d = 2 })
eq(#order, 9, "learned points all placed")
eq(select(3, Plan.Simulate(talents, order)), nil, "learned order is valid")
eq(order[1], "a", "top row first")

eq(select(2, Plan.Next({ "a", "a", "d", "a" }, { a = 2 })), "d", "next unlearned point")
eq(Plan.Next({ "a", "a", "d", "a" }, { a = 2 }), 3, "its place")
eq(Plan.Next({ "a" }, { a = 1 }), nil, "plan done")

local shared = Plan.Encode(1117, { name = "Arms: Leveling|x", level = 30, picks = { 101, 101, 101, 102, 101 } })
eq(shared, "FPP:1:1117:30:Arms Levelingx:101*3,102,101", "encode runs, strip : and |")
local back = Plan.Decode("  " .. shared .. " ")
eq(back and back.treeID, 1117, "decode tree")
eq(back and back.level, 30, "decode level")
eq(back and back.name, "Arms Levelingx", "decode name")
eq(back and #back.picks, 5, "decode points")
eq(back and back.picks[3], 101, "decode run")
eq(back and back.picks[4], 102, "decode single")
eq(#Plan.Decode("FPP:1:5:10::").picks, 0, "decode empty plan")
eq(Plan.Decode("hello"), nil, "decode junk")
eq(Plan.Decode("FPP:1:5:10:x:1**2"), nil, "decode bad run")
eq(Plan.Decode("FPP:1:5:60::1*999999999"), nil, "decode refuses a huge run")
eq(Plan.Decode("FPP:1:5:60::1*50,2*2"), nil, "decode refuses more than 51 points")
eq(#Plan.Decode("FPP:1:5:60::1*50,2").picks, 51, "decode takes 51 points")
eq(Plan.Decode("FPP:1:5:60:|cffff0000Red|r:1").name, "cffff0000Redr", "decode drops | from names")

eq(Plan.FirstLevel(30, 21), 10, "first point at 10")
eq(Plan.FirstLevel(5, 0), 10, "none earned yet: Classic's 10")
eq(Plan.PointsAt(30, 10), 21, "21 points at 30")
eq(Plan.PointsAt(9, 10), 0, "none before 10")
eq(Plan.LevelOf(21, 10), 30, "21st point at 30")
eq(Plan.FirstLevel(30, 26, 5), 5, "talented: counted from points earned")
eq(Plan.FirstLevel(4, 0, 5), 5, "talented, none earned yet: level 5")
eq(Plan.FirstLevel(60, 51, 5), 5, "talented, all 51 earned: level 5")
eq(Plan.FirstLevel(60, 51), 10, "all 51 earned: level 10")
eq(Plan.PointsAt(60, 5), 51, "never more than 51")
eq(Plan.PointsAt(30, 5), 26, "talented: 26 points at 30")

-- Rows 90 apart from the top at 100; a node 1 off its row's height stays in it, and a gate
-- condition the game gave is kept.
local gated = {
    top = { y = 100 },
    nudged = { y = 101 },
    second = { y = 190 },
    fourth = { y = 370 },
    given = { y = 370, req = 7 },
}
Plan.RowGates(gated)
eq(gated.top.req, 0, "row gates: top row needs nothing")
eq(gated.nudged.req, 0, "row gates: a 1 gap isn't a row")
eq(gated.second.req, 5, "row gates: second row needs 5")
eq(gated.fourth.req, 15, "row gates: rows counted by the smallest gap")
eq(gated.given.req, 7, "row gates: a gate condition is kept")
local single = { only = { y = 40 } }
Plan.RowGates(single, 3)
eq(single.only.req, 0, "row gates: one node is the top row")
local custom = { a = { y = 0 }, b = { y = 50 } }
Plan.RowGates(custom, 3)
eq(custom.b.req, 3, "row gates: points per row can be given")

-- Errors ----------------------------------------------------------------------------------------

local Errors = ns.Errors
local heard, toggled = 0, 0
Errors.OnChanged(function()
    heard = heard + 1
end)
eq(Errors.IsOn(), false, "errors off at first")
eq(Errors.SessionCount(), 0, "no count while off")
Errors.Toggle() -- does nothing while off
Errors.Provide({
    session = function() return 3 end,
    saved = function() return 7 end,
    toggle = function() toggled = toggled + 1 end,
    clearSession = function() toggled = toggled + 10 end,
})
eq(Errors.IsOn(), true, "errors on once provided")
eq(heard, 1, "providing tells listeners")
eq(Errors.SessionCount(), 3, "session count")
eq(Errors.SavedCount(), 7, "saved count")
Errors.Toggle()
eq(toggled, 1, "toggle opens the window")
Errors.ClearSession()
eq(toggled, 11, "clear session reaches error catcher")
Errors.Changed()
eq(heard, 2, "changes tell listeners")
Errors.Provide(nil)
eq(Errors.IsOn(), false, "errors off again")
eq(Errors.SavedCount(), 0, "no saved count while off")
eq(heard, 3, "turning off tells listeners")

-- Prices ----------------------------------------------------------------------------------------

local Prices = ns.Prices
game.cachedItems["Strange Dust"] = 10940
eq(Prices.Available(), false, "no prices without a source")
eq(Prices.Auction(10940), nil, "no auction price without a source")
eq(Prices.ItemByName("Strange Dust"), 10940, "item cache finds a name without a source")
eq(Prices.ItemByName("Bolt of Silk Cloth"), nil, "unknown name without a source")
eq(Prices.Inline(), false, "price lines at the edge without a source")
Prices.SetSource({
    price = function(itemID)
        return itemID == 4305 and 120 or nil
    end,
    itemByName = function(name)
        return name == "Bolt of Silk Cloth" and 4305 or nil
    end,
    inline = function()
        return true
    end,
})
eq(Prices.Available(), true, "prices with a source")
eq(Prices.Auction(4305), 120, "source's price")
eq(Prices.Auction(10940), nil, "item the source has no price for")
eq(Prices.ItemByName("Bolt of Silk Cloth"), 4305, "source finds a name the cache doesn't")
eq(Prices.ItemByName("Strange Dust"), 10940, "item cache first")
eq(Prices.Inline(), true, "source's alignment")
Prices.SetSource(nil)
eq(Prices.Auction(4305), nil, "no prices once the source goes")

-- Disenchant ------------------------------------------------------------------------------------

do
    local Disenchant = ns.Disenchant
    local function describe(list)
        if not list then
            return "nil"
        end
        local parts = {}
        for i, each in ipairs(list) do
            parts[i] = ("%d %g %d-%d"):format(each.item, each.chance, each.min, each.max)
        end
        return table.concat(parts, ", ")
    end
    eq(describe(Disenchant.Outcomes(2, 28, false)), "11083 0.75 1-2, 11082 0.2 1-2, 11084 0.05 1-1",
        "disenchant: uncommon armor 26-30 is mostly Soul Dust")
    eq(describe(Disenchant.Outcomes(2, 28, true)), "11082 0.75 1-2, 11083 0.2 1-2, 11084 0.05 1-1",
        "disenchant: uncommon weapon 26-30 is mostly Greater Astral")
    eq(describe(Disenchant.Outcomes(2, 5, false)), "10940 0.8 1-2, 10938 0.2 1-2",
        "disenchant: uncommon armor 5-15 has no shard")
    eq(describe(Disenchant.Outcomes(2, 15, true)), "10938 0.8 1-2, 10940 0.2 1-2",
        "disenchant: uncommon weapon 5-15")
    eq(describe(Disenchant.Outcomes(2, 21, true)), "10998 0.75 1-2, 10940 0.15 4-6, 10978 0.1 1-1",
        "disenchant: uncommon weapon 21-25 shard at 10%")
    eq(describe(Disenchant.Outcomes(2, 65, false)), "16204 0.75 2-5, 16203 0.2 2-3, 14344 0.05 1-1",
        "disenchant: uncommon armor top bracket")
    eq(Disenchant.Outcomes(2, 4, false), nil, "disenchant: uncommon below level 5")
    eq(Disenchant.Outcomes(2, 66, false), nil, "disenchant: uncommon above the table")
    eq(describe(Disenchant.Outcomes(3, 11, true)), "10978 1 1-1", "disenchant: rare lowest bracket")
    eq(describe(Disenchant.Outcomes(3, 60, false)), "14344 0.995 1-1, 20725 0.005 1-1",
        "disenchant: rare 56-65 can give a Nexus Crystal")
    eq(Disenchant.Outcomes(3, 10, false), nil, "disenchant: rare below level 11")
    eq(describe(Disenchant.Outcomes(4, 45, false)), "11177 1 2-4", "disenchant: epic 40-45")
    eq(describe(Disenchant.Outcomes(4, 58, true)), "20725 1 1-1", "disenchant: epic 56-60")
    eq(describe(Disenchant.Outcomes(4, 70, true)), "20725 1 1-2", "disenchant: epic 61-80")
    eq(Disenchant.Outcomes(4, 39, false), nil, "disenchant: epic below level 40")
    eq(Disenchant.Outcomes(1, 30, false), nil, "disenchant: common gives nothing")
    eq(Disenchant.Outcomes(5, 70, false), nil, "disenchant: legendary isn't in the table")
    eq(Disenchant.Outcomes(2, nil, false), nil, "disenchant: no item level")
    eq(Disenchant.ForItem(15, 2, "", 30), nil, "disenchant: not a weapon or armor")
    eq(Disenchant.ForItem(4, 2, "INVTYPE_BODY", 30), nil, "disenchant: shirts can't")
    eq(Disenchant.ForItem(4, 2, "INVTYPE_TABARD", 30), nil, "disenchant: tabards can't")
    eq(describe(Disenchant.ForItem(2, 2, "INVTYPE_WEAPON", 28)), describe(Disenchant.Outcomes(2, 28, true)),
        "disenchant: class 2 counts as a weapon")
    eq(describe(Disenchant.ForItem(4, 2, "INVTYPE_CHEST", 28)), describe(Disenchant.Outcomes(2, 28, false)),
        "disenchant: class 4 counts as armor")
    -- chance x average amount x price: 0.75 x 1.5 x 100 + 0.2 x 1.5 x 1000 + 0.05 x 1 x 2000
    local prices = { [11083] = 100, [11082] = 1000, [11084] = 2000 }
    local total, missing = Disenchant.Value(Disenchant.Outcomes(2, 28, false), function(id)
        return prices[id]
    end)
    eq(total, 0.75 * 1.5 * 100 + 0.2 * 1.5 * 1000 + 0.05 * 2000, "disenchant: average value")
    eq(missing, 0, "disenchant: every outcome priced")
    prices[11084] = nil
    total, missing = Disenchant.Value(Disenchant.Outcomes(2, 28, false), function(id)
        return prices[id]
    end)
    eq(total, 0.75 * 1.5 * 100 + 0.2 * 1.5 * 1000, "disenchant: unpriced outcome left out")
    eq(missing, 1, "disenchant: counts the outcome with no price")
end

-- Auctionator's prices, while the player chose them and it's loaded.
local chooseAuctionator = false
Prices.SetSource({
    price = function(itemID)
        if itemID == 4305 then
            return 120, 1000
        end
    end,
    itemByName = function() end,
    inline = function()
        return false
    end,
    auctionator = function()
        return chooseAuctionator
    end,
})
local ownPrice, ownSeen = Prices.Auction(4305)
eq(ownPrice, 120, "auctionator: our price while it isn't chosen")
eq(ownSeen, 1000, "auctionator: and when ours was seen")
chooseAuctionator = true
eq(Prices.AuctionatorLoaded(), false, "auctionator: not loaded")
eq(Prices.UsingAuctionator(), false, "auctionator: chosen but not loaded")
eq(Prices.Auction(4305), 120, "auctionator: our price while it isn't loaded")
local callers = {}
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, itemID)
        callers[#callers + 1] = caller
        if type(itemID) ~= "number" then
            error("bad item ID")
        end
        return ({ [4305] = 300, [10940] = 50, [10938] = 200 })[itemID]
    end,
} } }
game.clock = 10 * 86400
eq(Prices.AuctionatorLoaded(), true, "auctionator: loaded")
eq(Prices.UsingAuctionator(), true, "auctionator: in use")
local theirPrice, theirSeen = Prices.Auction(4305)
eq(theirPrice, 300, "auctionator: its price")
eq(theirSeen, nil, "auctionator: no age without its age call")
eq(callers[1], "Forever++", "auctionator: our caller ID")
eq(Prices.Auction(2589), nil, "auctionator: an item it has no price for")
eq(Prices.Auction("x"), nil, "auctionator: its error is caught")
Auctionator.API.v1.GetAuctionAgeByItemID = function(_, itemID)
    return itemID == 4305 and 2 or nil
end
theirPrice, theirSeen = Prices.Auction(4305)
eq(theirSeen, 8 * 86400, "auctionator: seen its age in days ago")
theirPrice, theirSeen = Prices.Auction(10940)
eq(theirPrice, 50, "auctionator: a price without an age")
eq(theirSeen, nil, "auctionator: and no age for it")
-- Disenchant prices its materials through Prices.Auction: 0.8 x 1.5 x 50 + 0.2 x 1.5 x 200.
local deValue, deMissing = ns.Disenchant.Value(ns.Disenchant.Outcomes(2, 5, false), Prices.Auction)
eq(deValue, 0.8 * 1.5 * 50 + 0.2 * 1.5 * 200, "auctionator: disenchant value from its prices")
eq(deMissing, 0, "auctionator: every disenchant outcome priced")
chooseAuctionator = false
eq(Prices.Auction(4305), 120, "auctionator: back to ours when it's turned off")
chooseAuctionator = true
Prices.SetSource(nil)
eq(Prices.UsingAuctionator(), false, "auctionator: not in use without a source")
eq(Prices.Auction(4305), nil, "auctionator: no prices without a source")
Auctionator = nil

-- Saved prices ------------------------------------------------------------------------------------

local packed = Prices.Pack(4800, 1791836472)
eq(packed, "4800,1530607", "prices: a saved price is copper and minutes")
local copper, seenAt = Prices.Unpack(packed)
eq(copper, 4800, "prices: unpacked copper")
eq(seenAt, 1791836420, "prices: unpacked time, to the minute")
eq(Prices.Pack(10000000000, 1792175033), "10000000000,1536250", "prices: a price past 2^31 copper")
eq((Prices.Unpack(Prices.Pack(10000000000, 1792175033))), 10000000000,
    "prices: a price past 2^31 copper comes back")
eq(Prices.Unpack(nil), nil, "prices: nothing saved")
eq(Prices.Unpack({ price = 1 }), nil, "prices: an old table isn't a saved price")
copper, seenAt = Prices.Unpack(Prices.Pack(700, 0))
eq(copper, 700, "prices: a price seen before the epoch keeps its copper")
eq(seenAt <= 0, true, "prices: and a time before the epoch")

-- A house from 0.7.0 to 0.8.4, and one from before 0.7.0.
local newer = { scannedAt = 1791836000, items = { [1] = { price = 50, seenAt = 1791836472 },
    [2] = "60,1530600", [3] = { broken = true } } }
Prices.PackHouse(newer)
eq(newer.items[1], Prices.Pack(50, 1791836472), "prices: a saved table is packed")
eq(newer.items[2], "60,1530600", "prices: a packed price stays")
eq(newer.items[3], nil, "prices: a broken entry goes")
local older = { scannedAt = 1790781485, prices = { [7] = 4800, [8] = 700 } }
Prices.PackHouse(older)
eq(older.prices, nil, "prices: the old price list goes")
copper, seenAt = Prices.Unpack(older.items[7])
eq(copper, 4800, "prices: an old price is kept")
eq(math.abs(seenAt - 1790781485) < 60, true, "prices: aged from the house's scan")
local unscanned = { prices = { [7] = 4800 } }
Prices.PackHouse(unscanned)
eq(unscanned.prices, nil, "prices: an unscanned house's old list goes")
eq(unscanned.items[7], nil, "prices: and its prices with it, having no age")
local zeroScan = { scannedAt = 0, prices = { [7] = 4800 } }
Prices.PackHouse(zeroScan)
eq(zeroScan.items[7], nil, "prices: a house scanned at 0 drops its old prices")

-- Hold Shift to Skip checkboxes become key dropdowns.
local shiftSaved = { AutoGossip = { shiftSkips = false }, AutoRepair = { shiftSkips = true } }
ns.Keys.MigrateShift(shiftSaved, "AutoGossip", "shiftSkips", "skipKey")
ns.Keys.MigrateShift(shiftSaved, "AutoRepair", "shiftSkips", "skipKey")
ns.Keys.MigrateShift(shiftSaved, "AutoSellJunk", "shiftSkips", "skipKey")
eq(shiftSaved.AutoGossip.skipKey, "none", "keys: an unticked checkbox is None")
eq(shiftSaved.AutoRepair.skipKey, "shift", "keys: a ticked checkbox is Shift")
eq(shiftSaved.AutoRepair.shiftSkips, nil, "keys: the checkbox goes")
eq(shiftSaved.AutoSellJunk, nil, "keys: nothing saved, nothing made")

-- Store -----------------------------------------------------------------------------------------

local Store = ns.Store

-- A fresh install is current at once and runs no steps.
local ran = {}
Store.Step(1, function(db) ran[#ran + 1] = "1:" .. tostring(db.modules ~= nil) end)
Store.Step(2, function(db)
    ran[#ran + 1] = "2"
    Store.Split(db, { TalentPlanner = { builds = true } })
end)
Store.Step(3, function(db)
    ran[#ran + 1] = "3"
    Store.Rename(db, { BagSlots = "BagSlotCounter" })
end)
Store.CharacterStep(2, function(char, db)
    Store.Claim(char, db, "TalentPlanner", "builds", function(entries)
        local mine = entries["G-1"] and { [1] = entries["G-1"] }
        entries["G-1"] = nil
        return mine
    end)
end)
local freshDB, freshChar = {}, {}
eq(Store.Upgrade(freshDB, freshChar), true, "store: empty saved variables are a fresh install")
eq(#ran, 0, "store: a fresh install runs no account steps")
eq(freshDB.version, Store.VERSION, "store: a fresh install is current")
eq(freshChar.version, Store.VERSION, "store: a fresh character is current")

-- The 0.8 layout: every setting and table in `modules`, under the old names.
local oldDB = { seenModules = { BagSlots = "0.8.2" }, modules = {
    BagSlots = { enabled = true, size = "large", position = "top" },
    TalentPlanner = { enabled = true, builds = { ["G-1"] = { active = 1 }, ["H-1"] = { active = 2 } } },
} }
local oldChar = {}
eq(Store.Upgrade(oldDB, oldChar), false, "store: saved settings aren't a fresh install")
eq(table.concat(ran, ","), "1:true,2,3", "store: steps run in version order, version 1 on the old layout")
eq(oldDB.modules, nil, "store: the old layout is gone")
eq(oldDB.settings.BagSlotCounter.position, "top", "store: settings follow a renamed module")
eq(oldDB.settings.BagSlots, nil, "store: the old name is gone")
eq(oldDB.seenModules.BagSlotCounter, "0.8.2", "store: the version a module was seen in follows it")
eq(oldChar.data.TalentPlanner.builds[1].active, 1, "store: a character takes its own data")
eq(oldDB.unclaimed.TalentPlanner.builds["H-1"].active, 2, "store: another character's data waits")
ran = {}
Store.Upgrade(oldDB, oldChar)
eq(#ran, 0, "store: each step runs once")

-- What a module reads and writes.
local defaults = { enabled = true, size = "large", position = "bottomright", banks = {}, seen = { list = {} } }
oldDB.settings.BagSlotCounter.stale = 5
oldDB.data.BagSlotCounter = { gone = {} }
local view = Store.Load(oldDB, oldChar, "BagSlotCounter", defaults)
local settings = oldDB.settings.BagSlotCounter
eq(view.size, "large", "store: a setting reads its default")
eq(settings.size, nil, "store: a setting equal to its default isn't saved")
eq(settings.stale, nil, "store: a setting the defaults dropped is cleared")
eq(view.position, "top", "store: a changed setting reads what was chosen")
view.position = "bottomright"
eq(settings.position, nil, "store: setting a value back to its default forgets it")
view.size = "huge"
eq(settings.size, "huge", "store: a changed setting is saved")
eq(type(view.banks), "table", "store: data reads its table")
eq(oldDB.data.BagSlotCounter.banks, view.banks, "store: data is saved apart from settings")
eq(type(view.seen.list), "table", "store: data is filled with its default tables")
eq(oldDB.data.BagSlotCounter.gone, nil, "store: data the defaults dropped is cleared")
local plans = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} }, { builds = true })
eq(plans.builds[1].active, 1, "store: per-character data reads the character's table")
plans.builds[2] = { active = 3 }
eq(oldChar.data.TalentPlanner.builds[2].active, 3, "store: per-character data is saved for the character")
-- A key moved out of perCharacter takes the character's data to the account, and back.
local moved = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} })
eq(moved.builds[2].active, 3, "store: data moved to the account keeps what the character had")
eq(oldChar.data.TalentPlanner.builds, nil, "store: data moved to the account leaves the character")
moved = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} }, { builds = true })
eq(moved.builds[2].active, 3, "store: data moved back to the character comes along")
oldDB.unclaimed.Gone = { list = { a = {} } }
Store.Prune(oldDB, oldChar, { BagSlotCounter = true })
eq(oldDB.settings.TalentPlanner, nil, "store: a module that's gone loses its settings")
eq(oldDB.unclaimed.Gone, nil, "store: a module that's gone loses its unclaimed data")
view.size = "large"
Store.Tidy(oldDB, oldChar)
eq(oldDB.settings.BagSlotCounter, nil, "store: tidy drops a module with no changed settings")
eq(oldDB.data.BagSlotCounter, nil, "store: tidy drops data with nothing collected")
view.position = "top"
eq(oldDB.settings.BagSlotCounter.position, "top", "store: a write after tidy is saved again")
eq(type(view.seen.list), "table", "store: data after tidy is made again")
view.banks.x = 1
eq(oldDB.data.BagSlotCounter.banks.x, 1, "store: data made again is saved")

-- GameData --------------------------------------------------------------------------------------

local GameData = ns.GameData
local savedDB = ns.db
ns.db = nil -- before the saved variables load
local nodes = GameData.New("testNodes", { Peacebloom = { 182, 1 } })
eq(nodes:Get("Peacebloom")[2], 1, "game data: seed read")
eq(nodes:Get("Dreamfoil"), nil, "game data: unknown is nil")
eq(nodes:Learn("Dreamfoil", { 182, 270 }), true, "game data: learning something new changes it")
eq(nodes:Get("Dreamfoil")[2], 270, "game data: learned before login is kept in memory")
ns.db = {}
eq(nodes:Get("Dreamfoil")[2], 270, "game data: early learning moves to the saved table")
eq(ns.db.gameData.testNodes.values.Dreamfoil[2], 270, "game data: saved by set name")
eq(nodes:Learn("Dreamfoil", { 182, 270 }), false, "game data: learning the same is no change")
eq(nodes:Learn("Peacebloom", { 182, 5 }), true, "game data: learned overrides the seed")
eq(nodes:Get("Peacebloom")[2], 5, "game data: learned wins")
nodes:Learn("Peacebloom", { 182, 1 })
eq(ns.db.gameData.testNodes.values.Peacebloom, nil, "game data: learning the seed's value drops ours")
local seen = 0
for _ in nodes:Pairs() do
    seen = seen + 1
end
eq(seen, 2, "game data: pairs merges seed and learned")
eq(nodes:Learned(), 1, "game data: learned count")
GetBuildInfo = function()
    return "1.60.1", "70338", "Oct 1 2026", 16001
end
nodes:Learn("Silverleaf", { 182, 1 })
eq(ns.db.gameData.testNodes.build, "70338", "game data: learned data is tagged with the build")
GetBuildInfo = nil
ns.db.gameData.removedSet = { values = { x = 1 } }
GameData.Prune(ns.db)
eq(ns.db.gameData.removedSet, nil, "game data: a set the addon no longer makes is dropped")
eq(ns.db.gameData.testNodes.values.Silverleaf[2], 1, "game data: prune keeps sets still made")
local empty = GameData.New("testEmpty", { [1] = true })
eq(empty:Get(1), true, "game data: a set that learned nothing reads its seed")
eq(ns.db.gameData.testEmpty, nil, "game data: and saves nothing")
GameData.ForgetAll()
eq(nodes:Get("Dreamfoil"), nil, "game data: forget all")
eq(GameData.Spell(1804, "Pick Lock"), 1804, "game data: single ID passes through")
eq(GameData.Requires("Requires Herbalism (75)"), "Herbalism", "game data: requires skill")
eq(select(2, GameData.Requires("Requires Herbalism (75)")), 75, "game data: requires rank")
eq(GameData.Requires("Requires Level 20"), nil, "game data: other lines aren't requirements")
eq(select(3, GameData.TooltipRequires({ lines = { { leftText = "Requires Mining (1)" },
    { leftText = "|cffff2020Requires Mining (65)|r" } } })), 2,
    "game data: tooltip requirement skips the title and color codes")

-- Instances from the dungeon finder: { name, typeID, subtypeID, minLevel, maxLevel, maxRecLevel,
-- expansion, instance ID } by finder ID, spread into GetLFGDungeonInfo's order.
local finder = {
    [1] = { "The Deadmines", 1, 1, 18, 23, 23, 0, 36 },
    [2] = { "Blackrock Depths", 1, 1, 10, 60, 60, 0, 230 }, -- a whole bracket
    [3] = { "Drowned City", 1, 1, 40, 60, 45, 0, 3100 },
    [4] = { "Sunken Vault", 1, 3, 60, 60, 60, 0, nil },
    [5] = { "Random Classic Dungeon", 6, 1, 15, 60, 60, 0, nil },
    [6] = { "Retail Dungeon", 1, 1, 70, 80, 80, 10, 2600 },
}
GetLFDChoiceOrder = function()
    return { -1, 1, 2, 3, 4, 5, 6 }
end
GetLFGDungeonInfo = function(id)
    local d = finder[id]
    return d[1], d[2], d[3], d[4], d[5], nil, nil, d[6], d[7], nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, d[8]
end
local byKey = Instances.byKey
eq(Instances.Levels(byKey.deadmines, true), "18-23", "finder: levels replace the seed's")
eq(Instances.Levels(byKey.brd, true), "52-60", "finder: a whole bracket keeps the seed's")
eq(ns.db.gameData.instances.values[36].low, 18, "finder: learned for the account")
eq(ns.db.gameData.instances.values[230], nil, "finder: the seed's levels aren't saved")
eq(Instances.ByName("drowned city"), byKey.lfg3100, "finder: adds a dungeon the seed lacks")
eq(Instances.Levels(byKey.lfg3100, true), "40-45", "finder: a new dungeon's levels")
eq(byKey.lfgd4 and byKey.lfgd4[5], true, "finder: a raid without an instance ID")
eq(Instances.ByName("Random Classic Dungeon"), nil, "finder: random dungeons are left out")
eq(Instances.ByName("Retail Dungeon"), nil, "finder: later expansions are left out")
GetLFDChoiceOrder, GetLFGDungeonInfo = nil, nil

-- Herbs and veins: the seed, and what tooltips and loot teach.
local Professions = ns.Professions
eq(Professions.Node("Peacebloom")[3], 2447, "nodes: seed read")
eq(Professions.GatheringLine("Mining"), Professions.MINING, "nodes: English skill name")
eq(Professions.GatheringLine("Skinning"), nil, "nodes: not a gathering line")
eq(Professions.IsTool(2901, 2, 14), true, "tools: Mining Pick from the seed")
eq(Professions.IsTool(99999, 2, 20), true, "tools: any fishing pole")
eq(Professions.IsTool(99999, 2, 7), false, "tools: a sword isn't one")
eq(Professions.LearnRequirement("Friedenskraut", "Herbalism", 1), true, "nodes: learn a new name")
eq(Professions.Node("Friedenskraut")[1], Professions.HERBALISM, "nodes: learned skill line")
eq(Professions.Node("Friedenskraut")[3], nil, "nodes: learned without an item")
eq(Professions.LearnRequirement("Friedenskraut", "Herbalism", 1), false, "nodes: same again is no change")
eq(Professions.LearnRequirement("Copper Vein", "Mining", 1), false, "nodes: seed's requirement isn't saved")
eq(Professions.LearnNodeItem("Friedenskraut", 2447), true, "nodes: learn its item")
eq(Professions.Node("Friedenskraut")[2], 1, "nodes: item keeps the skill")
eq(Professions.LearnNodeItem("Copper Vein", 2835), false, "nodes: a known item stays")
eq(Professions.LearnRequirement("Copper Vein", "Mining", 5), true, "nodes: a changed requirement wins")
eq(Professions.Node("Copper Vein")[3], 2770, "nodes: and keeps the seed's item")
local function itemSkill(id)
    local line, skill = Professions.ItemSkill(id)
    return line and (line .. ":" .. skill) or "nil"
end
eq(itemSkill(2770), Professions.MINING .. ":5", "items: a learned requirement reaches the item")
Professions.ForgetNodes()
eq(Professions.Node("Friedenskraut"), nil, "nodes: forget")
eq(Professions.Node("Copper Vein")[2], 1, "nodes: forget restores the seed")
eq(itemSkill(2447), Professions.HERBALISM .. ":1", "items: herb")
eq(itemSkill(10620), Professions.MINING .. ":245", "items: the lowest vein that gives it")
eq(itemSkill(2835), Professions.MINING .. ":1", "items: a stone")
eq(itemSkill(2589), "nil", "items: not gathered")
ns.db = savedDB

-- Item stats and equipment ----------------------------------------------------------------------

local ItemStats, Equipment, Talents = ns.ItemStats, ns.Equipment, ns.Talents

local stats = ItemStats.Normalize({
    ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 3,
    RESISTANCE0_NAME = 34, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8.5, MADE_UP_STAT = 1, ITEM_MOD_TEXT = "no",
})
eq(stats.STR, 5, "stats: strength")
eq(stats.SP, 5, "stats: two spell power keys add up")
eq(stats.HEAL, 2, "stats: spell power heals too, spell damage doesn't")
eq(stats.ARMOR, 34, "stats: armor is resistance 0")
eq(stats.DPS, 8.5, "stats: weapon dps")
eq(stats.MADE_UP_STAT, nil, "stats: an unknown key isn't a stat")
eq(ItemStats.Unknown()[1], "MADE_UP_STAT", "stats: but is remembered")
eq(#ItemStats.Unknown(), 1, "stats: a non-number isn't remembered")
eq(ItemStats.Normalize(nil).STR, nil, "stats: nothing from nothing")
stats = ItemStats.Normalize({ ITEM_MOD_HIT_RATING_SHORT = 4, ITEM_MOD_CRIT_RATING_SHORT = 14,
    ITEM_MOD_DODGE_RATING_SHORT = 6, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 7 })
near(stats.HIT, 0.4, "stats: hit is a rating, 10 to 1% without the client")
near(stats.SPELLHIT, 0.4, "stats: the one hit counts for spells too")
near(stats.CRIT, 1, "stats: crit is a rating, 14 to 1%")
near(stats.SPELLCRIT, 1, "stats: the one crit counts for spells too")
near(stats.DODGE, 0.5, "stats: dodge is a rating, 12 to 1%")
eq(stats.DEF, 7, "stats: defense is skill points")

-- Which stat a tooltip line is about, from the client's strings (build 70450's, from Gear Probe).
do
    local strings = {
        ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:", ITEM_MOD_SPIRIT = "%c%s Spirit", ITEM_MOD_SPIRIT_SHORT = "Spirit",
        ITEM_MOD_STAMINA = "%c%s Stamina", ITEM_MOD_STAMINA_SHORT = "Stamina",
        ITEM_MOD_HIT_RATING = "Increases your hit by %s.", ITEM_MOD_HIT_RATING_SHORT = "Hit",
        ITEM_MOD_CRIT_RATING = "Increases your critical strike by %s.",
        ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike", RESISTANCE2_NAME = "Fire Resistance",
        ITEM_MOD_SPELL_POWER_SHORT = "Spell Power", ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    }
    for name, text in pairs(strings) do
        _G[name] = text
    end
    local line = ItemStats.LineStat
    eq(line("+6 Spirit"), "SPI", "line stat: an attribute")
    eq(line("-3 Stamina"), "STA", "line stat: a negative one")
    eq(line("+10 Fire Resistance"), "RES_FIRE", "line stat: a resistance by its name")
    eq(line("Durability 59 / 65"), nil, "line stat: not a stat")
    eq(line("(12.6 damage per second)"), nil, "line stat: dps isn't colored")
    local key, effect = line("Equip: Increases your hit by 1%.")
    eq(key, "HIT", "line stat: an Equip: line by its string")
    eq(effect, "Increases your hit by 1%.", "line stat: the effect after Equip:")
    local wand = { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.8 }
    local spell = "Equip: Increases damage and healing done by magical spells and effects by up to 2."
    eq(line(spell, wand), "SP", "line stat: a spell's wording by its number")
    eq(line(spell, nil), nil, "line stat: not without the item's stats")
    eq(line(spell, { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_ATTACK_POWER_SHORT = 2 }), nil,
        "line stat: two stats with the number are left alone")
    eq(line(spell, { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_INTELLECT_SHORT = 2 }), "SP",
        "line stat: an attribute is never an Equip: line's")
    eq(line("Equip: Improves your chance to hit by 1%.", { ITEM_MOD_HIT_RATING_SHORT = 10 }), "HIT",
        "line stat: a rating's percent")
    for name in pairs(strings) do
        _G[name] = nil
    end
end
eq(select(2, ItemStats.RatingRates()).HIT, "seed", "ratings: the seed without the client")
for _, key in ipairs(ItemStats.ORDER) do
    local known = key == "DPS_OFF" or key == "DPS_RANGED"
    for _, ours in pairs(ItemStats.KEYS) do
        if type(ours) == "table" then
            for _, each in ipairs(ours) do
                known = known or each == key
            end
        else
            known = known or ours == key
        end
    end
    eq(known, true, "stats: ORDER key " .. key .. " comes from a game key")
end
eq(ItemStats.Score({ STR = 5, SP = 5, ARMOR = 34 }, { STR = 1, SP = 2 }), 15, "score: weighted sum")
eq(ItemStats.Score({}, { STR = 1 }), 0, "score: nothing")
eq(ItemStats.Slotted({ DPS = 10, STR = 1 }, "INVTYPE_WEAPONOFFHAND").DPS_OFF, 10, "score: off-hand dps")
eq(ItemStats.Slotted({ DPS = 10 }, "INVTYPE_WEAPONOFFHAND").DPS, nil, "score: off-hand dps moved")
eq(ItemStats.Slotted({ DPS = 10 }, "INVTYPE_RANGEDRIGHT").DPS_RANGED, 10, "score: ranged dps")
local plain = { DPS = 10 }
eq(ItemStats.Slotted(plain, "INVTYPE_WEAPON"), plain, "score: main hand dps stays")
local up, percent = ItemStats.Compare(110, 100, 0)
eq(up, true, "compare: better is an upgrade")
near(percent, 10, "compare: by ten percent")
eq(ItemStats.Compare(105, 100, 10), false, "compare: under the threshold")
eq(ItemStats.Compare(100, 100, 0), false, "compare: the same isn't")
up, percent = ItemStats.Compare(5, 0, 0)
eq(up, true, "compare: anything beats an empty slot")
eq(percent, nil, "compare: with no percentage")
eq(ItemStats.Compare(0, 0, 0), false, "compare: nothing doesn't")

eq(Equipment.Slots("INVTYPE_FINGER")[2], 12, "slots: second ring")
eq(Equipment.Slots("INVTYPE_ROBE")[1], 5, "slots: a robe is the chest")
eq(Equipment.Slots("INVTYPE_BAG"), nil, "slots: a bag isn't gear")
eq(Equipment.Slots(""), nil, "slots: nothing isn't gear")
game.worn = { [11] = "ring1", [12] = "ring2", [16] = "main", [17] = "off" }
game.cachedItems.off = { 2, "Weapon", "Daggers", "INVTYPE_WEAPON", 0, 2, 15 }
local function wornOf(slot)
    return game.worn[slot]
end
local rivals = Equipment.RuleRivals("INVTYPE_FINGER", wornOf)
eq(#rivals, 2, "rivals: either ring")
eq(rivals[1][1], "ring1", "rivals: the first ring")
eq(rivals[2][1], "ring2", "rivals: the second ring")
rivals = Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf)
eq(#rivals, 1, "rivals: a two-hander has one alternative")
eq(#rivals[1], 2, "rivals: both hands")
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: a one-hander without dual wield is the main hand")
eq(rivals[1][1], "main", "rivals: the main hand")
game.dualWield = true
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 2, "rivals: dual wielding, either hand")
eq(rivals[2][1], "off", "rivals: the off hand")
game.worn[17] = nil
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 2, "rivals: dual wielding with an empty off hand still offers it")
eq(#rivals[2], 0, "rivals: as an empty alternative")
game.dualWield = false
rivals = Equipment.RuleRivals("INVTYPE_HEAD", wornOf)
eq(#rivals[1], 0, "rivals: an empty slot is an empty alternative")
eq(#Equipment.RuleRivals("INVTYPE_TABARD", wornOf), 0, "rivals: not gear, no alternatives")
-- What's worn is read by type: a worn two-hander fills the off hand too.
game.worn[17] = nil
game.cachedItems.great = { 3, "Weapon", "Two-Handed Swords", "INVTYPE_2HWEAPON", 0, 2, 8 }
game.worn[16] = "great"
eq(Equipment.WornType(16), "INVTYPE_2HWEAPON", "worn type: read from the worn item")
eq(Equipment.WornType(17), nil, "worn type: nil for an empty slot")
rivals = Equipment.RuleRivals("INVTYPE_SHIELD", wornOf)
eq(#rivals, 1, "rivals: a shield with a two-hander worn has one alternative")
eq(rivals[1][1], "great", "rivals: the two-hander, not an empty off hand")
game.dualWield = true
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: dual wielding with a two-hander worn, a one-hander replaces it")
eq(rivals[1][1], "great", "rivals: the two-hander")
game.worn[16] = "main"
game.cachedItems.shield = { 4, "Armor", "Shields", "INVTYPE_SHIELD", 0, 4, 6 }
game.worn[17] = "shield"
eq(Equipment.WornType(17), "INVTYPE_SHIELD", "worn type: a shield")
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: dual wielding with a shield worn, a one-hander is the main hand")
game.worn[17] = nil
rivals = Equipment.RuleRivals("INVTYPE_SHIELD", wornOf)
eq(#rivals[1], 0, "rivals: a shield with a one-hander worn takes the empty off hand")
game.dualWield = false
game.worn[17] = "off"
eq(Equipment.IsWorn("main"), true, "worn: by link")
eq(Equipment.IsWorn("other"), false, "worn: not by link")
eq(Equipment.LinkKey("|cnIQ2:|Hitem:6541::::::::19:1482:::1:12734::::::|h[Willow Gloves of Magic]|h|r"),
    "item:6541::::::::19:1482:::1:12734", "link key: the item with its suffix, without the tail")
eq(Equipment.LinkKey("item:6541::::::::19:1482:::1:12734:::::"), "item:6541::::::::19:1482:::1:12734",
    "link key: a bare link reads the same")
eq(Equipment.LinkKey("item:6541") == Equipment.LinkKey("item:6541::::::::19:1482:::1:12734"), false,
    "link key: the base item isn't the suffixed one")
game.worn[10] = "|cnIQ2:|Hitem:6541::::::::19:1482:::1:12734::::::|h[Willow Gloves of Magic]|h|r"
eq(Equipment.IsWorn("item:6541::::::::19:1482:::1:12734:::::"), true, "worn: a tooltip's link to the worn item")
eq(Equipment.IsWorn("item:6541"), false, "worn: not the base item")
eq(Equipment.IsWornGUID("Item-4618-0-4000000081C35317"), false, "worn guid: nothing without the item API")
eq(Equipment.Worn(11), "ring1", "worn: a slot's link")
eq(Equipment.CanDualWield(), false, "dual wield: off")
eq(Equipment.CanUse("item:1", 10), true, "can use: a level 30 can wear level 10 gear")
eq(Equipment.CanUse("item:1", 31), false, "can use: not level 31 gear")
local text = ItemStats.WeightString("Forever++ Frost (Mage)", "MAGE", "Frost",
    { INT = 0.35, SP = 1, SPELLHIT = 10, STA = 0, DPS_RANGED = 1.2 })
eq(text, '( Pawn: v1: "Forever++ Frost (Mage)": Class=Mage, Spec=Frost, Intellect=0.35, SpellPower=1, '
    .. 'SpellHitRating=10, RangedDps=1.2 )', "weight string: written in order, zeros left out")
local parsed, name, unknown = ItemStats.ParseWeightString(text)
eq(parsed and parsed.INT, 0.35, "weight string: read back")
eq(parsed and parsed.DPS_RANGED, 1.2, "weight string: ranged dps read back")
eq(name, "Forever++ Frost (Mage)", "weight string: its name")
eq(#unknown, 0, "weight string: nothing unknown")
parsed, name, unknown = ItemStats.ParseWeightString(' (Pawn:v1:"x": spelldamage = 2, Crit=3, MadeUp=4, Class=Rogue) ')
eq(parsed and parsed.SP, 2, "weight string: an alias and loose spacing")
eq(parsed and parsed.CRIT, 3, "weight string: a short name")
eq(unknown[1], "MadeUp", "weight string: an unknown stat is reported")
eq(ItemStats.ParseWeightString("hello"), nil, "weight string: not one")
eq(select(2, ItemStats.ParseWeightString("hello")), "format", "weight string: says why")
eq(ItemStats.ParseWeightString('( Pawn: v1: "x": )'), nil, "weight string: empty is not one")
local derived = ItemStats.DeriveAttributes({ AP = 0.5, RAP = 0.5, CRIT = 8, DODGE = 10, ARMOR = 0.05,
    HEALTH = 0.12, SPELLCRIT = 7, MANA = 0.02 },
    { AP_STR = 2, AP_AGI = 0, RAP_AGI = 2, CRIT_AGI = 0.05, DODGE_AGI = 0.05, ARMOR_AGI = 2, HEALTH_STA = 10,
        SPELLCRIT_INT = 0.0167, MANA_INT = 15 })
near(derived.STR, 1, "derived: strength from attack power")
near(derived.AGI, 2, "derived: agility from ranged attack power, crit, dodge, and armor")
near(derived.STA, 1.2, "derived: stamina from health")
near(derived.INT, 0.42, "derived: intellect from spell crit and mana, rounded")
derived = ItemStats.DeriveAttributes({ AP = 1 }, { AP_STR = 2 })
near(derived.STR, 2, "derived: strength alone")
eq(derived.AGI, nil, "derived: no agility without its rates")
eq(next(ItemStats.PlayerRates()) ~= nil, true, "rates: the flat armor rule is always there")
eq(ItemStats.PlayerRates().AP_STR, nil, "rates: nothing without the game's functions")
derived = ItemStats.DeriveAttributes({ AP = 0.25, BLOCKVALUE = 0.3 }, { AP_STR = 2, BLOCKVALUE_STR = 0.05 })
near(derived.STR, 0.52, "derived: strength's block value counts, rounded")
do
    -- The character sheet's functions answer 0 to 1 for the player's own points (stub: 25 Agility,
    -- 60 Intellect, 1% crit per 20 Agility, 1% dodge per 20, 1% spell crit per 60 Intellect).
    local saved = { UnitStat, GetCritChanceFromStat, GetDodgeChanceFromAttribute, GetSpellCritChanceFromStat,
        BLOCK_VALUE_PER_STRENGTH }
    local points = { [2] = 25, [4] = 60 }
    UnitStat = function(_, stat)
        return points[stat] or 10, points[stat] or 10
    end
    GetCritChanceFromStat = function(_, value)
        return value / 20 / 100
    end
    GetDodgeChanceFromAttribute = function(...)
        assert(select("#", ...) == 0, "dodge takes no arguments")
        return 25 / 20 / 100
    end
    GetSpellCritChanceFromStat = function(_, value)
        return value / 60 / 100
    end
    BLOCK_VALUE_PER_STRENGTH = 20
    -- ItemStats caches UnitStat at load, so reload it to see the stub.
    assert(loadfile("ForeverPlusPlus/Lib/ItemStats.lua"))("ForeverPlusPlus", ns)
    local rates = ns.ItemStats.PlayerRates()
    near(rates.CRIT_AGI, 0.05, "rates: crit per Agility in percent")
    near(rates.DODGE_AGI, 0.05, "rates: dodge per Agility in percent")
    near(rates.SPELLCRIT_INT, 1 / 60, "rates: spell crit per Intellect in percent")
    near(rates.BLOCKVALUE_STR, 0.05, "rates: block value per Strength")
    UnitStat, GetCritChanceFromStat, GetDodgeChanceFromAttribute, GetSpellCritChanceFromStat,
        BLOCK_VALUE_PER_STRENGTH = unpack(saved, 1, 5)
    ns.ItemStats = ItemStats
end
eq(Talents.Tabs(), nil, "talents: nothing without the trait API")
local tab, total = Talents.Dominant()
eq(tab, nil, "talents: no dominant tab without data")
eq(total, 0, "talents: no points without data")

-- Quests ----------------------------------------------------------------------------------------

do
    local Quests = ns.Quests
    local log = { [101] = { level = 12 }, [102] = { level = 20, difficultyLevel = 22 },
        [103] = { level = 0 } }
    local order = { 101, 102, 103 }
    C_QuestLog = {
        GetLogIndexForQuestID = function(id)
            for i, questID in ipairs(order) do
                if questID == id then
                    return i
                end
            end
        end,
        GetInfo = function(index) return log[order[index]] end,
        GetSelectedQuest = function() return 102 end,
    }
    GetQuestID = function() return 201 end
    eq(Quests.Level(101), 12, "quests: level from the log")
    eq(Quests.Level(102), 22, "quests: difficulty level first")
    eq(Quests.Level(103), nil, "quests: level 0 is unknown")
    eq(Quests.Level(999), nil, "quests: not in the log")
    eq(Quests.Level(nil), nil, "quests: no quest")
    QuestInfoFrame = { questLog = true }
    eq(Quests.DetailsID(), 102, "quests: details from the quest log")
    QuestInfoFrame.questLog = nil
    eq(Quests.DetailsID(), 201, "quests: details from the quest giver")
    eq(Quests.GiverID(), 201, "quests: the quest giver's quest")
    GetActiveQuestID = function(i) return 300 + i end
    GetActiveLevel = function(i) return 10 + i end
    GetAvailableQuestInfo = function(i) return false, 0, false, false, 400 + i end
    GetAvailableLevel = nil
    local function button(id, active)
        return { isActive = active, GetID = function() return id end }
    end
    local id, level = Quests.GreetingButton(button(2, 1))
    eq(id == 302 and level == 12, true, "quests: an active greeting quest")
    id, level = Quests.GreetingButton(button(3, 0))
    eq(id == 403 and level == nil, true, "quests: an available one without the level function")
    C_QuestLog, GetQuestID, QuestInfoFrame, GetActiveQuestID, GetActiveLevel = nil, nil, nil, nil, nil
    GetAvailableQuestInfo = nil
end

-- Taxi ------------------------------------------------------------------------------------------

do
    local Taxi = ns.Taxi
    local reads = 0
    local nodes, mapID = Taxi.Nodes()
    eq(#nodes == 0 and mapID == nil, true, "taxi: nothing without the API")
    game.now = 1
    C_TaxiMap = {
        GetAllTaxiNodes = function(map)
            reads = reads + 1
            return { { nodeID = map * 10 }, { nodeID = map * 10 + 1 } }
        end,
    }
    GetTaxiMapID = function() return 1414 end
    nodes, mapID = Taxi.Nodes()
    eq(#nodes == 2 and nodes[1].nodeID == 14140 and mapID == 1414, true, "taxi: the master's nodes")
    Taxi.Nodes()
    eq(reads, 1, "taxi: read once in a frame")
    game.now = 2
    GetTaxiMapID = function() return nil end
    nodes, mapID = Taxi.Nodes()
    eq(#nodes == 0 and mapID == nil and reads == 1, true, "taxi: no flight map open")
    C_TaxiMap, GetTaxiMapID = nil, nil
end

-- Core's module lifecycle -----------------------------------------------------------------------
-- The real Core.lua and Lib/Frames.lua in an `ns` of their own, against stub frames (events are
-- fired by hand) and a clock for C_Timer: modules turning on and off, OnWhile, parts with a
-- checkbox or a dropdown, and timers a module owns.

do
    local frames = {}
    local Frame = {}
    Frame.__index = Frame
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:RegisterEvent(event) self.events[event] = true end
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
    function Frame:HookScript() end
    CreateFrame = function()
        local frame = setmetatable({ scripts = {}, events = {} }, Frame)
        frames[#frames + 1] = frame
        return frame
    end

    -- Fires `event` on every frame registered for it, honoring unit filters as the client would.
    local function fire(event, ...)
        local unit = ...
        for _, frame in ipairs(frames) do
            local reg = frame.events[event]
            local pass = reg == true
            if type(reg) == "table" then
                for _, u in ipairs(reg) do
                    pass = pass or u == unit
                end
            end
            if pass then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end

    local function registered(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then
                return true
            end
        end
        return false
    end

    -- C_Timer on a clock that moves only when `wait` says.
    local now, pending = 0, {}
    C_Timer = {
        NewTimer = function(seconds, fn)
            local handle = { at = now + seconds, fn = fn }
            function handle:Cancel() self.cancelled = true end
            pending[#pending + 1] = handle
            return handle
        end,
    }
    local function wait(seconds)
        now = now + seconds
        local due = pending
        pending = {}
        for _, handle in ipairs(due) do
            if handle.at > now then
                pending[#pending + 1] = handle
            elseif not handle.cancelled then
                handle.fn()
            end
        end
    end

    securecallfunction = function(fn, ...) return fn(...) end -- errors fail the run
    hooksecurefunc = function() end
    InCombatLockdown = function() return false end
    GetLocale = function() return "enUS" end
    C_AddOns = { GetAddOnMetadata = function() return "0.9.0" end }
    SlashCmdList = {}
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    strsplit = function(sep, s, limit)
        local parts, from = {}, 1
        while not limit or #parts < limit - 1 do
            local at = s:find(sep, from, true)
            if not at then
                break
            end
            parts[#parts + 1] = s:sub(from, at - 1)
            from = at + #sep
        end
        parts[#parts + 1] = s:sub(from)
        return unpack(parts)
    end

    local core = {}
    for _, path in ipairs({ "Core", "Commands", "Locales/enUS/Core", "Lib/Store", "Lib/Frames", "Lib/Players" }) do
        local chunk = assert(loadfile("ForeverPlusPlus/" .. path .. ".lua"))
        chunk(ADDON, core)
    end
    core.GameData = { Prune = function() end }
    core.Profiler = { recording = false, Wrap = function(_, fn) return fn end }
    core.RefreshSetting = function() end -- Settings/Settings.lua's
    core.OpenSettings = function() return true end
    local Frames = core.Frames

    -- A module with a checkbox and a dropdown option, each driving events through OnWhile.
    local heard = {}
    local function count(key)
        return function() heard[key] = (heard[key] or 0) + 1 end
    end
    local plain = core.NewModule("Plain", "test", { enabled = true, loud = false, mode = "a" })
    plain.options = {
        { key = "loud", name = "Loud" },
        { key = "mode", name = "Mode", choices = { { "a" }, { "b" }, { "off" } } },
    }
    plain:OnWhile("loud", { PLAYER_MONEY = count("money") })
    plain:OnWhile("mode", { BAG_UPDATE = count("bag") })
    plain:OnWhile(function(db) return db.loud and db.mode == "b" end, { ZONE_CHANGED = count("zone") })
    function plain:OnEnable()
        self:On("PLAYER_LEVEL_UP", count("level"))
    end
    local plainTimer = Frames.Timer(plain)
    local plainQueue = Frames.Coalesce(count("coalesced"), 0.1, plain)

    -- A module made of a checkbox part and a dropdown part.
    local host = core.NewModule("Host", "test", { enabled = true })
    local check = host:NewPart({ key = "extra", name = "Extra", section = "S1" }, { loud2 = false })
    check:AddOptions({ { key = "loud2", name = "Loud" } })
    check:OnWhile("loud2", { PLAYER_XP_UPDATE = count("xp") })
    local WHERE = { { "off" }, { "top" }, { "bottom" } }
    local drop = host:NewPart({ key = "where", name = "Where", section = "S2", choices = WHERE },
        { where = "bottom" })
    local dropCalls = { enable = 0, disable = 0, changed = {} }
    function drop:OnEnable() dropCalls.enable = dropCalls.enable + 1 end
    function drop:OnDisable() dropCalls.disable = dropCalls.disable + 1 end
    function drop:OnOptionChanged(key) dropCalls.changed[#dropCalls.changed + 1] = key end
    drop:OnWhile("where", { MAIL_SHOW = count("mail") })
    local dropTimer = Frames.Timer(drop)
    local side = host:NewPart({ key = "side", name = "Side", section = "S3", choices = WHERE })

    eq(host.defaults.extra, true, "lifecycle: a checkbox part defaults to on")
    eq(host.defaults.where, "bottom", "lifecycle: a dropdown part keeps its default")
    eq(host.defaults.side, nil, "lifecycle: a dropdown part isn't defaulted to true")

    ForeverPlusPlusDB, ForeverPlusPlusCharDB = nil, nil
    core.Start()

    -- PartOn: a dropdown's "off" is off, any other choice on.
    for value, want in pairs({ off = false, top = true, [true] = true, [false] = false }) do
        host.db.side = value
        eq(core.PartOn(host, "side"), want, "lifecycle: PartOn " .. tostring(value))
    end
    host.db.side = nil
    eq(core.PartOn(host, "side"), false, "lifecycle: PartOn nil")

    -- OnWhile follows its option, and the module.
    eq(plain.enabled, true, "lifecycle: module on")
    eq(registered("PLAYER_LEVEL_UP"), true, "lifecycle: OnEnable's event")
    eq(registered("PLAYER_MONEY"), false, "lifecycle: OnWhile off with its checkbox")
    eq(registered("BAG_UPDATE"), true, "lifecycle: OnWhile on with its dropdown")
    core.SetOption("Plain", "loud", true)
    eq(registered("PLAYER_MONEY"), true, "lifecycle: checkbox on: listened")
    fire("PLAYER_MONEY")
    eq(heard.money, 1, "lifecycle: OnWhile handler ran")
    core.SetOption("Plain", "loud", false)
    eq(registered("PLAYER_MONEY"), false, "lifecycle: checkbox off: stopped")
    core.SetOption("Plain", "mode", "off")
    eq(registered("BAG_UPDATE"), false, "lifecycle: dropdown off: stopped")
    core.SetOption("Plain", "mode", "b")
    eq(registered("BAG_UPDATE"), true, "lifecycle: dropdown back on: listened")
    eq(registered("ZONE_CHANGED"), false, "lifecycle: OnWhile function false")
    core.SetOption("Plain", "loud", true)
    eq(registered("ZONE_CHANGED"), true, "lifecycle: OnWhile function true")
    for _ = 1, 5 do
        core.SetOption("Plain", "loud", true)
    end
    local n = 0
    for _, entry in ipairs(plain.events) do
        n = n + (entry[1] == "PLAYER_MONEY" and 1 or 0)
    end
    eq(n, 1, "lifecycle: syncing again doesn't pile up events")
    core.SetEnabled("Plain", false)
    eq(registered("PLAYER_MONEY"), false, "lifecycle: module off: OnWhile stopped")
    eq(registered("PLAYER_LEVEL_UP"), false, "lifecycle: module off: its events stopped")
    eq(plain.events, nil, "lifecycle: module off: events cleared")
    core.SetEnabled("Plain", true)
    eq(registered("PLAYER_MONEY"), true, "lifecycle: module back on: saved option listens")
    eq(registered("ZONE_CHANGED"), true, "lifecycle: module back on: OnWhile function listens")

    -- Owned timers stop with the module, and don't run while it's off.
    local ran = 0
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    core.SetEnabled("Plain", false)
    eq(plainTimer:IsPending(), false, "lifecycle: module off: timer cancelled")
    wait(2)
    eq(ran, 0, "lifecycle: cancelled timer didn't run")
    eq(heard.coalesced, nil, "lifecycle: cancelled Coalesce didn't run")
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    wait(2)
    eq(ran, 0, "lifecycle: a timer doesn't run while its module is off")
    eq(heard.coalesced, nil, "lifecycle: a Coalesce doesn't run while its module is off")
    core.SetEnabled("Plain", true)
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    plainQueue()
    wait(2)
    eq(ran, 1, "lifecycle: timer runs while on")
    eq(heard.coalesced, 1, "lifecycle: Coalesce runs once while on")

    -- A checkbox part: on with its checkbox, and its OnWhile follows its own option.
    eq(check.enabled, true, "lifecycle: checkbox part on")
    core.SetOption("Host", "loud2", true)
    eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part option on: listened")
    core.SetOption("Host", "extra", false)
    eq(check.enabled, false, "lifecycle: checkbox part off")
    eq(registered("PLAYER_XP_UPDATE"), false, "lifecycle: part off: OnWhile stopped")
    core.SetOption("Host", "extra", true)
    eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part back on: OnWhile listens")

    -- A dropdown part: on for any choice but "off", told when it moves between them.
    eq(drop.enabled, true, "lifecycle: dropdown part on at its default")
    eq(side.enabled or false, false, "lifecycle: dropdown part without a value is off")
    eq(registered("MAIL_SHOW"), true, "lifecycle: dropdown part's OnWhile")
    core.SetOption("Host", "where", "top")
    eq(drop.enabled, true, "lifecycle: dropdown part stays on between choices")
    eq(dropCalls.enable, 1, "lifecycle: not enabled again between choices")
    eq(dropCalls.changed[#dropCalls.changed], "where", "lifecycle: told its choice changed")
    dropTimer:Start(1, function() ran = ran + 10 end)
    core.SetOption("Host", "where", "off")
    eq(drop.enabled, false, "lifecycle: dropdown part off at \"off\"")
    eq(dropCalls.disable, 1, "lifecycle: dropdown part disabled once")
    eq(registered("MAIL_SHOW"), false, "lifecycle: dropdown part off: OnWhile stopped")
    wait(2)
    eq(ran, 1, "lifecycle: a part's timer stops with the part")
    core.SetOption("Host", "where", "bottom")
    eq(drop.enabled, true, "lifecycle: dropdown part back on")
    eq(dropCalls.enable, 2, "lifecycle: dropdown part enabled again")
    core.SetEnabled("Host", false)
    eq(drop.enabled, false, "lifecycle: module off: its parts off")
    eq(registered("MAIL_SHOW"), false, "lifecycle: module off: part's OnWhile stopped")
    core.SetEnabled("Host", true)
    eq(drop.enabled and check.enabled, true, "lifecycle: module on: its parts on")

    -- /fpp set and the presets (Commands.lua) go through the same paths.
    local fpp = SlashCmdList.FOREVERPLUSPLUS
    core.Print = function() end
    fpp("set Plain mode off")
    eq(plain.db.mode, "off", "commands: /fpp set takes a choice key")
    eq(registered("BAG_UPDATE"), false, "commands: /fpp set tells the module")
    fpp("toggle Plain loud")
    eq(plain.db.loud, false, "commands: /fpp toggle flips a checkbox")
    fpp("toggle Host")
    eq(host.enabled, false, "commands: /fpp toggle <module> turns it off")
    core.SetOption("Plain", "loud", true)
    core.ApplyPreset()
    eq(plain.db.loud == false and plain.db.mode == "a", true, "commands: preset resets options")
    eq(registered("PLAYER_MONEY") or not registered("BAG_UPDATE"), false,
        "commands: preset tells the module")
    eq(host.enabled, true, "commands: preset turns default-on modules back on")
    local said, ran = nil, false
    core.Print = function(text) said = text end
    core.AddCommand("ping", "", "test", function() ran = true end, "Plain")
    core.SetEnabled("Plain", false)
    fpp("ping")
    eq(not ran and said ~= nil and said:find("/fpp ping", 1, true) ~= nil, true,
        "commands: a command whose module is off says so")
    core.SetEnabled("Plain", true)
    fpp("ping")
    eq(ran, true, "commands: and runs once it's on")
end

-- Players ---------------------------------------------------------------------------------------

do
    local savedSecret = game.secret
    game.secret = "<secret>"
    local units = {
        player = { guid = "Player-1-AAAA", name = "Me", class = "MAGE", race = "Human", level = 30 },
        target = { guid = "Player-1-BBBB", name = "Bob", surname = "Stone", class = "WARRIOR",
            race = "Orc", level = 42, guild = "Red", visible = true },
        mouseover = { guid = "Player-1-CCCC", name = game.secret, class = "ROGUE", level = 10 },
    }
    UnitIsPlayer = function(unit) return units[unit] ~= nil end
    UnitGUID = function(unit) return units[unit] and units[unit].guid end
    UnitName = function(unit) return units[unit] and units[unit].name, units[unit] and units[unit].surname end
    UnitClass = function(unit) return "Localized", units[unit] and units[unit].class end
    UnitRace = function(unit) return units[unit] and units[unit].race end
    UnitIsVisible = function(unit) return units[unit] and units[unit].visible end
    GetGuildInfo = function(unit) return units[unit] and units[unit].guild end
    local savedUnitLevel = UnitLevel
    UnitLevel = function(unit) return units[unit] and units[unit].level end
    GetPlayerInfoByGUID = function(guid)
        if guid == "Player-2-DDDD" then
            return "Priest", "PRIEST", "Dwarf", "Dwarf", 2, "Dee", "Classic Beta PvP"
        elseif guid == "Player-9-BBBB" then
            return "Mage", "MAGE", "Gnome", "Gnome", 2, "Bob", "Classic Beta PvP"
        elseif guid == "Player-5-BBBB" then
            return "Warrior", "WARRIOR", "Orc", "Orc", 2, "Bob", ""
        end
    end
    GetRealmName = function() return "Classic Beta PvE" end
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PRIEST = "Priest" }
    LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Warrior", PRIEST = "Priest" }
    local savedTime = time
    time = function() return game.clock end
    load("ForeverPlusPlus/Lib/Players.lua")
    local Players = ns.Players
    ns.playersDB = {}
    local all = ns.playersDB
    game.clock = 1799999960 -- on a whole minute of the saved times

    local packed = Players.Pack({ class = "MAGE", level = 60, race = "Gnome", guild = "A, B", seen = game.clock })
    local entry = Players.Unpack(packed)
    eq(entry.class .. entry.level .. entry.race .. entry.guild, "MAGE60GnomeA, B", "players: pack round trip")
    eq(entry.seen, game.clock, "players: seen kept to the minute")
    eq(Players.Unpack("nonsense"), nil, "players: junk is no entry")
    eq(Players.Unpack(Players.Pack({ seen = game.clock })).class, nil, "players: empty fields read nil")

    eq(Players.Get(nil, "Bob"), nil, "players: nobody seen yet")
    eq(next(all), nil, "players: nothing saved until something is learned")
    Players.LearnUnit("target")
    local bob = Players.Get(nil, "Bob-Stone")
    eq(bob and bob.class, "WARRIOR", "players: unit class kept")
    eq(bob and bob.level, 42, "players: unit level kept")
    eq(bob and bob.guild, "Red", "players: unit guild kept")
    eq(bob and bob.race, "Orc", "players: unit race kept")
    eq(Players.Get("Player-1-BBBB", "bob") ~= nil, true, "players: found by GUID and lowercase name")
    eq(all.ClassicBetaPvE ~= nil, true, "players: kept under the realm's name")
    eq(Players.Get("Player-9-BBBB", "Bob"), nil, "players: another realm is someone else")
    eq(Players.Get("Player-5-BBBB", nil) ~= nil, true, "players: another realm ID of the same realm is the same")
    Players.LearnUnit("mouseover")
    eq(next(all.ClassicBetaPvE) ~= nil and Players.Get("Player-1-CCCC", nil), nil,
        "players: a secret name isn't kept")

    game.clock = game.clock + 7200
    Players.Learn(nil, "Bob", { level = 43 })
    bob = Players.Get(nil, "Bob")
    eq(bob.level .. bob.class .. bob.guild, "43WARRIORRed", "players: newer level, the rest kept")
    eq(bob.seen, game.clock, "players: seen time moves")
    Players.Learn(nil, "Bob", { level = game.secret, class = game.secret })
    eq(Players.Get(nil, "Bob").level, 43, "players: a secret level is skipped")
    units.target.guild, units.target.visible = nil, false
    Players.LearnUnit("target")
    eq(Players.Get(nil, "Bob").guild, "Red", "players: no guild from far away keeps the old one")
    units.target.visible = true
    game.clock = game.clock + 7200
    Players.LearnUnit("target")
    eq(Players.Get(nil, "Bob").guild, nil, "players: no guild up close clears it")

    game.clock = game.clock + 60
    Players.Learn("Player-2-DDDD", nil, {})
    local dee = Players.Get("Player-2-DDDD", nil)
    eq(dee and dee.class, "PRIEST", "players: class from the GUID")
    eq(dee and dee.race, "Dwarf", "players: race from the GUID")
    eq(all.ClassicBetaPvP ~= nil, true, "players: kept under the GUID's realm")
    eq(Players.ClassToken("Warrior"), "WARRIOR", "players: class token from its name")
    eq(Players.ClassName("PRIEST"), "Priest", "players: class name from its token")

    -- Old entries go at login, and the oldest past the limit.
    all.ClassicBetaPvE.old = Players.Pack({ level = 5, seen = game.clock - Players.MAX_AGE - 60 })
    all.Junk = { junk = 5 }
    Players.Prune(all)
    eq(all.ClassicBetaPvE.old, nil, "players: unseen too long is dropped")
    eq(all.Junk, nil, "players: junk and empty realms are dropped")
    eq(Players.Get(nil, "Bob") ~= nil, true, "players: recent ones stay")
    Players.Prune(all, 1)
    eq(Players.Get(nil, "Bob") == nil and Players.Get("Player-2-DDDD", nil) ~= nil, true,
        "players: past the limit, only the newest stay")
    Players.Prune(all, 0)
    eq(next(all), nil, "players: an emptied realm is dropped")
    ns.playersDB = nil
    eq(Players.Get(nil, "Bob"), nil, "players: nothing to read before login")
    UnitLevel, time, game.secret = savedUnitLevel, savedTime, savedSecret
end

-- Public API ------------------------------------------------------------------------------------
-- API.lua against the Lib files loaded above, with the few things it needs from Core stubbed.

do
    local reported = {}
    geterrorhandler = function()
        return function(err)
            reported[#reported + 1] = err
        end
    end
    local seenPlayers = {
        bob = { class = "MAGE", level = 42, race = "Gnome", guild = "Tinkers", seen = 5000 },
    }
    local api = setmetatable({
        modules = {
            ItemTooltips = { title = "Item Tooltips", category = "items", enabled = true },
            Gone = { title = "Gone", unavailable = true },
        },
        order = { "ItemTooltips", "Gone" },
        version = "1.0.0",
        Frames = { Coalesce = function(fn) return fn end }, -- runs at once, so tests see each call
        Players = {
            Get = function(_, name)
                return name and seenPlayers[name:lower():match("^[^%-]+")]
            end,
            ClassName = function(token)
                return token == "MAGE" and "Mage" or nil
            end,
        },
    }, { __index = ns })
    assert(loadfile("ForeverPlusPlus/API.lua"))(ADDON, api)
    local v1 = ForeverPlusPlusAPI.v1

    local apiVersion, addonVersion = v1.GetVersion()
    eq(apiVersion, 1, "api: version 1")
    eq(addonVersion, "1.0.0", "api: addon version")
    eq(pcall(function() ForeverPlusPlusAPI.v1.GetVersion = nil end), false, "api: v1 is read only")
    eq(pcall(function() ForeverPlusPlusAPI.v2 = {} end), false, "api: the root is read only")

    eq(v1.IsModuleEnabled("ItemTooltips"), true, "api: a module that's on")
    eq(v1.IsModuleEnabled("Nope"), nil, "api: a module that isn't there")
    local listed = v1.GetModules()
    eq(#listed, 1, "api: modules leave out unavailable ones")
    eq(listed[1].title, "Item Tooltips", "api: a module's title")

    -- Prices, and the callback that says they changed.
    local updates = 0
    v1.RegisterCallback("PRICES_UPDATED", function() updates = updates + 1 end, "test")
    eq(v1.HasAuctionPrices(), false, "api: no prices without a source")
    eq(v1.GetAuctionPrice(4305), nil, "api: no price without a source")
    eq(v1.GetAuctionPriceSource(), nil, "api: no source")
    ns.Prices.SetSource({
        price = function(itemID)
            if itemID == 4305 then
                return 120, 1000
            elseif itemID == 666 then
                error("broken source")
            end
        end,
        itemByName = function(name)
            return name == "Bolt of Silk Cloth" and 4305 or nil
        end,
        inline = function() return false end,
        auctionator = function() return false end,
    })
    eq(updates, 1, "api: a new source tells PRICES_UPDATED")
    eq(v1.GetAuctionPriceSource(), "ForeverPlusPlus", "api: our own prices")
    local price, seen = v1.GetAuctionPrice(4305)
    eq(price, 120, "api: price by ID")
    eq(seen, 1000, "api: and when it was seen")
    eq((v1.GetAuctionPrice("|cffffffff|Hitem:4305::::::::60:::::|h[Bolt of Silk Cloth]|h|r")), 120,
        "api: price by link")
    eq((v1.GetAuctionPrice("4305")), 120, "api: price by ID as text")
    eq((v1.GetAuctionPrice("Bolt of Silk Cloth")), 120, "api: price by name")
    eq(v1.GetAuctionPrice({}), nil, "api: nonsense gets nil")
    eq(v1.GetAuctionPrice(666), nil, "api: our error returns nil")
    eq(#reported, 1, "api: and goes to the error handler")
    ns.Prices.Changed()
    eq(updates, 2, "api: changed prices tell PRICES_UPDATED")
    v1.RegisterCallback("PRICES_UPDATED", function() error("caller's bug") end, "broken")
    ns.Prices.Changed()
    eq(updates, 3, "api: one failing callback doesn't stop the others")
    eq(#reported, 2, "api: the failing callback is reported")
    v1.UnregisterCallback("PRICES_UPDATED", "broken")
    v1.UnregisterCallback("PRICES_UPDATED", "test")
    ns.Prices.Changed()
    eq(updates, 3, "api: unregistered callbacks stop")
    eq(v1.RegisterCallback("NOPE", function() end), nil, "api: an unknown event")
    eq(#reported, 3, "api: is reported")
    ns.Prices.SetSource(nil)
    eq(v1.GetDisenchantValue(4305), nil, "api: no disenchant value without prices")

    -- Players seen: a copy, so a caller can't change what's saved.
    local info = v1.GetPlayerInfo("Bob-Surname")
    eq(info and info.class, "MAGE", "api: player class")
    eq(info and info.className, "Mage", "api: player class name")
    eq(info and info.level, 42, "api: player level")
    eq(info and info.lastSeen, 5000, "api: when they were seen")
    info.level = 1
    eq(v1.GetPlayerInfo("Bob").level, 42, "api: player info is a copy")
    eq(v1.GetPlayerInfo("Nobody"), nil, "api: someone never seen")
    eq(v1.GetPlayerInfo(nil, nil), nil, "api: no name, no player")

    -- Colors. The Instances tests above stubbed LevelRange to nil; give it a color again.
    local levelRange = ns.Colors.LevelRange
    ns.Colors.LevelRange = function(low)
        return { r = low / 100, g = 1, b = 0 }
    end
    local r, _, _, hex = v1.GetLevelColor(20, 30)
    eq(r, 0.2, "api: level color")
    eq(hex, "ff33ff00", "api: and its hex")
    ns.Colors.LevelRange = levelRange
    eq((v1.GetLevelColor("x")), nil, "api: a level that isn't a number")
    eq(v1.GetClassColor(nil), nil, "api: no class, no color")

    -- Dungeons and raids.
    local list = v1.GetInstances()
    eq(#list > 20, true, "api: every instance")
    eq(list[1].minLevel <= list[#list].minLevel, true, "api: by lowest level")
    local deadmines = v1.GetInstanceInfo(36)
    eq(deadmines and deadmines.englishName, "The Deadmines", "api: instance by ID")
    eq(deadmines and deadmines.isRaid, false, "api: a dungeon isn't a raid")
    local mc = v1.GetInstanceInfo("molten core")
    eq(mc and mc.isRaid, true, "api: instance by name")
    eq(v1.GetInstanceInfo("Nowhere"), nil, "api: not an instance")

    eq(type(v1.GetSkinningSkill(30)), "number", "api: skinning skill for a level")
    ForeverPlusPlusAPI, geterrorhandler = nil, nil
end

-- Done ------------------------------------------------------------------------------------------

print(("%d checks, %d failed"):format(count, failures))
os.exit(failures == 0 and 0 or 1)
