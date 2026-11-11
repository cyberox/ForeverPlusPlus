-- Durability: how worn the equipped items are, the warning level, and when a warning is due.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

local worn = {} -- slot -> { current, maximum }
GetInventoryItemDurability = function(slot)
    local item = worn[slot]
    if item then
        return item[1], item[2]
    end
end
T.load("Lib/Durability") -- it caches GetInventoryItemDurability
local D = ns.Durability

eq(D.Fraction(1), nil, "durability: an empty slot")
eq(D.Lowest(), nil, "durability: nothing worn has durability")
worn[1] = { 30, 60 }
worn[5] = { 90, 100 }
worn[16] = { 0, 0 } -- a maximum of 0 counts as no durability
eq(D.Fraction(1), 0.5, "durability: half worn")
eq(D.Fraction(16), nil, "durability: no maximum")
local lowest, slot = D.Lowest()
eq(lowest, 0.5, "durability: the most worn item")
eq(slot, 1, "durability: and its slot")
game.secret = 30
eq(D.Fraction(1), nil, "durability: a secret value is unknown")
eq(D.Lowest(), 0.9, "durability: and skipped")
game.secret = nil

eq(D.Level(nil, 0.25, true), "ok", "level: nothing to warn about")
eq(D.Level(0.5, 0.25, true), "ok", "level: above the threshold")
eq(D.Level(0.25, 0.25, true), "ok", "level: at the threshold")
eq(D.Level(0.2, 0.25, true), "low", "level: below the threshold")
eq(D.Level(0, 0.25, true), "broken", "level: broken")
eq(D.Level(0, 0.25, false), "low", "level: broken is only low without Warn When Broken")

eq(D.ShouldWarn(nil, "ok"), false, "warn: not while fine")
eq(D.ShouldWarn(nil, "low"), true, "warn: the first look finds it low")
eq(D.ShouldWarn("ok", "low"), true, "warn: dropping below")
eq(D.ShouldWarn("low", "low"), false, "warn: once per drop")
eq(D.ShouldWarn("low", "broken"), true, "warn: again when it breaks")
eq(D.ShouldWarn("broken", "broken"), false, "warn: once when broken")
eq(D.ShouldWarn("broken", "low"), false, "warn: not when one broken item is repaired")
eq(D.ShouldWarn("low", "ok"), false, "warn: not after a repair")
eq(D.ShouldWarn("ok", "broken"), true, "warn: breaking at once")
