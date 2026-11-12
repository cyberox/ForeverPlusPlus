-- Item Tooltips' disenchant value: on a green, blue, or purple weapon or armor piece, what
-- disenchanting it gives on average, priced from Auction Prices while that's on, or else the
-- material it most likely gives. Shift adds every outcome with its chance, in gray. An item the
-- game disenchants into something not known yet says so, and the player's own disenchants teach
-- it. The rules are in Lib/Disenchant.lua.
local _, ns = ...

local ipairs, format, floor, type = ipairs, string.format, math.floor, type
local C_Item, C_Container, C_Timer = C_Item, C_Container, C_Timer
local GRAY_FONT_COLOR = GRAY_FONT_COLOR
local IsShiftKeyDown, GetTime = IsShiftKeyDown, GetTime
local GetLootSourceInfo, GetNumLootItems = GetLootSourceInfo, GetNumLootItems
local GetLootSlotLink, GetLootSlotInfo = GetLootSlotLink, GetLootSlotInfo

local L = ns.L
local ItemTooltip = ns.ItemTooltip
local Disenchant = ns.Disenchant

local module = ns.modules.ItemTooltips:NewPart({
    key = "disenchant", name = L.ITEMTOOLTIPS_DISENCHANT, description = L.DISENCHANT_DESC,
    section = L.DISENCHANT_TITLE, added = "1.0.0-beta.1",
}, {
    disenchant = false,
})

-- A material's name, or a stand-in while the client hasn't cached it (asking loads it, so the
-- next redraw has it).
local function materialName(itemID)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name then
        return name
    end
    if C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return format(L.DISENCHANT_UNKNOWN_ITEM, itemID)
end

-- "1-2 Soul Dust", or "1 Nexus Crystal".
local function amountText(each)
    local amount = each.min == each.max and each.min or format(L.DISENCHANT_RANGE, each.min, each.max)
    return format(L.DISENCHANT_AMOUNT, amount, materialName(each.item))
end

-- "75%", "99.5%", "0.5%".
local function chanceText(chance)
    local percent = chance * 100
    if percent == floor(percent) then
        return format(L.DISENCHANT_CHANCE, format("%d", percent))
    end
    return format(L.DISENCHANT_CHANCE, format("%.1f", percent))
end

-- The disenchant outcomes for an item and its bracket: both nil when it can't be disenchanted (or
-- its item info isn't cached yet), outcomes nil when what its bracket gives isn't known yet.
local function outcomesFor(itemID)
    local _, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
    if not quality then
        return nil
    end
    return Disenchant.ForItem(classID, quality, equipLoc, itemLevel)
end

local function addDisenchant(tooltip, data)
    local itemID = module.enabled and ItemTooltip.ItemID(data)
    if not itemID then
        return
    end
    local outcomes, bracket = outcomesFor(itemID)
    if not bracket then
        return
    end
    local db = module.db
    if not outcomes then
        -- The game says it disenchants, but not into what: learned from the first one done.
        ItemTooltip.AddInfo(tooltip, L.DISENCHANT_LINE, L.DISENCHANT_NOT_KNOWN, db.align, "gray")
        return
    end
    local value, missing = Disenchant.Value(outcomes, ns.Prices.Auction)
    if missing == 0 and value > 0 then
        ItemTooltip.AddInfo(tooltip, L.DISENCHANT_LINE, ns.Money(floor(value + 0.5)), db.align, "white")
    else
        -- No prices for every outcome: what it most likely gives instead.
        ItemTooltip.AddInfo(tooltip, L.DISENCHANT_LINE, amountText(outcomes[1]), db.align, "white")
    end
    if IsShiftKeyDown() then
        local r, g, b = GRAY_FONT_COLOR:GetRGB()
        for _, each in ipairs(outcomes) do
            tooltip:AddLine(format(L.DISENCHANT_OUTCOME, chanceText(each.chance), amountText(each)),
                r, g, b)
        end
        if outcomes[1].seen then
            tooltip:AddLine(format(L.DISENCHANT_SEEN, outcomes[1].seen), r, g, b)
        end
    end
end

