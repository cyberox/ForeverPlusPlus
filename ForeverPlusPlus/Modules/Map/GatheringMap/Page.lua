-- Gathering Map's own page in Settings, laid out like the Modules and Console Variables pages: a
-- list on the left and the selected entry on the right, each scrolling on its own.
--
-- The list has a header for Herbs and for Ore that folds its nodes away, with the kind's checkbox
-- (the same switch as the world map's filter). Under each header is a row for every herb or vein:
-- its checkbox, which shows or hides it on both maps for this character, its icon, and how many
-- spots are remembered. Selecting a node shows its skill, how often and how lately it was
-- gathered, the zones its spots are in, and a button that forgets them. Selecting a kind shows
-- Show All and Hide All for its nodes. The search box narrows the list by name.
--
-- Hiding forgets nothing: hidden nodes are kept, for every character, and come back when shown.
local _, ns = ...

local ipairs, pairs, sort, format, lower, find, time = ipairs, pairs, table.sort, string.format,
    string.lower, string.find, time
local CreateFrame = CreateFrame

local L = ns.L
local Kit = ns.SettingsKit
local Professions = ns.Professions

local module = ns.modules.GatheringMap
local internal = module.internal

-- The kinds the page lists, in order.
local KINDS = {
    { kind = "herb", name = L.GATHERINGMAP_PAGE_HERBS },
    { kind = "ore", name = L.GATHERINGMAP_PAGE_ORE },
}

local LIST_WIDTH = 210 -- wider than the Modules page's list, for names like Ooze Covered Mithril
local ICON, INDENT = 14, 14 -- a node row's icon, and how far node rows sit in from their header
local BIG_ICON = 36 -- the selected node's icon
local ZONE_ROW = 18

local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local ui -- the page's frames, once built
local search = "" -- the search box's text, lowered
local selected -- { kind = "herb" } or { name = "Peacebloom" }
local folded = {} -- kind -> true while its nodes are folded away (for this session)
local entries = {} -- node name -> its entry, from the last collect()

-- Data ------------------------------------------------------------------------------------------

-- Every node of each kind: the herbs and veins Lib/Professions knows, and any remembered under a
-- name it doesn't, each as { name, kind, skill, spots, gathers, last, zones }, where zones is a
-- list of { mapID, spots, last }. Sorted by skill and then name.
local function collect()
    local byName = {}
    for name, node in Professions.EachNode() do
        local kind = Professions.LineKind(node[1])
        if kind == "herb" or kind == "ore" then
            byName[name] = { name = name, kind = kind, skill = node[2], spots = 0, gathers = 0,
                zones = {} }
        end
    end
    for mapID, list in pairs(module.db.nodes) do
        for _, node in ipairs(list) do
            local entry = byName[node.name]
            if not entry and (node.kind == "herb" or node.kind == "ore") then
                local known = Professions.Node(node.name)
                entry = { name = node.name, kind = node.kind, skill = known and known[2], spots = 0,
                    gathers = 0, zones = {} }
                byName[node.name] = entry
            end
            if entry then
                entry.spots = entry.spots + 1
                entry.gathers = entry.gathers + (node.count or 0)
                if node.time and (not entry.last or node.time > entry.last) then
                    entry.last = node.time
                end
                local zone = entry.zones[mapID]
                if not zone then
                    zone = { mapID = mapID, spots = 0 }
                    entry.zones[mapID] = zone
                end
                zone.spots = zone.spots + 1
                if node.time and (not zone.last or node.time > zone.last) then
                    zone.last = node.time
                end
            end
        end
    end
    local lists = { herb = {}, ore = {} }
    for _, entry in pairs(byName) do
        local zones = {}
        for _, zone in pairs(entry.zones) do
            zones[#zones + 1] = zone
        end
        sort(zones, function(a, b)
            if a.spots ~= b.spots then
                return a.spots > b.spots
            end
            return a.mapID < b.mapID
        end)
        entry.zones = zones
        local list = lists[entry.kind]
        list[#list + 1] = entry
    end
    for _, list in pairs(lists) do
        sort(list, function(a, b)
            if (a.skill or 0) ~= (b.skill or 0) then
                return (a.skill or 0) < (b.skill or 0)
            end
            return a.name < b.name
        end)
    end
    entries = byName
    return lists
end

local function matches(name)
    return search == "" or find(lower(name), search, 1, true) ~= nil
end

local function spotsText(spots)
    return spots == 0 and L.GATHERINGMAP_PAGE_NONE
        or spots == 1 and L.GATHERINGMAP_PAGE_ONE_SPOT
        or format(L.GATHERINGMAP_PAGE_SPOTS, spots)
end

-- Forgets every remembered spot of the node `name`, in every zone.
local function forgetName(name)
    local nodes = module.db.nodes
    local forgot = 0
    for mapID, list in pairs(nodes) do
        for i = #list, 1, -1 do
            if list[i].name == name then
                table.remove(list, i)
                forgot = forgot + 1
            end
        end
        if #list == 0 then
            nodes[mapID] = nil
        end
    end
    ns.Print(format(L.GATHERINGMAP_FORGOT, forgot))
    internal.Changed(nil)
end

local refresh

local function choose(choice)
    selected = choice
    refresh()
end

local function isSelected(row)
    local entry = row.entry
    if not (entry and selected) then
        return false
    end
    if row.isHeader then
        return selected.kind == entry.kind and not selected.name
    end
    return selected.name == entry.name
end

-- Art -------------------------------------------------------------------------------------------

local function newRoundIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    return icon
end

-- The node's item's icon, or a circle in its kind's color, as the maps draw it.
local function setIcon(texture, entry)
    local icon = internal.ItemIcon({ name = entry.name })
    if icon then
        texture:SetTexture(icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        texture:SetVertexColor(1, 1, 1)
    else
        local color = internal.COLORS[entry.kind]
        texture:SetTexture(internal.CIRCLE)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(color[1], color[2], color[3])
    end
end

-- A checkbox in a list row lights the row while the mouse is over it, as the row itself does.
local function hoverWith(box, row)
    box:HookScript("OnEnter", function() Kit.Hover(row, true) end)
    box:HookScript("OnLeave", function() Kit.Hover(row, false) end)
end

-- List rows -------------------------------------------------------------------------------------

-- A kind's header: the fold button, its checkbox, its name in gold, and how many nodes it lists.
local function newHeader(list, kind)
    local row
    row = Kit.NewListButton(list, function() return isSelected(row) end)
    row.isHeader, row.entry = true, kind
    row.fold = row:CreateTexture(nil, "ARTWORK")
    row.fold:SetSize(14, 14)
    row.fold:SetPoint("LEFT", 4, 0)
    row.box = Kit.NewCheckbox(row, 18, function(checked)
        module.db.hiddenKinds[kind.kind] = not checked or nil
        internal.Changed(nil)
    end)
    row.box:SetPoint("LEFT", row.fold, "RIGHT", 2, 0)
    hoverWith(row.box, row)
    Kit.AddTooltip(row.box, kind.name, L.GATHERINGMAP_PAGE_KIND_DESC)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.box, "RIGHT", 2, 0)
    row.text:SetText(kind.name)
    -- Clicking a header folds or unfolds it and shows the kind on the right.
    row:SetScript("OnClick", function()
        if search == "" then
            folded[kind.kind] = not folded[kind.kind] or nil
        end
        choose({ kind = kind.kind })
    end)
    return row
end

-- A node's row: its checkbox, icon, name, and spots remembered.
local function newNodeRow(list)
    local row
    row = Kit.NewListButton(list, function() return isSelected(row) end)
    row.box = Kit.NewCheckbox(row, 18, function(checked)
        module.db.hidden[row.entry.name] = not checked or nil
        internal.Changed(nil)
    end)
    row.box:SetPoint("LEFT", INDENT + 4, 0)
    hoverWith(row.box, row)
    row.icon = newRoundIcon(row, ICON)
    row.icon:SetPoint("LEFT", row.box, "RIGHT", 2, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function()
        choose({ name = row.entry.name })
    end)
    return row
end

local function fillNodeRow(row, entry, kindOn)
    row.entry = entry
    row.box:SetChecked(not module.db.hidden[entry.name])
    row.box:SetEnabled(kindOn)
    setIcon(row.icon, entry)
    row.icon:SetDesaturated(not kindOn)
    row.text:SetText(entry.name)
    local shown = kindOn and not module.db.hidden[entry.name]
    row.text:SetFontObject(shown and "GameFontHighlight" or "GameFontDisable")
    row.count:SetText(entry.spots > 0 and entry.spots or "")
end

-- The selected node -----------------------------------------------------------------------------

-- A label at the left and its value at the right edge, like the tooltips' Gathered and Last lines.
local function newPair(parent, width)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(width, ZONE_ROW)
    line.label = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.label:SetPoint("LEFT")
    line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.value:SetPoint("RIGHT")
    line.label:SetPoint("RIGHT", line.value, "LEFT", -8, 0)
    line.label:SetJustifyH("LEFT")
    line.label:SetWordWrap(false)
    return line
end

local function newNodeView(parent, width)
    local view = CreateFrame("Frame", nil, parent)
    view:SetWidth(width)
    view.stack = Kit.NewStack(view, width, 4)
    view.stack:SetPoint("TOPLEFT")

    local top = CreateFrame("Frame", nil, view.stack)
    top:SetSize(width, BIG_ICON + 4)
    view.icon = newRoundIcon(top, BIG_ICON)
    view.icon:SetPoint("TOPLEFT", 0, -2)
    view.title = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", view.icon, "TOPRIGHT", 8, -2)
    view.title:SetPoint("RIGHT")
    view.title:SetJustifyH("LEFT")
    view.requires = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.requires:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -4)
    view.top = top

    -- Shown on Maps: the same switch as the node's checkbox in the list.
    local show = CreateFrame("Frame", nil, view.stack)
    show:SetSize(width, 24)
    view.show = Kit.NewCheckbox(show, 22, function(checked)
        if view.entry then
            module.db.hidden[view.entry.name] = not checked or nil
            internal.Changed(nil)
        end
    end)
    view.show:SetPoint("LEFT", -2, 0)
    local label = show:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", view.show, "RIGHT", 2, 0)
    label:SetText(L.GATHERINGMAP_PAGE_SHOW)
    view.show:SetHitRectInsets(0, -(ns.Text.Width(label) + 2), 0, 0)
    view.showRow = show

    view.gathered = newPair(view.stack, width)
    view.gathered.label:SetText(L.GATHERINGMAP_TIP_GATHERED)
    view.last = newPair(view.stack, width)
    view.last.label:SetText(L.GATHERINGMAP_TIP_LAST)

    view.zonesHeader = CreateFrame("Frame", nil, view.stack)
    view.zonesHeader:SetSize(width, 22)
    local zonesLabel = view.zonesHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zonesLabel:SetPoint("BOTTOMLEFT", 0, 2)
    zonesLabel:SetText(L.GATHERINGMAP_PAGE_ZONES)
    view.zones = {}

    view.none = CreateFrame("Frame", nil, view.stack)
    view.none:SetSize(width, ZONE_ROW)
    local none = view.none:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    none:SetPoint("LEFT")
    none:SetText(L.GATHERINGMAP_PAGE_NONE)

    view.buttons = CreateFrame("Frame", nil, view.stack)
    view.buttons:SetSize(width, 26)
    view.forget = Kit.NewButton(view.buttons, L.GATHERINGMAP_PAGE_FORGET, 130, function()
        local entry = view.entry
        if entry then
            ns.Confirm("GATHERINGMAP_FORGET_NODE", L.GATHERINGMAP_PAGE_FORGET_CONFIRM, function()
                forgetName(entry.name)
            end, entry.name)
        end
    end)
    view.forget:SetPoint("BOTTOMLEFT", 0, 0)
    return view
end

local function fillNodeView(view, entry)
    view.entry = entry
    local kindOn = not module.db.hiddenKinds[entry.kind]
    setIcon(view.icon, entry)
    view.title:SetText(entry.name)
    local requires = internal.Requires({ name = entry.name })
    if requires then
        view.requires:SetText(requires[1])
        local color = requires[2]
        view.requires:SetTextColor(color.r, color.g, color.b)
    else
        view.requires:SetText("")
    end
    view.show:SetChecked(not module.db.hidden[entry.name])
    view.show:SetEnabled(kindOn)

    local stack = view.stack
    stack.entries = {}
    Kit.AddEntry(stack, view.top)
    Kit.AddEntry(stack, view.showRow, nil, 8)
    if entry.gathers > 0 then
        view.gathered.value:SetText(entry.gathers == 1 and L.GATHERINGMAP_TIP_ONCE
            or format(L.GATHERINGMAP_TIP_TIMES, entry.gathers))
        Kit.AddEntry(stack, view.gathered, nil, 8)
    else
        view.gathered:Hide()
    end
    if entry.last then
        view.last.value:SetText(ns.Text.Ago(time() - entry.last))
        Kit.AddEntry(stack, view.last, nil, 0)
    else
        view.last:Hide()
    end
    Kit.AddEntry(stack, view.zonesHeader, nil, 10)
    for i, zone in ipairs(entry.zones) do
        local line = view.zones[i]
        if not line then
            line = newPair(stack, stack:GetWidth())
            view.zones[i] = line
        end
        line.label:SetText(ns.WorldMap.MapName(zone.mapID, tostring(zone.mapID)))
        line.value:SetText(spotsText(zone.spots))
        Kit.AddEntry(stack, line, nil, 0)
    end
    for i = #entry.zones + 1, #view.zones do
        view.zones[i]:Hide()
    end
    -- Nothing to forget until a spot is remembered.
    if #entry.zones == 0 then
        Kit.AddEntry(stack, view.none, nil, 0)
        view.buttons:Hide()
    else
        view.none:Hide()
        Kit.AddEntry(stack, view.buttons, nil, 12)
    end
    Kit.Layout(stack)
    view:SetHeight(stack:GetHeight())
end

-- The selected kind -----------------------------------------------------------------------------

local function newKindView(parent, width)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(width, 260)
    view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", 0, -4)
    view.summary = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.summary:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -8)

    view.show = Kit.NewCheckbox(view, 22, function(checked)
        module.db.hiddenKinds[view.kind] = not checked or nil
        internal.Changed(nil)
    end)
    view.show:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", -2, -10)
    local label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", view.show, "RIGHT", 2, 0)
    label:SetText(L.GATHERINGMAP_PAGE_SHOW)
    view.show:SetHitRectInsets(0, -(ns.Text.Width(label) + 2), 0, 0)
    Kit.AddTooltip(view.show, L.GATHERINGMAP_PAGE_SHOW, L.GATHERINGMAP_PAGE_KIND_DESC)

    -- Show All / Hide All: every node of the kind the list shows (the search narrows it).
    local function setAll(shown)
        for _, entry in ipairs(view.listed or {}) do
            module.db.hidden[entry.name] = not shown or nil
        end
        internal.Changed(nil)
    end
    view.showAll = Kit.NewButton(view, L.GATHERINGMAP_PAGE_SHOW_ALL, 110, function()
        setAll(true)
    end)
    view.showAll:SetPoint("TOPLEFT", view.show, "BOTTOMLEFT", 2, -10)
    view.hideAll = Kit.NewButton(view, L.GATHERINGMAP_PAGE_HIDE_ALL, 110, function()
        setAll(false)
    end)
    view.hideAll:SetPoint("LEFT", view.showAll, "RIGHT", 8, 0)

    view.note = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.note:SetPoint("TOPLEFT", view.showAll, "BOTTOMLEFT", 0, -16)
    view.note:SetWidth(width)
    view.note:SetJustifyH("LEFT")
    view.note:SetText(L.GATHERINGMAP_PAGE_NOTE)
    return view
end

local function fillKindView(view, kind, list, listed)
    view.kind, view.listed = kind.kind, listed
    local kindOn = not module.db.hiddenKinds[kind.kind]
    view.title:SetText(kind.name)
    local spots = 0
    for _, entry in ipairs(list) do
        spots = spots + entry.spots
    end
    view.summary:SetText(format(L.GATHERINGMAP_PAGE_SUMMARY, #list, spots))
    view.show:SetChecked(kindOn)
    view.showAll:SetEnabled(kindOn)
    view.hideAll:SetEnabled(kindOn)
end

-- Refreshing ------------------------------------------------------------------------------------

-- Lists every node again: the kinds' headers and, unless folded, a row for each node the search
-- shows; then the selected node or kind on the right. Rows are made as needed and kept.
function refresh()
    if not ui then
        return
    end
    local lists = collect()
    local stack = ui.list
    stack.entries = {}
    local used, any = 0, false
    local listedByKind = {}
    for index, kind in ipairs(KINDS) do
        local kindOn = not module.db.hiddenKinds[kind.kind]
        local header = ui.headers[kind.kind]
        local listed = {}
        for _, entry in ipairs(lists[kind.kind]) do
            if matches(entry.name) then
                listed[#listed + 1] = entry
            end
        end
        listedByKind[kind.kind] = listed
        -- A search shows every kind open, and only kinds it finds something in.
        local open = search ~= "" or not folded[kind.kind]
        if search == "" or #listed > 0 then
            header.box:SetChecked(kindOn)
            header.fold:SetTexture(open and MINUS or PLUS)
            header.count:SetText(#listed)
            Kit.AddEntry(stack, header, nil, index > 1 and 8 or nil)
            any = any or #listed > 0
            if open then
                for _, entry in ipairs(listed) do
                    used = used + 1
                    local row = ui.rows[used]
                    if not row then
                        row = newNodeRow(stack)
                        ui.rows[used] = row
                    end
                    fillNodeRow(row, entry, kindOn)
                    Kit.AddEntry(stack, row)
                end
            end
        else
            header:Hide()
        end
    end
    for i = used + 1, #ui.rows do
        ui.rows[i]:Hide()
        ui.rows[i].entry = nil
    end
    if not any and search ~= "" then
        Kit.AddEntry(stack, ui.empty)
    else
        ui.empty:Hide()
    end
    Kit.Layout(stack)
    for _, row in ipairs(ui.rows) do
        Kit.Paint(row)
    end
    for _, header in pairs(ui.headers) do
        Kit.Paint(header)
    end

    -- The right side: the selected node, or its kind, or Herbs.
    local entry = selected and selected.name and entries[selected.name]
    if entry then
        ui.kindView:Hide()
        fillNodeView(ui.nodeView, entry)
        ui.nodeView:Show()
        ui.content:SetHeight(ui.nodeView:GetHeight())
    else
        local kindKey = selected and selected.kind or KINDS[1].kind
        for _, kind in ipairs(KINDS) do
            if kind.kind == kindKey then
                fillKindView(ui.kindView, kind, lists[kind.kind], listedByKind[kind.kind])
            end
        end
        ui.nodeView:Hide()
        ui.kindView:Show()
        ui.content:SetHeight(ui.kindView:GetHeight())
    end
end

-- The page --------------------------------------------------------------------------------------

function module:BuildPage(frame)
    ui = { headers = {}, rows = {}, frame = frame }
    Kit.AddPageTitle(frame, module.pageTitle)
    Kit.AddSearchBox(frame, nil, L.GATHERINGMAP_PAGE_SEARCH, function(text)
        search = lower(text)
        refresh()
    end)

    local split = Kit.NewSplit(frame, LIST_WIDTH)
    ui.list = split.list
    for _, kind in ipairs(KINDS) do
        ui.headers[kind.kind] = newHeader(split.list, kind)
    end
    ui.empty = Kit.NewEmptyRow(split.list, LIST_WIDTH)
    ui.empty.text:SetText(L.GATHERINGMAP_PAGE_EMPTY)

    ui.content = split.paneContent
    ui.nodeView = newNodeView(ui.content, split.paneWidth)
    ui.nodeView:SetPoint("TOPLEFT")
    ui.kindView = newKindView(ui.content, split.paneWidth)
    ui.kindView:SetPoint("TOPLEFT")

    -- Kept up to date while the page is open: a gather, a forget, or the map's filter.
    internal.OnChanged(function()
        if frame:IsVisible() then
            refresh()
        end
    end)
    frame:HookScript("OnShow", refresh)
    refresh()
end
