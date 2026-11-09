-- Waypoints: /way puts Blizzard's own map pin (the user waypoint) on a spot and tracks it, so the
-- game draws its pin and its marker in the world; a command another addon already has (TomTom's
-- /way) is left to that addon (Lib/Slash). The Arrow option adds a small arrow on screen that
-- turns toward the waypoint as you turn, with the distance under it, for the pin set by /way or
-- by clicking the map, or with Follow Selected Quest, for the quest selected on the map, or with
-- Point to Corpse, for the player's corpse while they're a ghost. It reads only the player's own
-- position and facing, never another unit's. Clear Pin on Arrival takes the pin away once the
-- arrow says the player has reached it. Text after /way's coordinates is the pin's note, shown
-- under the arrow, and /way share puts the pin's link in the chat box.
local _, ns = ...

local tonumber, format, floor, abs = tonumber, string.format, math.floor, math.abs
local tconcat = table.concat
local CreateFrame, UIParent, C_Map, C_QuestLog = CreateFrame, UIParent, C_Map, C_QuestLog
local GetPlayerFacing, GetTime, UnitIsGhost = GetPlayerFacing, GetTime, UnitIsGhost
local C_Timer = C_Timer

local L = ns.L
local WorldMap = ns.WorldMap

local module = ns.NewModule("Waypoints", L.WAYPOINTS_DESC, {
    enabled = true,
    way = true,
    arrow = true,
    quest = true,
    questName = true,
    corpse = true,
    clearOnArrival = true,
    scale = 100, -- percent
    x = 0, -- the arrow's offset from the center of the screen
    y = 340, -- near the top, clear of a windowed game's title bar
})
module.title = L.WAYPOINTS_TITLE
module.category = "map"
module.added = "0.8.0"

-- 0.8.x saved every default as if the player chose it, so an arrow at (0, 530) is 0.8.4's
-- default, not a place the player picked: let it take today's.
ns.Migrate(1, function(db)
    local saved = db.modules and db.modules.Waypoints
    if saved and saved.y == 530 and (saved.x or 0) == 0 then
        saved.y = nil
    end
end)

module.options = {
    { key = "way", name = L.WAYPOINTS_WAY, description = L.WAYPOINTS_WAY_DESC },
    { key = "arrow", name = L.WAYPOINTS_ARROW, description = L.WAYPOINTS_ARROW_DESC },
    { key = "quest", name = L.WAYPOINTS_QUEST, description = L.WAYPOINTS_QUEST_DESC,
        requires = "arrow", added = "0.9.0" },
    { key = "questName", name = L.WAYPOINTS_QUEST_NAME, description = L.WAYPOINTS_QUEST_NAME_DESC,
        requires = "quest", added = "0.9.0" },
    { key = "corpse", name = L.WAYPOINTS_CORPSE, description = L.WAYPOINTS_CORPSE_DESC,
        requires = "arrow", added = "0.9.0" },
    { key = "clearOnArrival", name = L.WAYPOINTS_CLEAR_ON_ARRIVAL,
        description = L.WAYPOINTS_CLEAR_ON_ARRIVAL_DESC, requires = "arrow", added = "0.9.0",
        changed = "1.1.0" }, -- on by default
}

-- /way ----------------------------------------------------------------------------------------

local function mapName(mapID)
    return WorldMap.MapName(mapID, "#" .. mapID)
end

