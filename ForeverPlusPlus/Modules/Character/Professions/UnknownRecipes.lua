-- Professions' Unknown Recipes: the recipes of the open profession the character doesn't know yet,
-- in a panel beside the professions window, opened with a button by its skill bar. Each shows the
-- skill it takes to learn, colored by whether that's now, soon, or later, and the item that
-- teaches it, with its auction price and whether it's in the bags.
--
-- Blizzard's window can't list them on Forever: its Camelot file (Blizzard_ProfessionsTemplates,
-- Camelot/Blizzard_Professions.lua, Gethe forever branch) makes GetDefaultShowUnlearned false,
-- turns Show Unlearned off again every time the list is built, and leaves the Learned and
-- Unlearned checkboxes out of the filter menu. So this lists them itself, from the game's tables
-- (Data.lua, made by tools/datagen): every recipe with its skill line, its spell, and the item that
-- teaches it with that item's required skill. A recipe no item teaches comes from a trainer or
-- elsewhere, and the tables don't say what skill it takes. Where the game lists a recipe as not
-- learned itself, its source text (GetRecipeSourceText) is shown; a later source, such as
-- QuestieDB's, goes in the same `source` field.
--
-- It changes nothing of Blizzard's: the button and the panel are our own frames on the crafting
-- page, made the first time the window opens with the part on.
local _, ns = ...

local _G, ipairs, type, format, pcall, select = _G, ipairs, type, string.format, pcall, select
local setmetatable = setmetatable
local CreateFrame, GameTooltip = CreateFrame, GameTooltip
local C_TradeSkillUI, C_Spell, C_Item, C_TooltipInfo = C_TradeSkillUI, C_Spell, C_Item, C_TooltipInfo

local L = ns.L
local Frames = ns.Frames
local Professions = ns.Professions -- ours; Blizzard's global of the same name is _G.Professions

local professions = ns.modules.Professions
local internal = professions.internal
local module = professions:NewPart({
    key = "unknownRecipes", name = L.PROFESSIONS_UNKNOWN, description = L.PROFESSIONS_UNKNOWN_DESC,
    section = L.PROFESSIONS_UNKNOWN, added = "1.6.0",
}, {
    unknownSoon = 25, -- how many skill points away a recipe counts as soon
    unknownNoItem = true, -- list recipes no item teaches (trainers and the like) too
    unknownWindow = {}, -- data: { open = true } while the panel is left open
})

module:AddOptions({
    {
        key = "unknownSoon", name = L.PROFESSIONS_UNKNOWN_SOON, description = L.PROFESSIONS_UNKNOWN_SOON_DESC,
        min = 5, max = 75, step = 5, format = "%d",
    },
    { key = "unknownNoItem", name = L.PROFESSIONS_UNKNOWN_NOITEM, description = L.PROFESSIONS_UNKNOWN_NOITEM_DESC },
})

-- What can be learned when, said once on the Modules page while the part is on.
professions.notice[#professions.notice + 1] = {
    text = L.PROFESSIONS_UNKNOWN_LIMITS,
    description = L.PROFESSIONS_UNKNOWN_LIMITS_DESC,
    shown = function()
        return ns.PartOn(professions, "unknownRecipes")
    end,
}

-- The list ------------------------------------------------------------------------------------------

local learnCache = {} -- item ID -> the skill its tooltip's "Requires Blacksmithing (125)" line gives
local iconCache = {} -- spell ID -> the icon of what it makes, or of the spell

-- The skill an item without one in the tables needs, from its tooltip. Nil until the item's data
-- has loaded; asked again on the next refresh then.
local function learnOf(item)
    local cached = learnCache[item]
    if cached then
        return cached
    end
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(item)
    local _, rank = ns.GameData.TooltipRequires(data)
    if rank then
        learnCache[item] = rank
    elseif C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(item)
    end
    return rank
end

local function nameOf(spell)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
    if ns.IsText(name) and name ~= "" then
        return name
    end
end

