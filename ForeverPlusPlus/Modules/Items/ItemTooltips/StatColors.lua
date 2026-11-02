-- Item Tooltips' stat colors: each stat line in an item's tooltip ("+6 Spirit", "Equip: Increases
-- your hit by 1%.") drawn in that stat's color from ns.Colors.STATS, so the stats an item has
-- read at a glance. An Equip: line keeps "Equip:" in Blizzard's green.
local _, ns = ...

local type, setmetatable, pcall = type, setmetatable, pcall
local Enum, C_Item, ITEM_SPELL_TRIGGER_ONEQUIP = Enum, C_Item, ITEM_SPELL_TRIGGER_ONEQUIP

local L = ns.L
local ItemTooltip, ItemStats, Colors, Text = ns.ItemTooltip, ns.ItemStats, ns.Colors, ns.Text

local module = ns.modules.ItemTooltips:NewPart({
    key = "statColors", name = L.ITEMTOOLTIPS_STATCOLORS, description = L.STATCOLORS_DESC,
    section = L.STATCOLORS_TITLE, added = "1.0.0-beta.1",
}, {
    statColors = true,
})

-- Probe: Mainline's line types; plain stat and Equip: lines are 0 (docs/forever-api.md).
local PLAIN = Enum.TooltipDataLineType and Enum.TooltipDataLineType.None or 0

local NONE = {} -- an item whose stats can't be read
local itemStats = setmetatable({}, { __mode = "k" }) -- tooltip data -> the item's raw stat table

-- The item's stat table, read once per tooltip, for Equip: lines whose wording is a spell's.
local function statsOf(data)
    local raw = itemStats[data]
    if raw then
        return raw ~= NONE and raw or nil
    end
    local link = ns.IsText(data.hyperlink, true) and data.hyperlink
    if not link and ns.IsText(data.guid, true) and C_Item.GetItemLinkByGUID then
        local ok, byGUID = pcall(C_Item.GetItemLinkByGUID, data.guid)
        link = ok and ns.IsText(byGUID, true) and byGUID
    end
    local id = not link and ItemTooltip.ItemID(data)
    link = link or (id and "item:" .. id)
    raw = link and C_Item.GetItemStats and C_Item.GetItemStats(link)
    raw = ns.IsReadable(raw) and type(raw) == "table" and raw or nil
    itemStats[data] = raw or NONE
    return raw
end

-- Whether a line is an Equip: line ("Equip: Increases ...").
local function isEquip(plain)
    local equip = ITEM_SPELL_TRIGGER_ONEQUIP
    return type(equip) == "string" and equip ~= "" and plain:sub(1, #equip) == equip
end

-- Draws a stat line again in its stat's color and returns true, so Blizzard's is skipped.
local function colorLine(tooltip, data, lineData)
    if not module.enabled or lineData.type ~= PLAIN then
        return
    end
    local text = lineData.leftText
    -- A line with right text is the damage line, never a stat.
    if not ns.IsText(text, true) or ns.IsText(lineData.rightText, true) then
        return
    end
    local plain = Text.Plain(text)
    local key, effect = ItemStats.LineStat(plain, isEquip(plain) and statsOf(data) or nil)
    local color = key and Colors.STATS[key]
    if not color then
        return
    end
    local line = plain
    if effect then
        -- "Equip:" stays in the line's own color; the effect takes the stat's.
        local lead = plain:sub(1, #plain - #effect)
        local own = lineData.leftColor
        if ns.IsReadable(own) and type(own) == "table" and own.r then
            lead = Colors.Text(own, lead)
        end
        line = lead .. Colors.Code(color[1], color[2], color[3]) .. effect .. "|r"
    end
    local wrap = lineData.wrapText
    tooltip:AddLine(line, color[1], color[2], color[3], ns.IsReadable(wrap) and wrap == true)
    return true
end

function module:OnEnable()
    -- The hook can't be removed; colorLine checks the part is on and lets Blizzard's line show
    -- when it's off.
    ItemTooltip.ReplaceLine(colorLine, module)
end
