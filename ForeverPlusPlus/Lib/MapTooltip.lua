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

---Adds lines to a tooltip already showing, such as Blizzard's own for a minimap dot: each a
---string (gold), or the table one of the helpers above makes. Lines wrap, but for a Pair. Call
---`tooltip:Show()` after, so it fits them.
---@param tooltip table
---@param lines (string|table)[]?
function MapTooltip.AddLines(tooltip, lines)
    local white, gold = HIGHLIGHT_FONT_COLOR, NORMAL_FONT_COLOR
    for _, line in ipairs(lines or {}) do
        local text, color = line, gold
        if type(line) == "table" then
            text, color = line[1], line[2]
        end
        if type(line) == "table" and line.right then
            tooltip:AddDoubleLine(text, line.right, color.r, color.g, color.b, white.r, white.g, white.b)
        else
            tooltip:AddLine(text, color.r, color.g, color.b, true)
        end
    end
end

---Shows the tooltip for a map icon: `title` (white, or a `{ text, color }` table, as a gathering
---node's gold name like the minimap's own tooltip), then the lines as AddLines takes them. With
---`kind`, the title has it in gold at the right edge. With `above`, the tooltip sits above that
---frame's top left, as the game's own minimap tooltip does over the minimap, rather than beside
---`owner`.
---@param owner table the frame the tooltip sits beside
---@param title string|table
---@param lines (string|table)[]?
---@param kind? string
---@param above? table
function MapTooltip.Show(owner, title, lines, kind, above)
    if above then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMRIGHT", above, "TOPLEFT")
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local white, gold = HIGHLIGHT_FONT_COLOR, NORMAL_FONT_COLOR
    local color = white
    if type(title) == "table" then
        title, color = title[1], title[2]
    end
    if kind then
        GameTooltip:AddDoubleLine(title, kind, color.r, color.g, color.b, gold.r, gold.g, gold.b)
    else
        GameTooltip:SetText(title, color.r, color.g, color.b)
    end
    MapTooltip.AddLines(GameTooltip, lines)
    GameTooltip:Show()
end
