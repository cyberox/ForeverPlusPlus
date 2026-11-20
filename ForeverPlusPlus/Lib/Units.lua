-- Who a unit is to the player: in their group, on their friends list, a recent ally, in their guild,
-- someone's pet or summon, and an NPC's title. Friends and guildmates can also be checked by name,
-- and what's known of a player (class, race, level, zone) gathered from their GUID and the lists.
-- Identity can be secret (mostly in instances), and a value we can't read counts as "no".
local _, ns = ...

local UnitInParty, UnitInRaid, UnitGUID, UnitIsInMyGuild = UnitInParty, UnitInRaid, UnitGUID, UnitIsInMyGuild
local C_FriendList, C_BattleNet, C_TooltipInfo, type = C_FriendList, C_BattleNet, C_TooltipInfo, type
local tonumber = tonumber
local C_RecentAllies, C_GuildInfo, IsInGuild, IsGuildMember = C_RecentAllies, C_GuildInfo, IsInGuild, IsGuildMember
local BNGetNumFriends, GetNumGuildMembers, GetGuildRosterInfo = BNGetNumFriends, GetNumGuildMembers, GetGuildRosterInfo
local UnitPlayerControlled, UnitCreatureType, UnitIsOtherPlayersPet = UnitPlayerControlled, UnitCreatureType, UnitIsOtherPlayersPet
local GetPlayerInfoByGUID, UnitTokenFromGUID, UnitLevel = GetPlayerInfoByGUID, UnitTokenFromGUID, UnitLevel

local readable = ns.IsReadable

local Units = {}
ns.Units = Units

-- The player ------------------------------------------------------------------------------------
-- For a module that does something by itself (casts, sheathes, opens): whether now is a bad time.
-- The player's own state can be secret too, and an answer the game hides counts as busy, since
-- waiting costs a moment and acting at the wrong time interrupts the player.

local busy = ns.IsTrueOrSecret

---Whether the player is casting or channelling, or the game won't say.
---@return boolean
function Units.PlayerCasting()
    return busy(UnitCastingInfo and UnitCastingInfo("player"))
        or busy(UnitChannelInfo and UnitChannelInfo("player"))
end

---Why the player can't be made to act right now, or nil when they can: "combat", "dead" (or a
---ghost), "taxi" (on a flight), or "casting" (a cast or a channel).
---@return string? reason
function Units.PlayerBusy()
    if InCombatLockdown() then
        return "combat"
    elseif busy(UnitIsDeadOrGhost("player")) then
        return "dead"
    elseif busy(UnitOnTaxi("player")) then
        return "taxi"
    elseif Units.PlayerCasting() then
        return "casting"
    end
    return nil
end

---Whether the unit is in the player's party or raid.
---@param unit string
---@return boolean
function Units.InGroup(unit)
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    return (readable(party) and party) or (readable(raid) and raid ~= nil) or false
end

---Whether the unit is on the player's friends list or a Battle.net friend.
---@param unit string
---@return boolean
function Units.IsFriend(unit)
    return Units.IsFriendGUID(UnitGUID(unit))
end

---Whether the player with this GUID is on the player's friends list or a Battle.net friend.
---@param guid string?
---@return boolean
function Units.IsFriendGUID(guid)
    if not ns.IsText(guid, true) then
        return false
    end
    if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then
        return true
    end
    return C_BattleNet and C_BattleNet.GetAccountInfoByGUID
        and C_BattleNet.GetAccountInfoByGUID(guid) ~= nil or false
end

---Whether the player with this GUID is in the player's guild. Asks the server, so unlike
---IsGuildmateName it doesn't need the guild roster loaded.
---@param guid string?
---@return boolean
function Units.IsGuildmateGUID(guid)
    if not (IsGuildMember and ns.IsText(guid, true)) then
        return false
    end
    local mate = IsGuildMember(guid)
    return readable(mate) and mate and true or false
end

