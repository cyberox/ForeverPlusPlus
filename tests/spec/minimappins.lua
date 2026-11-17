-- MinimapPins: zone-map spots as minimap spots and back, what the minimap shows, whether icons
-- could have moved, the tracking menu's entries, the minimap's shape
-- (round, or square while GetMinimapShape says so), spots on and at its edge for each, and word to
-- listeners and LibDBIcon when the shape changes.
local T = ...
local ns, eq = T.ns, T.eq

-- Cached at load, so stubbed first: a minimap 200 across, and what the game says of the player,
-- which the cases below change.
local game = T.game
game.secret = "<secret>"
local SECRET = game.secret
local world = { rotate = false, facing = 0, speed = 0, radius = 100 }
Minimap = { GetWidth = function() return 200 end }
GetCVarBool = function() return world.rotate end
GetPlayerFacing = function() return world.facing end
GetUnitSpeed = function() return world.speed end
C_Minimap = { GetViewRadius = function() return world.radius end }
local cvarChanged
ns.On = function(event, fn)
    if event == "CVAR_UPDATE" then
        cvarChanged = fn
    end
end
T.load("Lib/MinimapPins")
local Pins = ns.MinimapPins

-- Rounded, so sums of sines and cosines compare.
local function near(value)
    return math.floor(value * 1000 + 0.5) / 1000
end

do
    -- A zone 1000 yards wide and 500 tall, the player in its middle, 2 minimap units to a yard.
    local v = { x = 0.5, y = 0.5, width = 1000, height = 500, scale = 2, angle = 0 }
    local right, up = Pins.ToMinimap(v, 0.6, 0.5)
    eq(near(right) .. ":" .. near(up), "200:0", "minimappins: east of the player is right")
    right, up = Pins.ToMinimap(v, 0.5, 0.4)
    eq(near(right) .. ":" .. near(up), "0:100", "minimappins: north of the player (a lower y) is up")
    -- Turned a quarter turn, as when the minimap rotates with a player facing west.
    v.angle = math.pi / 2
    right, up = Pins.ToMinimap(v, 0.6, 0.5)
    eq(near(right) .. ":" .. near(up), "0:-200", "minimappins: a quarter turn puts east at the bottom")
    -- There and back, at several turns.
    for _, angle in ipairs({ 0, 0.7, math.pi / 2, 2.5, math.pi, 5 }) do
        v.angle = angle
        local x, y = Pins.FromMinimap(v, Pins.ToMinimap(v, 0.37, 0.81))
        eq(near(x) .. ":" .. near(y), "0.37:0.81", "minimappins: there and back at a turn of " .. angle)
    end
end

do
    -- What the minimap shows: nil when any part can't be read.
    local where = { map = 1411, x = 0.25, y = 0.75 }
    ns.WorldMap.PlayerPosition = function() return where.map, where.x, where.y end
    ns.WorldMap.Size = function(mapID) return mapID == 1411 and 1000 or nil, 500 end
    local v = Pins.View()
    eq(v and (v.mapID .. ":" .. v.x .. ":" .. v.y .. ":" .. v.width .. ":" .. v.height), "1411:0.25:0.75:1000:500",
        "minimappins: the player's map and spot")
    eq(v and (v.half .. ":" .. v.scale .. ":" .. v.angle), "100:1:0", "minimappins: half its width, units per yard, no turn")
    world.radius = 0
    eq(Pins.View(), nil, "minimappins: no view with no radius")
    world.radius = SECRET
    eq(Pins.View(), nil, "minimappins: nor with a radius the game hides")
    world.radius = 50
    eq(Pins.View().scale, 2, "minimappins: zoomed in, more units to a yard")
    where.map = nil
    eq(Pins.View(), nil, "minimappins: no view where the player has no map")
    where.map = 9
    eq(Pins.View(), nil, "minimappins: nor on a map with no size")
    where.map = 1411

    -- Rotating: read once, and again after a CVar changes.
    eq(Pins.Rotating(), false, "minimappins: not rotating")
    world.rotate, world.facing = true, 1.5
    eq(Pins.Rotating(), false, "minimappins: the setting is kept until a CVar changes")
    cvarChanged()
    eq(Pins.Rotating(), true, "minimappins: read again after a CVar changes")
    eq(Pins.View().angle, 1.5, "minimappins: turned by the player's facing while it rotates")
    world.facing = SECRET
    eq(Pins.View(), nil, "minimappins: no view while the facing is hidden")
    world.facing = 1.5
