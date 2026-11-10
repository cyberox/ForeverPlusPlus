-- Forever Quest Icons: a small icon after the name of quests that are new to Forever, the ones
-- that weren't in original Classic, in the quest log on the world map, the objective tracker, a
-- quest giver's list of quests, and the title of a quest's details, each with its own checkbox.
-- Idea from ForeverQuestTint; none of its code.
--
-- New quests are told apart by ID. Every quest of original Classic has an ID of 9665 or less
-- (inferred from Classic quest data), so a higher ID is a quest Forever added.
--
-- The icon is a texture in the title's text, cut down to its art so it sits at the text's height.
-- Blizzard measures a row's height from its text before we add to it, so a title the icon would
-- push onto another line is left without one.
local _, ns = ...

local ipairs, type, format, floor = ipairs, type, string.format, math.floor
local setmetatable, sub = setmetatable, string.sub

local L = ns.L
local Quests = ns.Quests

local module = ns.NewModule("ForeverQuestIcons", L.FOREVERQUESTICONS_DESC, {
    enabled = true,
    log = true,
    tracker = true,
    givers = true,
    details = true,
    icon = "logo", -- a key of ICONS
    color = "blue", -- a key of COLORS, for an icon that takes one
    -- Icon size in each place, in percent, picked by eye in game.
    logSize = 100,
    trackerSize = 100,
    giversSize = 80,
    -- The details title's font is larger, so a smaller share keeps the icon near the lists' size.
    detailsSize = 60,
})
module.title = L.FOREVERQUESTICONS_TITLE
module.category = "quests"

-- A place's checkbox, with its size slider in the same row.
local function place(key, name, description, added)
    local sizeKey = key .. "Size"
    return { key = key, name = name, description = description, slider = sizeKey, added = added },
        { key = sizeKey, name = L.FOREVERQUESTICONS_SIZE, description = L.FOREVERQUESTICONS_SIZE_DESC,
            requires = key, min = 50, max = 300, step = 10, format = "%d%%" }
end

