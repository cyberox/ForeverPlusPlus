-- Social Button: the social (Quick Join) button sits above the chat window on its own. This puts
-- it at the bottom of the column of small buttons beside the window, with the others, and gives
-- it back its place when the module turns off. The button is an ordinary frame; Blizzard moves it
-- from its own code now and then, so its SetPoint is hooked to put it back.
local _, ns = ...

local ipairs = ipairs

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("SocialButton", L.SOCIALBUTTON_DESC, {
})
module.title = L.SOCIALBUTTON_TITLE
module.category = "chat"

local original -- where Blizzard had the button: its parent and anchor points

local function remember(button)
    original = { parent = button:GetParent(), points = ns.Frames.GetPoints(button) }
end

local function restore(button)
    if not original then
        return
    end
    button:SetParent(original.parent)
    ns.Frames.SetPoints(button, original.points)
end

-- Blizzard's chat alerts (Text to Speech, voice prompts) stack on the button, the first in
-- ChatAlertFrame's chain; with the button in our column they'd sit on top of it. The alert that
-- anchors to it goes where the button would have been: on the chain's base.
local function unchainAlerts()
    local container, button = _G.ChatAlertFrame, QuickJoinToastButton
    local systems = container and container.alertFrameSubSystems
    if not systems then
        return
    end
    local base = container.baseAnchorFrame or container
    for _, system in ipairs(systems) do
        local frame = system.anchorFrame
        if frame and frame ~= button and frame.GetPoint and frame:IsShown() then
            local point, relativeTo, relativePoint = frame:GetPoint(1)
            if relativeTo == button then
                frame:ClearAllPoints()
                frame:SetPoint(point, base, relativePoint, 0, 0)
            end
        end
    end
end

-- Blizzard moved the button: put it back in the column. One function for every turn on, since
-- module:Hook hooks a function once, and a new one each time would add another hook.
local function onSetPoint()
    if not Chat.IsLaying() then
        Chat.Layout()
    end
end

function module:IsAvailable()
    return QuickJoinToastButton ~= nil and Chat.Anchor() ~= nil
end

function module:OnEnable()
    local button = QuickJoinToastButton
    if not original then
        remember(button)
    end
    local host = Chat.Anchor():GetParent()
    if host then
        button:SetParent(host)
    end
    -- Its line in the chat menu while the chat window is too short for it: its own art (QuickJoinToast.xml).
    Chat.AddButton(self.name, button, 10, "|A:quickjoin-button-friendslist-up:16:16|a " .. L.SOCIALBUTTON_MENU)
    self:Hook(button, "SetPoint", onSetPoint)
    -- Probe: ChatAlertFrame and its subsystem list are Mainline's (AlertFrames.lua).
    if _G.ChatAlertFrame and _G.ChatAlertFrame.UpdateAnchors then
        self:Hook(_G.ChatAlertFrame, "UpdateAnchors", unchainAlerts)
    end
    unchainAlerts()
end

function module:OnDisable()
    Chat.RemoveButton(self.name, true)
    restore(QuickJoinToastButton)
    -- The buttons below it (Chat Copy's) were anchored to it, so lay them out again now it's back.
    Chat.Layout()
end
