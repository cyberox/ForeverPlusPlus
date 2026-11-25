-- Chat Border: a border around each chat window, in Blizzard's own frame art. Blizzard's chat
-- windows have a thin border of their own, but it takes the background's color and opacity
-- (FCF_SetWindowColor and FCF_SetWindowAlpha set every texture in CHAT_FRAME_TEXTURES alike), so
-- it can't be seen unless the background can. Ours is a frame of our own in each window, around
-- the window's background, so it shows and hides with the window: a docked window's only while
-- its tab is in front, and none while a window is minimized.
--
-- The background is the texture `frame.Background` (FloatingBorderedFrame in FloatingChatFrame.xml),
-- which Blizzard already stretches over the Combat Log's bar of filter buttons and a window's
-- scroll bar (FloatingChatFrame_UpdateBackgroundAnchors), and anchors the tabs to. Following it
-- puts the border where Blizzard's own is. (wow-ui-source's `forever` branch, read 2026-11-24.)
local _, ns = ...

local _G, ipairs, type, setmetatable = _G, ipairs, type, setmetatable
local CreateFrame = CreateFrame

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatBorder", L.CHATBORDER_DESC, {
    enabled = false,
    style = "tooltip", -- a BORDERS key; set below to one this client has
    opacity = 100,
})
module.title = L.CHATBORDER_TITLE
module.category = "chat"
module.added = "1.9.0"

-- The borders, in the order the dropdown lists them: a backdrop edge file of Blizzard's, at an
-- edge size that suits a chat window, `outset` pixels past the window's background so the line
-- sits on the background's edge. `backdrop` is the global Blizzard keeps it in, read first in
-- case a patch moves the file. The same three, at the same sizes, as Square Minimap's.
local BORDERS = {
    { "tooltip", L.CHATBORDER_STYLE_THIN, backdrop = "BACKDROP_TOOLTIP_16_16_5555",
        file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 16, outset = 4 },
    { "dialog", L.CHATBORDER_STYLE_STONE, backdrop = "BACKDROP_DIALOG_32_32",
        file = "Interface\\DialogFrame\\UI-DialogBox-Border", size = 16, outset = 5 },
    { "gold", L.CHATBORDER_STYLE_GOLD, backdrop = "BACKDROP_GOLD_DIALOG_32_32",
        file = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", size = 16, outset = 5 },
}

local STYLES, CHOICES = {}, {}
for _, style in ipairs(BORDERS) do
    -- Probe: only the borders whose art this client has, when it can say.
    if not GetFileIDFromPath or GetFileIDFromPath(style.file) ~= nil then
        STYLES[style[1]] = style
        CHOICES[#CHOICES + 1] = { style[1], style[2] }
    end
end
module.defaults.style = CHOICES[1] and CHOICES[1][1] or "tooltip"

module.options = {
    {
        key = "style",
        name = L.CHATBORDER_STYLE,
        description = L.CHATBORDER_STYLE_DESC,
        choices = CHOICES,
    },
    {
        key = "opacity",
        name = L.CHATBORDER_OPACITY,
        description = L.CHATBORDER_OPACITY_DESC,
        min = 10, max = 100, step = 5, format = "%d%%",
    },
}

-- Our border frame in each chat window. Weak, so a window that goes takes its border with it.
local borders = setmetatable({}, { __mode = "k" })

---Draws a window's border in the chosen style, making its frame the first time.
---@param frame table a chat window
local function apply(frame)
    local style = STYLES[module.db.style]
    local background = frame.Background
    local border = borders[frame]
    if not (style and background and frame.GetFrameLevel) then
        if border then
            border:Hide()
        end
        return
    end
    if not border then
        border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        if not border.SetBackdrop then
            return
        end
        -- At the window's own level, under its tabs, buttons, and resize corner.
        border:SetFrameLevel(frame:GetFrameLevel())
        borders[frame] = border
    end
    local backdrop = _G[style.backdrop]
    border:SetBackdrop({
        edgeFile = type(backdrop) == "table" and backdrop.edgeFile or style.file,
        edgeSize = style.size,
    })
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", background, "TOPLEFT", -style.outset, style.outset)
    border:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", style.outset, -style.outset)
    border:SetAlpha(module.db.opacity / 100)
    border:Show()
end

function module:IsAvailable()
    return _G.ChatFrame1 ~= nil and CHOICES[1] ~= nil
end

function module:OnEnable()
    -- Also a window added later: one made for a whisper, or one a reset brings back.
    Chat.EachWindow(self, apply)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        local border = borders[frame]
        if border then
            border:Hide()
        end
    end
end

function module:OnOptionChanged()
    if self.enabled then
        for _, frame in ipairs(Chat.Frames()) do
            apply(frame)
        end
    end
end
