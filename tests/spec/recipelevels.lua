-- Professions' recipe levels: where a recipe turns yellow, green, and gray, the color they give at
-- a skill, and Skill Bar's layout of them.
local T = ...
local ns, eq, ok, near = T.ns, T.eq, T.ok, T.near

local Professions = ns.Professions
local D = Professions.DIFFICULTY

-- The numbers match Enum.TradeskillRelativeDifficulty's.
eq(D.OPTIMAL, 0, "levels: orange is Optimal")
eq(D.MEDIUM, 1, "levels: yellow is Medium")
eq(D.EASY, 2, "levels: green is Easy")
eq(D.TRIVIAL, 3, "levels: gray is Trivial")

-- Rough Grinding Stone on build 70888: yellow 45, gray 85, so green at 65 (Classic's 25/45/65/85).
local stone = Professions.RecipeLevels(45, 85)
eq(stone.yellow, 45, "levels: yellow as given")
eq(stone.green, 65, "levels: green halfway")
eq(stone.gray, 85, "levels: gray as given")
-- An odd sum rounds down.
eq(Professions.RecipeLevels(45, 80).green, 62, "levels: green rounds down")
-- Yellow at gray: orange straight to gray.
local flat = Professions.RecipeLevels(100, 100)
eq(flat.green, 100, "levels: no yellow or green")
-- Numbers that don't make sense.
eq(Professions.RecipeLevels(90, 85), nil, "levels: yellow past gray")
eq(Professions.RecipeLevels(nil, 85), nil, "levels: no yellow")
eq(Professions.RecipeLevels(0, 85), nil, "levels: yellow of 0")
eq(Professions.RecipeLevels(45, nil), nil, "levels: no gray")

-- The color at a skill, at each edge.
eq(Professions.LevelDifficulty(stone, 1), D.OPTIMAL, "levels: orange at 1")
eq(Professions.LevelDifficulty(stone, 44), D.OPTIMAL, "levels: orange below yellow")
eq(Professions.LevelDifficulty(stone, 45), D.MEDIUM, "levels: yellow at yellow")
eq(Professions.LevelDifficulty(stone, 64), D.MEDIUM, "levels: yellow below green")
eq(Professions.LevelDifficulty(stone, 65), D.EASY, "levels: green at green")
eq(Professions.LevelDifficulty(stone, 84), D.EASY, "levels: green below gray")
eq(Professions.LevelDifficulty(stone, 85), D.TRIVIAL, "levels: gray at gray")
eq(Professions.LevelDifficulty(stone, 300), D.TRIVIAL, "levels: gray past it")
eq(Professions.LevelDifficulty(flat, 99), D.OPTIMAL, "levels: flat recipe orange")
eq(Professions.LevelDifficulty(flat, 100), D.TRIVIAL, "levels: flat recipe gray")

-- The bar: 20 points either side (half of yellow to gray), so 25 to 105, four equal parts.
local bar = Professions.LevelBar(stone, 55)
eq(bar.from, 25, "bar: starts before yellow")
eq(bar.to, 105, "bar: ends after gray")
eq(#bar.segments, 4, "bar: four colors")
local want = { { D.OPTIMAL, 0, 0.25, 25 }, { D.MEDIUM, 0.25, 0.5, 45 }, { D.EASY, 0.5, 0.75, 65 },
    { D.TRIVIAL, 0.75, 1, 85 } }
for i, segment in ipairs(want) do
    eq(bar.segments[i][1], segment[1], "bar: color " .. i)
    near(bar.segments[i][2], segment[2], "bar: left " .. i)
    near(bar.segments[i][3], segment[3], "bar: right " .. i)
    eq(bar.segments[i][4], segment[4], "bar: level " .. i)
end
near(bar.marker, 0.375, "bar: marker at the skill")
eq(Professions.LevelBar(stone, 1).marker, 0, "bar: marker held at the start")
eq(Professions.LevelBar(stone, 300).marker, 1, "bar: marker held at the end")
eq(Professions.LevelBar(stone).marker, nil, "bar: no skill, no marker")

-- A short recipe still shows a few points either side.
local short = Professions.LevelBar(Professions.RecipeLevels(50, 54), 52)
eq(short.from, 45, "bar: at least 5 before yellow")
eq(short.to, 59, "bar: at least 5 after gray")

-- Orange straight to gray: two parts, no yellow or green.
local two = Professions.LevelBar(flat, 100)
eq(#two.segments, 2, "bar: flat recipe has two colors")
eq(two.segments[1][1], D.OPTIMAL, "bar: flat recipe orange first")
eq(two.segments[2][1], D.TRIVIAL, "bar: flat recipe gray next")
near(two.segments[2][2], 0.5, "bar: flat recipe halves")
ok(two.marker == 0.5, "bar: flat recipe marker at gray")
