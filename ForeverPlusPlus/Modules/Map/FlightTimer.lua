-- Flight Timer: how long a flight takes. The game doesn't say, so every flight you take is timed
-- and remembered by the game's flight point IDs (the same IDs Points of Interest uses), one time
-- for each pair of flight points. The next time, a bar shows the time left as you fly, and the
-- flight map's tooltip on a flight point shows how long it will take. Each pair is its own time:
-- flights differ each way, and a flight with stops is not the sum of its parts. Times are saved
-- for the whole account, since a flight is the same for every character. Before a route has been
-- flown, Estimated Times gives it the time the game's own flight paths say (ns.Taxi), marked "~".
local _, ns = ...

local ipairs, floor, format, max, min, tonumber = ipairs, math.floor, string.format, math.max, math.min, tonumber
local Enum, GetTime, UnitOnTaxi = Enum, GetTime, UnitOnTaxi
local GetNumRoutes, TaxiGetNodeSlot = GetNumRoutes, TaxiGetNodeSlot
local CreateFrame, UIParent, GameTooltip, PlaySound = CreateFrame, UIParent, GameTooltip, PlaySound

local L = ns.L

local module = ns.NewModule("FlightTimer", L.FLIGHTTIMER_DESC, {
    enabled = true,
    bar = true,
    tooltip = true,
    tooltipStyle = "double", -- "double" (label left, time right), "line", or "gray" (one line)
    estimates = true,
    landingSound = false,
    scale = 100, -- percent
    x = 0, -- the bar's offset from the center of the screen
    y = 250,
    -- Seconds by "fromNodeID>toNodeID". Data, not a setting.
    times = {},
})
module.title = L.FLIGHTTIMER_TITLE
module.category = "map"

module.options = {
    { key = "bar", name = L.FLIGHTTIMER_BAR, description = L.FLIGHTTIMER_BAR_DESC },
    { key = "tooltip", name = L.FLIGHTTIMER_TOOLTIP, description = L.FLIGHTTIMER_TOOLTIP_DESC },
    {
        key = "tooltipStyle", name = L.FLIGHTTIMER_STYLE, description = L.FLIGHTTIMER_STYLE_DESC,
        requires = "tooltip", added = "0.9.0",
        choices = {
            { "double", L.FLIGHTTIMER_STYLE_DOUBLE },
            { "line", L.FLIGHTTIMER_STYLE_LINE },
            { "gray", L.FLIGHTTIMER_STYLE_GRAY },
        },
    },
    {
        key = "estimates", name = L.FLIGHTTIMER_ESTIMATES, description = L.FLIGHTTIMER_ESTIMATES_DESC,
        added = "1.6.0",
    },
    {
        key = "landingSound", name = L.FLIGHTTIMER_LANDING_SOUND,
        description = L.FLIGHTTIMER_LANDING_SOUND_DESC, added = "0.9.0", changed = "1.6.0",
    },
}

local WIDTH, HEIGHT = 208, 16 -- about Blizzard's cast bar
local TOO_SHORT = 3 -- seconds; anything shorter wasn't a flight
local WAIT = 10 -- seconds to wait for a flight to start after asking for it
local LANDING = 5 -- seconds before landing that Sound on Landing plays

local clock = ns.Text.Clock

-- The flight points ----------------------------------------------------------------------------

-- Mainline's flight master API, at a flight master: slots are what the old API counts by, node
-- IDs are the game's own. Filled when the flight map opens.
local nodeOfSlot, slotOfNode, nameOfNode = {}, {}, {}
local current -- the node ID the flight master is at

local function readNodes()
    nodeOfSlot, slotOfNode, nameOfNode, current = {}, {}, {}, nil
    for _, node in ipairs((ns.Taxi.Nodes())) do
        if node.nodeID then
            if node.slotIndex then
                nodeOfSlot[node.slotIndex] = node.nodeID
                slotOfNode[node.nodeID] = node.slotIndex
            end
            nameOfNode[node.nodeID] = node.name
            if Enum.FlightPathState and node.state == Enum.FlightPathState.Current then
                current = node.nodeID
            end
        end
    end
end

-- The times ------------------------------------------------------------------------------------

local function key(from, to)
    return from .. ">" .. to
end

-- How long the flight from one node to another takes, in seconds, if it has been flown.
local function timed(from, to)
    return module.db.times[key(from, to)]
