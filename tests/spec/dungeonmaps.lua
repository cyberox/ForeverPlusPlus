-- DungeonMaps: whether DungeonJournal can show an instance's map, and asking it to, against a
-- made-up stub of what it leaves in reach; then the client's own map art, and wings.
local T = ...
local ns, eq = T.ns, T.eq

local combat = false
InCombatLockdown = function() return combat end
T.load("Lib/DungeonMaps", ns)
local DM = ns.DungeonMaps

eq(DM.Has(), false, "dungeonmaps: no DungeonJournal")
eq(DM.Can("Ragefire Chasm"), false, "dungeonmaps: nobody to show it")
eq(DM.Open("Ragefire Chasm"), false, "dungeonmaps: nothing opened")

local opened, toggled = nil, 0
ForeverDungeonJournal_NS = {
    DUNGEON_MAPS = { ["Ragefire Chasm"] = {} },
    DungeonFromInstanceName = function(name)
        return (name == "Ragefire Chasm" or name == "Uldaman") and name or nil
    end,
    OpenDungeonMap = function(key) opened = key end,
}
eq(DM.Has(), false, "dungeonmaps: DungeonJournal without its toggle doesn't count")
ForeverDungeonJournal_Toggle = function() toggled = toggled + 1 end
eq(DM.Has(), true, "dungeonmaps: DungeonJournal")
eq(DM.Can("Ragefire Chasm"), true, "dungeonmaps: a dungeon it has a map of")
eq(DM.Can("Uldaman"), false, "dungeonmaps: a dungeon it knows without a map")
eq(DM.Can("Nowhere"), false, "dungeonmaps: a dungeon it doesn't know")
eq(DM.Can(nil), false, "dungeonmaps: no name")
eq(DM.Open("Ragefire Chasm"), true, "dungeonmaps: asked DungeonJournal")
eq(opened, "Ragefire Chasm", "dungeonmaps: with its own key")
eq(toggled, 1, "dungeonmaps: its window opened first")
ForeverDungeonJournalFrame = { IsShown = function() return true end }
DM.Open("Ragefire Chasm")
eq(toggled, 1, "dungeonmaps: an open window isn't toggled shut")
combat = true
eq(DM.Open("Ragefire Chasm"), false, "dungeonmaps: not in combat")
combat = false
ForeverDungeonJournal_NS.OpenDungeonMap = function() error("changed") end
eq(DM.Open("Ragefire Chasm"), false, "dungeonmaps: its error stays its own")

-- The game's own art: asked of the client once for each instance, by its first tile.
ForeverDungeonJournal_NS, ForeverDungeonJournal_Toggle = nil, nil
eq(DM.Has(), false, "dungeonmaps: no art to ask for and no DungeonJournal")
local asked = {}
GetFileIDFromPath = function(path)
    asked[#asked + 1] = path
    return path:find("TheDeadmines", 1, true) and 449591 or nil
end
eq(DM.Has(), true, "dungeonmaps: the client can be asked for art")
eq(DM.Can(nil, 36), true, "dungeonmaps: an instance whose art is in the client")
eq(asked[1], "Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1", "dungeonmaps: asked by its first tile")
eq(DM.Can(nil, 389), false, "dungeonmaps: art this client lacks")
eq(DM.Can(nil, 289), false, "dungeonmaps: an instance with no art listed")
eq(DM.Can(nil, nil), false, "dungeonmaps: no instance")
DM.Can(nil, 36)
DM.Can(nil, 389)
eq(#asked, 2, "dungeonmaps: each instance asked once")
-- An instance of several wings lists them, and is asked for by its first wing's first floor.
eq(DM.Wings(36), nil, "dungeonmaps: an instance of one piece has no wings")
eq(DM.Wings(429), nil, "dungeonmaps: no wings without the art")
GetFileIDFromPath = function(path)
    asked[#asked + 1] = path
    return 1
end
local wings = DM.Wings(189)
eq(#wings, 4, "dungeonmaps: Scarlet Monastery's wings")
eq(wings[2].key .. ":" .. wings[2].name, "library:Library", "dungeonmaps: a wing's key and name")
eq(asked[#asked], "Interface\\WorldMap\\ScarletMonastery\\ScarletMonastery1_1", "dungeonmaps: wings asked by the first's tile")
-- DungeonJournal first, for a player who would sooner have its map: asked before the art.
eq(DM.HasJournal(), false, "dungeonmaps: no DungeonJournal to prefer")
opened = nil
ForeverDungeonJournal_NS = {
    DUNGEON_MAPS = { ["Scarlet Monastery"] = {} },
    DungeonFromInstanceName = function(name) return name end,
    OpenDungeonMap = function(key) opened = key end,
}
ForeverDungeonJournal_Toggle = function() end
eq(DM.HasJournal(), true, "dungeonmaps: DungeonJournal to prefer")
eq(DM.InJournal("Scarlet Monastery"), true, "dungeonmaps: a map DungeonJournal has")
eq(DM.InJournal("The Deadmines"), false, "dungeonmaps: a map DungeonJournal lacks")
eq(DM.Open("Scarlet Monastery", 189, nil, true), true, "dungeonmaps: DungeonJournal asked first")
eq(opened, "Scarlet Monastery", "dungeonmaps: though the game has art for it")
GetFileIDFromPath = function() error("changed") end
eq(DM.Can(nil, 34), false, "dungeonmaps: the client's error stays its own")
