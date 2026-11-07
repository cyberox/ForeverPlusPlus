-- Gathering Map's own page in Settings: every herb and vein it knows, in a list under Herbs and
-- Ore, each with a checkbox that shows or hides it on both maps for this character, its icon, the
-- skill it takes (in the trainer's colors against this character's), and how many spots of it are
-- remembered. A kind's header has its own checkbox, the same switch as the world map's filter, and
-- Show All / Hide All for its nodes. A search box narrows the list by name. Nothing here forgets a
-- node: hidden nodes are kept, for every character, and come back when shown again.
local _, ns = ...

local ipairs, pairs, sort, format, lower, find = ipairs, pairs, table.sort, string.format, string.lower,
    string.find
local CreateFrame = CreateFrame

local L = ns.L
local Kit = ns.SettingsKit
local Professions = ns.Professions

local module = ns.modules.GatheringMap
local internal = module.internal

-- The kinds the page lists, in order, with the skill line that gathers each.
local KINDS = {
    { kind = "herb", name = L.GATHERINGMAP_PAGE_HERBS, line = Professions.HERBALISM },
    { kind = "ore", name = L.GATHERINGMAP_PAGE_ORE, line = Professions.MINING },
}

local WIDTH = 560
local ROW_HEIGHT, HEADER_HEIGHT, ICON = 22, 30, 18
local SKILL_X, SPOTS_X = 300, 400 -- where a row's skill and spot count start

local ui -- the page's frames, once built
local search = "" -- the search box's text, lowered

-- Every node of each kind: the herbs and veins Lib/Professions knows, and any remembered here
-- under a name it doesn't, each as { name, skill, spots }, sorted by skill and then name.
local function collect()
    local byName = {}
    for name, node in Professions.EachNode() do
        local kind = Professions.LineKind(node[1])
        if kind == "herb" or kind == "ore" then
            byName[name] = { name = name, kind = kind, skill = node[2], spots = 0 }
        end
    end
    for _, list in pairs(module.db.nodes) do
        for _, node in ipairs(list) do
            local entry = byName[node.name]
            if not entry and (node.kind == "herb" or node.kind == "ore") then
                local known = Professions.Node(node.name)
                entry = { name = node.name, kind = node.kind, skill = known and known[2], spots = 0 }
                byName[node.name] = entry
            end
            if entry then
                entry.spots = entry.spots + 1
            end
        end
    end
    local lists = { herb = {}, ore = {} }
    for _, entry in pairs(byName) do
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
    return lists
end

local function matches(name)
    return search == "" or find(lower(name), search, 1, true) ~= nil
end

local refresh

-- Rows ----------------------------------------------------------------------------------------------

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

local function newRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH, ROW_HEIGHT)
    row.box = Kit.NewCheckbox(row, 22, function(checked)
        module.db.hidden[row.entry.name] = not checked or nil
        internal.Changed(nil)
    end)
    row.box:SetPoint("LEFT", 12, 0)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
    local mask = row:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    row.icon = icon
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    row.skill = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.skill:SetPoint("LEFT", SKILL_X, 0)
    row.spots = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.spots:SetPoint("LEFT", SPOTS_X, 0)
    return row
end

-- Fills a row for `entry`: checked while it's shown, greyed while its kind is off.
local function fillRow(row, entry, kindOn, line)
    row.entry = entry
    row.box:SetChecked(not module.db.hidden[entry.name])
    row.box:SetEnabled(kindOn)
    setIcon(row.icon, entry)
    row.icon:SetDesaturated(not kindOn)
    row.name:SetText(entry.name)
    row.name:SetFontObject(kindOn and "GameFontHighlight" or "GameFontDisable")
    if entry.skill then
        local color = Professions.Difficulty(Professions.Rank(line), entry.skill)
        row.skill:SetText(entry.skill)
        row.skill:SetTextColor(color.r, color.g, color.b)
    else
        row.skill:SetText("")
    end
    row.spots:SetText(entry.spots == 0 and L.GATHERINGMAP_PAGE_NONE
        or entry.spots == 1 and L.GATHERINGMAP_PAGE_ONE_SPOT
        or format(L.GATHERINGMAP_PAGE_SPOTS, entry.spots))
end

