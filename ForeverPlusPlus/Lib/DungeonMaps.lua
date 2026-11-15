-- Dungeon maps, for a module that wants to show one. The client has no dungeon map to open (no
-- dungeon-type UiMap, build 70938), but it still has the old dungeon map art as textures, so an
-- instance with art is drawn in a view of our own over the world map: the art, with Previous and
-- Next for an instance of several floors, and a right click to go back. Nothing is shipped; the
-- art has boss skulls and some banners painted in, and that's left as it is.
--
-- An instance without art (Scholomance in its Classic layout, Forever's new dungeons, or a game
-- language that lacks the textures) goes to the DungeonJournal addon (ForeverDungeonJournal,
-- 2.0.2) when it's there. It has no public API, so it's reached through what it leaves in reach,
-- read when called and every call protected: an update of its that moves things makes this say
-- "can't", never an error. Its shared table ForeverDungeonJournal_NS has DungeonFromInstanceName
-- (its key for an English name), DUNGEON_MAPS (which keys have a map), and OpenDungeonMap (selects
-- the dungeon and shows its map), which needs its window open first (ForeverDungeonJournal_Toggle
-- while ForeverDungeonJournalFrame isn't shown).
local _, ns = ...

local type, pcall, rawget, ipairs, pairs = type, pcall, rawget, ipairs, pairs
local min, CreateFrame, hooksecurefunc = math.min, CreateFrame, hooksecurefunc

local L = ns.L

local DungeonMaps = {}
ns.DungeonMaps = DungeonMaps

-- A global that may not be there (another addon's, or an API a patch could drop), or nil. rawget,
-- so a strict _G of someone's doesn't complain. Read when called, not kept.
local function global(name)
    return rawget(_G, name)
end

-- The game's art ---------------------------------------------------------------------------------
-- Each floor of an instance is 12 textures, Interface\WorldMap\<name>1 to 12: a grid 4 across and
-- 3 down of 256 pixel tiles, of which the last column uses 234 pixels and the last row 156, so a
-- map is 1002 by 668. Which textures each instance has is in Data/Instances.lua (dungeonArt, by
-- instance key), read here by instance ID. An instance whose first tile isn't in this client
-- counts as having no art.
local ART_PATH = "Interface\\WorldMap\\"

local ART = {} -- instance ID -> its floors, or { wings = { { key, name, floors }, ... } }
for key, art in pairs(ns.Data.dungeonArt) do
    local instance = ns.Data.instances[key]
    if instance then
        ART[instance[1]] = art
    end
end
local COLUMNS, ROWS, TILE = 4, 3, 256
local LAST_WIDTH, LAST_HEIGHT = 234, 156 -- the pixels of a tile used in the last column and row
local MAP_WIDTH = TILE * (COLUMNS - 1) + LAST_WIDTH
local MAP_HEIGHT = TILE * (ROWS - 1) + LAST_HEIGHT

local inClient = {} -- instance ID -> whether its art is in this client, once asked

-- An instance's art, if the game has it: its entry in ART, or nil.
local function artOf(instanceID)
    local art = instanceID and ART[instanceID]
    local fileID = art and global("GetFileIDFromPath")
    if not fileID then
        return nil
    end
    if inClient[instanceID] == nil then
        local first = art.wings and art.wings[1].floors[1] or art[1]
        local ok, id = pcall(fileID, ART_PATH .. first .. "1")
        inClient[instanceID] = ok and type(id) == "number" and id > 0
    end
    return inClient[instanceID] and art or nil
end

-- The floors of an instance the game has art for, or of the wing of it with that key (its first
-- wing when none is given), or nil.
local function floorsOf(instanceID, wingKey)
    local art = artOf(instanceID)
    if not (art and art.wings) then
        return art
    end
    for _, one in ipairs(art.wings) do
        if not wingKey or one.key == wingKey then
            return one.floors
        end
    end
end

-- Our view over the world map --------------------------------------------------------------------
-- A frame of our own over the map's canvas, above its pins, so the map itself isn't changed. It
-- takes the mouse while it's up, so the map under it doesn't pan, zoom, or leave for its parent.
-- Only the art, which has the instance's name painted on it, and, for an instance of several
-- floors, Previous and Next in its bottom corners. A right click goes back, as on the map.
local VIEW_LEVEL = 9000 -- above the canvas's pins, in the map's own strata
local view -- made the first time a map is shown
local shown -- { floors, floor } while the view is up

local function layout()
    local width, height = view:GetSize()
    local scale = min(width / MAP_WIDTH, height / MAP_HEIGHT)
    if not (scale > 0) then
        return
    end
    local left = (width - MAP_WIDTH * scale) / 2
    local top = (height - MAP_HEIGHT * scale) / 2
    for i, tile in ipairs(view.tiles) do
        local column, row = (i - 1) % COLUMNS, (i - 1 - (i - 1) % COLUMNS) / COLUMNS
        local w = column == COLUMNS - 1 and LAST_WIDTH or TILE
        local h = row == ROWS - 1 and LAST_HEIGHT or TILE
        tile:SetSize(w * scale, h * scale)
        tile:SetTexCoord(0, w / TILE, 0, h / TILE)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", view, "TOPLEFT", left + column * TILE * scale, -(top + row * TILE * scale))
    end
end

local function draw()
    local floors, floor = shown.floors, shown.floor
    for i, tile in ipairs(view.tiles) do
        tile:SetTexture(ART_PATH .. floors[floor] .. i)
    end
    view.previous:SetShown(#floors > 1)
    view.next:SetShown(#floors > 1)
end

local function close()
    shown = nil
    if view then
        view:Hide()
    end
end

local function onMouseUp(_, button)
    if shown and button == "RightButton" then
        close()
    end
end

-- Previous or Next: `step` floors on, round to the first after the last.
local function turn(step)
    return function(_, button)
        if not shown then
            return
        end
        if button == "RightButton" then
            close()
            return
        end
        shown.floor = (shown.floor - 1 + step) % #shown.floors + 1
        draw()
    end
end

-- A word to click, in white, gold under the mouse as Blizzard's text buttons are.
local function textButton(text, point, x, onClick)
    local button = CreateFrame("Button", nil, view)
    button:SetNormalFontObject("GameFontHighlight")
    button:SetHighlightFontObject("GameFontNormal")
    button:SetText(text)
    local label = button:GetFontString()
    button:SetSize(label:GetStringWidth() + 16, label:GetStringHeight() + 12)
    button:SetPoint(point, view, point, x, 16)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    return button
end

local function build(map)
    local canvas = map.ScrollContainer
    view = CreateFrame("Frame", nil, canvas)
    view:SetAllPoints(canvas)
    view:SetFrameLevel(VIEW_LEVEL)
    view:Hide()
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseUp", onMouseUp)
    view:SetScript("OnMouseWheel", function() end) -- kept from the map under it
    view:SetScript("OnSizeChanged", layout)
    -- The map closed with a dungeon up: it opens on the map again.
    view:SetScript("OnHide", close)

    local back = view:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(view)
    back:SetColorTexture(0, 0, 0, 1)

    view.tiles = {}
    for i = 1, COLUMNS * ROWS do
        view.tiles[i] = view:CreateTexture(nil, "ARTWORK")
    end

    view.previous = textButton(L.DUNGEONMAPS_PREVIOUS, "BOTTOMLEFT", 24, turn(-1))
    view.next = textButton(L.DUNGEONMAPS_NEXT, "BOTTOMRIGHT", -24, turn(1))

    -- Another map picked (the zone dropdown, the player zoning): the dungeon gives way to it.
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", close)
    end
end

-- Shows an instance's art over the world map, which must be open. Returns whether it did.
local function show(floors)
    local map = ns.WorldMap.Get()
    if not (map and map.ScrollContainer and map:IsShown()) then
        return false
    end
    if not view then
        build(map)
    end
    shown = { floors = floors, floor = 1 }
    draw()
    view:Show()
    layout()
    return true
end

-- DungeonJournal ---------------------------------------------------------------------------------

local function journal()
    local shared = global("ForeverDungeonJournal_NS")
    if type(shared) == "table" and type(shared.OpenDungeonMap) == "function"
        and type(shared.DungeonFromInstanceName) == "function" and type(shared.DUNGEON_MAPS) == "table"
        and type(global("ForeverDungeonJournal_Toggle")) == "function" then
        return shared
    end
end

-- DungeonJournal's key for an instance that has a map there, or nil.
local function journalKey(shared, name)
    local ok, key = pcall(shared.DungeonFromInstanceName, name)
    if ok and key ~= nil and shared.DUNGEON_MAPS[key] then
        return key
    end
end

local function journalCan(name)
    local shared = journal()
    return shared ~= nil and type(name) == "string" and journalKey(shared, name) ~= nil
end

---Whether any dungeon map can be shown: the client can be asked for its art, or DungeonJournal
---is there.
---@return boolean
function DungeonMaps.Has()
    return global("GetFileIDFromPath") ~= nil or journal() ~= nil
end

---Whether an instance's map can be shown, from the game's art or by DungeonJournal.
---@param name string? the instance's English name, as DungeonJournal knows it
---@param instanceID number? the instance's ID, as the game's art is listed
---@return boolean
function DungeonMaps.Can(name, instanceID)
    return artOf(instanceID) ~= nil or journalCan(name)
end

---The wings of an instance whose art is by wing (Dire Maul's east, west, and north), in order,
---each { key, name }, or nil for an instance of one piece or one without art. `Open` takes a key.
---@param instanceID number?
---@return { key: string, name: string }[]?
function DungeonMaps.Wings(instanceID)
    local art = artOf(instanceID)
    if not (art and art.wings) then
        return nil
    end
    local wings = {}
    for i, one in ipairs(art.wings) do
        wings[i] = { key = one.key, name = one.name }
    end
    return wings
end

---Whether DungeonJournal is there, for an option that needs it.
---@return boolean
function DungeonMaps.HasJournal()
    return journal() ~= nil
end

---Whether DungeonJournal has an instance's map.
---@param name string? the instance's English name
---@return boolean
function DungeonMaps.InJournal(name)
    return journalCan(name)
end

-- Asks DungeonJournal for an instance's map. Not in combat: it draws frames of its own, and
-- wasn't written to be driven by another addon there.
local function openJournal(name)
    if InCombatLockdown() or not journalCan(name) then
        return false
    end
    local shared = journal()
    local key = journalKey(shared, name)
    local window = global("ForeverDungeonJournalFrame")
    local open = type(window) == "table" and window.IsShown and window:IsShown()
    if not open and not pcall(global("ForeverDungeonJournal_Toggle")) then
        return false
    end
    return (pcall(shared.OpenDungeonMap, key))
end

---Shows an instance's map: the game's art over the open world map, or else in DungeonJournal
---(not in combat). With `journalFirst`, DungeonJournal when it has the map, or else the art.
---@param name string? the instance's English name
---@param instanceID number? the instance's ID
---@param wingKey string? the key of one of `Wings`, for an instance that has them (the first if
---not given)
---@param journalFirst boolean? the player would sooner have DungeonJournal's map
---@return boolean asked whether it was shown, or DungeonJournal asked (not whether it then drew it)
function DungeonMaps.Open(name, instanceID, wingKey, journalFirst)
    if journalFirst and openJournal(name) then
        return true
    end
    local floors = floorsOf(instanceID, wingKey)
    if floors and show(floors) then
        return true
    end
    return not journalFirst and openJournal(name)
end
