-- Our own icons on the minimap at spots on the zone map: what the minimap shows right now (the
-- player's spot, how far it sees, and how it's turned), and turning a spot on the map into a spot
-- on the minimap and back. Exact through moving, turning, and zooming, since it's worked out from
-- the player's own position rather than read from the minimap. Nothing is listened to until a
-- module first asks.
local _, ns = ...

local sin, cos, pairs, next, type = math.sin, math.cos, pairs, next, type
local CreateFrame, C_TooltipInfo, strtrim = CreateFrame, C_TooltipInfo, strtrim
local Minimap, GetCVarBool, GetPlayerFacing, GetUnitSpeed = Minimap, GetCVarBool, GetPlayerFacing, GetUnitSpeed
local C_Minimap, GetCursorPosition = C_Minimap, GetCursorPosition

local readable = ns.IsReadable

local MinimapPins = {}
ns.MinimapPins = MinimapPins

local rotating -- the rotateMinimap setting, nil until read and again after a CVar changes
local listening = false

---Whether the minimap turns with the player (Blizzard's Rotate Minimap setting).
---@return boolean
function MinimapPins.Rotating()
    if not listening then
        listening = true
        ns.On("CVAR_UPDATE", function()
            rotating = nil
        end)
    end
    if rotating == nil then
        rotating = GetCVarBool("rotateMinimap") and true or false
    end
    return rotating
end

local view = {}

---What the minimap shows right now: `mapID` (the player's zone map) and `x`, `y` (their spot on
---it, 0 to 1), the map's `width` and `height` in yards, `half` (half the minimap's width), `scale`
---(minimap units per yard), and `angle` (what the minimap is turned by, 0 unless it rotates). Nil
---when any of it can't be read, as in an instance. With `mapID`, on that map (one the player is
---on, such as the zone above their cave) instead of the one they're on. The same table every
---call, filled anew, so read it right away rather than keeping it.
---@param mapID? number
---@return table? view
function MinimapPins.View(mapID)
    local x, y
    mapID, x, y = ns.WorldMap.PlayerPosition(mapID)
    if not mapID then
        return nil
    end
    local width, height = ns.WorldMap.Size(mapID)
    if not width then
        return nil
    end
    local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if not (radius and ns.IsNumber(radius) and radius > 0) then
        return nil
    end
    local angle = 0
    if MinimapPins.Rotating() then
        angle = GetPlayerFacing and GetPlayerFacing()
        if not (angle and readable(angle)) then
            return nil
        end
    end
    view.mapID, view.x, view.y, view.width, view.height = mapID, x, y, width, height
    view.half = Minimap:GetWidth() / 2
    view.scale = view.half / radius
    view.angle = angle
    return view
end

---A spot on the view's zone map as minimap units right and up of the minimap's center.
---@param v table a view
---@param x number
---@param y number
---@return number right
---@return number up
function MinimapPins.ToMinimap(v, x, y)
    local east = (x - v.x) * v.width * v.scale
    local north = (v.y - y) * v.height * v.scale
    local c, s = cos(v.angle), sin(v.angle)
    return east * c + north * s, north * c - east * s
end

---Minimap units right and up of the minimap's center as a spot on the view's zone map.
---@param v table a view
---@param right number
---@param up number
---@return number x
---@return number y
function MinimapPins.FromMinimap(v, right, up)
    local c, s = cos(v.angle), sin(v.angle)
    local east, north = right * c - up * s, right * s + up * c
    return v.x + east / (v.width * v.scale), v.y - north / (v.height * v.scale)
end

---Where the mouse is, as minimap units right and up of the minimap's center.
---@return number right
---@return number up
function MinimapPins.CursorOffset()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    return x / scale - (cx or 0), y / scale - (cy or 0)
end

---Whether a spot right and up of the minimap's center is on the minimap, at least `inset` units
---inside its edge.
---@param right number
---@param up number
---@param inset? number
---@return boolean
function MinimapPins.Inside(right, up, inset)
    local radius = Minimap:GetWidth() / 2 - (inset or 0)
    return right * right + up * up <= radius * radius
end

-- Hovering a dot -----------------------------------------------------------------------------------
-- What the player's own mouse points at on the minimap: the game names the dots under the mouse
-- (C_TooltipInfo.GetMinimapMouseover), and the middle of everywhere the mouse was while it named
-- the same ones is the dot's middle. Read a few times a second only while the mouse is on the
-- minimap and a module listens; each hover is told once, when the names change or the mouse
-- leaves, so moving across the minimap tells each dot once rather than at every spot.

