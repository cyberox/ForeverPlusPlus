-- Appearance Icons: marks gear whose appearance you haven't collected yet with Blizzard's
-- transmogrifier icon in a corner of the item's icon (top right by default, where nothing else of
-- ours or Blizzard's sits), so you wear it once before selling it. It shows in your bags and bank,
-- at merchants, in the auction house, and in the loot window and loot rolls, and on the row of a
-- recipe that makes such gear in the professions window, each with its own checkbox.
--
-- "Not collected" is what the game's own item tooltip says: its "You haven't collected this
-- appearance" line (TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN), seen on Forever in Cameron's
-- screenshot (2026-11-06). C_TransmogCollection is in Forever's API too (Gethe forever branch,
-- TransmogItemsDocumentation.lua), but the tooltip line is what the player sees, so it decides.
-- Nothing is written onto Blizzard's frames: our own texture sits on the icon.
local _, ns = ...

local _G, pairs, wipe = _G, pairs, wipe
local C_Item, C_Container, C_TradeSkillUI = C_Item, C_Container, C_TradeSkillUI
local GetTime = GetTime

local L = ns.L
local ItemButtons = ns.ItemButtons

local module = ns.NewModule("AppearanceIcons", L.APPEARANCEICONS_DESC, {
    enabled = true,
    corner = "TOPRIGHT", -- free of Upgrade Arrows (top left), Already Known (bottom left), and counts
    size = 18, -- in the bags; other places scale from it
    padding = 1, -- how far the icon sits in from its corner, in pixels, as Upgrade Arrows' arrow
    bags = true,
    bank = true,
    merchant = true,
    auction = true,
    loot = true,
    professions = true, -- on a recipe's row in the professions window
    recipeSpot = "right", -- where on the row: "right" end, "before" the name (and its arrow), or "after" it
    hideLine = false, -- leave the tooltip's "You haven't collected this appearance" out
})
module.title = L.APPEARANCEICONS_TITLE
module.category = "items"
module.added = "1.2.0"

local ATLAS = "poi-transmogrifier" -- the transmogrifier on the map (29x36), drawn square

module.options = {
    ItemButtons.CornerOption(L.APPEARANCEICONS_CORNER_DESC, L.APPEARANCEICONS_SECTION_ICON, {
        -- Other modules' marks in the same corner. Settings reads their settings and shows these
        -- only while that module is on.
        conflicts = {
            {
                module = "UpgradeArrows", key = "corner", text = L.APPEARANCEICONS_CONFLICT_ARROW,
                when = function(db, other)
                    return db.corner == other.corner
                end,
            },
            {
                module = "UpgradeArrows", key = "downCorner", text = L.APPEARANCEICONS_CONFLICT_DOWN,
                when = function(db, other)
                    return other.downgrades and db.corner == other.downCorner and other.downCorner ~= other.corner
                end,
            },
            {
                module = "AlreadyKnown", key = "corner", text = L.APPEARANCEICONS_CONFLICT_KNOWN,
                when = function(db, other)
                    return db.corner == other.corner and other.style ~= "tint"
                end,
            },
        },
    }),
    ItemButtons.SizeOption(L.APPEARANCEICONS_SIZE, L.APPEARANCEICONS_SIZE_DESC, L.APPEARANCEICONS_SECTION_ICON),
    ItemButtons.PaddingOption(L.APPEARANCEICONS_SECTION_ICON),
    ItemButtons.PlaceOption("bags", L.APPEARANCEICONS_BAGS_DESC),
    ItemButtons.PlaceOption("bank", L.APPEARANCEICONS_BANK_DESC),
    ItemButtons.PlaceOption("merchant", L.APPEARANCEICONS_MERCHANT_DESC),
    ItemButtons.PlaceOption("auction", L.APPEARANCEICONS_AUCTION_DESC),
    ItemButtons.PlaceOption("loot", L.APPEARANCEICONS_LOOT_DESC),
    { key = "professions", name = L.APPEARANCEICONS_PROFESSIONS, description = L.APPEARANCEICONS_PROFESSIONS_DESC,
        section = L.ICONMARK_SECTION_SHOW },
    {
        key = "recipeSpot", name = L.APPEARANCEICONS_RECIPE_SPOT, description = L.APPEARANCEICONS_RECIPE_SPOT_DESC,
        section = L.ICONMARK_SECTION_SHOW, requires = "professions",
        choices = {
            { "right", L.APPEARANCEICONS_RECIPE_SPOT_RIGHT },
            { "before", L.APPEARANCEICONS_RECIPE_SPOT_BEFORE },
            { "after", L.APPEARANCEICONS_RECIPE_SPOT_AFTER },
        },
    },
    {
        key = "hideLine", name = L.APPEARANCEICONS_HIDE_LINE, description = L.APPEARANCEICONS_HIDE_LINE_DESC,
        section = L.APPEARANCEICONS_SECTION_TOOLTIP, added = "1.5.0",
    },
}

