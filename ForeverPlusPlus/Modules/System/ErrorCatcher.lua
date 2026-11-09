-- Error Catcher: catches Lua errors, blocked and forbidden actions, and Lua warnings instead of
-- Blizzard's error window and popup, saves them with the session they happened in, and shows
-- them in a window (`/fpp errors`, or a click with a key held on the Minimap Button module's
-- button, through ns.Errors): a list of errors on the left, the one picked on the right, and a
-- button that selects a bug report with the client, addon version, and modules on, ready to copy.
-- An error that happens again is counted instead of kept twice.
--
-- The error handler goes in when this file loads, not in OnEnable, so errors while the addons
-- after this one load are caught too. Whether the module is on is only known once saved
-- variables load, so until then errors wait in `pending`: OnEnable saves them, and OnLoad, when
-- the module is off, gives the handler back and passes them on to it. The TOC loads this file
-- first among the modules, so their load errors are caught too.
local _, ns = ...

local format, tostring, pcall, select, ipairs = string.format, tostring, pcall, select, ipairs
local min = math.min
local concat, tremove, wipe, time, date = table.concat, table.remove, wipe, time, date
local CreateFrame, GetTime = CreateFrame, GetTime
local C_Timer, error = C_Timer, error
local seterrorhandler, geterrorhandler = seterrorhandler, geterrorhandler
local debugstack, debuglocals = debugstack, debuglocals
local GetCallstackHeight, GetErrorCallstackHeight = GetCallstackHeight, GetErrorCallstackHeight

local L = ns.L

local module = ns.NewModule("ErrorCatcher", L.ERRORCATCHER_DESC, {
    enabled = true,
    chat = false,
    sound = "off", -- a key of SOUNDS, played with the chat message (issue #4)
    -- Data, not settings: a table, so presets leave it alone.
    saved = {
        session = 0, -- counts logins and reloads
        -- oldest first: { kind, message, stack, locals, count, session, first, time }
        errors = {},
    },
})
module.title = L.ERRORCATCHER_TITLE
module.category = "system"

local MAX_ERRORS = 100 -- the oldest go first
local MAX_TEXT = 2000 -- letters kept of a stack or the locals, so the saved file stays small
local PER_SECOND = 10 -- errors caught a second at most; an error in OnUpdate repeats every frame
local ANNOUNCE_EVERY = 10 -- seconds between chat messages and sounds about new errors

-- The Sound choices: Blizzard's own error and alert sounds, by SOUNDKIT name (SoundKitConstants.lua,
-- `forever` branch), read when played since a patch can drop one (it then plays nothing).
local SOUNDS = {
    buzz = "UI_GARRISON_ARCHITECT_TABLE_BUILDING_PLACEMENT_ERROR",
    denied = "LFG_DENIED",
    horn = "UI_GARRISON_TOAST_INVASION_ALERT",
    boss = "RAID_BOSS_EMOTE_WARNING",
    raidwarning = "RAID_WARNING",
    gm = "GM_CHAT_WARNING",
    alarm = "ALARM_CLOCK_WARNING_3",
    whisper = "TELL_MESSAGE",
}

local function playSound()
    local kit = SOUNDS[module.db.sound]
    local id = kit and SOUNDKIT and SOUNDKIT[kit]
    if id and PlaySound then
        PlaySound(id, "Master")
    end
end

local previous -- the handler before ours, given back when the module turns off
local pending = {} -- errors caught before saved variables loaded
local busy -- true while catching an error, so an error while catching can't loop
local allowance, lastCaught = PER_SECOND, 0
local lastAnnounced = -ANNOUNCE_EVERY
local window

-- Text that's safe to keep: a secret value or nil becomes `fallback`.
local function readable(value, fallback)
    if not ns.IsReadable(value) then
        return fallback
    end
    if value == nil then
        return fallback
    end
    value = tostring(value)
    if #value > MAX_TEXT then
        value = value:sub(1, MAX_TEXT) .. "\n..."
    end
    return value
end

-- Errors -------------------------------------------------------------------------------------

