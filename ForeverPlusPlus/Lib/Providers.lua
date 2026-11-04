-- What a module offers outside itself while it's on, by name, for the public API (API.lua) to
-- read: a table of functions the module sets in OnEnable and takes away in OnDisable, as Auction
-- Prices gives Lib/Prices.lua its source. So nothing outside a module reaches into it, and
-- nothing is offered while it's off. A module also says when what it offers changed, and
-- listeners (the API's callbacks) hear it.
local _, ns = ...

local ipairs = ipairs

local Providers = {}
ns.Providers = Providers

local offered = {} -- name -> table of functions
local listeners = {} -- name -> list of fn()

---Offers `impl` under `name`, or takes it away with nil. Changing it tells the listeners.
---@param name string
---@param impl table|nil
function Providers.Set(name, impl)
    if offered[name] == impl then
        return
    end
    offered[name] = impl
    Providers.Changed(name)
end

---What's offered under `name`, or nil while its module is off.
---@param name string
---@return table|nil
function Providers.Get(name)
    return offered[name]
end

---Calls `fn()` whenever what's under `name` changes. Called as often as the module says, so a
---listener that does real work should coalesce.
---@param name string
---@param fn function
function Providers.OnChanged(name, fn)
    listeners[name] = listeners[name] or {}
    local list = listeners[name]
    list[#list + 1] = fn
end

---Tells the listeners what's under `name` changed (from the module that offers it).
---@param name string
function Providers.Changed(name)
    for _, fn in ipairs(listeners[name] or {}) do
        ns.Call(fn)
    end
end
