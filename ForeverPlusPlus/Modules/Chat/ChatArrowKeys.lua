-- Chat Arrow Keys: while you type in chat, Up and Down bring back what you sent before and Left
-- and Right move through the text, without holding Alt.
--
-- The chat box already remembers what you sent, but reads the arrow keys only with Alt held, so
-- they keep moving your character while it's open (its "alt arrow key mode"). This turns that
-- off. It's the game's own history and the game's own typing, so a recalled slash command is sent
-- as if typed; nothing of ours writes into the box. Each box's own mode is kept to put back.
local _, ns = ...

local ipairs, setmetatable = ipairs, setmetatable

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatArrowKeys", L.CHATARROWKEYS_DESC, {
    enabled = true,
})
module.title = L.CHATARROWKEYS_TITLE
module.category = "chat"
module.added = "1.5.0"

local modes = setmetatable({}, { __mode = "k" }) -- edit box -> its mode before ours

local function editBoxOf(frame)
    return frame.editBox or _G[(frame:GetName() or "") .. "EditBox"]
end

local function apply(frame)
    local box = editBoxOf(frame)
    if not (box and box.SetAltArrowKeyMode and box.GetAltArrowKeyMode) then
        return
    end
    if module.enabled and modes[box] == nil then
        modes[box] = box:GetAltArrowKeyMode() and true or false
        box:SetAltArrowKeyMode(false)
    elseif not module.enabled and modes[box] ~= nil then
        box:SetAltArrowKeyMode(modes[box])
        modes[box] = nil
    end
end

function module:IsAvailable()
    local box = ChatFrame1 and editBoxOf(ChatFrame1)
    return box ~= nil and box.SetAltArrowKeyMode ~= nil
end

function module:OnEnable()
    -- Every window's chat box, and one added later.
    Chat.EachWindow(self, apply)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        apply(frame)
    end
end
