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
    eq(describe(Disenchant.Outcomes(2, 65, false)), "16204 0.75 2-5, 16203 0.2 2-3, 14344 0.05 1-1",
        "disenchant: uncommon armor top bracket")
    eq(Disenchant.Outcomes(2, 4, false), nil, "disenchant: uncommon below level 5")
    eq(Disenchant.Outcomes(2, 66, false), nil, "disenchant: uncommon above the table")
    eq(describe(Disenchant.Outcomes(3, 11, true)), "10978 1 1-1", "disenchant: rare lowest bracket")
    eq(describe(Disenchant.Outcomes(3, 60, false)), "14344 0.995 1-1, 20725 0.005 1-1",
        "disenchant: rare 56-65 can give a Nexus Crystal")
    eq(Disenchant.Outcomes(3, 10, false), nil, "disenchant: rare below level 11")
    eq(describe(Disenchant.Outcomes(4, 45, false)), "11177 1 2-4", "disenchant: epic 40-45")
    eq(describe(Disenchant.Outcomes(4, 58, true)), "20725 1 1-1", "disenchant: epic 56-60")
    eq(describe(Disenchant.Outcomes(4, 70, true)), "20725 1 1-2", "disenchant: epic 61-80")
    eq(Disenchant.Outcomes(4, 39, false), nil, "disenchant: epic below level 40")
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
