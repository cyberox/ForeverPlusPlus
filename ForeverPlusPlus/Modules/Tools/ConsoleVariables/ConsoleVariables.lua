-- Console Variables: a page under Forever++ in Settings that lists the game's console variables
-- (CVars) the player can change, laid out like the Modules page: a list of groups on the left
-- (Popular, Favorites, Changed, All, and the client's own categories), each with how many match
-- the search box at the top right, and the selected group's CVars beside it. Each shows a star
-- for Favorites, its name (gold while changed) over its help text, a box for its value, and a
-- Default button. A Popular one (Popular.lua: ones players look for, with a plain name and help of
-- our own) shows that name with the CVar's own in gray, in every group. Read-only CVars are left
-- out. Changes made in combat wait for it to end (ns.CVars.Apply), and one the game takes as
-- something else (a value past its range) says so in chat with its box flashing red.
-- Nothing is built until the page is first shown; `/fpp cvar <search>` opens it.
local _, ns = ...

local ipairs, pairs, type, sort = ipairs, pairs, type, table.sort
local format, tostring, tonumber = string.format, tostring, tonumber
local strlower, strfind, strtrim, tinsert = string.lower, string.find, strtrim, table.insert
local CreateFrame, InCombatLockdown, GetTime = CreateFrame, InCombatLockdown, GetTime
local C_CVar, C_Timer = C_CVar, C_Timer
-- The console's command list. Forever (build 70009) has the global, like Retail; C_Console is a
-- guess at a later rename.
local getAllCommands = ConsoleGetAllCommands or (C_Console and C_Console.GetAllCommands)
local L = ns.L

local module = ns.NewModule("ConsoleVariables", L.CONSOLEVARIABLES_DESC, {
    enabled = false,
    -- Data, not settings: the starred CVars, by lowercase name, for the account.
    favorites = {},
})
module.title = L.CONSOLEVARIABLES_TITLE
module.category = "tools" -- off, its page and command are gone; it costs nothing until opened
module.developer = { enabled = true }
module.internal = {}
local internal = module.internal

local LIST_WIDTH = 160 -- the group list, a little narrower than the module list
local ROW_HEIGHT = 40 -- a CVar's row: its name over its help text
local HEADER_HEIGHT = 26 -- a Popular section's header
local RESET_WIDTH, VALUE_WIDTH, GAP = 78, 112, 10
local STAR_SIZE = 16 -- the Favorites star at the row's left
local TEXT_LEFT = 6 + STAR_SIZE + 6 -- the name and help, past the star
local FLASH_SECONDS = 1.5 -- a box flashes red this long when the game kept another value
local STAR_ON, STAR_OFF = "auctionhouse-icon-favorite", "auctionhouse-icon-favorite-off"

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

-- every listed CVar, sorted: { name, key (lowercase name), text (lowercase name, title, and help),
-- help, category (an Enum.ConsoleCategory value), and for a Popular one title (its plain name),
-- section (its Popular header), and popular (its place in the Popular list) }
local all
local byKey = {} -- lowercase name -> entry in `all`
local popularCount = 0 -- how many Popular CVars this client has
-- the list's groups in order, Popular, Favorites, Changed, and All first: { key, label,
-- has(entry, changed), popular (listed in Popular's order, under its headers) }
local groups

local function isFavorite(entry)
    return module.db.favorites[entry.key] == true
end
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

-- Popular, Favorites, Changed, All, then a group for each of the client's categories that has a
-- CVar, by name.
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
    groups = {}
    if popularCount > 0 then
        groups[1] = {
            key = "popular",
            label = L.CONSOLEVARIABLES_POPULAR,
            has = function(entry) return entry.popular ~= nil end,
            popular = true,
        }
    end
    local fixed = {
        { key = "favorites", label = L.CONSOLEVARIABLES_FAVORITES, has = isFavorite },
        {
            key = "changed",
            label = L.CONSOLEVARIABLES_CHANGED,
            has = function(_, changed) return changed end,
        },
        { key = "all", label = L.CONSOLEVARIABLES_ALL, has = function() return true end },
    }
    for _, group in ipairs(fixed) do
        groups[#groups + 1] = group
    end
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
                    local entry = {
                        name = name,
                        key = key,
                        help = info.help or "",
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
    -- Popular's own names and help, on the CVars this client has. One the command list leaves
    -- out but the client knows (GetCVar answers) is added; one it doesn't know is skipped.
    popularCount = 0
    for _, section in ipairs(internal.POPULAR or {}) do
        for _, item in ipairs(section) do
            local name, title, help = item[1], item[2], item[3]
            local key = strlower(name)
            local entry = byKey[key]
            if not entry and C_CVar.GetCVar(name) ~= nil and not isReadOnly(name) then
                entry = { name = name, key = key, help = "" }
                byKey[key] = entry
                all[#all + 1] = entry
            end
            if entry and not entry.popular then
                popularCount = popularCount + 1
                entry.title, entry.section, entry.popular = title, section.header, popularCount
                entry.help = help
            end
        end
    end
    for _, entry in ipairs(all) do
        entry.text = entry.key .. " " .. strlower(entry.title or "") .. " " .. strlower(entry.help)
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
    local found = #rows
    -- Popular in its own order, under a header for each section.
    if group.popular then
        sort(rows, function(a, b) return a.popular < b.popular end)
        local listed, section = {}, nil
        for _, entry in ipairs(rows) do
            if entry.section ~= section then
                section = entry.section
                listed[#listed + 1] = { header = section }
            end
            listed[#listed + 1] = entry
        end
        rows = listed
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
    if found == 0 then
        if query ~= "" then
            empty = format(L.CONSOLEVARIABLES_NO_MATCH, search)
        elseif #all == 0 then
            empty = L.CONSOLEVARIABLES_NO_LIST
        elseif group.key == "favorites" then
            empty = L.CONSOLEVARIABLES_NO_FAVORITES
        else
            empty = L.CONSOLEVARIABLES_NONE_CHANGED
        end
    end
    ui.empty:SetText(empty or "")
    ui.empty:SetShown(empty ~= nil)
end

-- Whether the game holds `value` as `wanted`: the same text, or the same number ("1.50" is 1.5).
local function holds(value, wanted)
    if value == wanted then
        return true
    end
    local a, b = tonumber(value), tonumber(wanted)
    return a ~= nil and a == b
end

local flashUntil = {} -- lowercase name -> when its box stops flashing red

local function apply(name, value)
    if InCombatLockdown() then
        ns.Print(format(L.CONSOLEVARIABLES_AFTER_COMBAT, name))
    end
    ns.CVars.Apply(name, value, function(ok)
        if not ok then
            ns.Print(format(L.CONSOLEVARIABLES_REFUSED, name))
        else
            -- Taken, but as something else: a value past its range is held at the end of it, and
            -- some CVars round. Say so, and flash the box, rather than let it snap back quietly.
            local now = read(name)
            if now ~= nil and not holds(now, value) then
                ns.Print(format(L.CONSOLEVARIABLES_KEPT, name, tostring(now), value))
                flashUntil[strlower(name)] = GetTime() + FLASH_SECONDS
                C_Timer.After(FLASH_SECONDS, function() refresh() end)
            end
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
    GameTooltip:SetText(entry.title or entry.name, 1, 1, 1)
    if entry.title then
        GameTooltip:AddLine(entry.name, unpack(ns.Colors.GRAY))
    end
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
    if row.entry then
        row.highlight:Show()
        showTooltip(row)
    end
end

local function leaveRow(row)
    row.highlight:Hide()
    GameTooltip:Hide()
end

local function paintStar(row)
    row.star:SetNormalAtlas(isFavorite(row.entry) and STAR_ON or STAR_OFF)
end

local function buildRow(row)
    row:EnableMouse(true)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.highlight:Hide()

    -- A Popular section's header; the row is one or the other, since the list pools one kind.
    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 6, 5)
    row.header:Hide()

    -- Favorites: Blizzard's auction house star, gold while the CVar is starred.
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(STAR_SIZE, STAR_SIZE)
    row.star:SetPoint("LEFT", 6, 0)
    row.star:SetHighlightAtlas(STAR_ON, "ADD")
    row.star:SetScript("OnClick", function()
        local favorites = module.db.favorites
        favorites[row.entry.key] = (not isFavorite(row.entry)) or nil
        paintStar(row)
        refresh()
    end)
    row.star:HookScript("OnEnter", function() enterRow(row) end)
    row.star:HookScript("OnLeave", function() leaveRow(row) end)

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
    row.name:SetPoint("TOPLEFT", TEXT_LEFT, -6)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -GAP - 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.help = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.help:SetPoint("TOPLEFT", TEXT_LEFT, -23)
    row.help:SetPoint("RIGHT", row.value, "LEFT", -GAP - 6, 0)
    row.help:SetJustifyH("LEFT")
    row.help:SetWordWrap(false)

    row:SetScript("OnEnter", enterRow)
    row:SetScript("OnLeave", leaveRow)
end

-- The parts of a CVar's row, hidden while the row is a header.
local function showParts(row, shown)
    row.star:SetShown(shown)
    row.value:SetShown(shown)
    row.reset:SetShown(shown)
    row.name:SetShown(shown)
    row.help:SetShown(shown)
    row.header:SetShown(not shown)
end

-- The box in red while the game has just kept another value than the one typed, else its own.
local function paintBox(row)
    local flash = (flashUntil[row.entry.key] or 0) > GetTime()
    local r, g, b = 1, 1, 1
    if flash then
        r, g, b = 1, 0.3, 0.3
    end
    row.value:SetTextColor(r, g, b)
    -- InputBoxTemplate's border, where this client's template has the parts by these keys.
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local part = row.value[key]
        if part and part.SetVertexColor then
            part:SetVertexColor(r, g, b)
        end
    end
end

local function initRow(row, entry)
    if not row.value then
        buildRow(row)
    end
    if entry.header then
        row.entry = nil
        showParts(row, false)
        row.header:SetText(entry.header)
        return
    end
    showParts(row, true)
    row.entry = entry
    paintStar(row)
    paintBox(row)
    local value, default, flags = read(entry.name)
    local changed = default ~= nil and value ~= default
    -- A Popular one by its plain name, with the CVar's own after it in gray.
    if entry.title then
        row.name:SetText(format("%s  |cff808080%s|r", entry.title, entry.name))
    else
        row.name:SetText(entry.name)
    end
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
        -- A new search looks through everything, not only the group the page opened on; the
        -- other groups' counts still say what they'd show.
        local starting = search == "" and text ~= ""
        search = text
        if starting and selected ~= "all" then
            choose("all")
        else
            refresh()
        end
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
    view:SetElementExtentCalculator(function(_, entry)
        return entry.header and HEADER_HEIGHT or ROW_HEIGHT
    end)
    view:SetElementInitializer("Frame", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, split.scrollBar, view)

    -- Opens on Favorites once the player has starred something, else on Popular (All on a client
    -- with none of Popular's CVars). Starting a search moves to All (see the search box).
    if not selected then
        selected = next(module.db.favorites) and "favorites" or (popularCount > 0 and "popular")
            or "all"
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
