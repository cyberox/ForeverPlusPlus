-- Professions' Unlearned Recipes: the open profession's recipes the character doesn't know, in
-- Blizzard's own recipe list, under its Unlearned divider and in its own greyed categories, as the
-- modern game shows them with Show Unlearned on. Blizzard's Filter menu gets that checkbox back,
-- and a submenu of our own filters for them: where they come from, when they can be learned, and
-- whether the item that teaches one is in the bags. Each row shows the skill it takes to learn,
-- green now, yellow soon, red later, and the recipe page the item that teaches it.
--
-- Why it adds them itself: on Forever the game gives every recipe's info, learned or not
-- (GetAllRecipeIDs and GetRecipeInfo), but its filtered list never holds an unlearned one, even with
-- SetShowUnlearned(true) (docs/forever-api.md). Blizzard's list code already draws, sorts,
-- collapses, and selects unlearned recipes (Professions.GenerateCraftingDataProvider,
-- Blizzard_ProfessionsTemplates): so after Blizzard sets the list's data provider, this puts them
-- in that same tree in Blizzard's own node shapes, and Blizzard's code does the rest.
--
-- How, without making the list redraw for each of hundreds of rows: the tree data provider tells
-- the scroll box to update in full after every insert. So our nodes are built in a provider of
-- our own nobody watches, then each top one is moved into Blizzard's tree (TreeNodeMixin:MoveNode),
-- a redraw or two per category; our provider then passes our nodes' changes (a category collapsed)
-- on to Blizzard's.
local _, ns = ...

local _G, ipairs, pairs, type, format, pcall, tostring = _G, ipairs, pairs, type, string.format, pcall, tostring
local concat = table.concat
local CreateFrame, GameTooltip = CreateFrame, GameTooltip
local C_TradeSkillUI, C_Item = C_TradeSkillUI, C_Item

local L = ns.L
local Professions = ns.Professions -- ours; Blizzard's global of the same name is _G.Professions

local professions = ns.modules.Professions
local internal = professions.internal
local module = professions:NewPart({
    key = "unlearnedRecipes", name = L.PROFESSIONS_UNLEARNED, description = L.PROFESSIONS_UNLEARNED_DESC,
    section = L.PROFESSIONS_UNLEARNED, added = "1.6.0",
}, {
    unlearnedShow = false, -- the Filter menu's Show Unlearned: the list stays Blizzard's until ticked
    unlearnedItems = true, -- sources: recipes an item teaches
    unlearnedOthers = true, -- and the rest (trainers and the like)
    unlearnedNow = true, -- when: can be learned now
    unlearnedSoon = true, -- within unlearnedWithin points
    unlearnedWithin = 25,
    unlearnedLater = true, -- further off, or past the rank's most
    unlearnedBags = false, -- only those whose item is in the bags
})

-- Blizzard's own words where the client has them, so the menu reads as the modern game's.
local SHOW_LABEL = _G.PROFESSION_RECIPES_SHOW_UNLEARNED or L.PROFESSIONS_UNLEARNED_SHOW
local MENU_LABEL = _G.PROFESSIONS_CATEGORY_UNLEARNED or L.PROFESSIONS_UNLEARNED_MENU
local SOURCES_LABEL = _G.SOURCES or L.PROFESSIONS_UNLEARNED_SOURCES

-- The source kinds' checkboxes, by Professions.RECIPE_SOURCES' keys: a kind added there needs its
-- checkbox here, and is left out of the menu until it has one.
local SOURCE_OPTIONS = {
    item = { key = "unlearnedItems", name = L.PROFESSIONS_UNLEARNED_ITEMS },
    other = { key = "unlearnedOthers", name = L.PROFESSIONS_UNLEARNED_OTHERS },
}
local WHEN_OPTIONS = {
    { when = "now", key = "unlearnedNow", name = L.PROFESSIONS_UNLEARNED_NOW },
    { when = "soon", key = "unlearnedSoon", name = L.PROFESSIONS_UNLEARNED_SOON },
    { when = "later", key = "unlearnedLater", name = L.PROFESSIONS_UNLEARNED_LATER },
}

