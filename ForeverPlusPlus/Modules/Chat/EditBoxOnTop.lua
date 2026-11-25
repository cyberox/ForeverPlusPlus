-- Edit Box on Top: the box chat is typed in sits above its chat window's tabs instead of under
-- the window.
--
-- Each window's edit box (`frame.editBox`) is anchored once, in FloatingChatFrame.xml, under its
-- window: nothing of Blizzard's moves it afterwards, so its place is ours to change and to give
-- back. It goes above the window's background, which the tabs stand on (FCF_SetTabPosition) and
-- which already reaches over the Combat Log's bar of filter buttons, as wide as it was: the
-- background's width and one more to the right. The anchors it had are kept to put back, so one
-- another addon had moved returns to where that addon left it.
-- (wow-ui-source's `forever` branch, read 2026-11-24.)
local _, ns = ...

local _G, ipairs, setmetatable = _G, ipairs, setmetatable

local L = ns.L
local Chat = ns.Chat
local Frames = ns.Frames

local module = ns.NewModule("EditBoxOnTop", L.EDITBOXONTOP_DESC, {
    enabled = false,
})
module.title = L.EDITBOXONTOP_TITLE
module.category = "chat"
module.added = "1.9.0"

-- How far above the background's top the box's bottom goes: past the tabs, which are 32 high but
-- drawn in the lower 24 or so, less the few empty pixels at the bottom of the box's own art.
local ABOVE = 22

-- The anchors each edit box had before we moved it, to give back.
local original = setmetatable({}, { __mode = "k" })

---Moves a window's edit box above its tabs.
---@param frame table a chat window
local function apply(frame)
    local box, background = frame.editBox, frame.Background
    if not (box and background and box.GetNumPoints) then
        return
    end
    if not original[box] then
        original[box] = Frames.GetPoints(box)
    end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", background, "TOPLEFT", -3, ABOVE)
    box:SetPoint("BOTTOMRIGHT", background, "TOPRIGHT", 1, ABOVE)
end

function module:IsAvailable()
    return _G.ChatFrame1 ~= nil and _G.ChatFrame1.editBox ~= nil
end

function module:OnEnable()
    -- Also a window added later: one made for a whisper, or one a reset brings back.
    Chat.EachWindow(self, apply)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        local box = frame.editBox
        local points = box and original[box]
        if points then
            original[box] = nil
            if points[1] then
                Frames.SetPoints(box, points)
            end
        end
    end
end
