-- Macro Icon Search: a search box in the macro window's icon picker. Type part of a spell's or
-- item's name and the picker shows the icons of your spells and of the items you carry or wear
-- that match, in place of the whole list.
-- The game gives addons the macro icons as file numbers with no names (GetMacroIcons), so an
-- icon can only be found through something that has both a name and an icon: the spellbook, bags,
-- and worn gear. Searching every icon by its file name would need a list of them shipped with the
-- addon and redone each patch.
-- Blizzard's picker (MacroPopupFrame, from IconSelectorPopupFrameTemplate; Gethe forever branch,
-- Blizzard_MacroUI/Blizzard_MacroIconSelector.lua, read 2026-11-10) shows whatever its
-- IconSelector's two functions return and saves the texture of the icon clicked, so a search hands
-- it our own short list and, when cleared, Blizzard's again. Nothing of Blizzard's is replaced.
local _, ns = ...

local pairs, ipairs, type, sort, lower, find = pairs, ipairs, type, table.sort, string.lower, string.find
local C_Container, C_Item, C_Spell = C_Container, C_Item, C_Spell
local GetInventoryItemID, GetInventoryItemTexture = GetInventoryItemID, GetInventoryItemTexture

local L = ns.L

local module = ns.NewModule("MacroIconSearch", L.MACROICONSEARCH_DESC, {
    enabled = true,
})
module.title = L.MACROICONSEARCH_TITLE
module.category = "character"
module.added = "1.5.0"

local MACRO_UI = "Blizzard_MacroUI"
local BAGS, WORN = 4, 19 -- the backpack and four bags; the worn slots

local box -- our search box, made the first time the picker shows
local named -- { { name (lowercase), texture } } for this showing of the picker
local searching = false -- the picker shows our list

-- Every spell known and item carried or worn, with its icon. Built when the picker shows, since
-- both change between showings.
local function gather()
    local list = {}
    local function add(name, texture)
        if ns.IsText(name) and name ~= "" and texture then
            list[#list + 1] = { name = lower(name), texture = texture }
        end
    end
    for name, ranks in pairs(ns.Spellbook.Ranks()) do
        local top = ranks[#ranks]
        add(name, top and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(top.id))
    end
    if C_Container and C_Container.GetContainerNumSlots and C_Item and C_Item.GetItemNameByID then
        for bag = 0, BAGS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    add(C_Item.GetItemNameByID(info.itemID), info.iconFileID)
                end
            end
        end
        for slot = 1, WORN do
            local id = GetInventoryItemID("player", slot)
            if id then
                add(C_Item.GetItemNameByID(id), GetInventoryItemTexture("player", slot))
            end
        end
    end
    sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

-- The icons whose spell or item name has `query` in it, each once, in name order.
local function matches(query)
    named = named or gather()
    local icons, seen = {}, {}
    for _, entry in ipairs(named) do
        if not seen[entry.texture] and find(entry.name, query, 1, true) then
            seen[entry.texture] = true
            icons[#icons + 1] = entry.texture
        end
    end
    return icons
end

local function selector()
    local popup = _G.MacroPopupFrame
    local icons = popup and popup.IconSelector
    if icons and type(icons.SetSelectionsDataProvider) == "function" then
        return icons, popup
    end
end

-- Blizzard's own list again, as MacroPopupFrameMixin:Update gives it.
local function restore()
    if not searching then
        return
    end
    searching = false
    local icons, popup = selector()
    if icons and popup.GetIconByIndex and popup.GetNumIcons then
        icons:SetSelectionsDataProvider(function(index)
            return popup:GetIconByIndex(index)
        end, function()
            return popup:GetNumIcons()
        end)
    end
end

local function search(text)
    if not module.enabled then
        return
    end
    local query = lower(text)
    if query == "" then
        restore()
        return
    end
    local icons = selector()
    if not icons then
        return
    end
    local found = matches(query)
    searching = true
    icons:SetSelectionsDataProvider(function(index)
        return found[index]
    end, function()
        return #found
    end)
end

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.MACROICONSEARCH_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.MACROICONSEARCH_TIP, nil, nil, nil, true)
    GameTooltip:Show()
end

-- The row above the icons: Blizzard's "Choose an Icon:" label at the left and its All Icons
-- dropdown at the right, with room between them (IconSelectorPopupFrameTemplate's BorderBox
-- children; Gethe forever branch 1.60.1.70862, Blizzard_SharedXML/Mainline/
-- SharedUIPanelTemplates.xml, read 2026-11-11).
local function topRow(popup)
    local border = popup.BorderBox
    local label = border and border.IconSelectionText
    local dropdown = border and border.IconTypeDropdown
    if label and dropdown and label.GetRight and dropdown.GetLeft then
        return label, dropdown
    end
end

local GAP = 12 -- from the box to the label and the dropdown; its border art reaches 5 px past it
local MIN_WIDTH, BOTTOM_WIDTH = 40, 150

-- In the top row the box fills the gap between the label and the dropdown, so a longer
-- translated label leaves it narrower instead of under it. One anchor can't take its left edge
-- from the label and its height from the dropdown, so it hangs from the dropdown and its width is
-- the gap, measured each time the picker shows.
local function fit(popup)
    local label, dropdown = topRow(popup)
    if not (box and label) then
        return
    end
    local left, right = label:GetRight(), dropdown:GetLeft()
    if left and right then
        local width = right - left - 2 * GAP
        box:SetWidth(width > MIN_WIDTH and width or MIN_WIDTH)
    end
    -- Blizzard hides the label and dropdown while a spell or item is held over the picker, to
    -- show its drop area there.
    box:SetShown(dropdown:IsShown())
end

-- The box sits in the top row, right of "Choose an Icon:" and left of the dropdown, centered on
-- the dropdown. On a client without those it goes left of the Okay button, in the bottom row.
local function makeBox(popup)
    local border = popup.BorderBox
    local label, dropdown = topRow(popup)
    local anchor = dropdown or (border and border.OkayButton)
    if not anchor then
        return
    end
    local made = ns.SettingsKit.AddSearchBox(border, anchor, L.MACROICONSEARCH_BOX, search)
    if not made then
        return
    end
    if label then
        made:ClearAllPoints()
        made:SetPoint("RIGHT", dropdown, "LEFT", -GAP, 0)
        made:SetHeight(20)
        module:HookScript(dropdown, "OnShow", function()
            fit(popup)
        end)
        module:HookScript(dropdown, "OnHide", function()
            made:Hide()
        end)
    else
        made:SetSize(BOTTOM_WIDTH, 20)
    end
    made:HookScript("OnEnter", tooltip)
    made:HookScript("OnLeave", GameTooltip_Hide)
    return made
end

-- The picker shows Blizzard's list each time it opens (its OnShow runs Update), so ours starts
-- empty with it.
local function onShow(popup)
    named, searching = nil, false
    box = box or makeBox(popup)
    if box then
        box:SetText("")
        box:Show()
        fit(popup)
    end
end

local function onHide()
    named, searching = nil, false
end

local function setup()
    local popup = _G.MacroPopupFrame
    if not (popup and selector()) then
        return
    end
    module:HookScript(popup, "OnShow", onShow)
    module:HookScript(popup, "OnHide", onHide)
    if popup:IsShown() then
        onShow(popup)
    end
end

function module:OnEnable()
    ns.AddOns.WhenLoaded(MACRO_UI, setup)
end

function module:OnDisable()
    ns.AddOns.Cancel(MACRO_UI, setup)
    restore()
    named = nil
    if box then
        box:SetText("")
        box:Hide()
    end
end
