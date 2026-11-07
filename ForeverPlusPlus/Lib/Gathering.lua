-- Gathering: the herbs, veins, and chests the player takes, as they take them: what it was, where
-- they stood, and what it gave. Nothing is listened to until a module asks (Gathering.Listen).
--
-- A gather starts with UNIT_SPELLCAST_SENT for a gathering spell, which names its target, and
-- counts only once UNIT_SPELLCAST_SUCCEEDED comes with the same cast ID, so a gather that fails or
-- is interrupted counts for nothing. Its loot is the next loot window from a world object, if one
-- opens soon after. The target's name can be empty or secret; then the soft-target object or the
-- last object tooltip names it instead. GatherLite and GatherMate2 do the same on Forever (read
-- 2026-11-06); none of their code.
local _, ns = ...

local pairs, type, tonumber, next = pairs, type, tonumber, next
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

-- The object the player last hovered in the world, for a cast that doesn't name its target.
local hovered, hoveredAt

local function onObjectTooltip(_, data)
    local lines = data and data.lines
    local first = type(lines) == "table" and lines[1]
    local text = type(first) == "table" and first.leftText
    if IsText(text, true) then
        hovered, hoveredAt = text, GetTime()
    end
end

-- What the cast is aimed at: its target, else the soft-target object, else the object hovered
-- just before. And which of those it was, for a debug log.
local function targetName(target)
    if IsText(target, true) then
        return target, "target"
    end
    -- Probe: "softinteract" is Mainline's unit for the object the player faces; Forever may not
    -- have it.
    if UnitExists and UnitName and UnitExists("softinteract") then
        local name = UnitName("softinteract")
        if IsText(name, true) then
            return name, "softinteract"
        end
    end
    if hovered and GetTime() - hoveredAt <= HOVER_WAIT then
        return hovered, "tooltip"
    end
    return nil, "none"
end

local listeners = {} -- fn -> true
local pending -- the gather under way: cast but not yet succeeded, or waiting for its loot
local serial = 0 -- counts gathers, so a timer can tell it's still the one it was set for

local function tell(gather)
    if pending == gather then
        pending = nil
    end
    gather.castGUID = nil
    -- Herbs and veins teach the item they give, for every module that reads nodes.
    local item = gather.items[1]
    if gather.name and item and item.id and (gather.kind == "herb" or gather.kind == "ore") then
        Professions.LearnNodeItem(gather.name, item.id, gather.line)
    end
    for fn in pairs(listeners) do
        fn(gather)
    end
end

local function onSent(_, unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local spell = gatheringSpell(spellID)
    if not spell then
        return
    end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance == true then
        return
    end
    local name, from = targetName(target)
    local mapID, x, y = ns.WorldMap.PlayerPosition()
    serial = serial + 1
    pending = {
        serial = serial,
        name = name,
        from = from,
        kind = spell[2],
        line = spell[3],
        spellID = spellID,
        castGUID = IsText(castGUID) and castGUID or nil,
        mapID = mapID,
        x = x,
        y = y,
        items = {},
    }
end

-- Whether an event's cast is the pending gather's: the same cast ID, or the same spell when the
-- client didn't give a readable one.
local function isPending(castGUID, spellID)
    if not (pending and not pending.succeeded) then
        return false
    end
    if pending.castGUID and IsText(castGUID) then
        return castGUID == pending.castGUID
    end
    return IsNumber(spellID) and spellID == pending.spellID
end

local function onSucceeded(_, unit, castGUID, spellID)
    if unit ~= "player" or not isPending(castGUID, spellID) then
        return
    end
    local gather = pending
    gather.succeeded = GetTime()
    -- Told when its loot comes, or without it if none does in time (auto loot that found nothing,
    -- a chest already empty).
    C_Timer.After(WAIT, function()
        if pending == gather then
            tell(gather)
        end
    end)
end

local function onFailed(_, unit, castGUID, spellID)
    if unit == "player" and isPending(castGUID, spellID) then
        pending = nil
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

local function onLootOpened()
    local gather = pending
    if not (gather and gather.succeeded and GetTime() - gather.succeeded <= WAIT) then
        return
    end
    -- A creature's loot isn't the gather's. Where the client can't say, it's taken as the gather's.
    local fromObject, objectID = lootSource()
    if fromObject == false then
        return
    end
    gather.objectID = objectID
    for slot = 1, GetNumLootItems() do
        local item = slotItem(slot)
        if item.id or item.icon then
            gather.items[#gather.items + 1] = item
        end
    end
    tell(gather)
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
    if on then
        ns.On("LOOT_OPENED", onLootOpened)
    else
        ns.Off("LOOT_OPENED", onLootOpened)
        pending, hovered = nil, nil
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

---Calls `fn(gather)` each time the player gathers something, while `on`: a module listens in
---`OnEnable` and stops in `OnDisable`, and nothing is heard while no module listens. `gather` is
---`{ name, from, kind, line, spellID, mapID, x, y, objectID, items, succeeded }`: the node's name
---as the world writes it (nil when nothing named it) and `from`, what named it ("target",
---"softinteract", "tooltip", or "none"); `kind` ("herb", "ore", "treasure") and `line`, the skill
---line of the spell; where the player stood when they cast (`mapID`, `x`, `y`, nil where it can't
---be read); the world object's ID from its loot (nil without loot); and `items`, the loot as
---`{ id, count, icon }`. Gathers in instances aren't told. Don't keep or change the table.
---@param fn fun(gather: table)
---@param on boolean
function Gathering.Listen(fn, on)
    listeners[fn] = on and true or nil
    listen(next(listeners) ~= nil)
end
