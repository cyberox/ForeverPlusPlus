-- The modifier key a module lets the player hold to skip what it does (Auto Quest, Auto Gossip,
-- Auto Repair, Auto Sell Junk, Auto Release), to let something through (Skip Cinematics), to
-- pick another action (Minimap Button, World Map's Zone Info), or to drag (Movable Windows), so
-- each offers the same choices under the same names.
local _, ns = ...

local type = type
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown
local L = ns.L

local Keys = {}
ns.Keys = Keys

-- Key, then name, as a dropdown's `choices` take them.
Keys.CHOICES = {
    { "shift", L.KEY_SHIFT },
    { "ctrl", L.KEY_CTRL },
    { "alt", L.KEY_ALT },
    { "none", L.KEY_NONE },
}

local DOWN = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

---Whether `key` (a key of `Keys.CHOICES`) is held down. Never for "none".
---@param key string
---@return boolean
function Keys.IsDown(key)
    local down = DOWN[key]
    return down ~= nil and down() and true or false
end

---A dropdown option for the key setting `key` (such as "skipKey"); its default, such as "shift",
---goes in the module's defaults.
---@param key string the setting
---@param name string
---@param description string
---@param section? string
---@param changed? string the version it last changed in, for its NEW tag
---@return table option
function Keys.Option(key, name, description, section, changed)
    return { key = key, name = name, description = description, choices = Keys.CHOICES,
        section = section, changed = changed }
end

---Moves an old "hold Shift" checkbox setting of `saved[module]` to a key setting: Shift while it
---was on, None while it was off. For ns.Migrate.
---@param saved table every module's saved settings
---@param module string
---@param old string the checkbox's setting
---@param new string the key's setting
function Keys.MigrateShift(saved, module, old, new)
    local db = saved[module]
    if not (db and type(db[old]) == "boolean") then
        return
    end
    db[new] = db[old] and "shift" or "none"
    db[old] = nil
end
