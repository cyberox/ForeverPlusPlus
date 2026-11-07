-- Blizzard's item buttons, for modules that mark items on them: the bag windows and their buttons,
-- the bank's, the merchant's buttons, the auction house's browse list, the loot window and loot
-- rolls, quest reward choices, our own textures laid over their icons, and an item's tooltip
-- lines. Nothing is written onto Blizzard's frames: what a module lays on an icon is kept in a
-- weak table of its own.
local _, ns = ...

local _G, ipairs, pairs, type, setmetatable, floor = _G, ipairs, pairs, type, setmetatable, math.floor
local C_TooltipInfo = C_TooltipInfo

local ItemButtons = {}
ns.ItemButtons = ItemButtons

local function weak()
    return setmetatable({}, { __mode = "k" })
end

-- Marks on icons --------------------------------------------------------------------------------
-- Every module that puts a mark on an item or action button icon (Upgrade Arrows, Appearance
-- Icons, Already Known, Spell Ranks) offers the same options for it, in this order: its style if
-- it has one, Corner, a size in pixels (step 2, up to 32), and Padding (0 to 10 pixels, 1 by
-- default).

local L = ns.L

---The corners a mark can sit in, as a dropdown's choices.
ItemButtons.CORNERS = {
    { "TOPLEFT", L.ICONMARK_CORNER_TOPLEFT },
    { "TOPRIGHT", L.ICONMARK_CORNER_TOPRIGHT },
    { "BOTTOMLEFT", L.ICONMARK_CORNER_BOTTOMLEFT },
    { "BOTTOMRIGHT", L.ICONMARK_CORNER_BOTTOMRIGHT },
}

-- An option with `extra`'s fields (added, shown, conflicts, a different min) laid over it.
local function withExtra(option, extra)
    for key, value in pairs(extra or {}) do
        option[key] = value
    end
    return option
end

---The Corner dropdown (key `corner`), the same for every mark.
---@param description string what sits in the corner, in the module's words
---@param section? string
---@param extra? table more fields for the option
---@return table option
function ItemButtons.CornerOption(description, section, extra)
    return withExtra({
        key = "corner", name = L.ICONMARK_CORNER, description = description, section = section,
        choices = ItemButtons.CORNERS,
    }, extra)
end

---The mark's size slider (key `size`): 8 to 32 pixels in steps of 2 unless `extra` says otherwise.
---@param name string "Arrow Size", "Check Size"
---@param description string
---@param section? string
---@param extra? table
---@return table option
function ItemButtons.SizeOption(name, description, section, extra)
    return withExtra({
        key = "size", name = name, description = description, section = section,
        min = 8, max = 32, step = 2, format = L.ICONMARK_PIXELS,
    }, extra)
end

---The Padding slider (key `padding`), 0 to 10 pixels, the same for every mark.
---@param section? string
---@param extra? table
---@return table option
function ItemButtons.PaddingOption(section, extra)
    return withExtra({
        key = "padding", name = L.ICONMARK_PADDING, description = L.ICONMARK_PADDING_DESC,
        section = section, min = 0, max = 10, step = 1, format = L.ICONMARK_PIXELS,
    }, extra)
end

-- The places a module can mark items in, by their option keys, with the same names everywhere.
local PLACE_NAMES = {
    bags = L.ICONMARK_PLACE_BAGS,
    bank = L.ICONMARK_PLACE_BANK,
    merchant = L.ICONMARK_PLACE_MERCHANT,
    auction = L.ICONMARK_PLACE_AUCTION,
    loot = L.ICONMARK_PLACE_LOOT,
    mail = L.ICONMARK_PLACE_MAIL,
    quests = L.ICONMARK_PLACE_QUESTS,
}

---A place's checkbox in a mark's Show On section (key `place`): its name is the same in every
---module, its description says what that module does there. List them bags, bank, merchant,
---auction, loot, then the module's own (mail, quests).
---@param place string bags, bank, merchant, auction, loot, mail, or quests
---@param description string
---@param extra? table
---@return table option
function ItemButtons.PlaceOption(place, description, extra)
    return withExtra({
        key = place, name = PLACE_NAMES[place], description = description,
        section = L.ICONMARK_SECTION_SHOW,
    }, extra)
end

