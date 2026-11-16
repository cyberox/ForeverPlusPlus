-- Reputation Bar Text: the reputation bar shows its numbers all the time, not only under the
-- mouse, with the percent and your standing, and gets a tooltip, which Blizzard's has none of.
-- Done as XP Bar Text does it: Blizzard's bar text's frame is hidden and a font string of ours,
-- in the same font and spot, shows ours instead. Each status bar container (Edit Mode's two) has
-- its own reputation bar, so both get one. The bars come from Blizzard_StatusTrackingBar
-- (Shared/ReputationBar.lua, Forever build 70938).
--
-- Watch Faction You Gain With moves the bar to the faction whose reputation last went up.
local _, ns = ...

local ipairs, floor, format, wipe = ipairs, math.floor, string.format, wipe
local CreateFrame, GetTime, GameTooltip = CreateFrame, GetTime, GameTooltip
local C_Reputation, C_GossipInfo = C_Reputation, C_GossipInfo

local L = ns.L
local isNumber = ns.IsNumber
local number = ns.Text.Number

local module = ns.NewModule("RepBarText", L.REPBARTEXT_DESC, {
    enabled = true,
    always = true, -- false: only while the mouse is over the bar, like Blizzard's
    percent = true,
    standing = true,
    rate = false,
    tooltip = true,
    autoWatch = false,
    solid = false, -- no divider lines over the bar
})
module.title = L.REPBARTEXT_TITLE
module.category = "character"
module.presets = { developer = { options = { rate = true } } } -- Show Reputation per Hour
module.added = "1.7.1"

module.options = {
    { key = "always", name = L.REPBARTEXT_ALWAYS, description = L.REPBARTEXT_ALWAYS_DESC },
    { key = "percent", name = L.REPBARTEXT_PERCENT, description = L.REPBARTEXT_PERCENT_DESC },
    { key = "standing", name = L.REPBARTEXT_STANDING, description = L.REPBARTEXT_STANDING_DESC },
    { key = "rate", name = L.REPBARTEXT_RATE, description = L.REPBARTEXT_RATE_DESC },
    { key = "tooltip", name = L.REPBARTEXT_TOOLTIP, description = L.REPBARTEXT_TOOLTIP_DESC },
    ns.StatusBars.SolidOption(),
    { key = "autoWatch", name = L.REPBARTEXT_AUTO_WATCH, description = L.REPBARTEXT_AUTO_WATCH_DESC },
}
ns.StatusBars.Solid(module, "Reputation")

local ADDON = "Blizzard_StatusTrackingBar"
local EXALTED = 8 -- the last standing (Blizzard's MAX_REPUTATION_REACTION)
local RATE_AFTER = 60 -- seconds of watching a faction before its pace shows

local texts = setmetatable({}, { __mode = "k" }) -- Blizzard's reputation bar -> our font string
local bars = {} -- the reputation bars, once found

-- "Friendly", in the player's gender where the language has two.
local function standingName(reaction)
    local key = "FACTION_STANDING_LABEL" .. reaction
    return GetText and GetText(key, UnitSex("player")) or _G[key]
end

-- Whether the faction counts some other way than the eight standings (paragon, renown, a
-- friendship): Mainline's kinds, which Forever isn't known to have. Blizzard's own text stays.
local function special(id)
    if C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(id) then
        return true
    end
    if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id) then
        return true
    end
    local friend = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
        and C_GossipInfo.GetFriendshipReputation(id)
    local friendID = friend and friend.friendshipFactionID
    return isNumber(friendID) and friendID > 0
end

-- The watched faction: its ID, name, standing (1 to 8), how far into the standing you are
-- (`value` of `max`), and your reputation in all (`total`). Nil with none watched, one counted
-- another way, or values that can't be read.
local function read()
    -- Probe: C_Reputation is Mainline's.
    local data = C_Reputation and C_Reputation.GetWatchedFactionData
        and C_Reputation.GetWatchedFactionData()
    if not data then
        return nil
    end
    local id, reaction = data.factionID, data.reaction
    local low, high, total = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    if not (isNumber(id) and id ~= 0 and ns.IsText(data.name, true) and isNumber(reaction)
        and isNumber(low) and isNumber(high) and isNumber(total)) or special(id) then
        return nil
    end
    return {
        id = id, name = data.name, reaction = reaction, total = total,
        value = total - low, max = high - low,
        capped = reaction >= EXALTED or high <= low,
    }
end

-- "2,100 (42%)", or just the number with Percent off.
local function amount(n, max)
    if module.db.percent and max > 0 then
        return format(L.REPBARTEXT_AMOUNT, number(n), floor(n / max * 100))
    end
    return number(n)
end

-- The session ----------------------------------------------------------------------------------

-- Each faction's reputation when it was first seen and when that was, for what this session
-- gained and at what pace. Not saved.
local session = {} -- faction ID -> { start = time, first = reputation }

local function note(id, total)
    if not session[id] then
        session[id] = { start = GetTime(), first = total }
    end
end

-- What the session gained with the faction, and that per hour (nil in its first minute and with
-- nothing gained).
local function pace(info)
    local seen = session[info.id]
    if not seen then
        return 0, nil
    end
    local gained = info.total - seen.first
    local elapsed = GetTime() - seen.start
    if elapsed < RATE_AFTER or gained <= 0 then
        return gained, nil
    end
    return gained, gained / elapsed * 3600
end

-- Watch Faction You Gain With ------------------------------------------------------------------

local known = {} -- faction ID -> its reputation at the last look

-- Walks the reputation list and gives the faction that went up the most since the last look, or
-- nil. A faction under a collapsed header isn't in the list, so it isn't seen.
local function gainedWith()
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
        return nil
    end
    local best, bestGain
    for index = 1, (C_Reputation.GetNumFactions()) do
        local data = C_Reputation.GetFactionDataByIndex(index)
        local id, total = data and data.factionID, data and data.currentStanding
        if isNumber(id) and id ~= 0 and isNumber(total) and (not data.isHeader or data.isHeaderWithRep) then
            local old = known[id]
            known[id] = total
            if old and total > old then
                -- The session counts from before this gain, not after it.
                note(id, old)
                if not bestGain or total - old > bestGain then
                    best, bestGain = id, total - old
                end
            end
        end
    end
    return best
end

-- The text and tooltip -------------------------------------------------------------------------

-- Our text, or nil when there's nothing of ours to show (then Blizzard's own text stays).
local function barText(info)
    if not info then
        return nil
    end
    local db = module.db
    local text = info.name
    local standing = db.standing and standingName(info.reaction)
    if standing then
        text = format(L.REPBARTEXT_NAME_STANDING, text, standing)
    end
    if info.capped then
        return text
    end
    text = format(L.REPBARTEXT_REP, text, number(info.value), number(info.max))
    if db.percent then
        text = format(L.REPBARTEXT_WITH_PERCENT, text, floor(info.value / info.max * 100))
    end
    local _, rate = pace(info)
    local nextName = db.rate and rate and standingName(info.reaction + 1)
    if nextName then
        text = text .. "    " .. format(L.REPBARTEXT_RATE_TEXT, number(floor(rate)),
            ns.Text.Clock((info.max - info.value) / rate * 3600), nextName)
    end
    return text
