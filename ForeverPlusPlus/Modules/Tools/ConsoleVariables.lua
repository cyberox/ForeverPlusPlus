-- Console Variables: a page under Forever++ in Settings that lists the game's console variables
-- (CVars) the player can change, laid out like the Modules page: a list of groups on the left
-- (Changed, All, and the client's own categories), each with how many match the search box at the
-- top right, and the selected group's CVars beside it. Each shows its name (gold while changed)
-- over its help text, a box for its value, and a Default button. Read-only CVars are left out.
-- Changes made in combat wait for it to end (ns.CVars.Apply).
-- Nothing is built until the page is first shown; `/fpp cvar <search>` opens it.
local _, ns = ...

local ipairs, pairs, type, sort = ipairs, pairs, type, table.sort
local format, tostring = string.format, tostring
local strlower, strfind, strtrim, tinsert = string.lower, string.find, strtrim, table.insert
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local C_CVar = C_CVar
-- The console's command list. Forever (build 70009) has the global, like Retail; C_Console is a
-- guess at a later rename.
local getAllCommands = ConsoleGetAllCommands or (C_Console and C_Console.GetAllCommands)
local L = ns.L

local module = ns.NewModule("ConsoleVariables", L.CONSOLEVARIABLES_DESC, { enabled = false })
module.title = L.CONSOLEVARIABLES_TITLE
module.category = "tools" -- off, its page and command are gone; it costs nothing until opened

local LIST_WIDTH = 160 -- the group list, a little narrower than the module list
local ROW_HEIGHT = 40 -- a CVar's row: its name over its help text
local RESET_WIDTH, VALUE_WIDTH, GAP = 78, 112, 10

-- Names for the client's categories (Enum.ConsoleCategory keys). Some read badly to players, so
-- they get plainer ones (see the locale file). A key the client adds later shows as it is.
local CATEGORY_NAMES = {
    Debug = L.CONSOLEVARIABLES_CATEGORY_DEBUG,
    Graphics = L.CONSOLEVARIABLES_CATEGORY_GRAPHICS,
    Console = L.CONSOLEVARIABLES_CATEGORY_CONSOLE,
    Combat = L.CONSOLEVARIABLES_CATEGORY_COMBAT,
    Game = L.CONSOLEVARIABLES_CATEGORY_GAME,
    Default = L.CONSOLEVARIABLES_CATEGORY_DEFAULT,
    Net = L.CONSOLEVARIABLES_CATEGORY_NET,
    Sound = L.CONSOLEVARIABLES_CATEGORY_SOUND,
    Gm = L.CONSOLEVARIABLES_CATEGORY_GM,
    Reveal = L.CONSOLEVARIABLES_CATEGORY_REVEAL,
    None = L.CONSOLEVARIABLES_CATEGORY_NONE,
}

-- every listed CVar, sorted: { name, key (lowercase name), text (lowercase name and help), help,
-- category (an Enum.ConsoleCategory value) }
local all
local byKey = {} -- lowercase name -> entry in `all`
-- the list's groups in order, Changed and All first: { key, label, has(entry, changed) }
local groups
local search, selected = "", nil -- the search text, and the selected group's key
local ui -- the page's parts, once built

-- value, default, and flags ({ account, character, readOnly, secure }) for one CVar.
local function read(name)
    if C_CVar.GetCVarInfo then
        local value, default, account, character, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
        return value, default, {
            account = account,
            character = character,
            readOnly = locked or readOnly,
            secure = secure,
        }
    end
    return C_CVar.GetCVar(name), C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name), {}
end

local function isReadOnly(name)
    local _, _, flags = read(name)
    return flags.readOnly
end

local function isChanged(name)
    local value, default = read(name)
    return default ~= nil and value ~= default
end

