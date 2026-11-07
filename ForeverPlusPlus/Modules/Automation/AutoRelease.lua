-- Auto Release: releases your spirit when you die in a battleground, so you're at the spirit
-- healer for the next wave. Not when you can come back where you fell: a soulstone, reincarnation,
-- or someone resurrecting you. Arenas are left alone, since the game doesn't release there.
local _, ns = ...

local select = select
local IsInInstance, UnitIsDead, UnitIsGhost = IsInInstance, UnitIsDead, UnitIsGhost
local UnitHasIncomingResurrection, HasNoReleaseAura = UnitHasIncomingResurrection, HasNoReleaseAura
local RepopMe, C_DeathInfo = RepopMe, C_DeathInfo

local L = ns.L

local module = ns.NewModule("AutoRelease", L.AUTORELEASE_DESC, {
    enabled = false,
    delay = 0, -- seconds
    skipKey = "none",
    chat = true,
})
module.title = L.AUTORELEASE_TITLE
module.category = "automation"
module.quickToggle = "world"

module.options = {
    {
        key = "delay",
        name = L.AUTORELEASE_DELAY,
        description = L.AUTORELEASE_DELAY_DESC,
        min = 0, max = 10, step = 1,
        format = function(seconds)
            if seconds == 0 then
                return L.AUTORELEASE_NOW
            end
            return ns.Text.Seconds(seconds)
        end,
    },
    ns.Keys.Option("skipKey", L.SKIP_KEY, L.AUTORELEASE_KEY_DESC),
    ns.ChatOption(L.AUTORELEASE_CHAT_DESC),
}
module.options[2].added = "0.9.0" -- the Skip Key

-- Self-resurrect options (soulstone, reincarnation) arrive a moment after PLAYER_DEAD, so even
-- "right away" waits this long before looking.
local MIN_WAIT = 0.5 -- seconds

local timer = ns.Frames.Timer(module) -- the pending release
local offered = false -- someone offered a resurrection since this death

local function cancel()
    timer:Cancel()
end

local function inBattleground()
    return select(2, IsInInstance()) == "pvp"
end

local function canSelfResurrect()
    if not (C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions) then
        return false
    end
    local options = C_DeathInfo.GetSelfResurrectOptions()
    return options ~= nil and #options > 0
end

-- A resurrection on its way: one being cast on the corpse, or one offered and not yet answered.
-- The cast check may be secret, which counts as not.
local function resurrectionComing()
    if offered then
        return true
    end
    if not UnitHasIncomingResurrection then
        return false
    end
    local incoming = UnitHasIncomingResurrection("player")
    return ns.IsReadable(incoming) and incoming == true
end

local function release()
    if not (UnitIsDead("player") and not UnitIsGhost("player") and inBattleground()) then
        return
    end
    -- Some fights hold you where you fell; the game greys out Release there too.
    if HasNoReleaseAura and HasNoReleaseAura() then
        return
    end
    -- The player chose to stay where they fell; Blizzard's Release button is still there.
    if ns.Keys.IsDown(module.db.skipKey) then
        return
    end
    if canSelfResurrect() then
        module:Print(L.AUTORELEASE_SELF_RES)
        return
    end
    if resurrectionComing() then
        module:Print(L.AUTORELEASE_RES_OFFER)
        return
    end
    RepopMe()
    module:Print(L.AUTORELEASE_RELEASED)
end

local function onDead()
    cancel()
    offered = false
    if not inBattleground() then
        return
    end
    local delay = module.db.delay
    timer:Start(delay > MIN_WAIT and delay or MIN_WAIT, release)
end

local function onResurrectRequest()
    offered = true
end

local function onAlive()
    cancel()
    offered = false
end

function module:OnEnable()
    self:On("PLAYER_DEAD", onDead)
    self:On("RESURRECT_REQUEST", onResurrectRequest)
    self:On("PLAYER_ALIVE", onAlive)
    self:On("PLAYER_UNGHOST", onAlive)
end

