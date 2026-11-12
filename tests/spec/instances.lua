-- Instances: the seed's dungeons and raids, their names in the player's language, and levels.
local T = ...
local ns, eq, game, player = T.ns, T.eq, T.game, T.player

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
eq(Instances.Levels(Instances.byKey.brd), "Level 48-60", "level range")
eq(Instances.Levels(Instances.byKey.brd, true), "48-60", "compact range")

-- Lowest levels: the finder's from the generated tables, unless kept by hand.
local generated = ns.TableData.instanceLevels
eq(Instances.byKey.uldaman[3], generated[70], "lowest level from the generated tables")
eq(Instances.byKey.zulfarrak[3], generated[209], "Zul'Farrak matched despite the finder's spelling")
eq(Instances.byKey.shapersTerrace[3], 58, "a level seen in game is kept over the tables'")
eq(Instances.byKey.naxxramas[3], 60, "an instance the tables lack keeps its hand level")
for key, inst in pairs(Instances.byKey) do
    eq(type(inst[3]), "number", key .. " has a lowest level")
end
eq(Instances.Levels(Instances.byKey.mc, true), "60", "compact single")
eq(Instances.Icon(Instances.byKey.mc, 14), "|A:Raid:14:14|a", "raid icon")
eq(Instances.Icon(Instances.byKey.brd, 14), "|A:Dungeon:14:14|a", "dungeon icon")
