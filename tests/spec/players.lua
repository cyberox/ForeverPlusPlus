-- Players: players seen, packed for the saved variables, learned from units, and pruned.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

do
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
    -- Players caches these globals at load, so it's loaded after them.
    T.load("Lib/Players")
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
end
