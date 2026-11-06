-- Units: who a unit is to the player (group, friend, recent ally, guildmate), the same by name,
-- what's known of a player from their GUID and the lists, summons, and NPC titles. Dim Other
-- Players and the friendly plates read these, so a wrong "no" fades a friend.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

local SECRET = "<secret>"
game.secret = SECRET -- the one value the game hides

-- target: a friend in the party. focus: a guildmate in the raid. mouseover: a recent ally whose
-- answers are all secret. boss: a stranger's pet. totem and critter: summons by creature type.
local units = {
    target = { guid = "Player-1-AAAA", party = true, level = 30 },
    focus = { guid = "Player-1-BBBB", raid = 3, guild = true, level = 0 },
    mouseover = { guid = SECRET, party = SECRET, raid = SECRET, guild = SECRET },
    arena1 = { guid = "Player-1-EEEE", ally = true },
    boss = { controlled = true },
    totem = { creature = 11, controlled = true },
    critter = { creature = 12 },
    npc = { controlled = false },
    hidden = { controlled = SECRET },
}
local function field(key)
    return function(unit) return units[unit] and units[unit][key] end
end
UnitInParty, UnitInRaid, UnitGUID = field("party"), field("raid"), field("guid")
UnitIsInMyGuild, UnitPlayerControlled = field("guild"), field("controlled")
UnitLevel = field("level")
UnitCreatureType = function(unit) return "Beast", units[unit] and units[unit].creature end
UnitIsOtherPlayersPet = function() return false end
C_FriendList = {
    IsFriend = function(guid) return guid == "Player-1-AAAA" end,
    GetNumFriends = function() return 2 end,
    GetFriendInfoByIndex = function(i)
        return ({
            { name = "Ann", guid = "Player-1-AAAA", connected = true, level = 30, area = "Durotar",
                className = "Warrior" },
            { name = "Cal-OtherRealm", guid = "Player-2-CCCC", connected = false, level = 40, area = "Elwynn" },
        })[i]
    end,
}
C_BattleNet = {
    GetAccountInfoByGUID = function(guid) return guid == "Player-3-DDDD" and {} or nil end,
    GetFriendAccountInfo = function(i)
        return i == 1 and { gameAccountInfo = { characterName = "Dee" } } or nil
    end,
}
BNGetNumFriends = function() return 1 end
IsGuildMember = function(guid)
    if guid == "Player-1-BBBB" then
        return true
    elseif guid == "Player-9-SSSS" then
        return SECRET
    end
    return false
end
local inGuild, rosterAsked = true, 0
IsInGuild = function() return inGuild end
C_GuildInfo = { GuildRoster = function() rosterAsked = rosterAsked + 1 end }
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function()
    -- name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName,
    -- achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
    return "Bob-Realm", "Member", 1, 52, "Mage", "Orgrimmar", "", "", true, 0, "MAGE", 0, 0, false, false,
        0, "Player-1-BBBB"
end
C_RecentAllies = { IsRecentAllyByGUID = function(guid) return guid == "Player-1-EEEE" end }
GetPlayerInfoByGUID = function(guid)
    if guid == "Player-1-BBBB" then
        return "Mage", "MAGE", "Gnome"
    end
end
UnitTokenFromGUID = function(guid) return guid == "Player-1-AAAA" and "target" or nil end
local tooltip = {}
C_TooltipInfo = { GetUnit = function(unit) return tooltip[unit] end }
T.load("Lib/Units") -- it caches these
local Units = ns.Units

-- In the group.
eq(Units.InGroup("target"), true, "units: in the party")
eq(Units.InGroup("focus"), true, "units: in the raid")
eq(Units.InGroup("npc"), false, "units: not grouped")
eq(Units.InGroup("mouseover"), false, "units: a secret answer is no")

