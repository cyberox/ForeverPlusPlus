-- CVars: changing game settings for a module and putting the player's own values back, waiting out
-- combat, CVars renamed between patches, Bind's options, the off notice, and values left over by
-- a /reload in combat. A bug here leaves the player's game settings changed, so it's worth the care.
local T = ...
local ns, eq = T.ns, T.eq

-- The client's CVars, and every SetCVar call in order.
local cvars = { nameplateShowFriendlyPlayers = "0", coords = "1", locked = "0" }
local sets = {}
local refuse = {} -- names SetCVar says no to
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value)
        sets[#sets + 1] = name .. "=" .. tostring(value)
        if refuse[name] then
            return false
        end
        cvars[name] = value
        return true
    end,
}
-- Combat: AfterCombat runs at once out of it, and queues in order in it, as Core's does.
local inCombat, queued = false, {}
ns.AfterCombat = function(fn)
    if inCombat then
        queued[#queued + 1] = fn
    else
        fn()
    end
end
local function leaveCombat()
    inCombat = false
    local run = queued
    queued = {}
    for _, fn in ipairs(run) do
        fn()
    end
end
local handlers = {}
ns.On = function(event, fn) handlers[event] = fn end
ns.Off = function(event) handlers[event] = nil end
ns.L.SETTINGS_TURN_ON = "Turn On"
T.load("Lib/CVars") -- it caches C_CVar
local CVars = ns.CVars
local function log()
    local text = table.concat(sets, ",")
    sets = {}
    return text
end

-- Names newest first: the first the client knows is used.
eq(CVars.IsOn({ "nameplateShowFriendlyPlayerUnits", "nameplateShowFriendlyPlayers" }), false,
    "cvars: an older name is used when the newest is missing")
eq(CVars.IsOn("coords"), true, "cvars: on is \"1\"")
eq(CVars.IsOn("missing"), false, "cvars: one this client doesn't have is off")

-- Set keeps the player's first value, and changes nothing that's already right.
local saved = {}
CVars.Set(saved, { "newName", "nameplateShowFriendlyPlayers" }, "1")
eq(log(), "nameplateShowFriendlyPlayers=1", "cvars: set under the name the client has")
eq(saved.nameplateShowFriendlyPlayers, "0", "cvars: the player's value is kept")
CVars.Set(saved, "nameplateShowFriendlyPlayers", "1")
eq(log(), "", "cvars: setting what it already is does nothing")
cvars.nameplateShowFriendlyPlayers = "2" -- something else changed it since
CVars.Set(saved, "nameplateShowFriendlyPlayers", "1")
eq(saved.nameplateShowFriendlyPlayers, "0", "cvars: the first value is kept, not ours")
CVars.Set(saved, "missing", "1")
eq(log() == "nameplateShowFriendlyPlayers=1" and saved.missing == nil, true,
    "cvars: a CVar the client lacks is left alone")

-- Restore puts one back and forgets it; RestoreAll puts back the rest.
CVars.Set(saved, "coords", "0")
log()
CVars.Restore(saved, "nameplateShowFriendlyPlayers")
eq(log(), "nameplateShowFriendlyPlayers=0", "cvars: restore puts the player's value back")
eq(saved.nameplateShowFriendlyPlayers, nil, "cvars: and forgets it")
CVars.Restore(saved, "nameplateShowFriendlyPlayers")
eq(log(), "", "cvars: restoring again does nothing")
CVars.RestoreAll(saved)
eq(log() == "coords=1" and next(saved) == nil, true, "cvars: restore all puts back the rest")

-- In combat everything waits, and runs in order once it ends.
inCombat = true
CVars.Set(saved, "coords", "0")
CVars.Restore(saved, "coords")
eq(log(), "", "cvars: nothing changes in combat")
leaveCombat()
eq(log(), "coords=0,coords=1", "cvars: after combat, in the order asked")
eq(next(saved), nil, "cvars: and nothing is left saved")

-- Apply: the player's own choice, nothing remembered, and told how it went.
local results = {}
CVars.Apply("locked", "1", function(ok) results[#results + 1] = tostring(ok) end)
refuse.coords = true
CVars.Apply("coords", "0", function(ok) results[#results + 1] = tostring(ok) end)
CVars.Apply("missing", "1", function(ok) results[#results + 1] = tostring(ok) end)
eq(table.concat(results, ","), "true,false,false", "cvars: apply says whether the client took it")
refuse.coords = nil
log()

-- Same: the same text, or the same number written the game's way.
eq(CVars.Same("0.650000", "0.65"), true, "same: a number the game wrote its own way")
eq(CVars.Same("1", "1"), true, "same: the same text")
eq(CVars.Same("inline", "popout"), false, "same: different text")
eq(CVars.Same("0.3", "0.65"), false, "same: different numbers")
eq(CVars.Same(nil, "1"), false, "same: a CVar with no value")

-- Hold: sets only what's different, and says how it went.
local held = {}
local function hold(name, value)
    CVars.Hold(name, value, function(result, now) held[#held + 1] = result .. ":" .. tostring(now) end)
end
cvars.scale = "0.300000"
hold("scale", "0.65")
eq(log() .. "|" .. held[#held], "scale=0.65|set:0.65", "hold: sets one that's different")
cvars.scale = "0.650000"
hold("scale", "0.65")
eq(log() .. "|" .. held[#held], "|held:0.650000", "hold: leaves one that already is, written its way")
hold("missing", "1")
eq(log() .. "|" .. held[#held], "|missing:nil", "hold: one this client lacks is left alone")
refuse.scale = true
cvars.scale = "0.3"
hold("scale", "0.65")
eq(held[#held], "refused:0.3", "hold: one the client says no to")
refuse.scale = nil
local realSet = C_CVar.SetCVar
C_CVar.SetCVar = function(name, value)
    return realSet(name, name == "scale" and "2.0" or value) -- held at the end of its range
end
hold("scale", "5")
eq(held[#held], "kept:2.0", "hold: one the game takes as something else says what it kept")
C_CVar.SetCVar = realSet
log()
inCombat = true
cvars.scale = "0.3"
hold("scale", "0.65")
local before = #held
eq(log(), "", "hold: waits for combat to end")
leaveCombat()
eq(log() .. "|" .. #held - before, "scale=0.65|1", "hold: and then sets it")

-- Bind: an option that's on sets its CVar to "1", off puts the player's value back.
cvars.locked = "0"
local module = { db = { enabled = true, saved = {}, lock = false, show = true } }
local bound = CVars.Bind(module, { lock = "locked", show = { "newShow", "coords" } })
bound.ApplyAll()
eq(cvars.locked == "0" and module.db.saved.locked == nil, true, "bind: an option that's off leaves it")
module.db.lock = true
bound.Apply("lock")
eq(cvars.locked == "1" and module.db.saved.locked == "0", true, "bind: on sets it and keeps the player's")
bound.Apply("unmapped")
module.db.lock = false
bound.Apply("lock")
eq(cvars.locked, "0", "bind: off puts the player's back")
module.db.lock = true
bound.Apply("lock")
bound.Restore()
eq(cvars.locked == "0" and next(module.db.saved) == nil, true, "bind: restore puts everything back")

-- The notice: shown while the module is on and the CVar is off, and its button turns it on.
cvars.coords = "0"
local notice = CVars.OffNotice(module, { "newShow", "coords" }, "Coordinates are off.", "Why.")
eq(notice.button, "Turn On", "notice: its button")
eq(notice.shown(), true, "notice: shown while the CVar is off")
module.db.enabled = false
eq(notice.shown(), false, "notice: not while the module is off")
module.db.enabled = true
notice.fn()
eq(cvars.coords == "1" and notice.shown() == false, true, "notice: the button turns it on")
eq(CVars.OffNotice(module, "missing", "x", "y").shown(), false, "notice: never for a CVar the client lacks")

-- At login, a module that's off but still holds values (a /reload in combat) puts them back.
local leftover = { enabled = false, db = { saved = { locked = "0" } } }
local stillOn = { enabled = true, db = { saved = { coords = "0" } } }
cvars.locked, cvars.coords = "1", "1"
CVars.Track(leftover)
CVars.Track(stillOn)
eq(type(handlers.PLAYER_ENTERING_WORLD), "function", "leftovers: checked when the player enters the world")
handlers.PLAYER_ENTERING_WORLD()
eq(cvars.locked == "0" and next(leftover.db.saved) == nil, true, "leftovers: an off module's values go back")
eq(cvars.coords, "1", "leftovers: a module that's on keeps its changes")
eq(handlers.PLAYER_ENTERING_WORLD, nil, "leftovers: only once")
