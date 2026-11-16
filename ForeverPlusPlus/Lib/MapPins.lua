-- Our own icons on the world map, through Blizzard's map data providers: the map asks for the
-- icons each time it shows a map and drops them when it leaves it. The icons are our own frames
-- on the map's canvas (no XML template, so no global mixin), kept the same size on screen at every
-- zoom. They show a tooltip but let clicks through, so the map still zooms and changes maps.
-- Nothing is made until a layer is enabled.
local _, ns = ...

local ipairs, pairs, select, setmetatable, hooksecurefunc = ipairs, pairs, select, setmetatable, hooksecurefunc
local CreateFrame = CreateFrame
local C_Map, GameTooltip = C_Map, GameTooltip
local CreateVector2D = CreateVector2D

local L = ns.L

local MapPins = {}
ns.MapPins = MapPins

local WorldMap = ns.WorldMap
local worldMap = WorldMap.Get

-- The options every module with icons on the world map has, with the same names, ranges, and
-- steps in each. `extra` adds fields (`requires`, `added`) or replaces one, such as a
-- `description` that says what the module's icons are.
local function withExtra(option, extra)
    for key, value in pairs(extra or {}) do
        option[key] = value
    end
    return option
end

---The icons' size slider: 50 to 200 percent of their normal size, in steps of 10.
---@param key string the module's option key
---@param section? string
---@param extra? table more fields for the option
---@return table option
function MapPins.SizeOption(key, section, extra)
    return withExtra({
        key = key, name = L.MAPPINS_SIZE, description = L.MAPPINS_SIZE_DESC, section = section,
        min = 50, max = 200, step = 10, format = "%d%%",
    }, extra)
end

---The icons' opacity slider: 10 to 100 percent, in steps of 5.
---@param key string
---@param section? string
---@param extra? table
---@return table option
function MapPins.OpacityOption(key, section, extra)
    return withExtra({
        key = key, name = L.MAPPINS_OPACITY, description = L.MAPPINS_OPACITY_DESC, section = section,
        min = 10, max = 100, step = 5, format = "%d%%",
    }, extra)
end

---The On Continent Maps checkbox: whether the icons show on maps above a zone's too.
---@param key string
---@param section? string
---@param extra? table
---@return table option
function MapPins.ContinentOption(key, section, extra)
    return withExtra({
        key = key, name = L.MAPPINS_CONTINENTS, description = L.MAPPINS_CONTINENTS_DESC,
        section = section,
    }, extra)
end

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

local IsShiftKeyDown, IsControlKeyDown = IsShiftKeyDown, IsControlKeyDown

