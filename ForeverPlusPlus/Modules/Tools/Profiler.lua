-- Profiler: a page under Forever++ in Settings that shows how much CPU each module takes, to find
-- what needs work. Record times every call into each module's code (Lib/Profiler.lua) until Stop;
-- the list shows the heaviest modules first, with their milliseconds a second, their worst single
-- frame, and how often they ran, beside the game's own numbers for Forever++ as a whole. A module
-- with parts or named sources has the AddOn List's +/- and folds open to them (its parts, then
-- what its time went to by source: an event, a hook, an update); the heaviest module with parts
-- starts open, once. A faint bar behind each module shows its share against the heaviest. Under the list, the
-- worst frames Forever++ took too long in (spikes) say when, how long, and whose call it was.
-- Copy gives it all as one line for a bug report. Memory can only be read for the whole addon,
-- with how fast it grew while recording. Nothing is timed until Record, and nothing is built
-- until the page is first shown; `/fpp profiler` opens it. While the module is off its page and
-- command are gone and nothing is timed.
local _, ns = ...

local ipairs, format, concat, min = ipairs, string.format, table.concat, math.min
local CreateFrame, C_Timer, GameTooltip = CreateFrame, C_Timer, GameTooltip
local L = ns.L
local Profiler = ns.Profiler

local module = ns.NewModule("Profiler", L.PROFILER_DESC, { enabled = false })
module.title = L.PROFILER_TITLE
module.category = "system"
module.presets = { developer = { enabled = true } }

local ROW_HEIGHT = 22 -- a module's row
local PART_HEIGHT = 18 -- a part's row under it
local INDENT = 20 -- a part's name sits this far in from its module's
local TOGGLE = 14 -- the +/- button's size
-- Right edges of the three number columns, in from the list's right edge.
local COLUMNS = { -200, -100, -4 }
local NAME_RIGHT = -290 -- where a name stops, clear of the first column
local REFRESH = 1 -- seconds between updates while the page is open
local SPIKE_LINES = 5 -- spikes listed under the list, worst first
local SPIKES_HEIGHT = 20 + SPIKE_LINES * 14 -- their header and lines
local COPY_MODULES, COPY_SOURCES, COPY_SPIKES = 8, 3, 3 -- what Copy's line holds
local COPY_MAX = 2000 -- the copy box's letters

local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local TOGGLE_HIGHLIGHT = "Interface\\Buttons\\UI-PlusButton-Hilight"

local ui -- the page's parts, once built
local ticker
local open = setmetatable({}, { __mode = "k" }) -- module key -> true while it's unfolded
local opened = false -- the heaviest module has been opened by itself once

local function nameOf(key)
    if key == Profiler.SHARED then
        return L.PROFILER_SHARED
    end
    if key.label then
        return key.label
    end
    -- A module's part (module:NewPart): the name of its checkbox option.
    if key.module and key.key then
        for _, option in ipairs(key.module.options or {}) do
            if option.key == key.key then
                return option.name
            end
        end
        return key.key
    end
    return key.title or key.name or "?"
end

-- Whose call it was, for a spike: the module, its part after it, and the source.
local function whoOf(key, source)
    local name = nameOf(key)
    local owner = key ~= Profiler.SHARED and (key.parent or key.module)
    if owner then
        name = nameOf(owner) .. ": " .. name
    end
    if source then
        name = name .. ", " .. source
    end
    return name
end

-- Rows ------------------------------------------------------------------------------------------

local function newNumber(row, x)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", row, "RIGHT", x, 0)
    text:SetJustifyH("RIGHT")
    return text
end