module:AddOptions({
    { key = "unlearnedShow", name = SHOW_LABEL, description = L.PROFESSIONS_UNLEARNED_SHOW_DESC },
    {
        key = "unlearnedItems", name = L.PROFESSIONS_UNLEARNED_ITEMS, description = L.PROFESSIONS_UNLEARNED_ITEMS_DESC,
        section = SOURCES_LABEL, requires = "unlearnedShow",
    },
    {
        key = "unlearnedOthers", name = L.PROFESSIONS_UNLEARNED_OTHERS,
        description = L.PROFESSIONS_UNLEARNED_OTHERS_DESC, requires = "unlearnedShow",
    },
    {
        key = "unlearnedNow", name = L.PROFESSIONS_UNLEARNED_NOW, description = L.PROFESSIONS_UNLEARNED_NOW_DESC,
        section = L.PROFESSIONS_UNLEARNED_WHEN, requires = "unlearnedShow",
    },
    {
        key = "unlearnedSoon", name = L.PROFESSIONS_UNLEARNED_SOON, description = L.PROFESSIONS_UNLEARNED_SOON_DESC,
        requires = "unlearnedShow", slider = "unlearnedWithin",
    },
    {
        key = "unlearnedWithin", name = L.PROFESSIONS_UNLEARNED_WITHIN, description = L.PROFESSIONS_UNLEARNED_WITHIN_DESC,
        requires = "unlearnedSoon", min = 5, max = 75, step = 5, format = "%d",
    },
    {
        key = "unlearnedLater", name = L.PROFESSIONS_UNLEARNED_LATER, description = L.PROFESSIONS_UNLEARNED_LATER_DESC,
        requires = "unlearnedShow",
    },
    {
        key = "unlearnedBags", name = L.PROFESSIONS_UNLEARNED_BAGS, description = L.PROFESSIONS_UNLEARNED_BAGS_DESC,
        requires = "unlearnedShow",
    },
})

-- What the game's data can and can't say, once on the Modules page while the part is on.
professions.notice[#professions.notice + 1] = {
    text = L.PROFESSIONS_UNLEARNED_LIMITS,
    description = L.PROFESSIONS_UNLEARNED_LIMITS_DESC,
    shown = function()
        return ns.PartOn(professions, "unlearnedRecipes")
    end,
}

-- Blizzard's groups for the list's top nodes (the local Group enum in Blizzard_Professions.lua:
-- Favorite, Learned, UnlearnedDivider, Unlearned), which its root sorts by.
local GROUP_DIVIDER, GROUP_UNLEARNED = 3, 4
-- The divider's height (the same function): taller with learned recipes above it.
local DIVIDER_AFTER_LEARNED, DIVIDER_ALONE = 70, 30

local function craftingPage()
    local frame = _G.ProfessionsFrame
    return frame and frame.CraftingPage
end

-- Whether the open list is one of the player's own professions: not a guild's, an NPC's, a link,
-- or runeforging. Probe: each call is Mainline's.
local function ownList()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and internal.ListHasSkillUps()) then
        return false
    end
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then
        return false
    end
    return not (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember())
end

-- The open profession's unlearned recipes -----------------------------------------------------------
-- Read once per profession (and again after a recipe is learned or the window opens again): each
-- `{ info, item, learn, line, inLine }`, info our own copy of the recipe's info at its first rank,
-- as Blizzard lists ranked recipes. Left out: junk the game still knows (Professions.IsJunkRecipe:
-- disabled, dummy, unnamed, "[DNT]", "Deprecated"), and a recipe whose earlier rank is learned,
-- which Blizzard's list already shows.

local cache -- { professionID, list }

local function forget()
    cache = nil
end

local RANKS_MAX = 10 -- a guard on the rank chain

local function firstRank(info)
    local T = C_TradeSkillUI
    for _ = 1, RANKS_MAX do
        local previous = info.previousRecipeID and T.GetRecipeInfo(info.previousRecipeID)
        if not previous then
            break
        end
        info = previous
    end
    return info
end

local function copy(info)
    local own = {}
    for key, value in pairs(info) do
        own[key] = value
    end
    -- Blizzard's sort compares these as numbers; on Forever every recipe had them (2026-11-09).
    if type(own.maxTrivialLevel) ~= "number" then
        own.maxTrivialLevel = 0
    end
    if type(own.itemLevel) ~= "number" then
        own.itemLevel = 0
    end
    return own
