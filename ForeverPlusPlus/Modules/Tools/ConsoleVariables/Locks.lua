-- Console Variables' locks: a CVar the player locks on the page keeps its value. The game starts
-- some CVars at their default every session (nameplateSimplifiedScale, which it doesn't seem to
-- save; see docs/forever-api.md), and the game's own Settings or other addons change others. A
-- locked one is put back when the module turns on (at login), after every loading screen, and
-- whenever CVAR_UPDATE says a CVar changed, through ns.CVars.Hold, after combat.
--
-- The locks are the module's data (`locks`, for the account): lowercase name -> { name, value }.
-- This is all the module does while its page is closed: a GetCVar per lock at each loading screen,
-- and CVAR_UPDATE heard only while something is locked. Nothing here builds the page.
local _, ns = ...

local pairs, next, format, tostring = pairs, next, string.format, tostring
local strlower, GetTime = string.lower, GetTime
local L = ns.L
local module = ns.modules.ConsoleVariables
local internal = module.internal

-- A lock put back this many times within FIGHT_SECONDS is fighting something that keeps setting
-- it (another addon, or one of our modules setting the same CVar). It stops until the next login
-- or reload rather than trade values with it on every change.
local FIGHT_LIMIT, FIGHT_SECONDS = 5, 10

local stuck = {} -- lowercase name -> true: given up on until the next login or reload
local pending = {} -- lowercase name -> true: a put-back is waiting (for combat, or the page's change)
local fights = {} -- lowercase name -> { since, count }: put-backs after something changed it

local function locks()
    return module.db.locks
end

---Whether the CVar (by lowercase name) is locked.
---@param key string
---@return boolean
function internal.IsLocked(key)
    return locks()[key] ~= nil
end

---The value a locked CVar is kept at, or nil.
---@param key string
---@return string|nil
function internal.LockedValue(key)
    local lock = locks()[key]
    return lock and lock.value
end

---Whether a lock has stopped until the next login or reload (the game wouldn't hold its value, or
---something kept changing it).
---@param key string
---@return boolean
function internal.IsStuck(key)
    return stuck[key] == true
end

local onCVarUpdate

-- CVAR_UPDATE only while the module is on and something is locked.
local function listen()
    if not ns.HasEvent("CVAR_UPDATE") then
        return
    end
    if module.enabled and next(locks()) then
        module:On("CVAR_UPDATE", onCVarUpdate)
    else
        module:Off("CVAR_UPDATE", onCVarUpdate)
    end
end

local function giveUp(key, message)
    stuck[key] = true
    module:Print(message)
end

-- Counts a put-back made after something changed the CVar, and gives up on a fight.
local function countFight(key, lock)
    local now = GetTime()
    local fight = fights[key]
    if not fight or now - fight.since > FIGHT_SECONDS then
        fight = { since = now, count = 0 }
        fights[key] = fight
    end
    fight.count = fight.count + 1
    if fight.count >= FIGHT_LIMIT then
        giveUp(key, format(L.CONSOLEVARIABLES_LOCK_FIGHT, lock.name))
    end
end

-- Puts one lock's value back if the CVar has another, once combat is over. `changed`: CVAR_UPDATE
-- said something changed, so a put-back counts toward a fight.
local function hold(key, changed)
    local lock = locks()[key]
    if not lock or stuck[key] or pending[key] then
        return
    end
    pending[key] = true
    -- Our own wait for combat, so a module turned off meanwhile sets nothing after it.
    ns.AfterCombat(function()
        if not module.enabled or locks()[key] ~= lock then
            pending[key] = nil
            return
        end
        -- Setting it fires CVAR_UPDATE at once; `pending` keeps that from starting another.
        ns.CVars.Hold(lock.name, lock.value, function(result, now)
            pending[key] = nil
            if locks()[key] ~= lock then
                return -- unlocked or changed on the page meanwhile
            end
            if result == "missing" then
                -- A patch dropped or renamed it, so there's nothing left to keep.
                locks()[key] = nil
                listen()
            elseif result == "refused" or result == "kept" then
                -- The game won't take it any more (read-only now, a smaller range): say so once
                -- instead of trying on every change.
                giveUp(key, format(L.CONSOLEVARIABLES_LOCK_FAILED, lock.name, lock.value, tostring(now)))
            elseif result == "set" and changed then
                countFight(key, lock)
            end
        end)
    end)
end

local function holdAll(changed)
    for key in pairs(locks()) do
        hold(key, changed)
    end
end

-- Checks every lock rather than only the CVar named: a few GetCVar calls, and nothing depends on
-- how this client spells the name it passes. Only a value that really changed is set.
onCVarUpdate = function()
    holdAll(true)
end

local function onEnteringWorld()
    holdAll(false)
end

---Locks a CVar at `value`, or moves its lock there: the player locked it, or changed it on the page
---(the lock follows what the game then holds). Clears a lock that had stopped.
---@param name string
---@param value string
function internal.Lock(name, value)
    local key = strlower(name)
    locks()[key] = { name = name, value = value }
    stuck[key], pending[key], fights[key] = nil, nil, nil
    listen()
end

---Unlocks a CVar, leaving its value as it is.
---@param key string
function internal.Unlock(key)
    locks()[key] = nil
    stuck[key], pending[key], fights[key] = nil, nil, nil
    listen()
end

---Holds a locked CVar's lock still while the page changes it, so the change isn't put back before
---the page moves the lock to it (internal.Lock).
---@param key string
function internal.PauseLock(key)
    if locks()[key] then
        pending[key] = true
    end
end

function module:OnEnable()
    -- Turning it back on is a fresh start for locks that had stopped.
    stuck, fights = {}, {}
    self:On("PLAYER_ENTERING_WORLD", onEnteringWorld)
    listen()
    holdAll(false)
end
