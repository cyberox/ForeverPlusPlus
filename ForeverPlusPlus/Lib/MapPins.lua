-- Our own icons on the world map, through Blizzard's map data providers: the map asks for the
-- icons each time it shows a map and drops them when it leaves it. The icons are our own frames
-- on the map's canvas (no XML template, so no global mixin), kept the same size on screen at every
-- zoom. They show a tooltip but let clicks through, so the map still zooms and changes maps.
-- Nothing is made until a layer is enabled.
local _, ns = ...

local ipairs, select, setmetatable, hooksecurefunc = ipairs, select, setmetatable, hooksecurefunc
local CreateFrame = CreateFrame
local C_Map, GameTooltip = C_Map, GameTooltip
local CreateVector2D = CreateVector2D

local MapPins = {}
ns.MapPins = MapPins

local WorldMap = ns.WorldMap
local worldMap = WorldMap.Get

---The first atlas in the list this client has, or the last one. For art that may not exist on
---every build.
---@param ... string atlas names, best first
---@return string
function MapPins.Atlas(...)
    return ns.Frames.FirstAtlas(...) or (select(select("#", ...), ...))
end

-- Where one map sits on another, by map ID pair, once asked. The layout doesn't change.
local rects = {}

---A point on one map (x and y from 0 to 1) as a point on another that shows it, such as a zone
---on its continent, or nil when the game can't place it there.
---@param fromMap number
---@param toMap number
---@param x number
---@param y number
---@return number? x
---@return number? y
function MapPins.Translate(fromMap, toMap, x, y)
    local key = fromMap * 100000 + toMap
    local rect = rects[key]
    if rect == nil then
        rect = false
        if C_Map and C_Map.GetMapRectOnMap then
            local left, right, top, bottom = C_Map.GetMapRectOnMap(fromMap, toMap)
            if left and right > left and bottom > top then
                rect = { left, right, top, bottom }
            end
        end
        rects[key] = rect
    end
    local tx, ty
    if rect then
        tx, ty = rect[1] + (rect[2] - rect[1]) * x, rect[3] + (rect[4] - rect[3]) * y
    elseif C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        -- Probe: through world coordinates, when the game has no rectangle for the pair.
        local continent, world = C_Map.GetWorldPosFromMapPos(fromMap, CreateVector2D(x, y))
        if continent and world then
            local _, position = C_Map.GetMapPosFromWorldPos(continent, world, toMap)
            if position then
                tx, ty = position:GetXY()
            end
        end
    end
    if tx and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
        return tx, ty
    end
end

-- Pins ----------------------------------------------------------------------------------------

local function onEnter(pin)
    local info = pin.info
    local lines = info.lines
    if type(lines) == "function" then
        lines = lines(info)
    end
    ns.MapTooltip.Show(pin, info.title, lines, info.kind)
    -- An empty ring has nothing to light up: its art is hidden, and the highlight would fill it.
    if not info.hollow then
        pin.highlight:Show()
    end
end

local function onLeave(pin)
    GameTooltip:Hide()
    pin.highlight:Hide()
end

local function newPin(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin.texture = pin:CreateTexture(nil, "ARTWORK")
    pin.texture:SetAllPoints()
    pin.highlight = pin:CreateTexture(nil, "OVERLAY")
    pin.highlight:SetAllPoints()
    pin.highlight:SetBlendMode("ADD")
    pin.highlight:SetAlpha(0.5)
    pin.highlight:Hide()
    -- Hover for the tooltip; clicks go through to the map. Probe: without the split, the pin
    -- takes the mouse whole.
    if pin.SetMouseMotionEnabled and pin.SetMouseClickEnabled then
        pin:SetMouseMotionEnabled(true)
        pin:SetMouseClickEnabled(false)
    else
        pin:EnableMouse(true)
    end
    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    return pin
end

-- Shift-clicks ---------------------------------------------------------------------------------
-- A pin that does something on Shift+click takes clicks only while Shift is held over it, so a
-- plain click still goes through to the map (zooming, changing maps) or the minimap (a ping).

local IsShiftKeyDown = IsShiftKeyDown

-- While the mouse is on the pin: takes clicks only with Shift held, and shows its tooltip again
-- when Shift goes up or down, for lines shown only with Shift.
local function watchShift(pin)
    local shift = IsShiftKeyDown() and true or false
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(pin.shiftClick ~= nil and shift)
    end
    if shift ~= pin.shiftWas then
        local first = pin.shiftWas == nil
        pin.shiftWas = shift
        if not first and GameTooltip:IsOwned(pin) then
            pin:GetScript("OnEnter")(pin)
        end
    end
end

local function onShiftClick(pin, button)
    if IsShiftKeyDown() and pin.shiftClick then
        pin.shiftClick(pin, button)
    end
end

---Has `fn(pin, button)` run when the pin is clicked with Shift held; a click without Shift goes
---through to what's under the pin. Nil `fn` stops it. The pin's OnEnter and OnLeave are hooked
---(HookScript), so its own tooltip scripts stay.
---@param pin table
---@param fn? fun(pin: table, button: string)
function MapPins.ShiftClick(pin, fn)
    pin.shiftClick = fn
    if pin.shiftHooked or not fn then
        return
    end
    pin.shiftHooked = true
    pin:HookScript("OnEnter", function(self)
        watchShift(self)
        self:SetScript("OnUpdate", watchShift)
    end)
    pin:HookScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.shiftWas = nil
        if self.SetMouseClickEnabled then
            self:SetMouseClickEnabled(false)
        end
    end)
    pin:SetScript("OnMouseUp", onShiftClick)
