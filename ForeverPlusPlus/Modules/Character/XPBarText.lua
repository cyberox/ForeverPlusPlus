-- XP Bar Text: the experience bar shows its numbers all the time, not only under the mouse, with
-- the percent, your rested XP, and the XP the quests in your log will give. Blizzard's bar text's
-- frame is hidden and a font string of ours, in the same font and spot, shows ours instead. Each
-- status bar container (Edit Mode's two) has its own experience bar, so both get one. The bars
-- come from Blizzard_StatusTrackingBar (FrameXML on Forever build 70338).
--
-- Quest XP on Bar fills the bar on from your XP with what the quests ready to turn in give, in
-- green, the way Blizzard's bar already shows rested XP ahead of it (ExhaustionLevelFillBar).
local _, ns = ...

local ipairs, floor, format, min = ipairs, math.floor, string.format, math.min
local CreateFrame, GetTime, UnitLevel = CreateFrame, GetTime, UnitLevel
local UnitXP, UnitXPMax, GetXPExhaustion = UnitXP, UnitXPMax, GetXPExhaustion
local C_QuestLog = C_QuestLog

local L = ns.L
local readable = ns.IsReadable
local number = ns.Text.Number

local module = ns.NewModule("XPBarText", L.XPBARTEXT_DESC, {
    enabled = true,
    always = true, -- false: only while the mouse is over the bar, like Blizzard's
    percent = true,
    rested = true,
    quests = "complete", -- "off", "complete" (ready to turn in), or "all"
    questColor = true,
    rate = false,
    questBar = true,
    tooltip = true,
})
module.title = L.XPBARTEXT_TITLE
module.category = "character"
module.added = "0.8.0"

module.options = {
    {
        key = "always", name = L.XPBARTEXT_ALWAYS, description = L.XPBARTEXT_ALWAYS_DESC,
        section = L.XPBARTEXT_SECTION_TEXT,
    },
    {
        key = "percent", name = L.XPBARTEXT_PERCENT, description = L.XPBARTEXT_PERCENT_DESC,
        section = L.XPBARTEXT_SECTION_TEXT,
    },
    {
        key = "rested", name = L.XPBARTEXT_RESTED, description = L.XPBARTEXT_RESTED_DESC,
        section = L.XPBARTEXT_SECTION_TEXT,
    },
    {
        key = "quests", name = L.XPBARTEXT_QUESTS, description = L.XPBARTEXT_QUESTS_DESC,
        choices = {
            { "complete", L.XPBARTEXT_QUESTS_COMPLETE },
            { "all", L.XPBARTEXT_QUESTS_ALL },
            { "off", L.XPBARTEXT_QUESTS_OFF },
        },
        section = L.XPBARTEXT_SECTION_TEXT,
    },
    {
        key = "questColor", name = L.XPBARTEXT_QUEST_COLOR, description = L.XPBARTEXT_QUEST_COLOR_DESC,
        added = "0.9.0", section = L.XPBARTEXT_SECTION_TEXT, requires = "quests",
    },
    {
        key = "rate", name = L.XPBARTEXT_RATE, description = L.XPBARTEXT_RATE_DESC,
        added = "1.0.3", section = L.XPBARTEXT_SECTION_TEXT,
    },
    {
        key = "questBar", name = L.XPBARTEXT_QUEST_BAR, description = L.XPBARTEXT_QUEST_BAR_DESC,
        added = "0.9.0", section = L.XPBARTEXT_SECTION_BAR,
    },
    {
        key = "tooltip", name = L.XPBARTEXT_TOOLTIP, description = L.XPBARTEXT_TOOLTIP_DESC,
        added = "0.9.0", section = L.XPBARTEXT_SECTION_BAR,
    },
}

local ADDON = "Blizzard_StatusTrackingBar"
-- The reputation bar's green, a fill made for this bar.
local QUEST_FILL = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green"
-- Tooltip values in their colors on the bar: Blizzard's rested blue, and our quest green.
local RESTED_COLOR = { 0.25, 0.6, 1 }
local READY_COLOR = { 0.25, 0.85, 0.25 }

local texts = setmetatable({}, { __mode = "k" }) -- Blizzard's experience bar -> our font string
local fills = setmetatable({}, { __mode = "k" }) -- Blizzard's experience bar -> our quest fill
local bars = {} -- the experience bars, once found
local questXP = 0 -- what the Quest XP choice counts, for the text
local readyXP = 0 -- what the quests ready to turn in give
local allXP = 0 -- what all the quests in the log give

-- Your XP and the XP the level needs, or nil when they can't be read (secret values).
local function readXP()
    local current, max = UnitXP("player"), UnitXPMax("player")
    if readable(current) and readable(max) and type(current) == "number"
        and type(max) == "number" and max > 0 then
        return current, max
    end
end

-- Your rested XP, or nil when there's none or it can't be read.
local function readRested()
    local rested = GetXPExhaustion and GetXPExhaustion()
    if ns.IsNumber(rested) and rested > 0 then
        return rested
    end
end

-- "2,100 (42%)", or just the number with Percent off.
local function amount(n, max)
    if module.db.percent and max > 0 then
        return format(L.XPBARTEXT_AMOUNT, number(n), floor(n / max * 100))
    end
    return number(n)
end

-- The XP the quests in your log give, those ready to turn in and all of them: the text shows one
-- (the Quest XP choice), the bar the first, the tooltip both. A quest's reward reads 0 until the
-- game has its data; QUEST_LOG_UPDATE comes when it does.
local function countQuestXP()
    questXP, readyXP, allXP = 0, 0, 0
    local which = module.db.quests
    if not (GetQuestLogRewardXP and C_QuestLog and C_QuestLog.GetNumQuestLogEntries
        and C_QuestLog.GetInfo) then
        return
    end
    local isComplete = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
    for index = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(index)
        local id = info and not info.isHeader and info.questID
        if id then
            local xp = GetQuestLogRewardXP(id)
            if ns.IsNumber(xp) then
                allXP = allXP + xp
                if isComplete and isComplete(id) then
                    readyXP = readyXP + xp
                end
            end
        end
    end
    questXP = (which == "all" and allXP) or (which == "complete" and readyXP) or 0
end

-- XP gained since login (or since the module came on), for XP per hour and time to level.
local session = {}

local function trackXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not (readable(xp) and readable(max) and readable(level) and type(xp) == "number"
        and type(max) == "number" and type(level) == "number") then
        return
    end
    if not session.xp then
        session.start, session.gained = GetTime(), 0
    elseif level > session.level then
        -- Leveled: the rest of the old level, then what's into the new one.
        session.gained = session.gained + (session.max - session.xp) + xp
    elseif xp > session.xp then
        session.gained = session.gained + (xp - session.xp)
    end
    session.xp, session.max, session.level = xp, max, level
end

-- XP per hour this session, or nil before there's a minute of it with XP gained.
local function xpPerHour()
    local elapsed = session.start and GetTime() - session.start or 0
    if elapsed < 60 or session.gained <= 0 then
        return nil
    end
    return session.gained / elapsed * 3600
end

-- Our lines under Blizzard's tooltip for the bar, which it builds on every mouseover: Blizzard's
-- has your XP and rested state, ours what's left, rested XP, quest XP, and the pace.
local function addTooltip()
    if not module.db.tooltip then
        return
    end
    local tooltip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
    local current, max = readXP()
    -- Blizzard's builds nothing without a rest state; then there's nothing to add to.
    if not (tooltip:IsShown() and tooltip:GetOwner() == UIParent and current) then
        return
    end
    -- A value's color, when it has one, is its color on the bar.
    local function line(label, value, color)
        local r, g, b = 1, 1, 1
        if color then
            r, g, b = color[1], color[2], color[3]
        end
        tooltip:AddDoubleLine(label, value, 1, 1, 1, r, g, b)
    end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    line(L.XPBARTEXT_TIP_LEFT, amount(max - current, max))
    local rested = readRested()
    if rested then
        line(L.XPBARTEXT_TIP_RESTED, amount(rested, max), RESTED_COLOR)
    end
    if readyXP > 0 then
        line(L.XPBARTEXT_TIP_READY, amount(readyXP, max), READY_COLOR)
    end
    if allXP > readyXP then
        line(L.XPBARTEXT_TIP_ALL, amount(allXP, max))
    end
    local rate = xpPerHour()
    if rate then
        line(L.XPBARTEXT_TIP_RATE, number(floor(rate)))
        line(L.XPBARTEXT_TIP_TIME, ns.Text.Clock((max - current) / rate * 3600))
    end
    tooltip:Show()
end

-- Our text, or nil when the XP can't be read (then Blizzard's own text stays).
local function barText(current, max)
    if not current then
        return nil
    end
    local text = format(L.XPBARTEXT_XP, number(current), number(max))
    if module.db.percent then
        text = format(L.XPBARTEXT_WITH_PERCENT, text, floor(current / max * 100))
    end
    local rested = module.db.rested and readRested()
    if rested then
        text = text .. "    " .. format(L.XPBARTEXT_RESTED_TEXT, amount(rested, max))
    end
    if module.db.quests ~= "off" and questXP > 0 then
        local quests = format(L.XPBARTEXT_QUESTS_TEXT, amount(questXP, max))
        if module.db.questColor and current + questXP >= max then
            -- Enough to level: green, like a quest you can turn in.
            quests = ns.Colors.Text(GREEN_FONT_COLOR, quests)
        end
        text = text .. "    " .. quests
    end
    local rate = module.db.rate and xpPerHour()
    if rate then
        text = text .. "    " .. format(L.XPBARTEXT_RATE_TEXT, number(floor(rate)),
            ns.Text.Clock((max - current) / rate * 3600))
    end
    return text
