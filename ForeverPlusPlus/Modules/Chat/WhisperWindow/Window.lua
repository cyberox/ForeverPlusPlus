-- Whisper Window's window, drawn like Error Catcher's: the conversations on the left, newest first,
-- and the one picked on the right, in Blizzard's whisper colors, with a box under it to reply in.
-- It can be dragged and resized, and remembers where. It fades while the player moves or fights
-- (each its own opacity), and comes back while the mouse is over it or the reply box is in use.
-- A button in the column beside the chat window opens it and counts the unread whispers.
local _, ns = ...

local ipairs, format, date, time, pcall, type = ipairs, string.format, date, time, pcall, type
local setmetatable, min, max = setmetatable, math.min, math.max
local CreateFrame, UIParent, GameTooltip, GetTime = CreateFrame, UIParent, GameTooltip, GetTime
local strtrim, GetCursorPosition = strtrim, GetCursorPosition

local L = ns.L
local Frames, Colors = ns.Frames, ns.Colors
local module = ns.modules.WhisperWindow
local internal = module.internal

local WINDOW_NAME = "ForeverPlusPlusWhisperWindow" -- named so Escape closes it
local WIDTH, HEIGHT = 640, 400
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 480, 260, 1200, 900
local LIST_WIDTH = 200
local LIST_MIN, DETAILS_MIN = 140, 270 -- how narrow dragging the divider makes either side
local ROW_HEIGHT = 38
local REPLY_MIN, REPLY_MAX = 24, 66 -- the reply box's height: one line, growing to four
local STRIP = 28 -- the strip under the list and the conversation, for New Whisper and the reply box
local ICON = "Interface\\ChatFrame\\UI-ChatWhisperIcon"

local window, button, watcher
local selected -- the conversation open on the right
local list = {} -- the conversations the list shows

---Whether the window is open.
---@return boolean
function internal.IsShown()
    return window ~= nil and window:IsShown()
end

---Whether the player is reading a conversation now: it's open in the window.
---@param conversation table
---@return boolean
function internal.IsReading(conversation)
    return internal.IsShown() and selected == conversation
end

-- Colors ----------------------------------------------------------------------------------------

-- Blizzard's color for a kind of chat line (ChatTypeInfo), white where it's missing.
local function chatColor(chatType)
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if info and type(info.r) == "number" then
        return info.r, info.g, info.b
    end
    return 1, 1, 1
end

local function lineColor(conversation, kind)
    if kind == "info" then
        return chatColor("SYSTEM")
    elseif conversation.bnet then
        return chatColor(kind == "in" and "BN_WHISPER" or "BN_WHISPER_INFORM")
    end
    return chatColor(kind == "in" and "WHISPER" or "WHISPER_INFORM")
end

local GRAY = "|cff808080"

-- A conversation's name in its class color, when its class is known.
local function coloredName(conversation)
    local color = conversation.class and Colors.ClassToken(conversation.class)
    if color then
        return Colors.Text(color, conversation.display)
    end
    return conversation.display
end

-- Your name as the other side sees it: with your surname (UnitName's second value on Forever, not
-- a realm), in your class color.
local function playerName()
    local name, surname = UnitName("player")
    if not ns.IsText(name, true) then
        return L.WHISPERWINDOW_YOU
    end
    if ns.IsText(surname, true) then
        name = format(L.WHISPERWINDOW_FULL_NAME, name, surname)
    end
    local color = Colors.Class("player")
    return color and Colors.Text(color, name) or name
end