local RECHECK = 10 -- seconds an answer is believed before a new look
local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass: only gear has an appearance

-- Is it collected --------------------------------------------------------------------------------

-- True when the tooltip says the appearance isn't collected, false when it doesn't, nil while
-- the game has no tooltip for the item yet (not cached), so that isn't taken for "collected".
local function tooltipUncollected(link)
    local unknown = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN
    if not unknown then
        return false
    end
    local lines = ItemButtons.TooltipLines(link)
    if not lines then
        return nil
    end
    for i = 2, #lines do -- line 1 is the name
        local text = lines[i].leftText
        if ns.IsText(text) and text == unknown then
            return true
        end
    end
    return false
end

-- Hide Tooltip Line: the icon says the same, so the tooltip's own line can go. The line is left out
-- as the tooltip is drawn; the lookup above reads the item's tooltip data, which still has it.
-- Runs before every line of every tooltip, so the option is checked first.
local function skipLine(_, line)
    if not module.db.hideLine then
        return false
    end
    local unknown, text = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN, line and line.leftText
    return unknown ~= nil and ns.IsText(text) and text == unknown
end

local results = {} -- link -> true (not collected) or false, with the time it was looked at
local checkedAt = {}
local waiting = {} -- itemID -> true while the game has no tooltip for it yet
-- The lookups' own row on the Profiler page: reading an item's tooltip is the costly part.
local Profiler = ns.Profiler
local PART_LOOKUP = Profiler.Part(module, L.APPEARANCEICONS_PART_LOOKUP)

-- Whether an item link is gear whose appearance isn't collected. An answer is kept, but looked at
-- again after a while or when the collection changes: wearing it collects it.
local function uncollected(link)
    if not link then
        return false
    end
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
    if not itemID or (classID ~= WEAPON and classID ~= ARMOR) then
        return false
    end
    local now = GetTime()
    local result = results[link]
    if result ~= nil and now - (checkedAt[link] or 0) < RECHECK then
        return result
    end
    result = Profiler.Call(PART_LOOKUP, tooltipUncollected, link)
    if result == nil then
        waiting[itemID] = true -- not loaded yet: look again when its data arrives
        return false
    end
    results[link], checkedAt[link] = result, now
    return result
end

local function forget()
    wipe(results)
    wipe(checkedAt)
end

-- Marks -----------------------------------------------------------------------------------------

local marks = ItemButtons.Overlays(function(icon)
    return icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
end)

local hasAtlas = false -- whether this client has the atlas, read in OnEnable

-- Shows or clears our mark on an icon.
local function setMark(icon, on)
    local mark = marks:Set(icon, on and hasAtlas)
    if not mark then
        return
    end
    -- Icon Size is a bag icon's; other icons get it in proportion.
    local size = ItemButtons.MarkSize(icon, module.db.size)
    mark:SetAtlas(ATLAS)
    mark:SetSize(size, size)
    ItemButtons.PlaceInCorner(mark, icon, module.db.corner, module.db.padding)
