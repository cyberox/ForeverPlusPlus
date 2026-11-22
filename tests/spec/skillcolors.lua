-- Professions' gathering colors: how hard a node or a skin is at a skill (red, orange, yellow,
-- green, gray), at every edge between two colors, and the Skinning a creature's level takes.
local T = ...
local ns, eq, ok = T.ns, T.eq, T.ok

local Professions = ns.Professions
local color = Professions.Difficulty

-- A node that takes 75 (Silver Vein). Each color is one table, so the same color is the same value.
local red, orange, yellow = color(nil, 75), color(75, 75), color(100, 75)
local green, gray = Professions.STANDARD, Professions.TRIVIAL
local all = { red, orange, yellow, green, gray }
for i = 1, #all do
    for j = i + 1, #all do
        ok(all[i] ~= all[j], "difficulty: colors " .. i .. " and " .. j .. " differ")
    end
end

eq(color(nil, 1), red, "difficulty: without the profession it's red, whatever it takes")
eq(color(0, 75), red, "difficulty: red at no skill")
eq(color(74, 75), red, "difficulty: red one below what it takes")
eq(color(75, 75), orange, "difficulty: orange at what it takes")
eq(color(99, 75), orange, "difficulty: orange one below yellow")
eq(color(100, 75), yellow, "difficulty: yellow 25 past")
eq(color(124, 75), yellow, "difficulty: yellow one below green")
eq(color(125, 75), green, "difficulty: green 50 past")
eq(color(174, 75), green, "difficulty: green one below gray")
eq(color(175, 75), gray, "difficulty: gray 100 past")
eq(color(300, 75), gray, "difficulty: gray from there on")

-- The lowest nodes take 1, so a new gatherer starts on orange.
eq(color(1, 1), orange, "difficulty: skill 1 on a node that takes 1")
eq(color(25, 1), orange, "difficulty: still orange at 25")
eq(color(26, 1), yellow, "difficulty: yellow at 26")
eq(color(101, 1), gray, "difficulty: gray at 101")

-- Yellow is the classic one, not the client's QuestDifficultyColors.difficult (which the test
-- client marks with a string), so "often" stands out from a tooltip's gold title.
eq(yellow.r == 1 and yellow.g == 1 and yellow.b == 0, true, "difficulty: yellow is (1, 1, 0)")
for i, each in ipairs(all) do
    eq(type(each.r) == "number" and type(each.g) == "number" and type(each.b) == "number", true,
        "difficulty: color " .. i .. " has r, g, and b")
end

-- Which creatures can be skinned: a family that never is, then what a corpse taught.
eq(Professions.Skinnable(4006, 3), false, "skinnable: a spider isn't")
eq(Professions.Skinnable(4006, 1), nil, "skinnable: a wolf isn't known either way")
eq(Professions.Skinnable(nil, nil), nil, "skinnable: nothing to go on")
Professions.LearnSkinnable(100, false)
eq(Professions.Skinnable(100, 1), false, "skinnable: a looted corpse that didn't say so")
Professions.LearnSkinnable(100, true)
eq(Professions.Skinnable(100, 1), true, "skinnable: a corpse that says so wins")
Professions.LearnSkinnable(100, false)
eq(Professions.Skinnable(100, 1), true, "skinnable: and stays, whatever a later corpse lacks")
Professions.LearnSkinnable(4006, true)
eq(Professions.Skinnable(4006, 3), true, "skinnable: a corpse beats the family")

-- Skinning: 1 through level 10, then ten a level to 20, then five times the level.
local need = Professions.SkinningNeed
eq(need(1), 1, "skinning: level 1")
eq(need(10), 1, "skinning: level 10 still takes 1")
eq(need(11), 10, "skinning: level 11")
eq(need(15), 50, "skinning: level 15")
eq(need(20), 100, "skinning: level 20")
eq(need(21), 105, "skinning: level 21")
eq(need(60), 300, "skinning: level 60")
eq(need(63), 315, "skinning: a level 63 boss")
-- A higher creature never takes less, across both edges.
local rising = true
for level = 2, 63 do
    rising = rising and need(level) >= need(level - 1)
end
eq(rising, true, "skinning: never falls as the level rises")

-- The two together: a level 20 creature for a skinner at each edge.
eq(color(99, need(20)), red, "skinning: can't skin level 20 at 99")
eq(color(100, need(20)), orange, "skinning: can at 100")
eq(color(200, need(20)), gray, "skinning: gray at 200")