end

-- Puts a pin at its place on the canvas, sized so the map's zoom doesn't change it on screen.
local function place(pin, map)
    local canvas = map:GetCanvas()
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
    local size = pin.info.size / (scale > 0 and scale or 1)
    pin:SetSize(size, size)
    if pin.info.ring then
        ns.MinimapPins.PlaceRing(pin.ring, pin, size)
    end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * pin.x,
        -canvas:GetHeight() * pin.y)
end

-- Blizzard's pins ------------------------------------------------------------------------------

local acquireHooks = {} -- functions to call after the world map acquires one of its own pins
local hooked = false

local function hookAcquire(map)
    if hooked then
        return
    end
    hooked = true
    hooksecurefunc(map, "AcquirePin", function(self, template, ...)
        for _, fn in ipairs(acquireHooks) do
            fn(self, template, ...)
        end
    end)
end

---Calls `fn(map, template, ...)` after the world map acquires a pin of its own, with what the map
---was given for it (for Blizzard's POI pins, the poiInfo), once the map has loaded. The hook
---can't come off, so `fn` checks whether its module is on. Asking again with the same `fn`
---changes nothing, so it can be called from `OnEnable`.
---@param fn fun(map: table, template: string, ...)
function MapPins.OnAcquire(fn)
    for _, known in ipairs(acquireHooks) do
        if known == fn then
            return
        end
    end
    acquireHooks[#acquireHooks + 1] = fn
    WorldMap.WhenLoaded(hookAcquire)
end

---Has the world map redraw everything on it, Blizzard's pins too, if it's open.
function MapPins.RefreshMap()
    local map = worldMap()
    if map and map:IsShown() and map.RefreshAllDataProviders then
        map:RefreshAllDataProviders()
    end
end

-- Layers --------------------------------------------------------------------------------------

local Layer = {}
Layer.__index = Layer

-- Hides every pin and keeps it for the next map.
function Layer:Release()
    for i = 1, self.count do
        local pin = self.pins[i]
        if GameTooltip:IsOwned(pin) then
            GameTooltip:Hide()
        end
        pin:Hide()
        pin.info = nil
    end
    self.count = 0
end

-- The round mask Mainline's portraits use, for an icon drawn round (Minimap Node Icons uses it on
-- the minimap too).
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TRIM = 0.08 -- the edge cut off an item icon, as the bags do

---Sets an icon frame's art from `info` as a layer's pins take it (see MapPins.New): an atlas, or
---a texture (an item icon) trimmed, optionally round, tinted, see-through, and ringed. `pin` has
---its art in `pin.texture`, and optionally a hover highlight in `pin.highlight`; the mask and the
---ring are made on it when first needed. For our icons elsewhere too, such as on the minimap; the
---ring is placed by whoever sizes the pin (MinimapPins.PlaceRing).
---@param pin table
---@param info table
function MapPins.SetArt(pin, info)
    local texture, highlight = pin.texture, pin.highlight
    if info.atlas then
        texture:SetAtlas(info.atlas)
        if highlight then
            highlight:SetAtlas(info.atlas)
        end
    else
        local trim = info.trim and TRIM or 0
        texture:SetTexture(info.texture)
        texture:SetTexCoord(trim, 1 - trim, trim, 1 - trim)
        if highlight then
            highlight:SetTexture(info.texture)
            highlight:SetTexCoord(trim, 1 - trim, trim, 1 - trim)
        end
    end
    local round = info.round and true or false
    if round ~= (pin.round or false) then
        if not pin.mask then
            pin.mask = pin:CreateMaskTexture()
            pin.mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            pin.mask:SetAllPoints(texture)
        end
        if round then
            texture:AddMaskTexture(pin.mask)
            if highlight then
                highlight:AddMaskTexture(pin.mask)
            end
        else
            texture:RemoveMaskTexture(pin.mask)
            if highlight then
                highlight:RemoveMaskTexture(pin.mask)
            end
        end
        pin.round = round
    end
    local color = info.color
    texture:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
    texture:SetDesaturated(info.desaturated or false)
    -- Hollow: the ring alone, nothing inside it.
    texture:SetShown(not info.hollow)
    pin:SetAlpha(info.alpha or 1)
    if info.ring then
        pin.ring = pin.ring or ns.MinimapPins.NewRing(pin)
        pin.ring:Show()
    elseif pin.ring then
        pin.ring:Hide()
    end
end

function Layer:Add(map, x, y, info)
    self.count = self.count + 1
    local pin = self.pins[self.count]
    if not pin then
        pin = newPin(map:GetCanvas())
        self.pins[self.count] = pin
    end
    pin.x, pin.y, pin.info = x, y, info
    MapPins.SetArt(pin, info)
    if info.shiftClick or pin.shiftClick then
        MapPins.ShiftClick(pin, info.shiftClick)
    end
    -- Where Blizzard's own dungeon entrance icons go: above the map art and areas, below quests.
    local manager = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if manager then
        pin:SetFrameLevel(manager:GetValidFrameLevel("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE"))
    end
    place(pin, map)
    pin:Show()
end

-- Draws the pins for the map it shows now.
function Layer:Draw()
    self:Release()
    local map = self.provider:GetMap()
    local mapID = map and map:GetMapID()
    if not mapID then
        return
    end
    self.fill(mapID, function(x, y, info)
        self:Add(map, x, y, info)
    end)
end

function Layer:Place()
    local map = self.provider:GetMap()
    if not map then
        return
    end
    for i = 1, self.count do
        place(self.pins[i], map)
    end
end

-- The layer's data provider: what the map calls as it changes maps and zooms. Made once the map
-- has loaded, since the mixin comes with it.
local function newProvider(layer)
    return WorldMap.NewProvider({
        RemoveAllData = function() layer:Release() end,
        RefreshAllData = function() layer:Draw() end,
        OnCanvasScaleChanged = function() layer:Place() end,
        OnCanvasSizeChanged = function() layer:Place() end,
    })
end

-- Adds the layer to the world map, once it has loaded.
function Layer:Attach(map)
    self.provider = self.provider or newProvider(self)
    if not self.attached then
        self.attached = true
        map:AddDataProvider(self.provider)
        -- Adding a provider doesn't draw it; the map only asks when it shows or changes map.
        if map:IsShown() then
            self:Draw()
        end
    end
end

---Shows the layer's pins on the world map.
function Layer:Enable()
    self.onLoad = self.onLoad or function(map)
        self:Attach(map)
    end
    WorldMap.WhenLoaded(self.onLoad)
end

---Takes the layer's pins off the world map.
function Layer:Disable()
    if self.onLoad then
        WorldMap.Cancel(self.onLoad)
    end
    if self.attached then
        self.attached = false
        worldMap():RemoveDataProvider(self.provider)
    end
    self:Release()
end

---Redraws the pins, after something that decides them changed (a setting).
function Layer:Refresh()
    if self.attached then
        self:Draw()
    end
end

---Makes a layer of map pins. `fill(mapID, add)` runs each time the map shows a map, and calls
---`add(x, y, info)` for each pin: x and y from 0 to 1 across the map, and info
---`{ atlas, size, title, lines, desaturated }` (size in pixels on screen; lines of tooltip text
---under the title, as `ns.MapTooltip.Show` takes them; desaturated to gray the icon). In place of
---`atlas`, `texture` (a file ID or path, such as an item icon) with `trim` to cut off an item
---icon's edge. Any pin can also have `round` (drawn round), `color` ({ r, g, b } it's tinted),
---`alpha`, `ring` (the minimap's gold ring around it), `hollow` (only the ring, its art
---hidden), and `shiftClick` (`fn(pin, button)` on a click with Shift held; see
---ShiftClick). Call `layer:Enable()` to show it and
---`layer:Disable()` to take it off.
---@param fill fun(mapID: number, add: fun(x: number, y: number, info: table))
---@return table layer
function MapPins.New(fill)
    return setmetatable({ fill = fill, pins = {}, count = 0 }, Layer)
end
