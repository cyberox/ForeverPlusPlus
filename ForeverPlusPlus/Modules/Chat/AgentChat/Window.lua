-- Agent Chat's window, drawn like Whisper Window's: your T3 Code threads on the left, those that
-- need you or are working first, and the one picked on the right, as a chat. It can be dragged and
-- resized, and remembers where. AgentChat.lua keeps what it shows and calls internal.Refresh when
-- that changes.
local _, ns = ...

local ipairs, format, time, date, type, pcall, tostring, tonumber, select = ipairs, string.format,
    time, date, type, pcall, tostring, tonumber, select
local max, min, abs, floor = math.max, math.min, math.abs, math.floor
local CreateFrame, UIParent, GameTooltip, C_Timer, IsShiftKeyDown = CreateFrame, UIParent, GameTooltip, C_Timer,
    IsShiftKeyDown

local L = ns.L
local Frames, Colors = ns.Frames, ns.Colors
local module = ns.modules.AgentChat
local internal = module.internal

local WINDOW_NAME = "ForeverPlusPlusAgentChat" -- named so Escape closes it
local WIDTH, HEIGHT = 760, 460
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 560, 320, 1400, 1000
local LIST_WIDTH = 230
local ROW_HEIGHT, GROUP_HEIGHT = 36, 18
local MAX_LINES = 6000
local MAX_SEND = 4000 -- characters in one message: about 15 seconds to send, at 28 bytes a frame
local DAY = 24 * 60 * 60 -- the Active tab shows threads changed this recently
local REPLY_MIN, REPLY_MAX = 40, 74 -- the reply box's height: two lines, growing to four

-- Colors: what you wrote in gold like the game's own headings, the agent in the light blue of
-- Blizzard's whisper you sent, its progress notes dimmed, and notes in gray.
local YOU = { 1, 0.82, 0 }
local AGENT = { 0.55, 0.78, 1 }
local TEXT = { 0.92, 0.92, 0.92 }
local PROGRESS = { 0.62, 0.61, 0.58 }
local NOTE = { 0.6, 0.6, 0.6 }
local GRAY = "|cff808080"

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

-- Text as the game should show it as is: no escape codes from it, no carriage returns.
local function plain(text)
    return (tostring(text or ""):gsub("\r", ""):gsub("|", "||"))
end

local function joinNonEmpty(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if type(part) == "string" and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "  " .. GRAY .. "\194\183|r  ") -- a gray middle dot
end

-- What threads are doing, and how that reads ----------------------------------------------------------

local WORKING = { running = true, starting = true, preparing = true, queued = true }

local function stateOf(thread)
    if WORKING[thread.status] then
        return "working"
    elseif thread.status == "waiting" then
        return "waiting"
    elseif thread.status == "failed" then
        return "failed"
    end
    return internal.IsUnread(thread) and "unread" or "idle"
end

