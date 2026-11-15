-- Plugins: what another addon's module is handed (Lib/Plugins.lua). The handle's fields and its
-- life through login are in spec/core_plugins.lua; this is the promise around them: a plugin gets
-- tables of its own, never ours, what it gives us is checked, its functions are called guarded,
-- and it can't do while its module is off what our own modules can't.
local T = ...
local eq, raises = T.eq, T.raises

-- The real Core.lua, Lib/Frames.lua and Lib/Plugins.lua in an `ns` of their own, against stub
-- frames and a clock for C_Timer, as tests/lib/core.lua has them.
do
    local frames = {}
    local Frame = {}
    Frame.__index = Frame
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:RegisterEvent(event) self.events[event] = true end
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:HookScript() end
    CreateFrame = function()
        local frame = setmetatable({ scripts = {}, events = {} }, Frame)
        frames[#frames + 1] = frame
        return frame
    end
    local function fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then
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
    local function waiting()
        local count = 0
        for _, handle in ipairs(pending) do
            count = count + (handle.cancelled and 0 or 1)
        end
        return count
    end

    -- Errors go to the error handler, as the client's securecallfunction sends them, and are
    -- counted here: a guarded call reports and goes on.
    local reported = {}
    local function report(err)
        reported[#reported + 1] = tostring(err)
    end
    geterrorhandler = function() return report end
    securecallfunction = function(fn, ...)
        local results = { pcall(fn, ...) }
        if not results[1] then
            report(results[2])
            return
        end
        return unpack(results, 2)
    end
    -- Whether `fn` ran without raising, and reported exactly `count` errors.
    local function reports(count, fn)
        local before = #reported
        local ok = pcall(fn)
        return ok and #reported - before == count
    end
    hooksecurefunc = function() end
    InCombatLockdown = function() return false end
    C_CVar = { GetCVar = function() end, GetCVarDefault = function() end, SetCVar = function() return true end }
    C_EventUtils = { IsEventValid = function(event) return event ~= "NO_SUCH_EVENT" end }
    GetLocale = function() return "enUS" end
    C_AddOns = { GetAddOnMetadata = function() return "0.9.0" end }
    SlashCmdList = {}
    UnitGUID = function() return "Player-1-A" end
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

    local core = {}
    for _, path in ipairs({ "Core", "Commands", "Locales/enUS/Core", "Lib/Presets", "Lib/Store", "Lib/Profiles",
        "Lib/Frames", "Lib/Players", "Lib/CVars", "Lib/Text", "Lib/Secret", "Lib/Plugins" }) do
        T.load(path, core)
    end
    core.GameData = { Prune = function() end }
    core.Profiler = { recording = false, Wrap = function(_, fn) return fn end }
    core.RefreshSetting = function() end

    -- Stand-ins for the map libraries: a layer that records what the kit does with it.
    local layers = {}
    core.MapPins = {
        New = function(fill)
            local layer = { fill = fill, pins = {}, on = false, refreshed = 0 }
            function layer:Enable() self.on = true end
            function layer:Disable() self.on = false end
            function layer:Refresh() self.refreshed = self.refreshed + 1 end
            layers[#layers + 1] = layer
            return layer
        end,
    }
    local waypoint
    core.WorldMap = {
        SetWaypoint = function(mapID, x, y, name)
            if mapID == 13 then
                error("ours broke")
            end
            waypoint = { mapID, x, y, name }
            return true
        end,
        IsContinent = function(info) return info.mapType == 2 end,
    }
    core.MapTooltip = {
        Note = function(text) return { text, { r = 0.5, g = 0.5, b = 0.5 } } end,
        Detail = function(text) return { text, { r = 1, g = 1, b = 1 } } end,
        Pair = function(label, value) return { label, { r = 1, g = 1, b = 1 }, right = value } end,
    }
    local readyFn
    core.QuestieDB = {
        IsReady = function() return true end,
        OnReady = function(fn) readyFn = fn end,
        Cancel = function(fn)
            if readyFn == fn then
                readyFn = nil
            end
        end,
    }

    local Plugins = core.Plugins
    local kit = Plugins.Kit()
    local PREFIX = "ForeverPlusPlus: "

    -- Defaults: only what the saved variables can hold, copied.
    local seen = { first = { 1, 2 } }
    local plugin = Plugins.Register("MyAddonThing", "Does a thing.",
        { size = 20, mode = "a", loud = true, chat = true, seen = seen }, "MyAddon")
    local real = core.modules.MyAddonThing
    seen.first[1], seen.later = 99, true
    eq(real.defaults.seen ~= seen and real.defaults.seen.first[1] == 1 and real.defaults.seen.later == nil, true,
        "plugins: a table default is copied, all the way down")
    local ring = {}
    ring.ring = ring
    raises(function() Plugins.Register("Ring", "x", { data = ring }) end, "default data",
        "plugins: a default that holds itself")
    raises(function() Plugins.Register("Fn", "x", { run = function() end }) end, "default run",
        "plugins: a default that is a function")
    raises(function() Plugins.Register("NaN", "x", { size = 0 / 0 }) end, "default size",
        "plugins: a default that isn't a number")
    raises(function() Plugins.Register("On", "x", { enabled = "yes" }) end, "enabled",
        "plugins: enabled is true or false")
    eq(core.modules.Ring == nil and core.modules.Fn == nil and core.modules.On == nil, true,
        "plugins: a refused module isn't made")

    -- Options: what would break the Modules page is refused as it's set.
    local function options(list)
        return function() plugin.options = list end
    end
    raises(options({ { key = "loud", name = "Loud", requires = "loud" } }), "back to itself",
        "plugins: an option under itself")
    raises(options({ { key = "loud", name = "Loud", requires = "mode" },
        { key = "mode", name = "Mode", choices = { { "a", "A" } }, requires = "loud" } }), "back to itself",
        "plugins: two options under each other")
    raises(options({ { key = "size", name = "Size", min = 10, max = 40, step = 0 } }), "step",
        "plugins: a slider with no step to take")
    raises(options({ { key = "size", name = "Size", min = 10, max = 40, format = "%d of %d" } }), "format",
        "plugins: a format that takes more than the value")
    raises(options({ { key = "size", name = "Size", min = 30, max = 40 } }), "between",
        "plugins: a default outside its slider")
    raises(options({ { key = "size", name = "Size", min = 10, max = 1 / 0 } }), "min under max",
        "plugins: a slider without an end")
    plugin.options = {
        { key = "loud", name = "Loud" },
        { key = "mode", name = "Mode", choices = { { "a", "A" }, { "b", "B" } }, requires = "loud" },
        { key = "size", name = "Size", min = 10, max = 40, step = 2, format = "%d%%", requires = "mode" },
    }
    eq(#real.options, 3, "plugins: options under one another in a line are fine")

    -- A timer: the plugin's own table, with our timer out of reach.
    local timer = kit.Timer(plugin)
    eq(real.timers ~= nil and timer ~= real.timers[1], true, "plugins: a timer isn't Core's own")
    eq(timer.module == nil and timer.handle == nil and getmetatable(timer) == false, true,
        "plugins: nor a way to the module behind it")
    eq(type(timer.Start) == "function" and type(timer.Cancel) == "function"
        and type(timer.IsPending) == "function", true, "plugins: a timer has its three methods")
    raises(function() timer.Start = nil end, "read only", "plugins: a timer is read only")
    raises(function() kit.Timer() end, "needs your module", "plugins: a timer needs a module")
    raises(function() kit.Timer({}) end, "needs your module", "plugins: and not any table")
    raises(function() kit.Timer(real) end, "needs your module", "plugins: nor Core's module, were it found")
    local ran = {}
    local function count(key)
        return function() ran[key] = (ran[key] or 0) + 1 end
    end
    eq(timer:Start(1, count("early")), false, "plugins: a timer doesn't start before login")
    eq(waiting(), 0, "plugins: and nothing waits")

    -- Coalesce: the same, as a function.
    local queue, cancel = kit.Coalesce(count("burst"), 0.5, plugin)
    eq(type(queue) == "function" and type(cancel) == "function", true, "plugins: coalesce gives queue and cancel")
    raises(function() kit.Coalesce(count("x"), 0.5) end, "needs your module", "plugins: coalesce needs a module")
    raises(function() kit.Coalesce("x", 0.5, plugin) end, "Coalesce%(fn", "plugins: coalesce needs a function")
    raises(function() kit.Coalesce(count("x"), -1, plugin) end, "Coalesce%(fn", "plugins: and a delay from 0")
    local boom = kit.Coalesce(function() error("burst broke") end, 0, plugin)
    queue()
    eq(waiting(), 0, "plugins: nothing is queued before login")

    -- A map layer: made with the module, so it can come off with it.
    local fill
    local layer = kit.NewMapLayer(function(mapID, add) return fill(mapID, add) end, plugin)
    local ours = layers[1]
    eq(layer ~= ours and layer.fill == nil and layer.pins == nil and getmetatable(layer) == false, true,
        "plugins: a layer isn't MapPins' own")
    raises(function() layer.Enable = nil end, "read only", "plugins: a layer is read only")
    raises(function() kit.NewMapLayer(function() end) end, "needs your module", "plugins: a layer needs a module")
    raises(function() kit.NewMapLayer("fill", plugin) end, "NewMapLayer%(fill", "plugins: and a function")
    eq(layer:Enable() == false and ours.on == false, true, "plugins: a layer stays off while the module is")

    -- Events, hooks, and chat lines before login: nothing is heard, and nothing errors.
    eq(plugin:On("PLAYER_MONEY", count("money")), false, "plugins: no event while the module is off")
    eq(registered("PLAYER_MONEY"), false, "plugins: the game isn't asked for it either")
    eq(reports(0, function() plugin:Print("early") end), true, "plugins: a chat line before login is dropped")
    eq(plugin.db, nil, "plugins: no settings before login")

    local calls = {}
    function plugin:OnEnable()
        calls[#calls + 1] = "enable"
        calls.heard = self:On("PLAYER_MONEY", count("money"))
        calls.missing = self:On("NO_SUCH_EVENT", count("missing"))
        layer:Enable()
    end
    function plugin:OnDisable()
        calls[#calls + 1] = "disable"
        timer:Start(1, count("afterOff")) -- the module is off by now
    end

    ForeverPlusPlusDB, ForeverPlusPlusCharDB = nil, nil
    core.Start()

    -- Each is made once, while the plugin loads: one made in OnEnable would pile up.
    raises(function() kit.Timer(plugin) end, "while the plugin loads", "plugins: no new timer after login")
    raises(function() kit.Coalesce(count("x"), 0, plugin) end, "while the plugin loads",
        "plugins: no new coalesce after login")
    raises(function() kit.NewMapLayer(function() end, plugin) end, "while the plugin loads",
        "plugins: no new layer after login")
    eq(#real.timers == 3 and #layers == 1, true, "plugins: a refused one makes nothing")

    -- Settings: a table of the plugin's own over Store's, taking only its defaults' keys and types.
    local db = plugin.db
    eq(db ~= real.db and getmetatable(db) == false and db == plugin.db, true, "plugins: db isn't Store's table")
    eq(db.size == 20 and db.mode == "a" and db.enabled == false and db.nope == nil, true,
        "plugins: db reads the module's settings")
    db.size = 30
    eq(real.db.size, 30, "plugins: db saves a setting")
    db.size = nil
    eq(real.db.size, 20, "plugins: nil puts the default back")
    db.seen = { fresh = true }
    eq(real.db.seen.fresh, true, "plugins: db saves data")
    raises(function() db.size = "big" end, "takes a number", "plugins: a setting keeps its type")
    raises(function() db.size = 1 / 0 end, "takes a number", "plugins: and stays a number that saves")
    raises(function() db.seen = 5 end, "takes a table", "plugins: data stays a table")
    raises(function() db.nope = 1 end, "has no", "plugins: no setting outside the defaults")
    raises(function() db[{}] = 1 end, "has no", "plugins: nor one under a table")
    raises(function() db.enabled = true end, "player's", "plugins: enabled is the player's")
    eq(real.db.size == 20 and real.db.enabled == false, true, "plugins: a refused write changes nothing")

    -- Still off: nothing a plugin starts runs.
    eq(timer:Start(1, count("off")), false, "plugins: a timer doesn't start while the module is off")
    queue()
    eq(plugin:On("PLAYER_MONEY", count("money")), false, "plugins: still no event while it's off")
    eq(waiting() == 0 and layer:Enable() == false, true, "plugins: and nothing waits or shows")

    core.SetEnabled("MyAddonThing", true)
    eq(calls[1] == "enable" and calls.heard == true and calls.missing == false, true,
        "plugins: On says whether it listens, and skips an event the client lacks")
    eq(ours.on, true, "plugins: a layer goes on with the module")
    fire("PLAYER_MONEY")
    eq(ran.money, 1, "plugins: its event is heard while it's on")

    -- Wrong arguments are the plugin's mistake: an error in its own code, before Core sees them.
    raises(function() plugin:On(nil, count("x")) end, PREFIX .. "call it as module:On", "plugins: On without an event")
    raises(function() plugin:On("PLAYER_XP_UPDATE") end, "module:On", "plugins: On without a function")
    raises(function() plugin.On({}, "PLAYER_XP_UPDATE", count("x")) end, "module:On", "plugins: On on another table")
    eq(registered("PLAYER_XP_UPDATE"), false, "plugins: a refused On listens to nothing")
    raises(function() plugin:Hook({}, "Method") end, "module:Hook", "plugins: Hook without a function")
    raises(function() plugin:Hook("Global", "fn") end, "module:Hook", "plugins: Hook on a global without one")
    raises(function() plugin:HookScript({}, "OnShow") end, "module:HookScript", "plugins: HookScript without one")
    raises(function() plugin:HookScript(5, "OnShow", count("x")) end, "module:HookScript",
        "plugins: HookScript on what isn't a frame")
    raises(function() plugin:TooltipPostCall(1) end, "module:TooltipPostCall", "plugins: TooltipPostCall without one")
    raises(function() plugin:Print(5) end, "module:Print", "plugins: Print without text")
    eq(reports(0, function() plugin:HookScript(nil, "OnShow", count("x")) end), true,
        "plugins: a frame that isn't there is skipped")
    eq(reports(0, function() plugin:Hook({ Method = function() end }, "Method", count("x")) end), true,
        "plugins: a good hook")
    eq(real.hooked ~= nil and plugin.hooked == nil and plugin.timers == nil and plugin.events == nil, true,
        "plugins: the handle shows none of the module's own fields")

    -- A timer while the module is on, with the plugin's function guarded.
    raises(function() timer:Start("soon", count("x")) end, "timer:Start", "plugins: Start needs seconds")
    raises(function() timer:Start(1 / 0, count("x")) end, "timer:Start", "plugins: that end")
    raises(function() timer:Start(-1, count("x")) end, "timer:Start", "plugins: from 0")
    raises(function() timer:Start(1) end, "timer:Start", "plugins: Start needs a function")
    raises(function() timer.Start({}, 1, count("x")) end, "timer:Start", "plugins: Start on another table")
    eq(timer:IsPending(), false, "plugins: a refused Start leaves nothing waiting")
    eq(timer:Start(1, count("timed")) and timer:IsPending(), true, "plugins: a timer starts while the module is on")
    wait(1)
    eq(ran.timed == 1 and timer:IsPending() == false, true, "plugins: and runs once")
    timer:Start(1, function() error("timer broke") end)
    eq(reports(1, function() wait(1) end), true, "plugins: a timer function's error is reported, not raised")
    timer:Start(1, count("cancelled"))
    timer:Cancel()
    wait(1)
    eq(ran.cancelled, nil, "plugins: Cancel drops the run")
    queue()
    queue()
    wait(0.5)
    eq(ran.burst, 1, "plugins: coalesce runs once for a burst")
    boom()
    eq(reports(1, function() wait(0) end), true, "plugins: a coalesced function's error is reported")
    queue()
    cancel()
    wait(0.5)
    eq(ran.burst, 1, "plugins: its cancel drops the run")

    -- Icons: MapPins gets a checked copy, and the plugin's functions get its own tables back.
    local added = {}
    local function draw(mapID)
        added = {}
        ours.fill(mapID, function(x, y, icon) added[#added + 1] = { x = x, y = y, icon = icon } end)
    end
    local clicked = {}
    local theirs = {
        atlas = "Waypoint", size = 5000, title = "A spot", kind = "Spot", color = { 1, 0.5, 0 }, alpha = 7,
        round = 1, waypoint = "yes", shiftHint = "forget it", mine = "kept", cvar = "someCVar", ring = true,
        lines = function(info)
            return { "gold", kit.Tooltip.Note("gray"), kit.Tooltip.Pair("Seen", 3), 5, { 6 }, { "plain", "red" },
                info.mine }
        end,
        shiftClick = function(pin, button) clicked[#clicked + 1] = { pin = pin, button = button } end,
        ctrlClick = function() error("click broke") end,
    }
    local keptAdd
    fill = function(mapID, add)
        keptAdd = add
        add(0.25, 0.75, theirs)
        add(0.5, 0.5, { texture = 134400, size = 1, title = "Small", lines = { "one", {}, "two" } })
    end
    eq(reports(0, function() draw(7) end), true, "plugins: a layer draws")
    local icon = added[1] and added[1].icon or {}
    eq(#added == 2 and added[1].x == 0.25 and added[1].y == 0.75, true, "plugins: each icon reaches the map")
    eq(icon ~= theirs and icon.mine == nil and icon.cvar == nil and icon.ring == nil, true,
        "plugins: an icon is a copy with only the fields it may have")
    eq(icon.size == 128 and icon.alpha == 1 and added[2].icon.size == 4, true, "plugins: size and alpha in bounds")
    eq(icon.round == true and icon.waypoint == true and icon.desaturated == false, true, "plugins: flags are true or false")
    eq(icon.color ~= theirs.color and icon.color[2] == 0.5 and icon.title == "A spot" and icon.kind == "Spot", true,
        "plugins: its color is copied, its text passed on")
    local lines = icon.lines(icon)
    eq(#lines == 5 and lines[1] == "gold" and lines[2][1] == "gray" and lines[3].right == "3"
        and lines[4] == "plain" and lines[5] == "kept", true,
        "plugins: lines are cleaned, and their function gets the plugin's own info")
    eq(#added[2].icon.lines == 2 and added[2].icon.texture == 134400, true, "plugins: a list of lines is copied")
    local frame = { mapID = 7, x = 0.25, y = 0.75, info = icon, texture = {} }
    icon.shiftClick(frame, "RightButton")
    local got = clicked[1] or {}
    eq(got.pin ~= frame and got.pin.info == theirs and got.pin.texture == nil and got.pin.mapID == 7
        and got.pin.x == 0.25 and got.button == "RightButton", true,
        "plugins: a click gets where the icon is, not the pin's frame")
    eq(reports(1, function() icon.ctrlClick(frame) end), true, "plugins: a click's error is reported, not raised")
    theirs.lines = function() error("lines broke") end
    draw(7)
    local broken
    eq(reports(1, function() broken = added[1].icon.lines() end) and #broken == 0, true,
        "plugins: lines that break give none")
    raises(function() keptAdd(0.1, 0.1, theirs) end, "inside fill", "plugins: add kept past fill does nothing")
    eq(#added, 2, "plugins: and adds no icon")

    -- A bad icon is the plugin's mistake: reported from its fill, and never given to MapPins.
    for what, bad in pairs({
        ["no size"] = { atlas = "a", title = "t" },
        ["no art"] = { size = 16, title = "t" },
        ["no title"] = { atlas = "a", size = 16 },
        ["a size that isn't a number"] = { atlas = "a", size = 0 / 0, title = "t" },
        ["a click that isn't a function"] = { atlas = "a", size = 16, title = "t", click = true },
        ["lines that aren't a list"] = { atlas = "a", size = 16, title = "t", lines = "text" },
        ["a color that isn't one"] = { atlas = "a", size = 16, title = "t", color = { 1, "g", 0 } },
    }) do
        fill = function(_, add) add(0.5, 0.5, bad) end
        eq(reports(1, function() draw(7) end) and #added == 0, true, "plugins: an icon with " .. what)
    end
    fill = function(_, add) add("left", 0.5, theirs) end
    eq(reports(1, function() draw(7) end) and #added == 0, true, "plugins: an icon without a place")
    fill = function(_, add) add(0.5, 0.5) end
    eq(reports(1, function() draw(7) end) and #added == 0, true, "plugins: an icon without info")
    fill = function() error("fill broke") end
    eq(reports(1, function() draw(7) end), true, "plugins: a fill's error is reported, not raised into the map")
    layer:Refresh()
    eq(ours.refreshed, 1, "plugins: Refresh passes on")
    raises(function() layer.Refresh({}) end, "layer:Refresh", "plugins: a layer method on another table")

    -- The rest of the kit: bad arguments answer, or are named, and never reach our code.
    local a, b = kit.SetWaypoint(1, "x", 0.5)
    eq(a == false and b == "range", true, "plugins: a waypoint without numbers")
    a, b = kit.SetWaypoint({}, 0.5, 0.5)
    eq(a == false and b == "zone", true, "plugins: a waypoint without a map")
    eq(kit.SetWaypoint(1, 0.5, 0.5, {}) == true and waypoint[1] == 1 and waypoint[4] == nil, true,
        "plugins: a waypoint, with a name only when it's text")
    local answer = "unset"
    eq(reports(1, function() answer = kit.SetWaypoint(13, 0.5, 0.5) end) and answer == nil, true,
        "plugins: an error of ours is reported and returns nil")
    eq(kit.IsContinent(5) == false and kit.IsContinent() == false and kit.IsContinent({ mapType = 2 }), true,
        "plugins: IsContinent takes map info only")
    eq(kit.HasEvent() == false and kit.HasEvent({}) == false and kit.HasEvent("PLAYER_MONEY"), true,
        "plugins: HasEvent takes a name only")
    raises(function() kit.AfterCombat() end, "AfterCombat", "plugins: AfterCombat needs a function")
    eq(reports(1, function() kit.AfterCombat(function() error("combat broke") end) end), true,
        "plugins: its function's error is reported")
    raises(function() kit.Tooltip.Note() end, "Tooltip.Note", "plugins: a tooltip line needs text")
    raises(function() kit.Tooltip.Pair("Label", {}) end, "Tooltip.Pair", "plugins: both halves of a pair")
    eq(kit.Tooltip.Detail(5)[1], "5", "plugins: a number makes a line too")
    raises(function() kit.Tooltip.Note = nil end, "read only", "plugins: the kit's Tooltip is read only")
    raises(function() kit.QuestieDB.OnReady() end, "OnReady", "plugins: OnReady needs a function")
    local function ready() error("ready broke") end
    kit.QuestieDB.OnReady(ready)
    eq(readyFn ~= nil and readyFn ~= ready and reports(1, readyFn), true, "plugins: OnReady's function is guarded")
    eq(reports(0, function() kit.QuestieDB.Cancel() end) and readyFn ~= nil, true, "plugins: Cancel without one")
    kit.QuestieDB.Cancel(ready)
    eq(readyFn, nil, "plugins: Cancel finds the function OnReady was given")
    eq(kit.QuestieDB.IsReady() == true and reports(1, function() answer = kit.QuestieDB.Quest(1) end)
        and answer == nil, true, "plugins: a QuestieDB call that breaks returns nil")

    -- Off: everything the plugin had going stops with the module, as a built-in module's does.
    timer:Start(5, count("late"))
    queue()
    core.SetEnabled("MyAddonThing", false)
    eq(calls[2], "disable", "plugins: its OnDisable still runs")
    eq(ours.on, false, "plugins: its layer comes off the map by itself")
    eq(registered("PLAYER_MONEY"), false, "plugins: its events stop")
    wait(10)
    eq(ran.late == nil and ran.afterOff == nil and ran.burst == 1, true,
        "plugins: no timer runs after it, not even one started in OnDisable")
    eq(plugin:On("PLAYER_MONEY", count("money")) == false and registered("PLAYER_MONEY") == false, true,
        "plugins: and it can't listen again until it's on")
    eq(#reported, 18,"plugins: nothing else went to the error handler")
end
