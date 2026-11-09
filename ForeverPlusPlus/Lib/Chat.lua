-- Chat helpers the Chat modules share: the chat windows, rewriting their lines, chat lines in their
-- colors for an edit box, filters that hide lines, and the column of small buttons beside the main
-- chat window (Blizzard's menu and channel buttons, then ours).
local _, ns = ...

local _G, ipairs, type, tonumber, gsub, format = _G, ipairs, type, tonumber, string.gsub, string.format
local select = select
local setmetatable, CreateFrame, UIParent = setmetatable, CreateFrame, UIParent
local byte, find, match, sub = string.byte, string.find, string.match, string.sub
local min, concat = math.min, table.concat

local Chat = {}
ns.Chat = Chat

---The chat windows that exist, in order: the numbered ones (ChatFrame1 to 10), then the
---temporary ones Blizzard makes for a whisper popped out into its own tab (ChatFrame11 and up,
---listed in CHAT_FRAMES), unless `numbered`.
---@param numbered? boolean only the numbered windows
---@return table[]
function Chat.Frames(numbered)
    local frames, seen = {}, {}
    local function add(frame)
        if type(frame) == "table" and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        add(_G["ChatFrame" .. i])
    end
    if not numbered and type(CHAT_FRAMES) == "table" then
        for _, name in ipairs(CHAT_FRAMES) do
            add(_G[name])
        end
    end
    return frames
end

local eachWindow = setmetatable({}, { __mode = "k" }) -- module -> its fn for Chat.EachWindow

---Calls `fn` with each chat window now, and again whenever windows are added or reset, while the
---module is on. Call it from `OnEnable`, once: a second call replaces the module's `fn`.
---@param module table
---@param fn fun(frame: table)
function Chat.EachWindow(module, fn)
    local function all()
        for _, frame in ipairs(Chat.Frames()) do
            fn(frame)
        end
    end
    all()
    module:On("UPDATE_CHAT_WINDOWS", all)
    module:On("UPDATE_FLOATING_CHAT_WINDOWS", all)
    -- A temporary window comes with no chat window event. The hook can't be handed the window it
    -- made, so every window gets `fn` again. Hooked once per module, running its latest `fn`.
    local hooked = eachWindow[module] ~= nil
    eachWindow[module] = fn
    if not hooked then
        module:Hook("FCF_OpenTemporaryWindow", function()
            local current = eachWindow[module]
            for _, frame in ipairs(Chat.Frames()) do
                current(frame)
            end
        end)
    end
end

---Rewrites the lines a chat window already shows: each readable line `test` accepts becomes
---`rewrite(line)`, keeping its color and links. Does nothing on a client without TransformMessages.
---Each rewritten line counts as new, so one that had faded out shows again until it fades; there's
---no way to keep its time. Rewrite only when the change needs it.
---@param frame table
---@param test fun(line: string): boolean
---@param rewrite fun(line: string): string
function Chat.Transform(frame, test, rewrite)
    if not frame.TransformMessages then
        return
    end
    frame:TransformMessages(function(message)
        return ns.IsText(message) and test(message)
    end, function(message, ...)
        return rewrite(message), ...
    end)
end

---A pattern that finds a chat timestamp at the start of a line, for one of Blizzard's chat
---timestamp formats ("%I:%M ", "[%H:%M:%S] ", "%I:%M %p "). Its numbers can be any digits, so it
---finds the stamp of a line from any time.
---@param stampFormat string a `date` format, as the chat timestamp setting holds it
---@return string
function Chat.TimestampPattern(stampFormat)
    local pieces, i = { "^" }, 1
    while i <= #stampFormat do
        local c = sub(stampFormat, i, i)
        local spec = c == "%" and sub(stampFormat, i + 1, i + 1) or ""
        if spec == "p" then
            -- AM or PM in the player's language.
            pieces[#pieces + 1] = "[^%s%d]+"
            i = i + 2
        elseif spec == "%" then
            pieces[#pieces + 1] = "%%"
            i = i + 2
        elseif spec ~= "" then
            pieces[#pieces + 1] = "%d+"
            i = i + 2
        else
            pieces[#pieces + 1] = find(c, "[%^%$%(%)%%%.%[%]%*%+%-%?]") and "%" .. c or c
            i = i + 1
        end
    end
    return concat(pieces)
end

---The chat timestamp format the player picked in Blizzard's chat settings, or nil while
---timestamps are off.
---@return string?
function Chat.TimestampFormat()
    local util, stampFormat = _G.ChatFrameUtil, nil
    if util and util.GetTimestampFormat then
        stampFormat = util.GetTimestampFormat()
    else
        stampFormat = _G.CHAT_TIMESTAMP_FORMAT
    end
    if type(stampFormat) == "string" and stampFormat ~= "" then
        return stampFormat
    end
end

---The timestamp Blizzard puts in front of a chat line from an event, for the time now, or "" while
---timestamps are off. Blizzard's own is plain text in the line's color, made with BetterDate,
---so this is too. print() and AddMessage don't stamp a line by themselves.
---@return string
function Chat.Stamp()
    local stampFormat = Chat.TimestampFormat()
    if not stampFormat then
        return ""
    end
    local util = _G.TimeUtil
    local betterDate = util and util.BetterDate or _G.BetterDate
    if betterDate then
        return betterDate(stampFormat, _G.time())
    end
    return _G.date(stampFormat, _G.time())
end

-- Colored lines -----------------------------------------------------------------------------------
-- A chat line as an edit box can show it in its chat colors: the line's color around it, its own
-- color codes (names, links) kept, and links, textures, and atlases gone. Copying from an edit box
-- copies its raw text, codes and all, so Chat.Uncolor and the offsets below turn colored text and
-- positions in it into plain ones.

local PIPE, LOWER_C, LOWER_R = 124, 99, 114

local hexCode = ns.Colors.Code

---A named color (|cnIQ4: for an item's quality, |cnNAME: for a color global) as a plain color
---code, which edit boxes show; nil when the name isn't known.
---@param name string
---@return string?
local function namedCode(name)
    local quality = tonumber(match(name, "^IQ(%d+)$"))
    local color
    if quality then
        color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    else
        color = _G[name]
    end
    if type(color) ~= "table" then
        return nil
    end
    local r, g, b = color.r, color.g, color.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return hexCode(r, g, b)
    end
end

---A chat line in its chat colors, for an edit box. Nothing here may be given a secret value.
---@param text string
---@param r number?
---@param g number?
---@param b number?
---@return string
function Chat.Colored(text, r, g, b)
    text = gsub(text, "|H[^|]*|h(.-)|h", "%1")
    text = gsub(text, "|T[^|]*|t", "")
    text = gsub(text, "|A[^|]*|a", "")
    -- Item links color their names with |cnIQ1: and the like.
    text = gsub(text, "(|+)cn([^:|]*):", function(pipes, name)
        local code = #pipes % 2 == 1 and namedCode(name)
        if code then
            return sub(pipes, 2) .. code
        end
    end)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return text
    end
    local color = hexCode(r, g, b)
    -- An edit box keeps the first color until a |r and ignores a color code inside it, so the
    -- line's color ends before each color of its own (a name, a link) and comes back after it.
    -- An even run of pipes before the letter is escaped pipes, not a code.
    text = gsub(text, "(|+)([cr])", function(pipes, letter)
        if #pipes % 2 == 1 then
            local escaped = sub(pipes, 2)
            if letter == "r" then
                return escaped .. "|r" .. color
            end
            return escaped .. "|r|c"
        end
    end)
    return color .. text .. "|r"
end

---The length of the color code at byte i, or nil when there isn't one.
---@param text string
---@param i number
---@return number?
local function codeLength(text, i)
    if byte(text, i) ~= PIPE then
        return nil
    end
    local nextByte = byte(text, i + 1)
    if nextByte == LOWER_R then
        return 2
    elseif nextByte == LOWER_C then
        local _, last = find(text, "^|c%x%x%x%x%x%x%x%x", i)
        if not last then
            _, last = find(text, "^|cn[^:|]*:", i)
        end
        return last and last - i + 1
    end
end

---Walks colored text: a color code shows nothing and "||" shows one "|". Stops after `rawStop`
---bytes of it or once `shownStop` bytes show, and returns the bytes walked and the bytes shown.
---@param text string
---@param rawStop number?
---@param shownStop number?
---@param pieces table? gets the shown text
---@return number raw
---@return number shown
local function walk(text, rawStop, shownStop, pieces)
    local length = #text
    local i, shown = 1, 0
    while i <= length and not (rawStop and i > rawStop) and not (shownStop and shown >= shownStop) do
        local pipe = find(text, "|", i, true) or length + 1
        if pipe > i then
            local run = pipe - i
            if rawStop then
                run = min(run, rawStop - i + 1)
            end
            if shownStop then
                run = min(run, shownStop - shown)
            end
            if pieces then
                pieces[#pieces + 1] = sub(text, i, i + run - 1)
            end
            i, shown = i + run, shown + run
        else
            local code = codeLength(text, i)
            if code then
                i = i + code
            else
                if pieces then
                    pieces[#pieces + 1] = "|"
                end
                i, shown = i + (byte(text, i + 1) == PIPE and 2 or 1), shown + 1
            end
        end
    end
    return i - 1, shown
end

---Colored text as the plain text it shows.
---@param text string
---@return string
function Chat.Uncolor(text)
    local pieces = {}
    walk(text, nil, nil, pieces)
    return concat(pieces)
end

---Where a position in colored text falls in its plain text (both count bytes before it).
---@param text string colored text
---@param offset number
---@return number
function Chat.PlainOffset(text, offset)
    local _, shown = walk(text, offset)
    return shown
end

---Where a position in plain text falls in its colored text, before any codes there.
---@param text string colored text
---@param offset number
---@return number
function Chat.ColoredOffset(text, offset)
    return (walk(text, nil, offset))
end

-- Message filters --------------------------------------------------------------------------------
-- A filter decides, for each chat window, whether a chat event's line shows there: it returns
-- true to hide it. Probe: ChatFrameUtil's on Mainline, the older global on other clients.

local function filterApi(utilName, globalName)
    local util = _G.ChatFrameUtil
    if type(util) == "table" and type(util[utilName]) == "function" then
        return util[utilName]
    end
    local legacy = _G[globalName]
    if type(legacy) == "function" then
        return legacy
    end
end

---Hides chat lines of `event` for which `fn(frame, event, ...)` returns true, in every chat
---window. Adding the same `fn` twice changes nothing. Returns false on a client without filters.
---@param event string such as "CHAT_MSG_WHISPER"
---@param fn function
---@return boolean
function Chat.AddFilter(event, fn)
    local add = filterApi("AddMessageEventFilter", "ChatFrame_AddMessageEventFilter")
    if not add then
        return false
    end
    add(event, fn)
    return true
end

---Takes away a filter added with Chat.AddFilter.
---@param event string
---@param fn function
function Chat.RemoveFilter(event, fn)
    local remove = filterApi("RemoveMessageEventFilter", "ChatFrame_RemoveMessageEventFilter")
    if remove then
        remove(event, fn)
    end
end

-- The button column ----------------------------------------------------------------------------
-- Each module that adds a button gives it a key and an order; they stack under Blizzard's own
-- buttons, lowest order first, so two modules never put theirs in the same spot.

local column = {} -- { key, button, order, label }, sorted by order
local laying
local ours = setmetatable({}, { __mode = "k" }) -- the buttons Chat.NewButton made, to their label
-- The buttons that don't fit above Blizzard's chat menu button (a short chat window, issue #2):
-- hidden, with an entry in that button's menu instead, by key.
local folded = {}

-- The frame holding Blizzard's chat buttons, which ours join so they show and fade with them. Read
-- from the buttons each time, since another addon (Leatrix Plus' Hide chat buttons) can move them
-- out of the chat window's button frame.
local function host()
    local anchor = Chat.Anchor()
    local parent = anchor and anchor:GetParent()
    if parent then
        return parent
    end
    local frame = _G.ChatFrame1
    return frame and (frame.buttonFrame or frame.ButtonFrame) or UIParent
end

---A small button in the art of Blizzard's chat menu and channel buttons, with an icon on it, for
---the column (Chat.AddButton). It sits in the frame that holds them, so it fades with them.
---@param texture string the icon's texture path
---@param onClick function
---@param title string the tooltip's first line
---@param text string the tooltip's description
---@return table button with `.icon`
function Chat.NewButton(texture, onClick, title, text)
    local b = CreateFrame("Button", nil, host())
    ours[b] = format("|T%s:16:16|t %s", texture, title)
    local template = Chat.Anchor()
    b:SetSize(template and template:GetWidth() or 32, template and template:GetHeight() or 32)
    b:SetNormalAtlas("chatframe-button-up")
    b:SetPushedAtlas("chatframe-button-down")
    b:SetHighlightAtlas("chatframe-button-highlight")
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(texture)
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    b.icon = icon
    b:SetScript("OnMouseDown", function()
        icon:SetPoint("CENTER", 1, -1)
    end)
    b:SetScript("OnMouseUp", function()
        icon:SetPoint("CENTER", 0, 0)
    end)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

---The last of Blizzard's own chat buttons, which ours go under.
---@return table?
function Chat.Anchor()
    return _G.ChatFrameChannelButton or _G.ChatFrameMenuButton
end

---Whether Blizzard's chat buttons can't be seen, so ours can't either: most likely another chat
---addon hid them or put its own chat in place of Blizzard's (issue #2). Also true for a moment
---while the chat window itself is hidden.
---@return boolean
function Chat.ButtonsHidden()
    local anchor = Chat.Anchor()
    return not (anchor and anchor:IsVisible())
end

---Whether the button `key` added is in the chat menu button's menu, since the chat window is too
---short for it in the column.
---@param key string
---@return boolean
function Chat.Folded(key)
    return folded[key] ~= nil
end

---The notices for a module with a button in the column: a gray row while Blizzard's chat buttons are
---hidden, saying what still works without the button, and one while the chat window is too short
---for it, saying where it went.
---@param key string the key its button was added with (the module's name)
---@param text string
---@param description string
---@param shown? function only while this is true as well (the button's option is on). Settings calls
---a notice's `shown` with nothing, so it reads the module's settings itself (issue #5).
---@return table notices for `module.notice`
function Chat.HiddenNotice(key, text, description, shown)
    return {
        {
            text = text, description = description,
            shown = function()
                return (not shown or shown()) and Chat.ButtonsHidden()
            end,
        },
        {
            text = ns.L.CHAT_BUTTON_FOLDED, description = ns.L.CHAT_BUTTON_FOLDED_DESC,
            shown = function()
                return (not shown or shown()) and not Chat.ButtonsHidden() and Chat.Folded(key)
            end,
        },
    }
end

-- Blizzard's voice Deafen and Mute buttons sit under the channel button while in a voice channel
-- (FloatingChatFrameVoiceChat.xml), so the column starts below them then, and moves when they
-- show or hide.
local voiceHooked
local function top()
    local mute, deafen = _G.ChatFrameToggleVoiceMuteButton, _G.ChatFrameToggleVoiceDeafenButton
    if not voiceHooked then
        voiceHooked = true
        for _, button in ipairs({ deafen or false, mute or false }) do
            if button and button.HookScript then
                button:HookScript("OnShow", Chat.Layout)
                button:HookScript("OnHide", Chat.Layout)
            end
        end
    end
    if mute and mute:IsShown() then
        return mute
    elseif deafen and deafen:IsShown() then
        return deafen
    end
    return Chat.Anchor()
end

-- How low the column can reach, in screen pixels: the top of Blizzard's chat menu button (the
-- speech bubble), which sits at the bottom of the button frame (FloatingChatFrame.xml), so a short
-- chat window put our buttons under it (issue #2). Nil when it isn't under the column: hidden, or
-- moved by another addon.
local function lowest(above)
    local menu = _G.ChatFrameMenuButton
    if not (menu and menu:IsShown()) then
        return nil
    end
    local menuTop, menuLeft, menuRight = menu:GetTop(), menu:GetLeft(), menu:GetRight()
    local aboveBottom, aboveLeft, aboveRight = above:GetBottom(), above:GetLeft(), above:GetRight()
    if not (menuTop and menuLeft and menuRight and aboveBottom and aboveLeft and aboveRight) then
        return nil
    end
    local scale, aboveScale = menu:GetEffectiveScale(), above:GetEffectiveScale()
    menuTop = menuTop * scale
    if menuTop > aboveBottom * aboveScale or menuLeft * scale >= aboveRight * aboveScale
        or menuRight * scale <= aboveLeft * aboveScale then
        return nil
    end
    return menuTop
end

local function show(button, shown)
    button:SetAlpha(shown and 1 or 0)
    button:EnableMouse(shown)
end

-- The chat window's size and the menu button change what fits, so the column is laid out again
-- then, and once more on the next frame, when every button's place has caught up with the new
-- size. Hooked once for each frame, since a hook can't be taken off.
local again
local function layoutAgain()
    again = nil
    Chat.Layout()
end
local function onResize()
    Chat.Layout()
    if not again and C_Timer then
        again = true
        C_Timer.After(0, layoutAgain)
    end
end
local watched = setmetatable({}, { __mode = "k" })
local function watch(frame, ...)
    if frame and not watched[frame] and frame.HookScript then
        watched[frame] = true
        for i = 1, select("#", ...) do
            frame:HookScript((select(i, ...)), onResize)
        end
    end
end

-- The folded buttons at the end of Blizzard's chat menu, after a line, in the column's order.
local function addFolded(_, root)
    local any = false
    for _, entry in ipairs(column) do
        if folded[entry.key] then
            if not any then
                any = true
                root:CreateDivider()
            end
            local button = entry.button
            root:CreateButton(entry.label or entry.key, function()
                button:Click()
            end)
        end
    end
end

local menuAdded
local function addToMenu()
    -- Probe: Menu.ModifyMenu and the menu's tag are Mainline's (ChatFrameMenuButton.lua).
    if not menuAdded and Menu and Menu.ModifyMenu then
        menuAdded = true
        Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", addFolded)
    end
end

---Puts the buttons in the column back in place. Modules call it again when something moves one.
---Those that don't fit above the chat menu button are hidden and listed in its menu instead.
function Chat.Layout()
    if not column[1] then
        return
    end
    local previous = top()
    if not previous then
        return
    end
    laying = true
    local parent = host()
    watch(parent, "OnSizeChanged")
    watch(_G.ChatFrameMenuButton, "OnShow", "OnHide")
    local bottom = lowest(previous)
    local y = bottom and previous:GetBottom() * previous:GetEffectiveScale()
    for _, entry in ipairs(column) do
        local button = entry.button
        -- Ours follow Blizzard's buttons if an addon moved them; Social Button moves its own.
        if ours[button] and button:GetParent() ~= parent then
            button:SetParent(parent)
        end
        button:ClearAllPoints()
        button:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        previous = button
        local fits = true
        if y then
            -- Where it really is now, read back; where it should be when that isn't known yet.
            local scale = button:GetEffectiveScale()
            y = y - (2 + button:GetHeight()) * scale
            local real = button:GetBottom()
            fits = (real and real * scale or y) >= bottom
        end
        if not fits and not folded[entry.key] then
            folded[entry.key] = button
            show(button, false)
            addToMenu()
        elseif fits and folded[entry.key] then
            folded[entry.key] = nil
            show(button, true)
        end
    end
    laying = false
end

---Whether the column is being laid out right now, so a hook on SetPoint can ignore our own moves.
---@return boolean
function Chat.IsLaying()
    return laying == true
end

---Adds a button to the column (or moves it, when the key is already there).
---@param key string the module's name
---@param button table
---@param order number
---@param label? string its line in the chat menu while it doesn't fit (Chat.NewButton's has one)
function Chat.AddButton(key, button, order, label)
    Chat.RemoveButton(key, true)
    column[#column + 1] = { key = key, button = button, order = order, label = label or ours[button] }
    table.sort(column, function(a, b)
        return a.order < b.order
    end)
    Chat.Layout()
end

---Takes a button out of the column. It stays where it is; the caller puts it back or hides it.
---@param key string
---@param quiet? boolean skip laying out the rest
function Chat.RemoveButton(key, quiet)
    for i, entry in ipairs(column) do
        if entry.key == key then
            table.remove(column, i)
            if folded[key] then
                folded[key] = nil
                show(entry.button, true)
            end
            break
        end
    end
    if not quiet then
        Chat.Layout()
    end
end
