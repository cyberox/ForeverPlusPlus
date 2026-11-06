-- Core: modules and parts turning on and off, OnWhile, owned timers, /fpp set, and presets.
local T = ...
local eq = T.eq

-- The real Core.lua and Lib/Frames.lua in an `ns` of their own, against stub frames (events are
-- fired by hand) and a clock for C_Timer: modules turning on and off, OnWhile, parts with a
-- checkbox or a dropdown, and timers a module owns.

do
    local frames = {}
    local Frame = {}
    Frame.__index = Frame
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:RegisterEvent(event) self.events[event] = true end
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
    function Frame:HookScript() end
    CreateFrame = function()
        local frame = setmetatable({ scripts = {}, events = {} }, Frame)
        frames[#frames + 1] = frame
        return frame
    end

    -- Fires `event` on every frame registered for it, honoring unit filters as the client would.
    local function fire(event, ...)
        local unit = ...
        for _, frame in ipairs(frames) do
            local reg = frame.events[event]
            local pass = reg == true
            if type(reg) == "table" then
                for _, u in ipairs(reg) do
                    pass = pass or u == unit
                end
            end
            if pass then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end

    local function registered(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then
                return true
            end
        end
        return false
    end

    -- C_Timer on a clock that moves only when `wait` says.
    local now, pending = 0, {}
    C_Timer = {
        NewTimer = function(seconds, fn)
            local handle = { at = now + seconds, fn = fn }
            function handle:Cancel() self.cancelled = true end
            pending[#pending + 1] = handle
            return handle
        end,
    }
    local function wait(seconds)
        now = now + seconds
        local due = pending
        pending = {}
        for _, handle in ipairs(due) do
            if handle.at > now then
                pending[#pending + 1] = handle
            elseif not handle.cancelled then
                handle.fn()
            end
        end
    end

    securecallfunction = function(fn, ...) return fn(...) end -- errors fail the run
    hooksecurefunc = function() end
    InCombatLockdown = function() return false end
    GetLocale = function() return "enUS" end
    C_AddOns = { GetAddOnMetadata = function() return "0.9.0" end }
    SlashCmdList = {}
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    strsplit = function(sep, s, limit)
        local parts, from = {}, 1
        while not limit or #parts < limit - 1 do
            local at = s:find(sep, from, true)
            if not at then
                break
            end
            parts[#parts + 1] = s:sub(from, at - 1)
            from = at + #sep
        end
        parts[#parts + 1] = s:sub(from)
        return unpack(parts)
    end

    local core = {}
    for _, path in ipairs({ "Core", "Commands", "Locales/enUS/Core", "Lib/Store", "Lib/Frames", "Lib/Players" }) do
        T.load(path, core)
    end
    core.GameData = { Prune = function() end }
    core.Profiler = { recording = false, Wrap = function(_, fn) return fn end }
    core.RefreshSetting = function() end -- Settings/Settings.lua's
    core.OpenSettings = function() return true end
    local Frames = core.Frames

    -- A module with a checkbox and a dropdown option, each driving events through OnWhile.
    local heard = {}
    local function count(key)
        return function() heard[key] = (heard[key] or 0) + 1 end
    end
    local plain = core.NewModule("Plain", "test", { enabled = true, loud = false, mode = "a" })
    plain.options = {
        { key = "loud", name = "Loud" },
        { key = "mode", name = "Mode", choices = { { "a" }, { "b" }, { "off" } } },
    }
    plain:OnWhile("loud", { PLAYER_MONEY = count("money") })
    plain:OnWhile("mode", { BAG_UPDATE = count("bag") })
    plain:OnWhile(function(db) return db.loud and db.mode == "b" end, { ZONE_CHANGED = count("zone") })
    function plain:OnEnable()
        self:On("PLAYER_LEVEL_UP", count("level"))
    end
    local plainTimer = Frames.Timer(plain)
    local plainQueue = Frames.Coalesce(count("coalesced"), 0.1, plain)

    -- A module made of a checkbox part and a dropdown part.
    local host = core.NewModule("Host", "test", { enabled = true })
    local check = host:NewPart({ key = "extra", name = "Extra", section = "S1" }, { loud2 = false })
    check:AddOptions({ { key = "loud2", name = "Loud" } })
    check:OnWhile("loud2", { PLAYER_XP_UPDATE = count("xp") })
    local WHERE = { { "off" }, { "top" }, { "bottom" } }
    local drop = host:NewPart({ key = "where", name = "Where", section = "S2", choices = WHERE },
        { where = "bottom" })
    local dropCalls = { enable = 0, disable = 0, changed = {} }
    function drop:OnEnable() dropCalls.enable = dropCalls.enable + 1 end
    function drop:OnDisable() dropCalls.disable = dropCalls.disable + 1 end
    function drop:OnOptionChanged(key) dropCalls.changed[#dropCalls.changed + 1] = key end
    drop:OnWhile("where", { MAIL_SHOW = count("mail") })
    local dropTimer = Frames.Timer(drop)
    local side = host:NewPart({ key = "side", name = "Side", section = "S3", choices = WHERE })

    eq(host.defaults.extra, true, "lifecycle: a checkbox part defaults to on")
    eq(host.defaults.where, "bottom", "lifecycle: a dropdown part keeps its default")
    eq(host.defaults.side, nil, "lifecycle: a dropdown part isn't defaulted to true")

    ForeverPlusPlusDB, ForeverPlusPlusCharDB = nil, nil
    core.Start()

    -- PartOn: a dropdown's "off" is off, any other choice on.
    for value, want in pairs({ off = false, top = true, [true] = true, [false] = false }) do
        host.db.side = value
        eq(core.PartOn(host, "side"), want, "lifecycle: PartOn " .. tostring(value))
    end
    host.db.side = nil
    eq(core.PartOn(host, "side"), false, "lifecycle: PartOn nil")

    -- OnWhile follows its option, and the module.
    eq(plain.enabled, true, "lifecycle: module on")
    eq(registered("PLAYER_LEVEL_UP"), true, "lifecycle: OnEnable's event")
    eq(registered("PLAYER_MONEY"), false, "lifecycle: OnWhile off with its checkbox")
    eq(registered("BAG_UPDATE"), true, "lifecycle: OnWhile on with its dropdown")
    core.SetOption("Plain", "loud", true)
    eq(registered("PLAYER_MONEY"), true, "lifecycle: checkbox on: listened")
    fire("PLAYER_MONEY")
    eq(heard.money, 1, "lifecycle: OnWhile handler ran")
    core.SetOption("Plain", "loud", false)
    eq(registered("PLAYER_MONEY"), false, "lifecycle: checkbox off: stopped")
    core.SetOption("Plain", "mode", "off")
    eq(registered("BAG_UPDATE"), false, "lifecycle: dropdown off: stopped")
    core.SetOption("Plain", "mode", "b")
    eq(registered("BAG_UPDATE"), true, "lifecycle: dropdown back on: listened")
    eq(registered("ZONE_CHANGED"), false, "lifecycle: OnWhile function false")
    core.SetOption("Plain", "loud", true)
    eq(registered("ZONE_CHANGED"), true, "lifecycle: OnWhile function true")
    for _ = 1, 5 do
        core.SetOption("Plain", "loud", true)
    end
    local n = 0
    for _, entry in ipairs(plain.events) do
        n = n + (entry[1] == "PLAYER_MONEY" and 1 or 0)
    end
    eq(n, 1, "lifecycle: syncing again doesn't pile up events")
    core.SetEnabled("Plain", false)
    eq(registered("PLAYER_MONEY"), false, "lifecycle: module off: OnWhile stopped")
    eq(registered("PLAYER_LEVEL_UP"), false, "lifecycle: module off: its events stopped")
    eq(plain.events, nil, "lifecycle: module off: events cleared")
    core.SetEnabled("Plain", true)
    eq(registered("PLAYER_MONEY"), true, "lifecycle: module back on: saved option listens")
    eq(registered("ZONE_CHANGED"), true, "lifecycle: module back on: OnWhile function listens")

    -- Owned timers stop with the module, and don't run while it's off.
    local ran = 0
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    core.SetEnabled("Plain", false)
    eq(plainTimer:IsPending(), false, "lifecycle: module off: timer cancelled")
    wait(2)
    eq(ran, 0, "lifecycle: cancelled timer didn't run")
    eq(heard.coalesced, nil, "lifecycle: cancelled Coalesce didn't run")
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    wait(2)
    eq(ran, 0, "lifecycle: a timer doesn't run while its module is off")
    eq(heard.coalesced, nil, "lifecycle: a Coalesce doesn't run while its module is off")
    core.SetEnabled("Plain", true)
    plainTimer:Start(1, function() ran = ran + 1 end)
    plainQueue()
    plainQueue()
    wait(2)
    eq(ran, 1, "lifecycle: timer runs while on")
    eq(heard.coalesced, 1, "lifecycle: Coalesce runs once while on")

    -- A checkbox part: on with its checkbox, and its OnWhile follows its own option.
    eq(check.enabled, true, "lifecycle: checkbox part on")
    core.SetOption("Host", "loud2", true)
    eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part option on: listened")
    core.SetOption("Host", "extra", false)
    eq(check.enabled, false, "lifecycle: checkbox part off")
    eq(registered("PLAYER_XP_UPDATE"), false, "lifecycle: part off: OnWhile stopped")
    core.SetOption("Host", "extra", true)
    eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part back on: OnWhile listens")

    -- A dropdown part: on for any choice but "off", told when it moves between them.
    eq(drop.enabled, true, "lifecycle: dropdown part on at its default")
    eq(side.enabled or false, false, "lifecycle: dropdown part without a value is off")
    eq(registered("MAIL_SHOW"), true, "lifecycle: dropdown part's OnWhile")
    core.SetOption("Host", "where", "top")
    eq(drop.enabled, true, "lifecycle: dropdown part stays on between choices")
    eq(dropCalls.enable, 1, "lifecycle: not enabled again between choices")
    eq(dropCalls.changed[#dropCalls.changed], "where", "lifecycle: told its choice changed")
    dropTimer:Start(1, function() ran = ran + 10 end)
    core.SetOption("Host", "where", "off")
    eq(drop.enabled, false, "lifecycle: dropdown part off at \"off\"")
    eq(dropCalls.disable, 1, "lifecycle: dropdown part disabled once")
    eq(registered("MAIL_SHOW"), false, "lifecycle: dropdown part off: OnWhile stopped")
    wait(2)
    eq(ran, 1, "lifecycle: a part's timer stops with the part")
    core.SetOption("Host", "where", "bottom")
    eq(drop.enabled, true, "lifecycle: dropdown part back on")
    eq(dropCalls.enable, 2, "lifecycle: dropdown part enabled again")
    core.SetEnabled("Host", false)
    eq(drop.enabled, false, "lifecycle: module off: its parts off")
    eq(registered("MAIL_SHOW"), false, "lifecycle: module off: part's OnWhile stopped")
    core.SetEnabled("Host", true)
    eq(drop.enabled and check.enabled, true, "lifecycle: module on: its parts on")

    -- /fpp set and the presets (Commands.lua) go through the same paths.
    local fpp = SlashCmdList.FOREVERPLUSPLUS
    core.Print = function() end
    fpp("set Plain mode off")
    eq(plain.db.mode, "off", "commands: /fpp set takes a choice key")
    eq(registered("BAG_UPDATE"), false, "commands: /fpp set tells the module")
    fpp("toggle Plain loud")
    eq(plain.db.loud, false, "commands: /fpp toggle flips a checkbox")
    fpp("toggle Host")
    eq(host.enabled, false, "commands: /fpp toggle <module> turns it off")
    core.SetOption("Plain", "loud", true)
    core.ApplyPreset()
    eq(plain.db.loud == false and plain.db.mode == "a", true, "commands: preset resets options")
    eq(registered("PLAYER_MONEY") or not registered("BAG_UPDATE"), false,
        "commands: preset tells the module")
    eq(host.enabled, true, "commands: preset turns default-on modules back on")
    local said, ran = nil, false
    core.Print = function(text) said = text end
    core.AddCommand("ping", "", "test", function() ran = true end, "Plain")
    core.SetEnabled("Plain", false)
    fpp("ping")
    eq(not ran and said ~= nil and said:find("/fpp ping", 1, true) ~= nil, true,
        "commands: a command whose module is off says so")
    core.SetEnabled("Plain", true)
    fpp("ping")
    eq(ran, true, "commands: and runs once it's on")

    -- A choice stays saved, even at the default, until a reset forgets it.
    local saved = core.db.settings
    core.SetEnabled("Plain", false)
    core.SetEnabled("Plain", true)
    eq(saved.Plain and saved.Plain.enabled, true, "choices: a module turned off and on keeps its choice")
    core.SetOption("Plain", "loud", true)
    core.SetOption("Plain", "loud", false)
    eq(saved.Plain.loud, false, "choices: an option set back to its default keeps the choice")
    plain.defaults.loud = true -- a later release turns it on by default
    eq(plain.db.loud, false, "choices: so a new default doesn't change it")
    core.ResetOption("Plain", "loud")
    eq(saved.Plain.loud, nil, "choices: the undo arrow forgets it")
    eq(plain.db.loud, true, "choices: and the new default reads back")
    eq(registered("PLAYER_MONEY"), true, "choices: and the module hears it")
    plain.defaults.loud = false
    core.ResetOption("Plain", "loud")
    core.SetOption("Plain", "mode", "a")
    core.ApplyPreset()
    eq(saved.Plain == nil or (saved.Plain.enabled == nil and saved.Plain.mode == nil), true,
        "choices: a preset forgets what it puts back to the default")
    core.ApplyPreset({ "Plain" }, { Plain = { mode = "b" } })
    eq(saved.Plain and saved.Plain.mode, "b", "choices: and saves what it sets otherwise")
    core.ApplyPreset()
end
