-- Agent Chat's window, drawn like Whisper Window's: your T3 Code threads on the left, newest first,
-- and the one picked on the right, as a chat. It can be dragged and resized, and remembers where.
-- AgentChat.lua keeps what it shows and calls internal.Refresh when that changes.
local _, ns = ...

local ipairs, format, time, type, pcall, tostring, tonumber, select, unpack = ipairs, string.format, time,
    type, pcall, tostring, tonumber, select, unpack
local max, min = math.max, math.min
local CreateFrame, UIParent, GameTooltip = CreateFrame, UIParent, GameTooltip

local L = ns.L
local Frames, Colors = ns.Frames, ns.Colors
local module = ns.modules.AgentChat
local internal = module.internal

local WINDOW_NAME = "ForeverPlusPlusAgentChat" -- named so Escape closes it
local WIDTH, HEIGHT = 760, 460
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 560, 300, 1400, 1000
local LIST_WIDTH = 230
local ROW_HEIGHT = 38
local MAX_LINES = 6000
local MAX_SEND = 4000 -- characters in one message: about 15 seconds to send, at 28 bytes a frame

-- Colors: what you wrote in gold like the game's own headings, the agent in the light blue of
-- Blizzard's whisper you sent, and notes in gray.
local YOU = { 1, 0.82, 0 }
local AGENT = { 0.55, 0.78, 1 }
local TEXT = { 0.92, 0.92, 0.92 }
local NOTE = { 0.6, 0.6, 0.6 }

local window

---Whether the window is open.
---@return boolean
function internal.IsShown()
    return window ~= nil and window:IsShown()
end

local function byId(id)
    for _, thread in ipairs(internal.threads) do
        if thread.id == id then
            return thread
        end
    end
end

-- A thread's state in a word, in its color: working, needs you, failed, or when it last changed.
local WORKING = { running = true, starting = true, preparing = true, queued = true }
local function statusText(thread)
    local status = thread.status
    if WORKING[status] then
        return Colors.Code(0.25, 1, 0.25) .. L.AGENTCHAT_WORKING .. "|r"
    elseif status == "waiting" then
        return Colors.Code(1, 0.82, 0) .. L.AGENTCHAT_NEEDS_YOU .. "|r"
    elseif status == "failed" then
        return Colors.Code(1, 0.3, 0.3) .. L.AGENTCHAT_FAILED .. "|r"
    end
    local updated = tonumber(thread.updated)
    return updated and updated > 0 and ns.Text.Ago(max(0, time() - updated)) or ""
end

local function joinNonEmpty(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if type(part) == "string" and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "  |cff808080\194\183|r  ") -- a gray middle dot
end

-- Text as the game should show it as is: no escape codes from it, no carriage returns.
local function plain(text)
    return (tostring(text or ""):gsub("\r", ""):gsub("|", "||"))
end

-- The list ------------------------------------------------------------------------------------------

local function buildRow(row)
    row.selected = Frames.RowTexture(row, "BACKGROUND", "Options_List_Active", 1, 0.82, 0, 0.15)
    row:SetHighlightTexture(Frames.RowTexture(row, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.08))
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPRIGHT", -6, -6)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", 8, -6)
    row.name:SetPoint("RIGHT", row.info, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.preview = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.preview:SetPoint("BOTTOMLEFT", 8, 6)
    row.preview:SetPoint("BOTTOMRIGHT", -6, 6)
    row.preview:SetJustifyH("LEFT")
    row.preview:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        internal.Select(self.thread.id)
    end)
end

local function initRow(row, thread)
    if not row.name then
        buildRow(row)
    end
    row.thread = thread
    row.name:SetText(plain(thread.title ~= "" and thread.title or L.AGENTCHAT_UNTITLED))
    row.info:SetText(statusText(thread))
    row.preview:SetText(joinNonEmpty(plain(thread.project), plain(thread.model)))
    row.selected:SetShown(thread.id == internal.selected)
end

