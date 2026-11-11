-- Profiles: sets of settings the player can switch between. A profile holds which modules are on,
-- their settings (Edit Mode places included, which are plain settings), and the data a module
-- marks as the profile's (`module.perProfile`). Everything else a module collects, and what is kept
-- per character, stays where it is.
--
-- Profiles belong to the account; which one a character uses is saved for that character
-- (ForeverPlusPlusCharDB.profile), and the account remembers every character seen, with the profile
-- it uses, for the Profiles page and for setting another character's profile, which that character
-- takes at its next login. Everyone starts with Default, the account's own settings (see
-- Lib/Store.lua), so nothing changes until a second profile exists. Default can't be renamed or
-- deleted; deleting another sends its characters back to Default.
--
-- Switching is live: Core turns the modules off, Store reads the other profile, and Core turns on
-- what that one has on (ns.ChangeProfile). In combat it waits for combat to end.
local _, ns = ...

local pairs, ipairs, type, next, tostring, sort = pairs, ipairs, type, next, tostring, table.sort
local format, gsub, lower, sub = string.format, string.gsub, string.lower, string.sub

local Store = ns.Store
local L = ns.L

local Profiles = {}
ns.Profiles = Profiles

---Default's id, as the Profiles page and the public API name it. Store keeps Default as nil.
Profiles.DEFAULT = "default"
Profiles.MAX_NAME = 32 -- characters in a profile's name

local listeners = {} -- fn(switched) after anything about the profiles changes
local me -- this character's key in db.characters (its GUID), once logged in

local function db()
    return ns.db
end

local function child(t, key)
    local value = t[key]
    if type(value) ~= "table" then
        value = {}
        t[key] = value
    end
    return value
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy(v)
    end
    return out
end
Profiles.Copy = copy

-- Store's id for a profile: nil for Default.
local function storeID(id)
    if id == Profiles.DEFAULT then
        return nil
    end
    return id
end

local function publicID(id)
    return id or Profiles.DEFAULT
end

local function changed(switched)
    for _, fn in ipairs(listeners) do
        ns.Call(fn, switched and true or false)
    end
end

