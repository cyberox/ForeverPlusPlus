-- How every tooltip over the world map looks, so a pin and a panel say things the same way, like
-- Blizzard's own map tooltips: a white title, gold lines for what kind of place it is, white for
-- the details (where, what level), gray for a note, and faction colors for a side.
local _, ns = ...

local ipairs, type, gsub = ipairs, type, string.gsub
local GameTooltip = GameTooltip
local NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR = NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR

local MapTooltip = {}
ns.MapTooltip = MapTooltip

local NBSP = "\194\160" -- a no-break space, in UTF-8

---Text that won't wrap in the middle, such as a name with its level range: every space in it is
---a no-break space.
---@param text string
---@return string
function MapTooltip.NoBreak(text)
    return (gsub(text, " ", NBSP))
end

---A line of detail (where a place is, what level): white instead of the gold lines are.
---@param text string
---@return table line
function MapTooltip.Detail(text)
    return { text, HIGHLIGHT_FONT_COLOR }
end

---A line of note (something not learned yet): gray.
---@param text string
---@return table line
function MapTooltip.Note(text)
    local gray = ns.Colors.GRAY
    return { text, { r = gray[1], g = gray[2], b = gray[3] } }
end

---A side's name ("Horde") on a line in its color, or nil for neutral.
---@param side string? "H", "A", or anything else
---@return table? line
function MapTooltip.Side(side)
    local name = ns.WorldMap.SideName(side or "")
    if name then
        return { name, ns.Colors.Faction(side) }
    end
end

---A white label on the left and its value at the right edge, as Blizzard's Sell Price line:
---"Gathered:" and "3 times".
---@param label string
---@param value string
---@return table line
function MapTooltip.Pair(label, value)
    return { label, HIGHLIGHT_FONT_COLOR, right = value }
end

---Shows the tooltip for a map icon. A line is a string, gold, or the table one of the helpers
---above makes; text with color codes keeps them. Lines wrap, but for a Pair. With `kind`, the
---title has it in gold at the right edge (a node's "Ore").
---@param owner table the frame the tooltip sits beside
---@param title string
---@param lines (string|table)[]?
---@param kind? string
function MapTooltip.Show(owner, title, lines, kind)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local white, gold = HIGHLIGHT_FONT_COLOR, NORMAL_FONT_COLOR
    if kind then
        GameTooltip:AddDoubleLine(title, kind, white.r, white.g, white.b, gold.r, gold.g, gold.b)
    else
        GameTooltip:SetText(title, white:GetRGB())
    end
    for _, line in ipairs(lines or {}) do
        local text, color = line, gold
        if type(line) == "table" then
            text, color = line[1], line[2]
        end
        if type(line) == "table" and line.right then
            GameTooltip:AddDoubleLine(text, line.right, color.r, color.g, color.b, white.r, white.g, white.b)
        else
            GameTooltip:AddLine(text, color.r, color.g, color.b, true)
        end
    end
    GameTooltip:Show()
end