-- A bag slot's icon (ContainerFrameItemButtonTemplate, 37 square): a mark's Size option is its
-- size there.
ItemButtons.BAG_ICON = 37

---A mark's size on `icon`: `size` pixels on an icon `reference` wide (a bag icon unless given),
---in proportion to this icon's own width, so a mark looks the same on a loot roll, a merchant's
---item, or the auction house's small icons. `size` itself while the icon has no width yet.
---@param icon table? the region the mark sits on
---@param size number
---@param reference? number
---@return number
function ItemButtons.MarkSize(icon, size, reference)
    local width = icon and icon.GetWidth and icon:GetWidth()
    if ns.IsNumber(width) and width > 0 then
        return floor(size * width / (reference or ItemButtons.BAG_ICON) + 0.5)
    end
    return size
end

---Puts a mark in a corner of an icon (or any region), `padding` pixels in from it: right and down
---from the top left, left and up from the bottom right.
---@param mark table a Texture
---@param icon table the region it sits on
---@param corner string TOPLEFT, TOPRIGHT, BOTTOMLEFT, or BOTTOMRIGHT
---@param padding? number
function ItemButtons.PlaceInCorner(mark, icon, corner, padding)
    padding = padding or 0
    local x = corner:find("LEFT") and padding or -padding
    local y = corner:find("TOP") and -padding or padding
    mark:ClearAllPoints()
    mark:SetPoint(corner, icon, corner, x, y)
end

local bagFrames