---Calls `fn(switched)` after anything about the profiles changes: one made, renamed, or deleted, a
---character moved, or (`switched` true) this character switching to another.
---@param fn fun(switched: boolean)
function Profiles.OnChanged(fn)
    listeners[#listeners + 1] = fn
end

---Whether a profile is there. Default always is.
---@param id string?
---@return boolean
function Profiles.Exists(id)
    if id == Profiles.DEFAULT then
        return true
    end
    local profiles = db() and db().profiles
    return id ~= nil and type(profiles) == "table" and type(profiles[id]) == "table"
end

---The profile this character uses.
---@return string id
function Profiles.Current()
    return publicID(Store.profile)
end

---A profile's name, or nil when it isn't there.
---@param id string
---@return string?
function Profiles.Name(id)
    if id == Profiles.DEFAULT then
        return L.PROFILES_DEFAULT
    end
    local profile = Profiles.Exists(id) and db().profiles[id]
    return profile and tostring(profile.name or id) or nil
end

---Every profile's id: Default first, then the rest by name.
---@return string[]
function Profiles.List()
    local ids = {}
    for id, profile in pairs(db() and db().profiles or {}) do
        if type(profile) == "table" then
            ids[#ids + 1] = id
        end
    end
    sort(ids, function(a, b)
        local na, nb = lower(Profiles.Name(a)), lower(Profiles.Name(b))
        if na ~= nb then
            return na < nb
        end
        return a < b
    end)
    table.insert(ids, 1, Profiles.DEFAULT)
    return ids
end

---How many profiles there are, Default included.
---@return integer
function Profiles.Count()
    return #Profiles.List()
end

---A name as a profile may have it: no color codes, textures, links or other escapes, no control
---characters, no % (popups format their text, and a name goes into it), trimmed, and at most
---MAX_NAME characters. "" when nothing is left.
---@param text any
---@return string
function Profiles.CleanName(text)
    if type(text) ~= "string" then
        return ""
    end
    text = ns.Text.Plain(text)
    text = gsub(text, "[|%%]", "")
    text = gsub(text, "[%c]", "")
    text = gsub(gsub(text, "^%s+", ""), "%s+$", "")
    text = gsub(text, "%s+", " ")
    if #text > Profiles.MAX_NAME then
        text = gsub(sub(text, 1, Profiles.MAX_NAME), "%s+$", "")
    end
    return text
end

---The profile with this name, ignoring case, if any. Default's name is Default's.
---@param name string
---@return string? id
function Profiles.Find(name)
    name = lower(Profiles.CleanName(name))
    for _, id in ipairs(Profiles.List()) do
        if lower(Profiles.Name(id)) == name then
            return id
        end
    end
end

-- Checks a name for a new or renamed profile: the cleaned name, or nil and why not.
local function checkName(name, except)
    name = Profiles.CleanName(name)
    if name == "" then
        return nil, L.PROFILES_NAME_EMPTY
    end
    local taken = Profiles.Find(name)
    if taken and taken ~= except then
        return nil, format(L.PROFILES_NAME_TAKEN, name)
    end
    return name
end
Profiles.CheckName = checkName

---A name no profile has yet: `name` cleaned, or with " 2", " 3" after it when that's taken.
---@param name string
---@return string
function Profiles.FreeName(name)
    local clean = Profiles.CleanName(name)
    if clean == "" then
        clean = L.PROFILES_IMPORTED
    end
    local try, n = clean, 1
    while Profiles.Find(try) do
        n = n + 1
        local suffix = " " .. n
        try = gsub(sub(clean, 1, Profiles.MAX_NAME - #suffix), "%s+$", "") .. suffix
    end
    return try
end

-- What a profile holds, as plain tables: its settings, and its profile data by module and key.
-- Default's profile data is in the account's data, beside the account's own.
local function contents(id)
    local root = Store.Root(db(), storeID(id))
    local settings = copy(type(root.settings) == "table" and root.settings or {})
    local data = {}
    for name, module in pairs(ns.modules or {}) do
        for key in pairs(module.perProfile or {}) do
            local byKey = type(root.data) == "table" and root.data[name]
            local value = type(byKey) == "table" and byKey[key]
            if type(value) == "table" and next(value) ~= nil then
                child(data, name)[key] = copy(value)
            end
        end
    end
    return settings, data
end
Profiles.Contents = contents

-- Puts `settings` and `data` into a profile, in place of what it had.
local function fill(id, settings, data)
    local root = Store.Root(db(), storeID(id))
    root.settings = copy(settings or {})
    if root == db() then
        -- Default: only the profile data in the account's table changes.
        for name, module in pairs(ns.modules or {}) do
            for key in pairs(module.perProfile or {}) do
                local byKey = type(root.data) == "table" and root.data[name]
                if type(byKey) == "table" then
                    byKey[key] = nil
                end
                local value = data and data[name] and data[name][key]
                if type(value) == "table" then
                    child(child(root, "data"), name)[key] = copy(value)
                end
            end
        end
    else
        root.data = copy(data or {})
    end
end

---Makes a profile, with nothing changed from the defaults or as a copy of `from`, and returns its
---id, or nil and why not (the name is empty or taken). This character stays on its profile.
---@param name string
---@param from? string a profile to copy
---@return string? id
---@return string? reason
function Profiles.Create(name, from)
    local clean, reason = checkName(name)
    if not clean then
        return nil, reason
    end
    local saved = db()
    local profiles = child(saved, "profiles")
    local serial = (type(saved.profileSerial) == "number" and saved.profileSerial or 0) + 1
    while profiles["p" .. serial] do
        serial = serial + 1
    end
    saved.profileSerial = serial
    local id = "p" .. serial
    profiles[id] = { name = clean }
    if from and Profiles.Exists(from) then
        fill(id, contents(from))
    end
    changed(false)
    return id
end

---Renames a profile other than Default. Returns true, or nil and why not.
---@param id string
---@param name string
---@return boolean?
---@return string? reason
function Profiles.Rename(id, name)
    if id == Profiles.DEFAULT or not Profiles.Exists(id) then
        return nil, L.PROFILES_DEFAULT_ALWAYS
    end
    local clean, reason = checkName(name, id)
    if not clean then
        return nil, reason
    end
    db().profiles[id].name = clean
    changed(false)
    return true
end

-- Characters ------------------------------------------------------------------------------------

-- The account's record of each character seen: GUID -> { name, realm, class, level, profile,
-- moved }. `profile` is nil for Default; `moved` says another character changed it, for this one to
-- take at its next login.
local function characters()
    return child(db(), "characters")
end

---Every character seen, by name: { key, name, realm, class, level, profile, current }.
---@return table[]
function Profiles.Characters()
    local list = {}
    for key, record in pairs(characters()) do
        if type(record) == "table" then
            local profile = record.profile
            if not Profiles.Exists(profile) then
                profile = nil
            end
            list[#list + 1] = {
                key = key, name = tostring(record.name or "?"), realm = record.realm,
                class = record.class, level = record.level,
                profile = publicID(profile), current = key == me,
            }
        end
    end
    sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return tostring(a.realm) < tostring(b.realm)
    end)
    return list
end

---The characters that use a profile.
---@param id string
---@return table[] as Profiles.Characters gives them
function Profiles.Users(id)
    local users = {}
    for _, character in ipairs(Profiles.Characters()) do
        if character.profile == id then
            users[#users + 1] = character
        end
    end
    return users
end

---This character's entry, as Profiles.Characters gives it, or nil before login.
---@return table?
function Profiles.Me()
    for _, character in ipairs(Profiles.Characters()) do
        if character.current then
            return character
        end
    end
end

-- Remembers this character's name, class and level for the list.
local function record()
    if not me then
        return
    end
    local entry = child(characters(), me)
    local name = UnitName and UnitName("player")
    entry.name = ns.IsText and ns.IsText(name) and name or entry.name
    local realm = GetRealmName and GetRealmName()
    entry.realm = ns.IsText and ns.IsText(realm) and realm or entry.realm
    if UnitClass then
        local _, class = UnitClass("player")
        entry.class = ns.IsText and ns.IsText(class) and class or entry.class
    end
    local level = UnitLevel and UnitLevel("player")
    entry.level = type(level) == "number" and level or entry.level
    entry.profile = Store.profile
    entry.moved = nil
end

---At login, before any module reads its settings: picks this character's profile (one another
---character set for it, or New Characters Use for a character new to the addon, or what it used
---last) and remembers the character. `fresh` is true when the character had no saved variables.
---@param fresh boolean
function Profiles.Login(fresh)
    local saved, char = db(), ns.charDB
    me = UnitGUID and UnitGUID("player")
    if type(me) ~= "string" then
        me = nil
    end
    local entry = me and characters()[me]
    if type(entry) == "table" and entry.moved then
        char.profile = entry.profile
    elseif fresh and type(entry) ~= "table" then
        char.profile = storeID(saved.newCharacters)
    end
    if not Profiles.Exists(char.profile) then
        char.profile = nil
    end
    if not Profiles.Exists(saved.newCharacters) or saved.newCharacters == Profiles.DEFAULT then
        saved.newCharacters = nil
    end
    Store.profile = char.profile
    record()
    if ns.On then
        ns.On("PLAYER_LOGOUT", record) -- the level it leaves at, for the list
    end
end

---Forgets a character other than this one: it leaves the list until it logs in again, when it
---comes back on the profile its own saved variables name.
---@param key string
function Profiles.Forget(key)
    if key == me then
        return
    end
    characters()[key] = nil
    changed(false)
end

---The profile a character new to the addon starts on.
---@return string id
function Profiles.NewCharacters()
    local id = db().newCharacters
    return Profiles.Exists(id) and id or Profiles.DEFAULT
end

---@param id string
function Profiles.SetNewCharacters(id)
    if Profiles.Exists(id) then
        db().newCharacters = storeID(id)
        changed(false)
    end
end

-- Switching -------------------------------------------------------------------------------------

---Switches this character to a profile, live, or once combat ends. Returns true when it switched
---now, false when it waits for combat to end, nil when the profile isn't there.
---@param id string
---@return boolean?
function Profiles.Switch(id)
    if not Profiles.Exists(id) then
        return nil
    end
    local now = not (InCombatLockdown and InCombatLockdown())
    ns.AfterCombat(function()
        if not Profiles.Exists(id) then
            return -- deleted while waiting
        end
        if publicID(Store.profile) ~= id then
            ns.ChangeProfile(function()
                Store.profile = storeID(id)
                ns.charDB.profile = Store.profile
                record()
            end)
        end
        changed(true)
    end)
    return now
end

---Sets which profile a character uses: this one switches (see Profiles.Switch), another takes it
---at its next login.
---@param key string
---@param id string
---@return boolean? as Profiles.Switch, or true for another character
function Profiles.SetCharacter(key, id)
    if not Profiles.Exists(id) then
        return nil
    end
    if key == me then
        return Profiles.Switch(id)
    end
    local entry = characters()[key]
    if type(entry) ~= "table" then
        return nil
    end
    entry.profile, entry.moved = storeID(id), true
    changed(false)
    return true
end

---Deletes a profile other than Default. Its characters go back to Default: this one at once (or
---after combat), the others at their next login. Returns true, false while it waits for combat,
---or nil for Default or a profile that isn't there.
---@param id string
---@return boolean?
function Profiles.Delete(id)
    if id == Profiles.DEFAULT or not Profiles.Exists(id) then
        return nil
    end
    local function drop()
        if not Profiles.Exists(id) then
            return
        end
        for key, entry in pairs(characters()) do
            if type(entry) == "table" and entry.profile == id and key ~= me then
                entry.profile, entry.moved = nil, true
            end
        end
        if db().newCharacters == id then
            db().newCharacters = nil
        end
        db().profiles[id] = nil
        if next(db().profiles) == nil then
            db().profiles = nil
        end
        changed(false)
    end
    if Profiles.Current() ~= id then
        drop()
        return true
    end
    local now = Profiles.Switch(Profiles.DEFAULT)
    ns.AfterCombat(drop) -- after the switch, which waits for combat too
    return now
end

---Puts new contents into a profile, in place of what it had (an import's Replace). The profile in
---use changes live, as a switch does.
---@param id string
---@param settings table
---@param data table
---@return boolean?
function Profiles.Replace(id, settings, data)
    if not Profiles.Exists(id) then
        return nil
    end
    local now = not (InCombatLockdown and InCombatLockdown())
    ns.AfterCombat(function()
        if not Profiles.Exists(id) then
            return
        end
        if Profiles.Current() == id then
            ns.ChangeProfile(function()
                fill(id, settings, data)
            end)
        else
            fill(id, settings, data)
        end
        changed(Profiles.Current() == id)
    end)
    return now
end

---Makes a profile from contents (an import's Import as New). Returns its id, or nil and why not.
---@param name string
---@param settings table
---@param data table
---@return string? id
---@return string? reason
function Profiles.CreateFrom(name, settings, data)
    local clean, reason = checkName(name)
    if not clean then
        return nil, reason
    end
    local id = Profiles.Create(clean)
    fill(id, settings, data)
    changed(false)
    return id
end

-- A preset (as ns.ApplyPreset takes it) as the settings it leaves: the modules in `enable` on and
-- the option values in `options`, with only what differs from a module's defaults saved, as
-- ns.ApplyPreset forgets a value at its default. Modules that are always on or unavailable, and
-- options that are Blizzard's settings (`cvar`), are left out, as there.
local function presetSettings(enable, options)
    local settings = {}
    local wanted = {}
    for _, name in ipairs(enable or {}) do
        wanted[name] = true
    end
    for name, module in pairs(ns.modules or {}) do
        if not (module.alwaysOn or module.unavailable) then
            local defaults = module.defaults or {}
            if wanted[name] and not defaults.enabled then
                child(settings, name).enabled = true
            end
            local overrides = options and options[name]
            for _, option in ipairs(overrides and module.options or {}) do
                local value = overrides[option.key]
                if value ~= nil and type(value) ~= "table" and not option.cvar
                    and value ~= defaults[option.key] then
                    child(settings, name)[option.key] = value
                end
            end
        end
    end
    return settings
end
Profiles.PresetSettings = presetSettings

---Makes a profile from a preset, such as Developer's Defaults (ns.DeveloperPreset), written into
---its own settings: the profile in use isn't touched and nothing is applied live. Returns its id,
---or nil and why not.
---@param name string
---@param enable? string[] module names to turn on whatever their default is
---@param options? table<string, table<string, any>> per module, option values used instead of its defaults
---@return string? id
---@return string? reason
function Profiles.CreateFromPreset(name, enable, options)
    return Profiles.CreateFrom(name, presetSettings(enable, options), {})
end

-- What a profile holds, counted: the modules it has on and the settings it changed from their
-- defaults, by the modules' own defaults.
local function count(settings)
    local on, changedCount = 0, 0
    for name, module in pairs(ns.modules or {}) do
        if not (module.alwaysOn or module.unavailable) then
            local own = type(settings[name]) == "table" and settings[name] or {}
            local enabled = own.enabled
            if enabled == nil then
                enabled = module.defaults.enabled
            end
            if enabled and not module.locked then
                on = on + 1
            end
            for key, value in pairs(own) do
                if key ~= "enabled" and module.defaults[key] ~= nil and value ~= module.defaults[key] then
                    changedCount = changedCount + 1
                end
            end
        end
    end
    return on, changedCount
end
Profiles.CountSettings = count

---How many modules a profile has on, and how many settings it changed from their defaults.
---@param id string
---@return integer modules
---@return integer settings
function Profiles.Summary(id)
    return count((contents(id)))
end

---"1 character", "3 characters".
---@param n integer
---@return string
function Profiles.UsersText(n)
    return n == 1 and L.PROFILES_ONE_CHARACTER or format(L.PROFILES_CHARACTERS, n)
end

---Switches with a line in chat saying so, or that it waits for combat to end.
---@param id string
function Profiles.SwitchAndSay(id)
    local now = Profiles.Switch(id)
    if now ~= nil then
        ns.Print(format(now and L.PROFILES_SWITCHED or L.PROFILES_AFTER_COMBAT, Profiles.Name(id)))
    end
end

-- /fpp profiles lists them; /fpp profiles <name> switches this character to one. /fpp profile
-- does the same, so a missing "s" doesn't matter.
local function command(rest)
    rest = gsub(gsub(rest or "", "^%s+", ""), "%s+$", "")
    if rest ~= "" then
        local id = Profiles.Find(rest)
        if id then
            Profiles.SwitchAndSay(id)
        else
            ns.Print(format(L.PROFILES_NO_SUCH, Profiles.CleanName(rest)))
        end
        return
    end
    ns.Print(L.PROFILES_HEADER)
    local current = Profiles.Current()
    for _, id in ipairs(Profiles.List()) do
        ns.PrintLine(format("  %s%s  |cff999999%s|r", id == current and "|cff44dd44>|r " or "  ",
            Profiles.Name(id), Profiles.UsersText(#Profiles.Users(id))))
    end
end
ns.AddCommand("profiles", "[name]", L.SLASH_PROFILE, command)
ns.AddCommand("profile", "[name]", L.SLASH_PROFILE, command)
