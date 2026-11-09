-- Chat Copy: a button in the column beside the chat window that opens the selected chat tab in a
-- window, in its chat colors and already selected, so Ctrl+C copies it as plain text. Its Select
-- All button selects it all again after a click or scroll lost the selection; it can't copy by
-- itself, since CopyToClipboard is protected (only Blizzard's secure code may call it). The lines
-- come from the chat frame's own buffer (GetMessageInfo); a line the game marks secret can't be
-- read, so it shows as a placeholder instead.
-- Its Click Timestamps option makes the timestamp Blizzard puts on each chat line a link: clicking
-- it shows that line in a popup to copy. Blizzard adds the stamp itself, so the finished line is
-- rewritten through the chat frame's own TransformMessages, a frame after it arrives (so other
-- modules rewriting the same line see it first). The link is the stamp's own text in the line's
-- color, so nothing looks different; the popup is there to copy from, as the window is.
local _, ns = ...

local CreateFrame, C_Timer, EventRegistry = CreateFrame, C_Timer, EventRegistry
local ipairs, pairs, type, time = ipairs, pairs, type, time
local floor, concat = math.floor, table.concat
local find, match, sub = string.find, string.match, string.sub

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatCopy", L.CHATCOPY_DESC, {
    stamps = false,
})
module.title = L.CHATCOPY_TITLE
module.category = "chat"

module.notice = Chat.HiddenNotice(module.name, L.CHATCOPY_BUTTON_HIDDEN, L.CHATCOPY_BUTTON_HIDDEN_DESC)

module.options = {
    {
        key = "stamps",
        name = L.CHATCOPY_STAMPS,
        description = L.CHATCOPY_STAMPS_DESC,
        added = "0.8.0",
    },
}

-- The window's text box is limited in length; a long chat drops its oldest lines to fit, with
-- room left for the selection marker below.
local MAX_LETTERS = 200000
local MAX_TEXT = MAX_LETTERS - 100

-- Copying from an edit box copies its raw text, color codes and all, so while Ctrl (or Cmd) is
-- held the box holds the plain text instead, with the same selection.
local COPY_KEYS = { LCTRL = true, RCTRL = true, LMETA = true, RMETA = true }
-- Typed over the selection to find where it is; edit boxes have no way to ask.
local MARKER = "{fpp:selection}"

local button, window