-- Each icon: an atlas, or a texture file the client has but no atlas names; `crop` is the art's
-- part of it (left, right, top, bottom, as shares), cut from the empty room around it (measured
-- on build 1.60.1.70862's files); `aspect` is the art's width over its height, and `height` its
-- height at 100% as a share of the text's font size. One with `tint` is plain art a color suits.
local ICONS = {
    -- The blue medallion of the login screen and the launcher, a W on the infinity loop.
    medallion = {
        file = "Interface\\Glues\\Common\\Glues-WoW-ForeverLogo-Infinity",
        crop = { 0.1191, 0.5488, 0, 1 }, aspect = 220 / 256, height = 1.35,
    },
    -- The Trading Post's infinity sign.
    infinity = {
        atlas = "perks-infinity", crop = { 0.0294, 0.9706, 0.0556, 0.9444 }, aspect = 2,
        height = 1, tint = true,
    },
    -- The Forever logo of the game menu, in one flat color.
    logo = {
        atlas = "logo-wow-forever", crop = { 0.2562, 0.7688, 0.2281, 0.7906 }, aspect = 164 / 180,
        height = 1.35, tint = true,
    },
    coin = { atlas = "tokens-wow-generic-small", aspect = 1, height = 1.2 },
    star = { atlas = "campcollection-icon-star", aspect = 20 / 19, height = 1.1 },
}

-- Colors for an icon with `tint`, as the texture's vertex color.
local COLORS = {
    gold = { 255, 209, 0 }, -- NORMAL_FONT_COLOR, Blizzard's gold text
    blue = { 64, 190, 230 }, -- the medallion's blue
}

module.options = {
    {
        key = "icon", name = L.FOREVERQUESTICONS_ICON, description = L.FOREVERQUESTICONS_ICON_DESC,
        choices = {
            { "medallion", L.FOREVERQUESTICONS_ICON_MEDALLION },
            { "infinity", L.FOREVERQUESTICONS_ICON_INFINITY },
            { "logo", L.FOREVERQUESTICONS_ICON_LOGO },
            { "coin", L.FOREVERQUESTICONS_ICON_COIN },
            { "star", L.FOREVERQUESTICONS_ICON_STAR },
        },
        changed = "1.5.0", -- more icons, and the Forever logo in blue by default
    },
    {
        key = "color", name = L.FOREVERQUESTICONS_COLOR, description = L.FOREVERQUESTICONS_COLOR_DESC,
        choices = {
            { "art", L.FOREVERQUESTICONS_COLOR_ART },
            { "gold", L.FOREVERQUESTICONS_COLOR_GOLD },
            { "blue", L.FOREVERQUESTICONS_COLOR_BLUE },
        },
        shown = function(db)
            local icon = ICONS[db.icon]
            return icon ~= nil and icon.tint == true
        end,
        added = "1.5.0",
    },
}
for _, args in ipairs({
    { "log", L.FOREVERQUESTICONS_LOG, L.FOREVERQUESTICONS_LOG_DESC },
    { "tracker", L.FOREVERQUESTICONS_TRACKER, L.FOREVERQUESTICONS_TRACKER_DESC },
    { "givers", L.FOREVERQUESTICONS_GIVERS, L.FOREVERQUESTICONS_GIVERS_DESC },
    { "details", L.FOREVERQUESTICONS_DETAILS, L.FOREVERQUESTICONS_DETAILS_DESC, "0.9.0" },
}) do
    local toggle, size = place(args[1], args[2], args[3], args[4])
    module.options[#module.options + 1] = toggle
    module.options[#module.options + 1] = size
end

-- The last quest ID of original Classic (inferred from Classic quest data). Nothing in play says
-- it, so a fix ships as a new seed.
local CLASSIC_QUESTS = ns.GameData.New("foreverQuestIcons", { lastClassicQuest = 9665 },
    { label = "Forever Quest Icons" })

-- Texel coordinates in |T markup are out of the size given with them, so any file's shares fit.
local TEXELS = 10000

-- Where an icon's art is: its file (a path or file ID) and its part of it, as shares. An atlas is
-- looked up (atlas names change between builds); nil when this client hasn't got it.
local function source(icon)
    local l, r, t, b = 0, 1, 0, 1
    local crop = icon.crop
    if crop then
        l, r, t, b = crop[1], crop[2], crop[3], crop[4]
    end
    if icon.file then
        return icon.file, l, r, t, b
    end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon.atlas)
    if not (info and info.file) then
        return nil
    end
    local width = info.rightTexCoord - info.leftTexCoord
    local height = info.bottomTexCoord - info.topTexCoord
    return info.file, info.leftTexCoord + l * width, info.leftTexCoord + r * width,
        info.topTexCoord + t * height, info.topTexCoord + b * height
end

-- How far to raise the icon in a place (lower, when negative), as a share of the font's size, so
-- its middle meets the letters'. Measured on screenshots, 2026-11-10: in the tracker it sat about
-- 2 px low, in a quest giver's list about 1 px high.
local LIFT = { tracker = 0.15, givers = -0.08 }

local function iconFor(fontString, percent, place)
    local icon = ICONS[module.db.icon] or ICONS.medallion
    local file, l, r, t, b = source(icon)
    if not file then
        -- The medallion is a file every Forever client has, so it stands in for a missing atlas.
        icon = ICONS.medallion
        file, l, r, t, b = source(icon)
    end
    local _, fontSize = fontString:GetFont()
    fontSize = fontSize or 12
    local size = fontSize * (percent or 100) / 100
    local height = floor(size * icon.height + 0.5)
    local width = floor(height * icon.aspect + 0.5)
    local lift = floor(fontSize * (LIFT[place] or 0) + 0.5)
    local markup = format("|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d", file, height, width, lift, TEXELS, TEXELS,
        floor(l * TEXELS + 0.5), floor(r * TEXELS + 0.5), floor(t * TEXELS + 0.5),
        floor(b * TEXELS + 0.5))
    local color = icon.tint and COLORS[module.db.color]
    if color then
        markup = markup .. format(":%d:%d:%d", color[1], color[2], color[3])
    end
    return markup .. "|t"
end

local function isNew(questID)
    return type(questID) == "number" and questID > CLASSIC_QUESTS:Get("lastClassicQuest")
end

-- What we last put at the end of each title, kept apart from Blizzard's font strings.
local added = setmetatable({}, { __mode = "k" })

-- A title without our icon at its end, so a title can be marked again (another icon, or none)
-- without stacking icons, even after something else (Quest Levels) changed the rest of it. A
-- title Blizzard wrote again doesn't end with it, and stays as it is.
local function plain(fontString, text)
    local suffix = added[fontString]
    if suffix and #text >= #suffix and sub(text, -#suffix) == suffix then
        return sub(text, 1, #text - #suffix)
    end
    return text
end

---Adds the icon to a quest title, or takes it off.
---@param fontString table the title's font string
---@param questID number|nil
---@param place string "log", "tracker", "givers", or "details": its checkbox and size
local function mark(fontString, questID, place)
    if not fontString then
        return
    end
    local text = fontString:GetText()
    if type(text) ~= "string" then
        return
    end
    text = plain(fontString, text)
    local db = module.db
    local icon = module.enabled and db[place] and isNew(questID)
        and iconFor(fontString, db[place .. "Size"], place)
    local suffix = icon and " " .. icon or nil
    local wanted = suffix and text .. suffix or text
    if wanted ~= fontString:GetText() then
        if suffix and fontString.GetNumLines then
            -- Count the lines of the plain title, not of one we marked before.
            fontString:SetText(text)
            local lines = fontString:GetNumLines()
            fontString:SetText(wanted)
            if fontString:GetNumLines() > lines then
                fontString:SetText(text)
                suffix = nil
            end
        else
            fontString:SetText(wanted)
        end
    end
    added[fontString] = suffix
end

-- The quest log beside the world map.
local function markLog()
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool then
        return
    end
    for button in pool:EnumerateActive() do
        mark(button.Text, button.questID, "log")
    end
end

-- The objective tracker: its quest and campaign quest sections, each block's id a quest ID.
local TRACKERS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local function markBlock(block)
    mark(block.HeaderText, block.id, "tracker")
end

local function markTrackerQuest(tracker, quest)
    local block = quest and quest.GetID and tracker.GetExistingBlock
        and tracker:GetExistingBlock(quest:GetID())
    if block then
        markBlock(block)
    end
end

local function markTracker()
    for _, name in ipairs(TRACKERS) do
        local tracker = _G[name]
        if tracker and tracker.EnumerateActiveBlocks then
            tracker:EnumerateActiveBlocks(markBlock)
        end
    end
end

-- A quest giver's list, the gossip way (most NPCs).
local function markGossip()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    local box = panel and panel.ScrollBox
    if not (box and box.ForEachFrame) then
        return
    end
    box:ForEachFrame(function(button)
        local data = button.GetElementData and button:GetElementData()
        local kind = data and data.buttonType
        if kind == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST or kind == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then
            mark(button:GetFontString(), data.info and data.info.questID, "givers")
        end
    end)
end

-- A quest giver's list, the older greeting way.
local function markGreeting()
    local panel = QuestFrameGreetingPanel
    local pool = panel and panel.titleButtonPool
    if not pool then
        return
    end
    for button in pool:EnumerateActive() do
        mark(button:GetFontString(), (Quests.GreetingButton(button)), "givers")
    end
end

-- The title of a quest's details: QuestInfo_Display fills them for a quest giver's offer and
-- reward, and for the quest log on the map.
local function markDetails()
    mark(QuestInfoTitleHeader, Quests.DetailsID(), "details")
end

-- The window that asks for a quest's items before you turn it in.
local function markProgress()
    mark(QuestProgressTitleText, Quests.GiverID(), "details")
end

-- The tracker is its own Blizzard addon. Each tracker frame has its own copy of the method, so
-- the frame is hooked.
local function hookTracker()
    for _, name in ipairs(TRACKERS) do
        module:Hook(_G[name], "UpdateSingle", markTrackerQuest)
    end
    markTracker()
end

local function markAll()
    markLog()
    markTracker()
    markGossip()
    markGreeting()
    markDetails()
    markProgress()
end

function module:OnEnable()
    self:Hook("QuestLogQuests_Update", markLog)
    ns.AddOns.WhenLoaded("Blizzard_ObjectiveTracker", hookTracker)
    -- Runs when the list is filled and when it scrolls.
    self:Hook(GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox,
        "Update", markGossip)
    if QuestFrameGreetingPanel then
        -- The panel's script holds the function it had at load, and Blizzard also calls the
        -- global itself, so both are hooked.
        self:HookScript(QuestFrameGreetingPanel, "OnShow", markGreeting)
        self:Hook("QuestFrameGreetingPanel_OnShow", markGreeting)
    end
    self:Hook("QuestInfo_Display", markDetails)
    self:HookScript(QuestFrameProgressPanel, "OnShow", markProgress)
    self:Hook("QuestFrameProgressPanel_OnShow", markProgress)
    markAll()
end

-- Hooks stop by themselves; the titles showing now get their own text back.
function module:OnDisable()
    ns.AddOns.Cancel("Blizzard_ObjectiveTracker", hookTracker)
    markAll()
end

function module:OnOptionChanged()
    markAll()
end