-- A kind's header: its checkbox and name, the column names, and Show All / Hide All.
local function newHeader(parent, kind)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(WIDTH, HEADER_HEIGHT)
    header.box = Kit.NewCheckbox(header, 24, function(checked)
        module.db.hiddenKinds[kind.kind] = not checked or nil
        internal.Changed(nil)
        refresh()
    end)
    header.box:SetPoint("BOTTOMLEFT", 0, 2)
    Kit.AddTooltip(header.box, kind.name, L.GATHERINGMAP_PAGE_KIND_DESC)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", header.box, "RIGHT", 4, 0)
    label:SetText(kind.name)
    local skill = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skill:SetPoint("LEFT", SKILL_X, -4)
    skill:SetText(L.GATHERINGMAP_PAGE_SKILL)
    local spots = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spots:SetPoint("LEFT", SPOTS_X, -4)
    spots:SetText(L.GATHERINGMAP_PAGE_REMEMBERED)
    -- Show All / Hide All: every node of the kind the list shows (the search narrows it).
    local function setAll(shown)
        for _, row in ipairs(ui.rows[kind.kind]) do
            if row:IsShown() and row.entry then
                module.db.hidden[row.entry.name] = not shown or nil
            end
        end
        internal.Changed(nil)
        refresh()
    end
    header.hideAll = Kit.NewButton(header, L.GATHERINGMAP_PAGE_HIDE_ALL, 90, function()
        setAll(false)
    end)
    header.hideAll:SetPoint("BOTTOMRIGHT", 0, 2)
    header.showAll = Kit.NewButton(header, L.GATHERINGMAP_PAGE_SHOW_ALL, 90, function()
        setAll(true)
    end)
    header.showAll:SetPoint("RIGHT", header.hideAll, "LEFT", -6, 0)
    return header
end

-- Refreshing ---------------------------------------------------------------------------------------

-- Lists every node again: the kinds' headers and a row for each node the search shows. Rows are
-- made as needed and kept.
function refresh()
    if not ui then
        return
    end
    local lists = collect()
    local stack = ui.content
    stack.entries = {}
    for _, kind in ipairs(KINDS) do
        local kindOn = not module.db.hiddenKinds[kind.kind]
        local header = ui.headers[kind.kind]
        header.box:SetChecked(kindOn)
        header.showAll:SetEnabled(kindOn)
        header.hideAll:SetEnabled(kindOn)
        local rows = ui.rows[kind.kind]
        local shown = 0
        local any = false
        for _, entry in ipairs(lists[kind.kind]) do
            if matches(entry.name) then
                shown = shown + 1
                local row = rows[shown]
                if not row then
                    row = newRow(stack)
                    rows[shown] = row
                end
                fillRow(row, entry, kindOn, kind.line)
                any = true
            end
        end
        for i = shown + 1, #rows do
            rows[i]:Hide()
            rows[i].entry = nil
        end
        Kit.AddEntry(stack, header, function()
            return any
        end, 14)
        for i = 1, shown do
            Kit.AddEntry(stack, rows[i])
        end
    end
    -- Rows past the ones listed stay hidden: Layout only places the stack's entries.
    Kit.Layout(stack)
    ui.empty:SetShown(#stack.entries == #KINDS and true or false)
end

-- The page -------------------------------------------------------------------------------------------

function module:BuildPage(frame)
    ui = { headers = {}, rows = {} }
    Kit.AddPageTitle(frame, module.pageTitle)
    Kit.AddSearchBox(frame, nil, L.GATHERINGMAP_PAGE_SEARCH, function(text)
        search = lower(text)
        refresh()
    end)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 10, -64)
    note:SetPoint("RIGHT", -40, 0)
    note:SetJustifyH("LEFT")
    note:SetText(L.GATHERINGMAP_PAGE_NOTE)

    local scroll = Kit.NewScroll(frame)
    scroll:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -6, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    ui.content = Kit.NewStack(scroll, WIDTH, 0)
    scroll:SetScrollChild(ui.content)

    for _, kind in ipairs(KINDS) do
        ui.headers[kind.kind] = newHeader(ui.content, kind)
        ui.rows[kind.kind] = {}
    end

    ui.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ui.empty:SetPoint("TOP", scroll, "TOP", 0, -20)
    ui.empty:SetText(L.GATHERINGMAP_PAGE_EMPTY)

    frame:HookScript("OnShow", refresh)
    refresh()
end
