-- Players we've seen: class, level, race, and guild of each other player the game has shown us,
-- remembered for the account, so a module can show them for someone who isn't near now (a name in
-- chat, a whisper). It listens only while a module uses it (Players.Use), and learns from the
-- group, the guild roster, the friends list, who results the player asked for, units they target,
-- mouse over, or see a nameplate of, and chat lines, which carry the speaker's GUID. What it learns
-- last wins, so a level goes up as they do. Anything the game makes secret is skipped, never kept.
--
-- It's saved in a variable of its own, ForeverPlusPlusPlayersDB (Core loads it as ns.playersDB), so
-- thousands of players stay out of the settings. A player is kept by their first name (on Forever,
-- UnitName's second value and the part after a "-" are a surname, not a realm) under their realm's
-- name, from their GUID, or the player's own when there's none (who results) or the game leaves it
-- out (someone on the player's own realm). Forever's realms are its rulesets ("Classic Beta PvE"),
-- each split over several realm IDs in GUIDs, so the name, not the ID, says who's who. Entries not
-- seen for MAX_AGE are dropped at login, and the oldest go once there are more than MAX_PLAYERS.
--
--   ForeverPlusPlusPlayersDB = { [realm, no spaces] = { [first name, lowercased] = "CLASS,level,minutes,race,guild" } }
local _, ns = ...

local pairs, next, type, tonumber, time, floor = pairs, next, type, tonumber, time, math.floor
local format, lower, match, gsub, sort = string.format, string.lower, string.match, string.gsub, table.sort
local UnitIsPlayer, UnitGUID, UnitName, UnitClass, UnitRace, UnitLevel = UnitIsPlayer, UnitGUID, UnitName,
    UnitClass, UnitRace, UnitLevel
local GetRealmName = GetRealmName
local GetGuildInfo, UnitIsVisible, GetPlayerInfoByGUID = GetGuildInfo, UnitIsVisible, GetPlayerInfoByGUID
local IsInRaid, GetNumGroupMembers, IsInGuild = IsInRaid, GetNumGroupMembers, IsInGuild
local GetNumGuildMembers, GetGuildRosterInfo, C_FriendList = GetNumGuildMembers, GetGuildRosterInfo, C_FriendList

local Players = {}
ns.Players = Players

local EPOCH = 1700000000 -- as Lib/Prices.lua: saved times are minutes since then
local MAX_AGE = 60 * 24 * 60 * 60 -- seconds; someone unseen for 60 days is dropped at login
local MAX_PLAYERS = 5000 -- the oldest go past this, so a busy city can't grow the file for ever
local REFRESH = 60 * 60 -- seconds before an unchanged entry gets its seen time written again

Players.MAX_AGE = MAX_AGE

-- Class tokens and names ------------------------------------------------------------------------

local classTokens -- localized class name -> class token, made on first use

---The class token ("WARRIOR") for a localized class name, as the friends list gives it.
---@param name string?
---@return string?
function Players.ClassToken(name)
    if not ns.IsText(name, true) then
        return nil
    end
    if not classTokens then
        classTokens = {}
        for _, names in pairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for token, localized in pairs(names) do
                classTokens[localized] = token
            end
        end
    end
    return classTokens[name]
end

---The localized class name for a class token, or nil.
---@param token string?
---@return string?
function Players.ClassName(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return token and type(names) == "table" and names[token] or nil
end

-- Saved entries ---------------------------------------------------------------------------------
-- One short string each, as auction prices are: thousands are saved.

---An entry as the string saved for it.
---@param entry { class: string?, level: number?, race: string?, guild: string?, seen: number }
---@return string
function Players.Pack(entry)
    return format("%s,%s,%d,%s,%s", entry.class or "", entry.level and floor(entry.level) or "",
        floor((entry.seen - EPOCH) / 60), entry.race or "", entry.guild or "")
end

---The entry a saved string holds, or nil for anything else. The guild comes last, so a comma in
---its name is kept.
---@param saved any
---@return { class: string?, level: number?, race: string?, guild: string?, seen: number }?
function Players.Unpack(saved)
    if type(saved) ~= "string" then
        return nil
    end
    local class, level, minutes, race, guild = match(saved, "^([^,]*),(%d*),(%-?%d+),([^,]*),(.*)$")
    if not class then
        return nil
    end
    return {
        class = class ~= "" and class or nil,
        level = tonumber(level),
        race = race ~= "" and race or nil,
        guild = guild ~= "" and guild or nil,
        seen = EPOCH + tonumber(minutes) * 60,
    }
end

local count -- entries saved, counted on first use

local function countAll(all)
    local n = 0
    for _, realm in pairs(all) do
        for _ in pairs(realm) do
            n = n + 1
        end
    end
    return n
end

---Drops entries not seen for MAX_AGE, anything that isn't an entry, and the oldest past
---`limit` (MAX_PLAYERS). Called at login, and when the count runs over.
---@param all table ForeverPlusPlusPlayersDB
---@param limit? number
function Players.Prune(all, limit)
    count = nil
    if next(all) == nil then
        return
    end
    local oldest = time() - MAX_AGE
    local kept = {}
    for realmID, realm in pairs(all) do
        if type(realm) ~= "table" then
            all[realmID] = nil
        else
            for key, value in pairs(realm) do
                local entry = Players.Unpack(value)
                if not entry or entry.seen < oldest then
                    realm[key] = nil
                else
                    kept[#kept + 1] = { realm, key, entry.seen }
                end
            end
        end
    end
    limit = limit or MAX_PLAYERS
    if #kept > limit then
        sort(kept, function(a, b)
            return a[3] > b[3]
        end)
        for i = limit + 1, #kept do
            kept[i][1][kept[i][2]] = nil
        end
    end
    for realmID, realm in pairs(all) do
        if next(realm) == nil then
            all[realmID] = nil
        end
    end
    count = nil
end

-- Names and realms ------------------------------------------------------------------------------

-- A name's first part, lowercased: "Bob" for "Bob-Surname", "Bob Surname", or "Bob-Realm".
local function firstName(name)
    if not ns.IsText(name, true) then
        return nil
    end
    return lower(match(name, "^[^%-%s]+") or name)
end

local function readText(value)
    if ns.IsText(value, true) then
        return value
    end
end

local function isPlayerGUID(guid)
    return ns.IsText(guid, true) and match(guid, "^Player%-") ~= nil
end

-- A realm's name as a key: "ClassicBetaPvE" for "Classic Beta PvE".
local function realmKey(realm)
    return realm and (gsub(realm, "[%s%-]", "")) or nil
end

local ownRealm

-- The player's own realm. "?" while the game can't say.
local function homeRealm()
    if not ownRealm then
        ownRealm = realmKey(readText(GetRealmName and GetRealmName()))
    end
    return ownRealm or "?"
end

---Where a player is kept: their realm's key and their own, or nil when there's no name to go by.
---A readable GUID names another realm, and the name too when none is given.
---@param guid string?
---@param name string?
---@return string? realm
---@return string? key
local function where(guid, name)
    local realm
    if isPlayerGUID(guid) and GetPlayerInfoByGUID then
        local _, _, _, _, _, guidName, guidRealm = GetPlayerInfoByGUID(guid)
        name = name or readText(guidName)
        realm = realmKey(readText(guidRealm))
    end
    local key = firstName(name)
    if not key then
        return nil
    end
    return realm or homeRealm(), key
end

-- Reading and learning --------------------------------------------------------------------------

---What's known of a player: their class token, level, localized race, guild name, and when they
---were last seen (time()). Nil for someone never seen. A guild left out may be no guild at all.
---@param guid string? their GUID, when the caller has it
---@param name string? their name, with or without a surname
---@return { class: string?, level: number?, race: string?, guild: string?, seen: number }?
function Players.Get(guid, name)
    local all = ns.playersDB
    local realm, key = where(guid, name)
    if not (all and realm) then
        return nil
    end
    local byName = all[realm]
    return byName and Players.Unpack(byName[key]) or nil
end

local function readLevel(value)
    if ns.IsNumber(value) and value > 0 then
        return value
    end
end

---Remembers what a source tells of a player; what it leaves out stays as last seen. `info.guild`
---false means they're in no guild, nil that the source doesn't say. Secret or empty values are
---skipped, so a caller can pass the game's values as they come.
---@param guid string?
---@param name string?
---@param info { class: string?, level: number?, race: string?, guild: string|false|nil }
function Players.Learn(guid, name, info)
    local realm, key = where(guid, name)
    if not realm then
        return
    end
    local class, race, level = readText(info.class), readText(info.race), readLevel(info.level)
    if isPlayerGUID(guid) and GetPlayerInfoByGUID and not (class and race) then
        local _, token, localizedRace = GetPlayerInfoByGUID(guid)
        class, race = class or readText(token), race or readText(localizedRace)
    end
    local all = ns.playersDB
    if not all then
        return
    end
    local byName = all[realm]
    if type(byName) ~= "table" then
        byName = {}
        all[realm] = byName
    end
    local old = Players.Unpack(byName[key])
    local guild = info.guild
    if guild == false then
        guild = nil
    elseif not readText(guild) then
        guild = old and old.guild
    end
    local now = time()
    local entry = {
        class = class or old and old.class,
        level = level or old and old.level,
        race = race or old and old.race,
        guild = guild,
        seen = now,
    }
    -- Nothing new and seen lately: leave it, since the guild roster tells of everyone in it often.
    if old and old.class == entry.class and old.level == entry.level and old.race == entry.race
        and old.guild == entry.guild and now - old.seen < REFRESH then
        return
    end
    if not old then
        count = (count or countAll(all)) + 1
    end
    byName[key] = Players.Pack(entry)
    if count and count > MAX_PLAYERS + 100 then
        Players.Prune(all)
    end
end

---Remembers a unit, when it's another player whose name can be read: its class, race, level, and
---guild (or that it has none, when the unit is near enough for the game to say).
---@param unit string
function Players.LearnUnit(unit)
    if not (ns.IsTrue(UnitIsPlayer(unit))) then
        return
    end
    local name = UnitName(unit)
    if not ns.IsText(name, true) then
        return
    end
    local _, class = UnitClass(unit)
    local race = UnitRace and UnitRace(unit)
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if not readText(guild) then
        -- No guild, or one the game hasn't sent yet for a unit far away: only one near says none.
        local near = ns.IsReadable(guild) and UnitIsVisible and ns.IsTrue(UnitIsVisible(unit))
        if near then
            guild = false
        else
            guild = nil
        end
    end
    Players.Learn(UnitGUID(unit), name, { class = class, race = race, level = UnitLevel(unit), guild = guild })
end

-- Listening -------------------------------------------------------------------------------------

local function learnGroup()
    local raid = IsInRaid and IsInRaid()
    local prefix, total = raid and "raid" or "party", raid and GetNumGroupMembers() or 4
    for i = 1, total do
        Players.LearnUnit(prefix .. i)
    end
end

local function learnGuild()
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then
        return
    end
    local guild = readText(GetGuildInfo("player"))
    for i = 1, (GetNumGuildMembers()) do
        local name, _, _, level, _, _, _, _, _, _, token, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        Players.Learn(guid, name, { class = token, level = level, guild = guild })
    end
end

local function learnFriends()
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
        return
    end
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        -- An offline friend's level and class aren't sent.
        if info and info.connected then
            Players.Learn(info.guid, info.name, { class = Players.ClassToken(info.className),
                level = info.level })
        end
    end
end

-- Who results come only from a /who the player sent (or the who list they opened).
local function learnWho()
    if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then
        return
    end
    for i = 1, (C_FriendList.GetNumWhoResults()) or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info then
            local guild = info.fullGuildName
            if ns.IsText(guild) and guild == "" then
                guild = false
            end
            Players.Learn(info.guid, info.fullName, { class = info.filename, level = info.level,
                race = info.raceStr, guild = guild })
        end
    end
end

-- A chat line's speaker and GUID: the class and race come from the GUID.
local function learnChat(_, _, sender, _, _, _, _, _, _, _, _, _, guid)
    if isPlayerGUID(guid) then
        Players.Learn(guid, ns.IsText(sender, true) and sender or nil, {})
    end
end

local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL" }

local function onUnit(_, unit)
    if ns.IsText(unit, true) then
        Players.LearnUnit(unit)
    end
end

local users = {} -- owner -> true, while it uses the list
local listening = false

-- Lists the game sends again and again in bursts (the guild roster every few seconds) are read
-- once after a burst, and not at all once nobody listens.
local function soon(fn, delay)
    local queue
    return function()
        if not queue then
            queue = ns.Frames.Coalesce(function()
                if listening then
                    fn()
                end
            end, delay)
        end
        queue()
    end
end

local EVENTS = {
    GROUP_ROSTER_UPDATE = soon(learnGroup, 0.5),
    GUILD_ROSTER_UPDATE = soon(learnGuild, 2),
    FRIENDLIST_UPDATE = soon(learnFriends, 1),
    WHO_LIST_UPDATE = learnWho,
    PLAYER_TARGET_CHANGED = function() Players.LearnUnit("target") end,
    PLAYER_FOCUS_CHANGED = function() Players.LearnUnit("focus") end,
    UPDATE_MOUSEOVER_UNIT = function() Players.LearnUnit("mouseover") end,
    NAME_PLATE_UNIT_ADDED = onUnit,
    UNIT_LEVEL = onUnit,
    PLAYER_GUILD_UPDATE = function() Players.LearnUnit("player") end,
}
for _, event in pairs(CHAT_EVENTS) do
    EVENTS[event] = learnChat
end

local function start()
    listening = true
    for event, fn in pairs(EVENTS) do
        if ns.HasEvent(event) then
            ns.On(event, fn)
        end
    end
    Players.LearnUnit("player")
    learnGroup()
    learnFriends()
    learnGuild()
    -- The roster the client has may be old or not there yet; GUILD_ROSTER_UPDATE follows.
    ns.Units.RequestGuildRoster()
end

local function stop()
    listening = false
    for event, fn in pairs(EVENTS) do
        ns.Off(event, fn)
    end
end

---Starts learning players for `owner` (a module, from OnEnable). It listens while any owner uses it.
---@param owner table
function Players.Use(owner)
    users[owner] = true
    if not listening then
        start()
    end
end

---Stops learning for `owner` (from OnDisable). What was learned stays saved.
---@param owner table
function Players.Release(owner)
    users[owner] = nil
    if listening and next(users) == nil then
        stop()
    end
end
