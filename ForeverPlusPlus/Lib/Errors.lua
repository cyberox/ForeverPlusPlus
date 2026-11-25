-- What Error Catcher shares while it's on, so another module (the minimap button) can show its
-- counts and open its window without reaching into it. Error Catcher provides; others read and
-- listen. Nothing is provided while Error Catcher is off.
local _, ns = ...

local ipairs = ipairs

local call = ns.Call -- so one listener's error doesn't stop the others

local Errors = {}
ns.Errors = Errors

local source -- { session, saved, toggle, clearSession, clearAll } functions while Error Catcher is on
local listeners = {}

---Tells the listeners that the counts changed, or that Error Catcher came or went.
function Errors.Changed()
    for _, fn in ipairs(listeners) do
        call(fn)
    end
end

---Error Catcher's side: its counts and window while it's on, or nil when it turns off.
---@param provider? { session: (fun(): number), saved: (fun(): number), toggle: fun(), clearSession: fun(), clearAll: fun(), report: (fun(message: string))? }
function Errors.Provide(provider)
    source = provider
    Errors.Changed()
end

---Whether Error Catcher is on to show errors.
---@return boolean
function Errors.IsOn()
    return source ~= nil
end

---How many different errors this session caught, or 0 with Error Catcher off.
---@return number
function Errors.SessionCount()
    return source and source.session() or 0
end

---How many errors are saved, from every session, or 0 with Error Catcher off.
---@return number
function Errors.SavedCount()
    return source and source.saved() or 0
end

---Opens or closes Error Catcher's window, if it's on.
function Errors.Toggle()
    if source then
        source.toggle()
    end
end

---Forgets this session's errors, keeping earlier sessions', if Error Catcher is on.
function Errors.ClearSession()
    if source then
        source.clearSession()
    end
end

---Forgets every saved error, from every session, if Error Catcher is on. Asks first, as Error
---Catcher's own Clear button does.
function Errors.ClearAll()
    if source then
        source.clearAll()
    end
end

---Adds an entry to Error Catcher's list that isn't a Lua error: a value of Blizzard's an addon
---wrote, from Taint Watcher. Error Catcher adds what was going on.
---@param message string
---@return boolean kept false with Error Catcher off
function Errors.Report(message)
    if source and source.report then
        source.report(message)
        return true
    end
    return false
end

---Calls `fn()` whenever the counts change or Error Catcher turns on or off. Add it once.
---@param fn fun()
function Errors.OnChanged(fn)
    listeners[#listeners + 1] = fn
end