local function refreshList()
    window.scrollBox:SetDataProvider(CreateDataProvider(internal.threads), ScrollBoxConstants.RetainScrollPosition)
    window.empty:SetShown(#internal.threads == 0 and internal.heard)
end

-- The conversation ---------------------------------------------------------------------------------

local function addText(messages, text, color)
    -- A line at a time: long messages wrap, and blank lines keep their space.
    for line in (plain(text) .. "\n"):gmatch("(.-)\n") do
        messages:AddMessage(line ~= "" and line or " ", color[1], color[2], color[3])
    end
end

-- The queued messages under the conversation, each with Steer and a cancel X, and the reply box
-- and Stop for the thread shown.
local MAX_QUEUE_ROWS = 4
local QUEUE_ROW_HEIGHT = 22

-- A message, read as Markdown.
local function addMarkdown(messages, text, color)
    for _, line in ipairs(ns.Markdown.Lines(text)) do
        messages:AddMessage(line, color[1], color[2], color[3])
    end
end

local function refreshQueue(thread)
    local f = window
    local queue = thread and internal.queues[thread.id]
    local items = queue and queue.items or {}
    local active = (queue and queue.active) or (thread and WORKING[thread.status]) or false
    local shown = min(#items, MAX_QUEUE_ROWS)
    for i, row in ipairs(f.queueRows) do
        local item = i <= shown and items[i]
        row:SetShown(item and true or false)
        if item then
            row.q = item.q
            local text = plain(item.text ~= "" and item.text or L.AGENTCHAT_QUEUED_HIDDEN):gsub("\n", " ")
            if i == MAX_QUEUE_ROWS and #items > MAX_QUEUE_ROWS then
                text = format(L.AGENTCHAT_MORE_QUEUED, #items - MAX_QUEUE_ROWS + 1)
                row.steer:Hide()
                row.cancel:Hide()
            else
                row.steer:Show()
                row.cancel:Show()
                row.steer:SetEnabled(queue.active and true or false)
            end
            row.text:SetText(text)
        end
    end
    f.queue:SetHeight(shown > 0 and shown * QUEUE_ROW_HEIGHT + 4 or 1)
    f.stop:SetEnabled(active and true or false)
    f.edit:SetEnabled(thread ~= nil)
    if thread then
        f.edit.hint:SetText(L.AGENTCHAT_SEND_HINT)
    else
        f.edit.hint:SetText("")
    end
end

local function refreshThread()
    local f = window
    local messages = f.messages
    local thread = internal.selected and byId(internal.selected)
    refreshQueue(thread)
    if not thread then
        f.name:SetText(internal.selected and "" or L.AGENTCHAT_PICK)
        f.details:SetText("")
        messages:Clear()
        return
    end
    f.name:SetText(plain(thread.title ~= "" and thread.title or L.AGENTCHAT_UNTITLED))
    f.details:SetText(joinNonEmpty(plain(thread.project), plain(thread.model), statusText(thread)))

    -- Drawn again whole on each change (a running message grows in place); stay where the player
    -- scrolled to, unless they were at the bottom.
    local atBottom = messages:AtBottom()
    local offset = messages:GetScrollOffset()
    messages:Clear()
    local conversation = internal.conversations[thread.id]
    if not conversation then
        messages:AddMessage(L.AGENTCHAT_LOADING, NOTE[1], NOTE[2], NOTE[3])
        return
    end
    if conversation.older > 0 then
        messages:AddMessage(format(L.AGENTCHAT_OLDER, conversation.older), NOTE[1], NOTE[2], NOTE[3])
    end
    for _, pos in ipairs(conversation.order) do
        local item = conversation.items[pos]
        local you = item.role == "user"
        local who = you and L.AGENTCHAT_YOU or (item.role == "assistant" and (thread.model ~= "" and thread.model
            or L.AGENTCHAT_AGENT)) or item.role
        messages:AddMessage(" ")
        messages:AddMessage(plain(who), unpack(you and YOU or AGENT))
        addMarkdown(messages, item.text, TEXT)
        if item.cut then
            messages:AddMessage(L.AGENTCHAT_CUT, NOTE[1], NOTE[2], NOTE[3])
        end
    end
    -- What the player sent that T3 hasn't taken yet, or turned down.
    for _, sent in ipairs(internal.sending) do
        if sent.threadId == thread.id then
            messages:AddMessage(" ")
            if sent.error then
                messages:AddMessage(format(L.AGENTCHAT_NOT_SENT, plain(sent.error)), 1, 0.3, 0.3)
            else
                messages:AddMessage(L.AGENTCHAT_SENDING, NOTE[1], NOTE[2], NOTE[3])
            end
            addText(messages, sent.text, NOTE)
        end
    end
    if atBottom then
        messages:ScrollToBottom()
    else
        messages:SetScrollOffset(offset)
    end
end

local function refreshStatus()
    local text, color = "", NOTE
    if internal.outOfSlots then
        text, color = L.AGENTCHAT_OUT_OF_SLOTS, { 1, 0.82, 0 }
    elseif internal.note then
        text, color = plain(internal.note), { 1, 0.3, 0.3 }
    elseif not internal.heard then
        text = L.AGENTCHAT_WAITING
    end
    window.status:SetText(text)
    window.status:SetTextColor(color[1], color[2], color[3])
end

---Draws again what changed: "list", "thread", or "status".
---@param what string
function internal.Refresh(what)
    if not (window and window:IsShown()) then
        return
    end
    if what == "list" then
        refreshList()
        refreshThread() -- its title and state are in the list
    elseif what == "thread" then
        refreshThread()
    end
    refreshStatus()
end

-- The window ------------------------------------------------------------------------------------------

local function savePlace()
    if window.SetUserPlaced then
        window:SetUserPlaced(false)
    end
    local point, _, relativePoint, x, y = window:GetPoint(1)
    local layout = module.db.layout
    layout.point, layout.relativePoint, layout.x, layout.y = point, relativePoint, x, y
    layout.width, layout.height = window:GetWidth(), window:GetHeight()
end

local function place()
    local layout = module.db.layout
    window:ClearAllPoints()
    if layout.point then
        window:SetPoint(layout.point, UIParent, layout.relativePoint or layout.point, layout.x or 0, layout.y or 0)
    else
        window:SetPoint("CENTER")
    end
    window:SetSize(layout.width and max(MIN_WIDTH, min(MAX_WIDTH, layout.width)) or WIDTH,
        layout.height and max(MIN_HEIGHT, min(MAX_HEIGHT, layout.height)) or HEIGHT)
end

-- Blizzard's resize grip in the bottom right corner. Probe: Mainline's template.
local function addResizeGrip(f)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    end
    if not Frames.HasTemplate("PanelResizeButtonTemplate") then
        return
    end
    local grip = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    if grip.Init then
        pcall(grip.Init, grip, f, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    end
    grip:HookScript("OnMouseUp", savePlace)
end

local function tooltip(owner, title, text)
    owner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", GameTooltip_Hide)
end

local function newMessages(parent)
    local messages = CreateFrame("ScrollingMessageFrame", nil, parent)
    messages:SetFontObject(ChatFontNormal)
    messages:SetJustifyH("LEFT")
    messages:SetFading(false)
    messages:SetMaxLines(MAX_LINES)
    if messages.SetIndentedWordWrap then
        messages:SetIndentedWordWrap(false)
    end
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(self, delta)
        local steps = IsShiftKeyDown() and 10 or 3
        for _ = 1, steps do
            if delta > 0 then
                self:ScrollUp()
            else
                self:ScrollDown()
            end
        end
    end)
    return messages
end

local function newWindow()
    local f = Frames.PortraitWindow(WINDOW_NAME, L.AGENTCHAT_TITLE)
    window = f
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", f.StartMoving)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        savePlace()
    end)
    Frames.CloseOnEscape(f)
    addResizeGrip(f)

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 66, -38)
    f.summary:SetText(L.AGENTCHAT_SUMMARY)

    -- The threads, on the left.
    local listInset = Frames.Inset(f)
    listInset:SetPoint("TOPLEFT", 4, -60)
    listInset:SetPoint("BOTTOMLEFT", 4, 28)
    listInset:SetWidth(LIST_WIDTH)
    local scrollBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 3, -3)
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 3)
    local scrollBar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    f.scrollBox = scrollBox
    f.empty = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(L.AGENTCHAT_NO_THREADS)
    f.empty:Hide()

    -- The conversation, on the right.
    local details = f.Inset or Frames.Inset(f)
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 2, 0)
    details:SetPoint("BOTTOMRIGHT", -6, 28)
    f.name = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("TOPLEFT", 12, -10)
    f.name:SetPoint("RIGHT", -12, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.details = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.details:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
    f.details:SetPoint("RIGHT", -12, 0)
    f.details:SetJustifyH("LEFT")
    f.details:SetWordWrap(false)
    local line = details:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -48)
    line:SetPoint("TOPRIGHT", -8, -48)
    -- The queue, at the bottom of the conversation: a row per queued message.
    f.queue = CreateFrame("Frame", nil, details)
    f.queue:SetPoint("BOTTOMLEFT", 8, 4)
    f.queue:SetPoint("BOTTOMRIGHT", -8, 4)
    f.queue:SetHeight(1)
    local queueLine = f.queue:CreateTexture(nil, "ARTWORK")
    queueLine:SetColorTexture(1, 1, 1, 0.1)
    queueLine:SetHeight(1)
    queueLine:SetPoint("TOPLEFT")
    queueLine:SetPoint("TOPRIGHT")
    f.queueRows = {}
    for i = 1, MAX_QUEUE_ROWS do
        local row = CreateFrame("Frame", nil, f.queue)
        row:SetHeight(QUEUE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -4 - (i - 1) * QUEUE_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -4 - (i - 1) * QUEUE_ROW_HEIGHT)
        row.cancel = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
        row.cancel:SetSize(20, 20)
        row.cancel:SetPoint("RIGHT", 0, 0)
        row.cancel:SetScript("OnClick", function()
            internal.Cancel(row.q)
        end)
        row.steer = Frames.Button(row, L.AGENTCHAT_STEER, 64, function()
            internal.Steer(row.q)
        end)
        row.steer:SetHeight(20)
        row.steer:SetPoint("RIGHT", row.cancel, "LEFT", -2, 0)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("LEFT", 2, 0)
        label:SetText(L.AGENTCHAT_QUEUED)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", label, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.steer, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        tooltip(row.steer, L.AGENTCHAT_STEER, L.AGENTCHAT_STEER_TIP)
        tooltip(row.cancel, L.AGENTCHAT_CANCEL, L.AGENTCHAT_CANCEL_TIP)
        row:Hide()
        f.queueRows[i] = row
    end

    f.messages = newMessages(details)
    f.messages:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 4, -4)
    f.messages:SetPoint("BOTTOMRIGHT", f.queue, "TOPRIGHT", -2, 4)

    -- How the link is doing, beside the heading.
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("LEFT", f.summary, "RIGHT", 16, 0)
    f.status:SetPoint("RIGHT", -12, 0)
    f.status:SetJustifyH("RIGHT")
    f.status:SetWordWrap(false)

    -- The strip at the bottom: the reply box under the conversation, and Stop.
    f.stop = Frames.Button(f, L.AGENTCHAT_STOP, 70, internal.Stop)
    f.stop:SetPoint("BOTTOMRIGHT", -24, 4)
    tooltip(f.stop, L.AGENTCHAT_STOP, L.AGENTCHAT_STOP_TIP)
    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetHeight(20)
    edit:SetPoint("BOTTOMLEFT", details, "BOTTOMLEFT", 8, -24)
    edit:SetPoint("RIGHT", f.stop, "LEFT", -10, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(MAX_SEND)
    edit:SetFontObject(ChatFontNormal)
    edit:SetScript("OnEnterPressed", function(self)
        if internal.Send(self:GetText()) then
            self:SetText("")
        else
            self:ClearFocus()
        end
    end)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self)
        self.hint:SetShown((self:GetText() or "") == "")
    end)
    edit.hint = edit:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    edit.hint:SetPoint("LEFT", 2, 0)
    f.edit = edit

    f:HookScript("OnShow", function()
        refreshList()
        refreshThread()
        refreshStatus()
        internal.ViewChanged()
    end)
    f:HookScript("OnHide", function()
        f.edit:ClearFocus()
        internal.ViewChanged()
    end)
    place()
    f:Hide()
    return f
end

---Opens or closes the window.
function internal.Toggle()
    if not window then
        newWindow()
    end
    window:SetShown(not window:IsShown())
end

---Closes the window, if it's open.
function internal.Hide()
    if window then
        window:Hide()
    end
end