local function buildRow(row)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.highlight:Hide()

    -- A module's share of the time against the heaviest's, in gold like its name, faint.
    row.bar = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.bar:SetPoint("TOPLEFT", 0, -2)
    row.bar:SetPoint("BOTTOMLEFT", 0, 2)
    row.bar:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.1)
    row.bar:Hide()

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(TOGGLE, TOGGLE)
    row.toggle:SetPoint("LEFT", 2, 0)
    row.toggle:SetHighlightTexture(TOGGLE_HIGHLIGHT, "ADD")
    row.toggle:SetScript("OnClick", function()
        row:Click()
    end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.numbers = {}
    for i, x in ipairs(COLUMNS) do
        row.numbers[i] = newNumber(row, x)
    end

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.entry and self.entry.result.counted then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.name:GetText(), 1, 1, 1)
            GameTooltip:AddLine(L.PROFILER_COUNTED, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if entry and entry.kind == "module" and (entry.result.parts or entry.result.sources) then
            local key = entry.result.key
            open[key] = not open[key] or nil
            ui.refreshList()
        end
    end)
end

-- Fills a row from its entry: { kind = "module", "part", "own", "header" (By source), or
-- "source", result, share (a module's time against the heaviest's, 0 to 1) }.
local function initRow(row, entry)
    if not row.name then
        buildRow(row)
    end
    row.entry = entry
    local result = entry.result
    local isModule = entry.kind == "module"
    row:SetHeight(isModule and ROW_HEIGHT or PART_HEIGHT)

    local share = isModule and entry.share or 0
    row.bar:SetShown(share > 0)
    if share > 0 then
        -- The list's width: a row may not be laid out yet when it's filled.
        row.bar:SetWidth(ui.scrollBox:GetWidth() * share)
    end

    if entry.kind == "header" then
        row.toggle:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", TOGGLE + 8 + INDENT, 0)
        row.name:SetFontObject("GameFontNormalSmall")
        row.name:SetText(L.PROFILER_SOURCES)
        row.name:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        for _, text in ipairs(row.numbers) do
            text:SetText("")
        end
        return
    end

    local hasParts = isModule and (result.parts ~= nil or result.sources ~= nil)
    row.toggle:SetShown(hasParts)
    if hasParts then
        local texture = open[result.key] and MINUS or PLUS
        row.toggle:SetNormalTexture(texture)
        row.toggle:SetPushedTexture(texture)
    end

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", isModule and TOGGLE + 8 or TOGGLE + 8 + INDENT, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
    -- Gold module names like Settings' labels; parts in white, and what's besides them in gray.
    row.name:SetFontObject(isModule and "GameFontNormal" or "GameFontHighlightSmall")
    row.name:SetText(entry.kind == "own" and L.PROFILER_OWN or nameOf(result.key))
    local nameColor = isModule and NORMAL_FONT_COLOR
        or entry.kind == "own" and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR
    row.name:SetTextColor(nameColor.r, nameColor.g, nameColor.b)

    local numbers = row.numbers
    if result.counted then
        numbers[1]:SetText("")
        numbers[2]:SetText("")
    else
        numbers[1]:SetText(format("%.3f", result.perSecond))
        numbers[2]:SetText(format("%.2f", result.peak))
    end
    numbers[3]:SetText(format("%.1f", result.callsPerSecond))
    local color = isModule and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
    for _, text in ipairs(numbers) do
        text:SetFontObject(isModule and "GameFontHighlight" or "GameFontHighlightSmall")
        text:SetTextColor(color.r, color.g, color.b)
    end
end

