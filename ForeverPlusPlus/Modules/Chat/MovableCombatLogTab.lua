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

-- Where the log sits in the dock, and whether it's the window shown.
local function place(dock, frame)
    for index, docked in ipairs(_G.FCFDock_GetChatFrames(dock)) do
        if docked == frame then
            return index, _G.FCFDock_GetSelectedWindow(dock) == frame
        end
    end
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
    local index, selected = place(dock, frame)
    if fixed or not index then
        _G.FCF_DockUpdate()
        return
    end
    -- Redrawing as it is would loop the anchors: the strip of tabs sits at the log tab's right
    -- edge, and the log's tab would go into that strip, so the redraw stops halfway and both
    -- vanish. Out of the dock first, the strip moves to General's edge, then back in its place.
    _G.FCF_UnDockFrame(frame)
    _G.FCF_DockFrame(frame, index, selected)
end

function module:IsAvailable()
    return _G.ChatFrame2 ~= nil and _G.GENERAL_CHAT_DOCK ~= nil and _G.FCF_DockFrame ~= nil
end

function module:OnEnable()
    ns.AfterCombat(apply)
end

function module:OnDisable()
    ns.AfterCombat(apply)
end