end

-- Bags and bank -----------------------------------------------------------------------------------

local function updateBag(frame)
    local on = module.db.bags
    ItemButtons.EachBagButton(frame, function(_, icon, bag, slot)
        local link = on and C_Container.GetContainerItemLink(bag, slot)
        setMark(icon, link and uncollected(link))
    end)
end

local function updateBank()
    local on = module.db.bank
    ItemButtons.EachBankButton(function(icon, tab, slot)
        local link = on and tab and C_Container.GetContainerItemLink(tab, slot)
        setMark(icon, link and uncollected(link))
    end)
end

-- Merchants -------------------------------------------------------------------------------------

local function updateMerchant()
    local on = module.db.merchant
    ItemButtons.EachMerchantItem(function(icon, index)
        setMark(icon, on and uncollected(_G.GetMerchantItemLink(index)))
    end)
end

-- The buyback tab reuses the same buttons.
local function clearMerchant(icon)
    setMark(icon, false)
end

-- Auction house and loot ------------------------------------------------------------------------

local function updateAuction()
    local on = module.db.auction
    ItemButtons.EachAuctionRow(function(icon, itemID)
        setMark(icon, on and itemID and uncollected("item:" .. itemID))
    end)
end

local function markLoot(icon, _, link)
    setMark(icon, module.db.loot and link and uncollected(link))
end

local function markRoll(icon, link)
    setMark(icon, module.db.loot and link and uncollected(link))
end

-- Professions -------------------------------------------------------------------------------------
-- The recipe list's rows have no item icon, so the mark goes on the row at text height, where the
-- Recipe Icon option says. Blizzard's row (ProfessionsRecipeListRecipeMixin, Gethe forever
-- branch), left to right: the skill-up arrow (SkillUps, 26 wide from 9 pixels left of the row,
-- its arrow at its right and a number left of that), the name, the "[3]" craftable count, and at
-- the right end the lock icon of a disabled recipe. Nothing of Blizzard's is moved.

local ROW_SIZE = 14
-- Where the skill-up arrow starts, from the row's left: its slot starts 9 pixels left of the row
-- and is 26 wide, and the arrow (13 wide, professions-icon-skill-*) sits at the slot's right.
local ARROW_LEFT = -9 + 26 - 13

-- The mark's column at the row's right end (Professions.NewRowColumn), in use while Recipe Icon
-- is there: the Professions module's skill-ups number and profit sit left of it then.
local endColumn = ns.Professions.NewRowColumn(10, ROW_SIZE, 2)

local rowMarks = ItemButtons.Overlays(function(row)
    return row:CreateTexture(nil, "OVERLAY", nil, 7)
end)

local outputs = {} -- recipeID -> the item it makes, or false for none (an enchant)

local function outputOf(recipeID)
    local item = outputs[recipeID]
    if item == nil then
        local T = C_TradeSkillUI
        local schematic = T and T.GetRecipeSchematic and T.GetRecipeSchematic(recipeID, false)
        item = schematic and schematic.outputItemID or false
        outputs[recipeID] = item
    end
    return item or nil
end

local function markRow(row, node)
    if not (row and row.Label) then
        return
    end
    local on = module.enabled and module.db.professions and hasAtlas
    local recipeID
    if on then
        local info = ns.Professions.RowRecipe(row, node)
        recipeID = info and info.recipeID
    end
    local spot = module.db.recipeSpot
    local atEnd = spot ~= "after" and spot ~= "before"
    endColumn:Use(on and atEnd)
    local item = recipeID and outputOf(recipeID)
    local mark = rowMarks:Set(row, item and uncollected("item:" .. item))
    if not mark then
        endColumn:Place(row, nil)
        return
    end
    mark:SetAtlas(ATLAS)
    mark:SetSize(ROW_SIZE, ROW_SIZE)
    if atEnd then
        -- At the row's right end, left of a disabled recipe's lock icon.
        endColumn:Place(row, mark)
        return
    end
    endColumn:Place(row, nil)
    mark:ClearAllPoints()
    if spot == "after" then
        -- After the name, or after its count when that shows.
        local after = row.Count and row.Count:IsShown() and row.Count or row.Label
        mark:SetPoint("LEFT", after, "RIGHT", 2, 0)
    elseif spot == "before" then
        -- One column on every row, just left of where the skill-up arrow goes (13 wide, its
        -- left edge 4 pixels into the row), whether a row has an arrow or not, so the names
        -- don't look indented. Only the arrow's "2" for several skill-ups pushes it further left.
        local skillUps = row.SkillUps
        local text = skillUps and skillUps:IsShown() and skillUps.Text
        if text and text:IsShown() then
            mark:SetPoint("RIGHT", text, "LEFT", -1, 0)
        else
            mark:SetPoint("RIGHT", row, "LEFT", ARROW_LEFT - 1, 0)
        end
    end