end

local function candidates(professionID)
    if cache and cache.professionID == professionID then
        return cache.list
    end
    local T = C_TradeSkillUI
    local data = internal.recipes or {}
    local inLine = T.IsRecipeInSkillLine
    local list, seen = {}, {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and not info.learned and not Professions.IsJunkRecipe(info) then
            local first = firstRank(info)
            if not first.learned and not seen[first.recipeID] and not Professions.IsJunkRecipe(first) then
                seen[first.recipeID] = true
                local entry = data[first.skillLineAbilityID]
                list[#list + 1] = {
                    info = copy(first), item = entry and entry[5], learn = entry and entry[6],
                    line = entry and entry[3],
                    inLine = not (inLine and professionID) or inLine(first.recipeID, professionID),
                }
            end
        end
    end
    cache = { professionID = professionID, list = list }
    return list
end

-- What the list shows -----------------------------------------------------------------------------

local shown = {} -- recipe ID -> its candidate, for the rows and the page, from the last build
local added -- { provider, scratch, nodes }: what we put in Blizzard's tree

local function filters(db)
    local sources = {}
    for source, option in pairs(SOURCE_OPTIONS) do
        sources[source] = db[option.key]
    end
    local when = {}
    for _, option in ipairs(WHEN_OPTIONS) do
        when[option.when] = db[option.key]
    end
    return { sources = sources, when = when, bags = db.unlearnedBags }
end

-- While one of Blizzard's own filters is on that no unlearned recipe passes (Has Skill Up, Have
-- Materials), or one this can't tell for them (Slots, categories), none is added. Probe: each
-- call is Mainline's.
local function blizzardNarrows()
    local T = C_TradeSkillUI
    return (T.GetOnlyShowMakeableRecipes and T.GetOnlyShowMakeableRecipes())
        or (T.GetOnlyShowSkillUpRecipes and T.GetOnlyShowSkillUpRecipes())
        or (T.AreAnyInventorySlotsFiltered and T.AreAnyInventorySlotsFiltered())
        or (T.AnyRecipeCategoriesFiltered and T.AnyRecipeCategoriesFiltered())
end

-- The search box's text as Blizzard filters by it (Professions.OnRecipeListSearchTextChanged: a
-- name, or "60-70" and "~65" as item levels), and whether the player is searching.
local function search()
    local T = C_TradeSkillUI
    local text = T.GetRecipeItemNameFilter and T.GetRecipeItemNameFilter()
    local low, high
    if T.GetRecipeItemLevelFilter then
        low, high = T.GetRecipeItemLevelFilter()
    end
    if type(high) == "number" and high > 0 then
        return true, nil, low, high
    end
    if type(text) == "string" and text ~= "" then
        return true, text
    end
    return false
end

-- A category's info for our tree, as Blizzard's list keeps its unlearned ones: our own copy, in
-- the Unlearned group and drawn greyed.
local function categoryOf(id)
    local T = C_TradeSkillUI
    local info = T.GetCategoryInfo and T.GetCategoryInfo(id)
    if type(info) ~= "table" then
        return nil
    end
    local own = {}
    for key, value in pairs(info) do
        own[key] = value
    end
    own.group, own.unlearned = GROUP_UNLEARNED, true
    if type(own.uiOrder) ~= "number" then
        own.uiOrder = 0
    end
    return own
end

-- Our nodes for one category, in Blizzard's shapes (AttachTreeDataRecursive): its subcategories,
-- then its recipes between a top and a bottom padding.
local function attach(parent, branch, collapses)
    local info = branch.info
    local node = parent:Insert({ categoryInfo = info, group = GROUP_UNLEARNED })
    if collapses and collapses[info.categoryID] then
        node:SetCollapsed(true, false, true)
    end
    for _, child in ipairs(branch.categories) do
        attach(node, child, collapses)
    end
    if #branch.recipes > 0 then
        node:Insert({ topPadding = true, order = -1 })
        for _, recipe in ipairs(branch.recipes) do
            node:Insert({ recipeInfo = recipe, order = 0 })
        end
        node:Insert({ bottomPadding = true, order = 1 })
    end
end