---Blizzard's bag windows that are there: the combined bags, then one per bag. FrameXML makes
---them at load, so the list is made once; don't change it.
---@return table[]
function ItemButtons.Frames()
    if not bagFrames then
        bagFrames = { _G.ContainerFrameCombinedBags }
        for i = 1, _G.NUM_CONTAINER_FRAMES or 13 do
            bagFrames[#bagFrames + 1] = _G["ContainerFrame" .. i]
        end
    end
    return bagFrames
end

---Calls `fn(button, icon, bag, slot)` for each item button in a bag window.
---@param frame table a bag window from `ItemButtons.Frames`
---@param fn function
function ItemButtons.EachBagButton(frame, fn)
    if not frame.EnumerateValidItems then
        return
    end
    for _, button in frame:EnumerateValidItems() do
        local bag = button.GetBagID and button:GetBagID() or button:GetParent():GetID()
        fn(button, button.icon or button.Icon, bag, button:GetID())
    end
end

---Runs `update(frame)` as each bag window draws its items (a hook through `module`, so it stops
---when the module turns off).
---@param module table
---@param update fun(frame: table)
function ItemButtons.HookBags(module, update)
    for _, frame in ipairs(ItemButtons.Frames()) do
        module:Hook(frame, "UpdateItems", update) -- skipped on a window without it
    end
end

---Calls `update(frame)` for each bag window that's open.
---@param update fun(frame: table)
function ItemButtons.EachOpenBag(update)
    for _, frame in ipairs(ItemButtons.Frames()) do
        if frame:IsShown() then
            update(frame)
        end
    end
end

-- Bank --------------------------------------------------------------------------------------------

---Calls `fn(icon, tab, slot)` for each item button of the bank's shown tab, with its bag (tab)
---and slot for C_Container (nil when the button can't say). Forever's bank is Blizzard's
---BankPanel with tabs (Blizzard_UIPanels_Game, Camelot BankFrame).
---@param fn fun(icon: table?, tab: number?, slot: number?)
function ItemButtons.EachBankButton(fn)
    local panel = _G.BankPanel
    if not (panel and panel.EnumerateValidItems) then
        return
    end
    for button in panel:EnumerateValidItems() do
        local tab, slot
        if button.GetBankTabID and button.GetContainerSlotID then
            tab, slot = button:GetBankTabID(), button:GetContainerSlotID()
        end
        fn(button.icon, tab, slot)
    end
end

---Runs `update()` as the bank draws its shown tab's items, through `module` (so it stops when the
---module turns off).
---@param module table
---@param update fun()
function ItemButtons.HookBank(module, update)
    module:Hook(_G.BankPanel, "RefreshAllItemsForSelectedTab", update)
    module:Hook(_G.BankPanel, "GenerateItemSlotsForSelectedTab", update)
end

-- Merchant ----------------------------------------------------------------------------------------

---The icon of the merchant's `i`th button on the page, or nil.
---@param i number
---@return table?
function ItemButtons.MerchantIcon(i)
    local button = _G["MerchantItem" .. i .. "ItemButton"]
    return button and (button.icon or _G["MerchantItem" .. i .. "ItemButtonIconTexture"])
end

---Calls `fn(icon, index)` for each button on the merchant's page, with the merchant item index it
---shows (for GetMerchantItemLink). Does nothing without the merchant window.
---@param fn function
function ItemButtons.EachMerchantItem(fn)
    local frame = _G.MerchantFrame
    if not (frame and _G.GetMerchantItemLink) then
        return
    end
    local perPage = _G.MERCHANT_ITEMS_PER_PAGE or 10
    for i = 1, perPage do
        fn(ItemButtons.MerchantIcon(i), ((frame.page or 1) - 1) * perPage + i)
    end
end

---Whether the merchant window shows its Merchant tab: Buyback shows its items on the same buttons.
---@return boolean
function ItemButtons.MerchantShown()
    local frame = _G.MerchantFrame
    return frame and frame:IsShown() and (frame.selectedTab or 1) == 1 or false
end

local clearers = weak() -- clear -> the function hooked for it, the same one every OnEnable, since
-- module:Hook hooks once per function and a new one would hook again each time the module turns on

---Marks the merchant's items while a module is on: `update()` when the Merchant tab draws, and
---`clear(icon)` on each button when the Buyback tab draws on the same buttons.
---@param module table
---@param update fun()
---@param clear fun(icon: table)
function ItemButtons.HookMerchant(module, update, clear)
    module:Hook("MerchantFrame_UpdateMerchantInfo", update)
    local clearAll = clearers[clear]
    if not clearAll then
        clearAll = function()
            ItemButtons.EachMerchantItem(clear)
        end
        clearers[clear] = clearAll
    end
    module:Hook("MerchantFrame_UpdateBuybackInfo", clearAll)
end

-- Auction house -----------------------------------------------------------------------------------

-- The browse list's scroll box. Its rows are read as we see them, never Blizzard's category
-- tables: adding to those taints the auction house.
local function browseList()
    local frame = _G.AuctionHouseFrame
    local results = frame and frame.BrowseResultsFrame
    return results and results.ItemList and results.ItemList.ScrollBox
end

---Calls `fn(icon, itemID)` for each row the auction house's browse list shows. `itemID` is nil
---for a row without an item.
---@param fn fun(icon: table, itemID: number?)
function ItemButtons.EachAuctionRow(fn)
    -- Nothing to mark while the window is closed: its rows hold the last search, and the list's
    -- Update hook (HookAuction) marks them when it opens.
    local frame = _G.AuctionHouseFrame
    local box = frame and frame:IsShown() and browseList()
    if not (box and box.ScrollTarget) then
        return
    end
    for _, row in ipairs({ box.ScrollTarget:GetChildren() }) do
        local itemKey = row.rowData and row.rowData.itemKey
        local cell = row.cells and row.cells[2]
        if itemKey and cell and cell.Icon then
            fn(cell.Icon, itemKey.itemID)
        end
    end
end

local auctionHooks = {} -- update -> the function waiting for the auction house to load

---Runs `update()` as the auction house's browse list redraws, through `module` (so it stops when
---the module turns off), from now or once the load-on-demand auction house has loaded. Call
---`ItemButtons.CancelAuction(update)` from OnDisable.
---@param module table
---@param update fun()
function ItemButtons.HookAuction(module, update)
    local hook = auctionHooks[update]
    if not hook then
        hook = function()
            local box = browseList()
            if box and type(box.Update) == "function" then
                module:Hook(box, "Update", update)
                update()
            end
        end
        auctionHooks[update] = hook
    end
    ns.AddOns.WhenLoaded("Blizzard_AuctionHouseUI", hook)
end

---Stops waiting for the auction house to hook `update`.
---@param update fun()
function ItemButtons.CancelAuction(update)
    local hook = auctionHooks[update]
    if hook then
        ns.AddOns.Cancel("Blizzard_AuctionHouseUI", hook)
    end
end

-- Loot ------------------------------------------------------------------------------------------

