-- Item Tooltips' two changes to an item's stat lines, each with its own checkbox. Stat Colors
-- draws each stat line ("+6 Spirit", "Equip: Increases your hit by 1%.") in that stat's color from
-- ns.Colors.STATS, so the stats an item has read at a glance; an Equip: line keeps "Equip:" in
-- Blizzard's green. Short Stat Text writes an Equip: bonus that is one plain stat the way the game
-- writes a plain stat, "+29 Spell Power". Both redraw the same line, so one function does both.
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

local short = ns.modules.ItemTooltips:NewPart({
    key = "shortStats", name = L.ITEMTOOLTIPS_SHORTSTATS, description = L.SHORTSTATS_DESC,
    section = L.SHORTSTATS_TITLE, added = "1.9.0",
}, {
    shortStats = false,
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

-- Draws a stat line again, in its stat's color, as a short stat, or both, and returns true, so
-- Blizzard's is skipped. A line neither part changes is left to Blizzard.
local function drawLine(tooltip, data, lineData)
    local colors, shorten = module.enabled, short.enabled
    if not (colors or shorten) or lineData.type ~= PLAIN then
        return
    end
    local text = lineData.leftText
    -- A line with right text is the damage line, never a stat.
    if not ns.IsText(text, true) or ns.IsText(lineData.rightText, true) then
        return
    end
    local plain = Text.Plain(text)
    local raw = isEquip(plain) and statsOf(data) or nil
    local key, effect = ItemStats.LineStat(plain, raw)
    local color = colors and key and Colors.STATS[key]
    local brief = shorten and key and effect and ItemStats.ShortEffect(key, effect, raw)
    if not (color or brief) then
        return
    end
    local wrap = lineData.wrapText
    wrap = ns.IsReadable(wrap) and wrap == true
    local own = lineData.leftColor
    own = ns.IsReadable(own) and type(own) == "table" and own.r and own or nil
    if brief then
        -- A short stat reads as the plain stats do: all in the stat's color, or with colors off
        -- in the Equip: line's own green, which still says it's a bonus.
        local r, g, b = 1, 1, 1
        if color then
            r, g, b = color[1], color[2], color[3]
        elseif own then
            r, g, b = own.r, own.g, own.b
        end
        tooltip:AddLine(brief, r, g, b, wrap)
        return true
    end
    local line = plain
    if effect then
        -- "Equip:" stays in the line's own color; the effect takes the stat's.
        local lead = plain:sub(1, #plain - #effect)
        if own then
            lead = Colors.Text(own, lead)
        end
        line = lead .. Colors.Code(color[1], color[2], color[3]) .. effect .. "|r"
    end
    tooltip:AddLine(line, color[1], color[2], color[3], wrap)
    return true
end

-- The hook can't be removed; drawLine checks which parts are on and lets Blizzard's line show
-- when neither is. Asked for by whichever part turns on first.
function module:OnEnable()
    ItemTooltip.ReplaceLine(drawLine, module)
end

function short:OnEnable()
    ItemTooltip.ReplaceLine(drawLine, module)
end