-- The recipes to add to `provider` now, or nil: those the filters, the search, and Blizzard's list
-- leave in. Fills `shown`.
local function pick(provider)
    shown = {}
    local db = module.db
    if not (module.enabled and db.unlearnedShow and ownList()) or blizzardNarrows() then
        return nil
    end
    -- What Blizzard's tree holds: its learned recipes, by ID and name (the game's data has some
    -- recipes twice, one learned), or that it lists unlearned ones itself, when it's left alone.
    local learnedIDs, learnedNames, anyLearned = {}, {}, false
    for _, node in provider:EnumerateEntireRange() do
        local data = node:GetData()
        local info = data and data.recipeInfo
        if info then
            if not info.learned then
                return nil
            end
            anyLearned = true
            learnedIDs[info.recipeID] = true
            if type(info.name) == "string" then
                learnedNames[info.name] = true
            end
        end
    end
    local page = craftingPage()
    local profession = page and page.professionInfo
    local searching, text, low, high = search()
    local wanted = filters(db)
    local skills = {} -- line -> { skill, max }
    local list = {}
    for _, recipe in ipairs(candidates(profession and profession.professionID)) do
        local info = recipe.info
        local keep = (searching or recipe.inLine) and not learnedIDs[info.recipeID]
            and not learnedNames[info.name]
        if keep and searching then
            if high then
                keep = info.itemLevel >= low and info.itemLevel <= high
            else
                keep = Professions.MatchesSearch(info.name, text)
            end
        end
        if keep then
            local line = recipe.line
            local skill = line and skills[line]
            if line and not skill then
                local level, most = Professions.Progress(line)
                skill = { level, most }
                skills[line] = skill
            end
            recipe.state = Professions.LearnState(recipe.learn, skill and skill[1], skill and skill[2],
                db.unlearnedWithin)
            recipe.inBags = db.unlearnedBags and recipe.item ~= nil and (C_Item.GetItemCount(recipe.item) or 0) > 0
            if Professions.PassesUnlearned(recipe, wanted) then
                list[#list + 1] = info
                shown[info.recipeID] = recipe
            end
        end
    end
    if #list == 0 then
        return nil
    end
    return list, searching, anyLearned
end

local learnColumn -- the rows' column, below

local function remove()
    local was = added
    added = nil
    if not was then
        return
    end
    was.scratch:UnregisterCallback("OnSizeChanged", was)
    was.scratch:UnregisterCallback("OnSort", was)
    local page = craftingPage()
    local box = page and page.RecipeList and page.RecipeList.ScrollBox
    if box and box:GetDataProvider() == was.provider then
        for _, node in ipairs(was.nodes) do
            was.provider:Remove(node)
        end
    end
end

-- Puts the unlearned recipes in Blizzard's tree, once per provider.
local function add(provider)
    if added and added.provider == provider then
        return -- the same provider set again (ScrollBox:Rebuild): ours are in it
    end
    added = nil
    local recipes, searching, anyLearned = pick(provider)
    learnColumn:Use(recipes ~= nil)
    if not recipes then
        return
    end
    local page = craftingPage()
    local collapses = page.GetCollapses and page:GetCollapses()
    local scratch = CreateTreeDataProvider()
    local root = scratch:GetRootNode()
    root:Insert({ isDivider = true, dividerHeight = anyLearned and DIVIDER_AFTER_LEARNED or DIVIDER_ALONE,
        group = GROUP_DIVIDER })
    -- Not searching, Blizzard leaves out categories without recipes of their own; searching it
    -- keeps them (discardRootCategories).
    for _, branch in ipairs(Professions.RecipeTree(recipes, categoryOf, searching)) do
        attach(root, branch, collapses)
    end
    local nodes = {}
    for i, node in ipairs(root:GetNodes()) do
        nodes[i] = node
    end
    local target = provider:GetRootNode()
    for _, node in ipairs(nodes) do
        target:MoveNode(node) -- sorted into place by Blizzard's root comparator
    end
    added = { provider = provider, scratch = scratch, nodes = nodes }
    local function pass()
        provider:Invalidate()
    end
    scratch:RegisterCallback("OnSizeChanged", pass, added)
    scratch:RegisterCallback("OnSort", pass, added)
end

-- After Blizzard sets the list's data provider (ProfessionsCraftingPageMixin:Init, and a rebuild).
local function onSetDataProvider(_, provider)
    if provider then
        add(provider)
    end
end

-- Again with the provider the list has now, after a filter or option changed.
local function refresh()
    local page = craftingPage()
    local box = page and page.RecipeList and page.RecipeList.ScrollBox
    local provider = box and box:GetDataProvider()
    remove()
    if provider then
        add(provider)
    else
        learnColumn:Use(false)
    end
end

-- The rows ------------------------------------------------------------------------------------------
-- The skill an unlearned recipe takes to learn, at the right end of its row in its own column
-- (Professions.NewRowColumn): left of the others, which unlearned rows leave empty, so known rows
-- keep theirs where they were.

local function stateColor(state)
    if state == "now" then
        return GREEN_FONT_COLOR
    elseif state == "soon" then
        return YELLOW_FONT_COLOR
    end
    return RED_FONT_COLOR
end

learnColumn = Professions.NewRowColumn(40, 20, 2) -- up to three digits
local numbers = ns.ItemButtons.Overlays(function(row)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("RIGHT")
    return text
end)

local function rowNumber(row, node)
    if not (row and row.Label) then
        return
    end
    local info = Professions.RowRecipe(row, node)
    local recipe = module.enabled and info and not info.learned and shown[info.recipeID]
    local value = recipe and recipe.state ~= "unknown" and recipe.learn or nil
    local text = numbers:Set(row, value)
    if text then
        text:SetText(value)
        text:SetTextColor(stateColor(recipe.state):GetRGB())
    end
    learnColumn:Place(row, text)
end

local ROW_HOOKS = { Init = rowNumber }

-- The recipe page ----------------------------------------------------------------------------------
-- For an unlearned recipe an item teaches, one line under its name (internal.PlaceOnForm, where
-- Skill Bar's bar is for known ones): the item in its quality's color, whether it's in the bags,
-- and its auction price. Hover for the item, Shift+click to link it. Nothing for a recipe no item
-- teaches: Blizzard's own Unlearned Recipe line under the reagents gives its source.

local FORM_ORDER = 30
local line -- our button on the form, made the first time it's needed
local waiting -- the item whose data was asked for

local function itemName(item)
    local name = C_Item.GetItemNameByID(item)
    if not ns.IsText(name) then
        waiting = item
        C_Item.RequestLoadItemDataByID(item)
        return nil
    end
    local quality = C_Item.GetItemQualityByID(item)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and color.hex and (color.hex .. name .. "|r") or name
end

local function lineText(item)
    local name = itemName(item)
    if not name then
        return nil
    end
    if (C_Item.GetItemCount(item) or 0) > 0 then
        name = format(L.PROFESSIONS_UNLEARNED_OWNED, name)
    end
    local copper = ns.Prices.Available() and ns.Prices.Auction(item)
    if copper then
        name = format(L.PROFESSIONS_UNLEARNED_PRICED, name, ns.Money(copper))
    end
    return format(L.PROFESSIONS_UNLEARNED_TAUGHT, name)
end

local function insertLink(link)
    local util = _G.ChatFrameUtil
    local insert = util and util.InsertLink or _G.ChatEdit_InsertLink
    if link and insert then
        insert(link)
    end
end

local function buildLine(form)
    local b = CreateFrame("Button", nil, form)
    local font = _G.GameFontHighlightSmall2 and "GameFontHighlightSmall2" or "GameFontHighlightSmall"
    b.text = b:CreateFontString(nil, "OVERLAY", font)
    b.text:SetPoint("LEFT")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.item)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    b:SetScript("OnClick", function(self)
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local _, link = C_Item.GetItemInfo(self.item)
            insertLink(link)
        end
    end)
    return b
end

local function hideLine(form)
    if line and line:IsShown() then
        line:Hide()
        internal.PlaceOnForm(form, FORM_ORDER, nil)
    end
end

-- The room the row leaves the line, which it takes up to its text's whole width.
local function fitLine(room)
    local full = line.full
    local width = room and room < full and room or full
    line.text:SetWidth(width)
    line:SetSize(width, line.text:GetStringHeight())
end

-- After the form shows a recipe (its Init), or with the recipe it shows now.
local function drawLine(form, info)
    waiting = nil
    local icon, name = form and form.OutputIcon, form and form.OutputText
    local entry = module.enabled and info and not info.learned and internal.recipes
        and internal.recipes[info.skillLineAbilityID]
    local item = entry and entry[5]
    local text = item and icon and name and icon:IsShown() and name:IsShown() and lineText(item)
    if not text then
        hideLine(form)
        return
    end
    line = line or buildLine(form)
    line.item = item
    line.text:SetWidth(0)
    line.text:SetText(text)
    line.full = line.text:GetStringWidth()
    line:Show()
    fitLine(nil)
    internal.PlaceOnForm(form, FORM_ORDER, line, fitLine)
end

local function redrawLine()
    local form = Professions.RecipeForm()
    if form and module.enabled then
        drawLine(form, form.currentRecipeInfo)
    end
end

ns.Prices.OnChanged(function()
    if module.enabled and line and line:IsShown() then
        redrawLine()
    end
end)

-- The Filter menu ------------------------------------------------------------------------------------
-- Show Unlearned at the top, where the modern game has it, then a submenu of our filters for them
-- laid out like its Sources submenu: Check All, Uncheck All, then checkboxes. Only on the crafting
-- page's own list; the crafting orders page's filter menu has the same tag.

local TAG = "MENU_PROFESSIONS_FILTER" -- Professions.SetupFilterMenu, Camelot/Blizzard_Professions.lua

local function isOn(key)
    return function()
        return module.db[key] and true or false
    end
end

-- Through Core, as the Modules page sets options: OnOptionChanged redraws the list.
local function toggle(key)
    return function()
        ns.SetOption(module.name, key, not module.db[key])
    end
end

local function setAll(on)
    for _, option in pairs(SOURCE_OPTIONS) do
        ns.SetOption(module.name, option.key, on)
    end
    for _, option in ipairs(WHEN_OPTIONS) do
        ns.SetOption(module.name, option.key, on)
    end
    return MenuResponse and MenuResponse.Refresh
end

local function addEntries(owner, root)
    local page = module.enabled and craftingPage()
    if not (page and page.RecipeList and owner == page.RecipeList.FilterDropdown and ownList()) then
        return
    end
    root:Insert(MenuUtil.CreateCheckbox(SHOW_LABEL, isOn("unlearnedShow"), toggle("unlearnedShow")), 1)
    local menu = MenuUtil.CreateButton(MENU_LABEL)
    menu:SetEnabled(isOn("unlearnedShow"))
    menu:CreateButton(_G.CHECK_ALL or L.PROFESSIONS_UNLEARNED_CHECK_ALL, function()
        return setAll(true)
    end)
    menu:CreateButton(_G.UNCHECK_ALL or L.PROFESSIONS_UNLEARNED_UNCHECK_ALL, function()
        return setAll(false)
    end)
    menu:CreateTitle(SOURCES_LABEL)
    for _, kind in ipairs(Professions.RECIPE_SOURCES) do
        local option = SOURCE_OPTIONS[kind.key]
        if option then
            menu:CreateCheckbox(option.name, isOn(option.key), toggle(option.key))
        end
    end
    menu:CreateTitle(L.PROFESSIONS_UNLEARNED_WHEN)
    for _, option in ipairs(WHEN_OPTIONS) do
        menu:CreateCheckbox(option.name, isOn(option.key), toggle(option.key))
    end
    menu:CreateDivider()
    menu:CreateCheckbox(L.PROFESSIONS_UNLEARNED_BAGS, isOn("unlearnedBags"), toggle("unlearnedBags"))
    root:Insert(menu, 2)
end

-- Added once at load: Blizzard's menus can't take an addition back, so the entries check whether
-- the part is on each time the menu opens. Probe: Menu.ModifyMenu and MenuUtil are Mainline's.
if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.CreateCheckbox then
    Menu.ModifyMenu(TAG, addEntries)
end

-- Turning on and off -------------------------------------------------------------------------------

-- The list, the rows' mixin, and the form are in a load-on-demand Blizzard addon: hooked once
-- they're there.
local function hook()
    local page = craftingPage()
    local box = page and page.RecipeList and page.RecipeList.ScrollBox
    if not box then
        return false
    end
    module:Hook(box, "SetDataProvider", onSetDataProvider)
    module:Hook(Professions.RecipeForm(), "Init", drawLine)
    return Professions.HookRecipeRows(module, ROW_HOOKS)
end

local function onOpen()
    forget()
    hook()
end

-- The page's item, once its data has come (or never will: then the line stays hidden).
local function onItemData(_, item, success)
    if item == waiting then
        waiting = nil
        if success then
            redrawLine()
        end
    end
end

function module:OnEnable()
    self:On("ADDON_LOADED", hook)
    self:On("TRADE_SKILL_SHOW", onOpen)
    self:On("TRADE_SKILL_CLOSE", forget)
    self:On("NEW_RECIPE_LEARNED", forget)
    self:On("BAG_UPDATE_DELAYED", redrawLine)
    self:On("ITEM_DATA_LOAD_RESULT", onItemData)
    if hook() then
        refresh()
        redrawLine()
    end
end

function module:OnDisable()
    if craftingPage() then
        remove()
    end
    shown = {}
    learnColumn:Use(false)
    numbers:HideAll()
    hideLine(Professions.RecipeForm())
    forget()
end

function module:OnOptionChanged()
    if craftingPage() then
        refresh()
    end
end

-- Debug: what the game says about where the selected unlearned recipe comes from, to learn whether
-- Blizzard's source data (Mainline's sourceType, GetRecipeSourceText, IsAnyRecipeFromSource) works
-- on Forever. Probe: every call is Mainline's; none is in this client's API docs but sourceType.

