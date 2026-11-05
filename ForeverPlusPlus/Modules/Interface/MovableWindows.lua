-- Movable Windows: hold the move key and drag one of Blizzard's windows (character, spellbook,
-- professions, friends, bags, and the rest below) to put it somewhere else. It stays there until
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
local InCombatLockdown, UIParent = InCombatLockdown, UIParent
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
module.added = "1.0.0"

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
}
local MAX_BAGS = 13 -- ContainerFrame1 to 13: the backpack, bags, and bank bags
for i = 1, MAX_BAGS do
    NAMES[#NAMES + 1] = "ContainerFrame" .. i
end

local weak = { __mode = "k" }
local nameOf = setmetatable({}, weak) -- window -> its name, once hooked
local original = setmetatable({}, weak) -- window -> Blizzard's anchors before we first moved it
local wasMovable = setmetatable({}, weak) -- window -> whether it was movable before we made it so
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
    return not (InCombatLockdown() and frame:IsProtected())
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