end

local ROW_HOOKS = { Init = markRow }

local function updateRecipes()
    ns.Professions.EachRecipeRow(markRow)
end

-- The rows' mixin is in a load-on-demand Blizzard addon: hooked once it's there.
local function hookRecipes()
    ns.Professions.HookRecipeRows(module, ROW_HOOKS)
end

-- Module ----------------------------------------------------------------------------------------

local function refresh()
    updateRecipes()
    if ItemButtons.MerchantShown() then
        updateMerchant()
    end
    updateAuction()
    ItemButtons.EachOpenBag(updateBag)
    local bank = _G.BankFrame
    if bank and bank:IsShown() then
        updateBank()
    end
    ItemButtons.EachRoll(markRoll)
    ItemButtons.EachLootSlot(markLoot)
end

local refreshSoon = ns.Frames.Coalesce(function()
    if module.enabled then
        refresh()
    end
end, 0.5, module)

-- Item data arrives a little after a window opens; look again once it has, only for an item we
-- couldn't answer for yet, or while a merchant is open, whose links are missing until it loads.
local function onItemInfo(_, itemID)
    local merchant = _G.MerchantFrame
    if not ((itemID and waiting[itemID]) or (merchant and merchant:IsShown())) then
        return
    end
    if itemID then
        waiting[itemID] = nil
    end
    refreshSoon()
end

-- Collecting an appearance (wearing it, or one like it) changes the answers.
local function onCollectionChanged()
    forget()
    refreshSoon()
end

-- The professions window is a load-on-demand addon: hook its recipe rows once they're there.
local function onProfessions()
    hookRecipes()
    refreshSoon()
end

function module:OnEnable()
    hasAtlas = ns.Frames.HasAtlas(ATLAS)
    -- Probe: line pre calls are Mainline's; the line has no kind of its own, so every kind is asked.
    self:TooltipLinePreCall(TooltipDataProcessor and TooltipDataProcessor.AllTypes, skipLine)
    hookRecipes()
    self:On("ADDON_LOADED", onProfessions)
    self:On("TRADE_SKILL_SHOW", onProfessions)
    self:On("TRADE_SKILL_LIST_UPDATE", onProfessions)
    ItemButtons.HookMerchant(self, updateMerchant, clearMerchant)
    ItemButtons.HookBags(self, updateBag)
    ItemButtons.HookBank(self, updateBank)
    ItemButtons.HookLoot(self, markLoot)
    ItemButtons.HookRolls(self, markRoll)
    ItemButtons.HookAuction(self, updateAuction)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
    self:On("PLAYER_EQUIPMENT_CHANGED", onCollectionChanged)
    for _, event in pairs({ "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED" }) do
        if ns.HasEvent(event) then
            self:On(event, onCollectionChanged)
        end
    end
    refresh()
end

function module:OnDisable()
    ItemButtons.CancelAuction(updateAuction)
    marks:HideAll()
    rowMarks:HideAll()
    endColumn:Use(false)
    forget()
    wipe(waiting)
end

function module:OnOptionChanged()
    if self.enabled then
        refresh()
    end
end