-- The words typed, with commas as spaces so "45.2, 67.8" reads like "45.2 67.8", and where each
-- ends in `text`, so the note after the coordinates keeps its own commas.
local function words(text)
    local list, ends = {}, {}
    for word, last in text:gsub(",", " "):gmatch("(%S+)()") do
        list[#list + 1] = word
        ends[#ends + 1] = last
    end
    return list, ends
end

local CLEAR = { clear = true, reset = true, off = true, remove = true }

-- The note typed after /way's coordinates, and the pin it was typed for: { mapID, x, y, text }.
-- Blizzard's pin has no label, so the note is ours, shown with the arrow while that pin stays.
local note

-- How far apart (0 to 1) the pin and the note's spot may be and still be the same pin, for the
-- rounding the game's pin may do.
local SAME_PIN = 0.0001

-- The note of this map pin, or nil when it isn't the pin the note was typed for.
local function noteOf(pin)
    if not (note and pin and pin.uiMapID == note[1] and pin.position) then
        return nil
    end
    local x, y = pin.position.x, pin.position.y
    if ns.IsNumber(x) and ns.IsNumber(y) and abs(x - note[2]) < SAME_PIN
        and abs(y - note[3]) < SAME_PIN then
        return note[4]
    end
    return nil
end

-- Blizzard's link for the map pin, put in the chat edit box the way a shift-click on the pin does
-- (WaypointLocationPinMixin, wow-ui-source `forever`), or the box opened with it when none is.
-- After a frame: the box /way was typed in closes once the command returns. Unverified on Forever.
local function share()
    if not C_Map.GetUserWaypointHyperlink then
        ns.Print(L.WAYPOINTS_SHARE_UNAVAILABLE)
        return
    end
    local link = not (C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint())
        and C_Map.GetUserWaypointHyperlink()
    if not link or link == "" then
        ns.Print(L.WAYPOINTS_SHARE_NONE)
        return
    end
    C_Timer.After(0, function()
        local util = ChatFrameUtil
        local insert = util and util.InsertLink or ChatEdit_InsertLink
        if insert and insert(link) then
            return
        end
        local open = util and util.OpenChat or ChatFrame_OpenChat
        if open then
            open(link)
        else
            ns.Print(L.WAYPOINTS_SHARE_UNAVAILABLE)
        end
    end)
end

local function way(message)
    if not (module.enabled and module.db.way) then
        return -- chat cached the command before it was turned off, on a client we couldn't clear
    end
    if not WorldMap.CanWaypoint() then
        ns.Print(L.WAYPOINTS_UNAVAILABLE)
        return
    end
    message = message or ""
    local list, ends = words(message)
    if #list == 1 and CLEAR[list[1]:lower()] then
        note = nil
        C_Map.ClearUserWaypoint()
        ns.Print(L.WAYPOINTS_CLEARED)
        return
    end
    if #list == 1 and list[1]:lower() == "share" then
        share()
        return
    end
    -- [zone] x y [note]
    local at
    for i = 1, #list - 1 do
        if tonumber(list[i]) and tonumber(list[i + 1]) then
            at = i
            break
        end
    end
    if not at then
        ns.Print(L.WAYPOINTS_USAGE)
        return
    end
    local x, y = tonumber(list[at]), tonumber(list[at + 1])
    if x < 0 or x > 100 or y < 0 or y > 100 then
        ns.Print(L.WAYPOINTS_RANGE)
        return
    end
    local mapID
    if at > 1 then
        local name = tconcat(list, " ", 1, at - 1)
        mapID = WorldMap.FindMap(name)
        if not mapID then
            ns.Print(format(L.WAYPOINTS_NO_ZONE, name))
            return
        end
    else
        mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then
            ns.Print(L.WAYPOINTS_NO_MAP)
            return
        end
    end
    -- Set before the pin, whose USER_WAYPOINT_UPDATED redraws the arrow with it.
    local text = message:sub(ends[at + 1]):match("^[%s,]*(.-)%s*$")
    local previous = note
    note = text ~= "" and { mapID, x / 100, y / 100, text } or nil
    if not WorldMap.SetWaypoint(mapID, x / 100, y / 100) then
        note = previous
        ns.Print(format(L.WAYPOINTS_NOT_HERE, mapName(mapID)))
        return
    end
    if note then
        ns.Print(format(L.WAYPOINTS_SET_NOTE, text, mapName(mapID), x, y))
    else
        ns.Print(format(L.WAYPOINTS_SET, mapName(mapID), x, y))
    end
end

local WAY_KEY, WAY_SLASH = "FOREVERPLUSPLUS_WAY", "/way"

local function syncWay()
    if module.enabled and module.db.way then
        ns.Slash.Add(WAY_KEY, WAY_SLASH, way)
    else
        ns.Slash.Remove(WAY_KEY, WAY_SLASH)
    end
end

-- Where the waypoint is ----------------------------------------------------------------------

local ARRIVED = 10 -- yards; closer than this the arrow goes away. 5 was easy to ride past.
local QUEST_INTERVAL = 1 -- seconds between looking up where the selected quest is

-- The quest selected on the map (the super-tracked one) while Follow Selected Quest is on.
local function selectedQuest()
    if not (module.db.quest and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then
        return nil
    end
    local questID = C_SuperTrack.GetSuperTrackedQuestID()
    if questID and questID ~= 0 then
        return questID
    end
    return nil
end

-- Whether the arrow should point to the corpse: a ghost with Point to Corpse on.
local function followCorpse()
    return module.db.corpse and UnitIsGhost("player") and true or false
end

-- The quest point and the corpse (Lib/WorldMap) are looked up again each QUEST_INTERVAL, not every
-- turn of the arrow, and the map pin once each time it changes (refresh).
local cachedQuest, cachedPoint, cachedTitle, checkedAt = nil, nil, nil, 0
local cachedCorpse, corpseCheckedAt = nil, nil
local cachedWaypoint, cachedNote, waypointRead = nil, nil, false

-- What the arrow points at: the corpse while following it, then the selected quest when it has a
-- spot, otherwise the map pin. The second value is the line to show under the distance, if any
-- (the quest's name, or the pin's note from /way), and the third whether it's the map pin.
local function destination()
    if followCorpse() then
        local now = GetTime()
        if not corpseCheckedAt or now - corpseCheckedAt >= QUEST_INTERVAL then
            cachedCorpse, corpseCheckedAt = WorldMap.CorpsePoint(), now
        end
        if cachedCorpse then
            return cachedCorpse, L.WAYPOINTS_CORPSE_LABEL
        end
    end
    local questID = selectedQuest()
    if questID then
        local now = GetTime()
        if questID ~= cachedQuest or now - checkedAt >= QUEST_INTERVAL then
            -- The same spot keeps the old point, so its route (built per point) isn't built again.
            local point = WorldMap.QuestPoint(questID)
            if not (point and cachedPoint and questID == cachedQuest
                and point.uiMapID == cachedPoint.uiMapID
                and point.position.x == cachedPoint.position.x
                and point.position.y == cachedPoint.position.y) then
                cachedPoint = point
            end
            cachedQuest, checkedAt = questID, now
            cachedTitle = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        end
        if cachedPoint then
            return cachedPoint, module.db.questName and cachedTitle or nil
        end
    end
    if not waypointRead then
        waypointRead = true
        cachedWaypoint = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        cachedNote = noteOf(cachedWaypoint)
    end
    return cachedWaypoint, cachedNote, cachedWaypoint ~= nil
end

-- How far `point` is from the player in yards and its direction counter-clockwise from north,
-- or nil when the game can't say (Lib/WorldMap).
local toward = WorldMap.FromPlayer

-- The arrow -----------------------------------------------------------------------------------

local ARROW_ATLAS = "Navigation-Tracked-Arrow" -- the arrow of Blizzard's own waypoint marker
local ARROW_TEXTURE = "Interface\\Minimap\\MiniMap-QuestArrow" -- older art, if the atlas is gone
local SIZE = 48
local INTERVAL = 0.03 -- seconds between turns, smooth enough to follow the camera

local frame, watcher

-- "120 yds", like Blizzard's own marker.
local distanceText = ns.Text.Yards

local function newFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(SIZE, SIZE)
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetPoint("CENTER")
    if ns.Frames.HasAtlas(ARROW_ATLAS) then
        f.arrow:SetAtlas(ARROW_ATLAS)
    else
        f.arrow:SetTexture(ARROW_TEXTURE)
    end
    f.arrow:SetSize(SIZE * 0.6, SIZE * 0.6)
    f.distance = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.distance:SetPoint("TOP", f, "BOTTOM", 0, 4)
    f.quest = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.quest:SetPoint("TOP", f.distance, "BOTTOM", 0, -2)
    f:Hide()
    return f
end

local function place()
    frame:SetScale(module.db.scale / 100)
    ns.EditMode.Place(frame, module.db.x, module.db.y)
end

-- What the arrow's two lines say now, so they're only set when that changes.
local shownYards, shownTitle

-- Whether the arrow has pointed to the map pin from farther than ARRIVED since it was set, so
-- Clear Pin on Arrival doesn't take away a pin dropped where the player stands.
local headedToPin = false

-- Turns the arrow toward the waypoint, or takes it down when there's no direction to give.
local function update()
    if ns.EditMode.IsActive() then
        return -- the sample stays put while it's being placed
    end
    -- The target, the line to show under the distance, and whether the target is the map pin.
    local point, title, isPin = destination()
    local yards, angle = toward(point)
    if isPin and yards then
        if yards >= ARRIVED then
            headedToPin = true
        elseif headedToPin and module.db.clearOnArrival then
            headedToPin = false
            note = nil
            C_Map.ClearUserWaypoint() -- USER_WAYPOINT_UPDATED refreshes the arrow
        end
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not yards or yards < ARRIVED or not (facing and ns.IsReadable(facing)) then
        frame:Hide()
        return
    end
    frame.arrow:SetRotation(angle - facing)
    local rounded = floor(yards + 0.5)
    if rounded ~= shownYards then
        shownYards = rounded
        frame.distance:SetText(distanceText(yards))
    end
    title = title or ""
    if title ~= shownTitle then
        shownTitle = title
        frame.quest:SetText(title)
    end
    frame:Show()
end

local function arrowWanted()
    if not (module.enabled and module.db.arrow) then
        return false
    end
    return followCorpse() or selectedQuest() ~= nil
        or (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) or false
end

-- Runs the watcher only while there is a corpse, a waypoint, or a selected quest to point at.
local function refresh()
    if not frame then
        return
    end
    cachedQuest = nil -- look the quest up again: the selection or the quest may have changed
    corpseCheckedAt = nil -- and the corpse
    waypointRead = false -- and the map pin
    shownYards, shownTitle = nil, nil
    if arrowWanted() then
        watcher:Show()
        update()
    else
        watcher:Hide()
        if not ns.EditMode.IsActive() then
            frame:Hide()
        end
    end
end

-- A new pin, or none: the player hasn't headed to it yet.
local function waypointChanged()
    headedToPin = false
    refresh()
end

-- Edit Mode -----------------------------------------------------------------------------------

-- In Edit Mode the arrow shows pointing ahead, so it can be placed.
local function sample(active)
    shownYards, shownTitle = nil, nil -- the sample's text replaces what update set
    if active then
        frame.arrow:SetRotation(0)
        frame.distance:SetText(distanceText(120))
        frame.quest:SetText(module.db.quest and module.db.questName and L.WAYPOINTS_QUEST_NAME_SAMPLE
            or "")
        frame:Show()
    else
        frame:Hide()
        refresh()
    end
end

-- What the arrow follows, listened to only while it's on. A new selection shows at once; a quest's
-- spot moving is caught by QUEST_INTERVAL. Releasing to a ghost is PLAYER_ALIVE; coming back to
-- life from one is PLAYER_UNGHOST.
module:OnWhile("arrow", {
    USER_WAYPOINT_UPDATED = waypointChanged,
    PLAYER_ENTERING_WORLD = refresh,
})
module:OnWhile(function(db)
    return db.arrow and db.quest
end, { SUPER_TRACKING_CHANGED = refresh })
module:OnWhile(function(db)
    return db.arrow and db.corpse
end, { PLAYER_ALIVE = refresh, PLAYER_UNGHOST = refresh })

local function syncArrow()
    if module.enabled and module.db.arrow then
        if not frame then
            frame = newFrame()
            watcher = ns.Frames.Watcher(module, INTERVAL, update)
        end
        place()
        ns.EditMode.RegisterModule(module, frame, L.WAYPOINTS_ARROW, place, sample)
    elseif frame then
        ns.EditMode.Unregister(frame)
    end
    refresh()
end

-- What the public API (API.lua) reads while the module is on: where the arrow points, while it's
-- on (its events keep destination()'s cache fresh). It goes through destination() and toward()
-- like the arrow, so they share the route worked out per point.
local provider = {
    Target = function()
        if not module.db.arrow then
            return nil
        end
        local point, _, isPin = destination()
        if not (point and point.uiMapID and point.position) then
            return nil
        end
        local kind = isPin and "pin" or (point == cachedCorpse and "corpse") or "quest"
        local yards = toward(point)
        return { mapID = point.uiMapID, x = point.position.x, y = point.position.y, kind = kind,
            title = kind == "quest" and cachedTitle or nil, yards = yards }
    end,
}

function module:OnEnable()
    ns.Providers.Set("waypoints", provider)
    syncWay()
    syncArrow()
end

function module:OnDisable()
    ns.Providers.Set("waypoints", nil)
    syncWay()
    syncArrow()
end

function module:OnOptionChanged(option)
    if option == "way" then
        syncWay()
    elseif option == "arrow" or option == "quest" or option == "corpse" then
        syncArrow()
    end
end
