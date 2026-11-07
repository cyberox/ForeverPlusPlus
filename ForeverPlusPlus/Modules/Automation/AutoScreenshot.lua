-- Auto Screenshot: takes a screenshot when something worth keeping happens: a level up, an
-- achievement, good loot, a boss kill, and more, each with its own checkbox. The shot waits a
-- moment so Blizzard's toast is on screen, and can leave the interface out, also from the shots
-- the player takes with the Screenshot key. It can also ask for /played on a level up, so the
-- time is in chat (and in the shot).
local _, ns = ...

local ipairs, format, tonumber, type = ipairs, string.format, tonumber, type
local concat = table.concat
local C_Timer, C_Item = C_Timer, C_Item
local Screenshot, InCombatLockdown, UIParent = Screenshot, InCombatLockdown, UIParent
local CreateFrame, GetBindingKey = CreateFrame, GetBindingKey
local SetOverrideBindingClick, ClearOverrideBindings = SetOverrideBindingClick, ClearOverrideBindings
local GetNumTitles, IsTitleKnown, GetTime = GetNumTitles, IsTitleKnown, GetTime
local RequestTimePlayed = RequestTimePlayed

local L = ns.L
local readable = ns.IsReadable

local module = ns.NewModule("AutoScreenshot", L.AUTOSCREENSHOT_DESC, {
    enabled = false,
    levelUp = true,
    achievement = true,
    loot = false,
    lootQuality = "4", -- Enum.ItemQuality: 3 rare, 4 epic, 5 legendary
    bossKill = true,
    reputation = false,
    pvpRank = false,
    title = false,
    battleground = false,
    death = false,
    hideUI = false,
    playedTime = false,
    hideOwn = false,
    chat = true,
})
module.title = L.AUTOSCREENSHOT_TITLE
module.category = "automation"

local GENERAL, EVENTS = L.AUTOSCREENSHOT_SECTION_GENERAL, L.AUTOSCREENSHOT_SECTION_EVENTS

module.options = {
    { key = "hideUI", name = L.AUTOSCREENSHOT_HIDE_UI, description = L.AUTOSCREENSHOT_HIDE_UI_DESC,
        section = GENERAL },
    { key = "hideOwn", name = L.AUTOSCREENSHOT_HIDE_OWN, description = L.AUTOSCREENSHOT_HIDE_OWN_DESC,
        section = GENERAL, requires = "hideUI", added = "0.8.0" },
    ns.ChatOption(L.AUTOSCREENSHOT_CHAT_DESC, GENERAL),
    { key = "levelUp", name = L.AUTOSCREENSHOT_LEVEL_UP, description = L.AUTOSCREENSHOT_LEVEL_UP_DESC,
        section = EVENTS },
    { key = "playedTime", name = L.AUTOSCREENSHOT_PLAYED_TIME,
        description = L.AUTOSCREENSHOT_PLAYED_TIME_DESC, section = EVENTS, requires = "levelUp",
        added = "0.8.0" },
    { key = "achievement", name = L.AUTOSCREENSHOT_ACHIEVEMENT,
        description = L.AUTOSCREENSHOT_ACHIEVEMENT_DESC, section = EVENTS },
    { key = "loot", name = L.AUTOSCREENSHOT_LOOT, description = L.AUTOSCREENSHOT_LOOT_DESC,
        section = EVENTS },
    {
        key = "lootQuality",
        name = L.AUTOSCREENSHOT_LOOT_QUALITY,
        description = L.AUTOSCREENSHOT_LOOT_QUALITY_DESC,
        section = EVENTS,
        requires = "loot",
        choices = {
            { "3", L.AUTOSCREENSHOT_QUALITY_RARE },
            { "4", L.AUTOSCREENSHOT_QUALITY_EPIC },
            { "5", L.AUTOSCREENSHOT_QUALITY_LEGENDARY },
        },
    },
    { key = "bossKill", name = L.AUTOSCREENSHOT_BOSS_KILL, description = L.AUTOSCREENSHOT_BOSS_KILL_DESC,
        section = EVENTS },
    { key = "reputation", name = L.AUTOSCREENSHOT_REPUTATION,
        description = L.AUTOSCREENSHOT_REPUTATION_DESC, section = EVENTS },
    { key = "pvpRank", name = L.AUTOSCREENSHOT_PVP_RANK, description = L.AUTOSCREENSHOT_PVP_RANK_DESC,
        section = EVENTS },
    { key = "title", name = L.AUTOSCREENSHOT_NEW_TITLE, description = L.AUTOSCREENSHOT_NEW_TITLE_DESC,
        section = EVENTS },
    { key = "battleground", name = L.AUTOSCREENSHOT_BATTLEGROUND,
        description = L.AUTOSCREENSHOT_BATTLEGROUND_DESC, section = EVENTS },
    { key = "death", name = L.AUTOSCREENSHOT_DEATH, description = L.AUTOSCREENSHOT_DEATH_DESC,
        section = EVENTS },
}