-- Click hints: what clicks do on an icon, as green lines at the bottom of its tooltip, only while
-- Shift is held, so a tooltip is the thing itself until the player asks. Written here from what
-- the icon's `info` takes (see Clicks), for every layer alike: the Ctrl+click line is ours, and a
-- module gives only the words for its own actions (`clickHint`, `shiftHint`).
local function hints(info)
    local Note = ns.MapTooltip.Hint
    local list = {}
    if info.click and info.clickHint then
        list[#list + 1] = Note(info.clickHint)
    end
    if info.waypoint or info.ctrlClick then
        list[#list + 1] = Note(ns.L.MAPPINS_HINT_WAYPOINT)
    end
    if info.shiftClick and info.shiftHint then
        list[#list + 1] = Note(info.shiftHint)
    end
    return list
end

local function showTooltip(pin)
    local info = pin.info
    local lines = info.lines
    if type(lines) == "function" then
        lines = lines(info)
    end
    if IsShiftKeyDown() then
        -- A copy: the lines are the module's, and may be kept from one draw to the next.
        local all = {}
        for _, line in ipairs(lines or {}) do
            all[#all + 1] = line
        end
        for _, line in ipairs(hints(info)) do
            all[#all + 1] = line
        end
        lines = all
    end
    ns.MapTooltip.Show(pin, info.title, lines, info.kind)
end

-- Clicks: a pin lets every click through to the map (zooming, changing maps) except the ones its
-- `info` has something for, read when the click comes so a pooled pin needs no cleanup:
--   `click(pin, button)`      a plain left click; the pin then takes every click on it
--   `ctrlClick(pin)`          Ctrl+left click, the game's own gesture for the map pin
--   `waypoint = true`         the same, putting Blizzard's map pin on the pin's own spot
--   `shiftClick(pin, button)` a click with Shift held, either button
-- A pin with only the last three takes clicks only while that key is held over it.

local function takesClick(info)
    if info.click then
        return true
    end
    if (info.ctrlClick or info.waypoint) and IsControlKeyDown() then
        return true
    end
    return info.shiftClick ~= nil and IsShiftKeyDown()
end

-- While the mouse is on the pin: takes clicks or lets them through as the keys held say, and
-- shows its tooltip again when Shift goes up or down, for lines shown only with Shift.
local function watchKeys(pin)
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(takesClick(pin.info))
    end
    local shift = IsShiftKeyDown() and true or false
    if shift ~= pin.shiftWas then
        local first = pin.shiftWas == nil
        pin.shiftWas = shift
        if not first and GameTooltip:IsOwned(pin) then
            showTooltip(pin)
        end
    end
end

local function onMouseUp(pin, button)
    local info = pin.info
    if not info then
        return
    end
    if IsControlKeyDown() and (info.ctrlClick or info.waypoint) then
        if button ~= "LeftButton" then
            return
        end
        if info.ctrlClick then
            info.ctrlClick(pin)
        elseif pin.mapID then
            -- Named after the icon, for what shows the pin (WorldMap.WaypointNote).
            local title = info.title
            if type(title) == "table" then
                title = title[1]
            end
            ns.WorldMap.SetWaypoint(pin.mapID, pin.x, pin.y, title)
        end
    elseif IsShiftKeyDown() and info.shiftClick then
        info.shiftClick(pin, button)
    elseif info.click and button == "LeftButton" then
        info.click(pin, button)
    end
end

local function onEnter(pin)
    showTooltip(pin)
    -- An empty ring has nothing to light up: its art is hidden, and the highlight would fill it.
    if not pin.info.hollow then
        pin.highlight:Show()
    end
    watchKeys(pin)
    pin:SetScript("OnUpdate", watchKeys)
end

local function onLeave(pin)
    -- Only its own: the controller's cursor can be on one of Blizzard's pins by now, with its tooltip.
    if GameTooltip:IsOwned(pin) then
        GameTooltip:Hide()
    end
    pin.highlight:Hide()
    pin:SetScript("OnUpdate", nil)
    pin.shiftWas = nil
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(false)
    end
end

local function newPin(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin.ringAbove = true -- every pin of a layer shares one frame level (SetArt)
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
    pin:SetScript("OnMouseUp", onMouseUp)
    return pin
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

local padPin -- the pin the controller's cursor is on (see The controller's cursor)

-- Hides every pin and keeps it for the next map.
function Layer:Release()
    for i = 1, self.count do
        local pin = self.pins[i]
        if GameTooltip:IsOwned(pin) then
            GameTooltip:Hide()
        end
        if pin == padPin then
            -- The controller's cursor was on it, and a hidden pin gets no leave of its own.
            padPin = nil
            onLeave(pin)
        end
        pin:Hide()
        pin.info = nil
    end
    self.count = 0
end

-- The round mask Mainline's portraits use, for an icon drawn round, on the world map or, through
-- SetArt, the minimap.
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
        if not pin.ring then
            -- With `ringAbove`, the ring is in a frame of its own one level up: at one frame level
            -- the game draws every pin's art before every pin's ring, so a neighbor's ring could
            -- land between a pin's icon and its own ring (in game, 2026-11-07). Up a level, every
            -- ring is above every icon.
            local holder = pin
            if pin.ringAbove then
                holder = CreateFrame("Frame", nil, pin)
                holder:SetAllPoints(pin)
                holder:EnableMouse(false)
                holder:SetFrameLevel(pin:GetFrameLevel() + 1)
                pin.ringFrame = holder
            end
            pin.ring = ns.MinimapPins.NewRing(holder)
        end
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
    pin.mapID = map:GetMapID() -- for `waypoint`
    MapPins.SetArt(pin, info)
    -- Where Blizzard's own dungeon entrance icons go: above the map art and areas, below quests.
    local manager = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if manager then
        pin:SetFrameLevel(manager:GetValidFrameLevel("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE"))
        if pin.ringFrame then
            pin.ringFrame:SetFrameLevel(pin:GetFrameLevel() + 1)
        end
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

-- The controller's cursor ---------------------------------------------------------------------
-- With the controller interface on there's no mouse over the map: Blizzard moves a cursor of its
-- own (SoftCursor) and "enters" the pin it's on by itself, but only pins from the map's own pools
-- (MapCanvasMixin:UpdateGamepadCursor, Blizzard_MapCanvas.lua, build 70938). So while that cursor
-- shows, a frame on the map looks for the icon of ours under it and shows its tooltip as the
-- mouse would. Nothing runs without the controller interface, or while the map is closed.
-- **Unverified** in game: read from the source, and whether Forever has SoftCursor at all.

local layers = {} -- every layer made, to find the pin under the cursor
local PAD_INTERVAL = 0.05 -- seconds between looks
local PAD_REACH = 6 -- screen pixels past a pin's edge that still count as on it
local padWatcher, padElapsed = nil, 0

-- A frame's center in screen pixels, whatever its scale.
local function screenCenter(frame)
    local x, y = frame:GetCenter()
    if not x then
        return nil
    end
    local scale = frame:GetEffectiveScale()
    return x * scale, y * scale
end

local function padLeave()
    if padPin then
        local pin = padPin
        padPin = nil
        pin:SetScript("OnUpdate", nil)
        if pin.info then
            onLeave(pin)
        end
    end
end

local function padLook(_, elapsed)
    padElapsed = padElapsed + elapsed
    if padElapsed < PAD_INTERVAL then
        return
    end
    padElapsed = 0
    local cursor = _G.SoftCursor
    local cx, cy
    -- Only while the map has the controller's focus: the cursor stays shown after focus moves to
    -- the quest list beside it.
    local map = padWatcher:GetParent()
    local focused = not map.IsCanvasGamepadFocus or map:IsCanvasGamepadFocus()
    if focused and cursor and cursor:IsShown() then
        cx, cy = screenCenter(cursor)
    end
    local best, bestDistance
    if cx then
        for _, layer in ipairs(layers) do
            for i = 1, layer.count do
                local pin = layer.pins[i]
                local px, py = screenCenter(pin)
                if px and pin:IsVisible() then
                    local dx, dy = px - cx, py - cy
                    local distance = dx * dx + dy * dy
                    local reach = pin:GetWidth() * pin:GetEffectiveScale() / 2 + PAD_REACH
                    if distance <= reach * reach and (not bestDistance or distance < bestDistance) then
                        best, bestDistance = pin, distance
                    end
                end
            end
        end
    end
    if best ~= padPin then
        padLeave()
        if best then
            padPin = best
            onEnter(best)
        end
    end
end

local function padWatch(map)
    -- Not made at all without the controller interface, which takes a reload to turn on.
    if padWatcher or not map or not ns.Menus.GamepadUI() then
        return
    end
    padWatcher = CreateFrame("Frame", nil, map)
    padWatcher:SetScript("OnShow", function(self)
        padElapsed = 0
        self:SetScript("OnUpdate", ns.Menus.GamepadUI() and _G.SoftCursor and padLook or nil)
    end)
    padWatcher:SetScript("OnHide", padLeave)
    -- The A button: the map clicks its own pins under the cursor (ClickHoveredPins), then goes
    -- into the zone there (WorldMapMixin:GamepadMapClick, build 70938). Ours aren't among its
    -- pins, so the one under the cursor gets its plain click here, between the two. Seen in game
    -- 2026-11-16: the tooltips showed, but A did nothing on a dungeon's icon.
    if map.ClickHoveredPins then
        hooksecurefunc(map, "ClickHoveredPins", function()
            local pin = padPin
            local info = pin and pin.info
            if info and info.click then
                info.click(pin, "LeftButton")
            end
        end)
    end
    if map:IsVisible() then
        padWatcher:GetScript("OnShow")(padWatcher)
    end
end

-- Adds the layer to the world map, once it has loaded.
function Layer:Attach(map)
    padWatch(map)
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
---`{ atlas, size, title, kind, lines, desaturated }` (size in pixels on screen; the title, its
---kind, and lines of tooltip text under it, as `ns.MapTooltip.Show` takes them, `lines` also as
---`fn(info)` giving them when the tooltip shows; desaturated to gray the icon). In place of
---`atlas`, `texture` (a file ID or path, such as an item icon) with `trim` to cut off an item
---icon's edge. Any pin can also have `round` (drawn round), `color` ({ r, g, b } it's tinted),
---`alpha`, `ring` (the minimap's gold ring around it), `hollow` (only the ring, its art
---hidden), and what a click on it does (see Clicks above): `waypoint = true` (Ctrl+click puts
---Blizzard's map pin on its spot) or `ctrlClick` (`fn(pin)` in its place), `shiftClick`
---(`fn(pin, button)` with Shift held), and `click` (`fn(pin, button)` on a plain left click,
---which then doesn't reach the map). `clickHint` and `shiftHint` are the words for what its own
---`click` and `shiftClick` do, shown with the Ctrl+click line at the bottom of its tooltip while
---Shift is held; a module never writes hint lines itself. Call `layer:Enable()` to show it and
---`layer:Disable()` to take it off.
---@param fill fun(mapID: number, add: fun(x: number, y: number, info: table))
---@return table layer
function MapPins.New(fill)
    local layer = setmetatable({ fill = fill, pins = {}, count = 0 }, Layer)
    layers[#layers + 1] = layer
    return layer
end