end

-- Our green fill from the end of Blizzard's XP fill, as long as the ready quests' XP, up to the
-- bar's end. It follows Blizzard's fill as that grows, and hides where the XP can't be read.
local function updateFill(bar, current, max)
    local fill = fills[bar]
    local xpFill = bar.StatusBar:GetStatusBarTexture()
    if not (module.enabled and module.db.questBar and readyXP > 0 and xpFill and current
        and current < max and not (IsXPUserDisabled and IsXPUserDisabled())) then
        fill:Hide()
        return
    end
    local width = bar.StatusBar:GetWidth()
    local gain = min(readyXP, max - current)
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", xpFill, "TOPRIGHT")
    fill:SetPoint("BOTTOMLEFT", xpFill, "BOTTOMRIGHT")
    fill:SetWidth(gain / max * width)
    -- The part of the art this stretch of the bar would show, as Blizzard does for rested XP.
    fill:SetTexCoord(current / max, (current + gain) / max, 0, 1)
    fill:Show()
end

local function update(bar)
    local ours = texts[bar]
    if not ours then
        return
    end
    -- Read once for the fill and the text.
    local current, max = readXP()
    updateFill(bar, current, max)
    local text = module.enabled and barText(current, max)
    if not text then
        ours:Hide()
        bar.OverlayFrame:Show()
        return
    end
    bar.OverlayFrame:Hide()
    ours:SetText(text)
    ours:SetShown(module.db.always or (bar.ShouldBarTextBeDisplayed
        and bar:ShouldBarTextBeDisplayed()) or false)