-- "claude-opus-5-5" as "Claude Opus 5.5": words capitalized, and numbers in a row as one version.
local UPPER = { gpt = "GPT" }
local function modelName(model)
    model = tostring(model or "")
    local words, version = {}, nil
    for word in model:gmatch("[^%-_ ]+") do
        if word:match("^%d%d%d%d%d%d%d%d$") then -- a release date ("20250929"): left out
            version = nil
        elseif word:match("^%d+$") and version then
            version = version .. "." .. word
            words[#words] = version
        else
            local nice = UPPER[word:lower()] or (word:sub(1, 1):upper() .. word:sub(2))
            words[#words + 1] = nice
            version = word:match("^%d[%d%.]*$") and nice or nil
        end
    end
    return #words > 0 and table.concat(words, " ") or model
end

-- Who answers in a thread, by the name people know it by.
local PROVIDERS = { { "^claude", "Claude" }, { "^gpt", "Codex" }, { "codex", "Codex" }, { "^o%d", "Codex" },
    { "^gemini", "Gemini" } }
local function agentName(model)
    local lower = tostring(model or ""):lower()
    for _, provider in ipairs(PROVIDERS) do
        if lower:match(provider[1]) then
            return provider[2]
        end
    end
    return lower ~= "" and modelName(model) or L.AGENTCHAT_AGENT
end

local MODES = {
    ["full-access"] = L.AGENTCHAT_MODE_FULL,
    auto = L.AGENTCHAT_MODE_AUTO,
    ["auto-accept-edits"] = L.AGENTCHAT_MODE_EDITS,
    ["approval-required"] = L.AGENTCHAT_MODE_ASK,
}

local function ago(thread)
    local updated = tonumber(thread.updated)
    return updated and updated > 0 and ns.Text.Ago(max(0, time() - updated)) or ""
end

-- A time of day as the game's clock shows it (12 or 24 hours, by its setting).
local function clock(at)
    at = tonumber(at)
    if not at or at <= 0 then
        return ""
    end
    if GameTime_GetFormattedTime then
        local ok, text = pcall(GameTime_GetFormattedTime, tonumber(date("%H", at)), tonumber(date("%M", at)), true)
        if ok and type(text) == "string" then
            return text
        end
    end
    return date("%H:%M", at)
end

-- "2m 10s"
local function duration(seconds)
    seconds = max(0, floor(seconds))
    if seconds < 60 then
        return format(L.AGENTCHAT_SECONDS, seconds)
    elseif seconds < 3600 then
        return format(L.AGENTCHAT_MINUTES, floor(seconds / 60), seconds % 60)
    end
    return format(L.AGENTCHAT_HOURS, floor(seconds / 3600), floor(seconds % 3600 / 60))
end

-- The thread's state in a word, for the conversation's heading: not while working, since the
-- working line under the conversation says so.
local function stateWord(thread)
    local state = stateOf(thread)
    if state == "waiting" then
        return Colors.Code(1, 0.82, 0) .. L.AGENTCHAT_NEEDS_YOU .. "|r"
    elseif state == "failed" then
        return Colors.Code(1, 0.3, 0.3) .. L.AGENTCHAT_FAILED .. "|r"
    end
    return ""
end

-- Icons ------------------------------------------------------------------------------------------------
-- Blizzard's own art: a quest giver's "!" for needs you, the loading spinner for working, the red X
-- for failed, and a round blue dot (the whisper blue) for unread. Probe: atlas names change, so each
-- has a file to fall back on.

local NEEDS_ATLAS = Frames.FirstAtlas("QuestNormal", "quest-icon-exclamation")
local FAILED_ATLAS = Frames.FirstAtlas("common-icon-redx")
local NEEDS_FILE = "Interface\\GossipFrame\\AvailableQuestIcon"
local FAILED_FILE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function newSpinner(parent, size)
    local ok, spinner = pcall(CreateFrame, "Frame", nil, parent, "LoadingSpinnerTemplate")
    if ok and spinner then
        spinner:SetSize(size, size)
        return spinner
    end
end

-- An icon slot that shows one state at a time.
local function newStateIcon(parent, size)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(size, size)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.dot = icon:CreateTexture(nil, "ARTWORK")
    icon.dot:SetSize(size * 0.55, size * 0.55)
    icon.dot:SetPoint("CENTER")
    icon.dot:SetColorTexture(AGENT[1], AGENT[2], AGENT[3])
    local mask = icon:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon.dot)
    icon.dot:AddMaskTexture(mask)
    icon.spinner = newSpinner(icon, size + 4)
    if icon.spinner then
        icon.spinner:SetPoint("CENTER")
    else
        -- No spinner on this client: a green dot instead.
        icon.working = icon:CreateTexture(nil, "ARTWORK")
        icon.working:SetAllPoints(icon.dot)
        icon.working:SetColorTexture(0.25, 1, 0.25)
        icon.working:AddMaskTexture(mask)
    end
    return icon
end

local function setStateIcon(icon, state)
    icon.texture:Hide()
    icon.dot:SetShown(state == "unread")
    if icon.spinner then
        icon.spinner:SetShown(state == "working")
    else
        icon.working:SetShown(state == "working")
    end
    if state == "waiting" or state == "failed" then
        local atlas = state == "waiting" and NEEDS_ATLAS or FAILED_ATLAS
        if atlas then
            icon.texture:SetAtlas(atlas)
        else
            icon.texture:SetTexture(state == "waiting" and NEEDS_FILE or FAILED_FILE)
        end
        icon.texture:Show()
    end
end

-- The list ------------------------------------------------------------------------------------------

local TABS = { "active", "all" }
local TAB_NAMES = { active = L.AGENTCHAT_TAB_ACTIVE, all = L.AGENTCHAT_TAB_ALL }

local function tab()
    local chosen = module.db.layout.tab
    return TAB_NAMES[chosen] and chosen or "active"
end

local function buildRow(row)
    row.selected = Frames.RowTexture(row, "BACKGROUND", "Options_List_Active", 1, 0.82, 0, 0.15)
    row:SetHighlightTexture(Frames.RowTexture(row, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.08))
    row.icon = newStateIcon(row, 14)
    row.icon:SetPoint("TOPLEFT", 6, -5)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.preview = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.preview:SetPoint("BOTTOMLEFT", 25, 5)
    row.preview:SetPoint("BOTTOMRIGHT", -6, 5)
    row.preview:SetJustifyH("LEFT")
    row.preview:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        internal.Select(self.thread.id)
    end)
