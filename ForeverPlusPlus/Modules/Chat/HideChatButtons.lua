-- Hide Chat Buttons: the buttons beside the chat window (Blizzard's menu, channels, and social
-- buttons, and ours: Chat Copy's, Whisper Window's) can't be seen until the mouse is over the
-- chat, and fade in and out with its tabs.
--
-- Blizzard fades the tabs on FCF_FadeInChatFrame and FCF_FadeOutChatFrame, which FCF_OnUpdate calls
-- as the mouse comes over the chat window, its tabs, or its buttons and leaves again. It fades the
-- button frame too, but only of a window that isn't docked, and never below a fifth
-- (FloatingChatFrame.lua, wow-ui-source's forever branch). So the buttons themselves are faded
-- here, after the same two calls: an alpha on each, which multiplies with whatever Blizzard gives
-- the frame they sit in. A faded button still takes clicks, and the mouse over it fades it in.
local _, ns = ...

local _G, ipairs = _G, ipairs
local CreateFrame = CreateFrame

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("HideChatButtons", L.HIDECHATBUTTONS_DESC, {
    enabled = false,
})
module.title = L.HIDECHATBUTTONS_TITLE
module.category = "chat"
module.added = "1.7.0"

-- Seconds to fade in and out, as Blizzard's tabs do (CHAT_FRAME_FADE_TIME, CHAT_FRAME_FADE_OUT_TIME).
local FADE_IN, FADE_OUT = 0.15, 2

local driver -- our frame whose OnUpdate runs a fade; hidden between fades
local alpha, goal = 1, 1

-- The buttons now: everything in the frame that holds Blizzard's chat buttons, which ours join
-- (Lib/Chat.lua), and the social button where it's still above the chat window.
local function buttons()
    local list = {}
    local anchor = Chat.Anchor()
    local host = anchor and anchor:GetParent()
    if host then
        list = { host:GetChildren() }
    end
    local social = _G.QuickJoinToastButton
    if social and social:GetParent() ~= host then
        list[#list + 1] = social
    end
    return list
end

local function set(value)
    alpha = value
    for _, button in ipairs(buttons()) do
        button:SetAlpha(value)
    end
end

local function onUpdate(self, elapsed)
    local step = elapsed / (goal > alpha and FADE_IN or FADE_OUT)
    if goal > alpha then
        set(alpha + step < goal and alpha + step or goal)
    else
        set(alpha - step > goal and alpha - step or goal)
    end
    if alpha == goal then
        self:Hide()
    end
end

local function fadeTo(value)
    goal = value
    -- Set once now as well, so a button added since the last fade joins the others.
    set(alpha)
    driver:SetShown(alpha ~= goal)
end

-- Blizzard calls these for every docked window when the one in front fades, so the main window's
-- call comes whichever tab is in front.
local function onFadeIn(frame)
    if frame == _G.ChatFrame1 then
        fadeTo(1)
    end
end

local function onFadeOut(frame)
    if frame == _G.ChatFrame1 then
        fadeTo(0)
    end
end

function module:IsAvailable()
    return _G.ChatFrame1 ~= nil and Chat.Anchor() ~= nil
end

function module:OnEnable()
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", onUpdate)
    end
    self:Hook("FCF_FadeInChatFrame", onFadeIn)
    self:Hook("FCF_FadeOutChatFrame", onFadeOut)
    -- Blizzard's own note of whether the window is faded in now.
    fadeTo(_G.ChatFrame1.hasBeenFaded and 1 or 0)
end

function module:OnDisable()
    driver:Hide()
    goal = 1
    set(1)
end
