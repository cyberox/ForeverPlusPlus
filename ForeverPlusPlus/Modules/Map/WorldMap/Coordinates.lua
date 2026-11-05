-- Coordinates, a part of World Map: the player's and the cursor's coordinates on the world map.
-- Forever's map already has them (Blizzard's coordinates panel, shown by its own checkboxes under
-- Settings > Gameplay > Interface > Coordinates), so this leaves which ones show, and tenths, to
-- those, and moves Blizzard's text into the map's title bar: the player's on the left, the
-- cursor's on the right, either side of the title. Ideas from Leatrix Maps' coordinates; none of
-- its code.
local _, ns = ...

local max, min = math.max, math.min
local CreateFrame = CreateFrame

local L = ns.L
local CVars = ns.CVars

local module = ns.modules.WorldMap:NewPart({
    key = "coordinates", name = L.COORDS_TITLE, description = L.COORDS_DESC,
    section = L.COORDS_TITLE,
})

-- Blizzard's checkboxes for the player's and the cursor's coordinates on the map.
local MAP_CVARS = ns.WorldMap.COORDS_CVARS

-- Each of Blizzard's checkboxes that's off leaves a row out of the title bar, so World Map says so,
-- with a button for each, while this part is on.
local function offNotice(name, text, description)
    local notice = CVars.OffNotice(module.module, name, text, description)
    local off = notice.shown
    notice.shown = function()
        return module.db.coordinates and off()
    end
    return notice
end

module.module.notice = {
    offNotice(MAP_CVARS[1], L.COORDS_PLAYER_OFF, L.COORDS_PLAYER_OFF_DESC),
    offNotice(MAP_CVARS[2], L.COORDS_CURSOR_OFF, L.COORDS_CURSOR_OFF_DESC),
}

local INSET = 8 -- from the title bar's ends
local GAP = 12 -- the least room kept either side of the title
local THROTTLE = 0.05

-- The title bar ------------------------------------------------------------------------------

local coords -- Blizzard's panel, once found
local bar -- ours: two lines over the title bar

-- A line at one end of the bar: `point` is its side, against `edge`'s other side.
local function newLine(frame, point, edge, relativePoint, x)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint(point, edge, relativePoint, x, -1)
    line:SetJustifyH(point)
    line:SetWordWrap(false)
    return line
end

-- Our frame covers the title bar, a level above it so the text draws over its art. The title bar
-- is anchored to the map's frame, so it widens with the quest log and when the map is maximized,
-- and our lines follow. The cursor's stops short of the maximize button.
local function newBar(border)
    local title = border.TitleContainer
    local frame = CreateFrame("Frame", nil, border)
    frame:SetFrameLevel(title:GetFrameLevel() + 1)
    frame:SetAllPoints(title)
    frame.player = newLine(frame, "LEFT", frame, "LEFT", INSET)
    local button = border.MaximizeMinimizeFrame
    if button then
        frame.cursor = newLine(frame, "RIGHT", button, "LEFT", -INSET)
    else
        frame.cursor = newLine(frame, "RIGHT", frame, "RIGHT", -INSET)
    end
    return frame
end

local textWidth = ns.Text.Width

-- What each of our lines shows now, so a line whose text and room are the same isn't measured
-- again 20 times a second.
local shownText, shownRoom = {}, {}

-- One line from a row of Blizzard's: its text, which already has the tenths setting and, off the
-- player's map, the player's zone, cut short with "..." before it reaches the title.
local function copy(line, row, room)
    if not row:IsShown() then
        line:Hide()
        shownText[line] = nil
        return
    end
    local text = row.Label:GetText()
    local same = ns.IsText(text) and shownText[line] == text and shownRoom[line] == room
    if same and line:IsShown() then
        return
    end
    line:SetWidth(0)
    line:SetText(text)
    line:SetWidth(min(textWidth(line), max(room, 0)))
    line:Show()
    shownText[line], shownRoom[line] = ns.IsText(text) and text or nil, room
end

local function update()
    local titleText = WorldMapFrame.BorderFrame.TitleContainer.TitleText
    local titleWidth = titleText and textWidth(titleText) or 0
    -- Half the bar beside the title, less the ends and the maximize button's width on the right.
    local half = (bar:GetWidth() - titleWidth) / 2 - GAP - INSET
    local button = WorldMapFrame.BorderFrame.MaximizeMinimizeFrame
    copy(bar.player, coords.PlayerCoords, half)
    copy(bar.cursor, coords.CursorCoords, half - (button and button:GetWidth() or 0))
end

local onUpdate = ns.Profiler.Wrap(module, ns.Frames.Throttled(THROTTLE, update))

-- Ours in the title bar, or Blizzard's panel as it comes. Blizzard's text is only faded out, so
-- it keeps updating for ours to copy. Ours is the border frame's child, so it stops with the map.
local function restyle()
    local on = module.enabled and true or false
    coords:SetAlpha(on and 0 or 1)
    bar:SetShown(on)
    bar:SetScript("OnUpdate", on and onUpdate or nil)
    if on then
        update()
    end
end

local function attach(map)
    if not bar then
        local border = map.BorderFrame
        coords = ns.WorldMap.CoordsPanel()
        if not (coords and border and border.TitleContainer) then
            return -- a client without Blizzard's panel; its coordinates stay where they are
        end
        bar = newBar(border)
    end
    restyle()
end

function module:OnEnable()
    ns.WorldMap.WhenLoaded(attach)
end

function module:OnDisable()
    ns.WorldMap.Cancel(attach)
    if bar then
        restyle()
    end
end