---The chat window the player is looking at in its chat colors, newest line last: every line it
---holds (Blizzard's windows keep 128).
---@return string
local function chatText()
    local frame = SELECTED_CHAT_FRAME or ChatFrame1
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then
        return ""
    end
    local total = frame:GetNumMessages()
    local lines, size = {}, 0
    for i = total, 1, -1 do
        local text, r, g, b = frame:GetMessageInfo(i)
        local line
        if ns.IsText(text) then
            if not (ns.IsReadable(r) and ns.IsReadable(g) and ns.IsReadable(b)) then
                r, g, b = nil, nil, nil
            end
            line = Chat.Colored(text, r, g, b)
        else
            line = L.CHATCOPY_HIDDEN
        end
        size = size + #line + 1
        if size > MAX_TEXT then
            break
        end
        lines[#lines + 1] = line
    end
    -- Gathered newest first; the window shows them oldest first.
    local count = #lines
    for i = 1, floor(count / 2) do
        lines[i], lines[count - i + 1] = lines[count - i + 1], lines[i]
    end
    return concat(lines, "\n")
end

---Where the selection is in the box's text, as the bytes before its start and its end. This types
---over the selection, so the caller sets the box's text again after.
---@param edit table
---@param text string what the box holds
---@return number? start
---@return number? finish
local function selection(edit, text)
    edit:Insert(MARKER)
    local now = edit:GetText()
    local at = now:find(MARKER, 1, true)
    if not at then
        return nil
    end
    local start = at - 1
    return start, #text - (#now - start - #MARKER)
end

---Shows the plain or the colored text, keeping the selection and the scroll.
---@param plain boolean
local function showPlain(plain)
    if not window or window.plain == plain then
        return
    end
    local edit, colored = window.edit, window.colored
    local from = window.plain and Chat.Uncolor(colored) or colored
    local scroll = window.scroll:GetVerticalScroll()
    local start, finish = selection(edit, from)
    local length = #from
    edit:SetText(plain and Chat.Uncolor(colored) or colored)
    window.plain = plain
    if start == 0 and finish == length then
        edit:HighlightText()
    elseif start then
        local convert = plain and Chat.PlainOffset or Chat.ColoredOffset
        start, finish = convert(colored, start), convert(colored, finish)
        edit:SetCursorPosition(finish)
        edit:HighlightText(start, finish)
    end
    window.scroll:SetVerticalScroll(scroll)
end

local function newWindow()
    -- Named so Escape can close it (ns.Frames.CloseOnEscape).
    local f = ns.Frames.PortraitWindow("ForeverPlusPlusChatCopy", L.CHATCOPY_TITLE)
    f:SetSize(540, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", f.StartMoving)
    f:SetScript("OnMouseUp", f.StopMovingOrSizing)
    ns.Frames.CloseOnEscape(f)

    -- The text in the window's sunken box, below the portrait.
    local inset = f.Inset or ns.Frames.Inset(f)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 4, -60)
    inset:SetPoint("BOTTOMRIGHT", -6, 28)
    local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetMaxLetters(MAX_LETTERS)
    edit:SetWidth(480)
    edit:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    edit:SetScript("OnKeyDown", function(_, key)
        if COPY_KEYS[key] then
            showPlain(true)
        end
    end)
    edit:SetScript("OnKeyUp", function(_, key)
        if COPY_KEYS[key] then
            showPlain(false)
        end
    end)
    edit:SetScript("OnEditFocusLost", function()
        showPlain(false)
        f.hint:SetText("")
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width)
        edit:SetWidth(width)
    end)

    -- The strip at the bottom, as Error Catcher's: the button, and what to press beside it.
    f.selectAll = ns.Frames.Button(f, L.CHATCOPY_SELECT_ALL, 110, function()
        edit:SetFocus()
        edit:HighlightText()
        f.hint:SetText(L.CHATCOPY_SELECT_HINT)
    end)
    f.selectAll:SetPoint("BOTTOMRIGHT", -6, 4)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    f.hint:SetPoint("RIGHT", f.selectAll, "LEFT", -10, 0)

    f.edit, f.scroll = edit, scroll
    f:Hide()
    return f
end

local function open()
    window = window or newWindow()
    local text = chatText()
    window.colored = text ~= "" and text or L.CHATCOPY_EMPTY
    window.plain = false
    window.hint:SetText("")
    window.edit:SetText(window.colored)
    window:Show()
    window.edit:SetFocus()
    window.edit:HighlightText()
    -- Newest lines are at the bottom; the scroll range is known once the text has been laid out.
    C_Timer.After(0, function()
        if window:IsShown() then
            window.scroll:SetVerticalScroll(window.scroll:GetVerticalScrollRange())
        end
    end)
end

local function toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        open()
    end
end

local function newButton()
    return Chat.NewButton("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", toggle,
        L.CHATCOPY_TOOLTIP, L.CHATCOPY_TOOLTIP_DESC)
end

-- Click Timestamps ----------------------------------------------------------------------------

-- addon links go to EventRegistry's "SetItemRef" when clicked. The number tells the lines apart:
-- the session's start time, then a count, since Chat History brings back lines from before.
local LINK_PREFIX = "addon:ForeverPlusPlus:stamp:"
local SESSION = time() .. "."

local stampsOn = false
local lastStamp = 0
local pending = {}

---Makes the timestamp of each line in a chat window that has none yet a link.
---@param frame table
local function linkStamps(frame)
    local format = Chat.TimestampFormat()
    if not format then
        return
    end
    local pattern = Chat.TimestampPattern(format)
    Chat.Transform(frame, function(message)
        return find(message, pattern) ~= nil
    end, function(message)
        local _, finish = find(message, pattern)
        -- The space after the stamp stays outside the link.
        local stamp, space = match(sub(message, 1, finish), "^(.-)(%s*)$")
        lastStamp = lastStamp + 1
        return "|H" .. LINK_PREFIX .. SESSION .. lastStamp .. "|h" .. stamp .. "|h" .. space
            .. sub(message, finish + 1)
    end)
end

local function linkPending()
    for frame in pairs(pending) do
        pending[frame] = nil
        if stampsOn then
            linkStamps(frame)
        end
    end
end

local linkSoon = ns.Frames.Coalesce(linkPending, nil, module)

local function onMessage(frame)
    if not stampsOn then
        return
    end
    pending[frame] = true
    linkSoon()
end

---Shows the chat line that has a stamp link in a popup, as plain text ready to copy.
---@param link string
---@param frame table? the chat window it was clicked in
local function onStampClick(_, link, _, button, frame)
    if not (stampsOn and type(link) == "string" and button == "LeftButton") then
        return
    end
    local id = match(link, "^" .. LINK_PREFIX .. "([%d%.]+)$")
    if not id then
        return
    end
    frame = frame or SELECTED_CHAT_FRAME or ChatFrame1
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then
        return
    end
    local wanted = "|H" .. LINK_PREFIX .. id .. "|h"
    for i = 1, frame:GetNumMessages() do
        local text = frame:GetMessageInfo(i)
        if ns.IsText(text) and find(text, wanted, 1, true) == 1 then
            ns.Prompt("CHATCOPY_LINE", L.CHATCOPY_STAMPS_PROMPT, ns.Text.Plain(text))
            return
        end
    end
end

local function attach()
    for _, frame in ipairs(Chat.Frames()) do
        module:Hook(frame, "AddMessage", onMessage)
    end
end

---Turns Click Timestamps on or off to match the option.
local function updateStamps()
    local on = (module.enabled and module.db.stamps and EventRegistry ~= nil) and true or false
    if on == stampsOn then
        return
    end
    stampsOn = on
    if on then
        attach()
        module:Hook("FCF_OpenTemporaryWindow", attach) -- a whisper popped out into its own tab
        EventRegistry:RegisterCallback("SetItemRef", onStampClick, module)
        for _, frame in ipairs(Chat.Frames()) do
            linkStamps(frame)
        end
    else
        -- The stamps stay links: they look the same, and clicking one does nothing now. Rewriting
        -- the lines would bring back every line that had faded out (Chat.Transform).
        EventRegistry:UnregisterCallback("SetItemRef", module)
    end
end

-- A chat window added later. One function for every turn on, as with the hooks.
local function onWindows()
    if stampsOn then
        attach()
    end
end

function module:OnOptionChanged(key)
    if key == "stamps" then
        updateStamps()
    end
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.GetMessageInfo ~= nil
end

function module:OnEnable()
    button = button or newButton()
    button:Show()
    Chat.AddButton(self.name, button, 20)
    updateStamps()
    self:On("UPDATE_CHAT_WINDOWS", onWindows)
    self:On("UPDATE_FLOATING_CHAT_WINDOWS", onWindows)
end

function module:OnDisable()
    updateStamps()
    Chat.RemoveButton(self.name)
    if button then
        button:Hide()
    end
    if window then
        window:Hide()
    end
end