end

do
    -- Motion: whether icons could have moved since the last look.
    local moved = Pins.NewMotion()
    world.speed = 7
    eq(moved(), true, "motion: moving")
    world.speed = SECRET
    eq(moved(), true, "motion: a speed the game hides counts as moving")
    world.speed = nil
    eq(moved(), true, "motion: so does no speed at all")
    world.speed = 0
    eq(moved(), true, "motion: standing still, the first facing seen is new")
    eq(moved(), false, "motion: standing still and facing the same way")
    world.facing = 2
    eq(moved(), true, "motion: turned, while the minimap rotates")
    world.facing = SECRET
    eq(moved(), true, "motion: a facing the game hides counts as turned")
    world.facing = 2
    eq(moved(), true, "motion: and isn't kept, so the next one read is new")
    world.rotate = false
    cvarChanged()
    world.facing = 3
    eq(moved(), false, "motion: turning doesn't move icons on a minimap that doesn't rotate")
end

do
    -- The tracking menu's entries, skipping what isn't one.
    local seen = {}
    Pins.EachTracking(function(info, index) seen[#seen + 1] = index .. "=" .. info.spellID end)
    eq(#seen, 0, "tracking: nothing on a client without the list")
    local list = { { spellID = 2383 }, false, { spellID = 2580 } }
    C_Minimap.GetNumTrackingTypes = function() return #list end
    C_Minimap.GetTrackingInfo = function(i) return list[i] end
    Pins.EachTracking(function(info, index) seen[#seen + 1] = index .. "=" .. info.spellID end)
    eq(table.concat(seen, ","), "1=2383,3=2580", "tracking: each entry with its index, the empty one skipped")
end

do
    eq(Pins.Square(), false, "minimappins: round without GetMinimapShape")
    eq(Pins.Inside(80, 80), false, "minimappins: a corner is off a round minimap")
    eq(Pins.Inside(60, 60), true, "minimappins: inside the circle")
    local right, up = Pins.ToEdge(300, 400)
    eq(right == 60 and up == 80, true, "minimappins: the edge of a circle")

    GetMinimapShape = function() return "SQUARE" end
    eq(Pins.Square(), true, "minimappins: square while GetMinimapShape says so")
    eq(Pins.Inside(80, 80), true, "minimappins: a corner is on a square minimap")
    eq(Pins.Inside(80, 80, 30), false, "minimappins: but not inset from its edge")
    right, up = Pins.ToEdge(200, 100)
    eq(right == 100 and up == 50, true, "minimappins: the edge of a square")
    right, up = Pins.ToEdge(0, 0)
    eq(right == 0 and up == 0, true, "minimappins: the middle stays put")

    GetMinimapShape = function() return "ROUND" end
    eq(Pins.Square(), false, "minimappins: round when it says ROUND")
    GetMinimapShape = nil
end

do
    local heard = 0
    local function listener()
        heard = heard + 1
    end
    Pins.OnShapeChanged(listener, true)
    Pins.ShapeChanged()
    eq(heard, 1, "minimappins: a listener hears the shape change")
    Pins.OnShapeChanged(listener, false)
    Pins.ShapeChanged()
    eq(heard, 1, "minimappins: not once it stops listening")

    -- LibDBIcon places its buttons again when its radius is set, to what it is.
    local icons, placed = { radius = 5 }, nil
    function icons:SetButtonRadius(radius)
        placed = radius
    end
    LibStub = setmetatable({}, {
        __call = function(_, name, silent)
            if name == "LibDBIcon-1.0" and silent then
                return icons
            end
        end,
    })
    Pins.ShapeChanged()
    eq(placed, 5, "minimappins: LibDBIcon places its buttons again")
    icons.radius = nil
    placed = nil
    Pins.ShapeChanged()
    eq(placed, nil, "minimappins: not without a radius to keep")
end