-- A loot window row's icon, its loot slot, and the item's link.
local function lootSlot(frame, elementData, fn)
    local item = frame.Item
    local icon = item and (item.icon or item.Icon)
    local slot = elementData and elementData.slotIndex
    if type(slot) ~= "number" then
        fn(icon, nil, nil)
        return
    end
    fn(icon, slot, _G.GetLootSlotLink and _G.GetLootSlotLink(slot))
end

local lootHooked = {} -- fn -> true once its callback is on the loot window
local lootHooks = {} -- fn -> the function that puts its callback on the loot window

---Calls `fn(icon, slot, link)` for each row of the loot window as it shows, while `module` is on.
---Call it from OnEnable: it tries now and again on each LOOT_OPENED while the module is on, since
---the loot window may not be made yet. Once per `fn`: the callback can't come off. Probe: the
---scroll box and the callback are Mainline's, and this is unverified on Forever.
---@param module table
---@param fn fun(icon: table?, slot: number?, link: string?)
function ItemButtons.HookLoot(module, fn)
    local hook = lootHooks[fn]
    if not hook then
        hook = function()
            local box = _G.LootFrame and _G.LootFrame.ScrollBox
            if lootHooked[fn] or not (box and _G.ScrollUtil and _G.ScrollUtil.AddAcquiredFrameCallback) then
                return
            end
            lootHooked[fn] = true
            _G.ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame, elementData)
                if module.enabled then
                    lootSlot(frame, elementData, fn)
                end
            end, module, false)
            -- Not iterateExisting: it calls back without the owner argument, so rows showing now
            -- are marked here instead.
            if module.enabled then
                ItemButtons.EachLootSlot(fn)
            end
        end
        lootHooks[fn] = hook
    end
    hook()
    module:On("LOOT_OPENED", hook)
end

---Calls `fn(icon, slot, link)` for each row of the loot window while it's open.
---@param fn fun(icon: table?, slot: number?, link: string?)
function ItemButtons.EachLootSlot(fn)
    local loot = _G.LootFrame
    local box = loot and loot.ScrollBox
    if loot and loot:IsShown() and box and box.ForEachFrame then
        box:ForEachFrame(function(frame, elementData)
            lootSlot(frame, elementData, fn)
        end)
    end
end

-- Loot rolls: GroupLootFrame1..4 (Mainline's, which Forever loads), each showing its rollID's item
-- on IconFrame.Icon.
local ROLL_FRAMES = _G.NUM_GROUP_LOOT_FRAMES or 4

local function roll(frame, fn)
    local icon = frame.IconFrame and frame.IconFrame.Icon
    local rollID = frame.rollID
    fn(icon, rollID and _G.GetLootRollItemLink and _G.GetLootRollItemLink(rollID))
end

local rollHooks = weak() -- fn -> its OnShow handler

---Calls `fn(icon, link)` for a loot roll as its frame shows, before the player picks Need,
---through `module` (so it stops when the module turns off).
---@param module table
---@param fn fun(icon: table?, link: string?)
function ItemButtons.HookRolls(module, fn)
    local onShow = rollHooks[fn]
    if not onShow then
        onShow = function(frame)
            roll(frame, fn)
        end
        rollHooks[fn] = onShow
    end
    for i = 1, ROLL_FRAMES do
        module:HookScript(_G["GroupLootFrame" .. i], "OnShow", onShow)
    end
end

---Calls `fn(icon, link)` for each loot roll that shows.
---@param fn fun(icon: table?, link: string?)
function ItemButtons.EachRoll(fn)
    for i = 1, ROLL_FRAMES do
        local frame = _G["GroupLootFrame" .. i]
        if frame and frame:IsShown() then
            roll(frame, fn)
        end
    end
end

-- Quest rewards ---------------------------------------------------------------------------------
-- The reward buttons are Blizzard's (QuestInfo_Display fills them, both for a quest giver and the
-- quest log). Probe: those names are Mainline's, unverified on Forever.

---A quest reward button's icon region, where a mark on it goes (the button itself without one).
---@param button table
---@return table
function ItemButtons.RewardIcon(button)
    return button.Icon or button.icon or button
end

