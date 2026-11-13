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
    local inCombat = false
    InCombatLockdown = function() return inCombat end
    -- The client's CVars, for an option that is one of Blizzard's settings (`cvar`).
    local cvars, refuse = { coords = "0" }, {}
    C_CVar = {
        GetCVar = function(name) return cvars[name] end,
        GetCVarDefault = function() return "0" end,
        SetCVar = function(name, value)
            if refuse[name] then
                return false
            end
            cvars[name] = value
            return true
        end,
    }
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
    UnitGUID = function() return "Player-1-A" end
    local files = { "Core", "Commands", "Locales/enUS/Core", "Lib/Presets", "Lib/Store", "Lib/Profiles", "Lib/Frames",
        "Lib/Players", "Lib/CVars", "Lib/Text", "Lib/Secret", "Lib/Plugins" }
    for _, path in ipairs(files) do
        T.load(path, core)
    end
    core.GameData = { Prune = function() end }
    core.Profiler = { recording = false, Wrap = function(_, fn) return fn end }
    local refreshed = {}
    core.RefreshSetting = function(name) refreshed[#refreshed + 1] = name end -- Settings.lua's
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

    -- A module with a checkbox that is one of Blizzard's settings.
    local coords = core.NewModule("Coords", "test", { enabled = true, player = true })
    coords.options = { { key = "player", name = "Player", cvar = "coords" } }
    local coordsHeard = {}
    coords.OnOptionChanged = function(_, key) coordsHeard[#coordsHeard + 1] = key end

    -- A locked module (one the game broke) stays off, even saved as on.
    local locked = core.NewModule("Locked", "test", { enabled = true })
    locked.locked = true
    local lockedEnables = 0
    function locked:OnEnable() lockedEnables = lockedEnables + 1 end

    -- A tool that is always on, with an option, for switching profiles.
    local tool = core.NewModule("Tool", "test", { enabled = true, mode = "a" })
    tool.alwaysOn = true
    tool.options = { { key = "mode", name = "Mode", choices = { { "a" }, { "b" } } } }
    local toolHeard = {}
    tool.OnOptionChanged = function(_, key) toolHeard[#toolHeard + 1] = key end

    eq(host.defaults.extra, true, "lifecycle: a checkbox part defaults to on")
    eq(host.defaults.where, "bottom", "lifecycle: a dropdown part keeps its default")
    eq(host.defaults.side, nil, "lifecycle: a dropdown part isn't defaulted to true")

    -- A plugin's module (Lib/Plugins.lua): another addon's, through a handle.
    local Plugins = core.Plugins
    local plugin = Plugins.Register("MyAddonThing", "Does a thing.", { size = 20, mode = "a", loud = true,
        seen = {} }, "MyAddon")
    local real = core.modules.MyAddonThing
    eq(real ~= nil and plugin ~= real and Plugins.Module(plugin) == real, true,
        "plugins: a handle, not Core's module")
    eq(real.defaults.enabled, false, "plugins: off unless its defaults say on")
    eq(real.notice[1].text:find("MyAddon", 1, true) ~= nil, true, "plugins: its page names the addon")
    eq(plugin.name == "MyAddonThing" and plugin.enabled == false and plugin.defaults == nil, true,
        "plugins: a handle reads its name and state, nothing else")
    plugin.title, plugin.category = "My Thing", "map"
    eq(real.title .. "," .. real.category, "My Thing,map", "plugins: a title and category pass on")
    local theirs = {
        { key = "size", name = "Size", min = 10, max = 40, step = 2, cvar = "someCVar", debug = true },
        { key = "mode", name = "Mode", choices = { { "a", "A" }, { "b", "B" } }, requires = "loud" },
        { key = "loud", name = "Loud" },
    }
    plugin.options = theirs
    eq(real.options ~= theirs and real.options[1].min == 10 and real.options[2].choices[2][1] == "b", true,
        "plugins: options are copied")
    eq(real.options[1].cvar == nil and real.options[1].debug == nil, true,
        "plugins: a field only our modules use is left out")
    local function refused(fn)
        return not pcall(fn)
    end
    eq(refused(function() plugin.options = { { key = "nope", name = "x" } } end), true,
        "plugins: an option without a default")
    eq(refused(function() plugin.options = { { key = "size", name = "x" } } end), true,
        "plugins: a checkbox on a number")
    eq(refused(function() plugin.options = { { key = "mode", name = "x", choices = { { "z", "Z" } } } } end), true,
        "plugins: a dropdown whose default isn't a choice")
    eq(refused(function() plugin.options = { { key = "loud", name = "x", requires = "gone" } } end), true,
        "plugins: an option that needs one that isn't there")
    eq(refused(function() plugin.options = { { key = "enabled", name = "x" } } end), true,
        "plugins: no option for enabled")
    eq(#real.options, 3, "plugins: a refused list changes nothing")
    eq(refused(function() plugin.locked = true end), true, "plugins: a field outside the contract")
    eq(refused(function() plugin.title = 5 end), true, "plugins: a field of the wrong type")
    plugin.notice = { text = "Mine." }
    eq(#real.notice == 2 and real.notice[2].text == "Mine.", true, "plugins: its notice follows ours")
    plugin.actions = { { name = "Do", button = "Go", fn = function() end, key = "x" } }
    eq(real.actions[1].button == "Go" and real.actions[1].key == nil, true, "plugins: buttons are copied")
    plugin.perCharacter = { seen = true }
    eq(real.perCharacter.seen, true, "plugins: data for each character")
    eq(refused(function() plugin.perCharacter = { size = true } end), true, "plugins: only data can be per character")
    local pluginCalls = {}
    function plugin:OnEnable()
        pluginCalls[#pluginCalls + 1] = self == plugin and "enable" or "wrong self"
        self:On("PLAYER_MONEY", count("pluginMoney"))
    end
    function plugin:OnDisable()
        pluginCalls[#pluginCalls + 1] = "disable"
    end
    function plugin:OnOptionChanged(key)
        pluginCalls[#pluginCalls + 1] = "changed " .. key
    end
    eq(refused(function() Plugins.Register("MyAddonThing", "Again.", {}) end), true, "plugins: a name taken")
    eq(refused(function() Plugins.Register("not a name", "x", {}) end), true, "plugins: a name that isn't one word")
    eq(refused(function() Plugins.Register("NoDefaults", "x") end), true, "plugins: defaults are a table")

    -- A plugin seen before whose addon isn't loaded this session keeps its settings.
    ForeverPlusPlusDB = { plugins = { GoneAddonThing = true },
        settings = { GoneAddonThing = { size = 3 }, Removed = { size = 4 } } }
    ForeverPlusPlusCharDB = nil
    core.Start()
    eq(ForeverPlusPlusDB.settings.GoneAddonThing ~= nil and ForeverPlusPlusDB.settings.Removed == nil, true,
        "plugins: an absent plugin's settings stay, a removed module's go")
    eq(ForeverPlusPlusDB.plugins.MyAddonThing, true, "plugins: remembered once seen")
    ForeverPlusPlusDB.settings.GoneAddonThing, ForeverPlusPlusDB.plugins.GoneAddonThing = nil, nil

    eq(plugin.db.size == 20 and #pluginCalls == 0, true, "plugins: settings at login, off by default")
    core.SetEnabled("MyAddonThing", true)
    eq(pluginCalls[1] == "enable" and plugin.enabled, true, "plugins: OnEnable gets the handle")
    fire("PLAYER_MONEY")
    eq(heard.pluginMoney, 1, "plugins: its events are heard while it's on")
    core.SetOption("MyAddonThing", "size", 30)
    eq(pluginCalls[2] == "changed size" and plugin.db.size == 30, true, "plugins: OnOptionChanged")
    core.SetEnabled("MyAddonThing", false)
    fire("PLAYER_MONEY")
    eq(pluginCalls[3] == "disable" and heard.pluginMoney == 1, true, "plugins: off, its events stop")
    heard.pluginMoney = nil
    eq(refused(function() Plugins.Register("TooLate", "x", {}) end), true, "plugins: no module after login")
    eq(refused(function() plugin.options = theirs end), true, "plugins: no new options after login")
    core.MapTooltip = { Note = function(text) return { text } end, Detail = 1, Pair = 1, Show = 1 }
    core.QuestieDB = { IsReady = function() return true end, Reset = function() end }
    local kit = Plugins.Kit()
    eq(kit == Plugins.Kit() and refused(function() kit.Timer = nil end), true, "plugins: one kit, read only")
    eq(kit.Tooltip.Note("x")[1] == "x" and kit.Tooltip.Show == nil, true, "plugins: the kit's tooltip lines")
    eq(kit.QuestieDB.IsReady() and kit.QuestieDB.Reset == nil, true, "plugins: only the QuestieDB calls it lists")
    eq(kit.Timer(plugin).module == real and kit.IsNumber(5), true, "plugins: a timer owned by the plugin's module")

    eq(locked.enabled and true or false, false, "lifecycle: a locked module stays off at login")
    core.SetEnabled("Locked", true)
    eq(lockedEnables, 0, "lifecycle: a locked module can't be turned on")

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

    -- A `cvar` checkbox reads and sets the CVar; in combat it reads the choice until combat ends,
    -- and the module, the API's listeners and the page hear about it then.
    local told = {}
    core.OnModuleChanged(function(name, key)
        if name == "Coords" then told[#told + 1] = key end
    end)
    local function news() -- what the module and the listeners heard since last asked
        local text = table.concat(coordsHeard, ",") .. "|" .. table.concat(told, ",")
        coordsHeard, told = {}, {}
        return text
    end
    eq(coords.defaults.player, false, "cvar: the default is the client's")
    core.SetOption("Coords", "player", true)
    eq(cvars.coords == "1" and coords.db.player == true, true, "cvar: out of combat it's set at once")
    eq(news(), "player|player", "cvar: and the module hears it at once")
    inCombat = true
    core.SetOption("Coords", "player", false)
    eq(cvars.coords, "1", "cvar: in combat the CVar waits")
    eq(coords.db.player, false, "cvar: but the option reads the choice")
    eq(news(), "|", "cvar: and nobody is told yet")
    core.SetOption("Coords", "player", true)
    core.SetOption("Coords", "player", false)
    refreshed = {}
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(cvars.coords == "0" and coords.db.player == false, true, "cvar: after combat it's the last choice")
    eq(news(), "player|player", "cvar: told once, when it lands")
    eq(table.concat(refreshed, ","), "Coords", "cvar: and the page redraws")
    inCombat = true
    core.SetOption("Coords", "player", true)
    core.SetOption("Coords", "player", false)
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(news(), "|", "cvar: a choice taken back in combat tells nobody")
    inCombat = true
    core.SetOption("Coords", "player", true)
    core.ResetOption("Coords", "player")
    eq(coords.db.player, false, "cvar: the undo arrow in combat reads the default")
    core.SetOption("Coords", "player", true)
    refuse.coords = true
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(coords.db.player, false, "cvar: refused, it reads the CVar again")
    eq(news(), "player|player", "cvar: and the module and page hear it, having shown the choice")
    refuse.coords = nil
    inCombat = true
    core.ResetOption("Coords", "player")
    eq(news(), "|", "cvar: a reset in combat waits too")
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(news(), "|", "cvar: and tells nobody when nothing changed")

    -- module:TooltipLinePreCall hooks once, passes on what `fn` returns (true leaves the line
    -- out), and does nothing while the module is off. A tooltip type of the same number is a
    -- separate hook.
    plain:TooltipLinePreCall(18, function() end) -- no TooltipDataProcessor: nothing, no error
    local linePre, post = {}, {}
    TooltipDataProcessor = {
        AddLinePreCall = function(kind, fn) linePre[#linePre + 1] = { kind, fn } end,
        AddTooltipPostCall = function(kind, fn) post[#post + 1] = { kind, fn } end,
    }
    local skipLine = function(_, lineData) return lineData.skip end
    plain:TooltipLinePreCall(18, skipLine)
    plain:TooltipLinePreCall(18, skipLine)
    plain:TooltipPostCall(18, skipLine)
    eq(#linePre .. "," .. #post, "1,1", "hooks: a line pre call is hooked once, apart from post calls")
    eq(linePre[1][1], 18, "hooks: for its line type")
    eq(linePre[1][2]({}, { skip = true }), true, "hooks: a line pre call's true comes back")
    eq(linePre[1][2]({}, { skip = false }), false, "hooks: and its false")
    core.SetEnabled("Plain", false)
    eq(linePre[1][2]({}, { skip = true }), nil, "hooks: a line pre call does nothing while off")
    core.SetEnabled("Plain", true)
    TooltipDataProcessor = nil

    -- Profiles: a switch turns off what's on, reads the other profile, and turns on what it has
    -- on, live; in combat it waits. Presets reset only the profile in use.
    local Profiles = core.Profiles
    eq(Profiles.Current(), "default", "profiles: the character starts on Default")
    core.SetOption("Plain", "loud", true)
    local two = Profiles.Create("Two")
    core.db.profiles[two].settings = { Plain = { enabled = false, mode = "gone" }, Host = { extra = false },
        Tool = { mode = "b" } }
    local switchedTold = {}
    core.OnModuleChanged(function(name, key) switchedTold[#switchedTold + 1] = name .. ":" .. tostring(key) end)
    refreshed = {}
    eq(Profiles.Switch(two), true, "profiles: a switch out of combat")
    eq(plain.enabled, false, "profiles: a module the new profile has off turns off")
    eq(registered("PLAYER_LEVEL_UP"), false, "profiles: and its events stop")
    eq(host.enabled and not check.enabled, true, "profiles: a module on in both reads the new profile's parts")
    eq(plain.db.loud, false, "profiles: settings read the new profile")
    eq(plain.db.mode, "a", "profiles: a saved choice that isn't one goes back to its default")
    eq(tool.enabled and tool.db.mode == "b", true, "profiles: a tool stays on and reads the new profile")
    eq(toolHeard[#toolHeard], "mode", "profiles: and hears the option that changed")
    eq(table.concat(switchedTold, ","):find("Plain:nil", 1, true) ~= nil, true,
        "profiles: listeners hear of a module turned off")
    eq(#refreshed >= #core.order, true, "profiles: every module's page redraws")
    core.SetOption("Plain", "mode", "b")
    eq(core.db.settings.Plain.mode, nil, "profiles: a change goes to the profile in use, not Default")
    core.ApplyPreset()
    eq(core.db.profiles[two].settings.Plain == nil or core.db.profiles[two].settings.Plain.mode == nil, true,
        "profiles: Defaults resets the profile in use")
    eq(core.db.settings.Plain.loud, true, "profiles: and leaves the other profiles alone")
    core.SetEnabled("Plain", false)
    inCombat = true
    eq(Profiles.Switch("default"), false, "profiles: in combat a switch waits")
    eq(plain.enabled, false, "profiles: and nothing changes yet")
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(Profiles.Current(), "default", "profiles: once combat ends it switches")
    eq(plain.enabled and plain.db.loud, true, "profiles: and Default's modules and settings are back")
    eq(registered("PLAYER_LEVEL_UP"), true, "profiles: with their events")
    eq(check.enabled, true, "profiles: and parts")
    eq(tool.db.mode, "a", "profiles: and the tool's option")

    -- Presets (Lib/Presets.lua): a profile based on one reads, for whatever the player hasn't set,
    -- the preset's value (along `extends`) before the module's default, for options and on/off
    -- alike, at read time, so what a later release adds to the preset reaches it.
    local Presets = core.Presets
    Presets.Register("base", { title = "Base" })
    Presets.Register("spec", { title = "Spec", extends = "base" })
    plain.presets = { base = { enabled = true, options = { mode = "b" } }, spec = { enabled = false } }
    host.presets = { spec = { options = { loud2 = true } } }
    locked.presets = { spec = { enabled = true } }
    tool.presets = { spec = { options = { mode = "b" } } }
    coords.presets = { spec = { options = { player = false } } }
    core.ApplyPreset()
    local defaultSaved = core.db.settings
    eq(core.UsePreset("nothing"), false, "presets: one that isn't there does nothing")
    refreshed = {}
    eq(core.UsePreset("spec"), true, "presets: the Defaults popup's preset button")
    eq(core.db.preset, "spec", "presets: links the profile in use")
    eq(defaultSaved.Plain == nil or next(defaultSaved.Plain) == nil, true,
        "presets: and writes nothing of the preset's into its settings")
    eq(plain.db.mode, "b", "presets: an option reads the preset it extends")
    eq(plain.db.enabled == false and plain.enabled == false, true,
        "presets: the nearer preset wins: a module it turns off is off, live")
    eq(registered("PLAYER_LEVEL_UP"), false, "presets: and its events stop")
    eq(host.db.loud2 and registered("PLAYER_XP_UPDATE"), true, "presets: a part's option, and the part hears it")
    eq(host.db.extra, true, "presets: what no preset sets reads the default")
    eq(Presets.Enabled("spec", "Locked"), nil, "presets: say nothing to turn on a locked module")
    eq(not locked.enabled and lockedEnables == 0, true, "presets: a locked module stays off")
    eq(tool.db.mode, "a", "presets: a tool that's always on is left alone")
    eq(coords.db.player, false, "presets: one of Blizzard's settings reads the CVar")
    eq(Presets.Value("spec", "Coords", "player"), nil, "presets: which a preset never sets")
    eq(#refreshed >= #core.order, true, "presets: every page redraws")

    -- The three layers, and resets falling to the preset.
    core.SetOption("Plain", "mode", "a")
    eq(plain.db.mode, "a", "presets: the player's choice beats the preset")
    eq(core.BaseValue(plain, "mode"), "b", "presets: whose value is what a reset gives")
    eq(core.BaseValue(host, "extra"), true, "presets: else the default")
    core.ResetOption("Plain", "mode")
    eq(plain.db.mode .. "," .. tostring(defaultSaved.Plain and defaultSaved.Plain.mode), "b,nil",
        "presets: the undo arrow forgets the choice and the preset's value reads back")
    core.SetEnabled("Plain", true)
    eq(plain.enabled and defaultSaved.Plain.enabled, true, "presets: turning on a module the preset has off is a choice")
    core.SetEnabled("Plain", false)
    plain.db.enabled = nil
    eq(plain.db.enabled, false, "presets: forgotten, on/off reads the preset again")
    host.presets.spec.options.extra = false -- a later release adds to the preset
    eq(host.db.extra, false, "presets: what a release adds to the preset reaches the profile")
    host.presets.spec.options.extra = nil

    -- A preset this version doesn't have (saved by a newer version) reads as none.
    core.db.preset = "fromnewer"
    eq(plain.db.mode .. "," .. tostring(core.BaseValue(plain, "mode")), "a,a", "presets: an unknown preset is none")
    eq(plain.db.enabled, true, "presets: for on/off too")
    eq(core.db.preset, "fromnewer", "presets: and stays saved")
    core.db.preset = "spec"

    -- Recommended Defaults bases the profile on none again.
    core.ApplyPreset()
    eq(core.db.preset, nil, "presets: plain Defaults drops the link")
    eq(plain.enabled and plain.db.mode == "a" and not host.db.loud2, true, "presets: and the defaults read back, live")
    eq(registered("PLAYER_XP_UPDATE"), false, "presets: and the part hears that too")

    -- Switching live between a profile based on a preset and one on none, and unlinking.
    local linked = Profiles.CreateFromPreset("Linked", "spec")
    eq(next(core.db.profiles[linked].settings or {}), nil, "presets: a new profile from one has nothing set")
    Profiles.Switch(linked)
    eq(plain.enabled == false and plain.db.mode == "b" and host.db.loud2, true,
        "presets: switching to it reads the preset, live")
    Profiles.Switch("default")
    eq(plain.enabled and plain.db.mode == "a" and not host.db.loud2, true,
        "presets: and switching back reads Default's")
    Profiles.Switch(linked)
    core.SetOption("Host", "extra", false)
    eq(Profiles.SetPreset(linked, nil), true, "presets: unlinking the profile in use")
    local own = core.db.profiles[linked].settings
    eq(core.db.profiles[linked].preset, nil, "presets: unlinked")
    eq(plain.enabled == false and plain.db.mode == "b" and host.db.loud2 and not check.enabled, true,
        "presets: it looks the same, live")
    eq(tostring(own.Plain.enabled) .. "," .. own.Plain.mode .. "," .. tostring(own.Host.loud2) .. ","
        .. tostring(own.Host.extra), "false,b,true,false", "presets: the preset's values are its own now")
    eq(Profiles.SetPreset(linked, "spec"), true, "presets: linking again")
    eq(own.Host.extra, false, "presets: keeps the player's choices")
    Profiles.Switch("default")

    -- A module can tell being switched away from (a profile, a preset, Defaults) from being turned
    -- off by the player: ns.switching is true only for the first.
    local seen = {}
    local onDisable = plain.OnDisable
    plain.OnDisable = function(self)
        seen[#seen + 1] = core.switching and true or false
        if onDisable then
            onDisable(self)
        end
    end
    core.SetEnabled("Plain", true)
    core.SetEnabled("Plain", false)
    core.SetEnabled("Plain", true)
    Profiles.Switch(linked)
    Profiles.Switch("default")
    eq(tostring(seen[1]) .. "," .. tostring(seen[2]), "false,true",
        "switching: off by hand, then by a profile switch")
    eq(core.switching, false, "switching: over once the switch is done")
    plain.OnDisable = onDisable
end
