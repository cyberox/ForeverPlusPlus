-- Changing game settings (CVars) from a module, and putting the player's own values back.
-- Each module keeps the originals in its own saved table (usually a field of module.db), so they
-- survive a reload and two modules don't lose each other's. Many CVars (nameplates among them)
-- can't change in combat, so changes made then wait for it to end, in order (ns.AfterCombat).
local _, ns = ...

local type, pairs, next, C_CVar = type, pairs, next, C_CVar

local CVars = {}
ns.CVars = CVars

-- The first of `names` this client knows. CVars get renamed between patches, so callers can list
-- the names a setting has had, newest first.
local function find(names)
    if type(names) == "string" then
        names = { names }
    end
    for i = 1, #names do
        if C_CVar.GetCVar(names[i]) ~= nil then
            return names[i]
        end
    end
end

---Whether a CVar is on ("1"), trying its names newest first. False when this client has none.
---@param names string|string[]
---@return boolean
function CVars.IsOn(names)
    local name = find(names)
    return name ~= nil and C_CVar.GetCVar(name) == "1"
end

---A module's settings `notice` for a Blizzard setting it needs: a gray row saying so while the
---module is on and the CVar is off, with a button that turns the CVar on. Never shown on a client
---without the CVar, where the button couldn't do anything.
---@param module table
---@param names string|string[] the CVar, or its names newest first
---@param text string the row's short gray label
---@param description string its tooltip: what doesn't work while the CVar is off
---@return table notice for `module.notice`
function CVars.OffNotice(module, names, text, description)
    return {
        text = text,
        description = description,
        button = ns.L.SETTINGS_TURN_ON,
        fn = function()
            local name = find(names)
            if name then
                CVars.Apply(name, "1")
            end
        end,
        shown = function()
            return module.db.enabled and find(names) ~= nil and not CVars.IsOn(names)
        end,
    }
end

---Sets a CVar, remembering the player's value in `saved` the first time.
---@param saved table the owner's saved originals (CVar -> value)
---@param names string|string[] the CVar, or its names newest first
---@param value string
function CVars.Set(saved, names, value)
    ns.AfterCombat(function()
        local name = find(names)
        if not name then
            return
        end
        local current = C_CVar.GetCVar(name)
        if current ~= value then
            if saved[name] == nil then
                saved[name] = current
            end
            C_CVar.SetCVar(name, value)
        end
    end)
end

---Sets a CVar to a value the player chose, so nothing is remembered to put back. `done(ok)` is
---called once it has been tried (after combat, if the player is in combat).
---@param name string
---@param value string
---@param done? fun(ok: boolean)
function CVars.Apply(name, value, done)
    ns.AfterCombat(function()
        local ok = false
        if C_CVar.GetCVar(name) ~= nil then
            -- SetCVar returns false when the client refuses; treat no answer as done.
            ok = C_CVar.SetCVar(name, value) ~= false
        end
        if done then
            done(ok)
        end
    end)
end

---Ties a module's checkbox options to the game settings behind them, keeping the player's own
---values in `module.db.saved` (a `saved = {}` default). `map` is { option = cvar, ... } (each
---cvar a name or a list of names, newest first). An option that's on sets its CVar to "1"; one
---that's off puts the player's value back.
---  local cvars = ns.CVars.Bind(module, { player = "worldMapShowPlayerCoords" })
---  OnEnable: cvars.ApplyAll()   OnDisable: cvars.Restore()   OnOptionChanged: cvars.Apply(key)
---@param module table
---@param map table<string, string|string[]>
---@return table bound Apply(key), ApplyAll(), Restore()
function CVars.Bind(module, map)
    CVars.Track(module)
    local bound = {}
    ---Applies one option, if it's one of the mapped ones.
    function bound.Apply(key)
        local names = map[key]
        if not names then
            return
        end
        if module.db[key] then
            CVars.Set(module.db.saved, names, "1")
        else
            CVars.Restore(module.db.saved, names)
        end
    end
    function bound.ApplyAll()
        for key in pairs(map) do
            bound.Apply(key)
        end
    end
    ---Puts every CVar the module changed back to the player's value.
    function bound.Restore()
        CVars.RestoreAll(module.db.saved)
    end
    return bound
end

---Puts one CVar back to the player's value, if `saved` changed it.
---@param saved table
---@param names string|string[]
function CVars.Restore(saved, names)
    ns.AfterCombat(function()
        local name = find(names)
        if name and saved[name] ~= nil then
            C_CVar.SetCVar(name, saved[name])
            saved[name] = nil
        end
    end)
end

---Puts back every CVar in `saved`.
---@param saved table
function CVars.RestoreAll(saved)
    ns.AfterCombat(function()
        for name, value in pairs(saved) do
            C_CVar.SetCVar(name, value)
            saved[name] = nil
        end
    end)
end

-- Putting values back after a /reload in combat ----------------------------------------------------
-- A module turned off in combat waits for combat to end to put the player's values back (RestoreAll
-- through ns.AfterCombat). A /reload before then forgets that, and the module, off at the next
-- login, never runs OnDisable again. So once the player is in the world, a tracked module that's off
-- but still holds saved values puts them back.

local tracked = {} -- modules (or parts) whose `db.saved` holds the player's CVar values

---Puts `module.db.saved` back at login whenever the module is off then, in case it was turned off
---in combat just before a /reload. Bind does this itself; call it for a module that uses Set and
---RestoreAll directly.
---@param module table a module or a part
function CVars.Track(module)
    tracked[#tracked + 1] = module
end

local function restoreLeftovers()
    ns.Off("PLAYER_ENTERING_WORLD", restoreLeftovers)
    for _, module in pairs(tracked) do
        local saved = module.db and module.db.saved
        if not module.enabled and type(saved) == "table" and next(saved) ~= nil then
            CVars.RestoreAll(saved)
        end
    end
end

-- After PLAYER_LOGIN, when ns.Start has turned the modules on.
ns.On("PLAYER_ENTERING_WORLD", restoreLeftovers)