local DELAY = 1 -- seconds after the event, so its toast is on screen
local HIDE_WAIT = 0.1 -- seconds between hiding the interface and the shot, so it's drawn without
local UI_BACK = 3 -- seconds before the interface comes back if the game never reports the shot
-- Forever's PvP rank is the renown level of this faction (Blizzard's Camelot PVPRankFrame.lua).
local PVP_RANK_FACTION = 2800

-- Taking a picture ----------------------------------------------------------------------------

local timer = ns.Frames.Timer(module) -- the pending shot
local reason -- what the last shot was for, for chat; nil for the player's own
local hidden = false -- the interface is hidden for a shot and must come back
local busy = false -- a shot is on its way, until the game says it's taken or failed
-- Ends the shot if the game never reports it, so the next one isn't blocked. Its own timer, so a
-- later shot isn't shown the interface by this one's.
local fallback = ns.Frames.Timer(module)
local showUI, onShot

-- The shot is over (taken, failed, or never reported): the next one may start.
local function finish()
    module:Off("SCREENSHOT_SUCCEEDED", onShot)
    module:Off("SCREENSHOT_FAILED", onShot)
    fallback:Cancel()
    busy = false
    showUI()
end

function onShot(event)
    finish()
    -- Said now rather than when asked, so the chat line isn't in the picture.
    if event == "SCREENSHOT_SUCCEEDED" and reason then
        module:Print(format(L.AUTOSCREENSHOT_TAKEN, reason))
    end
end

-- Brings the interface back. Showing it can be blocked in combat, so it waits for combat to end
-- then; combat starting is also a cue, since that's the last moment it can.
function showUI()
    if not hidden then
        return
    end
    if InCombatLockdown() then
        ns.AfterCombat(showUI)
        return
    end
    hidden = false
    module:Off("PLAYER_REGEN_DISABLED", showUI)
    UIParent:SetAlpha(1)
end

-- Takes a shot now, for `why` (nil for one the player took themselves). One already on its way
-- (the interface hidden, the shot a moment off) covers it, so the two don't undo each other.
local function take(why)
    if busy then
        return
    end
    busy = true
    reason = why
    module:On("SCREENSHOT_SUCCEEDED", onShot)
    module:On("SCREENSHOT_FAILED", onShot)
    fallback:Start(UI_BACK, finish)
    -- Hiding the interface in combat can be blocked, and so can showing it again, so only out of
    -- combat. If the player hid it themselves (Alt-Z), it's already out of the way.
    if module.db.hideUI and not InCombatLockdown() and UIParent:IsShown() then
        hidden = true
        module:On("PLAYER_REGEN_DISABLED", showUI)
        -- Faded, not hidden: Hide and Show would run every shown window's OnHide and OnShow from
        -- our code. The shot looks the same.
        UIParent:SetAlpha(0)
        -- Not once the module has been turned off meanwhile (its OnDisable shows the UI again).
        C_Timer.After(HIDE_WAIT, function()
            if module.enabled then
                Screenshot()
            end
        end)
    else
        Screenshot()
    end