end

local function initRow(row, element)
    if not row.name then
        buildRow(row)
    end
    local thread = element.thread
    row.thread = thread
    local state = stateOf(thread)
    setStateIcon(row.icon, state)
    row.name:SetText(plain(thread.title ~= "" and thread.title or L.AGENTCHAT_UNTITLED))
    if state == "unread" then
        row.name:SetTextColor(1, 1, 1)
    else
        row.name:SetTextColor(1, 0.82, 0)
    end
    row.preview:SetText(joinNonEmpty(plain(thread.project), ago(thread)))
    row.selected:SetShown(thread.id == internal.selected)
end

local function initGroup(frame, element)
    if not frame.text then
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        frame.text:SetPoint("BOTTOMLEFT", 8, 3)
    end
    frame.text:SetText(element.group)
end

-- The list as the tab shows it: a heading and its threads for each group that has any.
local function listElements()
    local groups = { waiting = {}, working = {}, recent = {} } -- needs you, working, the rest
    local active = tab() == "active"
    local now = time()
    for _, thread in ipairs(internal.threads) do
        local state = stateOf(thread)
        -- A failed thread is over, so it sits with the rest, marked.
        local group = (state == "waiting" or state == "working") and state or "recent"
        local recent = (tonumber(thread.updated) or 0) >= now - DAY
        if not active or group ~= "recent" or state == "unread" or recent or thread.id == internal.selected then
            local list = groups[group]
            list[#list + 1] = { thread = thread }
        end
    end
    local elements = {}
    for _, group in ipairs({ { "waiting", L.AGENTCHAT_NEEDS_YOU }, { "working", L.AGENTCHAT_WORKING },
        { "recent", L.AGENTCHAT_RECENT } }) do
        local list = groups[group[1]]
        if #list > 0 then
            elements[#elements + 1] = { group = group[2] }
            for _, element in ipairs(list) do
                elements[#elements + 1] = element
            end
        end
    end
    return elements
end

local function refreshTabs()
    for _, button in ipairs(window.tabs) do
        local on = button.tab == tab()
        button.selected:SetShown(on)
        button.text:SetFontObject(on and "GameFontNormalSmall" or "GameFontDisableSmall")
    end
end

local function refreshList()
    local elements = listElements()
    window.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
    window.empty:SetText(#internal.threads == 0 and L.AGENTCHAT_NO_THREADS or L.AGENTCHAT_NO_ACTIVE)
    window.empty:SetShown(#elements == 0 and internal.heard)
    refreshTabs()
end

-- The conversation ---------------------------------------------------------------------------------

local function addText(messages, text, color)
    -- A line at a time: long messages wrap, and blank lines keep their space.
    for line in (plain(text) .. "\n"):gmatch("(.-)\n") do
        messages:AddMessage(line ~= "" and line or " ", color[1], color[2], color[3])
    end
end

-- A message, read as Markdown.
local function addMarkdown(messages, text, color)
    for _, line in ipairs(ns.Markdown.Lines(text)) do
        messages:AddMessage(line, color[1], color[2], color[3])
    end
end

-- The queued messages under the conversation, each with Steer and a cancel X, and the reply box
-- and Stop for the thread shown.
local MAX_QUEUE_ROWS = 4
local QUEUE_ROW_HEIGHT = 22

local function isWorking(thread)
    local queue = thread and internal.queues[thread.id]
    return (queue and queue.active) or (thread and WORKING[thread.status]) or false
end

-- "Working for 2m 10s" under the conversation while a turn runs.
local function refreshWorking(thread)
    local f = window
    local working = isWorking(thread)
    f.working:SetShown(working and true or false)
    f.working:SetHeight(working and 18 or 1)
    if not working then
        return
    end
    local queue = internal.queues[thread.id]
    local started = queue and tonumber(queue.started) or 0
    f.working.text:SetText(started > 0 and format(L.AGENTCHAT_WORKING_FOR, duration(time() - started))
        or L.AGENTCHAT_WORKING)
end

local function refreshQueue(thread)
    local f = window
    local queue = thread and internal.queues[thread.id]
    local items = queue and queue.items or {}
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
    f.stop:SetEnabled(isWorking(thread) and true or false)
    f.reply:SetEnabled(thread ~= nil)
    if not thread then
        f.reply.hint:SetText("")
    elseif internal.ShownAsk() then
        f.reply.hint:SetText(L.AGENTCHAT_ANSWER_HINT)
    else
        f.reply.hint:SetText(L.AGENTCHAT_SEND_HINT)
    end
    f.reply.newline:SetShown(thread ~= nil and (f.reply:GetText() or "") == "")
end

-- What the agent asks, above the queue: each question with its options as buttons to pick (one, or
-- several where it takes several), and Answer. Typed text answers a question with nothing picked.
-- Approvals can't be given from here (T3 doesn't offer it), so they only get a line.
local OPTION_HEIGHT = 22
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16:0:-1|t" -- before a picked option

local function askText(f, n)
    local text = f.askTexts[n]
    if not text then
        text = f.ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetJustifyH("LEFT")
        f.askTexts[n] = text
    end
    text:Show()
    return text
end

local function optionButton(f, n)
    local button = f.askButtons[n]
    if not button then
        button = Frames.Button(f.ask, nil, 60)
        button:SetScript("OnClick", function(self)
            internal.Pick(self.a, self.q, self.o)
        end)
        button:SetHeight(OPTION_HEIGHT - 2)
        button:HookScript("OnEnter", function(self)
            if self.tip and self.tip ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self:GetText())
                GameTooltip:AddLine(self.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        button:HookScript("OnLeave", GameTooltip_Hide)
        f.askButtons[n] = button
    end
    button:Show()
    return button
end

local function refreshAsk(thread)
    local f = window
    for _, text in ipairs(f.askTexts) do
        text:Hide()
    end
    for _, button in ipairs(f.askButtons) do
        button:Hide()
    end
    local asks = thread and internal.asks[thread.id]
    local request = thread and internal.ShownAsk()
    local approvals = asks and tonumber(asks.approvals) or 0
    if not request and approvals <= 0 then
        f.ask:SetHeight(1)
        f.ask.line:Hide()
        f.answer:Hide()
        return
    end
    f.ask.line:Show()
    local width = f.ask:GetWidth()
    if width < 100 then
        width = 400 -- not laid out yet; OnSizeChanged draws it again
    end
    local y, texts, buttons = -6, 0, 0
    if request then
        local picks = internal.picks[request.a] or {}
        for q, question in ipairs(type(request.questions) == "table" and request.questions or {}) do
            texts = texts + 1
            local text = askText(f, texts)
            text:SetWidth(width)
            text:SetPoint("TOPLEFT", 0, y)
            local header = plain(question.header)
            text:SetText((header ~= "" and Colors.Code(1, 0.82, 0) .. header .. "|r  " or "") .. plain(question.question))
            y = y - text:GetStringHeight() - 4
            local x = 0
            for o, option in ipairs(type(question.options) == "table" and question.options or {}) do
                buttons = buttons + 1
                local button = optionButton(f, buttons)
                local picked = picks[q] and picks[q][o]
                button.a, button.q, button.o, button.tip = request.a, q, o, plain(option.description)
                button:SetText((picked and CHECK or "") .. plain(option.label))
                local w = min(width, max(60, button:GetFontString():GetStringWidth() + 24))
                button:SetWidth(w)
                if x > 0 and x + w > width then
                    x, y = 0, y - OPTION_HEIGHT
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", x, y)
                if picked then
                    button:LockHighlight()
                    button:GetFontString():SetTextColor(1, 1, 1)
                else
                    button:UnlockHighlight()
                    button:GetFontString():SetTextColor(1, 0.82, 0)
                end
                x = x + w + 4
            end
            y = y - OPTION_HEIGHT - 4
        end
        f.answer:Show()
        f.answer:ClearAllPoints()
        f.answer:SetPoint("TOPRIGHT", 0, y)
        f.answer:SetEnabled(not internal.answering[request.a])
        texts = texts + 1
        local hint = askText(f, texts)
        hint:SetWidth(width - f.answer:GetWidth() - 8)
        hint:SetPoint("TOPLEFT", 0, y - 4)
        hint:SetText(Colors.Code(NOTE[1], NOTE[2], NOTE[3]) .. L.AGENTCHAT_ANSWER_HOW .. "|r")
        y = y - OPTION_HEIGHT - 2
    else
        f.answer:Hide()
    end
    if approvals > 0 then
        texts = texts + 1
        local text = askText(f, texts)
        text:SetWidth(width)
        text:SetPoint("TOPLEFT", 0, y)
        text:SetText(Colors.Code(1, 0.82, 0) .. (approvals == 1 and L.AGENTCHAT_APPROVAL
            or format(L.AGENTCHAT_APPROVALS, approvals)) .. "|r")
        y = y - text:GetStringHeight() - 4
    end
    f.ask:SetHeight(-y + 2)
end

-- A speaker's name, with the time of their first message in gray.
local function speaker(messages, name, color, at)
    local when = clock(at)
    messages:AddMessage(" ")
    messages:AddMessage(Colors.Code(color[1], color[2], color[3]) .. plain(name) .. "|r"
        .. (when ~= "" and "  " .. GRAY .. when .. "|r" or ""))
end

local function refreshThread()
    local f = window
    local messages = f.messages
    local thread = internal.selected and byId(internal.selected)
    refreshQueue(thread)
    refreshAsk(thread)
    refreshWorking(thread)
    if not thread then
        f.name:SetText(internal.selected and "" or L.AGENTCHAT_PICK)
        f.details:SetText("")
        messages:Clear()
        return
    end
    f.name:SetText(plain(thread.title ~= "" and thread.title or L.AGENTCHAT_UNTITLED))
    f.details:SetText(joinNonEmpty(plain(thread.project), plain(modelName(thread.model)), MODES[thread.mode] or "",
        stateWord(thread)))

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
    -- Messages in a row from the same side go under one name: yours, or the agent's turn.
    local agent = agentName(thread.model)
    local last
    for _, pos in ipairs(conversation.order) do
        local item = conversation.items[pos]
        local you = item.role == "user"
        if item.role ~= last then
            local name = you and L.AGENTCHAT_YOU or (item.role == "assistant" and agent) or item.role
            speaker(messages, name, you and YOU or AGENT, item.at)
            last = item.role
        end
        -- The game can't show them, so say they're there (the program guesses from T3's folder).
        local images, files = tonumber(item.images) or 0, tonumber(item.files) or 0
        if images > 0 then
            messages:AddMessage(images == 1 and L.AGENTCHAT_IMAGE or format(L.AGENTCHAT_IMAGES, images),
                NOTE[1], NOTE[2], NOTE[3])
        end
        if files > 0 then
            messages:AddMessage(files == 1 and L.AGENTCHAT_FILE or format(L.AGENTCHAT_FILES, files),
                NOTE[1], NOTE[2], NOTE[3])
        end
        -- The agent's notes along the way are dimmed; its last message in a turn is the answer.
        local progress = item.role == "assistant" and item.final == false
        addMarkdown(messages, item.text, progress and PROGRESS or TEXT)
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

-- The list's tabs: small buttons over it, the chosen one lit like a selected list row.
local function newTabs(f, parent)
    f.tabs = {}
    local x = 6
    for _, key in ipairs(TABS) do
        local button = CreateFrame("Button", nil, parent)
        button.tab = key
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.text:SetPoint("CENTER")
        button.text:SetText(TAB_NAMES[key])
        button:SetSize(button.text:GetStringWidth() + 16, 18)
        button:SetPoint("TOPLEFT", x, -4)
        button.selected = Frames.RowTexture(button, "BACKGROUND", "Options_List_Active", 1, 0.82, 0, 0.15)
        button:SetHighlightTexture(Frames.RowTexture(button, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.08))
        button:SetScript("OnClick", function(self)
            module.db.layout.tab = self.tab
            refreshList()
        end)
        x = x + button:GetWidth() + 2
        f.tabs[#f.tabs + 1] = button
    end
end

-- The reply box: two lines high, growing to four as it fills, then scrolling. Enter sends (or
-- answers what the agent asks), Shift+Enter starts a new line.
local function sendReply(text)
    if internal.ShownAsk() then
        return internal.Answer((text:gsub("\n", " ")))
    end
    return internal.Send(text)
end

local function newReply(f)
    local box = Frames.Inset(f)
    box:SetHeight(REPLY_MIN)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", -6, 5)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(MAX_SEND)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetHeight(REPLY_MIN - 10) -- a multi-line box grows from here as it fills
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(self, width)
        edit:SetWidth(width)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local most = max(0, edit:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(most, max(0, self:GetVerticalScroll() - delta * 14)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)

    -- Keep the cursor in view.
    edit:SetScript("OnCursorChanged", function(self, _, y, _, height)
        local top, shown = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then
            scroll:SetVerticalScroll(y)
        elseif y + height > top + shown then
            scroll:SetVerticalScroll(y + height - shown)
        end
    end)

    -- What the text was before its last change, to tell whether Enter itself just added a line.
    local before, now = "", ""
    edit:SetScript("OnTextChanged", function(self)
        before, now = now, self:GetText() or ""
        box.hint:SetShown(now == "")
        box.newline:SetShown(now == "" and box.hint:GetText() ~= "")
        box:SetHeight(min(REPLY_MAX, max(REPLY_MIN, self:GetHeight() + 10)))
    end)
    -- A multi-line box may put Enter's line break in before or after OnEnterPressed; this works
    -- either way: a break Enter added before is taken out of what's sent, and one added after is
    -- cleared on the next frame.
    edit:SetScript("OnEnterPressed", function(self)
        local text = self:GetText() or ""
        local cursor = self:GetCursorPosition() or 0
        local added = cursor > 0 and text:sub(cursor, cursor) == "\n"
            and text:sub(1, cursor - 1) .. text:sub(cursor + 1) == before
        if IsShiftKeyDown() then
            if not added then
                C_Timer.After(0, function()
                    if self:GetText() == text then
                        self:Insert("\n")
                    end
                end)
            end
            return
        end
        if added then
            text = before
        end
        if sendReply(text) then
            self:SetText("")
            C_Timer.After(0, function()
                if self:GetText() == "\n" then
                    self:SetText("")
                end
            end)
        else
            if added then
                self:SetText(text)
            end
            self:ClearFocus()
        end
    end)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    box.hint:SetPoint("TOPLEFT", 8, -7)
    box.newline = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.newline:SetPoint("BOTTOMLEFT", 8, 6)
    box.newline:SetText(L.AGENTCHAT_NEWLINE_HINT)
    box.edit = edit

    -- What the rest of the window calls: like an edit box.
    function box:SetEnabled(enabled)
        edit:SetEnabled(enabled)
        if not enabled then
            edit:ClearFocus()
        end
    end
    function box:GetText()
        return edit:GetText()
    end
    function box:SetText(text)
        edit:SetText(text)
    end
    function box:ClearFocus()
        edit:ClearFocus()
    end
    return box
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

    -- The threads, on the left, under their tabs.
    local listInset = Frames.Inset(f)
    listInset:SetPoint("TOPLEFT", 4, -60)
    listInset:SetPoint("BOTTOMLEFT", 4, 6)
    listInset:SetWidth(LIST_WIDTH)
    newTabs(f, listInset)
    local tabLine = listInset:CreateTexture(nil, "ARTWORK")
    tabLine:SetColorTexture(1, 1, 1, 0.1)
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", 4, -24)
    tabLine:SetPoint("TOPRIGHT", -4, -24)
    local scrollBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 3, -26)
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 3)
    local scrollBar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(function(factory, element)
        if element.group then
            factory("Frame", initGroup)
        else
            factory("Button", initRow)
        end
    end)
    view:SetElementExtentCalculator(function(_, element)
        return element.group and GROUP_HEIGHT or ROW_HEIGHT
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    f.scrollBox = scrollBox
    f.empty = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("LEFT", 12, 0)
    f.empty:SetPoint("RIGHT", -12, 0)
    f.empty:SetText(L.AGENTCHAT_NO_THREADS)
    f.empty:Hide()

    -- The strip at the bottom right: the reply box and Stop.
    f.stop = Frames.Button(f, L.AGENTCHAT_STOP, 70, internal.Stop)
    tooltip(f.stop, L.AGENTCHAT_STOP, L.AGENTCHAT_STOP_TIP)
    f.reply = newReply(f)
    f.reply:SetPoint("BOTTOMLEFT", listInset, "BOTTOMRIGHT", 2, 0)
    f.reply:SetPoint("RIGHT", f.stop, "LEFT", -8, 0)
    f.stop:SetPoint("BOTTOMRIGHT", -24, 10)

    -- The conversation, on the right, over the reply box: down to a line as wide as the window's
    -- right side, at the reply box's top, so it follows the box as that grows.
    local replyTop = CreateFrame("Frame", nil, f)
    replyTop:SetPoint("BOTTOMLEFT", f.reply, "TOPLEFT")
    replyTop:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    replyTop:SetHeight(1)
    local details = f.Inset or Frames.Inset(f)
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 2, 0)
    details:SetPoint("BOTTOMRIGHT", replyTop, "BOTTOMRIGHT", 0, 4)
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

    -- What the agent asks, above the queue.
    f.ask = CreateFrame("Frame", nil, details)
    f.ask:SetPoint("BOTTOMLEFT", f.queue, "TOPLEFT", 0, 0)
    f.ask:SetPoint("BOTTOMRIGHT", f.queue, "TOPRIGHT", 0, 0)
    f.ask:SetHeight(1)
    f.ask.line = f.ask:CreateTexture(nil, "ARTWORK")
    f.ask.line:SetColorTexture(1, 1, 1, 0.1)
    f.ask.line:SetHeight(1)
    f.ask.line:SetPoint("TOPLEFT")
    f.ask.line:SetPoint("TOPRIGHT")
    f.ask.line:Hide()
    f.askTexts, f.askButtons = {}, {}
    f.answer = Frames.Button(f.ask, L.AGENTCHAT_ANSWER, 80, function()
        if sendReply(f.reply:GetText() or "") then
            f.reply:SetText("")
        end
    end)
    f.answer:SetHeight(OPTION_HEIGHT - 2)
    f.answer:Hide()
    local lastWidth = 0
    f.ask:SetScript("OnSizeChanged", function(self, width)
        if abs(width - lastWidth) >= 1 then -- only the width changes the layout
            lastWidth = width
            refreshAsk(internal.selected and byId(internal.selected))
        end
    end)

    -- "Working for 2m 10s", over what the agent asks, ticking each second while shown.
    f.working = CreateFrame("Frame", nil, details)
    f.working:SetPoint("BOTTOMLEFT", f.ask, "TOPLEFT", 4, 2)
    f.working:SetPoint("BOTTOMRIGHT", f.ask, "TOPRIGHT", 0, 2)
    f.working:SetHeight(1)
    f.working.spinner = newSpinner(f.working, 16)
    f.working.text = f.working:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.working.text:SetTextColor(0.25, 1, 0.25)
    if f.working.spinner then
        f.working.spinner:SetPoint("LEFT", -2, 0)
        f.working.text:SetPoint("LEFT", f.working.spinner, "RIGHT", 2, 0)
    else
        f.working.text:SetPoint("LEFT")
    end
    f.working:Hide()
    f.working:SetScript("OnUpdate", Frames.Throttled(1, ns.Profiler.Wrap(module, function()
        refreshWorking(internal.selected and byId(internal.selected))
    end)))

    f.messages = newMessages(details)
    f.messages:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 4, -4)
    f.messages:SetPoint("BOTTOMRIGHT", f.working, "TOPRIGHT", -2, 4)

    -- How the link is doing, beside the heading.
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("LEFT", f.summary, "RIGHT", 16, 0)
    f.status:SetPoint("RIGHT", -12, 0)
    f.status:SetJustifyH("RIGHT")
    f.status:SetWordWrap(false)

    f:HookScript("OnShow", function()
        refreshList()
        refreshThread()
        refreshStatus()
        internal.ViewChanged()
    end)
    f:HookScript("OnHide", function()
        f.reply:ClearFocus()
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