---The saved errors and session number, or nil before saved variables load.
local function saved()
    return module.db and module.db.saved
end

---How many different errors this session caught.
---@return number
local function sessionCount()
    local data = saved()
    if not data then
        return 0
    end
    local count = 0
    for _, entry in ipairs(data.errors) do
        if entry.session == data.session then
            count = count + 1
        end
    end
    return count
end

local refreshWindow -- set below, once the window exists

local function changed()
    ns.Errors.Changed() -- the minimap button's count
    if refreshWindow then
        refreshWindow(true)
    end
end

-- The first line of an error, without the "Interface/AddOns/" every file path starts with.
local function short(message)
    local line = message:match("^[^\n]*") or message
    line = line:gsub("^Interface[/\\]AddOns[/\\]", "")
    if #line > 120 then
        line = line:sub(1, 117) .. "..."
    end
    return line
end

-- The first line as the window and chat show it: "|" doubled, so a link or color code in the
-- error shows as text instead of breaking the line.
local function shownLine(message)
    return (short(message):gsub("|", "||"))
end

-- Messages whose stack this session's saved entry already has: a repeat is only counted (store),
-- so its stack and locals aren't captured again.
local captured = {}

-- Saves an error, or counts it again if it's already saved. An error seen again in a new session
-- moves to the end, into this session, with its new stack.
local function store(entry, announce)
    local data = saved()
    local errors = data.errors
    for i = #errors, 1, -1 do
        local old = errors[i]
        if old.message == entry.message then
            old.count = (old.count or 1) + 1
            old.time = entry.time
            if old.session ~= data.session then
                old.session = data.session
                old.first = entry.time
                old.stack, old.locals = entry.stack, entry.locals
                tremove(errors, i)
                errors[#errors + 1] = old
            end
            changed()
            return
        end
    end
    entry.count = 1
    entry.session = data.session
    entry.first = entry.time
    errors[#errors + 1] = entry
    while #errors > MAX_ERRORS do
        captured[errors[1].message] = nil
        tremove(errors, 1)
    end
    if announce and GetTime() - lastAnnounced >= ANNOUNCE_EVERY then
        lastAnnounced = GetTime()
        module:Print(format(L.ERRORCATCHER_CAUGHT, shownLine(entry.message)))
        playSound()
    end
    changed()
end

-- Keeps an error: saved while the module is on, kept for later before saved variables load,
-- and handed to the old handler if ours is still called while the module is off.
local function catch(entry)
    if module.enabled then
        store(entry, true)
    elseif not module.db then
        pending[#pending + 1] = entry
    elseif previous then
        pcall(previous, entry.message)
    end
end

-- Whether another error may be caught now (at most PER_SECOND a second).
local function allowed()
    local now = GetTime()
    allowance = min(PER_SECOND, allowance + (now - lastCaught) * PER_SECOND)
    lastCaught = now
    if allowance < 1 then
        return false
    end
    allowance = allowance - 1
    return true
end

-- The stack and locals of the function that raised the error. Blizzard's own handler finds it
-- from the two stack heights; without them, it's three levels up (this, the pcall, the handler).
-- Must be called through pcall straight from the handler, for the fallback depth to be right.
local function capture()
    local level = 4
    local height = GetCallstackHeight and GetCallstackHeight()
    local errorHeight = GetErrorCallstackHeight and GetErrorCallstackHeight()
    if height and errorHeight then
        level = height - errorHeight + 1
    end
    -- Both can come back secret on Forever (Midnight's rules).
    return readable(debugstack and debugstack(level), nil), readable(debuglocals and debuglocals(level), nil)
end

-- The error handler: the game calls it with the message of every Lua error.
local function onError(message)
    if busy or not allowed() then
        return
    end
    busy = true
    local text = readable(message, L.ERRORCATCHER_SECRET)
    local stack, locals
    if not captured[text] then
        local ok
        -- Still called straight from the handler, as capture needs.
        ok, stack, locals = pcall(capture)
        if not ok then
            stack, locals = nil, nil
        end
        -- Only once it will be saved: one handed on while the module is off keeps nothing.
        if module.enabled or not module.db then
            captured[text] = true
        end
    end
    pcall(catch, {
        kind = "error",
        message = text,
        stack = stack,
        locals = locals,
        time = time(),
    })
    busy = false
end

-- ADDON_ACTION_BLOCKED and ADDON_ACTION_FORBIDDEN: an addon called something only Blizzard's
-- code may. The stack here would only be this handler's, so there's none.
local function onBlocked(event, addon, fn)
    if not allowed() then
        return
    end
    catch({
        kind = "blocked",
        message = format(L.ERRORCATCHER_BLOCKED, event, readable(addon, L.ERRORCATCHER_UNKNOWN),
            readable(fn, L.ERRORCATCHER_UNKNOWN)),
        time = time(),
    })
end

-- LUA_WARNING: older clients send a warning type before the text, newer ones only the text.
local function onWarning(_, ...)
    if not allowed() then
        return
    end
    local text = select(select("#", ...), ...)
    catch({
        kind = "warning",
        message = readable(text, L.ERRORCATCHER_UNKNOWN),
        time = time(),
    })
end

local function clear()
    local data = saved()
    wipe(captured)
    if data then
        wipe(data.errors)
        changed()
    end
end

-- Asks before forgetting every saved error.
local function confirmClear()
    ns.Confirm("ERRORCATCHER_CLEAR", L.ERRORCATCHER_CLEAR_CONFIRM, clear)
end

-- Forgets this session's errors, keeping earlier sessions'.
local function clearSession()
    wipe(captured)
    local data = saved()
    if not data then
        return
    end
    local kept = {}
    for _, entry in ipairs(data.errors) do
        if entry.session ~= data.session then
            kept[#kept + 1] = entry
        end
    end
    data.errors = kept
    changed()
end

-- Caught from here on (see the top of the file).
previous = geterrorhandler()
seterrorhandler(onError)

-- Whether another addon (BugGrabber) keeps the error handler to itself, so ours never goes in.
local function otherHandler()
    return geterrorhandler() ~= onError
end

-- A gray row in Settings while another addon catches the Lua errors, since then the window shows
-- only blocked actions and warnings, which would read as "no errors" without it.
module.notice = {
    text = L.ERRORCATCHER_OTHER_HANDLER,
    description = L.ERRORCATCHER_OTHER_HANDLER_DESC,
    shown = function()
        return module.enabled and otherHandler()
    end,
}

-- The bug report ----------------------------------------------------------------------------

-- What each kind of entry is called, and its color in the window.
local KINDS = {
    error = { name = L.ERRORCATCHER_KIND_ERROR, r = 1, g = 0.25, b = 0.25 },
    blocked = { name = L.ERRORCATCHER_KIND_BLOCKED, r = 1, g = 0.5, b = 0.1 },
    warning = { name = L.ERRORCATCHER_KIND_WARNING, r = 1, g = 0.82, b = 0 },
}

local function kindOf(entry)
    return KINDS[entry.kind] or KINDS.error
end

-- A time as a clock time if it was today, with the date if not.
local function when(stamp)
    stamp = stamp or 0
    if date("%Y-%m-%d", stamp) == date("%Y-%m-%d") then
        return date("%H:%M:%S", stamp)
    end
    return date("%Y-%m-%d %H:%M", stamp)
end

-- The other addons loaded now: an error is often theirs, or theirs and ours together.
local function otherAddOns()
    local names = {}
    if not (C_AddOns and C_AddOns.GetNumAddOns) then
        return names
    end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= ns.name and C_AddOns.IsAddOnLoaded(i) then
            local version = C_AddOns.GetAddOnMetadata(name, "Version")
            names[#names + 1] = version and version ~= "" and (name .. " " .. version) or name
        end
    end
    return names
end

-- How long ago an entry last happened ("12m ago").
local function age(entry)
    return ns.Text.Ago(time() - (entry.time or time()))
end

-- How often and when an entry happened, in one line.
local function seenText(entry)
    return format(L.ERRORCATCHER_META, entry.count or 1, entry.session or 0,
        when(entry.first or entry.time), when(entry.time), age(entry))
end

-- The message, stack, and locals of an entry, as lines.
local function addBody(lines, entry)
    lines[#lines + 1] = entry.message
    local any = false
    if entry.stack and entry.stack ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.ERRORCATCHER_STACK
        lines[#lines + 1] = entry.stack
        any = true
    end
    if entry.locals and entry.locals ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.ERRORCATCHER_LOCALS
        lines[#lines + 1] = entry.locals
        any = true
    end
    if not any then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.ERRORCATCHER_NO_STACK
    end
end

-- "|" is doubled so the text shows as it is, instead of as colors and icons.
local function plain(lines)
    return (concat(lines, "\n"):gsub("|", "||"))
end

-- What the window shows for an entry.
local function entryText(entry)
    local lines = {}
    addBody(lines, entry)
    return plain(lines)
end

---Everything a bug report needs about one entry: the addon and client, the modules and addons
---on, and the error itself.
local function reportText(entry)
    local gameVersion, build, _, interface = GetBuildInfo()
    local on, others = ns.ModulesOn(), otherAddOns()
    local lines = {
        format(L.ERRORCATCHER_REPORT_HEADER, ns.Metadata("Version")),
        format(L.ERRORCATCHER_REPORT_CLIENT, tostring(gameVersion), tostring(build),
            tostring(interface), GetLocale()),
        format(L.ERRORCATCHER_REPORT_DATE, date("%Y-%m-%d %H:%M:%S")),
        format(L.ERRORCATCHER_REPORT_MODULES, #on, concat(on, ", ")),
        format(L.ERRORCATCHER_REPORT_ADDONS, #others,
            #others > 0 and concat(others, ", ") or L.ERRORCATCHER_REPORT_NONE),
        "",
        kindOf(entry).name .. ". " .. seenText(entry),
        "",
    }
    addBody(lines, entry)
    return plain(lines)
end

-- The window ----------------------------------------------------------------------------------

local SESSION, LAST, ALL = "session", "last", "all"
local filter = SESSION
local list = {} -- the errors the filter shows, newest first
local selected -- the entry open on the right
local reporting = false -- whether the text box holds the bug report instead of the error
local shownText = "" -- what the text box holds, put back if it's typed in

-- The latest session before this one that caught anything.
local function lastSession(data)
    local last
    for _, entry in ipairs(data.errors) do
        if entry.session < data.session and (not last or entry.session > last) then
            last = entry.session
        end
    end
    return last
end

-- The errors a filter shows, newest first.
local function filtered(which)
    local data = saved()
    local result = {}
    if not data then
        return result
    end
    local wanted = which == SESSION and data.session or which == LAST and lastSession(data)
    for i = #data.errors, 1, -1 do
        local entry = data.errors[i]
        if which == ALL or entry.session == wanted then
            result[#result + 1] = entry
        end
    end
    return result
end

local function indexOf(entry)
    for i, e in ipairs(list) do
        if e == entry then
            return i
        end
    end
end

local function setEditText(text)
    shownText = text
    window.edit:SetText(text)
    window.edit:SetCursorPosition(0)
    window.scroll:SetVerticalScroll(0)
end

-- The right side: the picked entry, or a note that there's nothing.
local function showDetails()
    local f = window
    local entry = selected
    f.hint:SetText("")
    reporting = false
    if not entry then
        f.kind:SetText("")
        f.position:SetText("")
        f.message:SetText(L.ERRORCATCHER_NONE)
        f.meta:SetText("")
        setEditText("")
        f.copy:SetEnabled(false)
    else
        local kind = kindOf(entry)
        f.kind:SetText(kind.name)
        f.kind:SetTextColor(kind.r, kind.g, kind.b)
        f.position:SetText(format(L.ERRORCATCHER_POSITION, indexOf(entry) or 0, #list))
        f.message:SetText(shownLine(entry.message))
        f.meta:SetText(seenText(entry))
        setEditText(entryText(entry))
        f.copy:SetEnabled(true)
    end
    local data = saved()
    f.clear:SetEnabled(data ~= nil and #data.errors > 0)
end

-- Marks the picked row in the list.
local function markRows()
    window.scrollBox:ForEachFrame(function(row)
        row.selected:SetShown(row.entry == selected)
    end)
end

local function pick(entry)
    selected = entry
    markRows()
    showDetails()
end

local function summary()
    local data = saved()
    window.summary:SetText(format(L.ERRORCATCHER_SUMMARY, sessionCount(), data and #data.errors or 0))
end

-- Rebuilds the list. `follow` opens the newest error if the newest was open, so new ones show
-- at once. A bug report being copied stays put while its error stays open.
function refreshWindow(follow)
    if not (window and window:IsShown()) then
        return
    end
    local before = selected
    local wasNewest = selected == nil or selected == list[1]
    list = filtered(filter)
    if not indexOf(selected) or (follow and wasNewest) then
        selected = list[1]
    end
    window.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
    markRows()
    summary()
    if window.filter.GenerateMenu then
        window.filter:GenerateMenu() -- the counts in the dropdown's text
    end
    if reporting and selected == before then
        window.position:SetText(format(L.ERRORCATCHER_POSITION, indexOf(selected) or 0, #list))
        window.clear:SetEnabled(true)
    else
        showDetails()
    end
end

local function setFilter(value)
    filter = value
    selected = nil
    refreshWindow()
end

local FILTERS = {
    { SESSION, L.ERRORCATCHER_THIS_SESSION },
    { LAST, L.ERRORCATCHER_LAST_SESSION },
    { ALL, L.ERRORCATCHER_ALL },
}

-- Blizzard's dropdown for the session filter, with how many errors each shows. Probe:
-- WowStyle1DropdownTemplate is Mainline's; without it, a button that steps through the choices.
local function newFilter(parent)
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetWidth(180)
        dropdown:SetupMenu(function(_, root)
            for _, choice in ipairs(FILTERS) do
                root:CreateRadio(format(L.ERRORCATCHER_FILTER, choice[2], #filtered(choice[1])),
                    function(value)
                        return filter == value
                    end, setFilter, choice[1])
            end
        end)
        return dropdown
    end
    local b = ns.Frames.Button(parent, FILTERS[1][2], 180)
    b:SetScript("OnClick", function(self)
        for i, choice in ipairs(FILTERS) do
            if choice[1] == filter then
                local nextChoice = FILTERS[i % #FILTERS + 1]
                self:SetText(nextChoice[2])
                setFilter(nextChoice[1])
                return
            end
        end
    end)
    return b
end

local newInset, rowTexture = ns.Frames.Inset, ns.Frames.RowTexture

local ROW_HEIGHT = 38

local function buildRow(row)
    row.selected = rowTexture(row, "BACKGROUND", "Options_List_Active", 1, 0.82, 0, 0.15)
    row:SetHighlightTexture(rowTexture(row, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.08))
    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.kind:SetPoint("TOPLEFT", 8, -6)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPRIGHT", -6, -6)
    row.message = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.message:SetPoint("BOTTOMLEFT", 8, 6)
    row.message:SetPoint("BOTTOMRIGHT", -6, 6)
    row.message:SetJustifyH("LEFT")
    row.message:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        pick(self.entry)
    end)
end

local function initRow(row, entry)
    if not row.kind then
        buildRow(row)
    end
    row.entry = entry
    local kind = kindOf(entry)
    row.kind:SetText(kind.name)
    row.kind:SetTextColor(kind.r, kind.g, kind.b)
    row.info:SetText(format(L.ERRORCATCHER_ROW_INFO, entry.count or 1, age(entry)))
    row.message:SetText(shownLine(entry.message))
    row.selected:SetShown(entry == selected)
end

-- Puts the bug report in the text box, selected, so Ctrl+C copies it. Addons can't write to the
-- clipboard themselves.
local function copyReport()
    if not selected then
        return
    end
    setEditText(reportText(selected))
    reporting = true
    window.edit:SetFocus()
    window.edit:HighlightText()
    window.hint:SetText(L.ERRORCATCHER_COPY_HINT)
end

-- Named so Escape can close it (ns.Frames.CloseOnEscape).
local WINDOW_NAME = "ForeverPlusPlusErrorCatcher"

local LIST_WIDTH = 270

local function newWindow()
    local f = ns.Frames.PortraitWindow(WINDOW_NAME, L.ERRORCATCHER_TITLE)
    window = f
    f:SetSize(780, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", f.StartMoving)
    f:SetScript("OnMouseUp", f.StopMovingOrSizing)
    ns.Frames.CloseOnEscape(f)

    -- Beside the portrait: how many errors, and which sessions the list shows.
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 66, -38)
    f.filter = newFilter(f)
    f.filter:SetPoint("TOPRIGHT", -12, -31)

    -- The list, on the left.
    local listInset = newInset(f)
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

    -- The picked error, on the right.
    local details = f.Inset or newInset(f)
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 2, 0)
    details:SetPoint("BOTTOMRIGHT", -6, 28)

    f.kind = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.kind:SetPoint("TOPLEFT", 12, -10)
    f.position = details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.position:SetPoint("TOPRIGHT", -12, -12)
    f.message = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.message:SetPoint("TOPLEFT", f.kind, "BOTTOMLEFT", 0, -6)
    f.message:SetPoint("RIGHT", -12, 0)
    f.message:SetJustifyH("LEFT")
    f.message:SetMaxLines(3)
    f.meta = details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.meta:SetPoint("TOPLEFT", f.message, "BOTTOMLEFT", 0, -6)
    f.meta:SetPoint("RIGHT", -12, 0)
    f.meta:SetJustifyH("LEFT")

    local line = details:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", f.meta, "BOTTOMLEFT", 0, -8)
    line:SetPoint("RIGHT", -12, 0)

    local scroll = CreateFrame("ScrollFrame", nil, details, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetWidth(440)
    edit:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    -- Selected on click, ready for Ctrl+C.
    -- Not edit.HighlightText itself: the script's extra arguments would become its range.
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Read only: typing puts the text back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(shownText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width)
        edit:SetWidth(width)
    end)
    f.edit, f.scroll = edit, scroll

    -- The strip at the bottom.
    f.clear = ns.Frames.Button(f, L.ERRORCATCHER_CLEAR, 110, confirmClear)
    f.clear:SetPoint("BOTTOMLEFT", 4, 4)
    f.copy = ns.Frames.Button(f, L.ERRORCATCHER_COPY, 140, copyReport)
    f.copy:SetPoint("BOTTOMRIGHT", -6, 4)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    f.hint:SetPoint("RIGHT", f.copy, "LEFT", -10, 0)

    f:Hide()
    return f
end

local function toggleWindow()
    if window and window:IsShown() then
        window:Hide()
        return
    end
    if not window then
        newWindow()
    end
    window:Show()
    selected = nil
    refreshWindow()
end

-- The module ----------------------------------------------------------------------------------

-- What the minimap button reads and opens, through ns.Errors, while the module is on.
local provider = {
    session = sessionCount,
    saved = function()
        local data = saved()
        return data and #data.errors or 0
    end,
    toggle = toggleWindow,
    clearSession = clearSession,
    clearAll = confirmClear,
}

module.options = {
    {
        key = "sound", name = L.ERRORCATCHER_SOUND, description = L.ERRORCATCHER_SOUND_DESC,
        added = "1.3.1",
        choices = {
            { "off", L.ERRORCATCHER_SOUND_OFF },
            { "buzz", L.ERRORCATCHER_SOUND_BUZZ },
            { "denied", L.ERRORCATCHER_SOUND_DENIED },
            { "horn", L.ERRORCATCHER_SOUND_HORN },
            { "boss", L.ERRORCATCHER_SOUND_BOSS },
            { "raidwarning", L.ERRORCATCHER_SOUND_RAIDWARNING },
            { "gm", L.ERRORCATCHER_SOUND_GM },
            { "alarm", L.ERRORCATCHER_SOUND_ALARM },
            { "whisper", L.ERRORCATCHER_SOUND_WHISPER },
        },
    },
    ns.ChatOption(L.ERRORCATCHER_CHAT_DESC),
}

-- Picking a sound plays it, so the player knows what they picked.
function module:OnOptionChanged(key)
    if key == "sound" then
        playSound()
    end
end

module.actions = {
    {
        name = L.ERRORCATCHER_SHOW,
        button = L.ERRORCATCHER_SHOW_BUTTON,
        description = L.ERRORCATCHER_SHOW_DESC,
        fn = toggleWindow,
    },
    {
        name = L.ERRORCATCHER_CLEAR_NAME,
        button = L.ERRORCATCHER_CLEAR,
        description = L.ERRORCATCHER_CLEAR_DESC,
        confirm = L.ERRORCATCHER_CLEAR_CONFIRM,
        key = "ERRORCATCHER_CLEAR",
        fn = clear,
    },
}

-- Raises a Lua error on purpose, to see what catches it. On the next frame, so it goes to the
-- error handler on its own instead of out of the Settings button's click.
local function testError()
    C_Timer.After(0, function()
        error(L.ERRORCATCHER_TEST_MESSAGE)
    end)
end

-- In the Debug module's settings (Settings/Debug.lua). Works with the module off too, to see
-- Blizzard's handler.
module.debugActions = {
    {
        name = L.ERRORCATCHER_TEST,
        button = L.ERRORCATCHER_TEST_BUTTON,
        description = L.ERRORCATCHER_TEST_DESC,
        fn = testError,
        whileOff = true,
        section = L.DEBUG_SECTION_PREVIEWS,
    },
}

-- An event this client may not have: RegisterEvent can raise an error for an unknown one.
local function listen(event, fn)
    if ns.HasEvent(event) then
        module:On(event, fn)
    end
end

function module:OnLoad()
    local data = self.db.saved
    data.session = data.session + 1
    if self.db.enabled then
        return -- OnEnable saves what's pending
    end
    -- Off: give the handler back, with what it missed while the addons loaded.
    if geterrorhandler() == onError then
        seterrorhandler(previous)
    end
    for _, entry in ipairs(pending) do
        pcall(previous, entry.message)
    end
    pending = {}
end

-- Blizzard's "blocked from an action" popup, which offers to turn the addon off. Left to the addon
-- that has the error handler (module.notice says so), like Blizzard's error window.
local function onPopup(which)
    if which == "ADDON_ACTION_FORBIDDEN" and not otherHandler() then
        StaticPopup_Hide(which)
    end
end

-- Blizzard's error window, which still opens for Lua warnings.
local function onErrorWindow(frame)
    if not otherHandler() then
        frame:Hide()
    end
end

function module:OnEnable()
    local current = geterrorhandler()
    if current ~= onError then
        previous = current
        seterrorhandler(onError)
    end
    listen("ADDON_ACTION_BLOCKED", onBlocked)
    listen("ADDON_ACTION_FORBIDDEN", onBlocked)
    listen("LUA_WARNING", onWarning)
    if StaticPopup_Hide then
        self:Hook("StaticPopup_Show", onPopup)
    end
    self:HookScript(ScriptErrorsFrame, "OnShow", onErrorWindow)

    if #pending > 0 then
        local count = #pending
        for _, entry in ipairs(pending) do
            store(entry, false)
        end
        pending = {}
        self:Print(format(L.ERRORCATCHER_CAUGHT_LOADING, count))
    end
    ns.Errors.Provide(provider)
end

function module:OnDisable()
    if geterrorhandler() == onError then
        seterrorhandler(previous)
    end
    ns.Errors.Provide(nil)
    if window then
        window:Hide()
    end
end

-- Only while the module is on: Core says so otherwise.
ns.AddCommand("errors", "", L.ERRORCATCHER_COMMAND, toggleWindow, "ErrorCatcher")