end

local function updateAll()
    for _, bar in ipairs(bars) do
        update(bar)
    end
end

local function refreshQuests()
    countQuestXP()
    updateAll()
end
-- QUEST_LOG_UPDATE often comes several times in one frame (a kill, a turn-in): count once, a
-- frame later.
local refreshSoon = ns.Frames.Coalesce(refreshQuests, nil, module)

-- XP per hour on the bar drifts down while no XP comes in, and first shows a minute in: redrawn
-- each minute while it's on, not only on XP updates.
local rateTimer = ns.Frames.Timer(module)
local function tickRate()
    if module.db.rate then
        updateAll()
        rateTimer:Start(60, tickRate)
    else
        rateTimer:Cancel()
    end
end

-- The bar's width changes with Edit Mode and the action bars.
local function onResized(statusBar)
    update(statusBar:GetParent())
end

-- A frame of ours over Blizzard's XP fill and rested XP, but under the bar's border and text,
-- which are a strata higher, holding the quest fill.
local function newFill(bar)
    local frame = CreateFrame("Frame", nil, bar)
    frame:SetAllPoints(bar.StatusBar)
    frame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 1)
    local fill = frame:CreateTexture(nil, "ARTWORK")
    if ns.Frames.HasAtlas(QUEST_FILL) then
        fill:SetAtlas(QUEST_FILL)
    else
        fill:SetColorTexture(0.1, 0.6, 0.1)
    end
    -- A darker green than the art, so it reads as XP still to come and stands apart from rested XP.
    fill:SetVertexColor(0.55, 0.55, 0.55)
    fill:Hide()
    return fill