-- The line under the name: level, race, and class, then guild and zone, then friend, guildmate,
-- or offline, as far as the game and Forever++ know (internal.Details).
local function detailsText(conversation)
    local d = internal.Details(conversation)
    local who = {}
    if d.level then
        who[#who + 1] = format(L.WHISPERWINDOW_LEVEL, d.level)
    end
    who[#who + 1] = d.race
    if d.class then
        local color = conversation.class and Colors.ClassToken(conversation.class)
        who[#who + 1] = color and Colors.Text(color, d.class) or d.class
    end
    local parts = {}
    if #who > 0 then
        parts[#parts + 1] = table.concat(who, " ")
    end
    parts[#parts + 1] = d.guildName and format(L.WHISPERWINDOW_GUILD_NAME, d.guildName)
    parts[#parts + 1] = d.character and format(L.WHISPERWINDOW_PLAYING, d.character)
    parts[#parts + 1] = d.zone
    local tags = {}
    tags[#tags + 1] = d.friend and L.WHISPERWINDOW_FRIEND or nil
    tags[#tags + 1] = d.guild and L.WHISPERWINDOW_GUILD or nil
    tags[#tags + 1] = d.online == false and L.WHISPERWINDOW_OFFLINE or nil
    if #tags > 0 then
        parts[#parts + 1] = GRAY .. table.concat(tags, ", ") .. "|r"
    end
    if #parts == 0 then
        return GRAY .. L.WHISPERWINDOW_UNKNOWN .. "|r"
    end
    return table.concat(parts, "  -  ")
end

-- The messages ----------------------------------------------------------------------------------

local function stamp(seconds)
    if date("%Y-%m-%d", seconds) == date("%Y-%m-%d") then
        return date("%H:%M", seconds)
    end
    return date("%m-%d %H:%M", seconds)
end

-- A message as a line in the message frame, in its color, with its time and who said it.
local function messageLine(conversation, message)
    local when = GRAY .. "[" .. stamp(message.time or time()) .. "]|r"
    if message.kind == "info" then
        return format(L.WHISPERWINDOW_INFO_LINE, when, message.text)
    end
    local who = message.kind == "in" and coloredName(conversation) or playerName()
    return format(L.WHISPERWINDOW_LINE, when, who, message.text)
end

local function showMessages()
    local f = window
    f.messages:Clear()
    local conversation = selected
    if not conversation then
        f.name:SetText(L.WHISPERWINDOW_NONE)
        f.details:SetText("")
        f.invite:Hide()
        f.reply:Hide()
        return
    end
    f.details:SetText(detailsText(conversation)) -- first: it may learn the class
    f.name:SetText(coloredName(conversation))
    f.edit.hint:SetText(format(L.WHISPERWINDOW_REPLY_HINT, conversation.display))
    f.edit.hint:SetShown((f.edit:GetText() or "") == "")
    f.invite:SetShown(not conversation.bnet)
    f.reply:Show()
    for _, message in ipairs(conversation.messages) do
        f.messages:AddMessage(messageLine(conversation, message), lineColor(conversation, message.kind))
    end
    f.messages:ScrollToBottom()
end

-- Friends, Battle.net friends, the guild roster, or the group changed: the line under the name
-- again, after a burst.
local refreshDetails = Frames.Coalesce(function()
    if internal.IsShown() and selected then
        window.details:SetText(detailsText(selected))
        window.name:SetText(coloredName(selected))
    end
end, 0.5, module)

local DETAIL_EVENTS = { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE",
    "BN_FRIEND_INFO_CHANGED" }

-- Asks the server for fresh friend and guild info; refreshDetails runs when it comes.
local function askForDetails()
    if C_FriendList and C_FriendList.ShowFriends then
        C_FriendList.ShowFriends()
    end
    ns.Units.RequestGuildRoster()
end

-- The list --------------------------------------------------------------------------------------

local function summary()
    local unread = internal.UnreadTotal()
    local count = #list == 1 and L.WHISPERWINDOW_SUMMARY_ONE or format(L.WHISPERWINDOW_SUMMARY, #list)
    if unread > 0 then
        count = format(L.WHISPERWINDOW_SUMMARY_UNREAD, count, unread)
    end
    window.summary:SetText(count)
end

local function markRows()
    window.scrollBox:ForEachFrame(function(row)
        row.selected:SetShown(row.conversation == selected)
    end)
end

local function refreshList()
    list = internal.Sorted()
    window.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
    markRows()
    summary()
end

-- Opens a conversation on the right, read. `focus` puts the cursor in the reply box.
local drafts = setmetatable({}, { __mode = "k" }) -- conversation -> what's typed in its reply box

local function pick(conversation, focus)
    local edit = window.edit
    if selected then
        drafts[selected] = edit:GetText()
    end
    selected = conversation
    edit:SetText(conversation and drafts[conversation] or "")
    internal.MarkRead(conversation) -- redraws the list when it was unread
    markRows()
    showMessages()
    if conversation and not conversation.bnet then
        askForDetails()
    end
    if focus and conversation then
        window.edit:SetFocus()
    end
end

local function confirmRemove(conversation)
    -- internal.Remove closes it on the right too (internal.Changed sees it's gone).
    ns.Confirm("WHISPERWINDOW_REMOVE", L.WHISPERWINDOW_REMOVE_CONFIRM, function()
        internal.Remove(conversation)
    end, conversation.display)
end

-- The X shows only while the mouse is on its row, in place of the time, so the name keeps its
-- room. Moving onto the X leaves the row, so both ask whether the mouse is still on either.
local function updateHover(row)
    local over = row:IsMouseOver() or row.remove:IsMouseOver()
    row.remove:SetShown(over)
    row.info:SetShown(not over)
end

-- The small X on a row: removes its conversation at once. Probe: Mainline's close button without
-- scripts, the older one elsewhere.
local function newRemoveButton(row)
    local template = Frames.HasTemplate("UIPanelCloseButtonNoScripts") and "UIPanelCloseButtonNoScripts"
        or "UIPanelCloseButton"
    local b = CreateFrame("Button", nil, row, template)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", -2, -1)
    b:Hide()
    b:SetScript("OnClick", function()
        internal.Remove(row.conversation)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.WHISPERWINDOW_REMOVE)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip_Hide()
        updateHover(row)
    end)
    return b
end

-- The right-click menu on a row. Probe: Mainline's menus.
local function rowMenu(row)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    local conversation = row.conversation
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(conversation.display)
        if not conversation.bnet then
            root:CreateButton(L.WHISPERWINDOW_INVITE, function()
                internal.Invite(conversation)
            end)
        end
        root:CreateButton(L.WHISPERWINDOW_REMOVE, function()
            confirmRemove(conversation)
        end)
    end)
end

-- A right-click on a player's name in the messages opens Blizzard's unit menu, run from our click:
-- its Trade, Duel, and Follow lines ask how far the player is (UnitPopupSharedUtil.IsEnabled calls
-- CheckInteractDistance), which only Blizzard's own code may ask in combat, so the game blocks it
-- (the CheckInteractDistance block reported on 1.4.0; the cause is read from Blizzard's source and
-- Unverified in game). In combat the name gets this short menu of our own instead; out of combat
-- it's Blizzard's, as before. True when it showed one. Probe: Mainline's menus.
local function playerMenu(owner, link)
    if not (MenuUtil and MenuUtil.CreateContextMenu and ns.IsText(link)) then
        return false
    end
    local kind, name = strsplit(":", link)
    if kind ~= "player" or not name or name == "" then
        return false
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton(L.WHISPERWINDOW_INVITE, function()
            internal.Invite({ name = name })
        end)
        root:CreateButton(L.WHISPERWINDOW_MENU_COMBAT):SetEnabled(false)
    end)
    return true
end

local function buildRow(row)
    row.selected = Frames.RowTexture(row, "BACKGROUND", "Options_List_Active", 1, 0.82, 0, 0.15)
    row:SetHighlightTexture(Frames.RowTexture(row, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.08))
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", 8, -6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.remove = newRemoveButton(row)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPRIGHT", -6, -6)
    row.name:SetPoint("RIGHT", row.info, "LEFT", -4, 0)
    row:SetScript("OnEnter", updateHover)
    row:SetScript("OnLeave", updateHover)
    row.preview = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.preview:SetPoint("BOTTOMLEFT", 8, 6)
    row.preview:SetPoint("BOTTOMRIGHT", -6, 6)
    row.preview:SetJustifyH("LEFT")
    row.preview:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            rowMenu(self)
        else
            pick(self.conversation, true)
        end
    end)
end

local function initRow(row, conversation)
    if not row.name then
        buildRow(row)
    end
    row.conversation = conversation
    row.name:SetText(coloredName(conversation))
    local unread = conversation.unread or 0
    if unread > 0 then
        row.info:SetFontObject("GameFontGreenSmall")
        row.info:SetText(format(L.WHISPERWINDOW_UNREAD, unread))
    else
        row.info:SetFontObject("GameFontDisableSmall")
        row.info:SetText(ns.Text.Ago(time() - (conversation.last or time())))
    end
    local last = conversation.messages[#conversation.messages]
    local preview = last and ns.Text.Plain(last.text) or ""
    if last and last.kind == "out" then
        preview = format(L.WHISPERWINDOW_PREVIEW_YOU, preview)
    end
    row.preview:SetText(preview)
    row.selected:SetShown(conversation == selected)
    updateHover(row) -- a recycled row may still show the X
end

-- Opacity ---------------------------------------------------------------------------------------

local shownAlpha

-- The opacity for what the player is doing; full while the mouse is over it or they type in it.
local function updateAlpha()
    local db = module.db
    local alpha = db.alpha
    if not (window:IsMouseOver() or window.edit:HasFocus()) then
        local activity = Frames.PlayerActivity()
        if activity == "combat" then
            alpha = db.combatAlpha
        elseif activity == "moving" then
            alpha = db.movingAlpha
        end
    end
    if alpha ~= shownAlpha then
        shownAlpha = alpha
        window:SetAlpha(alpha / 100)
    end
end

-- Linking items ---------------------------------------------------------------------------------
-- Shift-clicking an item puts its link in the chat's edit box; while the reply box is in use it
-- goes there instead. Blizzard's code finds no chat box open and does nothing, then this runs.

local lastLink, lastLinkTime

local function insertLink(link)
    if not (window and window:IsShown() and window.edit:HasFocus() and ns.IsText(link, true)) then
        return
    end
    -- Both hooks may run for one click, when one calls the other.
    local now = GetTime()
    if link == lastLink and now == lastLinkTime then
        return
    end
    lastLink, lastLinkTime = link, now
    window.edit:Insert(link)
end

-- The window ------------------------------------------------------------------------------------

local function savePlace()
    -- Saved here, not in the game's layout cache, which a moved named frame would go into.
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
        window:SetPoint(layout.point, UIParent, layout.relativePoint or layout.point, layout.x or 0,
            layout.y or 0)
    else
        window:SetPoint("CENTER")
    end
    local width = layout.width and max(MIN_WIDTH, min(MAX_WIDTH, layout.width)) or WIDTH
    local height = layout.height and max(MIN_HEIGHT, min(MAX_HEIGHT, layout.height)) or HEIGHT
    window:SetSize(width, height)
end

-- The list at the width the player dragged it to, as far as the window's own width leaves room
-- for the conversation beside it. A narrower window shows it narrower without forgetting it.
local function sizeList()
    local width = module.db.layout.listWidth or LIST_WIDTH
    window.listInset:SetWidth(max(LIST_MIN, min(width, window:GetWidth() - DETAILS_MIN)))
end

-- The divider between the list and the conversation: dragged sideways, it sets the list's width.
-- It's the gap between the two boxes, gold under the mouse, with the game's resize cursor.
local function newDivider(f, listInset)
    local divider = CreateFrame("Button", nil, f)
    divider:SetWidth(8)
    divider:SetPoint("TOPLEFT", listInset, "TOPRIGHT", -3, 0)
    divider:SetPoint("BOTTOMLEFT", listInset, "BOTTOMRIGHT", -3, 0)
    divider:SetFrameLevel(listInset:GetFrameLevel() + 10)
    local line = divider:CreateTexture(nil, "HIGHLIGHT")
    line:SetColorTexture(1, 0.82, 0, 0.6)
    line:SetWidth(2)
    line:SetPoint("TOP", 0, -2)
    line:SetPoint("BOTTOM", 0, 2)

    local dragging
    local function drag()
        local x = GetCursorPosition() / f:GetEffectiveScale()
        module.db.layout.listWidth = max(LIST_MIN, min(x - f:GetLeft() - 5, f:GetWidth() - DETAILS_MIN))
        sizeList()
    end
    divider:SetScript("OnEnter", function()
        SetCursor("UI_RESIZE_CURSOR")
    end)
    divider:SetScript("OnLeave", function()
        if not dragging then
            ResetCursor()
        end
    end)
    divider:SetScript("OnMouseDown", function(self)
        dragging = true
        line:SetDrawLayer("OVERLAY") -- stays lit while the mouse runs ahead of it
        self:SetScript("OnUpdate", drag)
    end)
    local function stop(self)
        if dragging then
            dragging = false
            line:SetDrawLayer("HIGHLIGHT")
            self:SetScript("OnUpdate", nil)
            ResetCursor()
        end
    end
    divider:SetScript("OnMouseUp", stop)
    divider:SetScript("OnHide", stop)
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

-- What you sent this session, newest last, for Up and Down in the reply box like the chat's.
local sent = {}
local MAX_SENT = 30
local sentIndex -- the one shown, while stepping through them

-- A multi-line box may put Enter's line break in before or after OnEnterPressed. A whisper has no
-- line breaks, so they go as spaces (pasted ones too), and one put in after is cleared next frame.
local function clearBreak(edit)
    C_Timer.After(0, function()
        if edit:GetText() == "\n" then
            edit:SetText("")
        end
    end)
end

local function send(edit)
    local text = strtrim(((edit:GetText() or ""):gsub("%s*\n%s*", " ")))
    if text == "" or not selected then
        edit:SetText(text)
        clearBreak(edit)
        edit:ClearFocus()
        return
    end
    if internal.Send(selected, text) then
        if sent[#sent] ~= text then
            sent[#sent + 1] = text
            if #sent > MAX_SENT then
                table.remove(sent, 1)
            end
        end
        sentIndex = nil
        edit:SetText("")
        clearBreak(edit)
    else
        edit:SetText(text)
    end
end

-- Up and Down step through what was sent only from an empty box, or one still showing what they
-- brought back: in anything else they move the cursor between its lines.
local function stepSent(edit, key)
    if #sent == 0 or (key ~= "UP" and key ~= "DOWN") then
        return
    end
    local text = edit:GetText() or ""
    if not (text == "" or (sentIndex and text == sent[sentIndex])) then
        sentIndex = nil
        return
    end
    if text == "" then
        sentIndex = nil
    end
    if key == "UP" then
        sentIndex = math.max(1, (sentIndex or #sent + 1) - 1)
    elseif sentIndex then
        sentIndex = sentIndex + 1
        if sentIndex > #sent then
            sentIndex = nil
            edit:SetText("")
            return
        end
    else
        return
    end
    edit:SetText(sent[sentIndex])
    edit:SetCursorPosition(#sent[sentIndex])
end

-- The reply box under the conversation: a line high, growing to four as it fills, then scrolling,
-- so a long whisper can be read while it's typed. `onResize` runs when its height changes.
local function newReply(f, onResize)
    local box = Frames.Inset(f)
    box:SetHeight(REPLY_MIN)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -5)
    scroll:SetPoint("BOTTOMRIGHT", -8, 5)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    -- Longer than one whisper is fine: internal.Send splits it.
    edit:SetMaxLetters(internal.MAX_TEXT)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetHeight(REPLY_MIN - 10) -- a multi-line box grows from here as it fills
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width)
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

    -- The gray "Whisper Bob" (set by showMessages), only while the box is empty.
    edit.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    edit.hint:SetPoint("LEFT", 10, 0)
    edit.hint:SetPoint("RIGHT", -10, 0)
    edit.hint:SetJustifyH("LEFT")
    edit.hint:SetWordWrap(false)

    -- The box at the height its text needs, scrolled no further than keeps the cursor in view.
    -- The cursor moves to a new line before the box has grown for it, so both the text and the
    -- cursor changing come here: scrolling for the cursor alone, in the box's old height, pushed
    -- the first line out of a box that then had room for it.
    local shownHeight = REPLY_MIN
    local cursorTop, cursorHeight = 0, 0
    local function fit()
        local empty = (edit:GetText() or "") == ""
        edit.hint:SetShown(empty)
        local height = empty and REPLY_MIN or min(REPLY_MAX, max(REPLY_MIN, edit:GetHeight() + 10))
        if height ~= shownHeight then
            shownHeight = height
            box:SetHeight(height)
            onResize(height)
        end
        local shown = height - 10 -- the scroll frame's height, once the box has this one
        local most = empty and 0 or max(0, edit:GetHeight() - shown)
        local top = min(most, scroll:GetVerticalScroll())
        if cursorTop < top then
            top = cursorTop
        elseif cursorTop + cursorHeight > top + shown then
            top = cursorTop + cursorHeight - shown
        end
        scroll:SetVerticalScroll(max(0, min(most, top)))
    end
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        cursorTop, cursorHeight = -y, height
        fit()
    end)
    edit:SetScript("OnTextChanged", fit)
    edit:SetScript("OnEnterPressed", send)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnArrowPressed", stepSent)
    return box, edit
end

local function newMessages(parent)
    local messages = CreateFrame("ScrollingMessageFrame", nil, parent)
    messages:SetFontObject(ChatFontNormal)
    messages:SetJustifyH("LEFT")
    messages:SetFading(false)
    messages:SetMaxLines(internal.MAX_MESSAGES + 20)
    messages:SetHyperlinksEnabled(true)
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    messages:SetScript("OnHyperlinkClick", function(self, link, text, mouse)
        if mouse == "RightButton" and InCombatLockdown() and playerMenu(self, link) then
            return
        end
        if SetItemRef then
            SetItemRef(link, text, mouse, self)
        end
    end)
    messages:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    messages:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
    return messages
end

local function newWindow()
    local f = Frames.PortraitWindow(WINDOW_NAME, L.WHISPERWINDOW_WINDOW_TITLE)
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

    -- The conversations, on the left.
    local listInset = Frames.Inset(f)
    listInset:SetPoint("TOPLEFT", 4, -60)
    listInset:SetPoint("BOTTOMLEFT", 4, STRIP)
    f.listInset = listInset
    newDivider(f, listInset)
    f:HookScript("OnSizeChanged", sizeList)

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

    -- The conversation, on the right.
    local details = f.Inset or Frames.Inset(f)
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 2, 0)
    details:SetPoint("BOTTOMRIGHT", -6, STRIP)

    f.invite = ns.Frames.Button(details, L.WHISPERWINDOW_INVITE, 110, function()
        if selected then
            internal.Invite(selected)
        end
    end)
    f.invite:SetPoint("TOPRIGHT", -8, -6)
    f.name = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("TOPLEFT", 12, -10)
    f.name:SetPoint("RIGHT", f.invite, "LEFT", -8, 0)
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

    f.messages = newMessages(details)
    f.messages:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 4, -4)
    f.messages:SetPoint("BOTTOMRIGHT", -10, 6)

    -- The strip at the bottom: New Whisper under the list, the reply box under the conversation.
    f.new = ns.Frames.Button(f, L.WHISPERWINDOW_NEW, 130, function()
        ns.PromptName("WHISPERWINDOW_NEW", L.WHISPERWINDOW_NEW_PROMPT, "", function(name)
            internal.Open(internal.Start(name), true)
        end)
    end)
    f.new:SetPoint("BOTTOMLEFT", 4, 4)

    -- The reply box hangs under the conversation, which gives up the room it grows by. Short of
    -- the corner, for the resize grip.
    f.reply, f.edit = newReply(f, function(height)
        details:SetPoint("BOTTOMRIGHT", -6, STRIP + height - REPLY_MIN)
    end)
    f.reply:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -1)
    f.reply:SetPoint("TOPRIGHT", details, "BOTTOMRIGHT", -16, -1)

    f:HookScript("OnShow", function()
        shownAlpha = nil
        watcher:Show()
    end)
    f:HookScript("OnHide", function()
        watcher:Hide()
        f.edit:ClearFocus()
    end)
    place()
    sizeList()
    f:Hide()
    return f
end

local function ensureWindow()
    if not window then
        local ticked = GetTime()
        watcher = Frames.Watcher(module, 0.1, function()
            updateAlpha()
            -- The list's "5m ago" times move on.
            if GetTime() - ticked >= 30 then
                ticked = GetTime()
                refreshList()
            end
        end)
        newWindow()
    end
end

-- The conversation to open with nothing asked for: one with unread whispers, or the latest.
local function firstToOpen()
    local sorted = internal.Sorted()
    for _, conversation in ipairs(sorted) do
        if (conversation.unread or 0) > 0 then
            return conversation
        end
    end
    return sorted[1]
end

---Opens the window on a conversation (or the one waiting most, without one).
---@param conversation? table
---@param focus? boolean put the cursor in the reply box
function internal.Open(conversation, focus)
    ensureWindow()
    window:Show()
    refreshList()
    pick(conversation or (selected and internal.Conversations()[selected.key] == selected and selected)
        or firstToOpen(), focus)
end

---Opens or closes the window.
function internal.Toggle()
    if internal.IsShown() then
        window:Hide()
    else
        internal.Open()
    end
end

-- The chat button ---------------------------------------------------------------------------------

local function updateButton()
    if not button then
        return
    end
    local unread = internal.UnreadTotal()
    button.count:SetText(unread > 0 and unread or "")
    -- On the chat menu button too, while a short chat window has put this one in its menu.
    ns.Chat.SetBadge(module.name, unread)
    -- It pulses while whispers wait, like Blizzard's chat tabs with new messages.
    if unread > 0 then
        button.glow:Show()
        if not button.pulse:IsPlaying() then
            button.pulse:Play()
        end
    else
        button.pulse:Stop()
        button.glow:Hide()
    end
end

local function showButton()
    local on = module.enabled and module.db.chatButton and ns.Chat.Anchor() ~= nil
    if on then
        if not button then
            button = ns.Chat.NewButton(ICON, internal.Toggle, L.WHISPERWINDOW_TOOLTIP,
                L.WHISPERWINDOW_TOOLTIP_DESC)
            -- In Blizzard's gold, as its own chat buttons' icons are.
            local gold = NORMAL_FONT_COLOR
            if gold then
                button.icon:SetVertexColor(gold.r, gold.g, gold.b)
            else
                button.icon:SetVertexColor(1, 0.82, 0)
            end
            -- The whispers waiting, at the corner like the minimap button's error count.
            button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            button.count:SetPoint("BOTTOMRIGHT", 0, 0)
            -- The button's own highlight, glowing in and out while whispers wait.
            local glow = button:CreateTexture(nil, "OVERLAY")
            glow:SetAllPoints()
            glow:SetAtlas("chatframe-button-highlight")
            glow:SetBlendMode("ADD")
            glow:Hide()
            local pulse = glow:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.1)
            fade:SetToAlpha(1)
            fade:SetDuration(0.8)
            fade:SetSmoothing("IN_OUT")
            button.glow, button.pulse = glow, pulse
        end
        button:Show()
        -- Before Chat Copy's (20), so on a short chat window whispers keep their button and
        -- copying is the one that goes in the chat menu.
        ns.Chat.AddButton(module.name, button, 15)
        updateButton()
    elseif button then
        ns.Chat.RemoveButton(module.name)
        button:Hide()
    end
end

---Something in a conversation changed (nil: the list itself), so what shows it redraws.
---@param conversation? table
function internal.Changed(conversation)
    updateButton()
    if not internal.IsShown() then
        return
    end
    -- The open conversation was removed (or cleared, from Settings): close it on the right.
    if selected and internal.Conversations()[selected.key] ~= selected then
        selected = nil
        showMessages()
    end
    refreshList()
    if conversation and conversation == selected then
        showMessages()
    end
end

function internal.EnableWindow()
    showButton()
    for _, event in ipairs(DETAIL_EVENTS) do
        if ns.HasEvent(event) then
            module:On(event, refreshDetails)
        end
    end
    module:Hook("ChatEdit_InsertLink", insertLink)
    if ChatFrameUtil then
        module:Hook(ChatFrameUtil, "InsertLink", insertLink)
    end
end

function internal.DisableWindow()
    showButton()
    if window then
        window:Hide()
    end
end

function internal.OptionChanged(key)
    if key == "chatButton" then
        showButton()
    elseif window and window:IsShown() then
        shownAlpha = nil
        updateAlpha()
    end
end
