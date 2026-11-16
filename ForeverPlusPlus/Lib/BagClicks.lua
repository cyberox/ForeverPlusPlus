-- Secure right-clicks on items in Blizzard's bags, for modules whose right-click has to do what
-- only a hardware click may: use an item on a weapon, or cast a spell on the item.
--
-- Forever forbids addons from answering the targeting cursor themselves (PickupInventoryItem is
-- ADDON_ACTION_FORBIDDEN there), so this lays an invisible secure button over each matching item.
-- Its right-click does what the module's attributes say; every other click, drag, and the tooltip
-- go through to the bag slot as before. Secure buttons can't be placed in combat, so the overlays
-- leave when combat starts and the bags work as Blizzard's until it ends. Bag addons that replace
-- Blizzard's bags get no overlays: only a bag that is on screen does.
local _, ns = ...

local C_Container = C_Container
local CreateFrame, InCombatLockdown, IsModifierKeyDown = CreateFrame, InCombatLockdown, IsModifierKeyDown
local GameTooltip, UIParent = GameTooltip, UIParent
local pairs, setmetatable, _G = pairs, setmetatable, _G
local tremove = table.remove

local BagClicks = {}
ns.BagClicks = BagClicks

-- A right-click in the bags means something else while one of these is open (sell, deposit,
-- attach, trade, auction, guild bank), so it goes to Blizzard's button then.
local function busy()
    local frames = { _G.MerchantFrame, _G.BankFrame, _G.SendMailFrame, _G.TradeFrame, _G.AuctionHouseFrame,
        _G.GuildBankFrame }
    for i = 1, 6 do
        if frames[i] and frames[i]:IsShown() then
            return true
        end
    end
    return false
end

local ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }

local info = {} -- overlay -> { set, bag, slot, button, value, handled }

-- Clicks come on both press and release (the secure template acts on whichever the client's
-- ActionButtonUseKeyDown setting says); everything is worked out again for each.
local function onPreClick(self, mouseButton, down)
    local data = info[self]
    local handled = false
    if not InCombatLockdown() then
        self:SetAttribute("type2", nil)
        if mouseButton == "RightButton" and not IsModifierKeyDown() and not busy() then
            handled = data.set.click(self, data.value, data.bag, data.slot, down) and true or false
        end
    end
    data.handled = handled
end

-- Anything the secure click didn't do goes to Blizzard's bag button, as if it had been clicked,
-- once, on release like Blizzard's.
local function onPostClick(self, mouseButton, down)
    local data = info[self]
    if not down and not data.handled then
        data.button:Click(mouseButton)
    end
end

local function onDrag(self)
    local data = info[self]
    C_Container.PickupContainerItem(data.bag, data.slot)
end

local function onEnter(self)
    local data = info[self]
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    if ContainerFrameItemButton_CalculateItemTooltipAnchors then
        ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    GameTooltip:SetBagItem(data.bag, data.slot)
    GameTooltip:Show()
end

local function onLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function newOverlay(set)
    local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyUp", "AnyDown")
    overlay:RegisterForDrag("LeftButton")
    overlay:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    overlay:SetScript("PreClick", onPreClick)
    overlay:SetScript("PostClick", onPostClick)
    overlay:SetScript("OnDragStart", onDrag)
    overlay:SetScript("OnReceiveDrag", onDrag)
    overlay:SetScript("OnEnter", onEnter)
    overlay:SetScript("OnLeave", onLeave)
    info[overlay] = { set = set }
    return overlay
end

local Set = {}
Set.__index = Set