-- Events for when the recent allies list loads or changes. We can't ask for the list ourselves:
-- TryRequestRecentAlliesData is protected on Forever, so we use whatever the client has loaded
-- (it loads when the Recent Allies tab opens) and recolor when these fire.
Units.RECENT_ALLY_EVENTS = { "RECENT_ALLIES_CACHE_UPDATE", "RECENT_ALLIES_DATA_READY" }

---Whether the recent allies list is on this client. Call before listening to RECENT_ALLY_EVENTS.
---@return boolean
function Units.HasRecentAllies()
    return C_RecentAllies and C_RecentAllies.IsRecentAllyByGUID and true or false
end

---Whether the unit is on the player's Recent Allies list (players they've recently grouped or
---played with), which the game shows in light blue (ns.Colors.RECENT_ALLY).
---@param unit string
---@return boolean
function Units.IsRecentAlly(unit)
    if not Units.HasRecentAllies() then
        return false
    end
    local guid = UnitGUID(unit)
    if not (readable(guid) and guid) then
        return false
    end
    local ally = C_RecentAllies.IsRecentAllyByGUID(guid)
    return readable(ally) and ally or false
end

---Whether the unit is in the player's guild.
---@param unit string
---@return boolean
function Units.IsGuildmate(unit)
    local mate = UnitIsInMyGuild and UnitIsInMyGuild(unit)
    return readable(mate) and mate or false
end

-- By name, for events that give a player's name but no unit (a duel or group invite). Names are
-- compared without any "-Realm" part, and lowercased.
local function bare(name)
    if not ns.IsText(name) then
        return nil
    end
    return (name:match("^([^%-]+)") or name):lower()
end

-- Calls `fn(info)` for each entry on the friends list until it returns true; true if one did.
local function eachFriend(fn)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
        return false
    end
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and fn(info) then
            return true
        end
    end
    return false
end

-- Calls `fn(...)` with GetGuildRosterInfo's values for each member of the roster the client has,
-- until it returns true; true if one did.
local function eachGuildmate(fn)
    if not (IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then
        return false
    end
    for i = 1, (GetNumGuildMembers()) do
        if fn(GetGuildRosterInfo(i)) then
            return true
        end
    end
    return false
end

---Whether a player by this name is on the player's friends list or an online Battle.net friend.
---@param name string
---@return boolean
function Units.IsFriendName(name)
    local want = bare(name)
    if not want then
        return false
    end
    if eachFriend(function(info) return bare(info.name) == want end) then
        return true
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, (BNGetNumFriends()) do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            local game = info and info.gameAccountInfo
            if game and bare(game.characterName) == want then
                return true
            end
        end
    end
    return false
end

---Asks the server for the guild roster, so IsGuildmateName has names to check.
function Units.RequestGuildRoster()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

---Whether a player by this name is in the player's guild, from the roster the client has.
---@param name string
---@return boolean
function Units.IsGuildmateName(name)
    local want = bare(name)
    if not want then
        return false
    end
    return eachGuildmate(function(rosterName)
        return bare(rosterName) == want
    end)
end

-- What the game can tell about another player -------------------------------------------------

local function readNumber(value)
    if ns.IsNumber(value) and value > 0 then
        return value
    end
end

local function readText(value)
    if ns.IsText(value, true) then
        return value
    end
end

---What the game knows about a player who isn't on screen, from their GUID (class and race, once
---the client has seen them), a unit it can see (target, mouseover, group) for their level, and the
---friends list and guild roster for their level, zone, and whether they're online. Any of it can
---be missing: someone who's neither a friend, a guildmate, nor near has no level or zone.
---@param guid string?
---@param name string? matched against the lists when the GUID isn't there or doesn't match
---@return { class: string?, classToken: string?, race: string?, level: number?, zone: string?, online: boolean?, friend: boolean, guild: boolean }
function Units.PlayerDetails(guid, name)
    local d = { friend = false, guild = false }
    local hasGuid = ns.IsText(guid, true)
    local want = bare(name)
    local function matches(otherGuid, otherName)
        if hasGuid and ns.IsText(otherGuid, true) then
            return otherGuid == guid
        end
        return want ~= nil and bare(otherName) == want
    end
    if hasGuid then
        if GetPlayerInfoByGUID then
            local class, token, race = GetPlayerInfoByGUID(guid)
            d.class, d.classToken, d.race = readText(class), readText(token), readText(race)
        end
        d.friend = Units.IsFriendGUID(guid)
        d.guild = Units.IsGuildmateGUID(guid)
        -- Probe: UnitTokenFromGUID is Mainline's.
        local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
        if readText(unit) then
            d.level = readNumber(UnitLevel(unit))
            d.online = true
        end
    end
    eachFriend(function(info)
        if not matches(info.guid, info.name) then
            return false
        end
        d.friend = true
        d.online = info.connected and true or false
        if d.online then
            d.level = d.level or readNumber(info.level)
            d.zone = readText(info.area)
        end
        d.class = d.class or readText(info.className)
        return true
    end)
    eachGuildmate(function(rosterName, _, _, level, class, zone, _, _, online, _, token, _, _, _, _, _,
        rosterGuid)
        if not matches(rosterGuid, rosterName) then
            return false
        end
        d.guild = true
        d.online = online and true or false
        d.level = d.level or readNumber(level)
        d.class, d.classToken = d.class or readText(class), d.classToken or readText(token)
        if d.online then
            d.zone = d.zone or readText(zone)
        end
        return true
    end)
    return d
