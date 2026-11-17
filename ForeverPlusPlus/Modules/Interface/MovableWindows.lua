-- Movable Windows: hold the move key and drag one of Blizzard's windows (character, spellbook,
-- professions, friends, bags, Settings, and the rest below) to put it somewhere else. It stays
-- there until it closes, for the session, or for good, as the player picks. With the scale key
-- held, the mouse wheel resizes one. Ideas from BlizzMove and Leatrix Plus's frame dragging; none
-- of their code.
--
-- Blizzard places these windows itself, so a moved one would jump back: the UI panel manager
-- anchors the left, center, and right panels each time one opens or closes
-- (FramePositionDelegate:UpdateUIPanelPositions, a forbidden frame addons can't hook), and bags
-- stack up from the bottom right (UpdateContainerFrameAnchors). Both end in the window's own
-- SetPoint, so that is hooked, with OnShow, to put a moved window back where the player left it.
-- Only the window's anchors change: no Blizzard table, attribute, or function is written or
-- called, so the panel manager's secure code stays untainted (Gethe `forever` branch,
-- UIParentPanelManager.lua:616, ContainerFrame.lua:1380, checked 2026-11-04). A window that holds
-- protected frames (IsProtected) moves only out of combat; one it couldn't put back in combat goes
-- back when combat ends.
local _, ns = ...

local ipairs, pairs, type, setmetatable = ipairs, pairs, type, setmetatable
local InCombatLockdown, UIParent, GetMouseFoci = InCombatLockdown, UIParent, GetMouseFoci
local GetCursorPosition, CreateFrame = GetCursorPosition, CreateFrame
local GetPhysicalScreenSize, GameTooltip = GetPhysicalScreenSize, GameTooltip
local TooltipDataProcessor, C_Timer, IsShiftKeyDown = TooltipDataProcessor, C_Timer, IsShiftKeyDown
local tostring = tostring
local _G = _G

local L = ns.L
local Keys = ns.Keys