---Takes every overlay away. Only out of combat (or at PLAYER_REGEN_DISABLED, just before it); if
---lockdown has already started, once it ends.
function Set:Clear()
    if InCombatLockdown() then
        ns.AfterCombat(self.clear)
        return
    end
    local active, spare = self.active, self.spare
    for i = #active, 1, -1 do
        local overlay = active[i]
        overlay:Hide()
        overlay:ClearAllPoints()
        active[i] = nil
        spare[#spare + 1] = overlay
    end
end

---Lays one overlay, spare or new, over a bag button. Out of combat only.
function Set:Place(button, bag, slot, value)
    local overlay = tremove(self.spare) or newOverlay(self)
    local data = info[overlay]
    data.bag, data.slot, data.button, data.value, data.handled = bag, slot, button, value, false
    -- A strata above the bag's: bags are top-level frames, and raising one when it's clicked or
    -- opened lifts its buttons over anything at their own strata.
    overlay:SetFrameStrata(ABOVE[button:GetFrameStrata()] or "DIALOG")
    overlay:SetAllPoints(button)
    overlay:Show()
    self.active[#self.active + 1] = overlay
end

---Lays the overlays again over every shown bag item `match` takes. Does nothing in combat.
function Set:Update()
    if InCombatLockdown() then
        return
    end
    self:Clear()
    if not self.module.enabled or (self.wanted and not self.wanted()) then
        return
    end
    -- With the controller interface on, the cursor presses Blizzard's own item button
    -- (SmartNavigation's MouseDown and MouseUp), never an overlay over it, which would only sit
    -- in the mouse's way.
    if ns.Menus.GamepadUI() then
        return
    end
    local match = self.match
    for _, frame in pairs(ns.ItemButtons.Frames()) do
        -- On screen, not only shown: a bag addon keeps Blizzard's bags shown under a hidden parent
        -- or at no alpha, and an overlay there would be an unseen item over whatever is drawn in
        -- that spot.
        if frame:IsVisible() and frame:GetEffectiveAlpha() > 0 and frame.EnumerateValidItems then
            for _, button in frame:EnumerateValidItems() do
                if button:IsVisible() then
                    local bag, slot = button:GetBagID(), button:GetID()
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    local value = itemID and match(itemID, bag, slot)
                    if value then
                        self:Place(button, bag, slot, value)
                    end
                end
            end
        end
    end
end

---Updates the overlays on the next frame, once however many times it's called before then (bags
---call UpdateItems once per bag).
function Set:Refresh()
    self.refresh()
end

---Starts laying overlays; call from the module's OnEnable. Hooks and events go through the
---module, so they stop by themselves when it turns off.
function Set:Enable()
    local module, refresh = self.module, self.refresh
    for _, frame in pairs(ns.ItemButtons.Frames()) do
        module:Hook(frame, "UpdateItems", refresh)
        module:HookScript(frame, "OnShow", refresh)
        module:HookScript(frame, "OnHide", refresh)
    end
    module:On("BAG_UPDATE_DELAYED", refresh)
    module:On("PLAYER_REGEN_ENABLED", refresh)
    -- Fires just before combat lockdown starts, the last moment secure buttons can move.
    module:On("PLAYER_REGEN_DISABLED", self.clear)
    refresh()
end

---Takes the overlays away, now or once combat ends; call from the module's OnDisable.
function Set:Disable()
    ns.AfterCombat(self.clear)
end

---A set of overlays for one module.
---`match(itemID, bag, slot)` says which items get one: any value but nil or false, handed back to
---`click`. `click(overlay, value, bag, slot, down)` runs on a plain right-click out of combat
---when nothing else wants it (no merchant, bank, mail, trade, auction house, or guild bank), on
---press and on release. It sets the overlay's secure attributes for that click (`type2`, cleared
---before it runs, and what goes with it) and returns true when it took the click; false sends
---the click to Blizzard's bag button as usual. `wanted()`, when given, says whether any item could
---match right now; while it's false the bags aren't looked through at all.
---@param module table
---@param match fun(itemID: number, bag: number, slot: number): any
---@param click fun(overlay: table, value: any, bag: number, slot: number, down: boolean): boolean?
---@param wanted? fun(): boolean
---@return table set
function BagClicks.New(module, match, click, wanted)
    local set = setmetatable({ module = module, match = match, click = click, wanted = wanted,
        active = {}, spare = {} }, Set)
    set.refresh = ns.Frames.Coalesce(function()
        set:Update()
    end, nil, set.module)
    set.clear = function()
        set:Clear()
    end
    return set
end

---Whether Blizzard's bags are there to lay overlays on.
---@return boolean
function BagClicks.IsAvailable()
    return C_Container and C_Container.GetContainerItemID and C_Container.PickupContainerItem
        and _G.ContainerFrame1 and true or false
end