end

-- Blizzard's bar has a tooltip only for a paragon reward, so this one is ours alone: the
-- standing, what's left to the next, and what the session gained and at what pace.
local function showTooltip(bar)
    local info = module.db.tooltip and read()
    if not info then
        return
    end
    GameTooltip_SetDefaultAnchor(GameTooltip, bar)
    GameTooltip:SetText(info.name, 1, 1, 1)
    local function line(label, value)
        GameTooltip:AddDoubleLine(label, value, 1, 1, 1, 1, 1, 1)
    end
    local standing = standingName(info.reaction)
    if standing then
        line(L.REPBARTEXT_TIP_STANDING, standing)
    end
    local nextName = not info.capped and standingName(info.reaction + 1)
    if nextName then
        line(format(L.REPBARTEXT_TIP_LEFT, nextName), amount(info.max - info.value, info.max))
    end
    local gained, rate = pace(info)
    if gained ~= 0 then
        local sign = gained > 0 and "+" or "-"
        line(L.REPBARTEXT_TIP_SESSION, sign .. number(gained > 0 and gained or -gained))
    end
    if rate then
        line(L.REPBARTEXT_TIP_RATE, number(floor(rate)))
        if nextName then
            line(format(L.REPBARTEXT_TIP_TIME, nextName),
                ns.Text.Clock((info.max - info.value) / rate * 3600))
        end
    end
    GameTooltip:Show()
