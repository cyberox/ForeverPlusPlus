-- Movable Combat Log Tab: lets the Combat Log's tab be dragged anywhere among the chat tabs, past
-- the tabs the player made, instead of staying second, right after General.
--
-- Blizzard draws two kinds of docked tab (FCFDock_UpdateTabs): fixed ones, General and the Combat
-- Log, which XML marks `isStaticDocked`, and then every other window's in a strip after the last
-- fixed one. So whatever order the dock's list holds, the log is drawn second. Clearing that mark
-- makes the log's tab one of the strip's, drawn in the list's order, which Blizzard already saves
-- and restores when a tab is dropped (FCF_SaveDock). It also scrolls and shrinks like the others.
--
-- This is the one field we write on a Blizzard frame: there's no other way in, and the chat window
-- isn't secure. Tested in game in and out of combat (2026-11-17). Only XML's OnLoad sets the mark,
-- so it stays cleared until the module turns off, which puts it back.
local _, ns = ...

local _G = _G

local L = ns.L

local module = ns.NewModule("MovableCombatLogTab", L.MOVABLECOMBATLOGTAB_DESC, {
    enabled = false,
})
module.title = L.MOVABLECOMBATLOGTAB_TITLE
module.category = "chat"
module.added = "1.9.0"

local function apply()
    local frame = _G.ChatFrame2
    if not frame then
        return
    end
    local fixed = not module.enabled
    if (frame.isStaticDocked and true or false) == fixed then
        return
    end
    frame.isStaticDocked = fixed or nil
    _G.FCF_DockUpdate()
end

function module:IsAvailable()
    return _G.ChatFrame2 ~= nil and _G.FCF_DockUpdate ~= nil
end

function module:OnEnable()
    ns.AfterCombat(apply)
end

function module:OnDisable()
    ns.AfterCombat(apply)
end