end

-- Creature types that are always someone's summon (UnitCreatureType's second value on Mainline).
-- Checked first, since a player's totem or companion is player controlled too.
local SUMMON_TYPES = {
    [11] = "totem", -- Totem
    [12] = "companion", -- Non-combat Pet
}

---What kind of summon the unit is: "totem", "companion", or "pet" (a player's pet, minion, or
---guardian). False for an NPC of its own, nil when the game won't say (secret values).
---@param unit string
---@return string|boolean|nil
function Units.SummonKind(unit)
    local _, kind = UnitCreatureType(unit)
    if ns.IsNumber(kind) and SUMMON_TYPES[kind] then
        return SUMMON_TYPES[kind]
    end
    local controlled = UnitPlayerControlled(unit)
    if readable(controlled) and controlled then
        return "pet"
    end
    if UnitIsOtherPlayersPet then
        local pet = UnitIsOtherPlayersPet(unit)
        if readable(pet) and pet then
            return "pet"
        end
    end
    if not readable(controlled) then
        return nil
    end
    return false
end

---An NPC's title ("Innkeeper", "Weapon Merchant"), without brackets, or nil. It's the tooltip's
---second line; NPCs without a title have their level there instead ("Level 30 Humanoid"), which
---is told apart by its number (or "??").
---@param unit string
---@return string?
function Units.Title(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
        return nil
    end
    local data = C_TooltipInfo.GetUnit(unit)
    local line = data and data.lines and data.lines[2]
    local text = line and line.leftText
    if not ns.IsText(text) then
        return nil
    end
    text = text:gsub("^<", ""):gsub(">$", "")
    if text == "" or text:find("%d") or text:find("%?%?") then
        return nil
    end
    return text
end

---The NPC's ID from a creature's (or vehicle's) GUID, or nil for anything else. A secret GUID, in
---combat or an instance, isn't read.
---
---Creature-0-[server]-[instance]-[zone]-[NPC ID]-[spawn]. Only the ID's place is counted on: the
---game hides the parts before it one by one (the server and spawn, then the realm, in a 1.60.1
---hotfix, from Blizzard's 12.1.7 PTR notes, 2026-11-19), so they are taken as any text.
---@param guid any
---@return number?
function Units.NpcID(guid)
    if not ns.IsText(guid) then
        return nil
    end
    return tonumber(guid:match("^Creature%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-"))
        or tonumber(guid:match("^Vehicle%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-"))
end
