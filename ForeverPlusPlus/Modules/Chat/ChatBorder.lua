-- Chat Border: a border around each chat window, in Blizzard's own frame art. Blizzard's chat
-- windows have a thin border of their own, but it takes the background's color and opacity
-- (FCF_SetWindowColor and FCF_SetWindowAlpha set every texture in CHAT_FRAME_TEXTURES alike), so
-- it can't be seen unless the background can. Ours is a frame of our own in each window, around
-- the window's background, so it shows and hides with the window: a docked window's only while
-- its tab is in front, and none while a window is minimized. It moves and sizes with the window
-- too, in Edit Mode as anywhere, and a window made for a whisper gets one as it opens.
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
    color = "default", -- a COLORS key
    opacity = 100,
    fade = true,
    fadeOpacity = 40, -- as Blizzard's tab in front: CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA is 0.4
    editBox = true,
    editBoxChannel = true,
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

-- The colors, in the order the dropdown lists them: the art as Blizzard drew it, the character's
-- class color, and a few of Blizzard's own font colors by the global each is kept in, with the
-- same color written out for a client that drops one.
local COLORS = {
    { "default", L.CHATBORDER_COLOR_DEFAULT },
    { "class", L.CHATBORDER_COLOR_CLASS },
    { "gold", L.CHATBORDER_COLOR_GOLD, global = "NORMAL_FONT_COLOR", 1, 0.82, 0 },
    { "gray", L.CHATBORDER_COLOR_GRAY, global = "GRAY_FONT_COLOR", 0.5, 0.5, 0.5 },
    { "black", L.CHATBORDER_COLOR_BLACK, global = "BLACK_FONT_COLOR", 0, 0, 0 },
    { "blue", L.CHATBORDER_COLOR_BLUE, global = "BLUE_FONT_COLOR", 0, 0.75, 0.95 },
    { "green", L.CHATBORDER_COLOR_GREEN, global = "GREEN_FONT_COLOR", 0.1, 1, 0.1 },
    { "red", L.CHATBORDER_COLOR_RED, global = "RED_FONT_COLOR", 1, 0.1, 0.1 },
}

