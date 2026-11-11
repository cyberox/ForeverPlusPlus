-- Professions' columns at the right end of the recipe rows: where each sits as the others come
-- into use and go, and the recipe's name cut short before them.
local T = ...
local ns, eq, ok = T.ns, T.eq, T.ok

local Professions = ns.Professions

-- A stub region that remembers its last anchor.
local function region()
    local r = { shown = true }
    function r:ClearAllPoints() self.point = nil end
    function r:SetPoint(point, to, toPoint, x) self.point, self.to, self.x = point, to, x end
    function r:Hide() self.shown = false end
    return r
end

-- A stub recipe row: `width` wide, a name `full` wide, and maybe a lock.
local function newRow(width, full, locked)
    local row = {}
    function row:GetWidth() return width end
    row.Label = { GetStringWidth = function() return full end,
        SetWidth = function(self, w) self.width = w end }
    row.SkillUps = { GetWidth = function() return 26 end }
    row.Count = { IsShown = function() return false end, GetStringWidth = function() return 0 end }
    row.LockedIcon = { IsShown = function() return locked or false end, GetWidth = function() return 17 end }
    return row
end

local rows = {}
ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = {
    ForEachFrame = function(_, fn)
        for _, row in ipairs(rows) do
            fn(row)
        end
    end,
} } } }

-- Made out of order, as modules load in any order.
local profit = Professions.NewRowColumn(30, 0, 4)
local icon = Professions.NewRowColumn(10, 14, 2)
local number = Professions.NewRowColumn(20, 20, 2)

local row = newRow(300, 400)
rows[1] = row
local profitText, numberText, mark = region(), region(), region()

-- Alone, the profit sits at the row's end, and the name ends before it.
profit:Use(true)
profit:Place(row, profitText, 50)
eq(profitText.x, -4, "rows: the profit alone is at the end")
eq(profitText.to, row, "rows: anchored to the row")
eq(row.Label.width, 300 - 26 - (4 + 50 + 6), "rows: the name ends before the profit")

-- The number comes into use: the profit moves left of its column, on a row already drawn.
number:Use(true)
eq(profitText.x, -(2 + 20 + 4), "rows: the profit moves left of the number's column")
number:Place(row, numberText)
eq(numberText.x, -2, "rows: the number is at the end")

-- All three: where they always were before the columns could move.
icon:Use(true)
icon:Place(row, mark)
eq(mark.x, -2, "rows: the mark at the end")
eq(numberText.x, -18, "rows: the number left of the mark")
eq(profitText.x, -42, "rows: the profit left of both")
eq(row.Label.width, 300 - 26 - (42 + 50 + 6), "rows: the name ends before the furthest-left one")

-- A column in use takes its space on a row with nothing in it.
number:Place(row, nil)
eq(profitText.x, -42, "rows: an empty column in use keeps its space")

-- Out of use, the columns left of it move right.
number:Use(false)
eq(profitText.x, -(2 + 14 + 4), "rows: the profit moves right when the number goes")
icon:Use(false)
eq(profitText.x, -4, "rows: and to the end when the mark goes too")

-- Nothing on the row: Blizzard's own width, 10 from the end, or the name's own when shorter.
profit:Place(row, nil)
eq(row.Label.width, 300 - 26 - 10, "rows: a long name gets Blizzard's width back")
local short = newRow(300, 80)
rows[2] = short
profit:Place(short, region(), 50)
eq(short.Label.width, 80, "rows: a short name keeps its own width")

-- Left of a disabled recipe's lock.
local locked = newRow(300, 400, true)
rows[3] = locked
local lockedText = region()
profit:Place(locked, lockedText, 50)
eq(lockedText.to, locked.LockedIcon, "rows: anchored to the lock")
eq(lockedText.x, 2 - 4, "rows: left of the lock")
eq(locked.Label.width, 300 - 26 - 17 - (4 + 50 + 6), "rows: the lock takes room from the name too")

-- A row too narrow for the name and everything: the furthest-left goes, the rest stay.
icon:Use(true)
number:Use(true)
local narrow = newRow(120, 400)
rows[4] = narrow
local narrowProfit, narrowNumber = region(), region()
number:Place(narrow, narrowNumber)
profit:Place(narrow, narrowProfit, 50)
ok(not narrowProfit.shown, "rows: no room for the profit, so it's hidden")
ok(narrowNumber.shown, "rows: the number still fits")
eq(narrow.Label.width, 120 - 26 - (18 + 20 + 6), "rows: the name ends before the number")

-- The recipe a row is about, at its best known rank, and the recipe form.
local rank1, rank2 = { recipeID = 1 }, { recipeID = 2 }
eq(Professions.BestRank(rank1), rank1, "rows: without Blizzard's Professions, a recipe is itself")
eq(Professions.BestRank(nil), nil, "rows: no recipe, no rank")
_G.Professions = { GetHighestLearnedRecipe = function(info) return info == rank1 and rank2 or nil end }
eq(Professions.BestRank(rank1), rank2, "rows: a recipe with ranks stands for its best known one")
eq(Professions.BestRank(rank2), rank2, "rows: one Blizzard has no better rank for stays")
local node = { GetData = function() return { recipeInfo = rank1 } end }
eq(Professions.RowRecipe({}, node), rank2, "rows: a row's recipe, from Init's node")
eq(Professions.RowRecipe({ GetElementData = function() return node end }), rank2,
    "rows: or from the row's own element data")
eq(Professions.RowRecipe({ GetElementData = function() return { data = {} } end }), nil,
    "rows: a category header has no recipe")
_G.Professions = nil
eq(Professions.RecipeForm(), nil, "rows: no recipe form before Blizzard's has loaded")
ProfessionsFrame.CraftingPage.SchematicForm = node
eq(Professions.RecipeForm(), node, "rows: the crafting page's recipe form")