end

local function hideTooltip(bar)
    if GameTooltip:GetOwner() == bar then
        GameTooltip:Hide()
    end
end

local function update(bar)
    local ours = texts[bar]
    if not ours then
        return
    end
    local info = module.enabled and read()
    local text = barText(info)
    if not text then
        ours:Hide()
        bar.OverlayFrame:Show()
        return
    end
    note(info.id, info.total)
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

-- UPDATE_FACTION often comes several times for one gain: look once, a frame later.
local function onFaction()
    local id = module.db.autoWatch and gainedWith()
    if id and C_Reputation.SetWatchedFactionByID then
        local watched = C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
        if not (watched and watched.factionID == id) then
            -- Blizzard's bars follow by themselves, and update() comes from their own Update.
            C_Reputation.SetWatchedFactionByID(id)
        end
    end
    updateAll()
end
local onFactionSoon = ns.Frames.Coalesce(onFaction, nil, module)

-- The pace on the bar drifts down while no reputation comes in, and first shows a minute in:
-- redrawn each minute while it's on, not only when reputation changes.
local rateTimer = ns.Frames.Timer(module)
local function tickRate()
    if module.db.rate then
        updateAll()
        rateTimer:Start(60, tickRate)
    else
        rateTimer:Cancel()
    end
end

-- Finds each container's reputation bar and gives it our text, once.
local function setUp()
    if not module.enabled then
        return
    end
    local manager = StatusTrackingBarManager
    local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        and StatusTrackingBarInfo.BarsEnum.Reputation
    if not (manager and manager.barContainers and index) then
        return
    end
    for _, container in ipairs(manager.barContainers) do
        local bar = container.bars and container.bars[index]
        if bar and bar.OverlayFrame and bar.OverlayFrame.Text and not texts[bar] then
            -- Our own frame like Blizzard's OverlayFrame, so that one (holding only Blizzard's
            -- text) can be hidden while ours shows, as XP Bar Text does.
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
            bars[#bars + 1] = bar
        end
    end
    for _, bar in ipairs(bars) do
        -- Blizzard sets its text in Update and on mouseover, and shows it on mouseover.
        module:Hook(bar, "Update", update)
        module:Hook(bar, "UpdateCurrentText", update)
        module:Hook(bar, "UpdateTextVisibility", update)
        module:HookScript(bar, "OnEnter", showTooltip)
        module:HookScript(bar, "OnLeave", hideTooltip)
    end
    updateAll()
    ns.StatusBars.Refresh()
end

function module:OnEnable()
    ns.AddOns.WhenLoaded(ADDON, setUp)
    wipe(session)
    wipe(known)
    gainedWith() -- the first look only remembers where each faction stands
    self:On("UPDATE_FACTION", onFactionSoon)
    self:On("PLAYER_ENTERING_WORLD", onFactionSoon)
    tickRate()
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, setUp)
    for _, bar in ipairs(bars) do
        texts[bar]:Hide()
        bar.OverlayFrame:Show()
    end
    ns.StatusBars.Refresh()
end

function module:OnOptionChanged(key)
    if key == "rate" then
        tickRate()
    elseif key == "autoWatch" then
        -- Start from where each faction stands now, not from an old look.
        wipe(known)
        gainedWith()
    elseif key == "solid" then
        ns.StatusBars.Refresh()
    end
    updateAll()
end
