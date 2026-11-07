-- Macros: macros Forever++ writes and keeps up to date, one part each (SmartBuff.lua for now). A
-- part's macro is a general macro shared by your characters: made when its checkbox turns on, and
-- deleted for all of them when it turns off. Each character rewrites it for its own class when it
-- logs in or anything changes. The game doesn't let addons make or change macros in combat, so a change waits until
-- combat ends, and a mark of ours over each action button holding the macro says when it has
-- nothing to cast (a red X) or is out of date until combat ends (a warning triangle).
local _, ns = ...

local ipairs, pcall, format = ipairs, pcall, string.format
local InCombatLockdown = InCombatLockdown
local CreateMacro, EditMacro, DeleteMacro = CreateMacro, EditMacro, DeleteMacro
local GetMacroIndexByName, GetMacroBody, PickupMacro = GetMacroIndexByName, GetMacroBody, PickupMacro

local L = ns.L
local Frames, ActionButtons = ns.Frames, ns.ActionButtons

local module = ns.NewModule("Macros", L.MACROS_DESC, {
    enabled = false,
})
module.title = L.MACROS_TITLE
module.category = "character"
module.added = "1.0.0-beta.1"
module.options = {} -- each part adds its section
-- The game's rule, not ours, so say it where the player turns macros on; a notice with no button,
-- always shown.
module.notice = {
    text = L.MACROS_NOTICE,
    description = L.MACROS_NOTICE_DESC,
}
module.internal = {}
local internal = module.internal

local ICON = 134400 -- the question mark; #showtooltip shows the spell the macro casts instead
local MARK_SIZE = 18
local NONE_ATLAS, NONE_FILE = "common-icon-redx", "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local STALE_ATLAS, STALE_FILE = "services-icon-warning", "Interface\\DialogFrame\\DialogAlertIcon"

-- Character macros may not be loaded before the player is in the world (or the game says they
-- changed), and a macro looked up too early would be made twice.
local inWorld = false
local wanted = {} -- macro name -> true while its part is on
local states = {} -- macro name -> "none" or "stale" while its buttons are marked
local saidFailed = false

local function setIcon(texture, atlas, file)
    if Frames.HasAtlas(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetTexture(file)
    end
end

local marks = ActionButtons.Marks(function(frame)
    frame.none = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.none:SetSize(MARK_SIZE, MARK_SIZE)
    frame.none:SetPoint("CENTER")
    setIcon(frame.none, NONE_ATLAS, NONE_FILE)
    frame.stale = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.stale:SetSize(MARK_SIZE, MARK_SIZE)
    -- Inside the button's corner: past its edge, the next button over draws on top of it.
    frame.stale:SetPoint("TOPRIGHT", -1, -1)
    setIcon(frame.stale, STALE_ATLAS, STALE_FILE)
end)

local function drawMarks()
    if not module.enabled then
        return
    end
    ActionButtons.Each(function(button)
        -- By name: a macro's slot gives the spell it shows, not its index.
        local kind = ActionButtons.Content(button)
        local name = kind == "macro" and ActionButtons.MacroName(button)
        local state = name and states[name] or nil
        local frame = state and marks.Get(button) or marks.Find(button)
        if frame then
            frame:SetShown(state ~= nil)
            frame.none:SetShown(state == "none")
            frame.stale:SetShown(state == "stale")
        end
    end)
end

local queueMarks = Frames.Coalesce(drawMarks, 0.1, module)

---Whether macros can be made and changed now: the player is in the world and out of combat.
---@return boolean
function internal.Ready()
    return inWorld and not InCombatLockdown()
end

---Makes the general macro `name` with `body`, or changes it when it holds something else. Only
---while `internal.Ready()`; returns whether the macro holds `body` now.
---@param name string
---@param body string
---@return boolean
function internal.Write(name, body)
    if not internal.Ready() then
        return false
    end
    wanted[name] = true
    local index = GetMacroIndexByName(name)
    if not index or index == 0 then
        local ok, made = pcall(CreateMacro, name, ICON, body)
        if not (ok and made) then
            -- Said once on screen, like the game's own errors, with the game's reason when it gave one.
            if not saidFailed then
                saidFailed = true
                local reason = not ok and ns.IsText(made, true) and made or L.MACROS_FULL_REASON
                Frames.ErrorMessage(format(L.MACROS_FAILED, name, reason))
            end
            return false
        end
        saidFailed = false
        queueMarks()
        return true
    end
    if GetMacroBody(index) ~= body then
        EditMacro(index, name, ICON, body)
    end
    return true
end

---Whether the general macro `name` holds `body` now.
---@param name string
---@param body string
---@return boolean
function internal.Holds(name, body)
    local index = GetMacroIndexByName(name)
    return index ~= nil and index > 0 and GetMacroBody(index) == body
end

---Says the part writing macro `name` is on, as soon as it turns on: a delete still waiting for
---combat to end then leaves the macro alone, so its action bar slots keep it.
---@param name string
function internal.Want(name)
    wanted[name] = true
end

---Deletes the general macro `name`, now or once combat ends, unless its part is back on by then.
---@param name string
function internal.Delete(name)
    wanted[name] = nil
    states[name] = nil
    queueMarks()
    ns.AfterCombat(function()
        if wanted[name] then
            return
        end
        local index = GetMacroIndexByName(name)
        if index and index > 0 then
            DeleteMacro(index)
        end
    end)
end

---Marks the action buttons holding macro `name`: "none" when it has nothing to cast, "stale" when
---it's out of date until combat ends, nil for no mark.
---@param name string
---@param state? string
function internal.Mark(name, state)
    if states[name] ~= state then
        states[name] = state
        queueMarks()
    end
end

---Puts macro `name` on the cursor, to drop on an action bar. `make` writes it first when it isn't
---there yet (its part is on, but it couldn't be made before).
---@param name string
---@param make? function
function internal.Pickup(name, make)
    if InCombatLockdown() then
        Frames.ErrorMessage(L.MACROS_IN_COMBAT)
        return
    end
    local index = GetMacroIndexByName(name)
    if not (index and index > 0) and module.enabled and make then
        inWorld = true -- a click in Settings is long past login
        saidFailed = false
        make()
        index = GetMacroIndexByName(name)
    end
    if not (module.enabled and index and index > 0) then
        if not saidFailed then
            Frames.ErrorMessage(format(L.MACROS_MISSING, name))
        end
        return
    end
    PickupMacro(index)
end

-- Parts that are on, told when macros can first be made.
local function partsReady()
    for _, part in ipairs(module.parts or {}) do
        if part.enabled and part.OnReady then
            part:OnReady()
        end
    end
end

function module:OnLoad()
    local function entered()
        ns.Off("PLAYER_ENTERING_WORLD", entered)
        ns.Off("UPDATE_MACROS", entered)
        inWorld = true
        partsReady()
    end
    ns.On("PLAYER_ENTERING_WORLD", entered)
    ns.On("UPDATE_MACROS", entered)
end

function module:OnEnable()
    self:On("ACTIONBAR_SLOT_CHANGED", queueMarks)
    self:On("ACTIONBAR_PAGE_CHANGED", queueMarks)
    self:On("UPDATE_BONUS_ACTIONBAR", queueMarks)
    self:On("UPDATE_MACROS", queueMarks)
    self:On("PLAYER_REGEN_ENABLED", queueMarks) -- marks wanted in combat, on buttons without one yet
    queueMarks()
end

function module:OnDisable()
    marks.HideAll()
end