local module = ns.NewModule("MovableWindows", L.MOVABLEWINDOWS_DESC, {
    enabled = false,
    moveKey = "shift", -- held while dragging; "none" drags with the left button alone
    area = "anywhere", -- where a drag can start: "anywhere" in the window, or its "title" bar only
    remember = "always", -- "always" (saved), "session" (until logout or /reload), or "never"
    -- (back to Blizzard's place when it closes)
    resetKey = "ctrl", -- held while clicking a window to put it back; "none" for the click alone
    resetClick = "right", -- "right", "middle", "left", or "off"
    positions = {}, -- window name -> { point, relativePoint, x, y }, for "always"
    scaleKey = "ctrl", -- held while the mouse wheel resizes the window under it; "off" for never
    scales = {}, -- window name -> its size as a percent of Blizzard's, for "always"
})
module.title = L.MOVABLEWINDOWS_TITLE
module.category = "interface"
module.presets = { developer = { enabled = true } }
module.added = "1.0.0"
-- Where windows go is a layout, so each profile keeps its own.
module.perProfile = { positions = true, scales = true }

module.options = {
    Keys.Option("moveKey", L.MOVABLEWINDOWS_KEY, L.MOVABLEWINDOWS_KEY_DESC),
    {
        key = "area", name = L.MOVABLEWINDOWS_AREA, description = L.MOVABLEWINDOWS_AREA_DESC,
        choices = {
            { "anywhere", L.MOVABLEWINDOWS_AREA_ANYWHERE },
            { "title", L.MOVABLEWINDOWS_AREA_TITLE },
        },
        added = "1.6.0",
    },
    {
        key = "remember", name = L.MOVABLEWINDOWS_REMEMBER, description = L.MOVABLEWINDOWS_REMEMBER_DESC,
        choices = {
            { "always", L.MOVABLEWINDOWS_REMEMBER_ALWAYS },
            { "session", L.MOVABLEWINDOWS_REMEMBER_SESSION },
            { "never", L.MOVABLEWINDOWS_REMEMBER_NEVER },
        },
    },
    {
        key = "resetClick", name = L.MOVABLEWINDOWS_RESET_CLICK, description = L.MOVABLEWINDOWS_RESET_CLICK_DESC,
        choices = {
            { "right", L.MOVABLEWINDOWS_CLICK_RIGHT },
            { "middle", L.MOVABLEWINDOWS_CLICK_MIDDLE },
            { "left", L.MOVABLEWINDOWS_CLICK_LEFT },
            { "off", L.MOVABLEWINDOWS_CLICK_OFF },
        },
    },
    Keys.Option("resetKey", L.MOVABLEWINDOWS_RESET_KEY, L.MOVABLEWINDOWS_RESET_KEY_DESC),
    {
        key = "scaleKey", name = L.MOVABLEWINDOWS_SCALE_KEY, description = L.MOVABLEWINDOWS_SCALE_KEY_DESC,
        -- No None: the wheel alone scrolls lists and zooms the camera.
        choices = {
            { "shift", L.KEY_SHIFT },
            { "ctrl", L.KEY_CTRL },
            { "alt", L.KEY_ALT },
            { "off", L.MOVABLEWINDOWS_CLICK_OFF },
        },
        added = "1.6.0",
    },
}

local resetKeyOption = module.options[#module.options - 1]

-- The key only matters while a click resets.
resetKeyOption.shown = function(db) return db.resetClick ~= "off" end

-- A left-click reset with the move key is a drag (see startDrag), so that reset never happens.
resetKeyOption.conflicts = {
    {
        key = "moveKey",
        when = function(db) return db.resetClick == "left" and db.resetKey == db.moveKey end,
        text = L.MOVABLEWINDOWS_RESET_IS_MOVE,
    },
}

-- The Reset Click choices, as OnMouseDown names the buttons.
local RESET_BUTTONS = { right = "RightButton", middle = "MiddleButton", left = "LeftButton" }

module.notice = {
    { text = L.MOVABLEWINDOWS_NOTICE, description = L.MOVABLEWINDOWS_NOTICE_DESC },
    ns.Gamepad.LimitedNotice(), -- a drag, a held key, and the mouse wheel
}

-- The windows, by global name. Most load with Blizzard's load-on-demand addons, so they're looked
-- for again as addons load; ones this client doesn't have are skipped. Retail names, checked
-- against the `forever` branch's addon list (2026-11-04).
local NAMES = {
    "CharacterFrame", "PlayerSpellsFrame", "ProfessionsBookFrame", "ProfessionsFrame",
    "FriendsFrame", "CommunitiesFrame", "PVEFrame", "PVPUIFrame", "AchievementFrame",
    "CollectionsJournal", "EncounterJournal", "MacroFrame", "ClassTrainerFrame", "InspectFrame",
    "DressUpFrame", "MailFrame", "OpenMailFrame", "MerchantFrame", "BankFrame", "GuildBankFrame",
    "AuctionHouseFrame", "GossipFrame", "QuestFrame", "TradeFrame", "TabardFrame",
    "PetitionFrame", "GuildRegistrarFrame", "ItemTextFrame", "ItemSocketingFrame",
    "TimeManagerFrame", "CalendarFrame", "AddonList", "LootFrame", "ContainerFrameCombinedBags",
    -- Not a UI panel (Blizzard_SettingsPanel.xml: centered once, movable, never placed again),
    -- but players want it out of the way while they change settings.
    "SettingsPanel",
    -- More of Blizzard's panels that load on Forever (UIPanelWindows in the `forever` branch,
    -- 1.60.1.70790): the currency window, the Classic-style group finder, flight maps, chat
    -- channels and settings, the guild's rank settings, a quest's details, and Help.
    "TokenFrame", "LFGParentFrame", "TaxiFrame", "FlightMapFrame", "ChannelFrame",
    "ChatConfigFrame", "GuildControlUI", "QuestLogPopupDetailFrame", "HelpFrame",
    -- The world map, only while it's the small window: Blizzard sizes and places it again each
    -- time it's maximized or minimized (WorldMapMixin:Maximize, Minimize), and maximized it fills
    -- the screen, so then it's left to Blizzard (see FULL_SCREEN).
    "WorldMapFrame",
    -- Midnight's Social window, which takes FriendsFrame's place while C_SocialUI.IsSystemEnabled()
    -- (Blizzard_SocialUI, SocialUIControl.lua): Forever's Friends window. In game it's a UI panel.
    "SocialUIFrame",
    -- The Escape menu: a panel the panel manager doesn't anchor (centerFrameSkipAnchoring).
    "GameMenuFrame",
    -- The small zone map (Shift+M) hangs from its tab, which Blizzard drags only once it's
    -- unlocked from the tab's menu (Blizzard_BattlefieldMap.lua); the rest is map canvas, which
    -- keeps its clicks. So the tab is what moves, locked or not.
    "BattlefieldMapTab",
    -- Not the shop: CatalogShopFrame and StoreFrame load in Blizzard's secure environment
    -- (UseSecureEnvironment), out of addons' reach.
}

-- Windows that can fill the screen, by name: while one does, it isn't dragged or placed.
-- IsMaximized only reads WorldMapMixin's own flag.
local FULL_SCREEN = {
    WorldMapFrame = function(frame) return frame.IsMaximized and frame:IsMaximized() end,
}
local MAX_BAGS = 13 -- ContainerFrame1 to 13: the backpack, bags, and bank bags
for i = 1, MAX_BAGS do
    NAMES[#NAMES + 1] = "ContainerFrame" .. i
end

local weak = { __mode = "k" }
local nameOf = setmetatable({}, weak) -- window -> its name, once hooked
local original = setmetatable({}, weak) -- window -> Blizzard's anchors before we first moved it
local wasMovable = setmetatable({}, weak) -- window -> whether it was movable before we made it so
local wasClamped = setmetatable({}, weak) -- window -> whether it was kept on screen before we did
local wasUserPlaced = setmetatable({}, weak) -- window -> IsUserPlaced before a drag
local baseScale = setmetatable({}, weak) -- window -> Blizzard's own scale, once we've resized it
local session = {} -- name -> position, for "session" and "never"
local sessionScales = {} -- name -> size percent, for "session" and "never"
local dragging -- the window being dragged, if any
local placing = false -- while we set a window's anchors or scale ourselves, so our hooks keep out

-- Windows the wheel doesn't resize: the world map sizes itself as it's maximized and minimized,
-- and the zone map's tab is only the handle of a map that wouldn't follow it.
local NO_SCALE = { WorldMapFrame = true, BattlefieldMapTab = true }
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 50, 200, 5 -- percents of Blizzard's size; a step a notch

-- Where the player left a window, or nil to leave it to Blizzard.
local function positionOf(name)
    if module.db.remember == "always" then
        return module.db.positions[name]
    end
    return session[name]
end

-- The size the player gave a window, as a percent of Blizzard's, or nil for Blizzard's.
local function scaleOf(name)
    if module.db.remember == "always" then
        return module.db.scales[name]
    end
    return sessionScales[name]
end

local function canMove(frame)
    if InCombatLockdown() and frame:IsProtected() then
        return false
    end
    local fullScreen = FULL_SCREEN[nameOf[frame]]
    return not (fullScreen and fullScreen(frame))
end

-- Puts a window where the player left it, at the size they gave it, if they moved or resized it.
local function place(frame)
    if placing or frame == dragging or not module.enabled then
        return
    end
    local name = nameOf[frame]
    local p, percent = positionOf(name), scaleOf(name)
    if not ((p or percent) and canMove(frame)) then
        return
    end
    placing = true
    if percent then
        if baseScale[frame] == nil then
            local scale = frame:GetScale()
            baseScale[frame] = ns.IsNumber(scale) and scale > 0 and scale or 1 -- Blizzard's, for a reset
        end
        frame:SetScale(baseScale[frame] * percent / 100)
    end
    if p then
        if original[frame] == nil then
            original[frame] = ns.Frames.GetPoints(frame) -- Blizzard's, for a reset
        end
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    placing = false
end

local function placeAll()
    for frame in pairs(nameOf) do
        place(frame)
    end
end

-- Blizzard's own anchors and scale from before we first changed the window. The panel manager
-- places its panels again as they open; this covers the windows it doesn't, like bags.
local function putBack(frame)
    if not ((original[frame] or baseScale[frame]) and canMove(frame)) then
        return
    end
    placing = true
    if baseScale[frame] then
        frame:SetScale(baseScale[frame])
        baseScale[frame] = nil
    end
    if original[frame] then
        ns.Frames.SetPoints(frame, original[frame])
    end
    placing = false
end

local function putAllBack()
    for frame in pairs(nameOf) do
        putBack(frame)
    end
end

local function held(key)
    return key == "none" or Keys.IsDown(key)
end

-- Puts one window back where Blizzard places it and forgets where the player left it.
local function resetWindow(frame)
    local name = nameOf[frame]
    session[name] = nil
    module.db.positions[name] = nil
    sessionScales[name] = nil
    module.db.scales[name] = nil
    putBack(frame)
end

-- Whether the mouse is on a window's title bar: within TITLE_HEIGHT of its top edge, since not
-- every window has a title bar of its own to ask (bags, the Escape menu).
local TITLE_HEIGHT = 28

local function onTitle(frame)
    local top, scale = frame:GetTop(), frame:GetEffectiveScale()
    if not (ns.IsNumber(top) and ns.IsNumber(scale)) or scale <= 0 then
        return true
    end
    local _, y = GetCursorPosition()
    y = y / scale
    return y <= top and y >= top - TITLE_HEIGHT
end

local function startDrag(frame, button)
    if dragging or not canMove(frame) then
        return
    end
    local db = module.db
    -- The reset click first, so a left click with its own key resets rather than drags. One that's
    -- the same as the drag (left with the move key) drags.
    if button == RESET_BUTTONS[db.resetClick] and held(db.resetKey)
        and not (button == "LeftButton" and db.resetKey == db.moveKey) then
        resetWindow(frame)
        return
    end
    if button ~= "LeftButton" or not held(db.moveKey) then
        return
    end
    if db.area == "title" and not onTitle(frame) then
        return
    end
    if original[frame] == nil then
        original[frame] = ns.Frames.GetPoints(frame)
    end
    if wasMovable[frame] == nil then
        wasMovable[frame] = frame:IsMovable() and true or false
    end
    if wasClamped[frame] == nil then
        wasClamped[frame] = frame:IsClampedToScreen() and true or false
    end
    wasUserPlaced[frame] = frame:IsUserPlaced() and true or false
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:StartMoving()
    dragging = frame
end

local function stopDrag(frame)
    if dragging ~= frame then
        return
    end
    dragging = nil
    frame:StopMovingOrSizing()
    -- StartMoving marks the window user-placed, which the client would save in its layout cache
    -- and use over Blizzard's own place; the place is ours to keep, so it goes back to what it was.
    frame:SetUserPlaced(wasUserPlaced[frame] or false)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    local p = { point, relativePoint, x, y }
    session[nameOf[frame]] = p
    if module.db.remember == "always" then
        module.db.positions[nameOf[frame]] = p
    end
end

local function onHide(frame)
    stopDrag(frame)
    local name = nameOf[frame]
    if module.db.remember == "never" and (session[name] or sessionScales[name]) then
        session[name], sessionScales[name] = nil, nil -- back to Blizzard's place and size for next time
        putBack(frame)
    end
end

-- Blizzard placing the window (the panel manager, the bag stack) would undo a move, so it's put
-- back straight after. A window can get several SetPoint calls in a row; each is answered, so
-- ours is the one left.
local function onSetPoint(frame)
    if placing or frame == dragging then
        return
    end
    -- Blizzard's place as it sets it now, so a reset puts the window there.
    original[frame] = ns.Frames.GetPoints(frame)
    place(frame)
end

-- Blizzard scales some windows itself (bags, to fit the screen), which would undo a resize: its
-- scale is the new one ours is a percent of.
local function onSetScale(frame)
    if placing or baseScale[frame] == nil then
        return
    end
    local scale = frame:GetScale()
    if ns.IsNumber(scale) and scale > 0 then
        baseScale[frame] = scale
        place(frame)
    end
end

local function hook(name)
    local frame = _G[name]
    if type(frame) ~= "table" or nameOf[frame] or not frame.HookScript then
        return
    end
    nameOf[frame] = name
    module:HookScript(frame, "OnMouseDown", startDrag)
    module:HookScript(frame, "OnMouseUp", stopDrag)
    module:HookScript(frame, "OnShow", place)
    module:HookScript(frame, "OnHide", onHide)
    module:Hook(frame, "SetPoint", onSetPoint)
    module:Hook(frame, "SetScale", onSetScale)
    -- The title bar, where a window is most often grabbed, can take the click itself.
    local title = frame.TitleContainer
    if type(title) == "table" and title.HookScript then
        module:HookScript(title, "OnMouseDown", function(_, button)
            startDrag(frame, button)
        end)
        module:HookScript(title, "OnMouseUp", function()
            stopDrag(frame)
        end)
    end
end

-- Many windows are covered by frames of their own that take the click first, so the window never
-- hears it: the group finder's Browse and Listing pages fill it (Blizzard_LFGVanilla_Browse.xml),
-- and tabs, headers, and bars sit over others. So a click anywhere in one, with the move key or
-- the reset key held, finds the window it's in and drags or resets that, unless it's on something
-- the player uses (a button, a checkbox, a text box, a slider, or a scrolling area such as the
-- world map's canvas, which pans), which keeps the click.
-- A model keeps it too: dragging one turns it (the dressing room's character, a mount in the
-- journal), so moving the window from it would do both at once.
local USED = { Button = true, CheckButton = true, EditBox = true, Slider = true, ScrollFrame = true,
    Model = true, PlayerModel = true, DressUpModel = true, TabardModel = true, CinematicModel = true,
    ModelScene = true }
local MAX_DEPTH = 20 -- frames to walk up from the one clicked

local function windowAt()
    local focus = GetMouseFoci and GetMouseFoci()[1]
    if type(focus) ~= "table" or not focus.GetParent then
        return nil
    end
    if focus.IsForbidden and focus:IsForbidden() or focus.GetObjectType and USED[focus:GetObjectType()] then
        return nil
    end
    local frame = focus
    for _ = 1, MAX_DEPTH do
        if nameOf[frame] then
            return frame
        end
        frame = frame:GetParent()
        if not frame or frame.IsForbidden and frame:IsForbidden() then
            return nil
        end
    end
    return nil
end

local function onGlobalMouseDown(_, button)
    local db = module.db
    local resetting = button == RESET_BUTTONS[db.resetClick] and held(db.resetKey)
    if dragging or not (resetting or button == "LeftButton" and held(db.moveKey)) then
        return
    end
    local frame = windowAt()
    if frame then
        startDrag(frame, button)
    end
end

-- The drag may have started on a frame inside the window, which gets the mouse up instead.
local function onGlobalMouseUp()
    if dragging then
        stopDrag(dragging)
    end
end

-- Resizing --------------------------------------------------------------------------------------
-- With the scale key held, the mouse wheel makes the window under the mouse bigger or smaller. A
-- window hears the wheel only if Blizzard gave it a wheel handler, and giving it one would be
-- changing Blizzard's frame, so a frame of our own over the whole screen takes the wheel instead:
-- it's shown only while the key is held, takes no clicks, and takes the wheel only while the mouse
-- is over one of the windows. Which window is worked out from where the windows are, since our
-- frame is what's under the mouse then.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local catcher -- our frame, made the first time the key is held
local hovered -- the window under the mouse while the key is held

-- The topmost window that can be resized under the mouse, or nil.
local function windowUnderMouse()
    local x, y = GetCursorPosition()
    local best, bestRank
    for frame, name in pairs(nameOf) do
        if not NO_SCALE[name] and ns.IsTrue(frame:IsVisible()) then
            local scale = frame:GetEffectiveScale()
            local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
            if ns.IsNumber(scale) and scale > 0 and ns.IsNumber(left) and ns.IsNumber(right)
                and ns.IsNumber(top) and ns.IsNumber(bottom)
                and x >= left * scale and x <= right * scale and y >= bottom * scale and y <= top * scale then
                local rank = (STRATA[frame:GetFrameStrata()] or 0) * 10000 + frame:GetFrameLevel()
                if not best or rank > bestRank then
                    best, bestRank = frame, rank
                end
            end
        end
    end
    return best
end

local function onWheel(_, delta)
    local frame = hovered
    if dragging or not (frame and canMove(frame)) then
        return
    end
    local name = nameOf[frame]
    local old = scaleOf(name) or 100
    local new = old + (delta > 0 and SCALE_STEP or -SCALE_STEP)
    new = new < SCALE_MIN and SCALE_MIN or new > SCALE_MAX and SCALE_MAX or new
    if new == old then
        return
    end
    -- A moved window's place is in its own units, which just changed size: kept where it is.
    local p = positionOf(name)
    if p then
        p[3], p[4] = p[3] * old / new, p[4] * old / new
    end
    sessionScales[name] = new
    if module.db.remember == "always" then
        module.db.scales[name] = new
    end
    place(frame)
end

-- Runs each frame while the key is held. A key let go while the game wasn't looking (Alt+Tab)
-- sends no event, so it's asked again here.
local function watch(self)
    if not (module.enabled and Keys.IsDown(module.db.scaleKey)) then
        hovered = nil
        self:Hide()
        return
    end
    hovered = not dragging and windowUnderMouse() or nil
    self:EnableMouseWheel(hovered ~= nil)
end

local function onModifier()
    local want = Keys.IsDown(module.db.scaleKey)
    if want and not catcher then
        catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("TOOLTIP")
        catcher:EnableMouse(false)
        catcher:EnableMouseWheel(false)
        catcher:SetScript("OnUpdate", watch)
        catcher:SetScript("OnMouseWheel", onWheel)
        catcher:Hide()
    end
    if catcher then
        catcher:SetShown(want)
    end
end

local function hookAll()
    for _, name in ipairs(NAMES) do
        hook(name)
    end
    placeAll()
end

module.actions = {
    {
        name = L.MOVABLEWINDOWS_RESET, button = L.MOVABLEWINDOWS_RESET_BUTTON,
        description = L.MOVABLEWINDOWS_RESET_DESC,
        fn = function()
            module.db.positions = {}
            module.db.scales = {}
            for name in pairs(session) do
                session[name] = nil
            end
            for name in pairs(sessionScales) do
                sessionScales[name] = nil
            end
            putAllBack()
            ns.Print(L.MOVABLEWINDOWS_RESET_DONE)
        end,
    },
}

-- Steady tooltips ---------------------------------------------------------------------------------
-- The game wraps a tooltip's wrapped lines at the width of its widest line that doesn't wrap (an
-- item's name). When a wrapped line's first line is exactly that wide, rounding in where the
-- tooltip sits decides whether its last word fits, and at some places on screen the answer flips
-- each time the tooltip is redrawn (five times a second for a bag item), so the word hops between
-- two lines. Blizzard's own place for the bags happens not to be one of those places; a moved bag
-- can be, and so can any other moved window (a Waylaid Crate's "Use:" line, with only Blizzard's
-- lines on the tooltip; docs/forever-api.md has the numbers). Nowhere to put a window avoids it:
-- whole pixels and a whole number of pixels from Blizzard's place were both tried.
-- So the tie is broken instead: a tooltip gets a minimum width half a screen pixel over its own,
-- which gives a word that only just fits half a pixel to spare, more than rounding moves it.
-- Its own width is only known a frame after it's first drawn (read in the post call, it's still
-- the last tooltip's, which made every tooltip as wide as the one before), so it's read then,
-- kept for as long as the tooltip shows the same thing, and used on every redraw of it.
local pinned = setmetatable({}, weak) -- tooltip -> the minimum width we gave it
local seen = setmetatable({}, weak) -- tooltip -> what it's showing, as identity() names it
local natural = setmetatable({}, weak) -- tooltip -> that content's own width, once laid out

-- A minimum width is the width of what's inside the tooltip: the game adds the tooltip's edges
-- on top (given its own width, a tooltip came out some 30 pixels wider). How much it adds isn't
-- ours to know, so it's measured once, on the first tooltip we give a minimum: nil until then.
local border

-- What a tooltip shows, the same for every redraw of it, or nil when the game hides it. Shift
-- changes our price lines, and with them the width.
local function identity(data)
    local kind, id, guid = data.type, data.id, data.guid
    if not (ns.IsReadable(kind) and ns.IsReadable(id) and ns.IsReadable(guid)) then
        return nil
    end
    return tostring(kind) .. ":" .. tostring(id) .. ":" .. tostring(guid) .. (IsShiftKeyDown() and ":s" or "")
end

-- Gives the tooltip its minimum width, and says whether that changed anything.
local function pin(tooltip)
    local width, scale, minimum = natural[tooltip], tooltip:GetEffectiveScale(), tooltip:GetMinimumWidth()
    local _, height = GetPhysicalScreenSize()
    if not (width and ns.IsNumber(scale) and scale > 0 and ns.IsNumber(minimum)
        and ns.IsNumber(height) and height > 0) then
        return false
    end
    local wanted = width - (border or 0) + 768 / height / scale / 2
    if wanted <= minimum then
        return false -- Blizzard gave it more already
    end
    tooltip:SetMinimumWidth(wanted)
    pinned[tooltip] = tooltip:GetMinimumWidth() -- as the game keeps it
    return true
end

-- Ours never outlives the draw it was for: taken off when the tooltip is cleared for the next
-- one, which may be plain text (a button's name) that gets no post call to set its own.
local function unpin(tooltip)
    local ours = pinned[tooltip]
    if ours then
        pinned[tooltip] = nil
        local minimum = tooltip:GetMinimumWidth()
        if ns.IsNumber(minimum) and minimum == ours then
            tooltip:SetMinimumWidth(0)
        end
    end
end

local function forget(tooltip)
    unpin(tooltip)
    seen[tooltip], natural[tooltip] = nil, nil
end

local function steady(tooltip, data)
    if tooltip ~= GameTooltip then
        return
    end
    local id = type(data) == "table" and identity(data)
    if not id then
        seen[tooltip], natural[tooltip] = nil, nil
        return
    end
    if seen[tooltip] == id then
        pin(tooltip) -- a redraw of the same thing
        return
    end
    seen[tooltip], natural[tooltip] = id, nil
    unpin(tooltip) -- the last thing's, if it's somehow still on
    -- Next frame it's laid out: its width is its own, and it's drawn again with room to spare.
    C_Timer.After(0, function()
        if seen[tooltip] ~= id or pinned[tooltip] or not module.enabled then
            return
        end
        local width = tooltip:GetWidth()
        if ns.IsTrue(tooltip:IsShown()) and ns.IsNumber(width) and width > 0 then
            natural[tooltip] = width
            if not pin(tooltip) then
                return
            end
            tooltip:Show()
            if border then
                return
            end
            -- The first time: a frame on, how much wider than asked it came out is the edges.
            local asked = pinned[tooltip]
            C_Timer.After(0, function()
                if border or seen[tooltip] ~= id or pinned[tooltip] ~= asked then
                    return
                end
                local now = tooltip:GetWidth()
                if ns.IsNumber(now) then
                    border = now > asked and now - asked or 0
                    unpin(tooltip)
                    if pin(tooltip) then
                        tooltip:Show()
                    end
                end
            end)
        end
    end)
end

function module:OnEnable()
    if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
        self:TooltipPostCall(TooltipDataProcessor.AllTypes, steady)
        self:HookScript(GameTooltip, "OnHide", forget)
        self:HookScript(GameTooltip, "OnTooltipCleared", unpin)
        -- Every use of the tooltip starts here, whether or not it's told it was cleared.
        self:Hook(GameTooltip, "SetOwner", unpin)
    end
    hookAll()
    self:On("ADDON_LOADED", hookAll)
    self:On("GLOBAL_MOUSE_DOWN", onGlobalMouseDown)
    self:On("GLOBAL_MOUSE_UP", onGlobalMouseUp)
    self:On("MODIFIER_STATE_CHANGED", onModifier)
    -- Moves that waited out combat (a window holding protected frames).
    self:On("PLAYER_REGEN_ENABLED", placeAll)
end

-- Every window goes back to where Blizzard had it, and to how movable it was.
function module:OnDisable()
    if dragging then
        stopDrag(dragging)
    end
    if catcher then
        catcher:Hide()
    end
    hovered = nil
    forget(GameTooltip)
    putAllBack()
    for frame, movable in pairs(wasMovable) do
        if canMove(frame) then
            frame:SetMovable(movable)
        end
        wasMovable[frame] = nil
    end
    -- Kept on screen only while we moved it: as Blizzard had it again.
    for frame, clamped in pairs(wasClamped) do
        if canMove(frame) then
            frame:SetClampedToScreen(clamped)
        end
        wasClamped[frame] = nil
    end
end

function module:OnOptionChanged(key)
    if key == "remember" then
        -- A move made under the old choice is kept for the session, so nothing jumps now.
        if module.db.remember == "always" then
            for name, p in pairs(session) do
                module.db.positions[name] = p
            end
            for name, percent in pairs(sessionScales) do
                module.db.scales[name] = percent
            end
        end
    end
end