---Calls `fn(button, index, link, questLog)` for each item choice a quest's rewards frame shows:
---its choice index, its item link (nil while the game doesn't have it), and whether it's the
---quest log's rather than a quest giver's. Hides `overlays`' texture on every reward button
---first, when given, so a module clears its marks in the same walk.
---@param rewardsFrame table? such as QuestInfoFrame.rewardsFrame
---@param fn fun(button: table, index: number, link: string?, questLog: boolean?)
---@param overlays? table a set from `ItemButtons.Overlays`
---@return boolean walked false when there's no rewards frame with buttons to walk
function ItemButtons.EachRewardChoice(rewardsFrame, fn, overlays)
    local info = _G.QuestInfoFrame
    local buttons = rewardsFrame and rewardsFrame.RewardButtons
    if not (info and type(buttons) == "table") then
        return false
    end
    local questLog = info.questLog
    for _, button in ipairs(buttons) do
        if overlays then
            overlays:Set(button, false)
        end
        -- Currency choices aren't items; objectType is Mainline's, so missing means item.
        local object = button.objectType
        if button:IsShown() and button.type == "choice" and (object == nil or object == "item") then
            local index = button:GetID()
            local link
            if questLog then
                link = _G.GetQuestLogItemLink and _G.GetQuestLogItemLink("choice", index)
            else
                link = _G.GetQuestItemLink and _G.GetQuestItemLink("choice", index)
            end
            fn(button, index, link, questLog)
        end
    end
    return true
end

-- Overlays --------------------------------------------------------------------------------------

local Overlays = {}
Overlays.__index = Overlays

---Shows the texture over `key` (an icon or a button), made the first time it's needed, or hides
---it. Returns it while it shows.
---@param key table?
---@param on any
---@return table? texture
function Overlays:Set(key, on)
    if not key then
        return nil
    end
    local texture = self.made[key]
    if not on then
        if texture then
            texture:Hide()
        end
        return nil
    end
    if not texture then
        texture = self.make(key)
        self.made[key] = texture
    end
    texture:Show()
    return texture
end

---Hides every texture made, for OnDisable.
function Overlays:HideAll()
    for _, texture in pairs(self.made) do
        texture:Hide()
    end
end

---A set of our own textures, one per icon (or button), each made by `make(key)` the first time
---it's shown: `set:Set(key, on)` shows or hides it, `set:HideAll()` hides them all. Kept in a weak
---table, never on Blizzard's frames.
---@param make fun(key: table): table
---@return table set
function ItemButtons.Overlays(make)
    return setmetatable({ make = make, made = weak() }, Overlays)
end

---A new texture just above an icon that multiplies it by a color (MOD blend), so it looks like a
---vertex color without touching the icon's own, which Blizzard sets itself. The caller keeps it.
---@param icon table a Texture
---@param color number[] { r, g, b }
---@return table texture
function ItemButtons.Tint(icon, color)
    local layer, sublevel = icon:GetDrawLayer()
    sublevel = sublevel or 0
    local tint = icon:GetParent():CreateTexture(nil, layer, nil, sublevel < 7 and sublevel + 1 or 7)
    tint:SetColorTexture(color[1], color[2], color[3])
    tint:SetBlendMode("MOD")
    tint:SetAllPoints(icon)
    return tint
end

---An item's tooltip lines, or nil while the game has no tooltip for it yet (not cached), so that
---isn't taken for an answer.
---@param link string
---@return table[]?
function ItemButtons.TooltipLines(link)
    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link)
    local lines = data and ns.IsReadable(data) and data.lines
    if type(lines) ~= "table" or #lines == 0 then
        return nil
    end
    return lines
end

-- Blizzard's red (1, 0.125, 0.125), with room for rounding: a tooltip line for something the
-- character lacks (a class, armor skill, level, or profession).
local function isRed(color)
    if not (color and ns.IsReadable(color)) then
        return false
    end
    local r, g, b = color.r, color.g, color.b
    if not (ns.IsNumber(r) and type(g) == "number" and type(b) == "number") then
        return false
    end
    local red = _G.RED_FONT_COLOR
    local rr, rg, rb = red and red.r or 1, red and red.g or 0.125, red and red.b or 0.125
    return r > rr - 0.05 and g < rg + 0.05 and b < rb + 0.05
end

---Whether a tooltip line (from `TooltipLines`) is in Blizzard's red, on its left or right text.
---@param line table
---@return boolean
function ItemButtons.IsRedLine(line)
    if not ns.IsReadable(line) then
        return false
    end
    return isRed(line.leftColor) or (line.rightText ~= nil and isRed(line.rightColor))
end