-- Changed, All, then a group for each of the client's categories that has a CVar, by name.
local function loadGroups(present)
    local keys = {}
    for key, value in pairs(Enum.ConsoleCategory or {}) do
        keys[value] = key
    end
    local categories = {}
    for value in pairs(present) do
        local key = keys[value]
        local label = key and (CATEGORY_NAMES[key] or key) or tostring(value)
        categories[#categories + 1] = {
            key = value,
            label = label,
            has = function(entry) return entry.category == value end,
        }
    end
    sort(categories, function(a, b) return a.label < b.label end)
    groups = {
        {
            key = "changed",
            label = L.CONSOLEVARIABLES_CHANGED,
            has = function(_, changed) return changed end,
        },
        { key = "all", label = L.CONSOLEVARIABLES_ALL, has = function() return true end },
    }
    for _, group in ipairs(categories) do
        groups[#groups + 1] = group
    end
end

-- Every CVar this client lists that the player can change (read-only ones are left out), and the
-- groups they make. Without the list, typing an exact name still finds a CVar.
local function loadAll()
    all = {}
    local present = {}
    if getAllCommands then
        local cvarType = Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
        for _, info in ipairs(getAllCommands() or {}) do
            local name = info.command
            if info.commandType == cvarType and type(name) == "string" and name ~= ""
                and not isReadOnly(name) then
                local key = strlower(name)
                if not byKey[key] then
                    local help = info.help or ""
                    local entry = {
                        name = name,
                        key = key,
                        help = help,
                        text = key .. " " .. strlower(help),
                        category = info.category,
                    }
                    byKey[key] = entry
                    all[#all + 1] = entry
                    if info.category ~= nil then
                        present[info.category] = true
                    end
                end
            end
        end
    end
    sort(all, function(a, b) return a.key < b.key end)
    loadGroups(present)
end

local function groupOf(key)
    for _, group in ipairs(groups) do
        if group.key == key then
            return group
        end
    end
end

-- Lists the selected group's CVars that match the search and counts each group's matches.
-- `top` scrolls back to the top (a new group); otherwise the scroll position stays.
local function refresh(top)
    -- Not before the list is made: filling the search box while the page is built calls this.
    if not (ui and ui.scrollBox) then
        return
    end
    local query = strlower(search)
    local group = groupOf(selected) or groups[1]
    local counts, rows = {}, {}
    local function add(entry, changed)
        for _, other in ipairs(groups) do
            if other.has(entry, changed) then
                counts[other.key] = (counts[other.key] or 0) + 1
            end
        end
        if group.has(entry, changed) then
            rows[#rows + 1] = entry
        end
    end
    for _, entry in ipairs(all) do
        if query == "" or strfind(entry.text, query, 1, true) then
            add(entry, isChanged(entry.name))
        end
    end
    -- An exact name the list doesn't have (a hidden CVar, or no command list) still shows, first,
    -- in Changed and All, unless it's read-only.
    if query ~= "" and not byKey[query] and C_CVar.GetCVar(search) ~= nil
        and not isReadOnly(search) then
        local before = #rows
        add({ name = search, key = query, help = "", text = query }, isChanged(search))
        if #rows > before then
            tinsert(rows, 1, rows[#rows])
            rows[#rows] = nil
        end
    end
    ui.scrollBox:SetDataProvider(CreateDataProvider(rows), top
        and ScrollBoxConstants.DiscardScrollPosition or ScrollBoxConstants.RetainScrollPosition)
    for _, row in ipairs(ui.groupRows) do
        local count = counts[row.group.key] or 0
        row.count:SetText(count)
        -- Changed in gold while there's something in it, like a changed CVar's name.
        row.text:SetFontObject(row.group.key == "changed" and count > 0 and "GameFontNormal"
            or "GameFontHighlight")
    end
    -- Say why the list is empty instead of leaving a blank pane.
    local empty
    if #rows == 0 then
        if query ~= "" then
            empty = format(L.CONSOLEVARIABLES_NO_MATCH, search)
        elseif #all == 0 then
            empty = L.CONSOLEVARIABLES_NO_LIST
        else
            empty = L.CONSOLEVARIABLES_NONE_CHANGED
        end
    end
    ui.empty:SetText(empty or "")
    ui.empty:SetShown(empty ~= nil)
end

local function apply(name, value)
    if InCombatLockdown() then
        ns.Print(format(L.CONSOLEVARIABLES_AFTER_COMBAT, name))
    end
    ns.CVars.Apply(name, value, function(ok)
        if not ok then
            ns.Print(format(L.CONSOLEVARIABLES_REFUSED, name))
        end
        refresh()
    end)
end

-- Groups ---------------------------------------------------------------------------------------

local function choose(key)
    selected = key
    for _, row in ipairs(ui.groupRows) do
        ns.SettingsKit.Paint(row)
    end
    refresh(true)
end

-- A group's row in the list: its name, and how many of its CVars match the search in gray at the
-- right.
local function newGroupRow(list, group)
    local row = ns.SettingsKit.NewListButton(list, function() return selected == group.key end)
    row.group = group
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.text:SetText(group.label)
    row:SetScript("OnClick", function()
        if selected ~= group.key then
            choose(group.key)
        end
    end)
    return row
end

-- Rows -----------------------------------------------------------------------------------------

local function showTooltip(row)
    local entry = row.entry
    local value, default, flags = read(entry.name)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name, 1, 1, 1)
    if entry.help ~= "" then
        GameTooltip:AddLine(entry.help, nil, nil, nil, true)
    end
    GameTooltip:AddLine(format(L.CONSOLEVARIABLES_VALUE_IS, tostring(value)), unpack(ns.Colors.GRAY))
    if default ~= nil then
        GameTooltip:AddLine(format(L.CONSOLEVARIABLES_DEFAULT_IS, default), unpack(ns.Colors.GRAY))
    end
    -- The client doesn't say which CVars are on/off (no type in the command list or
    -- GetCVarInfo), and any takes any value, so a box for all and this hint where it may help.
    if value == "0" or value == "1" or default == "0" or default == "1" then
        GameTooltip:AddLine(L.CONSOLEVARIABLES_ON_OFF_HINT, unpack(ns.Colors.GRAY))
    end
    if flags.account then
        GameTooltip:AddLine(L.CONSOLEVARIABLES_ACCOUNT, unpack(ns.Colors.GRAY))
    elseif flags.character then
        GameTooltip:AddLine(L.CONSOLEVARIABLES_CHARACTER, unpack(ns.Colors.GRAY))
    end
    if flags.readOnly then
        GameTooltip:AddLine(L.CONSOLEVARIABLES_READ_ONLY, unpack(ns.Colors.RED))
    elseif flags.secure then
        GameTooltip:AddLine(L.CONSOLEVARIABLES_SECURE, unpack(ns.Colors.GRAY))
    end
    GameTooltip:Show()
end

-- The row and its box and button all highlight the row and show its tooltip: moving onto a child
-- frame is a leave for the row, which would drop the highlight over the box and the button.
local function enterRow(row)
    row.highlight:Show()
    showTooltip(row)
end

local function leaveRow(row)
    row.highlight:Hide()
    GameTooltip:Hide()
end

local function buildRow(row)
    row:EnableMouse(true)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.highlight:Hide()

    row.reset = ns.Frames.Button(row, L.CONSOLEVARIABLES_DEFAULT, RESET_WIDTH, function()
        local _, default = read(row.entry.name)
        if default ~= nil then
            apply(row.entry.name, default)
        end
    end)
    row.reset:SetPoint("RIGHT", -4, 0)
    -- It's disabled on most rows (already at the default) and still covers part of the row.
    row.reset:SetMotionScriptsWhileDisabled(true)
    row.reset:HookScript("OnEnter", function() enterRow(row) end)
    row.reset:HookScript("OnLeave", function() leaveRow(row) end)

    row.value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.value:SetSize(VALUE_WIDTH, 20)
    row.value:SetPoint("RIGHT", row.reset, "LEFT", -GAP, 0)
    row.value:SetAutoFocus(false)
    -- Our own box, so its Enter script is ours to set. Read the text before clearing focus: losing
    -- focus puts the current value back in the box, which would undo the edit.
    row.value:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText() or "")
        local value = read(row.entry.name)
        self:ClearFocus()
        if text ~= value then
            apply(row.entry.name, text)
        end
    end)
    -- Leaving the box without Enter drops the edit.
    row.value:HookScript("OnEditFocusLost", function(self)
        self:SetText(tostring(read(row.entry.name) or ""))
        self:SetCursorPosition(0)
    end)
    row.value:HookScript("OnEnter", function() enterRow(row) end)
    row.value:HookScript("OnLeave", function() leaveRow(row) end)

    -- The box's art reaches a few pixels left of it, so the text stops short of that.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 6, -6)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -GAP - 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.help = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.help:SetPoint("TOPLEFT", 6, -23)
    row.help:SetPoint("RIGHT", row.value, "LEFT", -GAP - 6, 0)
    row.help:SetJustifyH("LEFT")
    row.help:SetWordWrap(false)

    row:SetScript("OnEnter", enterRow)
    row:SetScript("OnLeave", leaveRow)
end

local function initRow(row, entry)
    if not row.value then
        buildRow(row)
    end
    row.entry = entry
    local value, default, flags = read(entry.name)
    local changed = default ~= nil and value ~= default
    row.name:SetText(entry.name)
    if flags.readOnly then
        row.name:SetTextColor(0.5, 0.5, 0.5)
    elseif changed then
        row.name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    else
        row.name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    end
    row.help:SetText(entry.help)
    if not row.value:HasFocus() then
        row.value:SetText(tostring(value or ""))
        row.value:SetCursorPosition(0)
    end
    if row.value.SetEnabled then
        row.value:SetEnabled(not flags.readOnly)
    end
    row.reset:SetEnabled(changed and not flags.readOnly)
end

-- Page -----------------------------------------------------------------------------------------

-- CVAR_UPDATE comes in bursts (the game's Settings can change dozens at once), and each refresh
-- goes through every CVar, so a burst refreshes once, on the next frame. Listened to only while
-- the page is open, to follow changes made anywhere (the game's own settings, other addons).
local onCVarUpdate = ns.Frames.Coalesce(refresh, nil, module)

---Draws the page the first time it's shown (called by Settings/Settings.lua).
---@param frame table the empty page
function module:BuildPage(frame)
    loadAll()
    ui = { groupRows = {} }

    local title = ns.SettingsKit.AddPageTitle(frame, module.title)
    local split = ns.SettingsKit.NewSplit(frame, LIST_WIDTH, true)

    -- In the title row at the top right. No Defaults button here: it resets Forever++'s settings,
    -- not console variables, so on this page it reads as the wrong thing.
    ui.search = ns.SettingsKit.AddSearchBox(frame, nil, L.CONSOLEVARIABLES_SEARCH, function(text)
        search = text
        refresh()
    end)
    if ui.search then
        ui.search:SetText(search)
    end

    -- Between the title and the search box: what a CVar's 0 and 1 usually mean, for players who
    -- haven't set one before. Each CVar's tooltip says the rest.
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    note:SetPoint("LEFT", title, "RIGHT", 14, -1)
    if ui.search then
        note:SetPoint("RIGHT", ui.search, "LEFT", -14, 0)
    end
    note:SetJustifyH("LEFT")
    note:SetWordWrap(false)
    note:SetText(L.CONSOLEVARIABLES_ON_OFF)

    for _, group in ipairs(groups) do
        local row = newGroupRow(split.list, group)
        ui.groupRows[#ui.groupRows + 1] = row
        ns.SettingsKit.AddEntry(split.list, row)
    end
    ns.SettingsKit.Layout(split.list)

    local scrollBox = split.pane
    ui.scrollBox = scrollBox

    -- Like the Modules page's "No modules match".
    ui.empty = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ui.empty:SetPoint("TOPLEFT", 6, -6)
    ui.empty:SetPoint("RIGHT", -6, 0)
    ui.empty:SetJustifyH("LEFT")
    ui.empty:Hide()

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, split.scrollBar, view)

    -- Opens on Changed while something is, otherwise All (or All for `/fpp cvar <search>`).
    if not selected then
        selected = "all"
        if search == "" then
            for _, entry in ipairs(all) do
                if isChanged(entry.name) then
                    selected = "changed"
                    break
                end
            end
        end
    end

    -- The listener stops by itself when the module turns off, and its queued refresh with it.
    self:HookScript(frame, "OnShow", function()
        self:On("CVAR_UPDATE", onCVarUpdate)
        refresh()
    end)
    frame:HookScript("OnHide", function() self:Off("CVAR_UPDATE", onCVarUpdate) end)
    if frame:IsShown() then
        self:On("CVAR_UPDATE", onCVarUpdate)
    end
    choose(selected)
end

---Shows the page with `text` in the search box, in All so nothing it finds is hidden.
---@param text string
local function openWith(text)
    search = text
    if text ~= "" then
        selected = "all"
    end
    if ui then
        if ui.search then
            ui.search:SetText(text)
        end
        choose(selected)
    end
    if not ns.OpenSettings(module.name) then
        ns.Print(L.CONSOLEVARIABLES_NO_PAGE)
    end
end

ns.AddCommand("cvar", "[search]", L.CONSOLEVARIABLES_COMMAND, function(rest)
    openWith(strtrim(rest))
end, module.name)
