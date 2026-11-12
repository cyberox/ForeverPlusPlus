-- Professions' recipes the player doesn't know: whether one can be learned now, the list of them
-- for the open profession, and which profession the known recipes belong to.
local T = ...
local ns, eq, ok = T.ns, T.eq, T.ok

local Professions = ns.Professions
local state = Professions.LearnState

eq(state(60, 75, 150, 25), "now", "learn: skill past the learn skill")
eq(state(75, 75, 150, 25), "now", "learn: at the learn skill")
eq(state(90, 75, 150, 25), "soon", "learn: within soon")
eq(state(100, 75, 150, 25), "soon", "learn: soon's edge")
eq(state(101, 75, 150, 25), "later", "learn: past soon")
eq(state(155, 140, 150, 25), "rank", "learn: past the rank's most")
eq(state(155, 140, nil, 25), "soon", "learn: no rank known")
eq(state(nil, 140, 150, 25), "unknown", "learn: no learn skill")
eq(state(100, nil, 150, 25), "unknown", "learn: no skill")

-- Made-up entries in Data.lua's shape: { yellow, gray, line, spell, item, learn }.
local BS, LW = 164, 165
local recipes = {
    [1] = { 15, 55, BS, 101 },                 -- trainer, known
    [2] = { 90, 130, BS, 102, 2002, 60 },      -- item, learn 60
    [3] = { 95, 125, BS, 103, 2003, 120 },     -- item, learn 120
    [4] = { 40, 80, BS, 104 },                 -- trainer
    [5] = { 200, 240, BS, 105, 2005, 175 },    -- item, past the rank
    [6] = { 100, 140, BS, 106, 2006 },         -- item without a learn skill
    [7] = { 50, 90, BS, 107, 2007, 30 },       -- named like the known recipe
    [8] = { 60, 100, BS, 108 },                -- trainer twin of 9
    [9] = { 60, 100, BS, 109, 2009, 50 },      -- item twin of 8
    [10] = { 20, 60, BS, 110, 2010, 10 },      -- a spell the game doesn't name
    [11] = { 30, 70, LW, 111, 2011, 1 },       -- another profession
}
local names = {
    [101] = "Rough Stone", [102] = "Bronze Mace", [103] = "Iron Buckle", [104] = "Copper Belt",
    [105] = "Mithril Spurs", [106] = "Steel Plate", [107] = "Rough Stone", [108] = "Twin",
    [109] = "Twin", [111] = "Leather Thing",
}
local function nameOf(spell)
    return names[spell]
end
local known, knownNames = { [1] = true }, { ["Rough Stone"] = true }
local options = { skill = 75, max = 150, soon = 50, noItems = true }

local list = Professions.UnknownRecipes(recipes, BS, known, knownNames, nameOf, options)
local order = {}
for i, recipe in ipairs(list) do
    order[i] = recipe.ability
end
eq(table.concat(order, " "), "9 2 3 5 6 4", "unknown: sorted by state, then skill or yellow, items over twins")
eq(list[1].state, "now", "unknown: learn 50 at 75 is now")
eq(list[3].state, "soon", "unknown: learn 120 at 75 is soon")
eq(list[4].state, "rank", "unknown: learn 175 past 150")
eq(list[5].state, "unknown", "unknown: an item without a learn skill")
eq(list[6].state, "noitem", "unknown: a recipe no item teaches")
eq(list[1].item, 2009, "unknown: the item kept")
eq(list[1].name, "Twin", "unknown: the name the game gives")

-- Without recipes no item teaches.
options.noItems = false
list = Professions.UnknownRecipes(recipes, BS, known, knownNames, nameOf, options)
eq(#list, 5, "unknown: trainer recipes left out")
for _, recipe in ipairs(list) do
    ok(recipe.item ~= nil, "unknown: only items left: " .. recipe.name)
end

-- The learn skill read from the item's tooltip, for an item without one in the tables.
options.learnOf = function(item)
    return item == 2006 and 80 or nil
end
list = Professions.UnknownRecipes(recipes, BS, known, knownNames, nameOf, options)
local steel
for _, recipe in ipairs(list) do
    if recipe.ability == 6 then
        steel = recipe
    end
end
eq(steel.learn, 80, "unknown: learn skill from learnOf")
eq(steel.state, "soon", "unknown: and its state")

-- The profession most known abilities are in.
eq(Professions.LineOfAbilities(recipes, { 1, 2, 11 }), BS, "line: the most")
eq(Professions.LineOfAbilities(recipes, { 11 }), LW, "line: one")
eq(Professions.LineOfAbilities(recipes, { 999 }), nil, "line: none in the data")
eq(Professions.LineOfAbilities(recipes, {}), nil, "line: nothing known")
