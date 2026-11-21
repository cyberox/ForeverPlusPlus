-- Professions' Data.lua: every recipe of every profession, from SkillLineAbility, keyed by its ID,
-- which the game's recipe info gives as skillLineAbilityID: the skill it turns yellow and gray at
-- (TrivialSkillLineRankLow and TrivialSkillLineRankHigh), its profession's skill line, its spell,
-- and the item that teaches it with the skill that item needs, when there is one. SkillLine names
-- each profession, for the comments. Only rows with a yellow and a gray level are written, and only
-- those whose yellow level isn't past gray. The file also lists the retired recipe categories
-- (see RETIRED_CATEGORY).
--
-- The teaching item is an ItemEffect with TriggerType 6 (learn) whose SpellID is the recipe's
-- spell, joined to its item through ItemXItemEffect; the skill it needs is the item's
-- RequiredSkillRank in ItemSparse (SkillLineAbility's MinSkillLineRank is 1 for nearly every
-- recipe, so it isn't that; docs/table-survey.md, section 6). Names, icons, reagents, and what a
-- recipe makes aren't written: the game gives them for a spell or item ID at run time.
--
-- Last, the Craftsman's Writs (see writs): the item each asks for and the recipe that makes it.
local CSV = require("csv")
local Lua = require("luaout")

local M = {
    path = "ForeverPlusPlus/Modules/Character/Professions/Data.lua",
    tables = { "SkillLineAbility", "SkillLine", "ItemEffect", "ItemXItemEffect", "ItemSparse",
        "TradeSkillCategory", "SpellEffect" },
}

-- The name TradeSkillCategory gives the category, one per profession, that holds the recipes
-- Season of Discovery added (build 1.60.1.70888: 2592 to 2598, 287 recipes with levels). Forever's
-- client still has them, but they aren't in Forever, so the addon leaves that category out.
local RETIRED_CATEGORY = "SEASON OF DISCOVERY"

local Int = CSV.Int

local LEARN_TRIGGER = 6 -- ItemEffect.TriggerType for "teaches this spell"

-- For summary.lua: a recipe line's key (its SkillLineAbility ID), or a writ's (its item ID), and
-- the line itself.
function M.Entry(line)
    local id = line:match("^    %[(%d+)%] = {")
    if id then
        return (line:find("{ item = ", 1, true) and "writ " or "ability ") .. id, line
    end
end

local WRIT_NAME = "^Craftsman's Writ: (.+)$" -- Forever's; Classic's Argent Dawn writs have " - "
local CREATE_ITEM = 24 -- SpellEffect.Effect

-- Writs that spell their item's name another way than the item does (build 1.60.1.70959): the
-- name on the writ -> the item's own.
local WRIT_ITEM_NAME = {
    ["Elixir of Ogre's Strength"] = "Elixir of Ogre Strength",
    ["Gyromatic Micro-Adjuster"] = "Gyromatic Micro-Adjustor",
    ["Pearl-Handled Dagger"] = "Pearl-handled Dagger",
    ["Potion of Demonslaying"] = "Potion of Demon Slaying",
}

-- The Craftsman's Writs: items named "Craftsman's Writ: <item>" that start a quest (ItemSparse's
-- StartQuestID), each { id, name (of the item it asks for), quest, item, spell }. The item is the one of
-- that name a profession's recipe makes (a SpellEffect with Effect 24 whose EffectItemType is the
-- item, of a spell in `recipeSpells`), the lowest ID of several; without one, the lowest item of
-- that name, with no spell. A writ whose item isn't found at all is left out, and said. How many it asks
-- for isn't in the client's tables (the quest's objectives come from the server).
local function writs(t, recipeSpells)
    local madeBy = {} -- item ID -> the lowest recipe spell that makes it
    for _, row in ipairs(CSV.Records(t.SpellEffect, "SpellEffect", { "SpellID", "Effect", "EffectItemType" })) do
        local spell = Int(row.SpellID, "SpellEffect.SpellID")
        local item = Int(row.EffectItemType, "EffectItemType")
        if Int(row.Effect, "Effect") == CREATE_ITEM and item > 0 and recipeSpells[spell]
            and (not madeBy[item] or spell < madeBy[item]) then
            madeBy[item] = spell
        end
    end
    local crafted, any = {}, {} -- item name -> the lowest item ID of that name: crafted, and at all
    local orders = {}
    for _, row in ipairs(CSV.Records(t.ItemSparse, "ItemSparse", { "ID", "Display_lang", "StartQuestID" })) do
        local id, name = Int(row.ID, "ItemSparse.ID"), row.Display_lang
        if madeBy[id] and (not crafted[name] or id < crafted[name]) then
            crafted[name] = id
        end
        if not any[name] or id < any[name] then
            any[name] = id
        end
        local wanted = name:match(WRIT_NAME)
        if wanted and Int(row.StartQuestID, "StartQuestID") > 0 then
            orders[#orders + 1] = { id = id, name = wanted, quest = Int(row.StartQuestID, "StartQuestID") }
        end
    end
    local out = {}
    for _, order in ipairs(orders) do
        local name = WRIT_ITEM_NAME[order.name] or order.name
        order.item = crafted[name] or any[name]
        order.spell = order.item and madeBy[order.item]
        if order.item then
            out[#out + 1] = order
        else
            io.stderr:write("datagen: no item named for the writ ", order.name, " (", order.id, ")\n")
        end
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

-- spell ID -> the item that teaches it and the skill it needs (nil when ItemSparse has no row for
-- the item). Of several items, one ItemSparse has a row for, then the lowest skill, then the
-- lowest ID, so the same tables give the same file.
local function teachers(t)
    local effects = {} -- ItemEffect ID -> spell it teaches
    for _, row in ipairs(CSV.Records(t.ItemEffect, "ItemEffect", { "ID", "TriggerType", "SpellID" })) do
        if Int(row.TriggerType, "TriggerType") == LEARN_TRIGGER then
            effects[Int(row.ID, "ItemEffect.ID")] = Int(row.SpellID, "SpellID")
        end
    end
    local need = {} -- item ID -> RequiredSkillRank, for items ItemSparse has
    for _, row in ipairs(CSV.Records(t.ItemSparse, "ItemSparse", { "ID", "RequiredSkillRank" })) do
        need[Int(row.ID, "ItemSparse.ID")] = Int(row.RequiredSkillRank, "RequiredSkillRank")
    end
    local function better(a, b)
        local na, nb = need[a], need[b]
        if (na ~= nil) ~= (nb ~= nil) then
            return na ~= nil
        end
        if na and nb and na ~= nb then
            return na < nb
        end
        return a < b
    end
    local bySpell = {}
    for _, row in ipairs(CSV.Records(t.ItemXItemEffect, "ItemXItemEffect", { "ItemEffectID", "ItemID" })) do
        local spell = effects[Int(row.ItemEffectID, "ItemEffectID")]
        if spell then
            local item = Int(row.ItemID, "ItemID")
            local best = bySpell[spell]
            if not best or better(item, best) then
                bySpell[spell] = item
            end
        end
    end
    local out = {}
    for spell, item in pairs(bySpell) do
        local learn = need[item]
        out[spell] = { item = item, learn = learn and learn > 0 and learn or nil }
    end
    return out
end

function M.Build(t, build, script)
    local names = {} -- skill line ID -> name
    for _, row in ipairs(CSV.Records(t.SkillLine, "SkillLine", { "ID", "DisplayName_lang" })) do
        names[Int(row.ID, "SkillLine.ID")] = row.DisplayName_lang
    end
    local taught = teachers(t)

    local recipeSpells = {} -- the spell of every recipe written
    local byLine = {} -- skill line ID -> { { id, spell, yellow, gray } }
    for _, row in ipairs(CSV.Records(t.SkillLineAbility, "SkillLineAbility", { "ID", "SkillLine",
        "Spell", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh" })) do
        local yellow = Int(row.TrivialSkillLineRankLow, "TrivialSkillLineRankLow")
        local gray = Int(row.TrivialSkillLineRankHigh, "TrivialSkillLineRankHigh")
        if gray > 0 and yellow > 0 and yellow <= gray then
            local line = Int(row.SkillLine, "SkillLine")
            byLine[line] = byLine[line] or {}
            recipeSpells[Int(row.Spell, "Spell")] = true
            table.insert(byLine[line], {
                id = Int(row.ID, "SkillLineAbility.ID"), spell = Int(row.Spell, "Spell"),
                yellow = yellow, gray = gray,
            })
        end
    end

    local lines = {}
    for line in pairs(byLine) do
        lines[#lines + 1] = line
    end
    table.sort(lines)

    local out = {
        "-- Every recipe in the game's SkillLineAbility table, keyed by its ID, which a recipe's info",
        "-- gives as skillLineAbilityID: { yellow, gray, skill line, spell, item, learn }. Yellow and gray",
        "-- are the skill it turns those colors at (TrivialSkillLineRankLow and TrivialSkillLineRankHigh);",
        "-- green is worked out from them (ns.Professions.RecipeLevels). Item is the one that teaches it",
        "-- (ItemEffect and ItemXItemEffect) and learn the skill that item needs (ItemSparse's",
        "-- RequiredSkillRank), each left out when the tables have none.",
        "--",
        "-- Generated by " .. script .. " from wago.tools' tables for build " .. build .. ".",
        "-- Don't edit it by hand: run the script again after a patch.",
        "local _, ns = ...",
        "",
        "ns.modules.Professions.internal.recipes = {",
    }
    for _, line in ipairs(lines) do
        out[#out + 1] = ("    -- %s (%d)"):format(Lua.Comment(names[line] or "?"), line)
        local list = byLine[line]
        table.sort(list, function(a, b)
            return a.id < b.id
        end)
        for _, entry in ipairs(list) do
            local fields = { entry.yellow, entry.gray, line, entry.spell }
            local teacher = taught[entry.spell]
            if teacher then
                fields[5] = teacher.item
                fields[6] = teacher.learn
            end
            out[#out + 1] = ("    [%d] = { %s },"):format(entry.id, table.concat(fields, ", "))
        end
    end
    out[#out + 1] = "}"

    local retired = {}
    for _, row in ipairs(CSV.Records(t.TradeSkillCategory, "TradeSkillCategory", { "ID", "Name_lang" })) do
        if row.Name_lang:upper() == RETIRED_CATEGORY then
            retired[#retired + 1] = Int(row.ID, "TradeSkillCategory.ID")
        end
    end
    table.sort(retired)
    out[#out + 1] = ""
    out[#out + 1] = "-- The recipe categories (a recipe info's categoryID) of recipes that aren't in Forever:"
    out[#out + 1] = "-- TradeSkillCategory's \"" .. RETIRED_CATEGORY .. "\", one per profession."
    out[#out + 1] = "ns.modules.Professions.internal.retiredCategories = {"
    for _, id in ipairs(retired) do
        out[#out + 1] = ("    [%d] = true,"):format(id)
    end
    out[#out + 1] = "}"

    out[#out + 1] = ""
    out[#out + 1] = "-- The Craftsman's Writs, by item ID: the item each asks for, the quest it starts, and the"
    out[#out + 1] = "-- spell of the recipe that makes the item (ItemSparse's \"Craftsman's Writ: <item>\" names and"
    out[#out + 1] = "-- StartQuestID, and SpellEffect's create item effects). How many a writ asks for isn't in the"
    out[#out + 1] = "-- tables."
    out[#out + 1] = "ns.modules.Professions.internal.writs = {"
    for _, writ in ipairs(writs(t, recipeSpells)) do
        local fields = "item = " .. writ.item .. ", quest = " .. writ.quest
            .. (writ.spell and (", spell = " .. writ.spell) or "")
        out[#out + 1] = ("    [%d] = { %s }, -- %s"):format(writ.id, fields, Lua.Comment(writ.name))
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

return M
