-- Gathering: the herbs, veins, chests, and fishing pools the player takes, as they take them: what
-- it was, where they stood (or, for a pool, where the line landed), and what it gave; and a herb or
-- vein their skill is too low for, from the game's error. Nothing is listened to until a module
-- asks (Gathering.Listen).
--
-- A gather starts with UNIT_SPELLCAST_SENT for a gathering spell, which names its target, and
-- counts only once UNIT_SPELLCAST_SUCCEEDED comes with the same cast ID, so a gather that fails or
-- is interrupted counts for nothing. Its loot is the next loot window from a world object, if one
-- opens soon after. The target's name can be empty or secret; then the soft-target object or the
-- last object tooltip names it instead. GatherLite and GatherMate2 do the same on Forever (read
-- 2026-11-06); none of their code.
local _, ns = ...

local pairs, ipairs, type, tonumber, next = pairs, ipairs, type, tonumber, next
local GetTime, IsInInstance, C_Timer, C_Spell, C_Item = GetTime, IsInInstance, C_Timer, C_Spell, C_Item
local UnitExists, UnitName = UnitExists, UnitName
local GetNumLootItems, GetLootSlotInfo, GetLootSlotLink = GetNumLootItems, GetLootSlotInfo, GetLootSlotLink
local GetLootSourceInfo = GetLootSourceInfo

local IsText, IsNumber = ns.IsText, ns.IsNumber
local Professions = ns.Professions

local Gathering = {}
ns.Gathering = Gathering