local function sourceText(T, id)
    if not T.GetRecipeSourceText then
        return nil
    end
    local ok, text = pcall(T.GetRecipeSourceText, id)
    if ok and ns.IsText(text) and text ~= "" then
        return ns.Text.Plain((text:gsub("|n", " ")))
    end
end

local function dumpSources()
    local T = C_TradeSkillUI
    local ids = T and T.GetAllRecipeIDs and T.GetAllRecipeIDs()
    if not (ids and #ids > 0 and T.GetRecipeInfo) then
        ns.Print(L.PROFESSIONS_DUMP_NONE)
        return
    end
    local form = Professions.RecipeForm()
    local selected = form and form.currentRecipeInfo
    selected = selected and selected.recipeID and T.GetRecipeInfo(selected.recipeID)
    local total, typed, texted = 0, 0, 0
    for _, id in ipairs(ids) do
        local info = T.GetRecipeInfo(id)
        if info and not info.learned then
            total = total + 1
            if info.sourceType ~= nil then
                typed = typed + 1
            end
            if sourceText(T, id) then
                texted = texted + 1
            end
            if not (selected and not selected.learned) then
                selected = info
            end
        end
    end
    if selected and not selected.learned then
        ns.Print(format(L.PROFESSIONS_UNLEARNED_DUMP_RECIPE, tostring(selected.name), selected.recipeID,
            tostring(selected.sourceType), tostring(sourceText(T, selected.recipeID))))
    end
    local from = {}
    local count = C_PetJournal and C_PetJournal.GetNumPetSources and C_PetJournal.GetNumPetSources()
    if T.IsAnyRecipeFromSource and type(count) == "number" then
        for i = 1, count do
            local ok, any = pcall(T.IsAnyRecipeFromSource, i)
            if ok and any then
                from[#from + 1] = tostring(i)
            end
        end
    end
    local filter = T.GetSourceTypeFilter and T.GetSourceTypeFilter()
    ns.Print(format(L.PROFESSIONS_UNLEARNED_DUMP_TYPES, #from > 0 and concat(from, ", ") or "-", tostring(filter)))
    ns.Print(format(L.PROFESSIONS_UNLEARNED_DUMP_COUNT, typed, texted, total))
end

professions.debugActions = professions.debugActions or {}
professions.debugActions[#professions.debugActions + 1] = {
    name = L.PROFESSIONS_UNLEARNED_DUMP, button = L.PROFESSIONS_DUMP_BUTTON,
    description = L.PROFESSIONS_UNLEARNED_DUMP_DESC, section = L.DEBUG_SECTION_DIAGNOSTICS,
    whileOff = true, fn = dumpSources,
}