-- Whether the open list is one of the player's own professions, with skill-ups, not a link or a
-- guild's list. Probe: IsTradeSkillLinked is Mainline's.
local function ownList()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and internal.ListHasSkillUps()) then
        return false
    end
    return not (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
end

-- The open profession's skill line, from the first known recipe the tables have, or nil. Cheap:
-- it stops at the first, so the button can ask on every list update.
local function openLine()
    local data = internal.recipes
    if not (data and ownList()) then
        return nil
    end
    local T = C_TradeSkillUI
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        local entry = info and info.learned and data[info.skillLineAbilityID]
        if entry then
            return entry[3]
        end
    end
end

-- Everything about the open profession's unknown recipes: { line, skill, max, list, counts }, or
-- nil when the open list isn't one.
local function scan()
    local data = internal.recipes
    if not (data and ownList()) then
        return nil
    end
    local T = C_TradeSkillUI
    local known, knownNames, abilities = {}, {}, {}
    local sources = {} -- ability -> recipe ID, for those the game lists as not learned
    local someRecipe
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        local ability = info and info.skillLineAbilityID
        if ability then
            if info.learned then
                known[ability] = true
                abilities[#abilities + 1] = ability
                someRecipe = someRecipe or id
                if ns.IsText(info.name) then
                    knownNames[info.name] = true
                end
            else
                sources[ability] = id
            end
        end
    end
    local line = Professions.LineOfAbilities(data, abilities)
    if not line then
        return nil
    end
    local skill, max = Professions.Progress(line)
    if not skill and someRecipe then
        skill = internal.SkillOf(someRecipe)
    end
    local db = module.db
    local list = Professions.UnknownRecipes(data, line, known, knownNames, nameOf, {
        skill = skill, max = max, soon = db.unknownSoon, noItems = db.unknownNoItem, learnOf = learnOf,
    })
    local counts = {}
    for _, recipe in ipairs(list) do
        counts[recipe.state] = (counts[recipe.state] or 0) + 1
        local id = sources[recipe.ability]
        if id and T.GetRecipeSourceText then
            local ok, text = pcall(T.GetRecipeSourceText, id)
            if ok and ns.IsText(text) and text ~= "" then
                recipe.source = text
            end
        end
    end
    return { line = line, skill = skill, max = max, list = list, counts = counts }
end

-- Looks ------------------------------------------------------------------------------------------

local function stateColor(state)
    if state == "now" then
        return GREEN_FONT_COLOR or CreateColor(0.1, 1, 0.1)
    elseif state == "soon" then
        return YELLOW_FONT_COLOR or CreateColor(1, 1, 0)
    elseif state == "later" or state == "rank" then
        return RED_FONT_COLOR or CreateColor(1, 0.1, 0.1)
    end
    return GRAY_FONT_COLOR or CreateColor(0.5, 0.5, 0.5)
end

local HEADERS = {
    now = L.PROFESSIONS_UNKNOWN_NOW, soon = L.PROFESSIONS_UNKNOWN_SOON_HEADER,
    later = L.PROFESSIONS_UNKNOWN_LATER, rank = L.PROFESSIONS_UNKNOWN_RANK,
    unknown = L.PROFESSIONS_UNKNOWN_UNSURE, noitem = L.PROFESSIONS_UNKNOWN_NOITEM_HEADER,
}

-- The icon of what a recipe makes, else of the item that teaches it, else of its spell. Probe:
-- GetRecipeSchematic is Mainline's; whether it answers for a recipe not learned is Unverified.
local function iconOf(recipe)
    local icon = iconCache[recipe.spell]
    if icon then
        return icon
    end
    local T = C_TradeSkillUI
    if T and T.GetRecipeSchematic then
        local ok, schematic = pcall(T.GetRecipeSchematic, recipe.spell, false)
        local output = ok and type(schematic) == "table" and schematic.outputItemID
        if type(output) == "number" and output > 0 then
            icon = C_Item.GetItemIconByID(output)
        end
    end
    if not icon and recipe.item then
        icon = C_Item.GetItemIconByID(recipe.item)
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(recipe.spell)
    end
    icon = icon or 134400 -- the question mark
    iconCache[recipe.spell] = icon
    return icon
end

-- The item's name in its quality's color, or nil before its data has loaded.
local function itemText(item)
    local name = C_Item.GetItemNameByID(item)
    if not ns.IsText(name) then
        C_Item.RequestLoadItemDataByID(item)
        return nil
    end
    local quality = C_Item.GetItemQualityByID(item)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then
        return color.hex .. name .. "|r"
    end
    return name
end

-- The panel ----------------------------------------------------------------------------------------

local PANEL_WIDTH = 360
local ROW_HEIGHT, HEADER_HEIGHT = 40, 24
local ICON_SIZE = 32
-- Forever's professions window has its profession tabs down its right side, the first 60 below
-- its top (Blizzard_Professions, Camelot/Blizzard_ProfessionsFrame.xml): the panel goes past them.
local TAB_Y = 60

local button, panel
local shown -- what the panel shows: scan()'s result
local refreshSoon

local function insertLink(link)
    local util = _G.ChatFrameUtil
    local insert = util and util.InsertLink or _G.ChatEdit_InsertLink
    if link and insert then
        insert(link)
    end
end

local function onRowClick(row)
    local recipe = row.recipe
    if not (recipe and IsModifiedClick and IsModifiedClick("CHATLINK")) then
        return
    end
    if recipe.item then
        local _, link = C_Item.GetItemInfo(recipe.item)
        insertLink(link)
    elseif C_Spell and C_Spell.GetSpellLink then
        insertLink(C_Spell.GetSpellLink(recipe.spell))
    end
end

local function onRowEnter(row)
    local recipe = row.recipe
    if not recipe then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if recipe.item then
        GameTooltip:SetItemByID(recipe.item)
    else
        GameTooltip:SetSpellByID(recipe.spell)
    end
    GameTooltip:AddLine(" ")
    local color = stateColor(recipe.state)
    if recipe.learn then
        GameTooltip:AddDoubleLine(L.PROFESSIONS_UNKNOWN_LEARN, recipe.learn, 1, 1, 1, color:GetRGB())
    end
    local colors = internal.DifficultyColors()
    local D = Professions.DIFFICULTY
    local levels = Professions.RecipeLevels(recipe.yellow, recipe.gray)
    if levels and colors then
        local r, g, b = colors[D.MEDIUM]:GetRGB()
        GameTooltip:AddDoubleLine(L.PROFESSIONS_BAR_YELLOW, levels.yellow, r, g, b, 1, 1, 1)
        r, g, b = colors[D.TRIVIAL]:GetRGB()
        GameTooltip:AddDoubleLine(L.PROFESSIONS_BAR_GRAY, levels.gray, r, g, b, 1, 1, 1)
    end
    if recipe.state == "rank" and shown and shown.max then
        GameTooltip:AddLine(format(L.PROFESSIONS_UNKNOWN_RANK_NOTE, shown.max), 0.5, 0.5, 0.5, true)
    end
    if recipe.source then
        GameTooltip:AddLine(recipe.source, 1, 1, 1, true)
    elseif not recipe.item then
        GameTooltip:AddLine(L.PROFESSIONS_UNKNOWN_NOITEM_NOTE, 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
end

local function onRowLeave(row)
    if GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
    end
end

local built = setmetatable({}, { __mode = "k" }) -- rows set up, pooled or shown

local function initRow(row, recipe)
    if not built[row] then
        built[row] = true
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.learn = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.learn:SetPoint("TOPRIGHT", -8, -6)
        row.learn:SetJustifyH("RIGHT")
        row.name:SetPoint("RIGHT", row.learn, "LEFT", -6, 0)
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.price:SetPoint("BOTTOMRIGHT", -8, 6)
        row.price:SetJustifyH("RIGHT")
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
        row.detail:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
        Frames.RowTexture(row, "HIGHLIGHT", "Options_List_Hover", 1, 1, 1, 0.1)
        row:SetScript("OnClick", onRowClick)
        row:SetScript("OnEnter", onRowEnter)
        row:SetScript("OnLeave", onRowLeave)
    end
    row.recipe = recipe
    row.icon:SetTexture(iconOf(recipe))
    row.icon:SetDesaturated(recipe.state ~= "now" and recipe.state ~= "soon")
    row.name:SetText(recipe.name)
    row.learn:SetText(recipe.learn or "")
    row.learn:SetTextColor(stateColor(recipe.state):GetRGB())
    local detail, price = nil, ""
    if recipe.item then
        detail = itemText(recipe.item) or RETRIEVING_ITEM_INFO or "..."
        if (C_Item.GetItemCount(recipe.item, true) or 0) > 0 then
            detail = format(L.PROFESSIONS_UNKNOWN_OWNED, detail)
        end
        local copper = ns.Prices.Available() and ns.Prices.Auction(recipe.item)
        if copper then
            price = ns.MoneyShort(copper)
        end
    else
        -- The source text's first line ("Trainer: ..."), else that the tables know no item.
        local source = recipe.source and ns.Text.Plain((recipe.source:gsub("|n", "\n")))
        detail = source and source:match("^[^\n]*") or L.PROFESSIONS_UNKNOWN_NOITEM_HEADER
    end
    row.detail:SetText(detail)
    row.price:SetText(price)
end

local function initHeader(frame, header)
    if not built[frame] then
        built[frame] = true
        frame:SetHeight(HEADER_HEIGHT)
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.text:SetPoint("BOTTOMLEFT", 8, 4)
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.1)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", 4, 0)
        line:SetPoint("BOTTOMRIGHT", -4, 0)
    end
    frame.text:SetText(format(L.PROFESSIONS_UNKNOWN_HEADER, HEADERS[header.header] or "", header.count))
end

local function draw()
    if not (panel and panel:IsShown()) then
        return
    end
    shown = scan()
    local elements = {}
    if shown then
        local last
        for _, recipe in ipairs(shown.list) do
            if recipe.state ~= last then
                last = recipe.state
                elements[#elements + 1] = { header = last, count = shown.counts[last] }
            end
            elements[#elements + 1] = recipe
        end
        local name = select(2, Professions.Rank(shown.line))
        if not ns.IsText(name) then
            local T = C_TradeSkillUI
            name = T.GetTradeSkillDisplayName and T.GetTradeSkillDisplayName(shown.line)
        end
        if ns.IsText(name) and shown.skill and shown.max then
            name = format(L.PROFESSIONS_UNKNOWN_PROFESSION, name, shown.skill, shown.max)
        end
        panel.summary:SetText(format(L.PROFESSIONS_UNKNOWN_SUMMARY, #shown.list, shown.counts.now or 0))
        panel.profession:SetText(ns.IsText(name) and name or "")
    else
        panel.summary:SetText(L.PROFESSIONS_UNKNOWN_NONE)
        panel.profession:SetText("")
    end
    panel.empty:SetShown(shown ~= nil and #shown.list == 0)
    local provider = CreateDataProvider(elements)
    panel.scrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end

local function buildPanel(page, frame)
    local f = Frames.PortraitWindow(nil, L.PROFESSIONS_UNKNOWN)
    f:SetParent(page)
    f:SetFrameLevel(page:GetFrameLevel() + 20)
    f:SetWidth(PANEL_WIDTH)
    local tab = frame.ProfessionsOverviewTab
    if tab then
        f:SetPoint("TOPLEFT", tab, "TOPRIGHT", 4, TAB_Y)
    else
        f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    end
    f:SetHeight(frame:GetHeight())
    f:EnableMouse(true)
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            module.db.unknownWindow.open = nil
            f:Hide()
        end)
    end
    f:SetScript("OnShow", draw)

    f.profession = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.profession:SetPoint("TOPLEFT", 66, -32)
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.summary:SetPoint("TOPLEFT", f.profession, "BOTTOMLEFT", 0, -4)
    f.summary:SetPoint("RIGHT", -12, 0)
    f.summary:SetJustifyH("LEFT")

    local inset = f.Inset or Frames.Inset(f)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 4, -62)
    inset:SetPoint("BOTTOMRIGHT", -6, 6)
    local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 3, -3)
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 3)
    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(function(factory, element)
        if element.header then
            factory("Frame", initHeader)
        else
            factory("Button", initRow)
        end
    end)
    view:SetElementExtentCalculator(function(_, element)
        return element.header and HEADER_HEIGHT or ROW_HEIGHT
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    f.scrollBox = scrollBox

    f.empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(L.PROFESSIONS_UNKNOWN_EMPTY)
    f.empty:Hide()
    f:Hide()
    return f
end

-- The button ---------------------------------------------------------------------------------------
-- A square button like the one beside it that links the profession (ProfessionsLinkButtonMixin:
-- the tertiary square button art, an icon in it), right of it on the skill bar's line.

local BUTTON_ART = {
    normal = "common-button-tertiary-square-normal",
    over = "common-button-tertiary-square-hover",
    down = "common-button-tertiary-square-pressed",
}
local BUTTON_ICON = 134939 -- Interface\Icons\INV_Scroll_03, a recipe

local function onButtonEnter(self)
    if Frames.HasAtlas(BUTTON_ART.over) then
        self.background:SetAtlas(BUTTON_ART.over, true)
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(L.PROFESSIONS_UNKNOWN, 1, 1, 1)
    GameTooltip:AddLine(L.PROFESSIONS_UNKNOWN_BUTTON_TIP, nil, nil, nil, true)
    GameTooltip:Show()
end

local function onButtonLeave(self)
    if Frames.HasAtlas(BUTTON_ART.normal) then
        self.background:SetAtlas(BUTTON_ART.normal, true)
    end
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function togglePanel()
    if not panel then
        return
    end
    if panel:IsShown() then
        module.db.unknownWindow.open = nil
        panel:Hide()
    else
        module.db.unknownWindow.open = true
        panel:Show()
    end
end

local function buildButton(page)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(23, 23)
    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetPoint("CENTER")
    if Frames.HasAtlas(BUTTON_ART.normal) then
        b.background:SetAtlas(BUTTON_ART.normal, true)
    else
        b.background:SetAllPoints()
        b.background:SetColorTexture(0, 0, 0, 0.5)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(15, 15)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(BUTTON_ICON)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", onButtonEnter)
    b:SetScript("OnLeave", onButtonLeave)
    b:SetScript("OnMouseDown", function(self)
        if Frames.HasAtlas(BUTTON_ART.down) then
            self.background:SetAtlas(BUTTON_ART.down, true)
        end
        self.icon:SetPoint("CENTER", 1, -1)
    end)
    b:SetScript("OnMouseUp", function(self)
        if Frames.HasAtlas(self:IsMouseOver() and BUTTON_ART.over or BUTTON_ART.normal) then
            self.background:SetAtlas(self:IsMouseOver() and BUTTON_ART.over or BUTTON_ART.normal, true)
        end
        self.icon:SetPoint("CENTER")
    end)
    b:SetScript("OnClick", togglePanel)
    -- Right of the link button, else of the skill bar, as Blizzard places the link button.
    if page.LinkButton then
        b:SetPoint("LEFT", page.LinkButton, "RIGHT", 4, 0)
    elseif page.RankBar then
        b:SetPoint("LEFT", page.RankBar, "RIGHT", 2, -4)
    else
        b:SetPoint("TOPRIGHT", -30, -36)
    end
    b:Hide()
    return b
end

-- Turning on and off -------------------------------------------------------------------------------

-- Once the professions window is there: our frames on its crafting page.
local function ensureFrames()
    local frame = _G.ProfessionsFrame
    local page = frame and frame.CraftingPage
    if not page then
        return false
    end
    if not button then
        button = buildButton(page)
        panel = buildPanel(page, frame)
    end
    return true
end

-- The button shows while the open list is one of the player's professions the tables know, and
-- the panel too while the player left it open.
local function update()
    if not (module.enabled and ensureFrames()) then
        return
    end
    local on = openLine() ~= nil
    button:SetShown(on)
    if on and module.db.unknownWindow.open then
        if panel:IsShown() then
            draw()
        else
            panel:Show()
        end
    else
        panel:Hide()
    end
end

refreshSoon = ns.Frames.Coalesce(update, nil, module)

-- A new price or an item's data matters only while the panel shows.
local function redrawSoon()
    if panel and panel:IsShown() then
        refreshSoon()
    end
end

ns.Prices.OnChanged(function()
    if module.enabled then
        redrawSoon()
    end
end)

function module:OnEnable()
    self:On("ADDON_LOADED", refreshSoon)
    self:On("TRADE_SKILL_SHOW", refreshSoon)
    self:On("TRADE_SKILL_LIST_UPDATE", refreshSoon)
    self:On("NEW_RECIPE_LEARNED", refreshSoon)
    self:On("SKILL_LINES_CHANGED", redrawSoon)
    self:On("CHAT_MSG_SKILL", redrawSoon)
    self:On("BAG_UPDATE_DELAYED", redrawSoon)
    self:On("ITEM_DATA_LOAD_RESULT", redrawSoon)
    update()
end

function module:OnDisable()
    if button then
        button:Hide()
        panel:Hide()
    end
    shown = nil
end

function module:OnOptionChanged()
    redrawSoon()
end
