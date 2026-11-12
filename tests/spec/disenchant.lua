-- Disenchant: what an item gives and its average value.
local T = ...
local ns, eq = T.ns, T.eq

do
    local Disenchant = ns.Disenchant
    local function describe(list)
        if not list then
            return "nil"
        end
        local parts = {}
        for i, each in ipairs(list) do
            parts[i] = ("%d %g %d-%d"):format(each.item, each.chance, each.min, each.max)
        end
        return table.concat(parts, ", ")
    end
    eq(describe(Disenchant.Outcomes(2, 28, false)), "11083 0.75 1-2, 11082 0.2 1-2, 11084 0.05 1-1",
        "disenchant: uncommon armor 26-30 is mostly Soul Dust")
    eq(describe(Disenchant.Outcomes(2, 28, true)), "11082 0.75 1-2, 11083 0.2 1-2, 11084 0.05 1-1",
        "disenchant: uncommon weapon 26-30 is mostly Greater Astral")
    eq(describe(Disenchant.Outcomes(2, 5, false)), "10940 0.8 1-2, 10938 0.2 1-2",
        "disenchant: uncommon armor 5-15 has no shard")
    eq(describe(Disenchant.Outcomes(2, 15, true)), "10938 0.8 1-2, 10940 0.2 1-2",
        "disenchant: uncommon weapon 5-15")
    eq(describe(Disenchant.Outcomes(2, 21, true)), "10998 0.75 1-2, 10940 0.15 4-6, 10978 0.1 1-1",
        "disenchant: uncommon weapon 21-25 shard at 10%")
    eq(describe(Disenchant.Outcomes(2, 60, false)), "16204 0.75 1-2, 16203 0.2 1-2, 14344 0.05 1-1",
        "disenchant: uncommon armor 56-60")
    eq(Disenchant.Outcomes(2, 4, false), nil, "disenchant: uncommon below level 5")
    eq(describe(Disenchant.Outcomes(3, 16, true)), "10978 1 1-1", "disenchant: rare 16-20")
    eq(describe(Disenchant.Outcomes(3, 25, true)), "10978 1 1-1", "disenchant: rare 21-25")
    eq(describe(Disenchant.Outcomes(3, 60, false)), "14344 0.995 1-1, 20725 0.005 1-1",
        "disenchant: rare 56-60 can give a Nexus Crystal")
    eq(describe(Disenchant.Outcomes(4, 45, false)), "11177 1 2-4", "disenchant: epic 40-45")
    eq(describe(Disenchant.Outcomes(4, 58, true)), "20725 1 1-1", "disenchant: epic 56-60")
    eq(Disenchant.Outcomes(4, 39, false), nil, "disenchant: epic below level 40")

    -- The game's brackets (Lib/DisenchantBrackets.lua, from ItemDisenchantLoot): every one the
    -- survey found, and none past them.
    local function bracket(quality, level, isWeapon)
        local b = Disenchant.Bracket(quality, level, isWeapon)
        return b and ("%d-%d"):format(b[3], b[4]) or "nil"
    end
    eq(#ns.TableData.disenchantBrackets, 54, "brackets: 54 rows, as in build 70888")
    eq(bracket(3, 5, false), "5-15", "brackets: rare from item level 5")
    eq(bracket(3, 10, true), "5-15", "brackets: rare 5-10 can be disenchanted")
    eq(bracket(3, 18, false), "16-20", "brackets: rare 11-25 is three brackets")
    eq(bracket(3, 80, false), "61-99", "brackets: rare above 65")
    eq(bracket(2, 85, true), "61-99", "brackets: uncommon above 65")
    eq(bracket(4, 90, false), "61-99", "brackets: epic above 80")
    eq(bracket(2, 100, false), "nil", "brackets: none past 99")
    eq(bracket(4, 39, false), "nil", "brackets: epic from 40")
    eq(bracket(1, 30, false), "nil", "brackets: common has none")
    -- Brackets whose results the hand rows don't confirm: disenchantable, results not known.
    eq(Disenchant.Outcomes(3, 10, false), nil, "unknown: rare 5-15")
    eq(Disenchant.Outcomes(2, 65, false), nil, "unknown: uncommon 61-99 (the old row said 61-65)")
    eq(Disenchant.Outcomes(4, 70, true), nil, "unknown: epic 61-99 (the old row said 61-80)")
    local outcomes, b = Disenchant.ForItem(4, 3, "INVTYPE_HEAD", 70)
    eq(outcomes, nil, "unknown: ForItem has no outcomes")
    eq(b and Disenchant.Key(b), "3:4:61", "unknown: but the item's bracket")

    -- Learned in play: the tally becomes the outcomes.
    local rare = Disenchant.Bracket(3, 70, false)
    eq(Disenchant.Learn(rare, { { id = 20725, count = 1 } }), true, "learn: counted")
    eq(Disenchant.Learn(rare, { { id = 14344, count = 1 } }), true, "learn: a second")
    eq(Disenchant.Learn(rare, { { id = 14344, count = 2 } }), true, "learn: a third")
    eq(describe(Disenchant.Outcomes(3, 70, false)), ("14344 %g 1-2, 20725 %g 1-1"):format(2 / 3, 1 / 3),
        "learn: chances and amounts from what was seen")
    eq(Disenchant.Outcomes(3, 70, false)[1].seen, 3, "learn: how many disenchants")
    eq(Disenchant.Outcomes(3, 70, true), nil, "learn: weapons are their own bracket")
    eq(Disenchant.Learn(rare, {}), false, "learn: no loot isn't counted")
    eq(Disenchant.Learn(rare, { { id = 20725 } }), false, "learn: unreadable loot isn't counted")
    eq(Disenchant.Learn(rare, { { id = 20725, count = 1 }, { id = 20725, count = 1 } }), true,
        "learn: one material in two slots")
    eq(Disenchant.Outcomes(3, 70, false)[2].max, 2, "learn: counts as one amount")
    -- A known bracket keeps its rows until play shows a material they don't give.
    local green = Disenchant.Bracket(2, 28, false)
    Disenchant.Learn(green, { { id = 11083, count = 2 } })
    eq(describe(Disenchant.Outcomes(2, 28, false)), "11083 0.75 1-2, 11082 0.2 1-2, 11084 0.05 1-1",
        "learn: what the rows give keeps the rows")
    Disenchant.Learn(green, { { id = 99999, count = 1 } })
    eq(describe(Disenchant.Outcomes(2, 28, false)), "11083 0.5 2-2, 99999 0.5 1-1",
        "learn: a material the rows lack replaces them")
    ns.GameData.ForgetAll()
    eq(Disenchant.Outcomes(3, 70, false), nil, "learn: forgotten")
    eq(Disenchant.Outcomes(1, 30, false), nil, "disenchant: common gives nothing")
    eq(Disenchant.Outcomes(5, 70, false), nil, "disenchant: legendary isn't in the table")
    eq(Disenchant.Outcomes(2, nil, false), nil, "disenchant: no item level")
    eq(Disenchant.ForItem(15, 2, "", 30), nil, "disenchant: not a weapon or armor")
    eq(Disenchant.ForItem(4, 2, "INVTYPE_BODY", 30), nil, "disenchant: shirts can't")
    eq(Disenchant.ForItem(4, 2, "INVTYPE_TABARD", 30), nil, "disenchant: tabards can't")
    eq(describe(Disenchant.ForItem(2, 2, "INVTYPE_WEAPON", 28)), describe(Disenchant.Outcomes(2, 28, true)),
        "disenchant: class 2 counts as a weapon")
    eq(describe(Disenchant.ForItem(4, 2, "INVTYPE_CHEST", 28)), describe(Disenchant.Outcomes(2, 28, false)),
        "disenchant: class 4 counts as armor")
    -- chance x average amount x price: 0.75 x 1.5 x 100 + 0.2 x 1.5 x 1000 + 0.05 x 1 x 2000
    local prices = { [11083] = 100, [11082] = 1000, [11084] = 2000 }
    local total, missing = Disenchant.Value(Disenchant.Outcomes(2, 28, false), function(id)
        return prices[id]
    end)
    eq(total, 0.75 * 1.5 * 100 + 0.2 * 1.5 * 1000 + 0.05 * 2000, "disenchant: average value")
    eq(missing, 0, "disenchant: every outcome priced")
    prices[11084] = nil
    total, missing = Disenchant.Value(Disenchant.Outcomes(2, 28, false), function(id)
        return prices[id]
    end)
    eq(total, 0.75 * 1.5 * 100 + 0.2 * 1.5 * 1000, "disenchant: unpriced outcome left out")
    eq(missing, 1, "disenchant: counts the outcome with no price")
end
