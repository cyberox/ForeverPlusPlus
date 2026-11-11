-- Character Window's durability bars: a thin bar beside each equipped item on the character frame
-- that shows how worn it is, green when whole through yellow to red when broken. Left column items
-- get it on their right side and right column items on their left, so it faces the character
-- model; the weapons along the bottom get a flat bar under them, since the gap between them is too
-- narrow. Items without durability get no bar. CharacterWindow.lua turns them on and off.
local _, ns = ...

local _G, pairs, CreateFrame = _G, pairs, CreateFrame
local pcall, GetInventorySlotInfo = pcall, GetInventorySlotInfo

local module = ns.modules.CharacterWindow
local internal = module.internal

-- Show a bar only below this much durability (a bar at exactly 1 is whole), by the `durability`
-- option's choices.
local SHOW_BELOW = { always = 2, worn = 1, half = 0.5, quarter = 0.25 }

local THICKNESS = 3 -- bar width, in pixels
local GAP = 2 -- space between the bar and the item button
local INSET = 2 -- how far the bar stops short of the button's ends

-- The slot names, by which edge of the button faces inward.
local SIDES = {
    RIGHT = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" },
    LEFT = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" },
    BOTTOM = { "MainHand", "SecondaryHand", "Ranged" }, -- Ranged only if Forever has the slot
}

local container -- our frame on the paper doll; bars are children, so they hide with it
---@type table<number, table>
local bars = {} -- inventory slot id -> StatusBar

local function makeBar(button, side)
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    if side == "BOTTOM" then
        bar:SetHeight(THICKNESS)
        bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", INSET, -GAP)
        bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", -INSET, -GAP)
    else
        bar:SetOrientation("VERTICAL")
        bar:SetWidth(THICKNESS)
        local point, other, x = "TOPLEFT", "TOPRIGHT", GAP
        if side == "LEFT" then
            point, other, x = "TOPRIGHT", "TOPLEFT", -GAP
        end
        bar:SetPoint(point, button, other, x, -INSET)
        bar:SetPoint("BOTTOM", button, "BOTTOM", 0, INSET)
    end
    bar:Hide()
    return bar
end

-- IsVisible, not IsShown: the container stays shown while the window is closed, and its OnShow
-- reads them when the window opens.
local function update()
    if not (container and container:IsVisible()) then
        return
    end
    local below = SHOW_BELOW[module.db.durability] or SHOW_BELOW.always
    for slot, bar in pairs(bars) do
        local fraction = ns.Durability.Fraction(slot)
        if fraction and fraction < below then
            bar:SetValue(fraction)
            -- Green at full, yellow at half, red at zero.
            if fraction > 0.5 then
                bar:SetStatusBarColor((1 - fraction) * 2, 1, 0)
            else
                bar:SetStatusBarColor(1, fraction * 2, 0)
            end
            bar:Show()
        else
            bar:Hide()
        end
    end
end

local function build()
    container = CreateFrame("Frame", nil, _G.PaperDollItemsFrame)
    container:SetAllPoints()
    -- Read again each time the window opens: at a fresh login the bars are built before the worn
    -- items are there, and no durability event may follow.
    container:SetScript("OnShow", update)
    for side, names in pairs(SIDES) do
        for i = 1, #names do
            local name = names[i] .. "Slot"
            local button = _G["Character" .. name]
            local ok, slot = pcall(GetInventorySlotInfo, name)
            if button and ok and slot then
                bars[slot] = makeBar(button, side)
            end
        end
    end
end

---Shows or hides the bars to match the module and its `durability` option. Once the character
---frame has loaded.
function internal.updateDurability()
    local on = module.enabled and module.db.durability ~= "off"
    if on and not container and _G.PaperDollItemsFrame then
        build()
    end
    if container then
        container:SetShown(on and true or false)
        update()
    end
end

-- The events update() wants while the module is on; it does nothing while the bars are hidden.
function internal.enableDurability()
    module:On("UPDATE_INVENTORY_DURABILITY", update)
    module:On("PLAYER_EQUIPMENT_CHANGED", update)
end
