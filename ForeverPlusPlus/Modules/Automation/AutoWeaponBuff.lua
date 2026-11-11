-- Auto Weapon Buff: right-clicking a sharpening stone, weightstone, oil, poison, or fishing lure in
-- your bags puts it straight onto your weapon instead of waiting for you to click the weapon, and
-- so does using one from an action bar.
--
-- Forever forbids addons from answering the targeting cursor themselves, so each such item in
-- Blizzard's bags gets a secure overlay (ns.BagClicks) whose right-click uses the item and then the
-- weapon slot through Blizzard's own `target-slot` attribute. Not in combat, when the bags work as
-- Blizzard's.
--
-- Which items count, and which weapons they go on, starts from the table below, since the game only
-- says what an item fits once its cursor is up. On top of it (ns.GameData, for the account), an
-- item with a use spell that you put on a weapon yourself is learned for that kind of weapon: once
-- its cast ends and the weapon has a new temporary buff. That covers items the table lacks and
-- fist weapons, which it leaves to the cursor. Main hand first; the off hand when only it can
-- take the item, when the main hand already has a buff and the off hand doesn't, or when the off
-- hand's buff runs out sooner. When no equipped weapon can take the item (a weightstone with only
-- blades), the right-click says so in red at the top of the screen, like Blizzard's own errors,
-- instead of bringing up a cursor nothing will take.
--
-- On an action bar the same `target-slot` attribute goes on Blizzard's action button itself: its
-- secure click reads it after using the item, while the item's cursor is up. It's set out of combat
-- when the bars or the weapons change (so a key binding finds it), and again just before each
-- click (to pick by the buffs' time left then). In combat the buttons work as Blizzard's, like the
-- bags. Unverified on Forever: that an attribute an addon sets on Blizzard's button doesn't stop
-- its click; if it does, this part goes and the bags stay.
local _, ns = ...

local C_Item, C_Container, C_PaperDollInfo = C_Item, C_Container, C_PaperDollInfo
local GetInventoryItemID, GetWeaponEnchantInfo, GetTime = GetInventoryItemID, GetWeaponEnchantInfo, GetTime
local GetActionInfo, InCombatLockdown = GetActionInfo, InCombatLockdown
local pairs, select, setmetatable, tostring, type = pairs, select, setmetatable, tostring, type

local L = ns.L

local module = ns.NewModule("AutoWeaponBuff", L.AUTOWEAPONBUFF_DESC, {
    enabled = false,
    warnNoFit = true,
    printSteps = false,
})
module.title = L.AUTOWEAPONBUFF_TITLE
module.category = "automation"
module.presets = { developer = { enabled = true } }
module.added = "0.8.0"
-- The game's rule, not ours, so say it where the player turns it on; a notice with no button.
module.notice = { text = L.AUTOWEAPONBUFF_NOTICE, description = L.AUTOWEAPONBUFF_NOTICE_DESC }

module.options = {
    {
        key = "warnNoFit",
        name = L.AUTOWEAPONBUFF_WARN,
        description = L.AUTOWEAPONBUFF_WARN_DESC,
        added = "0.8.2",
    },
    {
        key = "printSteps",
        name = L.AUTOWEAPONBUFF_PRINT,
        description = L.AUTOWEAPONBUFF_PRINT_DESC,
        debug = true,
        section = L.DEBUG_SECTION_LOGGING,
    },
}

local MAINHAND, OFFHAND = 16, 17
local WEAPON, FISHING_POLE = ns.Equipment.WEAPON, ns.Equipment.FISHING_POLE
local FIST = 13 -- Enum.ItemWeaponSubclass.Unarmed

-- Weapon subclasses a sharpening stone ("sharp") or weightstone ("blunt") goes on. Fist weapons
-- are in neither: which stone they take is Unverified, so they're left to the cursor.
local SHARP = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }

