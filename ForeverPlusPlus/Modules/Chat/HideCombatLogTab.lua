-- Hide Combat Log Tab: takes the Combat Log's tab off the chat window's row of tabs, so the tabs
-- after it move up beside General. The log itself is untouched and its tab comes back when the
-- module turns off.
--
-- Blizzard shows the tab and fades its alpha whenever the mouse nears the chat window
-- (FCFDock_UpdateTabs, FCF_FadeInChatFrame), so neither hiding it nor an alpha of 0 lasts. Its
-- scale is never set by Blizzard: at almost nothing the tab takes no room and can't be seen, and
-- the next tab, anchored to its right edge, sits where it was. Leatrix Plus hides it the same way
-- on other clients; none of its code. Only while the log is docked: a log window of its own needs
-- its tab to be moved or docked again.
local _, ns = ...

local _G = _G

local L = ns.L

local module = ns.NewModule("HideCombatLogTab", L.HIDECOMBATLOGTAB_DESC, {
    enabled = false,
})
module.title = L.HIDECOMBATLOGTAB_TITLE
module.category = "chat"
module.added = "1.7.0"

local TINY = 0.01 -- a scale can't be 0

local original -- the tab's own scale while ours is on it

local function apply()
    local frame, tab = _G.ChatFrame2, _G.ChatFrame2Tab
    if not (frame and tab) then
        return
    end
    local hide = module.enabled and frame.isDocked and true or false
    if hide == (original ~= nil) then
        return
    end
    if hide then
        original = tab:GetScale()
        tab:SetScale(TINY)
    else
        tab:SetScale(original)
        original = nil
    end
    tab:EnableMouse(not hide)
end

function module:IsAvailable()
    return _G.ChatFrame2 ~= nil and _G.ChatFrame2Tab ~= nil
end

function module:OnEnable()
    -- Also after a window is docked or pulled out of the dock, and when the windows are reset.
    ns.Chat.EachWindow(self, apply)
    self:Hook("FCF_DockFrame", apply)
    self:Hook("FCF_UnDockFrame", apply)
end

function module:OnDisable()
    apply()
end
