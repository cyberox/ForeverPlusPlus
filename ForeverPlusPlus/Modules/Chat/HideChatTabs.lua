-- Hide Chat Tabs: the chat windows' tabs can't be seen until the mouse is over the chat, and fade
-- in and out as Blizzard fades them.
--
-- Blizzard only dims a tab while the mouse is away: to 0.4 for the tab in front, 0.2 for the
-- others (FCF_FadeOutChatFrame, and the two alphas ChatFrameUtil keeps for each tab). It sets
-- those on the tab itself, in its own fades, so nothing of ours can go there. A tab's art and
-- name are regions of it though (ChatTabArtTemplate in FloatingChatFrame.xml), whose own alpha
-- nothing of Blizzard's sets and which multiplies with the tab's: those are faded here, after the
-- same two calls (ns.Chat.OnFade). Two are left alone: the glow that flashes on a tab with a new
-- message, so that still shows, and the highlight, which only draws with the mouse on the tab.
-- A tab that can't be seen still takes clicks and drags.
-- (wow-ui-source's `forever` branch, read 2026-11-24.)
local _, ns = ...

local _G, ipairs = _G, ipairs

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("HideChatTabs", L.HIDECHATTABS_DESC, {
    enabled = false,
})
module.title = L.HIDECHATTABS_TITLE
module.category = "chat"
module.added = "1.9.0"

-- The regions of a tab that are faded, by their key on it.
local PARTS = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight", "Text",
    "conversationIcon" }

---A chat window's tab.
---@param frame table a chat window
---@return table?
local function tabOf(frame)
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "Tab"]
end

---Sets how much of a window's tab shows.
---@param frame table a chat window
---@param amount number 0 for none of it to 1 for all
local function set(frame, amount)
    local tab = tabOf(frame)
    if not tab then
        return
    end
    for _, key in ipairs(PARTS) do
        local region = tab[key]
        if region and region.SetAlpha then
            region:SetAlpha(amount)
        end
    end
end

function module:IsAvailable()
    return _G.ChatFrame1 ~= nil and _G.ChatFrame1Tab ~= nil
end

function module:OnEnable()
    Chat.OnFade(self, set)
    -- Also a window added later, whose tab starts as faded as the window is.
    Chat.EachWindow(self, function(frame)
        set(frame, Chat.FadeAmount(frame))
    end)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        set(frame, 1)
    end
end
