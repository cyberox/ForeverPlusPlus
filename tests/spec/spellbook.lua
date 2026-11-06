-- Spellbook: the spells the player knows by name with every rank, in order, leaving out passives,
-- the other spec's, and spells still loading; ranks from subtext; and the level a spell is learned.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

game.secret = "<secret>"
local spells = {
    [10] = { "Fireball", "Rank 2", 12 }, [11] = { "Fireball", "Rank 1", 6 },
    [12] = { "Fireball", "Rank 10", 60 }, [20] = { "Frost Armor", "" }, [30] = { "Passive", "" },
    [40] = { "Other Spec", "Rank 1" }, [50] = { "Loading" }, [60] = { "<secret>", "Rank 1" },
}
local requested = {}
C_Spell = {
    GetSpellName = function(id) return spells[id] and spells[id][1] end,
    GetSpellSubtext = function(id) return spells[id] and spells[id][2] end,
    RequestLoadSpellData = function(id) requested[#requested + 1] = id end,
    GetSpellLevelLearned = function(id) return spells[id] and spells[id][3] end,
}
-- Two skill lines: the player's (seven items) and another spec's (one).
local items = { 10, 11, 12, 20, 30, 50, 60, 40 }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(line)
        if line == 1 then
            return { itemIndexOffset = 0, numSpellBookItems = 7 }
        end
        return { itemIndexOffset = 7, numSpellBookItems = 1, offSpecID = 63 }
    end,
    GetSpellBookItemInfo = function(i) return { spellID = items[i], isPassive = items[i] == 30 } end,
    IsSpellKnown = function(id) return id == 10 end,
}
Enum.SpellBookSpellBank = { Player = 0 }
T.load("Lib/Spellbook") -- it caches C_Spell and C_SpellBook
local Spellbook = ns.Spellbook

eq(Spellbook.Available(), true, "spellbook: this client can read it")
eq(Spellbook.Rank(10), 2, "spellbook: a rank from its subtext")
eq(Spellbook.Rank(20), nil, "spellbook: no rank without a number")
eq(Spellbook.IsKnown(10) and not Spellbook.IsKnown(11), true, "spellbook: known, as the game says")

local ranks, complete = Spellbook.Ranks()
local fireball = ranks.Fireball or {}
eq(#fireball, 3, "spellbook: every rank of a spell")
eq((fireball[1] or {}).rank .. "," .. (fireball[2] or {}).rank .. "," .. (fireball[3] or {}).rank, "1,2,10",
    "spellbook: ranks lowest first, by number, not text")
eq((fireball[3] or {}).subtext, "Rank 10", "spellbook: with the subtext /cast needs")
eq(ranks["Frost Armor"] and ranks["Frost Armor"][1].rank, 0, "spellbook: a spell without ranks is rank 0")
eq(ranks.Passive, nil, "spellbook: passives are left out")
eq(ranks["Other Spec"], nil, "spellbook: the other spec's are left out")
eq(ranks["<secret>"], nil, "spellbook: a secret name is left out")
eq(complete, false, "spellbook: incomplete while a spell is loading")
eq(requested[1], 50, "spellbook: and that spell's data is asked for")
eq(Spellbook.LevelLearned(12), 60, "spellbook: the level a spell is learned at")
eq(Spellbook.LevelLearned(20), nil, "spellbook: nil when the game doesn't say")

-- A client without the spellbook calls.
C_SpellBook = nil
T.load("Lib/Spellbook")
local empty, done = ns.Spellbook.Ranks()
eq(next(empty) == nil and done == false, true, "spellbook: nothing, and not complete, without the API")
