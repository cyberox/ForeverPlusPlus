-- Load-on-demand Blizzard addons: whether one has loaded, and code to run once it has. Nothing is
-- listened to until something waits. And which addons this character has on, as a set by name
-- that can be put back later (States, Changes, Apply).
local addonName, ns = ...

local _G, pairs, next, sort, C_AddOns = _G, pairs, next, table.sort, C_AddOns

local call = ns.Call -- so one waiter's error doesn't stop the others

local AddOns = {}
ns.AddOns = AddOns

---Whether an addon has loaded. Probe: without C_AddOns, everything counts as loaded.
---@param name string
---@return boolean
function AddOns.IsLoaded(name)
    return not C_AddOns or (C_AddOns.IsAddOnLoaded(name) and true or false)
end

local waiting = {} -- addon name -> { fn = true }

local function onLoaded(_, name)
    local fns = waiting[name]
    if not fns then
        return
    end
    waiting[name] = nil
    if not next(waiting) then
        ns.Off("ADDON_LOADED", onLoaded)
    end
    for fn in pairs(fns) do
        call(fn, name)
    end
end

---Calls `fn(name)` now if the addon has loaded, or else once it does. Waiting with the same `fn`
---again doesn't call it twice; `AddOns.Cancel` stops the wait, for a module turned off first.
---@param name string
---@param fn fun(name: string)
function AddOns.WhenLoaded(name, fn)
    if AddOns.IsLoaded(name) then
        fn(name)
        return
    end
    if not next(waiting) then
        ns.On("ADDON_LOADED", onLoaded)
    end
    waiting[name] = waiting[name] or {}
    waiting[name][fn] = true
end

---Stops waiting to call `fn` when the addon loads.
---@param name string
---@param fn function
function AddOns.Cancel(name, fn)
    local fns = waiting[name]
    if not (fns and fns[fn]) then
        return
    end
    fns[fn] = nil
    if not next(fns) then
        waiting[name] = nil
    end
    if not next(waiting) then
        ns.Off("ADDON_LOADED", onLoaded)
    end
end

-- Sets of addons ---------------------------------------------------------------------------------
-- By addon name, since an addon's index changes when addons are added or removed, and for this
-- character only, as Blizzard's AddOns list sets them (docs/forever-api.md).

---Which of the installed addons this character has on: { [addon name] = true or false }.
---@return table<string, boolean>
function AddOns.States()
    local states = {}
    local C, guid = _G.C_AddOns, _G.UnitGUID and _G.UnitGUID("player")
    if not (C and C.GetNumAddOns and C.GetAddOnInfo and C.GetAddOnEnableState and guid) then
        return states
    end
    local none = _G.Enum and _G.Enum.AddOnEnableState and _G.Enum.AddOnEnableState.None or 0
    for index = 1, C.GetNumAddOns() do
        local name = C.GetAddOnInfo(index)
        if name then
            states[name] = C.GetAddOnEnableState(index, guid) > none
        end
    end
    return states
end

---What a set saved from AddOns.States would change now: the addons to turn on and the ones to
---turn off, each by name in order. An addon the set doesn't name (installed since) or that isn't
---installed any more is left alone, and Forever++ is never turned off.
---@param wanted table<string, boolean>
---@return string[] on
---@return string[] off
function AddOns.Changes(wanted)
    local on, off = {}, {}
    for name, now in pairs(AddOns.States()) do
        local want = wanted[name]
        if want == true and not now then
            on[#on + 1] = name
        elseif want == false and now and name ~= addonName then
            off[#off + 1] = name
        end
    end
    sort(on)
    sort(off)
    return on, off
end

---Turns this character's addons on and off as a set says (see AddOns.Changes) and saves that, as
---the AddOns list's Okay does. Nothing loads or unloads until the interface reloads.
---@param wanted table<string, boolean>
function AddOns.Apply(wanted)
    local C, guid = _G.C_AddOns, _G.UnitGUID and _G.UnitGUID("player")
    if not (C and C.EnableAddOn and C.DisableAddOn and guid) then
        return
    end
    local on, off = AddOns.Changes(wanted)
    for _, name in ipairs(on) do
        C.EnableAddOn(name, guid)
    end
    for _, name in ipairs(off) do
        C.DisableAddOn(name, guid)
    end
    if C.SaveAddOns then
        C.SaveAddOns()
    end
end