-- The list's entries: each module, and while it's unfolded its parts, what it did besides, and
-- what its time went to by source.
local function entries(results)
    local list = {}
    local heaviest = results[1] and results[1].perSecond or 0
    for _, result in ipairs(results) do
        list[#list + 1] = { kind = "module", result = result,
            share = heaviest > 0 and min(result.perSecond / heaviest, 1) or 0 }
        if open[result.key] then
            for _, part in ipairs(result.parts or {}) do
                list[#list + 1] = { kind = "part", result = part }
            end
            if result.parts and result.own then
                list[#list + 1] = { kind = "own", result = result.own }
            end
            if result.sources then
                list[#list + 1] = { kind = "header", result = result }
                for _, source in ipairs(result.sources) do
                    list[#list + 1] = { kind = "source", result = source }
                end
            end
        end
    end
    return list
end

-- The worst frames, under the list.
local function refreshSpikes()
    local spikes = Profiler.Spikes()
    for i, line in ipairs(ui.spikeLines) do
        local spike = spikes[i]
        if spike then
            local who = whoOf(spike.key, spike.source)
            if spike.combat then
                who = who .. "  |cff808080" .. L.PROFILER_SPIKE_COMBAT .. "|r"
            end
            line:SetText(format(L.PROFILER_SPIKE, ns.Text.Clock(spike.at), spike.ms, who))
        else
            line:SetText(i == 1 and L.PROFILER_NO_SPIKES or "")
        end
    end
end

-- Everything on the page as one line, for a bug report: the version and recording, each of the
-- heaviest modules with its worst frame and calls, the top sources of the first few, and the
-- worst spikes.
local function copyText()
    local results = Profiler.Results()
    local parts = { format(L.PROFILER_COPY_LINE, ns.version or "?", ns.Text.Clock(Profiler.Elapsed() or 0)) }
    for i = 1, min(#results, COPY_MODULES) do
        local result = results[i]
        local text = format("%s %.3f ms/s (worst %.1f, %.0f/s)", nameOf(result.key), result.perSecond,
            result.peak, result.callsPerSecond)
        if i <= COPY_SOURCES and result.sources then
            local named = {}
            for j = 1, min(#result.sources, COPY_SOURCES) do
                local source = result.sources[j]
                named[j] = format("%s %.3f", source.key.label, source.perSecond)
            end
            text = text .. " [" .. concat(named, ", ") .. "]"
        end
        parts[#parts + 1] = text
    end
    local spikes = Profiler.Spikes()
    for i = 1, min(#spikes, COPY_SPIKES) do
        local spike = spikes[i]
        parts[#parts + 1] = format("spike %.1f ms at %s: %s%s", spike.ms, ns.Text.Clock(spike.at),
            whoOf(spike.key, spike.source), spike.combat and " (combat)" or "")
    end
    local text = concat(parts, " | ")
    return #text > COPY_MAX and text:sub(1, COPY_MAX) or text
end

-- Page --------------------------------------------------------------------------------------------

local function refreshList()
    local results = Profiler.Results()
    -- The heaviest module with parts starts open, once, so the page shows what parts look like.
    if not opened then
        for _, result in ipairs(results) do
            if result.parts then
                open[result.key] = true
                opened = true
                break
            end
        end
    end
    ui.scrollBox:SetDataProvider(CreateDataProvider(entries(results)), ScrollBoxConstants.RetainScrollPosition)
    ui.empty:SetShown(#results == 0)
end

local function refresh()
    if not ui then
        return
    end
    local recording = Profiler.recording
    ui.record:SetText(recording and L.PROFILER_STOP or L.PROFILER_RECORD)
    local seconds = Profiler.Elapsed()
    if recording then
        ui.status:SetText(format(L.PROFILER_RECORDING, ns.Text.Clock(seconds or 0)))
    elseif seconds then
        ui.status:SetText(format(L.PROFILER_STOPPED, ns.Text.Clock(seconds)))
    else
        ui.status:SetText(L.PROFILER_IDLE)
    end

    local average, peak, memory = Profiler.AddOn()
    local parts = {}
    if average then
        parts[#parts + 1] = format(L.PROFILER_ADDON_CPU, average, peak or 0)
    end
    if memory then
        local text = format(L.PROFILER_ADDON_MEMORY, memory / 1024)
        local growth = Profiler.MemoryGrowth(memory)
        if growth then
            text = text .. " " .. format(L.PROFILER_MEMORY_GROWTH, growth)
        end
        parts[#parts + 1] = text
    end
    ui.addon:SetText(#parts > 0 and concat(parts, "  ") or "")
    refreshList()
    refreshSpikes()
end

local function startTicker()
    if not ticker then
        ticker = C_Timer.NewTicker(REFRESH, refresh)
    end
end

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function newText(parent, template, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetJustifyH("LEFT")
    return text
end

---Draws the page the first time it's shown (called by Settings/Settings.lua).
---@param frame table the empty page
function module:BuildPage(frame)
    ui = { refreshList = refreshList }
    ns.SettingsKit.AddPageTitle(frame, module.title)

    ui.reset = ns.Frames.Button(frame, L.PROFILER_RESET, 96, function()
        Profiler.Reset()
        refresh()
    end)
    ui.reset:SetPoint("TOPRIGHT", -12, -19) -- where the Defaults button would be

    ui.record = ns.Frames.Button(frame, nil, 96, function()
        if Profiler.recording then
            Profiler.Stop()
        else
            Profiler.Start()
        end
        refresh()
    end)
    ui.record:SetPoint("RIGHT", ui.reset, "LEFT", -8, 0)

    ui.copy = ns.Frames.Button(frame, L.PROFILER_COPY, 96, function()
        ns.Prompt("PROFILER_COPY", L.PROFILER_COPY_PROMPT, copyText())
    end)
    ui.copy:SetPoint("RIGHT", ui.record, "LEFT", -8, 0)

    ui.status = newText(frame, "GameFontHighlight", 10, -62)
    ui.addon = newText(frame, "GameFontHighlight", 10, -82)
    -- One line that stops at the page's edge, cut short rather than running past it.
    ui.addon:SetPoint("RIGHT", -40, 0)
    ui.addon:SetWordWrap(false)
    ui.note = newText(frame, "GameFontDisableSmall", 10, -104)
    ui.note:SetPoint("RIGHT", -40, 0)
    ui.note:SetText(L.PROFILER_NOTE)

    -- The list: a scroll box like Console Variables', its column titles just above it.
    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -158)
    scrollBox:SetPoint("BOTTOMRIGHT", -32, 8 + SPIKES_HEIGHT + 8)
    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, entry)
        return entry.kind == "module" and ROW_HEIGHT or PART_HEIGHT
    end)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    ui.scrollBox = scrollBox

    local titles = { L.PROFILER_PER_SECOND, L.PROFILER_PEAK, L.PROFILER_CALLS }
    local moduleTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moduleTitle:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", TOGGLE + 8, 4)
    moduleTitle:SetText(L.PROFILER_MODULE)
    for i, x in ipairs(COLUMNS) do
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("BOTTOMRIGHT", scrollBox, "TOPRIGHT", x, 4)
        title:SetText(titles[i])
    end

    ui.empty = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ui.empty:SetPoint("TOPLEFT", 6, -6)
    ui.empty:SetText(L.PROFILER_EMPTY)

    -- The spikes, under the list: a gold header like the columns', then a line each.
    local spikesTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spikesTitle:SetPoint("TOPLEFT", scrollBox, "BOTTOMLEFT", TOGGLE + 8, -8)
    spikesTitle:SetText(format(L.PROFILER_SPIKES, Profiler.SPIKE_MS))
    ui.spikeLines = {}
    for i = 1, SPIKE_LINES do
        local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", spikesTitle, "BOTTOMLEFT", 0, -4 - (i - 1) * 14)
        line:SetPoint("RIGHT", scrollBox, "RIGHT", 0, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        ui.spikeLines[i] = line
    end

    frame:HookScript("OnShow", function()
        refresh()
        startTicker()
    end)
    frame:HookScript("OnHide", stopTicker)
    refresh()
    if frame:IsShown() then
        startTicker()
    end
end

-- Off, nothing is timed: a recording stops (and what it found is dropped) with the page.
function module:OnDisable()
    Profiler.Stop()
    Profiler.Reset()
    stopTicker()
end

-- /fpp profiler, not /fpp profile as it was up to 1.4.0: that one is the Profiles page's now, one
-- letter from /fpp profiles.
ns.AddCommand("profiler", "", L.PROFILER_COMMAND, function()
    if not ns.OpenSettings(module.name) then
        ns.Print(L.PROFILER_NO_PAGE)
    end
end, module.name)