local hoverListeners = {} -- fn -> true
local hoverFrame -- runs the reads while the mouse is on the minimap
local HOVER_READ = 0.05 -- seconds between reads
local sinceRead = 0
local hoverText, sumR, sumU, reads -- the names read now, and the mouse spots while they were

-- The names in the mouseover's first line, one a row (overlapping dots each add one), as plain
-- text, or nil.
local function hoverNames(text)
    local names = {}
    for row in text:gmatch("[^\n]+") do
        local name = strtrim(ns.Text.Plain(row))
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

local function flushHover()
    local text = hoverText
    hoverText = nil
    if not (text and reads and reads > 0) then
        return
    end
    local names = hoverNames(text)
    local right, up = sumR / reads, sumU / reads
    for fn in pairs(hoverListeners) do
        fn(names, right, up)
    end
end

local function readHover()
    local data = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_TooltipInfo.GetMinimapMouseover()
    local lines = data and data.lines
    local first = type(lines) == "table" and lines[1]
    local text = type(first) == "table" and first.leftText
    if not ns.IsText(text, true) then
        flushHover()
        return
    end
    if text ~= hoverText then
        flushHover()
        hoverText, sumR, sumU, reads = text, 0, 0, 0
    end
    local right, up = MinimapPins.CursorOffset()
    sumR, sumU, reads = sumR + right, sumU + up, reads + 1
end

local function onHoverUpdate(_, elapsed)
    sinceRead = sinceRead + elapsed
    if sinceRead < HOVER_READ then
        return
    end
    sinceRead = 0
    if not Minimap:IsMouseOver() then
        flushHover()
        hoverFrame:Hide()
        return
    end
    readHover()
end

local hookedHover = false

local function onMinimapEnter()
    if hoverFrame and next(hoverListeners) then
        sinceRead = HOVER_READ
        hoverFrame:Show()
    end
end

---Calls `fn(names, right, up)` once for each dot (or overlapping dots) the player points at on
---the minimap, while `on`: the names the game gives for it, and its middle in minimap units
---right and up of the minimap's center. Told when the mouse moves off it or leaves the minimap.
---@param fn fun(names: string[], right: number, up: number)
---@param on boolean
function MinimapPins.OnHover(fn, on)
    hoverListeners[fn] = on and true or nil
    if on and not hoverFrame then
        hoverFrame = CreateFrame("Frame")
        hoverFrame:Hide()
        hoverFrame:SetScript("OnUpdate", onHoverUpdate)
    end
    -- A script hook can't come off, so it's added once and does nothing while no one listens.
    if on and not hookedHover then
        hookedHover = true
        Minimap:HookScript("OnEnter", onMinimapEnter)
    end
    if next(hoverListeners) == nil and hoverFrame then
        hoverText = nil
        hoverFrame:Hide()
    elseif Minimap:IsMouseOver() then
        onMinimapEnter()
    end
end

-- The ring ---------------------------------------------------------------------------------------
-- The gold ring of the minimap's tracking button, which Blizzard also puts around a 24 pixel spec
-- icon (ItemDisplay.xml): the 64 pixel file with the icon's center 19 right and 18 down of its
-- corner. Scaled to the icon it's around.
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local RING_ICON, RING_FILE, RING_X, RING_Y = 24, 64, 19, 18

---A gold ring for an icon on `frame`, placed with PlaceRing.
---@param frame table
---@return table texture
function MinimapPins.NewRing(frame)
    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(RING)
    return ring
end

---Puts a ring around `icon`, an icon frame or texture `size` pixels across.
---@param ring table
---@param icon table
---@param size number
function MinimapPins.PlaceRing(ring, icon, size)
    local k = size / RING_ICON
    ring:SetSize(RING_FILE * k, RING_FILE * k)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", icon, "CENTER", -RING_X * k, RING_Y * k)
end

---A function that says whether icons on the minimap could have moved since it was last called:
---the player is moving, or turning while the minimap rotates. While they stand still the icons
---stay where they were, so a module can skip drawing them. Each caller makes its own, since it
---remembers the facing it last saw. On a boat the speed reads 0, so it says no there.
---@return fun(): boolean
function MinimapPins.NewMotion()
    local lastFacing
    return function()
        local speed = GetUnitSpeed and GetUnitSpeed("player")
        if not (ns.IsNumber(speed) and speed == 0) then
            return true
        end
        if MinimapPins.Rotating() then
            local facing = GetPlayerFacing and GetPlayerFacing()
            -- A facing that can't be read isn't kept, so the next comparison is never with a secret.
            if not (facing and readable(facing)) then
                lastFacing = nil
                return true
            elseif facing ~= lastFacing then
                lastFacing = facing
                return true
            end
        end
        return false
    end
end
