-- Movable Windows: hold the move key and drag one of Blizzard's windows (character, spellbook,
-- professions, friends, bags, Settings, and the rest below) to put it somewhere else. It stays there until
-- it closes, for the session, or for good, as the player picks. Ideas from BlizzMove and Leatrix
-- Plus's frame dragging; none of their code.
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
local _G = _G

local L = ns.L
local Keys = ns.Keys

local module = ns.NewModule("MovableWindows", L.MOVABLEWINDOWS_DESC, {
    enabled = false,
    moveKey = "shift", -- held while dragging; "none" drags with the left button alone
    remember = "always", -- "always" (saved), "session" (until logout or /reload), or "never"
    -- (back to Blizzard's place when it closes)
    resetKey = "ctrl", -- held while clicking a window to put it back; "none" for the click alone
    resetClick = "right", -- "right", "middle", "left", or "off"
    positions = {}, -- window name -> { point, relativePoint, x, y }, for "always"
})
module.title = L.MOVABLEWINDOWS_TITLE
module.category = "interface"
module.developer = { enabled = true }
module.added = "1.0.0"
-- Where windows go is a layout, so each profile keeps its own.
module.perProfile = { positions = true }

module.options = {
    Keys.Option("moveKey", L.MOVABLEWINDOWS_KEY, L.MOVABLEWINDOWS_KEY_DESC),
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
}

-- The key only matters while a click resets.
module.options[#module.options].shown = function(db) return db.resetClick ~= "off" end

-- A left-click reset with the move key is a drag (see startDrag), so that reset never happens.
module.options[#module.options].conflicts = {
    {
        key = "moveKey",
        when = function(db) return db.resetClick == "left" and db.resetKey == db.moveKey end,
        text = L.MOVABLEWINDOWS_RESET_IS_MOVE,
    },
}

-- The Reset Click choices, as OnMouseDown names the buttons.
local RESET_BUTTONS = { right = "RightButton", middle = "MiddleButton", left = "LeftButton" }

module.notice = { text = L.MOVABLEWINDOWS_NOTICE, description = L.MOVABLEWINDOWS_NOTICE_DESC }

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
local session = {} -- name -> position, for "session" and "never"
local dragging -- the window being dragged, if any
local placing = false -- while we set a window's anchors ourselves, so the SetPoint hook keeps out

-- Where the player left a window, or nil to leave it to Blizzard.
local function positionOf(name)
    if module.db.remember == "always" then
        return module.db.positions[name]
    end
    return session[name]
end

local function canMove(frame)
    if InCombatLockdown() and frame:IsProtected() then
        return false
    end
    local fullScreen = FULL_SCREEN[nameOf[frame]]
    return not (fullScreen and fullScreen(frame))
end

-- Puts a window where the player left it, if they moved it.
local function place(frame)
    if placing or frame == dragging or not module.enabled then
        return
    end
    local p = positionOf(nameOf[frame])
    if not (p and canMove(frame)) then
        return
    end
    if original[frame] == nil then
        original[frame] = ns.Frames.GetPoints(frame) -- Blizzard's, for a reset
    end
    placing = true
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    placing = false
end

local function placeAll()
    for frame in pairs(nameOf) do
        place(frame)
    end
end

-- Blizzard's own anchors from before we first moved the window. The panel manager places its
-- panels again as they open; this covers the windows it doesn't, like bags.
local function putBack(frame)
    if original[frame] and canMove(frame) then
        placing = true
        ns.Frames.SetPoints(frame, original[frame])
        placing = false
    end
end

local function putAllBack()
    for frame in pairs(original) do
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
    putBack(frame)
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
    if module.db.remember == "never" and session[nameOf[frame]] then
        session[nameOf[frame]] = nil -- back to Blizzard's place for next time
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
local USED = { Button = true, CheckButton = true, EditBox = true, Slider = true, ScrollFrame = true }
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
            for name in pairs(session) do
                session[name] = nil
            end
            putAllBack()
            ns.Print(L.MOVABLEWINDOWS_RESET_DONE)
        end,
    },
}

function module:OnEnable()
    hookAll()
    self:On("ADDON_LOADED", hookAll)
    self:On("GLOBAL_MOUSE_DOWN", onGlobalMouseDown)
    self:On("GLOBAL_MOUSE_UP", onGlobalMouseUp)
    -- Moves that waited out combat (a window holding protected frames).
    self:On("PLAYER_REGEN_ENABLED", placeAll)
end

-- Every window goes back to where Blizzard had it, and to how movable it was.
function module:OnDisable()
    if dragging then
        stopDrag(dragging)
    end
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
        end
    end
end
