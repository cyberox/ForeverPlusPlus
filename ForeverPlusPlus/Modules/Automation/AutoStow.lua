-- Auto Stow: puts your weapons away once they've been out for the Delay out of combat, whether
-- combat left them out or you drew them yourself. Pressing Sheath starts the Delay again.
--
-- No event says the sheath changed, so it looks twice a second out of combat (not at all in
-- combat). With a ranged weapon the Sheath key cycles away, melee, ranged, so from melee one
-- toggle draws the ranged weapon: it toggles, waits for the state to change, and toggles again
-- until everything is away, three toggles at most. A toggle that changes nothing within a couple
-- of seconds is tried once more, then it stops until the state changes some other way. The game also sheathes by itself
-- a few seconds after combat, often before the Delay is up (Cameron's log, 2026-10-22).
local _, ns = ...

-- The original ToggleSheath, from before the hook below, so our own stow doesn't look like the
-- player pressing the key.
local GetSheathState, ToggleSheath = GetSheathState, ToggleSheath
local UnitAffectingCombat, UnitIsDeadOrGhost = UnitAffectingCombat, UnitIsDeadOrGhost
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local IsInInstance, InCombatLockdown, GetTime = IsInInstance, InCombatLockdown, GetTime
local format, tostring = string.format, tostring

local L = ns.L

local module = ns.NewModule("AutoStow", L.AUTOSTOW_DESC, {
    enabled = true,
    delay = 5, -- seconds
    outsideOnly = false, -- leave weapons out in dungeons and raids
    logSheath = false,
})
module.title = L.AUTOSTOW_TITLE
module.category = "automation"
module.quickToggle = "loot"

module.options = {
    {
        key = "delay",
        name = L.AUTOSTOW_DELAY,
        description = L.AUTOSTOW_DELAY_DESC,
        min = 3, max = 30, step = 1, format = ns.Text.Seconds,
    },
    {
        key = "outsideOnly",
        name = L.AUTOSTOW_OUTSIDE_ONLY,
        description = L.AUTOSTOW_OUTSIDE_ONLY_DESC,
    },
    {
        key = "logSheath",
        name = L.AUTOSTOW_LOG,
        description = L.AUTOSTOW_LOG_DESC,
        debug = true,
        section = L.DEBUG_SECTION_LOGGING,
        added = "1.0.0-beta.1",
    },
}

-- GetSheathState: 1 is nothing drawn, 2 melee drawn, 3 ranged drawn.
local SHEATHED = 1
local LOOK = 0.5 -- seconds between looks out of combat
local RETRY = 1 -- seconds to wait while casting before trying again
-- A press shows in the state 0.1 to 0.7 seconds later (Cameron's log, 2026-10-22).
local POLL = 0.25 -- seconds between looks after a toggle
local WAIT = 2 -- seconds to wait for a toggle to change the state
-- A toggle right after the state changes is ignored: one the moment the ranged weapon came out
-- changed nothing, and Cameron's own press 0.5 seconds after a change did nothing while one 1.1
-- seconds after worked (his logs, 2026-10-22). So the next toggle waits this long.
local SETTLE = 1.25 -- seconds after a change before toggling again
local AGAIN = 1.5 -- seconds before trying once more after a toggle that changed nothing
local TOGGLES = 3 -- at most per stow

local timer = ns.Frames.Timer(module) -- the stow under way: a cast to wait out, or a toggle's wait
local watcher -- looks at the state out of combat; made on first enable
local drawnSince -- GetTime() the weapons came out, or nil while away (or not counting)
local stuck -- a state our toggles couldn't change: left alone until it changes
local stowing = false
local toggles, before, waitUntil -- this stow's toggles, the state before the last, when to give up
local retried = false -- the last toggle changed nothing and is being tried once more
local lastLogged -- the last state Log Sheath State printed

local function log(text)
    if module.db.logSheath then
        ns.Print(format(L.AUTOSTOW_LOG_LINE, GetTime(), text))
    end
end

local function blocked()
    return UnitAffectingCombat("player") or UnitIsDeadOrGhost("player")
end

-- A dungeon, raid, battleground or arena.
local function inInstance()
    local inside, kind = IsInInstance()
    return inside and kind ~= "none"
end

-- Ends the stow under way. `state` is left alone until it changes (a toggle didn't move it).
local function stopStow(state)
    timer:Cancel()
    stowing = false
    drawnSince = nil
    stuck = state
end

-- Stowing -------------------------------------------------------------------------------------

local step

-- After a toggle: once the state moves off what it was, let it settle and toggle again until it's
-- away. Nothing changed within WAIT: try once more a little later, then stop.
local function afterToggle()
    local state = GetSheathState()
    if state == before and GetTime() < waitUntil then
        timer:Start(POLL, afterToggle)
        return
    end
    if state == before then
        if retried then
            log(format(L.AUTOSTOW_LOG_NO_CHANGE, tostring(state)))
            stopStow(state)
        else
            log(format(L.AUTOSTOW_LOG_AGAIN, tostring(state)))
            retried = true
            timer:Start(AGAIN, step)
        end
        return
    end
    log(format(L.AUTOSTOW_LOG_TOGGLED, tostring(state)))
    retried = false
    timer:Start(SETTLE, step)
end

function step()
    local state = GetSheathState()
    if blocked() or state == SHEATHED then
        stopStow(nil)
        return
    end
    if toggles >= TOGGLES then
        log(format(L.AUTOSTOW_LOG_GAVE_UP, TOGGLES, tostring(state)))
        stopStow(state)
        return
    end
    -- Sheathing mid-cast can interrupt it; wait for the cast to finish. The player's own cast,
    -- out of combat, isn't secret.
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        timer:Start(RETRY, step)
        return
    end
    toggles, before, waitUntil = toggles + 1, state, GetTime() + WAIT
    log(format(L.AUTOSTOW_LOG_TOGGLE, tostring(state)))
    ToggleSheath()
    timer:Start(POLL, afterToggle)
end

local function stow()
    stowing, toggles, retried = true, 0, false
    step()
end

-- Watching ------------------------------------------------------------------------------------

local function look()
    local state = GetSheathState()
    if state ~= lastLogged then
        log(format(L.AUTOSTOW_LOG_STATE, tostring(state)))
        lastLogged = state
    end
    if stuck and state ~= stuck then
        stuck = nil
    end
    if state == SHEATHED or stuck or UnitIsDeadOrGhost("player") then
        drawnSince = nil
        return
    end
    if stowing then
        return
    end
    local now = GetTime()
    if not drawnSince then
        drawnSince = now
    elseif now - drawnSince >= module.db.delay
        and not (module.db.outsideOnly and inInstance()) then
        stow()
    end
end

local function startWatching()
    drawnSince, stuck, lastLogged = nil, nil, nil
    if not watcher then
        watcher = ns.Frames.Watcher(module, LOOK, look)
    end
    watcher:Show()
end

local function stopWatching()
    if watcher then
        watcher:Hide()
    end
    if stowing then
        stopStow(nil)
    end
    drawnSince = nil
end

local function onCombatEnd()
    log(format(L.AUTOSTOW_LOG_COMBAT_END, tostring(GetSheathState())))
    startWatching()
end

local function onCombatStart()
    log(L.AUTOSTOW_LOG_COMBAT_START)
    stopWatching()
end

-- Pressing Sheath (or Unsheath) yourself starts the Delay again and ends a stow under way.
local function onPlayerToggle()
    log(format(L.AUTOSTOW_LOG_PLAYER, tostring(GetSheathState())))
    if stowing then
        stopStow(nil)
    end
    drawnSince, stuck = nil, nil
end

function module:OnEnable()
    self:On("PLAYER_REGEN_ENABLED", onCombatEnd)
    self:On("PLAYER_REGEN_DISABLED", onCombatStart)
    self:Hook("ToggleSheath", onPlayerToggle)
    if not InCombatLockdown() then
        startWatching()
    end
end

function module:OnDisable()
    stopWatching()
end
