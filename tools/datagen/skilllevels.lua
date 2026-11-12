-- Professions' Data.lua: every recipe of every profession, from SkillLineAbility, keyed by its ID,
-- which the game's recipe info gives as skillLineAbilityID: the skill it turns yellow and gray at
-- (TrivialSkillLineRankLow and TrivialSkillLineRankHigh), its profession's skill line, its spell,
-- and the item that teaches it with the skill that item needs, when there is one. SkillLine names
-- each profession, for the comments. Only rows with a gray level are written, and only those whose
-- yellow level isn't past it.
--
-- The teaching item is an ItemEffect with TriggerType 6 (learn) whose SpellID is the recipe's
-- spell, joined to its item through ItemXItemEffect; the skill it needs is the item's
-- RequiredSkillRank in ItemSparse (SkillLineAbility's MinSkillLineRank is 1 for nearly every
-- recipe, so it isn't that; docs/table-survey.md, section 6). Names, icons, reagents, and what a
-- recipe makes aren't written: the game gives them for a spell or item ID at run time.
local CSV = require("csv")
local Lua = require("luaout")

local M = {
    path = "ForeverPlusPlus/Modules/Character/Professions/Data.lua",
    tables = { "SkillLineAbility", "SkillLine", "ItemEffect", "ItemXItemEffect", "ItemSparse" },
}

local Int = CSV.Int

local LEARN_TRIGGER = 6 -- ItemEffect.TriggerType for "teaches this spell"

-- For summary.lua: a recipe line's key (its SkillLineAbility ID) and the line itself.
function M.Entry(line)
    local id = line:match("^    %[(%d+)%] = {")
    if id then
        return "ability " .. id, line
    end
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

    local byLine = {} -- skill line ID -> { { id, spell, yellow, gray } }
    for _, row in ipairs(CSV.Records(t.SkillLineAbility, "SkillLineAbility", { "ID", "SkillLine",
        "Spell", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh" })) do
        local yellow = Int(row.TrivialSkillLineRankLow, "TrivialSkillLineRankLow")
        local gray = Int(row.TrivialSkillLineRankHigh, "TrivialSkillLineRankHigh")
        if gray > 0 and yellow > 0 and yellow <= gray then
            local line = Int(row.SkillLine, "SkillLine")
            byLine[line] = byLine[line] or {}
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
    return table.concat(out, "\n") .. "\n"
end

return M