-- The seed: item ID to the weapons it goes on: "sharp", "blunt", "melee" (oils and poisons, any
-- weapon but a fishing pole), or "pole" (fishing lures). What was learned in play is a table
-- instead: `kind` (the seed's, or nil for an item it lacks) and weapon subclass -> true for each
-- kind of weapon the item went on, which wins over the kind.
local KINDS = {}
local function add(kind, ...)
    for i = 1, select("#", ...) do
        KINDS[select(i, ...)] = kind
    end
end
-- Sharpening stones: Rough, Coarse, Heavy, Solid, Dense, Elemental, Consecrated.
add("sharp", 2862, 2863, 2871, 7964, 12404, 18262, 23122)
-- Weightstones: Rough, Coarse, Heavy, Solid, Dense.
add("blunt", 3239, 3240, 3241, 7965, 12643)
-- Wizard and mana oils, Blessed Wizard Oil, Shadow Oil, Frost Oil.
add("melee", 20744, 20746, 20750, 20749, 20745, 20747, 20748, 23123, 3824, 3829)
-- Poisons: Instant I-VI, Deadly I-V, Crippling I-II, Mind-numbing I-III, Wound I-IV.
add("melee", 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776,
    5237, 6951, 9186, 10918, 10920, 10921, 10922)
-- Lures: Shiny Bauble, Nightcrawlers, Bright Baubles, Aquadynamic Fish Attractor, Flesh Eating
-- Worm, Aquadynamic Fish Lens.
add("pole", 6529, 6530, 6532, 6533, 7307, 6811)

local BUFFS = ns.GameData.New("weaponBuffs", KINDS, { kind = "item", label = "Auto Weapon Buff items" })

function module:IsAvailable()
    return ns.BagClicks.IsAvailable() and C_Item and C_Item.GetItemInfoInstant and GetInventoryItemID
        and true or false
end

local weaponSubclass = ns.Equipment.WeaponSubclass

-- Whether an item with this entry (BUFFS's) can go on the weapon in this slot: true, false, or nil
-- when we don't know (a stone on a fist weapon, or a learned item on a kind of weapon it never
-- went on).
local function fits(entry, slot)
    local subclassID = weaponSubclass(slot)
    if not subclassID then
        return false
    elseif not entry then
        return nil
    end
    local kind = entry
    if type(entry) == "table" then
        if entry[subclassID] then
            return slot == MAINHAND or subclassID ~= FISHING_POLE
        end
        kind = entry.kind
        if not kind then
            return nil
        end
    end
    if kind == "pole" then
        return slot == MAINHAND and subclassID == FISHING_POLE
    elseif subclassID == FISHING_POLE then
        return false
    elseif subclassID == FIST and (kind == "sharp" or kind == "blunt") then
        return nil
    elseif kind == "sharp" then
        return SHARP[subclassID] or false
    elseif kind == "blunt" then
        return BLUNT[subclassID] or false
    end
    return true
end

-- Milliseconds left on the slot's temporary buff, or nil when it has none.
local function buffLeft(slot)
    local left
    if C_Item.GetWeaponEnchantInfo then
        -- Forever's buff frame reads it this way: a list per weapon slot, 0 for the main hand.
        local enchants = C_Item.GetWeaponEnchantInfo(slot - MAINHAND)
        for _, enchant in pairs(enchants or {}) do
            -- A secret flag counts as a buff whose time we can't read.
            if ns.IsTrueOrSecret(enchant.hasEnchant) then
                local timeLeft = enchant.timeLeft or 0
                if not ns.IsReadable(timeLeft) then
                    return 0 -- there is a buff, but not how long it has
                end
                if not left or timeLeft < left then
                    left = timeLeft
                end
            end
        end
    elseif C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
        left = info and (info.remainingTimeMs or 0)
    elseif GetWeaponEnchantInfo then
        local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
        if slot == MAINHAND then
            left = hasMain and (mainLeft or 0) or nil
        else
            left = hasOff and (offLeft or 0) or nil
        end
    end
    if left ~= nil and not ns.IsReadable(left) then
        return 0 -- there is a buff, but not how long it has
    end
    return left
end

-- The slot to put an item with this entry on, or nil when neither weapon can take it.
local function pickSlot(entry)
    local main, off = fits(entry, MAINHAND), fits(entry, OFFHAND)
    if main and off then
        local mainLeft, offLeft = buffLeft(MAINHAND), buffLeft(OFFHAND)
        if mainLeft and (not offLeft or offLeft < mainLeft) then
            return OFFHAND
        end
        return MAINHAND
    end
    return main and MAINHAND or off and OFFHAND or nil
end

-- Whether we know neither weapon can take an item with this entry.
local function noneFits(entry)
    return fits(entry, MAINHAND) == false and fits(entry, OFFHAND) == false
end

-- The entry's kind for Print Weapon Checks: the seed's, or "learned".
local function describe(entry)
    if type(entry) == "table" then
        return entry.kind or "learned"
    end
    return entry
end

local function warnNoFit(bag, slot)
    local itemID = C_Container.GetContainerItemID(bag, slot)
    local name = itemID and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    ns.Frames.ErrorMessage(name and L.AUTOWEAPONBUFF_WARN_TEXT:format(name) or L.AUTOWEAPONBUFF_WARN_TEXT_ANY)
end

-- Overlays ------------------------------------------------------------------------------------

-- An overlay for each item a worn weapon takes, and with Warn on, for one no weapon takes (to say
-- so).
local function match(itemID)
    local entry = BUFFS:Get(itemID)
    if entry and (fits(entry, MAINHAND) or fits(entry, OFFHAND) or module.db.warnNoFit and noneFits(entry)) then
        return entry
    end
end

local function click(overlay, entry, bag, slot, down)
    local target = pickSlot(entry)
    local warn = not target and module.db.warnNoFit and noneFits(entry)
    if target then
        overlay:SetAttribute("type2", "item")
        overlay:SetAttribute("item", bag .. " " .. slot)
    end
    overlay:SetAttribute("target-slot", target)
    if warn and not down then
        warnNoFit(bag, slot)
    end
    if not down and module.db.printSteps then
        ns.Print(L.AUTOWEAPONBUFF_PRINT_LINE:format(tostring(C_Container.GetContainerItemLink(bag, slot)),
            describe(entry), tostring(target)))
    end
    -- A warning takes the click: nothing goes to the bag button, so no cursor comes up.
    return target ~= nil or warn
end

local overlays = ns.BagClicks.New(module, match, click)

-- Learning -------------------------------------------------------------------------------------

-- The ID of the slot's temporary buff, or nil when it has none or we can't read it.
local function buffID(slot)
    local id
    if C_Item.GetWeaponEnchantInfo then
        for _, enchant in pairs(C_Item.GetWeaponEnchantInfo(slot - MAINHAND) or {}) do
            if ns.IsTrue(enchant.hasEnchant) then
                id = enchant.enchantID
                break
            end
        end
    elseif GetWeaponEnchantInfo then
        id = select(slot == MAINHAND and 4 or 8, GetWeaponEnchantInfo())
    end
    return ns.IsReadable(id) and id or nil
end

local function snapshot(slot)
    return { left = buffLeft(slot), id = buffID(slot) }
end

-- Whether the slot got a temporary buff between the two snapshots: a new one, another one, or the
-- same one with more time (a buff's time only runs down).
local function refreshed(before, now)
    if now.left == nil then
        return false
    elseif before.left == nil then
        return true
    elseif now.id and before.id and now.id ~= before.id then
        return true
    end
    return now.left > before.left
end

-- The last bag item with a use spell the player used, and both weapons' buffs at that moment.
local pending

-- Using an item with a use spell: remember it, in case it goes on a weapon.
local function remember(itemID)
    if not itemID or not C_Item.GetItemSpell then
        return
    end
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID or not ns.IsReadable(spellID) then
        return
    end
    pending = { itemID = itemID, spellID = spellID, time = GetTime(),
        [MAINHAND] = snapshot(MAINHAND), [OFFHAND] = snapshot(OFFHAND) }
end

-- A bag item (a right-click in the bags, or our overlay).
local function onUse(bag, slot)
    remember(C_Container.GetContainerItemID(bag, slot))
end

-- An action bar slot (a click or key on Blizzard's button).
local function onUseAction(action)
    if not (action and ns.IsReadable(action) and GetActionInfo) then
        return
    end
    local kind, itemID = GetActionInfo(action)
    if ns.IsReadable(kind) and kind == "item" and ns.IsReadable(itemID) then
        remember(itemID)
    end
end

local function learn(used)
    for slot = MAINHAND, OFFHAND do
        local subclassID = weaponSubclass(slot)
        if subclassID and refreshed(used[slot], snapshot(slot)) then
            local entry = BUFFS:Get(used.itemID)
            if fits(entry, slot) then
                return -- already known
            end
            -- A copy of what's known: its kind (none for an item learned in play) and the weapon
            -- types learned before.
            local learned = { kind = type(entry) ~= "table" and entry or nil }
            if type(entry) == "table" then
                for key, value in pairs(entry) do
                    learned[key] = value
                end
            end
            learned[subclassID] = true
            BUFFS:Learn(used.itemID, learned)
            overlays:Refresh()
            if module.db.printSteps then
                local weapon = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(WEAPON, subclassID)
                ns.Print(L.AUTOWEAPONBUFF_LEARNED_LINE:format(
                    tostring(C_Item.GetItemNameByID and C_Item.GetItemNameByID(used.itemID) or used.itemID),
                    tostring(weapon or subclassID)))
            end
            return
        end
    end
end

-- The used item's cast went off: once the buff is on, see which weapon it went on.
local learnTimer = ns.Frames.Timer(module)
local function onCast(_, unit, _, spellID)
    if not (pending and ns.IsReadable(unit) and ns.IsReadable(spellID)) or unit ~= "player"
        or spellID ~= pending.spellID then
        return
    end
    local used = pending
    pending = nil
    if GetTime() - used.time > 60 then
        return
    end
    learnTimer:Start(1, function()
        learn(used)
    end)
end

-- Action bars ---------------------------------------------------------------------------------

local targeted = setmetatable({}, { __mode = "k" }) -- action button -> the slot we set on it

-- Writes to Blizzard's button as rarely as possible: only out of combat, only a change, and only on
-- a button holding a weapon buff we know (others get nil, which they already have). In combat it
-- writes nothing; PLAYER_REGEN_ENABLED updates the bars again.
local function setTarget(button, slot)
    if targeted[button] ~= slot and not InCombatLockdown() then
        button:SetAttribute("target-slot", slot)
        targeted[button] = slot
    end
end

-- The weapon slot the item on this button goes on (nil when it holds none we know, or no worn
-- weapon takes it), its entry, and its item ID.
local function actionTarget(button)
    local kind, itemID = ns.ActionButtons.Content(button)
    local entry = kind == "item" and BUFFS:Get(itemID)
    if not entry then
        return nil
    end
    return pickSlot(entry), entry, itemID
end

local function updateButton(button)
    setTarget(button, module.enabled and actionTarget(button) or nil)
end

local updateBars = ns.Frames.Coalesce(function()
    ns.ActionButtons.Each(updateButton)
end, nil, module)

-- Takes our attribute off every button. Only out of combat: at PLAYER_REGEN_DISABLED lockdown may
-- already have started, and then the slot set before stays until combat ends (setTarget skips).
local function clearBars()
    for button in pairs(targeted) do
        setTarget(button, nil)
    end
end

-- Just before Blizzard's secure click: pick the slot again, with the buffs as they are now.
local function onActionPreClick(button, _, down)
    if InCombatLockdown() then
        return
    end
    updateButton(button)
    if not down and module.db.printSteps then
        local target, entry, itemID = actionTarget(button)
        if entry then
            ns.Print(L.AUTOWEAPONBUFF_PRINT_LINE:format(
                tostring(C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or itemID),
                describe(entry), tostring(target)))
        end
    end
end

local function onInventoryChanged(_, unit)
    if unit == "player" then
        updateBars()
    end
end

local BAR_EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }

function module:OnEnable()
    overlays:Enable()
    self:On("PLAYER_EQUIPMENT_CHANGED", overlays.refresh)
    self:Hook(C_Container, "UseContainerItem", onUse)
    self:On("UNIT_SPELLCAST_SUCCEEDED", onCast)
    if GetActionInfo then
        ns.ActionButtons.Each(function(button)
            self:HookScript(button, "PreClick", onActionPreClick)
        end)
        for _, event in pairs(BAR_EVENTS) do
            if ns.HasEvent(event) then
                self:On(event, updateBars)
            end
        end
        self:On("UNIT_INVENTORY_CHANGED", onInventoryChanged)
        -- Fires just before combat lockdown starts, the last moment the attribute can change.
        self:On("PLAYER_REGEN_DISABLED", clearBars)
        self:Hook("UseAction", onUseAction)
        updateBars()
    end
end

function module:OnOptionChanged(key)
    if key == "warnNoFit" then
        overlays:Refresh()
    end
end

function module:OnDisable()
    overlays:Disable()
    ns.AfterCombat(function()
        if not module.enabled then -- turned back on in combat: its own update set the bars
            clearBars()
        end
    end)
end
