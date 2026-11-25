-- Quest Tracker's additions to the header of the tracker's Quests section (QuestObjectiveTracker's
-- Header, Blizzard's ObjectiveTrackerModuleHeaderTemplate): the quest count beside its collapse
-- button, and a menu of the quest log's zones on a click. Everything here is a region or frame of
-- our own on that header; nothing of Blizzard's is moved, resized, or written to. QuestTracker.lua
-- turns it on and off.
local _, ns = ...

local type, ipairs = type, ipairs
local C_QuestLog, C_SuperTrack, Constants = C_QuestLog, C_SuperTrack, Constants
local CreateFrame, GameTooltip = CreateFrame, GameTooltip

local L = ns.L
local module = ns.modules.QuestTracker
local internal = module.internal

---The Quests section's header, or nil on a client whose tracker isn't built this way.
---@return table?
local function header()
    local section = QuestObjectiveTracker
    local frame = type(section) == "table" and section.Header
    return type(frame) == "table" and frame.CreateFontString and frame or nil
end

-- Quest count -------------------------------------------------------------------------------------
-- "12/25": the quests in the log against how many it holds, the numbers Forever's quest log shows
-- above its list (QuestLogQuests_ShowQuestCount, Camelot/QuestMapFrameUtils.lua on the forever
-- branch). In the header's own font, at the right beside the collapse button, and red once the
-- log is full.

local COUNT_GAP = 6 -- pixels between the count and the collapse button
local count -- our font string on the header, made the first time it's needed

-- How many quests the log holds: Blizzard's constant, as the quest log reads it.
local function questLimit()
    local consts = Constants and rawget(Constants, "QuestLogConsts")
    local limit = consts and consts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT
    if type(limit) ~= "number" and C_QuestLog.GetMaxNumQuestsCanAccept then
        limit = C_QuestLog.GetMaxNumQuestsCanAccept()
    end
    return type(limit) == "number" and limit > 0 and limit or nil
end

local function updateCount()
    local frame = header()
    if not (module.enabled and module.db.count and frame) then
        if count then
            count:Hide()
        end
        return
    end
    local _, quests = C_QuestLog.GetNumQuestLogEntries()
    local limit = questLimit()
    if type(quests) ~= "number" or not limit then
        if count then
            count:Hide()
        end
        return
    end
    if not count then
        count = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
        count:SetJustifyH("RIGHT")
        if frame.MinimizeButton then
            count:SetPoint("RIGHT", frame.MinimizeButton, "LEFT", -COUNT_GAP, 0)
        else
            count:SetPoint("RIGHT", frame, "RIGHT", -COUNT_GAP, 0)
        end
    end
    count:SetFormattedText("%d/%d", quests, limit)
    if quests >= limit and RED_FONT_COLOR then
        count:SetTextColor(RED_FONT_COLOR:GetRGB())
    elseif frame.Text and frame.Text.GetTextColor then
        count:SetTextColor(frame.Text:GetTextColor()) -- the header's own color, whatever it is
    end
    count:Show()
end

local requestCount = ns.Frames.Coalesce(updateCount, nil, module)

module:OnWhile("count", { QUEST_LOG_UPDATE = requestCount })

-- Zone menu ---------------------------------------------------------------------------------------
-- Zone Menu makes the header a dropdown: a click on it opens a menu of the zones in the quest log
-- (its headers), each a checkbox that tracks or untracks every quest of that zone, with Track All
-- and Untrack All under them. Real zone headers inside the list aren't possible without laying
-- the tracker out ourselves: a block's place is the sum of the heights before it
-- (ObjectiveTrackerModuleMixin:InternalAddBlock), so room for a header means writing Blizzard's
-- layout fields, which the quest item buttons' layout then reads as ours. This only changes what
-- is tracked, through C_QuestLog, the way the tracker's own right click menu does.
-- The click goes to a button of our own over the header's title, which Blizzard gives no click.
-- Not with the controller interface on, where the header is one of the controller's stops.

local zoneButton -- our button over the header's title, made the first time it's needed

-- The zones of the quest log in its own order: { title, quests = { questID, ... } }, without the
-- ones that list no quest (an empty or collapsed header).
local function logZones()
    local list, byTitle, zone = {}, {}, nil
    for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            zone = nil
            if ns.IsText(info.title, true) then
                zone = byTitle[info.title]
                if not zone then
                    zone = { title = info.title, quests = {} }
                    byTitle[info.title] = zone
                end
            end
        elseif info and zone and info.questID and not (info.isHidden or info.isTask or info.isBounty) then
            if #zone.quests == 0 then
                list[#list + 1] = zone
            end
            zone.quests[#zone.quests + 1] = info.questID
        end
    end
    return list
end

-- Whether every quest of a zone is tracked.
local function allTracked(zone)
    local watched = internal.watchedQuests()
    for _, questID in ipairs(zone.quests) do
        if not watched[questID] then
            return false
        end
    end
    return true
end

-- How many quests the tracker takes, or nil when the client doesn't say.
local function watchLimit()
    local consts = Constants and Constants.QuestWatchConsts
    local limit = consts and consts.MAX_QUEST_WATCHES
    return type(limit) == "number" and limit or nil
end

---Tracks or untracks a list of quests, once combat ends, as every change this module makes to
---the watch list waits. Says so when the tracker is full before they're all on it.
---@param quests number[]
---@param track boolean
local function setTracked(quests, track)
    ns.AfterCombat(function()
        if not module.enabled then
            return
        end
        local watched = internal.watchedQuests()
        if track then
            local limit = watchLimit()
            for _, questID in ipairs(quests) do
                if not watched[questID] then
                    if limit and C_QuestLog.GetNumQuestWatches() >= limit then
                        ns.Print(L.QUESTTRACKER_ZONES_FULL:format(limit))
                        break
                    end
                    C_QuestLog.AddQuestWatch(questID)
                end
            end
            return
        end
        -- Untracking a quest can drop it as the quest the map and arrow follow, so put that back.
        local super = ns.Quests.Selected()
        for _, questID in ipairs(quests) do
            if watched[questID] then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        end
        if super and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and ns.Quests.Selected() ~= super then
            C_SuperTrack.SetSuperTrackedQuestID(super)
        end
    end)
end

local function zoneMenu(_, root)
    root:CreateTitle(L.QUESTTRACKER_ZONES_TITLE)
    local zones = logZones()
    local all = {}
    for _, zone in ipairs(zones) do
        for _, questID in ipairs(zone.quests) do
            all[#all + 1] = questID
        end
        root:CreateCheckbox(L.QUESTTRACKER_ZONES_ENTRY:format(zone.title, #zone.quests), function()
            return allTracked(zone)
        end, function()
            setTracked(zone.quests, not allTracked(zone))
        end)
    end
    if #zones == 0 then
        root:CreateButton(L.QUESTTRACKER_ZONES_NONE):SetEnabled(false)
        return
    end
    root:CreateDivider()
    root:CreateButton(L.QUESTTRACKER_ZONES_ALL, function() setTracked(all, true) end)
    root:CreateButton(L.QUESTTRACKER_ZONES_CLEAR, function() setTracked(all, false) end)
end

local function onZoneEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip_SetTitle(GameTooltip, L.QUESTTRACKER_ZONES_TITLE)
    GameTooltip:AddLine(L.QUESTTRACKER_ZONES_HINT, GREEN_FONT_COLOR:GetRGB())
    GameTooltip:Show()
end

local function onZoneLeave()
    GameTooltip:Hide()
end

local function onZoneClick(self)
    if module.enabled and module.db.zones and not ns.Gamepad.On() then
        GameTooltip:Hide()
        ns.Menus.Open(self, zoneMenu)
    end
end

local function updateZoneButton()
    local frame = header()
    if not (module.enabled and module.db.zones and frame) or ns.Gamepad.On() then
        if zoneButton then
            zoneButton:Hide()
        end
        return
    end
    if not zoneButton then
        zoneButton = CreateFrame("Button", nil, frame)
        zoneButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        if frame.MinimizeButton then
            zoneButton:SetPoint("BOTTOMRIGHT", frame.MinimizeButton, "BOTTOMLEFT", 0, 0)
        else
            zoneButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        zoneButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        zoneButton:SetScript("OnClick", onZoneClick)
        zoneButton:SetScript("OnEnter", onZoneEnter)
        zoneButton:SetScript("OnLeave", onZoneLeave)
    end
    zoneButton:Show()
end

-- For QuestTracker.lua -----------------------------------------------------------------------------

---Shows or hides what the header gets, as the module or one of these options turns on or off.
function internal.updateHeader()
    updateCount()
    updateZoneButton()
end
