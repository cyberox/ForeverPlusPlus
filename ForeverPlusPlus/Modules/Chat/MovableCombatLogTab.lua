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

local _G, ipairs = _G, ipairs

local L = ns.L

local module = ns.NewModule("MovableCombatLogTab", L.MOVABLECOMBATLOGTAB_DESC, {
    enabled = false,
})
module.title = L.MOVABLECOMBATLOGTAB_TITLE
module.category = "chat"
module.added = "1.9.0"
module.notice = ns.Gamepad.LimitedNotice() -- dragging a tab needs a mouse

-- The tab of the last fixed window in the dock, which the strip of the other tabs starts after.
local function lastFixedTab(dock)
    local tab
    for _, docked in ipairs(_G.FCFDock_GetChatFrames(dock)) do
        if docked.isStaticDocked then
            tab = _G[docked:GetName() .. "Tab"] or tab
        end
    end
    return tab
end

local function apply()
    local frame, dock = _G.ChatFrame2, _G.GENERAL_CHAT_DOCK
    if not (frame and dock) then
        return
    end
    local fixed = not module.enabled
    if (frame.isStaticDocked and true or false) == fixed then
        return
    end
    frame.isStaticDocked = fixed or nil
    -- Redrawing as it is would loop the anchors: the strip of tabs sits at the log tab's right
    -- edge, and the log's tab would go into that strip, so the redraw stops halfway and both
    -- vanish. So the strip is moved to the last fixed tab's edge first, as the redraw then does
    -- itself.
    --
    -- Not by taking the log out of the dock and putting it back (FCF_UnDockFrame, FCF_DockFrame),
    -- which does the same: that writes the dock's list of windows in our name. With the controller
    -- interface on the dock makes its LB and RB bindings again from that list, and from then on
    -- the controller's own code is refused: the game menu, bags, and
    -- SetPreferredGamepadInteractTarget, until a /reload (Error Catcher's controller state, seen
    -- in game, build 70959, 2026-11-19: ChatFrame2.dock and GENERAL_CHAT_DOCK.footer.bindings ours
    -- a second after login).
    local strip = dock.scrollFrame
    if not fixed and strip then
        local tab = lastFixedTab(dock)
        if tab then
            strip:SetPoint("LEFT", tab, "RIGHT")
        else
            strip:SetPoint("LEFT")
        end
    end
    _G.FCF_DockUpdate()
end

function module:IsAvailable()
    return _G.ChatFrame2 ~= nil and _G.GENERAL_CHAT_DOCK ~= nil and _G.FCF_DockUpdate ~= nil
end

function module:OnEnable()
    ns.AfterCombat(apply)
end

function module:OnDisable()
    ns.AfterCombat(apply)
end