local COLOR, COLOR_CHOICES = {}, {}
for _, color in ipairs(COLORS) do
    COLOR[color[1]] = color
    COLOR_CHOICES[#COLOR_CHOICES + 1] = { color[1], color[2] }
end

---The chosen color, as the border's vertex color: white leaves the art as Blizzard drew it.
---@return number r
---@return number g
---@return number b
local function borderColor()
    local key = module.db.color
    local color
    if key == "class" then
        color = ns.Colors.Class("player")
    else
        local fixed = COLOR[key]
        local known = fixed and fixed.global and _G[fixed.global]
        if type(known) == "table" then
            color = known
        elseif fixed and fixed[3] then
            return fixed[3], fixed[4], fixed[5]
        end
    end
    if color and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

module.options = {
    {
        key = "style",
        name = L.CHATBORDER_STYLE,
        description = L.CHATBORDER_STYLE_DESC,
        choices = CHOICES,
    },
    {
        key = "color",
        name = L.CHATBORDER_COLOR,
        description = L.CHATBORDER_COLOR_DESC,
        choices = COLOR_CHOICES,
    },
    {
        key = "opacity",
        name = L.CHATBORDER_OPACITY,
        description = L.CHATBORDER_OPACITY_DESC,
        min = 10, max = 100, step = 5, format = "%d%%",
    },
    {
        key = "fade",
        name = L.CHATBORDER_FADE,
        description = L.CHATBORDER_FADE_DESC,
        slider = "fadeOpacity",
    },
    {
        key = "fadeOpacity",
        name = L.CHATBORDER_FADE_OPACITY,
        description = L.CHATBORDER_FADE_OPACITY_DESC,
        requires = "fade",
        min = 0, max = 100, step = 5, format = "%d%%",
    },
    {
        key = "editBox",
        name = L.CHATBORDER_EDITBOX,
        description = L.CHATBORDER_EDITBOX_DESC,
        section = L.CHATBORDER_SECTION_EDITBOX,
    },
    {
        key = "editBoxChannel",
        name = L.CHATBORDER_EDITBOX_CHANNEL,
        description = L.CHATBORDER_EDITBOX_CHANNEL_DESC,
        section = L.CHATBORDER_SECTION_EDITBOX,
        requires = "editBox",
    },
}

-- Our border frame in each chat window. Weak, so a window that goes takes its border with it.
local borders = setmetatable({}, { __mode = "k" })

---Sets how solid a window's border is: the Opacity, and with Fade with Chat less of it while
---the mouse is away, as Blizzard's tabs are. The window's own background can't be the measure:
---Blizzard fades it between the opacity the player gave the window and a quarter, which for a
---window left as it came are the same (FCF_FadeOutChatFrame, DEFAULT_CHATFRAME_ALPHA).
---@param frame table a chat window
---@param amount number how far Blizzard has faded the window in, 0 to 1
local function fade(frame, amount)
    local border = borders[frame]
    if not border then
        return
    end
    local db = module.db
    local alpha = db.opacity / 100
    if db.fade then
        local away = db.fadeOpacity / 100
        alpha = alpha * (away + (1 - away) * amount)
    end
    border:SetAlpha(alpha)
end

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
    -- After SetBackdrop, which draws the pieces anew.
    border:SetBackdropBorderColor(borderColor())
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", background, "TOPLEFT", -style.outset, style.outset)
    border:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", style.outset, -style.outset)
    fade(frame, Chat.FadeAmount(frame))
    border:Show()
end

-- The edit box -------------------------------------------------------------------------------------
-- The box a window's chat is typed in (`frame.editBox`, ChatFrameEditBoxTemplate) is 32 high and
-- hangs under its window: its top 2 under the window's bottom, its left 5 left of the window's,
-- its right 8 past the scroll bar's (FloatingChatFrame.xml). Its own art, three textures
-- (ChatFrameNEditBoxLeft, Mid, Right) and three more that light up in the chat's color while it
-- has focus (`focusLeft`, `focusMid`, `focusRight`), draws a box of another shape, so with Include
-- Edit Box those are made see-through and ours drawn instead: a dark texture of ours in the box,
-- and a border frame that is a child of it, so both show, hide, and dim with the box (the game
-- dims a box left on screen to 0.35, ChatFrameEditBoxMixin:Deactivate).
--
-- The border is as wide as the window's and its top line lies on the window's bottom line, so the
-- two read as one frame with a line between. Its place is given from the box, by the numbers
-- above, so it follows a box that something has moved.

local boxes = setmetatable({}, { __mode = "k" }) -- edit box -> { border, fill, focused, r, g, b }
local FILL_ALPHA = 0.5

---The regions of Blizzard's art on an edit box.
---@param box table
---@return table[]
local function boxArt(box)
    local art = { box.focusLeft, box.focusMid, box.focusRight }
    local name = box.GetName and box:GetName()
    if name then
        art[#art + 1] = _G[name .. "Left"]
        art[#art + 1] = _G[name .. "Mid"]
        art[#art + 1] = _G[name .. "Right"]
    end
    return art
end

---Colors an edit box's border: the chat's color while it's typed in, with the option, and the
---border's own otherwise.
---@param box table
local function colorBox(box)
    local state = boxes[box]
    if not (state and state.border) then
        return
    end
    if module.db.editBoxChannel and state.focused and state.r then
        state.border:SetBackdropBorderColor(state.r, state.g, state.b)
    else
        state.border:SetBackdropBorderColor(borderColor())
    end
end

-- Blizzard shows and hides the focus art with the box's focus (SetFocusRegionsShown), and colors
-- it for the chat the box is set to (SetFocusRegionVertexColors, from UpdateHeader, with that
-- chat's ChatTypeInfo). Ours follows the same two calls.
local function onFocusShown(box, shown)
    local state = boxes[box]
    if state then
        state.focused = shown and true or false
        colorBox(box)
    end
end

local function onFocusColor(box, color)
    local state = boxes[box]
    if state and type(color) == "table" then
        state.r, state.g, state.b = color.r, color.g, color.b
        colorBox(box)
    end
end

---Takes our border off an edit box and gives Blizzard's art back.
---@param box table
local function clearBox(box)
    local state = boxes[box]
    if not (state and state.shown) then
        return
    end
    -- The focus calls go unheard while this is off, so what was heard is forgotten.
    state.shown, state.focused = false, false
    state.border:Hide()
    state.fill:Hide()
    for _, region in ipairs(boxArt(box)) do
        region:SetAlpha(1)
    end
end

---Draws a window's edit box in the chosen style, or gives Blizzard's back without the option.
---@param frame table a chat window
local function applyBox(frame)
    local box = frame.editBox
    if not (box and box.CreateTexture) then
        return
    end
    local style = STYLES[module.db.style]
    if not (style and module.db.editBox) then
        clearBox(box)
        return
    end
    local state = boxes[box]
    if not state then
        local border = CreateFrame("Frame", nil, box, "BackdropTemplate")
        if not border.SetBackdrop then
            return
        end
        -- Under the box's text, which is in a higher layer of the same frame.
        local fill = box:CreateTexture(nil, "BACKGROUND", nil, -8)
        fill:SetColorTexture(0, 0, 0, FILL_ALPHA)
        fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -3)
        fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 1)
        state = { border = border, fill = fill }
        boxes[box] = state
        module:Hook(box, "SetFocusRegionsShown", onFocusShown)
        module:Hook(box, "SetFocusRegionVertexColors", onFocusColor)
    end
    local border, outset = state.border, style.outset
    local backdrop = _G[style.backdrop]
    border:SetBackdrop({
        edgeFile = type(backdrop) == "table" and backdrop.edgeFile or style.file,
        edgeSize = style.size,
    })
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", box, "TOPLEFT", 3 - outset, outset - 4)
    border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", outset - 1, 2 - outset)
    border:SetAlpha(module.db.opacity / 100)
    for _, region in ipairs(boxArt(box)) do
        region:SetAlpha(0)
    end
    state.shown = true
    colorBox(box)
    border:Show()
    state.fill:Show()
end

local function applyAll(frame)
    apply(frame)
    applyBox(frame)
end

function module:IsAvailable()
    return _G.ChatFrame1 ~= nil and CHOICES[1] ~= nil
end

function module:OnEnable()
    -- Before the borders are drawn, so each starts as faded as its window is now.
    Chat.OnFade(self, fade)
    -- Also a window added later: one made for a whisper, or one a reset brings back.
    Chat.EachWindow(self, applyAll)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        local border = borders[frame]
        if border then
            border:Hide()
        end
        if frame.editBox then
            clearBox(frame.editBox)
        end
    end
end

function module:OnOptionChanged()
    if self.enabled then
        for _, frame in ipairs(Chat.Frames()) do
            applyAll(frame)
        end
    end
end