-- Learning from play ------------------------------------------------------------------------------
-- A disenchant is a cast of Disenchant on a bag item, which the game locks while it casts, then
-- loot from that item. The cast's start names the item: the one disenchantable item locked in the
-- bags then (none or two, and it's left out). Its loot counts once the cast succeeds, only when
-- every item in it is an enchanting material (Trade Goods, Enchanting: 7, 12, as the client's Item
-- table has every Classic dust, essence, shard, and Nexus Crystal, build 70888), so a corpse's or
-- a chest's loot opened around it is never taken for one. Probe: the lock during the cast and
-- GetLootSourceInfo's "Item-" GUID are Mainline's; unverified on Forever.

local DISENCHANT_SPELL = ns.GameData.Spell(13262, "Disenchant") -- Enchanting's SkillLineAbility, 70888
local TRADE_GOODS, ENCHANTING = 7, 12
local LAST_BAG = 4
local WAIT = 5 -- seconds after the cast for its loot

local pending -- { castGUID, bracket, succeeded, items }

local function lockedItem()
    local found
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and ns.IsTrue(info.isLocked) and type(info.itemID) == "number" then
                local _, bracket = outcomesFor(info.itemID)
                if bracket then
                    if found then
                        return nil -- two: can't tell which
                    end
                    found = bracket
                end
            end
        end
    end
    return found
end

local function learn()
    local cast = pending
    pending = nil
    if cast and cast.items and cast.items[1] then
        Disenchant.Learn(cast.bracket, cast.items)
    end
end

local function isDisenchant(spellID)
    return ns.IsNumber(spellID) and spellID == DISENCHANT_SPELL
end

local function onStart(_, _, castGUID, spellID)
    if not isDisenchant(spellID) then
        return
    end
    local bracket = lockedItem()
    pending = bracket and { castGUID = ns.IsText(castGUID) and castGUID or nil, bracket = bracket } or nil
end

-- Whether an event's cast is the pending disenchant: its cast ID, or the spell when the start's
-- cast ID couldn't be read.
local function isPending(castGUID, spellID)
    if not (pending and isDisenchant(spellID)) then
        return false
    end
    return not pending.castGUID or (ns.IsText(castGUID) and castGUID == pending.castGUID)
end

local function onSucceeded(_, _, castGUID, spellID)
    if not isPending(castGUID, spellID) then
        return
    end
    pending.succeeded = GetTime()
    if pending.items then
        learn()
        return
    end
    local cast = pending
    C_Timer.After(WAIT, function()
        if pending == cast then
            pending = nil
        end
    end)
end

local function onFailed(_, _, castGUID, spellID)
    if isPending(castGUID, spellID) then
        pending = nil
    end
end

-- The loot, which can come before the cast's success.
local function onLoot()
    if not pending or pending.items then
        return
    end
    local source = GetLootSourceInfo and GetLootSourceInfo(1)
    if ns.IsText(source) and not source:find("^Item") then
        return
    end
    local items = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local _, _, count = GetLootSlotInfo(slot)
        local id, _, _, _, _, classID, subclassID
        if ns.IsText(link) then
            id, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
        end
        if not (ns.IsNumber(id) and classID == TRADE_GOODS and subclassID == ENCHANTING
            and ns.IsNumber(count)) then
            pending = nil -- not a disenchant's loot, or one it can't read whole
            return
        end
        items[#items + 1] = { id = id, count = count }
    end
    if not items[1] then
        return
    end
    pending.items = items
    if pending.succeeded then
        learn()
    end
end

function module:OnEnable()
    -- The hook can't be removed; addDisenchant checks the part is on instead.
    ItemTooltip.OnPrices(addDisenchant, module)
    -- Shift adds the outcomes.
    ItemTooltip.RedrawOnShift(self, true)
    self:OnUnit("UNIT_SPELLCAST_START", { "player" }, onStart)
    self:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
    self:OnUnit("UNIT_SPELLCAST_FAILED", { "player" }, onFailed)
    self:OnUnit("UNIT_SPELLCAST_INTERRUPTED", { "player" }, onFailed)
    -- Probe: LOOT_READY is Mainline's, before the window; Fast Loot takes the loot then.
    if ns.HasEvent("LOOT_READY") then
        self:On("LOOT_READY", onLoot)
    end
    self:On("LOOT_OPENED", onLoot)
end

function module:OnDisable()
    ItemTooltip.RedrawOnShift(self, false)
    pending = nil
end