end

-- Asks for a shot a moment from now. Things that happen together (a level up that also earns an
-- achievement) share one shot, named for the first.
local function request(why)
    if timer:IsPending() or not module.enabled then
        return
    end
    timer:Start(DELAY, function()
        take(why)
    end)
end

-- The player's own shots ----------------------------------------------------------------------
-- The Screenshot key takes its shot straight away, before anything could hide the interface. So
-- while Hide Interface and Your Own Screenshots are on, that key is bound to our button instead,
-- which takes the shot the same way as ours. Bindings can't change in combat, so the keys stay as
-- they were when combat started; in combat the button just takes the shot with the interface.

-- A click binding needs a button with a global name.
local BUTTON_NAME = "ForeverPlusPlusScreenshotButton"
local button -- made the first time it's needed (a frame can't be removed)
local boundKeys = "" -- the keys bound to the button now, to notice when the player changes them
local bindPending = false

local function bindKeys()
    if InCombatLockdown() then
        if not bindPending then
            bindPending = true
            ns.AfterCombat(function()
                bindPending = false
                bindKeys()
            end)
        end
        return
    end
    local keys = {}
    if module.enabled and module.db.hideUI and module.db.hideOwn then
        keys = { GetBindingKey("SCREENSHOT") }
    end
    local list = concat(keys, " ")
    -- Binding keys fires UPDATE_BINDINGS, which calls this again; only rebind on a real change.
    if list == boundKeys then
        return
    end
    boundKeys = list
    if button then
        ClearOverrideBindings(button)
    end
    if #keys == 0 then
        return
    end
    if not button then
        button = CreateFrame("Button", BUTTON_NAME)
        button:SetScript("OnClick", function()
            take(nil)
        end)
    end
    for _, key in ipairs(keys) do
        SetOverrideBindingClick(button, false, key, BUTTON_NAME)
    end
end

-- Reading chat lines --------------------------------------------------------------------------

-- A Lua pattern for one of the client's chat formats, such as LOOT_ITEM_SELF ("You receive loot:
-- %s."), capturing each %s and %d. Nil if the client doesn't have that format.
local function toPattern(text)
    if type(text) ~= "string" then
        return nil
    end
    return "^" .. ns.Text.FormatPattern(text, true) .. "$"
end