-- Friends, by unit, GUID, and name.
eq(Units.IsFriend("target"), true, "units: on the friends list")
eq(Units.IsFriend("focus"), false, "units: not a friend")
eq(Units.IsFriendGUID("Player-3-DDDD"), true, "units: a Battle.net friend by GUID")
eq(Units.IsFriendGUID(SECRET), false, "units: a secret GUID is no friend")
eq(Units.IsFriendGUID(""), false, "units: no GUID is no friend")
eq(Units.IsFriendName("ann"), true, "units: a friend by name, any case")
eq(Units.IsFriendName("Cal"), true, "units: by name without the realm")
eq(Units.IsFriendName("Dee-Realm"), true, "units: a Battle.net friend's character by name")
eq(Units.IsFriendName("Eve"), false, "units: not a friend by name")
eq(Units.IsFriendName(SECRET), false, "units: a secret name is no friend")

-- Guildmates, by unit, GUID (the server), and name (the roster).
eq(Units.IsGuildmate("focus"), true, "units: a guildmate")
eq(Units.IsGuildmate("target"), false, "units: not a guildmate")
eq(Units.IsGuildmate("mouseover"), false, "units: a secret guild answer is no")
eq(Units.IsGuildmateGUID("Player-1-BBBB"), true, "units: a guildmate by GUID")
eq(Units.IsGuildmateGUID("Player-9-SSSS"), false, "units: the server's secret answer is no")
eq(Units.IsGuildmateName("bob"), true, "units: a guildmate by name from the roster")
eq(Units.IsGuildmateName("Ann"), false, "units: not on the roster")
inGuild = false
eq(Units.IsGuildmateName("Bob"), false, "units: no roster without a guild")
Units.RequestGuildRoster()
eq(rosterAsked, 0, "units: no roster asked for without a guild")
inGuild = true
Units.RequestGuildRoster()
eq(rosterAsked, 1, "units: the roster asked for in a guild")

-- Recent allies.
eq(Units.HasRecentAllies(), true, "units: this client has recent allies")
eq(Units.IsRecentAlly("arena1"), true, "units: a recent ally")
eq(Units.IsRecentAlly("target"), false, "units: not a recent ally")
eq(Units.IsRecentAlly("mouseover"), false, "units: a secret GUID is no ally")

-- What's known of a player, from their GUID and the lists.
local ann = Units.PlayerDetails("Player-1-AAAA", "Ann")
eq(ann.friend and ann.online and ann.level == 30 and ann.zone, "Durotar",
    "details: a friend online, from their unit and the friends list")
eq(ann.class, "Warrior", "details: the class from the friends list")
local cal = Units.PlayerDetails(nil, "cal")
eq(cal.friend and cal.online == false and cal.level == nil and cal.zone == nil, true,
    "details: an offline friend by name has no level or zone")
local bob = Units.PlayerDetails("Player-1-BBBB", "Someone Else")
eq(bob.guild and bob.classToken == "MAGE" and bob.race, "Gnome", "details: a guildmate by GUID, not name")
eq(bob.level == 52 and bob.zone, "Orgrimmar", "details: level and zone from the roster")
local nobody = Units.PlayerDetails("Player-7-ZZZZ", "Zed")
eq(nobody.friend or nobody.guild or nobody.level or nobody.online or false, false,
    "details: a stranger far away has nothing")

-- Summons.
eq(Units.SummonKind("totem"), "totem", "summon: a totem by creature type, before player controlled")
eq(Units.SummonKind("critter"), "companion", "summon: a companion")
eq(Units.SummonKind("boss"), "pet", "summon: a player's pet")
eq(Units.SummonKind("npc"), false, "summon: an NPC of its own")
eq(Units.SummonKind("hidden"), nil, "summon: nil when the game won't say")

-- NPC titles: the tooltip's second line, unless it's the level line.
tooltip.target = { lines = { {}, { leftText = "<Innkeeper>" } } }
eq(Units.Title("target"), "Innkeeper", "title: without brackets")
tooltip.target = { lines = { {}, { leftText = "Level 30 Humanoid" } } }
eq(Units.Title("target"), nil, "title: the level line isn't one")
tooltip.target = { lines = { {}, { leftText = "Level ?? Elite" } } }
eq(Units.Title("target"), nil, "title: nor is a ?? level")
tooltip.target = { lines = { {}, { leftText = SECRET } } }
eq(Units.Title("target"), nil, "title: a secret line isn't read")
eq(Units.Title("focus"), nil, "title: no tooltip, no title")