end

-- Finds each container's experience bar and gives it our text, once.
local function setUp()
    if not module.enabled then
        return
    end
    local manager = StatusTrackingBarManager
    local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        and StatusTrackingBarInfo.BarsEnum.Experience
    if not (manager and manager.barContainers and index) then
        return
    end
    for _, container in ipairs(manager.barContainers) do
        local bar = container.bars and container.bars[index]
        if bar and bar.OverlayFrame and bar.OverlayFrame.Text and bar.StatusBar and not texts[bar] then
            -- Our own frame like Blizzard's OverlayFrame, so that one (holding only Blizzard's
            -- text) can be hidden while ours shows. Hidden, not alpha 0: on Forever something
            -- outside Lua put its alpha back to 1 just after login (2026-10-13).
            local holder = CreateFrame("Frame", nil, bar)
            holder:SetFrameStrata("MEDIUM")
            holder:SetAllPoints(bar.OverlayFrame)
            -- Above the bar's divider lines and border, as Blizzard's text is.
            holder:SetFrameLevel(bar.OverlayFrame:GetFrameLevel() + 1)
            local ours = holder:CreateFontString(nil, "ARTWORK", "TextStatusBarText")
            ours:SetDrawLayer("ARTWORK", 5)
            ours:SetPoint("CENTER", holder, "CENTER", 0, 0)
            ours:Hide()
            texts[bar] = ours
            fills[bar] = newFill(bar)
            bars[#bars + 1] = bar
        end
    end
    for _, bar in ipairs(bars) do
        -- Blizzard sets its text on every XP update and shows it on mouseover.
        module:Hook(bar, "UpdateCurrentText", update)
        module:Hook(bar, "UpdateTextVisibility", update)
        module:HookScript(bar.StatusBar, "OnSizeChanged", onResized)
        -- The bar's mouseover tooltip, built by its rested XP marker.
        module:Hook(bar.ExhaustionTick, "ExhaustionToolTipText", addTooltip)
    end
    refreshQuests()
end

function module:OnEnable()
    ns.AddOns.WhenLoaded(ADDON, setUp)
    session = {}
    trackXP()
    self:On("PLAYER_XP_UPDATE", function()
        trackXP()
        updateAll()
    end)
    self:On("UPDATE_EXHAUSTION", updateAll)
    self:On("PLAYER_LEVEL_UP", updateAll)
    self:On("PLAYER_ENTERING_WORLD", refreshQuests)
    self:On("QUEST_LOG_UPDATE", refreshSoon)
    tickRate()
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, setUp)
    for _, bar in ipairs(bars) do
        texts[bar]:Hide()
        fills[bar]:Hide()
        bar.OverlayFrame:Show()
    end
end

function module:OnOptionChanged(key)
    if key == "rate" then
        tickRate()
    end
    refreshQuests()
end
