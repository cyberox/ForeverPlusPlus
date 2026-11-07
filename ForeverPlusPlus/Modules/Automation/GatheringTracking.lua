-- Gathering Tracking: keeps Find Minerals and Find Herbs on. After login, zoning, and coming back
-- to life it turns one back on when nothing is being tracked, and it can swap between the two
-- every few seconds so both kinds of node show on the minimap. Only one tracking spell is on at a
-- time, so swapping is the only way to see both. Never in combat, on a flight, or while casting:
-- tracking is a spell, and casting it would stop a cast or a channel such as mining or fishing.
local _, ns = ...

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall
local format = string.format
local C_Minimap, C_Timer = C_Minimap, C_Timer
local GetTime, InCombatLockdown, UnitIsDeadOrGhost, UnitOnTaxi = GetTime, InCombatLockdown, UnitIsDeadOrGhost, UnitOnTaxi
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo

local L = ns.L

local HERBS = ns.GameData.Spell(2383, "Find Herbs")
local MINERALS = ns.GameData.Spell(2580, "Find Minerals")

-- Which spells each `track` choice uses, the one to turn back on first before the other.
local SPELLS = {
    both = { MINERALS, HERBS },
    minerals = { MINERALS },
    herbs = { HERBS },
}

local RETRY = 2 -- seconds between checks

-- The fewest seconds between swaps: each swap is a cast on the global cooldown, and a faster one
-- would keep taking it.
local FASTEST = 3

local module = ns.NewModule("GatheringTracking", L.GATHERINGTRACKING_DESC, {
    enabled = true,
    track = "both", -- a key of SPELLS
    reapply = true,
    swap = false,
    swapEvery = 10, -- seconds between swaps
    chat = true,
})
module.title = L.GATHERINGTRACKING_TITLE
module.category = "automation"
module.quickToggle = "gathering"

-- Swap was one slider, 0.8.4 and before, whose first stop (2) meant never.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local db = saved.GatherTracking
    if not (db and type(db.swap) == "number") then
        return
    end
    if db.swap >= FASTEST then
        db.swapEvery = db.swap
    end
    db.swap = db.swap >= FASTEST
end)

module.options = {
    {
        key = "track",
        name = L.GATHERINGTRACKING_TRACK,
        description = L.GATHERINGTRACKING_TRACK_DESC,
        choices = {
            { "both", L.GATHERINGTRACKING_TRACK_BOTH },
            { "minerals", L.GATHERINGTRACKING_TRACK_MINERALS },
            { "herbs", L.GATHERINGTRACKING_TRACK_HERBS },
        },
    },
    {
        key = "swap",
        name = L.GATHERINGTRACKING_SWAP,
        description = L.GATHERINGTRACKING_SWAP_DESC,
        slider = "swapEvery",
        changed = "0.9.0", -- a checkbox and its slider
        -- Swapping is between the two, so only with both chosen.
        shown = function(db)
            return db.track == "both"
        end,
    },
    {
        key = "swapEvery",
        name = L.GATHERINGTRACKING_SWAP_EVERY_NAME,
        description = L.GATHERINGTRACKING_SWAP_EVERY_DESC,
        requires = "swap",
        min = FASTEST, max = 30, step = 1,
        format = ns.Text.Seconds,
    },
    {
        key = "reapply",
        name = L.GATHERINGTRACKING_REAPPLY,
        description = L.GATHERINGTRACKING_REAPPLY_DESC,
    },
    ns.ChatOption(L.GATHERINGTRACKING_CHAT_DESC),
}