local lootPatterns -- built the first time, from the client's own (translated) formats
local function getLootPatterns()
    if not lootPatterns then
        lootPatterns = {}
        for _, text in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF,
            LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
            lootPatterns[#lootPatterns + 1] = toPattern(text)
        end
    end
    return lootPatterns
end

local standingPattern -- "You are now %s with %s."
local lowStandings -- Hated to Unfriendly, male and female: reaching these is a step down
local function getStanding()
    if standingPattern == nil then
        standingPattern = toPattern(FACTION_STANDING_CHANGED) or false
        lowStandings = {}
        for i = 1, 3 do
            for _, text in ipairs({ _G["FACTION_STANDING_LABEL" .. i],
                _G["FACTION_STANDING_LABEL" .. i .. "_FEMALE"] }) do
                lowStandings[text] = true
            end
        end
    end
    return standingPattern
end

-- Events --------------------------------------------------------------------------------------

local function onLoot(_, text)
    if not readable(text) or type(text) ~= "string" then
        return
    end
    for _, pattern in ipairs(getLootPatterns()) do
        local link = text:match(pattern)
        if link then
            local item = link:match("|H(item:[^|]+)|h")
            local quality = item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(item)
            if readable(quality) and quality and quality >= (tonumber(module.db.lootQuality) or 4) then
                request(L.AUTOSCREENSHOT_LOOT)
            end
            return
        end
    end
end

local function onStanding(_, text)
    local pattern = getStanding()
    if not (pattern and ns.IsText(text)) then
        return
    end
    local standing = text:match(pattern)
    if standing and not lowStandings[standing] then
        request(L.AUTOSCREENSHOT_REPUTATION)
    end
end

local TITLES_SETTLE = 10 -- seconds after login (or turning on) while the title list may still fill in
local knownTitles = 0
local countedAt = 0 -- when knownTitles was first counted

local function countTitles()
    local count = 0
    if GetNumTitles and IsTitleKnown then
        for i = 1, GetNumTitles() do
            if IsTitleKnown(i) then
                count = count + 1
            end
        end
    end
    return count
end

local function onTitles(_, unit)
    if unit ~= nil and not (readable(unit) and unit == "player") then
        return
    end
    local count = countTitles()
    -- Right after login the list can arrive late, which looks like new titles.
    if count > knownTitles and GetTime() - countedAt > TITLES_SETTLE then
        request(L.AUTOSCREENSHOT_NEW_TITLE)
    end
    knownTitles = count
end

-- Each checkbox's events, listened to only while it's on. Handlers get the event's name, then its
-- payload.
module:OnWhile("levelUp", { PLAYER_LEVEL_UP = function()
    request(L.AUTOSCREENSHOT_LEVEL_UP)
end })
module:OnWhile("achievement", { ACHIEVEMENT_EARNED = function(_, _, alreadyEarned)
    -- Already earned means on another character; this one only caught up.
    if not (readable(alreadyEarned) and alreadyEarned) then
        request(L.AUTOSCREENSHOT_ACHIEVEMENT)
    end
end })
module:OnWhile("loot", { CHAT_MSG_LOOT = onLoot })
module:OnWhile("bossKill", { ENCOUNTER_END = function(_, _, _, _, _, success)
    if readable(success) and success == 1 then
        request(L.AUTOSCREENSHOT_BOSS_KILL)
    end
end })
-- Which chat event carries "You are now Friendly with ..." isn't certain on this client, so both;
-- the line only comes once.
module:OnWhile("reputation", {
    CHAT_MSG_SYSTEM = onStanding,
    CHAT_MSG_COMBAT_FACTION_CHANGE = onStanding,
})
module:OnWhile("pvpRank", { MAJOR_FACTION_RENOWN_LEVEL_CHANGED = function(_, factionID, new, old)
    if readable(factionID) and readable(new) and readable(old)
        and factionID == PVP_RANK_FACTION and new > old then
        request(L.AUTOSCREENSHOT_PVP_RANK)
    end
end })
module:OnWhile("title", { KNOWN_TITLES_UPDATE = onTitles })
module:OnWhile("battleground", { PVP_MATCH_COMPLETE = function()
    request(L.AUTOSCREENSHOT_BATTLEGROUND)
end })
module:OnWhile("death", { PLAYER_DEAD = function()
    request(L.AUTOSCREENSHOT_DEATH)
end })
-- It's for the level up's screenshot, so only with Level Up on. Blizzard's chat prints the answer
-- (TIME_PLAYED_MSG), well before the shot is taken.
module:OnWhile(function(db)
    return db.playedTime and db.levelUp
end, { PLAYER_LEVEL_UP = function()
    if RequestTimePlayed then
        RequestTimePlayed()
    end
end })

-- Counts the titles already known when New Title turns on, so only later ones get a shot.
local function syncTitles()
    if module.db.title then
        if countedAt == 0 then
            knownTitles = countTitles()
            countedAt = GetTime()
        end
    else
        countedAt = 0
    end
end

function module:OnEnable()
    syncTitles()
    bindKeys()
    self:On("UPDATE_BINDINGS", bindKeys)
end

function module:OnDisable()
    timer:Cancel()
    finish()
    countedAt = 0
    bindKeys()
end

function module:OnOptionChanged()
    syncTitles()
    bindKeys()
end