end

-- The flight points a flight from the flight master to a slot passes, from, each stop, then to,
-- as the flight master routes it, or nil when it can't say.
local function routeOf(slot, to)
    if not (slot and current and GetNumRoutes and TaxiGetNodeSlot) then
        return nil
    end
    local count = tonumber(GetNumRoutes(slot))
    if not count or count < 1 then
        return nil
    end
    local hops = { current }
    for hop = 1, count do
        local node = nodeOfSlot[TaxiGetNodeSlot(slot, hop, false)]
        if not node then
            return nil
        end
        hops[#hops + 1] = node
    end
    if hops[#hops] ~= to then
        return nil
    end
    return hops
end

-- How long the flight from the flight master to a node takes: the player's own time once it has
-- been flown, else the estimate from its route (Estimated Times). Also whether it's an estimate,
-- and whether that estimate is the rougher kind, for a flight with stops.
local function flightTime(to, slot)
    local seconds = timed(current, to)
    if seconds then
        return seconds, false, false
    end
    if not module.db.estimates then
        return nil
    end
    -- Without the flight master's route, only a direct path can be assumed: the game takes one
    -- when there is one.
    local estimate, direct = ns.Taxi.FlightEstimate(routeOf(slot, to) or { current, to })
    if estimate then
        return estimate, true, not direct
    end
end

-- A time as the bar and tooltip show it, with "~" before an estimate.
local function timeText(seconds, estimated)
    if estimated then
        return format(L.FLIGHTTIMER_ESTIMATE, clock(seconds))
    end
    return clock(seconds)
end

-- The flight underway ---------------------------------------------------------------------------

-- { from, to, total, estimated, rough, name, asked, started, aborted, warned }, once one is asked
-- for, and `test` for Test Flight's. `total` is the player's time or, with `estimated`, the
-- estimate (`rough` for a flight with stops).
local flight
local lastFlight -- { from, to, seconds } of the flight that last landed, for the public API

local bar, watcher

local function newBar()
    -- The same box Blizzard draws tooltips in, with the fill inside it.
    local frame = ns.Frames.TooltipBox(UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    -- No strata of its own: MEDIUM like Blizzard's cast bar, so windows draw over it.
    local fill = CreateFrame("StatusBar", nil, frame)
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fill:SetStatusBarColor(1, 0.7, 0) -- the cast bar's gold
    fill:SetMinMaxValues(0, 1)
    frame.fill = fill
    frame.name = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.name:SetPoint("LEFT", 4, 0)
    frame.name:SetPoint("RIGHT", -44, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    frame.time = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.time:SetPoint("RIGHT", -4, 0)
    frame:Hide()
    return frame
end

local function place()
    bar:SetScale(module.db.scale / 100)
    ns.EditMode.Place(bar, module.db.x, module.db.y)
end

local function fillTo(fraction)
    bar.fill:SetValue(fraction)
end

-- Stops timing and takes the bar down, unless Edit Mode is showing it for placing.
local function cancel()
    flight = nil
    if watcher then
        watcher:Hide()
    end
    if bar and not ns.EditMode.IsActive() then
        bar:Hide()
    end
end

local function showFlight()
    local elapsed = GetTime() - flight.started
    bar.name:SetText(flight.name or "")
    if flight.total and not (flight.estimated and elapsed > flight.total) then
        local left = max(flight.total - elapsed, 0)
        fillTo(min(elapsed / flight.total, 1))
        bar.time:SetText(timeText(left, flight.estimated))
    else
        -- A flight not flown before, without an estimate or past it: the time so far.
        fillTo(1)
        bar.time:SetText(clock(elapsed))
    end
end

local function finish()
    if flight.started and not flight.aborted then
        local elapsed = GetTime() - flight.started
        if elapsed >= TOO_SHORT and flight.from and flight.to then
            module.db.times[key(flight.from, flight.to)] = floor(elapsed + 0.5)
        end
    end
    local landed = flight.started and not flight.test
    if landed then
        lastFlight = { from = flight.from, to = flight.to,
            seconds = floor(GetTime() - flight.started + 0.5) }
    end
    cancel()
    -- Landed: the public API's FLIGHT_ENDED (Current is nil again).
    if landed then
        ns.Providers.Changed("flights")
    end
end

-- The ready check's sound on the Master channel, so it's heard with sound effects off and, when
-- Sound in Background is on, while tabbed out.
local function playLanding()
    local kit = SOUNDKIT and SOUNDKIT.READY_CHECK
    if kit and PlaySound then
        PlaySound(kit, "Master")
    end
end

-- Sound on Landing: once, a few seconds before a flight of known length lands. A flight too short
-- for that would play it at takeoff, so it stays quiet, and so does a rough estimate, which can
-- be off by more than those few seconds.
local function checkLanding(now)
    if flight.warned or flight.rough or not (flight.total and module.db.landingSound) then
        return
    end
    if flight.total <= LANDING * 2 then
        flight.warned = true
    elseif flight.total - (now - flight.started) <= LANDING then
        flight.warned = true
        playLanding()
    end
end

local function tick()
    if not flight then
        cancel()
        return
    end
    local now = GetTime()
    if flight.test then
        -- A made-up flight (Debug's Test Flight): no taxi to watch, and nothing learned from it.
        if now - flight.started >= flight.total then
            cancel()
        elseif bar:IsShown() then
            showFlight()
        end
        return
    end
    if not flight.started then
        if UnitOnTaxi("player") then
            flight.started = now
            if module.db.bar then
                bar:Show()
            end
            -- Took off: the public API's FLIGHT_STARTED.
            ns.Providers.Changed("flights")
        elseif now - flight.asked > WAIT then
            cancel() -- never took off
        end
        return
    end
    if not UnitOnTaxi("player") then
        finish()
        return
    end
    checkLanding(now)
    if bar:IsShown() then
        showFlight()
    end
end

-- Asking a flight master to go to a slot: what the flight is, before it starts.
local function onTake(slot)
    local to = nodeOfSlot[slot]
    if not (to and current) then
        flight = nil
        return
    end
    local total, estimated, rough = flightTime(to, slot)
    flight = {
        from = current, to = to, total = total, estimated = estimated, rough = rough,
        name = nameOfNode[to], asked = GetTime(),
    }
    watcher:Show()
end

local function onEarlyLanding()
    if flight then
        flight.aborted = true -- the time to somewhere else says nothing about this flight
    end
end

-- The flight map's tooltip ---------------------------------------------------------------------

local adding -- so showing the tooltip again for the new line doesn't add it again

-- The node a tooltip over the flight map is about: the new map's pins carry their node data; the
-- old map's buttons are the slot they're for.
local function nodeOfOwner(owner)
    local data = owner.taxiNodeData
    if data and data.nodeID then
        return data.nodeID
    end
    if owner.nodeID then
        return owner.nodeID
    end
    -- Only the old map's own buttons (TaxiButtonN on TaxiRouteMap): a bag slot or action button
    -- has an ID too.
    local routes = _G.TaxiRouteMap
    if TaxiFrame and TaxiFrame:IsShown() and routes and owner.GetID and owner.GetParent
        and owner:GetParent() == routes then
        return nodeOfSlot[owner:GetID()]
    end
end

local function onTooltipShow(tooltip)
    if adding or not module.db.tooltip or tooltip ~= GameTooltip then
        return
    end
    if not ((FlightMapFrame and FlightMapFrame:IsShown()) or (TaxiFrame and TaxiFrame:IsShown())) then
        return
    end
    local owner = tooltip:GetOwner()
    local to = owner and nodeOfOwner(owner)
    if not (to and current) or to == current then
        return
    end
    local time, estimated = flightTime(to, slotOfNode[to])
    if not time then
        return
    end
    local text = timeText(time, estimated)
    adding = true
    local style = module.db.tooltipStyle
    if style == "line" then
        tooltip:AddLine(format(L.FLIGHTTIMER_TIME_LINE, text), 1, 1, 1)
    elseif style == "gray" then
        tooltip:AddLine(format(L.FLIGHTTIMER_TIME_LINE, text), 0.5, 0.5, 0.5)
    else
        tooltip:AddDoubleLine(L.FLIGHTTIMER_TIME, text, 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show() -- to fit the new line
    adding = false
end

-- Edit Mode -------------------------------------------------------------------------------------

-- In Edit Mode the bar shows even when nobody is flying, so it can be placed.
local function sample(active)
    if flight and flight.started then
        return
    end
    if active then
        bar.name:SetText(L.FLIGHTTIMER_TITLE)
        fillTo(0.6)
        bar.time:SetText(clock(45))
        bar:Show()
    else
        bar:Hide()
    end
end

module.actions = {
    {
        name = L.FLIGHTTIMER_RESET_TIMES,
        button = L.FLIGHTTIMER_RESET_TIMES_BUTTON,
        description = L.FLIGHTTIMER_RESET_TIMES_DESC,
        confirm = L.FLIGHTTIMER_RESET_TIMES_CONFIRM,
        fn = function()
            module.db.times = {}
            ns.Print(L.FLIGHTTIMER_RESET_TIMES_DONE)
        end,
    },
}

-- Debug's Test Flight: the bar counting down a made-up flight, to see it (or record it) without
-- a flight master. Ignored while a real flight is under way.
local TEST_LENGTH = 45
module.debugActions = {
    {
        name = L.FLIGHTTIMER_TEST, button = L.FLIGHTTIMER_TEST_BUTTON,
        description = L.FLIGHTTIMER_TEST_DESC, section = L.DEBUG_SECTION_PREVIEWS,
        fn = function()
            if not (bar and watcher) or (flight and not flight.test) then
                return
            end
            flight = { test = true, name = L.FLIGHTTIMER_TEST_PLACE, total = TEST_LENGTH,
                started = GetTime() }
            bar:Show()
            showFlight()
            watcher:Show()
        end,
    },
    {
        name = L.FLIGHTTIMER_CHECK, button = L.FLIGHTTIMER_CHECK_BUTTON,
        description = L.FLIGHTTIMER_CHECK_DESC, section = L.DEBUG_SECTION_TOOLS,
        fn = function()
            local check = ns.Taxi.CheckEstimates(module.db.times)
            if not check then
                ns.Print(L.FLIGHTTIMER_CHECK_NONE)
                return
            end
            ns.Print(format(L.FLIGHTTIMER_CHECK_RESULT, check.count, check.median, check.worst,
                check.worstRoute, check.speed, ns.Taxi.SPEED))
        end,
    },
}

-- What the public API (API.lua) reads while the module is on.
local provider = {
    -- Seconds the flight between two flight point IDs takes, once it has been flown.
    Time = function(from, to)
        return timed(from, to)
    end,
    -- Estimated seconds of the direct flight between two flight point IDs, from the game's flight
    -- paths, whether or not it has been flown or Estimated Times is on. Nil without a direct path.
    Estimate = function(from, to)
        return (ns.Taxi.FlightEstimate({ from, to }))
    end,
    -- The flight underway: from and to node IDs, its length in seconds (nil the first time it's
    -- flown), the estimate it's counted down by instead the first time (nil without one), and the
    -- seconds since it took off. Nil when not flying.
    Current = function()
        if not (flight and flight.started) or flight.test then
            return nil
        end
        return { from = flight.from, to = flight.to,
            total = not flight.estimated and flight.total or nil,
            estimate = flight.estimated and flight.total or nil,
            elapsed = GetTime() - flight.started }
    end,
    -- Every flight flown: "from>to" -> seconds.
    AllTimes = function()
        return module.db.times
    end,
    -- The flight that last landed: from, to, and its seconds, or nil.
    Last = function()
        return lastFlight
    end,
}

function module:OnEnable()
    ns.Providers.Set("flights", provider)
    if not bar then
        bar = newBar()
        watcher = ns.Frames.Watcher(self, 0.1, tick)
    end
    place()
    self:On("TAXIMAP_OPENED", readNodes)
    self:Hook("TakeTaxiNode", onTake)
    self:Hook("TaxiRequestEarlyLanding", onEarlyLanding)
    self:Hook(GameTooltip, "Show", onTooltipShow)
    self:On("PLAYER_ENTERING_WORLD", cancel) -- a loading screen ends any timing
    ns.EditMode.RegisterModule(self, bar, L.FLIGHTTIMER_TITLE, place, sample)
end

function module:OnDisable()
    ns.Providers.Set("flights", nil)
    if bar then
        ns.EditMode.Unregister(bar)
        cancel()
        bar:Hide()
    end
end

function module:OnOptionChanged(option)
    if option == "bar" and bar and not ns.EditMode.IsActive() then
        -- Turned on mid-flight, the bar shows for the rest of it.
        bar:SetShown(self.db.bar and flight and flight.started and true or false)
    end
end
