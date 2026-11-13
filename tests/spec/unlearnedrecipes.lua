-- Professions' recipes the player doesn't know: whether one can be learned now, the Filter menu's
-- filters for them, the search match, the junk the game still knows, and the categories they go
-- under in the recipe list.
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

eq(Professions.LearnWhen("now"), "now", "when: now")
eq(Professions.LearnWhen("rank"), "later", "when: past the rank is later")
eq(Professions.LearnWhen("unknown"), "unknown", "when: its own group without a learn skill")

-- What a trainer's window taught, by the recipe's name.
eq(Professions.TrainerSkill("Copper Chain Belt"), nil, "trainer: nothing before a trainer was seen")
ok(Professions.LearnTrainerSkill("Copper Chain Belt", 35), "trainer: learned")
eq(Professions.TrainerSkill("Copper Chain Belt"), 35, "trainer: remembered")
ok(not Professions.LearnTrainerSkill("Copper Chain Belt", 35), "trainer: the same again changes nothing")
ok(not Professions.LearnTrainerSkill("Journeyman", 0), "trainer: no skill, nothing learned")
ok(not Professions.LearnTrainerSkill("", 35), "trainer: no name")

-- Sources: an item teaches it, or anything else.
eq(Professions.RecipeSource({ item = 2002 }), "item", "source: an item")
eq(Professions.RecipeSource({}), "other", "source: no item")
for _, kind in ipairs(Professions.RECIPE_SOURCES) do
    ok(type(kind.key) == "string" and type(kind.test) == "function", "source kinds: " .. tostring(kind.key))
end

-- The filters.
local function filters(over)
    local f = {
        sources = { item = true, other = true },
        when = { now = true, soon = true, later = true, unknown = true },
        bags = false,
    }
    for key, value in pairs(over or {}) do
        f[key] = value
    end
    return f
end
local plans = { item = 2002, state = "later" }
local trainer = { state = "unknown" }
ok(Professions.PassesUnlearned(plans, filters()), "filter: everything on")
local noItems = filters({ sources = { item = false, other = true } })
ok(not Professions.PassesUnlearned(plans, noItems), "filter: recipe items off hides plans")
ok(Professions.PassesUnlearned(trainer, noItems), "filter: and keeps trainers")
local soonOnly = filters({ when = { now = true, soon = true, later = false } })
ok(not Professions.PassesUnlearned(plans, soonOnly), "filter: later off")
ok(Professions.PassesUnlearned({ item = 1, state = "rank" }, filters({ when = { later = true } })),
    "filter: past the rank counts as later")
ok(not Professions.PassesUnlearned(trainer, filters({ when = { now = true, soon = true, later = true } })),
    "filter: unknown off hides one without a learn skill")
ok(Professions.PassesUnlearned(trainer, filters({ when = { unknown = true } })), "filter: unknown alone keeps it")
local bags = filters({ bags = true })
ok(not Professions.PassesUnlearned(plans, bags), "filter: bags, not carried")
ok(Professions.PassesUnlearned({ item = 1, state = "now", inBags = true }, bags), "filter: bags, carried")

-- The search box.
ok(Professions.MatchesSearch("Iron Buckle", "buck"), "search: any case, anywhere")
ok(not Professions.MatchesSearch("Iron Buckle", "mace"), "search: no match")
ok(Professions.MatchesSearch("Iron Buckle", ""), "search: empty")
ok(Professions.MatchesSearch("Iron (Heavy)", "(heavy"), "search: plain text, not a pattern")

-- Junk.
ok(Professions.IsJunkRecipe({ name = "[DNT] Test Plate" }), "junk: DNT")
ok(Professions.IsJunkRecipe({ name = "Deprecated Shield" }), "junk: deprecated")
ok(Professions.IsJunkRecipe({ name = "" }), "junk: no name")
ok(Professions.IsJunkRecipe({ name = "Rough Stone", disabled = true }), "junk: disabled")
ok(Professions.IsJunkRecipe({ name = "Rough Stone", isDummyRecipe = true }), "junk: dummy")
ok(not Professions.IsJunkRecipe({ name = "Rough Stone" }), "junk: a real recipe")
ok(not Professions.IsJunkRecipe({ name = "Testament Robe" }), "junk: a name starting Test without a space")

-- The categories, as Blizzard's list builds them: Weapons (1) is a header over Axes (2) and
-- Maces (3); Armor (4) holds recipes itself and has Belts (5) under it.
local categories = {
    [1] = { categoryID = 1, name = "Weapons", uiOrder = 1 },
    [2] = { categoryID = 2, name = "Axes", uiOrder = 2, parentCategoryID = 1 },
    [3] = { categoryID = 3, name = "Maces", uiOrder = 1, parentCategoryID = 1 },
    [4] = { categoryID = 4, name = "Armor", uiOrder = 0 },
    [5] = { categoryID = 5, name = "Belts", uiOrder = 0, parentCategoryID = 4 },
}
local function categoryOf(id)
    return categories[id]
end
local recipes = {
    { recipeID = 10, categoryID = 2, name = "Copper Axe", maxTrivialLevel = 50, itemLevel = 10 },
    { recipeID = 11, categoryID = 3, name = "Bronze Mace", maxTrivialLevel = 130, itemLevel = 25 },
    { recipeID = 12, categoryID = 3, name = "Copper Mace", maxTrivialLevel = 50, itemLevel = 11 },
    { recipeID = 13, categoryID = 4, name = "Iron Buckle", maxTrivialLevel = 150, itemLevel = 30 },
    { recipeID = 14, categoryID = 5, name = "Copper Belt", maxTrivialLevel = 90, itemLevel = 15 },
    { recipeID = 15, categoryID = 99, name = "Nowhere", maxTrivialLevel = 1, itemLevel = 1 },
    { recipeID = 16, categoryID = 3, name = "Another Mace", maxTrivialLevel = 50, itemLevel = 11 },
}
local function names(list)
    local out = {}
    for i, node in ipairs(list) do
        out[i] = node.info.name
    end
    return table.concat(out, " ")
end

local top = Professions.RecipeTree(recipes, categoryOf, false)
eq(names(top), "Armor Maces Axes", "tree: headers without recipes left out, by order then name")
eq(names(top[1].categories), "Belts", "tree: a category under a parent with recipes stays under it")
eq(#top[1].recipes, 1, "tree: the parent's own recipe")
local maces = top[2].recipes
eq(maces[1].name, "Bronze Mace", "tree: highest gray level first")
eq(maces[2].name, "Another Mace", "tree: then item level, then name")
eq(maces[3].name, "Copper Mace", "tree: and the last")
local count = 0
for _, node in ipairs(top) do
    count = count + #node.recipes
    for _, child in ipairs(node.categories) do
        count = count + #child.recipes
    end
end
eq(count, 6, "tree: a recipe without a known category left out")

top = Professions.RecipeTree(recipes, categoryOf, true)
eq(names(top), "Armor Weapons", "tree: searching keeps the headers")
eq(names(top[2].categories), "Maces Axes", "tree: with their categories under them")

eq(#Professions.RecipeTree({}, categoryOf, false), 0, "tree: nothing")
