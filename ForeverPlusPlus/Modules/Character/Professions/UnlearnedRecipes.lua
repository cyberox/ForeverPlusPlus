-- Professions' Unlearned Recipes: the open profession's recipes the character doesn't know, in
-- Blizzard's own recipe list, each in its category among the learned ones. Blizzard's Filter menu
-- gets the modern game's Show Learned and Show Unlearned checkboxes back (learned only, unlearned
-- only, or both), and a submenu of our own filters for the unlearned: where they come from, when
-- they can be learned, and whether the item that teaches one is in the bags. Each row shows the
-- skill it takes to learn, green now, yellow soon, red later, and the recipe page the item that
-- teaches it.
--
-- Why it adds them itself: on Forever the game gives every recipe's info, learned or not
-- (GetAllRecipeIDs and GetRecipeInfo), but its filtered list never holds an unlearned one, even with
-- SetShowUnlearned(true) (docs/forever-api.md). Blizzard's list code already draws, sorts,
-- collapses, and selects unlearned recipes (Professions.GenerateCraftingDataProvider,
-- Blizzard_ProfessionsTemplates): so after Blizzard sets the list's data provider, this gives the
-- list a tree of its own in Blizzard's node shapes, and Blizzard's code does the rest.
--
-- How, without making the list redraw for each of hundreds of rows: a tree data provider tells
-- the scroll box watching it to update in full after every insert. So Blizzard's tree is only
-- read, never changed, and ours is built whole before the list sees it, then set once (`build`).
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
    unlearnedLearned = true, -- and its Show Learned: off with Show Unlearned on, only unlearned ones
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
local LEARNED_LABEL = _G.PROFESSION_RECIPES_SHOW_LEARNED or L.PROFESSIONS_UNLEARNED_LEARNED
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
    { key = "unlearnedLearned", name = LEARNED_LABEL, description = L.PROFESSIONS_UNLEARNED_LEARNED_DESC },
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
-- Favorite, Learned, UnlearnedDivider, Unlearned).
local GROUP_FAVORITE, GROUP_LEARNED = 1, 2

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
-- disabled, dummy, unnamed, "[DNT]", "Deprecated"), Season of Discovery's recipes, and a recipe
-- whose earlier rank is learned, which Blizzard's list already shows.

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
    -- Season of Discovery's recipes, which the client still has and Forever doesn't: by their
    -- category, from the generated Data.lua.
    local retired = internal.retiredCategories or {}
    local list, seen = {}, {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and not info.learned and not Professions.IsJunkRecipe(info) and not retired[info.categoryID] then
            local first = firstRank(info)
            if not first.learned and not seen[first.recipeID] and not Professions.IsJunkRecipe(first)
                and not retired[first.categoryID] then
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
local theirs -- the provider Blizzard last gave the list, which stays as Blizzard built it
local ours -- the provider we gave the list in its place, or nil while the list has Blizzard's
local swapping -- true while we set ours, so our own hook leaves it alone
local categories = {} -- category ID -> Blizzard's own info for it, from the tree it built

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

-- A category's info for our tree: Blizzard's own where its tree has the category, so its header is
-- the same one, and otherwise our own copy in the Learned group, drawn like any other.
local function categoryOf(id)
    if categories[id] then
        return categories[id]
    end
    local T = C_TradeSkillUI
    local info = T.GetCategoryInfo and T.GetCategoryInfo(id)
    if type(info) ~= "table" then
        return nil
    end
    local own = {}
    for key, value in pairs(info) do
        own[key] = value
    end
    own.group, own.unlearned = GROUP_LEARNED, false
    if type(own.uiOrder) ~= "number" then
        own.uiOrder = 0
    end
    return own
end

-- Our nodes for one category, in Blizzard's shapes (AttachTreeDataRecursive): its subcategories,
-- then its recipes between a top and a bottom padding. In the order they're given: our tree has
-- no sort comparators, since Professions.RecipeTree already put them in Blizzard's order.
local function attach(parent, branch, collapses)
    local info = branch.info
    local node = parent:Insert({ categoryInfo = info, group = GROUP_LEARNED })
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

-- What Blizzard's tree holds, read without changing it: its Favorites nodes, its learned recipes'
-- infos with their IDs and names (the game's data has some recipes twice, one learned), and its
-- categories' infos. Nil when it lists unlearned recipes itself: then it's left alone.
local function read(provider)
    local favorites, learned, ids, names = {}, {}, {}, {}
    categories = {}
    local function walk(node)
        local data = node:GetData()
        local category, info = data and data.categoryInfo, data and data.recipeInfo
        if category and category.categoryID then
            categories[category.categoryID] = category
        end
        if info then
            if not info.learned then
                return false
            end
            learned[#learned + 1] = info
            ids[info.recipeID] = true
            if type(info.name) == "string" then
                names[info.name] = true
            end
        end
        for _, child in ipairs(node:GetNodes()) do
            if walk(child) == false then
                return false
            end
        end
    end
    for _, top in ipairs(provider:GetRootNode():GetNodes()) do
        local data = top:GetData()
        if data and data.group == GROUP_FAVORITE then
            favorites[#favorites + 1] = top
        elseif walk(top) == false then
            return nil
        end
    end
    return { favorites = favorites, learned = learned, ids = ids, names = names }
end

-- The unlearned recipes' infos to show now: those the filters, the search, and Blizzard's list
-- (`has`, from read) leave in. Fills `shown`.
local function pick(has)
    shown = {}
    local db = module.db
    local learnedIDs, learnedNames = has.ids, has.names
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
    return list, searching
end

local learnColumn -- the rows' column, below

-- A node of Blizzard's tree and what's under it, again in ours, with the same data.
local function copyNode(parent, source)
    local node = parent:Insert(source:GetData())
    if source:IsCollapsed() then
        node:SetCollapsed(true, false, true)
    end
    for _, child in ipairs(source:GetNodes()) do
        copyNode(node, child)
    end
end

local function recipeList()
    local page = craftingPage()
    return page and page.RecipeList
end

-- Blizzard's "no results" text follows its own tree, which ours may differ from either way.
local function noResults()
    local list = recipeList()
    if ours and list and list.NoResultsText then
        list.NoResultsText:SetShown(ours:IsEmpty())
    end
end

-- Gives the list `provider` (ours, or Blizzard's back) without our hook taking it for Blizzard's.
local function give(box, provider, retain)
    swapping = true
    box:SetDataProvider(provider, retain)
    swapping = false
end

-- The list as the two Show checkboxes ask for it. Blizzard's tree is never changed: with both on,
-- or only Show Unlearned, a tree of our own is built whole, off screen, in Blizzard's node shapes
-- (learned and unlearned recipes together in each category), and given to the list once. That's
-- one redraw however many recipes there are, where adding them to the tree the list is watching
-- redrew it for every one.
local function build(box, retain)
    local db = module.db
    local was = ours
    ours = nil
    shown = {}
    local wantLearned, wantUnlearned = db.unlearnedLearned, db.unlearnedShow
    local has = module.enabled and theirs and not (wantLearned and not wantUnlearned) and ownList()
        and read(theirs)
    if not has then
        learnColumn:Use(false)
        if was and theirs and box:GetDataProvider() == was then
            give(box, theirs, retain) -- back to Blizzard's
        end
        return
    end
    local unlearned, searching = {}, false
    -- While one of Blizzard's own filters is on, no unlearned recipe is shown (blizzardNarrows).
    if wantUnlearned and not blizzardNarrows() then
        unlearned, searching = pick(has)
    end
    if wantLearned and #unlearned == 0 then
        learnColumn:Use(false)
        if was and box:GetDataProvider() == was then
            give(box, theirs, retain) -- nothing to add: Blizzard's as it is
        end
        return
    end
    local recipes = {}
    if wantLearned then
        for i, info in ipairs(has.learned) do
            recipes[i] = info
        end
    end
    for _, info in ipairs(unlearned) do
        recipes[#recipes + 1] = info
    end
    local page = craftingPage()
    local collapses = page.GetCollapses and page:GetCollapses()
    local provider = CreateTreeDataProvider()
    local root = provider:GetRootNode()
    if wantLearned then
        for _, favorite in ipairs(has.favorites) do
            copyNode(root, favorite)
        end
    end
    -- Not searching, Blizzard leaves out categories without recipes of their own; searching it
    -- keeps them (discardRootCategories).
    for _, branch in ipairs(Professions.RecipeTree(recipes, categoryOf, searching)) do
        attach(root, branch, collapses)
    end
    learnColumn:Use(#unlearned > 0)
    ours = provider
    give(box, provider, retain)
    noResults()
end

-- After Blizzard sets the list's data provider (ProfessionsCraftingPageMixin:Init, and a rebuild).
local function onSetDataProvider(box, provider, retain)
    if swapping or not provider then
        return
    end
    if provider == ours then
        return -- ours set again (ScrollBox:Rebuild)
    end
    theirs = provider
    build(box, retain)
end

-- Again from Blizzard's last tree, after a filter or option changed.
local function refresh()
    local list = recipeList()
    local box = list and list.ScrollBox
    if box and theirs then
        build(box, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
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
    -- The line without its price too, for a row too narrow for both: the name matters more, and
    -- the item's tooltip has the price.
    local short = format(L.PROFESSIONS_UNLEARNED_TAUGHT, name)
    local copper = ns.Prices.Available() and ns.Prices.Auction(item)
    if copper then
        return format(L.PROFESSIONS_UNLEARNED_TAUGHT, format(L.PROFESSIONS_UNLEARNED_PRICED, name,
            ns.Money(copper))), short
    end
    return short, nil
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

-- The room the row leaves the line, which it takes up to its text's whole width. Too narrow for
-- the whole line, it drops the price before the name is cut short.
local function fitLine(room)
    local full, text = line.full, line.long
    if room and room < full and line.short then
        full, text = line.shortWidth, line.short
    end
    local width = room and room < full and room or full
    line.text:SetText(text)
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
    local text, short
    if item and icon and name and icon:IsShown() and name:IsShown() then
        text, short = lineText(item)
    end
    if not text then
        hideLine(form)
        return
    end
    line = line or buildLine(form)
    line.item = item
    line.long, line.short = text, short
    line.text:SetWidth(0)
    if short then
        line.text:SetText(short)
        line.shortWidth = line.text:GetStringWidth()
    end
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
    -- The two checkboxes the modern game's menu has: learned only, unlearned only, or both.
    root:Insert(MenuUtil.CreateCheckbox(LEARNED_LABEL, isOn("unlearnedLearned"), toggle("unlearnedLearned")), 1)
    root:Insert(MenuUtil.CreateCheckbox(SHOW_LABEL, isOn("unlearnedShow"), toggle("unlearnedShow")), 2)
    -- In the menu before anything goes in it: a description outside a menu can't take entries
    -- (BaseMenuDescriptionMixin:Insert needs the menu's shared properties).
    local menu = MenuUtil.CreateButton(MENU_LABEL)
    root:Insert(menu, 3)
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
    -- Blizzard sets its "no results" text after the provider, from its own tree.
    module:Hook(page, "Init", noResults)
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
    -- The list gets Blizzard's own tree back.
    local list = recipeList()
    local box = list and list.ScrollBox
    if ours and theirs and box and box:GetDataProvider() == ours then
        give(box, theirs, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
        list.NoResultsText:SetShown(theirs:IsEmpty())
    end
    ours, theirs = nil, nil
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