-- The spells that gather, by the kind of node they take. Each is Classic's first rank; the other
-- ranks (Forever's Mining arrives as 2576, Journeyman) share its name, so they're matched by it.
local SPELLS = {
    { ns.GameData.Spell(2575, "Mining"), "ore", Professions.MINING },
    { ns.GameData.Spell(2366, "Herb Gathering"), "herb", Professions.HERBALISM },
    { ns.GameData.Spell(3365, "Opening"), "treasure" },
    { ns.GameData.Spell(1804, "Pick Lock"), "treasure", Professions.LOCKPICKING },
    { ns.GameData.Spell(7620, "Fishing"), "fish", Professions.FISHING },
}

local byID = {} -- spell ID -> its entry in SPELLS, or false for a spell that doesn't gather
local byName -- spell name -> its entry, once the names are read

local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return IsText(name, true) and name or nil
end

-- The entry in SPELLS for a spell the player cast, or nil.
local function gatheringSpell(spellID)
    if not IsNumber(spellID) then
        return nil
    end
    local found = byID[spellID]
    if found == nil then
        if not byName then
            byName = {}
            for _, entry in pairs(SPELLS) do
                local name = spellName(entry[1])
                if name then
                    byName[name] = entry
                end
            end
        end
        local name = spellName(spellID)
        found = name and byName[name] or false
        byID[spellID] = found
    end
    return found or nil
end

local WAIT = 1.5 -- seconds after a gather for its loot window, before it's told without loot
local HOVER_WAIT = 5 -- seconds an object tooltip still names what the player then casts at
-- Fishing: the cast "succeeds" as the line goes out, and the catch comes when the player clicks the
-- bobber, up to its 20 second channel later. The pool is where the bobber lands, out in front of
-- the player (Classic's cast lands about 15 yards off; unverified on Forever).
local FISH_WAIT = 25
local CAST_YARDS = 15
-- The bobber is a world object too: loot from it is open water, not a pool. Seed: Classic's
-- Fishing Bobber, object 35591; unverified on Forever.
local BOBBERS = ns.GameData.New("fishingBobbers", { [35591] = true })
-- The bobber's name as this client writes it, once a catch from it showed which object was
-- hovered to click it, and when the last catch came: what the player hovered before then was the
-- bobber, not the pool the next cast aims at.
local bobberName
local lastCatch = 0

-- The object the player last hovered in the world, for a cast that doesn't name its target.
local hovered, hoveredAt

local function onObjectTooltip(_, data)
    local lines = data and data.lines
    local first = type(lines) == "table" and lines[1]
    local text = type(first) == "table" and first.leftText
    if IsText(text, true) then
        hovered, hoveredAt = text, GetTime()
        -- A locked chest says the Lockpicking it takes under its name. Not in instances, where
        -- locked doors and boxes say it too, and nothing there is remembered.
        local skill, rank = ns.GameData.TooltipRequires(data)
        if skill and Professions.IsLockpicking(skill) and not (IsInInstance and IsInInstance()) then
            Professions.LearnChest(ns.Text.Plain(text), rank)
        end
    end
end

-- Whether a name the cast didn't give itself (the soft target's, a tooltip's) is something worth
-- remembering: a herb or vein, a chest, or a fishing pool.
local function isNode(name)
    return Professions.Node(name) ~= nil or Professions.Chest(name) or Professions.Pool(name)
end

-- What the cast is aimed at: its target, else the soft-target object, else the object hovered
-- just before. And which of those it was, for a debug log. The last two can name something else
-- (a mailbox hovered on the way), so they count only for a herb, vein, chest, or pool Professions
-- knows; the
-- hover is used once.
local function targetName(target)
    if IsText(target, true) then
        return target, "target"
    end
    -- Probe: "softinteract" is Mainline's unit for the object the player faces; Forever may not
    -- have it.
    if UnitExists and UnitName and UnitExists("softinteract") then
        local name = UnitName("softinteract")
        if IsText(name, true) and isNode(name) then
            return name, "softinteract"
        end
    end
    local name = hovered
    if name and GetTime() - hoveredAt <= HOVER_WAIT and isNode(name) then
        hovered = nil
        return name, "tooltip"
    end
    return nil, "none"
end

local trace -- fn(step, a, b, c) while a module logs what's heard, for finding out why a gather wasn't

---Has `fn(step, a, b, c)` told each step of hearing a gather, while a module logs them: "cast"
---(any spell the player casts: its name or ID, the target, and whether it gathers), "success"
---(spell ID, and whether it was the gather's cast), "failed", and "loot" (the source GUID and
---how many items). Nil to stop.
---@param fn? fun(step: string, a: any, b: any, c: any)
function Gathering.SetTrace(fn)
    trace = fn
end

local listeners = {} -- fn -> true
local pending -- the gather under way: cast but not yet succeeded, or waiting for its loot
local queued -- a gather still casting when another was cast, in case that one is refused
local QUEUE_WAIT = 10 -- seconds a gather still casting is kept aside: longer than any gather's cast
local serial = 0 -- counts gathers, so a timer can tell it's still the one it was set for

-- Forgets a gather that won't be told (a catch in open water), from whichever place it's kept.
local function drop(gather)
    if pending == gather then
        pending = nil
    end
    if queued == gather then
        queued = nil
    end
end

local function tell(gather)
    if gather.told then
        return
    end
    gather.told = true
    if pending == gather then
        pending = nil
    end
    if queued == gather then
        queued = nil
    end
    gather.castGUID = nil
    -- Herbs and veins teach the item they give, for every module that reads nodes: the first that
    -- isn't a vein's stone, since a vein gives its ore and stone in either order.
    local item
    for _, each in ipairs(gather.items) do
        if each.id and not Professions.IsStone(each.id) then
            item = each
            break
        end
    end
    if gather.name and item and (gather.kind == "herb" or gather.kind == "ore") then
        Professions.LearnNodeItem(gather.name, item.id, gather.line)
    end
    for fn in pairs(listeners) do
        fn(gather)
    end
end

-- Where the player stands, on the zone's map, so a node in a cave shows on the zone's map with the
-- rest: mapID, x, y, any of them nil where it can't be read; and the map of the cave they're in
-- (any map under the zone's, such as Fargodeep Mine), or nil on the zone's own.
local function playerSpot()
    local mapID, x, y = ns.WorldMap.PlayerPosition()
    local zone = mapID and ns.WorldMap.Zone(mapID)
    local inside
    if zone and zone ~= mapID then
        inside = mapID
        mapID, x, y = ns.WorldMap.PlayerPosition(zone)
    end
    return mapID, x, y, inside
end

-- The spot `yards` in front of the player on `mapID`, or x, y as they are when the facing or the
-- map's size can't be read. Facing is 0 for north and grows turning left; x grows east, y south.
local function ahead(mapID, x, y, yards)
    if not (mapID and x and y) then
        return x, y
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    local width, height = ns.WorldMap.Size(mapID)
    if not (IsNumber(facing) and width) then
        return x, y
    end
    -- Kept on the map: a spot past its edge can't be shared (Gathering.Decode).
    local function clamp(v)
        return v < 0 and 0 or v > 1 and 1 or v
    end
    return clamp(x - math.sin(facing) * yards / width), clamp(y - math.cos(facing) * yards / height)
end

local function onSent(_, unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local spell = gatheringSpell(spellID)
    if trace then
        trace("cast", IsNumber(spellID) and ((spellName(spellID) or "?") .. " " .. spellID) or "?",
            IsText(target) and target or "-", spell and spell[2] or "-")
    end
    if not spell then
        return
    end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance == true then
        return
    end
    local name, from = targetName(target)
    local mapID, x, y, inside = playerSpot()
    local aimed
    if spell[2] == "fish" then
        -- Only a pool is worth remembering; open water is everywhere. The object hovered just
        -- before the cast, a pool this doesn't know yet, names it if the catch comes from a pool:
        -- the bobber is hovered only after.
        if name and not Professions.Pool(name) then
            name, from = nil, "none"
        end
        -- Not the bobber clicked for the last catch, nor a herb, vein, or chest close by.
        if not name and hovered and GetTime() - hoveredAt <= HOVER_WAIT and hoveredAt > lastCatch
            and hovered ~= bobberName and not isNode(hovered) then
            aimed = hovered
        end
        x, y = ahead(mapID, x, y, CAST_YARDS)
    end
    serial = serial + 1
    -- A gather still casting is kept aside, not dropped: a second press while it casts sends a
    -- cast the game refuses at once ("Another action is in progress"), and the first one still
    -- finishes (in game, 2026-11-08).
    -- So is one that finished and waits for its loot: a press in the moment between the cast
    -- ending and the loot coming took its place, and its loot came as no one's (in game,
    -- 2026-11-08).
    local now = GetTime()
    if pending and not pending.succeeded and now - pending.sent <= QUEUE_WAIT then
        queued = pending
    elseif pending and pending.succeeded and not pending.looted and now - pending.succeeded <= WAIT then
        queued = pending
    else
        queued = nil
    end
    pending = {
        serial = serial,
        name = name,
        from = from,
        kind = spell[2],
        line = spell[3],
        spellID = spellID,
        castGUID = IsText(castGUID) and castGUID or nil,
        sent = GetTime(),
        aimed = aimed,
        mapID = mapID,
        x = x,
        y = y,
        inside = inside,
        items = {},
    }
end

-- Whether an event's cast is `gather`'s: the same cast ID, or the same spell when the client
-- didn't give a readable one.
local function isCast(gather, castGUID, spellID)
    if not (gather and not gather.succeeded) then
        return false
    end
    if gather.castGUID and IsText(castGUID) then
        return castGUID == gather.castGUID
    end
    return IsNumber(spellID) and spellID == gather.spellID
end

-- The gather an event's cast is: the pending one, or the one kept aside while a second press was
-- refused; nil for neither.
local function castOf(castGUID, spellID)
    if isCast(pending, castGUID, spellID) then
        return pending
    elseif isCast(queued, castGUID, spellID) then
        return queued
    end
end

local function onSucceeded(_, unit, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local gather = castOf(castGUID, spellID)
    if trace and (pending or queued) then
        trace("success", IsNumber(spellID) and spellID or "?", gather and "yes" or "no")
    end
    if not gather then
        return
    end
    -- The one kept aside finished after all: it's the gather again.
    if gather == queued then
        pending, queued = gather, nil
    end
    gather.succeeded = GetTime()
    -- Its loot came first: told now.
    if gather.looted then
        tell(gather)
        return
    end
    -- Told when its loot comes, or without it if none does in time (auto loot that found nothing,
    -- a chest already empty). A cast at a pool is told only with its catch: one that caught
    -- nothing says nothing about where the pool is.
    local fishing = gather.kind == "fish"
    C_Timer.After(fishing and FISH_WAIT or WAIT, function()
        if pending == gather or queued == gather then
            if queued == gather then
                queued = nil
            end
            if fishing then
                if pending == gather then
                    pending = nil
                end
            elseif not gather.told then
                tell(gather)
            end
        end
    end)
end

-- The gather that just failed, for the error that says why, which can come after the failure.
local failed, failedAt

local function onFailed(_, unit, castGUID, spellID)
    local gather = unit == "player" and castOf(castGUID, spellID)
    if not gather then
        return
    end
    failed, failedAt = gather, GetTime()
    if gather == pending then
        -- A second press refused while the first still casts: the first is the gather again.
        pending, queued = queued, nil
    else
        queued = nil
    end
    if trace then
        trace("failed", IsNumber(spellID) and spellID or "?")
    end
end

-- Too low a skill --------------------------------------------------------------------------------
-- A herb or vein the player's skill is too low for refuses the cast with a red error naming the
-- skill and the rank it takes ("Requires Mining 175"). Its exact words aren't known on Forever and
-- differ between languages, so the error counts when it names Herbalism or Mining with a number
-- after it, and only for a gather just tried or a node of that kind the player faces or hovered.

local ERROR_WAIT = 1 -- seconds from the cast (or its failure) to the error that says why

local LINES = { Professions.MINING, Professions.HERBALISM }

---The gathering skill line (Herbalism or Mining) an error names and the rank after it, as in
---"Requires Mining 175", or nil.
---@param message string plain text
---@return number? line
---@return number? need
function Gathering.Requirement(message)
    for _, line in ipairs(LINES) do
        local skill = Professions.LineName(line)
        local at = skill and message:find(skill, 1, true)
        if at then
            local need = tonumber(message:match("(%d+)", at + #skill))
            if need then
                return line, need
            end
        end
    end
end

-- The gather the error is about: the one just cast or just failed, or else one at the node the
-- player faces or hovered, when the cast never began. Nil when none is of that skill line.
local function refused(line)
    local now = GetTime()
    local gather
    if pending and not pending.succeeded and now - pending.sent <= ERROR_WAIT then
        gather = pending
    elseif failed and now - failedAt <= ERROR_WAIT then
        gather = failed
    end
    if gather then
        return gather.line == line and gather or nil
    end
    local name, from = targetName(nil)
    if not name or Professions.KindLine(Professions.Kind(name)) ~= line then
        return nil
    end
    local mapID, x, y, inside = playerSpot()
    return { name = name, from = from, kind = Professions.LineKind(line), line = line, mapID = mapID,
        x = x, y = y, inside = inside, items = {} }
end

local function onError(_, _, message)
    if not IsText(message, true) then
        return
    end
    local line, need = Gathering.Requirement(ns.Text.Plain(message))
    if not line then
        return
    end
    local inInstance = IsInInstance and IsInInstance()
    local gather = inInstance ~= true and refused(line)
    if trace then
        trace("refused", message, gather and gather.name or "-")
    end
    if not (gather and gather.name) then
        return
    end
    if pending == gather then
        pending = nil
    end
    failed = nil
    -- Teaches every module the skill the node takes, then tells them where it was found.
    Professions.LearnRequirement(gather.name, Professions.LineName(line), need)
    gather.castGUID, gather.requires = nil, need
    for fn in pairs(listeners) do
        fn(gather)
    end
end

-- Whether the loot window holds a world object's loot (nil when the client can't say), and that
-- object's ID from its GUID. Probe: GetLootSourceInfo is in Mainline's loot API.
local function lootSource()
    local guid = GetLootSourceInfo and GetLootSourceInfo(1)
    if not IsText(guid) then
        return nil, nil
    end
    if not guid:find("^GameObject") then
        return false, nil
    end
    -- GameObject-0-[server]-[instance]-[zone]-[object ID]-[spawn]
    return true, tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- The item in a loot slot: { id, count, icon }, any of them nil when it can't be read.
local function slotItem(slot)
    local icon, _, count = GetLootSlotInfo(slot)
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = IsText(link) and C_Item.GetItemInfoInstant(link) or nil
    return {
        id = IsNumber(id) and id or nil,
        count = IsNumber(count) and count or nil,
        icon = ns.IsReadable(icon) and icon or nil,
    }
end

-- The loot, once a gather: LOOT_READY comes first and is all there is with auto loot or Fast
-- Loot, which take it before a window opens (in game, 2026-11-07, no LOOT_OPENED); LOOT_OPENED
-- after it changes nothing. It can come before the cast's UNIT_SPELLCAST_SUCCEEDED, so loot read
-- then waits on the gather for its success to tell it.
local function onLoot(event)
    local gather = pending
    -- The loot of a gather that finished while a later press is still casting (or was just
    -- refused) is that finished gather's.
    if queued and queued.succeeded and not queued.looted and not (pending and pending.succeeded) then
        gather = queued
    end
    if trace then
        local guid = GetLootSourceInfo and GetLootSourceInfo(1)
        trace("loot", IsText(guid) and guid or "?", GetNumLootItems(),
            (event or "") .. ", " .. (gather and (gather.succeeded and "after success" or "before success")
                or "no gather"))
    end
    local wait = gather and gather.kind == "fish" and FISH_WAIT or WAIT
    if not gather or gather.looted or (gather.succeeded and GetTime() - gather.succeeded > wait) then
        return
    end
    -- A creature's loot isn't the gather's. Where the client can't say, it's taken as the gather's.
    local fromObject, objectID = lootSource()
    if fromObject == false then
        return
    end
    -- A catch: from a pool when its source is the pool (anything but the bobber), named by the
    -- pool the cast was aimed at, what that object was seen as before, or the object hovered just
    -- before casting. Open water's is dropped.
    if gather.kind == "fish" then
        local now = GetTime()
        lastCatch = now
        if not objectID or BOBBERS:Get(objectID) then
            -- On Forever a catch comes from the bobber even in a pool (in game, 2026-11-08), so
            -- the bobber says nothing about where it landed. A pool counts when one Professions
            -- knows was named around the cast: aimed at as it went out, or its tooltip seen while
            -- the line was out (pointing at the bobber in it). Otherwise it's open water.
            local name = gather.name
            if not name and hovered and hoveredAt >= gather.sent - HOVER_WAIT
                and Professions.Pool(hovered) then
                name = hovered
            elseif not name and hovered and now - hoveredAt <= HOVER_WAIT then
                -- The object hovered just now was the bobber, clicked to take this.
                bobberName = hovered
            end
            if trace then
                trace("catch", name or "-", hovered or "-")
            end
            if not name then
                drop(gather)
                return
            end
            gather.name = name
        else
            local name = gather.name or Professions.PoolByObject(objectID) or gather.aimed
            if not name then
                drop(gather)
                return
            end
            Professions.LearnPool(name, objectID)
            gather.name = name
        end
    end
    gather.looted = true
    gather.objectID = objectID
    for slot = 1, GetNumLootItems() do
        local item = slotItem(slot)
        if item.id or item.icon then
            gather.items[#gather.items + 1] = item
        end
    end
    if gather.succeeded then
        tell(gather)
    end
end

local listening = false
local tooltipHooked = false

local function listen(on)
    if on == listening then
        return
    end
    listening = on
    local change = on and ns.OnUnit or ns.OffUnit
    change("UNIT_SPELLCAST_SENT", { "player" }, onSent)
    change("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
    change("UNIT_SPELLCAST_FAILED", { "player" }, onFailed)
    change("UNIT_SPELLCAST_INTERRUPTED", { "player" }, onFailed)
    -- A cast refused before it began (moving, too far) fails quietly, without UNIT_SPELLCAST_FAILED.
    if ns.HasEvent("UNIT_SPELLCAST_FAILED_QUIET") then
        change("UNIT_SPELLCAST_FAILED_QUIET", { "player" }, onFailed)
    end
    if on then
        ns.On("UI_ERROR_MESSAGE", onError)
        ns.On("LOOT_OPENED", onLoot)
        -- Probe: LOOT_READY is Mainline's; without it, LOOT_OPENED alone.
        if ns.HasEvent("LOOT_READY") then
            ns.On("LOOT_READY", onLoot)
        end
    else
        ns.Off("UI_ERROR_MESSAGE", onError)
        ns.Off("LOOT_OPENED", onLoot)
        ns.Off("LOOT_READY", onLoot)
        pending, queued, hovered, failed = nil, nil, nil, nil
    end
    -- A tooltip hook can't come off, so it's added once and does nothing while no one listens.
    if on and not tooltipHooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
        tooltipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
            if listening then
                onObjectTooltip(tooltip, data)
            end
        end)
    end
end

-- Remembering nodes ----------------------------------------------------------------------------
-- A map's nodes are a list of { name, kind, x, y, count, time }: x and y from 0 to 1 across the
-- map, rounded to 4 places (half a yard on a big zone), how many times it was gathered, and when
-- last (time()). The player stands a few yards from what they gather, from a different side each
-- time, so a node's spot is the average of where they stood.

local floor, sqrt = math.floor, math.sqrt

Gathering.RADIUS = 15 -- yards within which a gather is of a node already known
local WEIGHT = 10 -- the most gathers a spot's average counts, so a node that moved still follows
local VISIT = 120 -- seconds within which gathering a node again is the same visit

---A spot rounded to the 4 places nodes are saved with.
---@param v number
---@return number
function Gathering.Round(v)
    return floor(v * 10000 + 0.5) / 10000
end

---How far apart two spots on a map are, in yards, for a map `width` by `height` yards.
---@return number yards
function Gathering.Distance(x1, y1, x2, y2, width, height)
    local dx, dy = (x1 - x2) * width, (y1 - y2) * height
    return sqrt(dx * dx + dy * dy)
end

---The node in `list` nearest to x, y within `radius` yards for which `match(node)` is true (any
---node without `match`), and how far it is; nil when there's none.
---@param list table a map's nodes
---@param x number
---@param y number
---@param width number the map's size in yards
---@param height number
---@param radius number yards
---@param match? fun(node: table): boolean
---@return table? node
---@return number? yards
function Gathering.Nearest(list, x, y, width, height, radius, match)
    local best, bestYards
    -- The distance first: it's cheap, and `match` (names that share a spawn) isn't.
    for i = 1, #list do
        local node = list[i]
        local yards = Gathering.Distance(x, y, node.x, node.y, width, height)
        if yards <= radius and (not bestYards or yards < bestYards) and (not match or match(node)) then
            best, bestYards = node, yards
        end
    end
    return best, bestYards
end

-- Moves a node's spot toward x, y, by one part in as many as the gathers and sightings it has
-- (up to WEIGHT).
local function average(node, x, y)
    local weight = node.count + (node.sightings or 0)
    if weight > WEIGHT then
        weight = WEIGHT
    end
    node.x = Gathering.Round((node.x * weight + x) / (weight + 1))
    node.y = Gathering.Round((node.y * weight + y) / (weight + 1))
end

-- Whether a remembered node is the one named `name` would be: the same name, or one that spawns
-- in the same spots (Silver in Tin's).
local function sameSpawn(name)
    return function(known)
        return Professions.SharesSpawn(known.name, name)
    end
end

-- Counts `name` among a node's names, gathered (`gathered`) or only seen, when the spot has spawned
-- more than one (Tin and Silver): `names` holds each one's gathers, and `name`, the one most
-- gathered, is the one the node is shown as.
local function noteName(node, name, kind, gathered)
    if node.name == name and not node.names then
        return
    end
    local names = node.names
    if not names then
        names = { [node.name] = node.count }
        node.names = names
    end
    names[name] = (names[name] or 0) + (gathered and 1 or 0)
    if names[name] > (names[node.name] or 0) then
        node.name, node.kind = name, kind
    end
end

---Adds a gather of the node `name` at x, y to a map's nodes: the same node within `radius` yards
---counts it once more and moves its spot toward this one (unless it was gathered in the last two
---minutes, the same visit); else it's a new node. A node of another name that spawns in the
---same spots (Professions.SharesSpawn: Silver in Tin's) is the same node, which then keeps each
---name's gathers in `names` and is shown as the one most gathered. Returns the node and whether
---it's new.
---@param list table a map's nodes
---@param name string
---@param kind string
---@param x number
---@param y number
---@param width number the map's size in yards
---@param height number
---@param now number time()
---@param radius? number yards, Gathering.RADIUS by default
---@return table node
---@return boolean new
function Gathering.Add(list, name, kind, x, y, width, height, now, radius)
    local node = Gathering.Nearest(list, x, y, width, height, radius or Gathering.RADIUS, sameSpawn(name))
    if node and node.time and now - node.time < VISIT then
        -- Mined again on the same visit (a vein gives two or three times): not another gather.
        node.time = now
        return node, false
    elseif node then
        average(node, x, y)
        noteName(node, name, kind, true)
        node.count = node.count + 1
        if not node.names then
            node.kind = kind
        end
        node.time = now
        return node, false
    end
    node = { name = name, kind = kind, x = Gathering.Round(x), y = Gathering.Round(y), count = 1, time = now }
    list[#list + 1] = node
    return node, true
end

---Adds a sighting of the node `name` at x, y to a map's nodes (seen on the minimap, not gathered):
---like Add, but it doesn't count as a gather. The same node within Gathering.RADIUS yards moves
---toward it, once a visit; else it's a new node, gathered 0 times. A sighting is the dot's own
---spot (Minimap Node Icons reads it standing still), so it weighs as much as a gather. Returns
---the node and whether it's new.
---@param list table a map's nodes
---@param name string
---@param kind string
---@param x number
---@param y number
---@param width number the map's size in yards
---@param height number
---@param now number time()
---@return table node
---@return boolean new
function Gathering.See(list, name, kind, x, y, width, height, now)
    local node = Gathering.Nearest(list, x, y, width, height, Gathering.RADIUS, sameSpawn(name))
    if node then
        noteName(node, name, kind, false)
        if not (node.seen and now - node.seen < VISIT) then
            average(node, x, y)
            node.sightings = (node.sightings or 0) + 1
        end
        node.seen = now
        return node, false
    end
    node = { name = name, kind = kind, x = Gathering.Round(x), y = Gathering.Round(y), count = 0,
        sightings = 1, seen = now }
    list[#list + 1] = node
    return node, true
end

-- Sharing nodes --------------------------------------------------------------------------------
-- Remembered nodes as one line of text to copy and paste: "GM1", the names used, and each map's
-- nodes, with numbers in base 36 to keep it short:
--
--   GM1/oCopper Vein~hPeacebloom/1429:0,abc,1a2,3,t5k2f0;1,.../1436:...
--
-- A name starts with its kind's letter (h herb, o ore, t treasure, f fish). A node is its name's
-- place in the list (from 0), x and y in ten-thousandths of the map, how many times it was
-- gathered, and when last (time(), or 0 for never), and, for one in a cave, that cave's map ID. No
-- "|", which a text box reads as a code.

local KIND_LETTERS = { herb = "h", ore = "o", treasure = "t", fish = "f" }
local LETTER_KINDS = {}
for kind, letter in pairs(KIND_LETTERS) do
    LETTER_KINDS[letter] = kind
end
local HEADER = "GM1"
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local concat = table.concat

local function base36(n)
    n = floor(n)
    if n <= 0 then
        return "0"
    end
    local out = ""
    while n > 0 do
        local digit = n % 36
        out = DIGITS:sub(digit + 1, digit + 1) .. out
        n = (n - digit) / 36
    end
    return out
end

---Remembered nodes, by zone map ID (each a list as Add makes them), as a line of text to share.
---With `keep`, only the nodes it's true for.
---@param maps table<number, table>
---@param keep? fun(node: table): boolean
---@return string text
---@return number count how many nodes it holds
function Gathering.Encode(maps, keep)
    local names, index = {}, {}
    local parts, count = {}, 0
    local ids = {}
    for mapID in pairs(maps) do
        ids[#ids + 1] = mapID
    end
    table.sort(ids)
    for _, mapID in ipairs(ids) do
        local nodes = {}
        for _, node in ipairs(maps[mapID]) do
            local letter = KIND_LETTERS[node.kind]
            if letter and type(node.name) == "string" and (not keep or keep(node)) then
                local key = letter .. node.name
                local i = index[key]
                if not i then
                    names[#names + 1] = key
                    i = #names - 1
                    index[key] = i
                end
                local x = node.x < 0 and 0 or node.x > 1 and 1 or node.x
                local y = node.y < 0 and 0 or node.y > 1 and 1 or node.y
                local fields = { base36(i), base36(x * 10000 + 0.5), base36(y * 10000 + 0.5),
                    base36(node.count or 0), base36(node.time or 0) }
                if type(node.inside) == "number" then
                    fields[6] = base36(node.inside)
                end
                nodes[#nodes + 1] = concat(fields, ",")
            end
        end
        if #nodes > 0 then
            parts[#parts + 1] = mapID .. ":" .. concat(nodes, ";")
            count = count + #nodes
        end
    end
    return HEADER .. "/" .. concat(names, "~") .. "/" .. concat(parts, "/"), count
end

local MAX_COUNT = 1000000 -- more gathers than anyone makes, so a hand-made count can't be huge

---The nodes in a line of text Encode made, by zone map ID, each as { name, kind, x, y, count,
---time }; nil when it isn't one. A node off its map is left out. With `now` (time()), a time later
---than it is taken as now, so a sharer's clock running ahead can't keep a node "just gathered".
---@param text string
---@param now? number
---@return table<number, table>? maps
---@return number count
function Gathering.Decode(text, now)
    if type(text) ~= "string" then
        return nil, 0
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local header, namePart, rest = text:match("^([^/]+)/([^/]*)/?(.*)$")
    if header ~= HEADER then
        return nil, 0
    end
    local names = {}
    for key in namePart:gmatch("[^~]+") do
        local kind = LETTER_KINDS[key:sub(1, 1)]
        local name = key:sub(2)
        if not kind or name == "" then
            return nil, 0
        end
        names[#names + 1] = { name, kind }
    end
    local maps, count = {}, 0
    for part in rest:gmatch("[^/]+") do
        local mapID, body = part:match("^(%d+):(.*)$")
        mapID = tonumber(mapID)
        if not mapID then
            return nil, 0
        end
        local list = maps[mapID] or {}
        maps[mapID] = list
        for each in body:gmatch("[^;]+") do
            -- A sixth field, when there is one, is the cave it's in.
            local i, x, y, gathers, when, inside = each:match("^(%w+),(%w+),(%w+),(%w+),(%w+),?(%w*)$")
            local entry = i and names[(tonumber(i, 36) or -1) + 1]
            x, y = x and tonumber(x, 36), y and tonumber(y, 36)
            if not (entry and x and y) then
                return nil, 0
            end
            if x <= 10000 and y <= 10000 then
                local last = tonumber(when, 36)
                if last and now and last > now then
                    last = now
                end
                local gathered = tonumber(gathers, 36) or 0
                list[#list + 1] = { name = entry[1], kind = entry[2], x = x / 10000, y = y / 10000,
                    count = gathered > MAX_COUNT and MAX_COUNT or gathered,
                    time = last and last > 0 and last or nil,
                    inside = inside ~= "" and tonumber(inside, 36) or nil }
                count = count + 1
            end
        end
    end
    return maps, count
end

---Adds a node shared from elsewhere to a map's `list`: one already known within RADIUS yards of
---the same spawn keeps its spot and takes the larger count and the later time; else it's added.
---@param list table
---@param node table as Decode gives it
---@param width number the map's size in yards
---@param height number
---@return boolean added
function Gathering.Merge(list, node, width, height)
    local known = Gathering.Nearest(list, node.x, node.y, width, height, Gathering.RADIUS,
        sameSpawn(node.name))
    if known then
        if (node.count or 0) > (known.count or 0) then
            known.count = node.count
        end
        if node.time and (not known.time or node.time > known.time) then
            known.time = node.time
        end
        known.inside = known.inside or node.inside
        return false
    end
    list[#list + 1] = { name = node.name, kind = node.kind, x = Gathering.Round(node.x),
        y = Gathering.Round(node.y), count = node.count or 0, time = node.time, inside = node.inside }
    return true
end

-- Sightings and remembered spots ------------------------------------------------------------------
-- What one module that sees nodes (Minimap Node Icons, reading the minimap's dots) and one that
-- remembers them (Gathering Map) tell each other, through here so neither reaches into the other.
-- Either works alone; each is better with the other on.

local sightListeners = {} -- fn -> true
local remembered -- fn(name, mapID, x, y): the spot of a node remembered near there, or nil

-- A spot on `mapID` as one on its zone's map (a cave's spot on the zone around it).
local function onZone(mapID, x, y)
    local zone = ns.WorldMap.Zone(mapID)
    if not zone or zone == mapID then
        return mapID, x, y
    end
    x, y = ns.MapPins.Translate(mapID, zone, x, y)
    if x then
        return zone, x, y
    end
end

---Calls `fn(sighting)` each time a module sees a herb or vein where it really is, without the
---player gathering it, while `on`. `sighting` is `{ name, kind, mapID, x, y }`, on the zone's map.
---@param fn fun(sighting: table)
---@param on boolean
function Gathering.ListenSightings(fn, on)
    sightListeners[fn] = on and true or nil
end

---Tells the modules listening that the herb or vein `name` is at x, y on `mapID`: a spot known to
---be the node's own (as a minimap dot's, read while the player stood still), not where the
---player stood. Does nothing for a name that isn't a node known by its kind.
---@param name string
---@param mapID number
---@param x number
---@param y number
function Gathering.Sighted(name, mapID, x, y)
    if not next(sightListeners) then
        return
    end
    local kind = Professions.Kind(name)
    if not kind then
        return
    end
    mapID, x, y = onZone(mapID, x, y)
    if not mapID then
        return
    end
    local sighting = { name = name, kind = kind, mapID = mapID, x = x, y = y }
    for fn in pairs(sightListeners) do
        fn(sighting)
    end
end

---Sets where remembered nodes are looked up: `fn(name, mapID, x, y)` gives the spot on the zone's
---map `mapID` of the node `name` remembered nearest x, y, or nil. Nil to stop, when the module
---that remembers them turns off.
---@param fn? fun(name: string, mapID: number, x: number, y: number): number?, number?
function Gathering.SetRemembered(fn)
    remembered = fn
end

---The spot of the node `name` remembered nearest x, y on `mapID` (any map; a cave's is looked up
---on its zone's), on `mapID`, or nil when none is remembered there or nothing remembers nodes.
---@param name string
---@param mapID number
---@param x number
---@param y number
---@return number? x
---@return number? y
function Gathering.Remembered(name, mapID, x, y)
    if not remembered then
        return nil
    end
    local zone, zx, zy = onZone(mapID, x, y)
    if not zone then
        return nil
    end
    local rx, ry = remembered(name, zone, zx, zy)
    if not rx or zone == mapID then
        return rx, ry
    end
    return ns.MapPins.Translate(zone, mapID, rx, ry)
end

local live -- fn(): the map ID and the nodes with an icon on the minimap's live dots now

---Sets where the nodes drawn on the minimap's own dots right now are read: `fn()` gives a map ID
---and a list of `{ name, x, y }` on it. Nil to stop, when the module that draws them turns off.
---@param fn? fun(): number?, table?
function Gathering.SetLive(fn)
    live = fn
end

---The map ID and the nodes drawn on the minimap's own dots right now (`{ name, x, y }` on it), so
---a module drawing remembered nodes can leave those be. Nil when nothing draws them.
---@return number? mapID
---@return table? nodes
function Gathering.Live()
    if live then
        return live()
    end
end

---Calls `fn(gather)` each time the player gathers something, while `on`: a module listens in
---`OnEnable` and stops in `OnDisable`, and nothing is heard while no module listens. `gather` is
---`{ name, from, kind, line, spellID, mapID, x, y, objectID, items, succeeded }`: the node's name
---as the world writes it (nil when nothing named it) and `from`, what named it ("target",
---"softinteract", "tooltip", or "none"); `kind` ("herb", "ore", "treasure", "fish") and `line`, the skill
---line of the spell; where the player stood when they cast, on their zone's map (`mapID`, `x`,
---`y`, nil where it can't be read), and `inside`, the map of the cave they stood in (nil outside);
---the world object's ID from its loot (nil without loot); and `items`, the loot as
---`{ id, count, icon }`. A herb or vein the player's skill was too low for is told too, with
---`requires`, the rank it takes, and no loot: it wasn't gathered. Gathers in instances aren't told.
---Don't keep or change the table.
---@param fn fun(gather: table)
---@param on boolean
function Gathering.Listen(fn, on)
    listeners[fn] = on and true or nil
    listen(next(listeners) ~= nil)
end