-- Reads the tracking list: the index of each of our spells the player knows, which of them is on,
-- and whether any tracking spell is on (a hunter's Track Beasts counts). Read every time, since it
-- changes as spells are learned. GetTrackingInfo has no secret values.
local function scan()
    local index, ours, any = {}, nil, false
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" then
            local spellID = info.spellID
            if spellID == HERBS or spellID == MINERALS then
                index[spellID] = i
            end
            if info.active and (info.type == "spell" or (spellID and spellID > 0)) then
                any = true
                if spellID == HERBS or spellID == MINERALS then
                    ours = spellID
                end
            end
        end
    end
    return index, ours, any
end

-- Unit state can be secret; when it is, wait (ns.IsTrueOrSecret).
local yes = ns.IsTrueOrSecret

-- Whether casting a tracking spell now would fail or get in the way.
local function busy()
    return InCombatLockdown() or yes(UnitIsDeadOrGhost("player")) or yes(UnitOnTaxi("player"))
        or yes(UnitCastingInfo("player")) or yes(UnitChannelInfo("player"))
end

local blocked = false -- the client refused SetTracking from an addon; stop until /reload
local last -- the last of our spells seen on, turned back on first

local function track(i)
    local ok, err = pcall(C_Minimap.SetTracking, i, true)
    if not ok and not blocked then
        blocked = true
        module:Print(format(L.GATHERINGTRACKING_FAILED, tostring(err)))
    end
end

-- Turning tracking back on --------------------------------------------------------------------

local want = false -- turn tracking back on at the next chance
local timer = ns.Frames.Timer(module) -- the next check, stopped by Core when the module turns off
local deadline = 0 -- GetTime() until which to keep checking

-- How long to keep checking once the player can cast. At a fresh login the list fills in seconds
-- after the event, and after coming back to life it can still show the tracking lost at death as on
-- for a moment, or a cast right then can fail, so one look isn't enough.
local WATCH = 12

-- The Track choice just changed: turn the chosen spell on in place of ours that isn't chosen any
-- more, even with Reapply off, since the player just picked it.
local switch = false

local function chosen(spells, spellID)
    for _, id in ipairs(spells) do
        if id == spellID then
            return true
        end
    end
    return false
end

local function reapply()
    if not (want and (module.db.reapply or switch)) or blocked then
        want, switch = false, false
        return
    end
    if busy() then
        deadline = GetTime() + WATCH -- the time to watch starts once the player can cast
        timer:Start(RETRY, reapply)
        return
    end
    local index, ours, any = scan()
    local spells = SPELLS[module.db.track]
    if (not any and module.db.reapply) or (switch and ours and not chosen(spells, ours)) then
        local first
        for _, spellID in ipairs(spells) do
            if index[spellID] then
                if spellID == last then
                    first = spellID
                    break
                end
                first = first or spellID
            end
        end
        if first then
            track(index[first])
        end
    end
    switch = false
    -- Look again until the time is up, whether something was on or we just turned it on.
    if module.db.reapply and GetTime() < deadline then
        timer:Start(RETRY, reapply)
    else
        want = false
    end
end

-- Login, /reload, zoning, and coming back to life. The tracking list can lag the event a little.
local function request()
    want = true
    deadline = GetTime() + WATCH
    if not timer:IsPending() then
        timer:Start(1, reapply)
    end
end

-- Swapping ------------------------------------------------------------------------------------

local ticker

local function swap()
    if blocked or busy() then
        return
    end
    local index, ours = scan()
    -- Swap only while one of ours is on: off, or another tracker, is the player's choice.
    local other = (ours == MINERALS and HERBS) or (ours == HERBS and MINERALS)
    if other and module.db.track == "both" and index[other] then
        track(index[other])
    end
end

local function stopSwapping()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function startSwapping()
    stopSwapping()
    if module.db.swap and not blocked then
        ticker = C_Timer.NewTicker(module.db.swapEvery, swap)
    end
end

-- Events --------------------------------------------------------------------------------------

local function onTrackingChanged()
    local _, ours = scan()
    last = ours or last
end

-- SetTracking may be protected on a later build; it then fails this way instead of erroring.
local function onBlocked(_, addon, action)
    if addon == ns.name and type(action) == "string" and action:find("SetTracking", 1, true)
        and not blocked then
        blocked = true
        stopSwapping()
        module:Print(L.GATHERINGTRACKING_BLOCKED)
    end
end

local REAPPLY_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }

function module:OnEnable()
    for _, event in ipairs(REAPPLY_EVENTS) do
        self:On(event, request)
    end
    self:On("MINIMAP_UPDATE_TRACKING", onTrackingChanged)
    self:On("ADDON_ACTION_BLOCKED", onBlocked)
    self:On("ADDON_ACTION_FORBIDDEN", onBlocked)
    onTrackingChanged()
    startSwapping()
    request()
end

function module:OnDisable()
    stopSwapping()
end

function module:OnOptionChanged(key)
    if not self.enabled then
        return
    end
    if key == "swap" or key == "swapEvery" then
        startSwapping()
    elseif key == "reapply" and self.db.reapply then
        request()
    elseif key == "track" then
        switch = true
        request()
    end
end
