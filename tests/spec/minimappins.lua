-- MinimapPins: the minimap's shape (round, or square while GetMinimapShape says so), spots on and
-- at its edge for each, and word to listeners and LibDBIcon when the shape changes.
local T = ...
local ns, eq = T.ns, T.eq

-- Cached at load, so stubbed first: a minimap 200 across.
Minimap = { GetWidth = function() return 200 end }
T.load("Lib/MinimapPins")
local Pins = ns.MinimapPins

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
