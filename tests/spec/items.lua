-- Items: item stats, stat weights, which worn items an item would replace, and talents.
local T = ...
local ns, eq, near, game = T.ns, T.eq, T.near, T.game

local ItemStats, Equipment, Talents = ns.ItemStats, ns.Equipment, ns.Talents

local stats = ItemStats.Normalize({
    ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 3,
    RESISTANCE0_NAME = 34, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8.5, MADE_UP_STAT = 1, ITEM_MOD_TEXT = "no",
})
eq(stats.STR, 5, "stats: strength")
eq(stats.SP, 5, "stats: two spell power keys add up")
eq(stats.HEAL, 2, "stats: spell power heals too, spell damage doesn't")
eq(stats.ARMOR, 34, "stats: armor is resistance 0")
eq(stats.DPS, 8.5, "stats: weapon dps")
eq(stats.MADE_UP_STAT, nil, "stats: an unknown key isn't a stat")
eq(ItemStats.Unknown()[1], "MADE_UP_STAT", "stats: but is remembered")
eq(#ItemStats.Unknown(), 1, "stats: a non-number isn't remembered")
eq(ItemStats.Normalize(nil).STR, nil, "stats: nothing from nothing")
stats = ItemStats.Normalize({ ITEM_MOD_HIT_RATING_SHORT = 4, ITEM_MOD_CRIT_RATING_SHORT = 14,
    ITEM_MOD_DODGE_RATING_SHORT = 6, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 7 })
near(stats.HIT, 0.4, "stats: hit is a rating, 10 to 1% without the client")
near(stats.SPELLHIT, 0.4, "stats: the one hit counts for spells too")
near(stats.CRIT, 1, "stats: crit is a rating, 14 to 1%")
near(stats.SPELLCRIT, 1, "stats: the one crit counts for spells too")
near(stats.DODGE, 0.5, "stats: dodge is a rating, 12 to 1%")
eq(stats.DEF, 7, "stats: defense is skill points")

-- Which stat a tooltip line is about, from the client's strings (build 70450's, from Gear Probe).
do
    local strings = {
        ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:", ITEM_MOD_SPIRIT = "%c%s Spirit", ITEM_MOD_SPIRIT_SHORT = "Spirit",
        ITEM_MOD_STAMINA = "%c%s Stamina", ITEM_MOD_STAMINA_SHORT = "Stamina",
        ITEM_MOD_HIT_RATING = "Increases your hit by %s.", ITEM_MOD_HIT_RATING_SHORT = "Hit",
        ITEM_MOD_CRIT_RATING = "Increases your critical strike by %s.",
        ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike", RESISTANCE2_NAME = "Fire Resistance",
        ITEM_MOD_SPELL_POWER_SHORT = "Spell Power", ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    }
    for name, text in pairs(strings) do
        _G[name] = text
    end
    local line = ItemStats.LineStat
    eq(line("+6 Spirit"), "SPI", "line stat: an attribute")
    eq(line("-3 Stamina"), "STA", "line stat: a negative one")
    eq(line("+10 Fire Resistance"), "RES_FIRE", "line stat: a resistance by its name")
    eq(line("Durability 59 / 65"), nil, "line stat: not a stat")
    eq(line("(12.6 damage per second)"), nil, "line stat: dps isn't colored")
    local key, effect = line("Equip: Increases your hit by 1%.")
    eq(key, "HIT", "line stat: an Equip: line by its string")
    eq(effect, "Increases your hit by 1%.", "line stat: the effect after Equip:")
    local wand = { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.8 }
    local spell = "Equip: Increases damage and healing done by magical spells and effects by up to 2."
    eq(line(spell, wand), "SP", "line stat: a spell's wording by its number")
    eq(line(spell, nil), nil, "line stat: not without the item's stats")
    eq(line(spell, { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_ATTACK_POWER_SHORT = 2 }), nil,
        "line stat: two stats with the number are left alone")
    eq(line(spell, { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_INTELLECT_SHORT = 2 }), "SP",
        "line stat: an attribute is never an Equip: line's")
    eq(line("Equip: Improves your chance to hit by 1%.", { ITEM_MOD_HIT_RATING_SHORT = 10 }), "HIT",
        "line stat: a rating's percent")
    for name in pairs(strings) do
        _G[name] = nil
    end
end
eq(select(2, ItemStats.RatingRates()).HIT, "seed", "ratings: the seed without the client")
for _, key in ipairs(ItemStats.ORDER) do
    local known = key == "DPS_OFF" or key == "DPS_RANGED"
    for _, ours in pairs(ItemStats.KEYS) do
        if type(ours) == "table" then
            for _, each in ipairs(ours) do
                known = known or each == key
            end
        else
            known = known or ours == key
        end
    end
    eq(known, true, "stats: ORDER key " .. key .. " comes from a game key")
end
eq(ItemStats.Score({ STR = 5, SP = 5, ARMOR = 34 }, { STR = 1, SP = 2 }), 15, "score: weighted sum")
eq(ItemStats.Score({}, { STR = 1 }), 0, "score: nothing")
eq(ItemStats.Slotted({ DPS = 10, STR = 1 }, "INVTYPE_WEAPONOFFHAND").DPS_OFF, 10, "score: off-hand dps")
eq(ItemStats.Slotted({ DPS = 10 }, "INVTYPE_WEAPONOFFHAND").DPS, nil, "score: off-hand dps moved")
eq(ItemStats.Slotted({ DPS = 10 }, "INVTYPE_RANGEDRIGHT").DPS_RANGED, 10, "score: ranged dps")
local plain = { DPS = 10 }
eq(ItemStats.Slotted(plain, "INVTYPE_WEAPON"), plain, "score: main hand dps stays")
local up, percent = ItemStats.Compare(110, 100, 0)
eq(up, true, "compare: better is an upgrade")
near(percent, 10, "compare: by ten percent")
eq(ItemStats.Compare(105, 100, 10), false, "compare: under the threshold")
eq(ItemStats.Compare(100, 100, 0), false, "compare: the same isn't")
up, percent = ItemStats.Compare(5, 0, 0)
eq(up, true, "compare: anything beats an empty slot")
eq(percent, nil, "compare: with no percentage")
eq(ItemStats.Compare(0, 0, 0), false, "compare: nothing doesn't")

eq(Equipment.Slots("INVTYPE_FINGER")[2], 12, "slots: second ring")
eq(Equipment.Slots("INVTYPE_ROBE")[1], 5, "slots: a robe is the chest")
eq(Equipment.Slots("INVTYPE_BAG"), nil, "slots: a bag isn't gear")
eq(Equipment.Slots(""), nil, "slots: nothing isn't gear")
game.worn = { [11] = "ring1", [12] = "ring2", [16] = "main", [17] = "off" }
game.cachedItems.off = { 2, "Weapon", "Daggers", "INVTYPE_WEAPON", 0, 2, 15 }
local function wornOf(slot)
    return game.worn[slot]
end
local rivals = Equipment.RuleRivals("INVTYPE_FINGER", wornOf)
eq(#rivals, 2, "rivals: either ring")
eq(rivals[1][1], "ring1", "rivals: the first ring")
eq(rivals[2][1], "ring2", "rivals: the second ring")
rivals = Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf)
eq(#rivals, 1, "rivals: a two-hander has one alternative")
eq(#rivals[1], 2, "rivals: both hands")
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: a one-hander without dual wield is the main hand")
eq(rivals[1][1], "main", "rivals: the main hand")
game.dualWield = true
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 2, "rivals: dual wielding, either hand")
eq(rivals[2][1], "off", "rivals: the off hand")
game.worn[17] = nil
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 2, "rivals: dual wielding with an empty off hand still offers it")
eq(#rivals[2], 0, "rivals: as an empty alternative")
game.dualWield = false
rivals = Equipment.RuleRivals("INVTYPE_HEAD", wornOf)
eq(#rivals[1], 0, "rivals: an empty slot is an empty alternative")
eq(#Equipment.RuleRivals("INVTYPE_TABARD", wornOf), 0, "rivals: not gear, no alternatives")
-- What's worn is read by type: a worn two-hander fills the off hand too.
game.worn[17] = nil
game.cachedItems.great = { 3, "Weapon", "Two-Handed Swords", "INVTYPE_2HWEAPON", 0, 2, 8 }
game.worn[16] = "great"
eq(Equipment.WornType(16), "INVTYPE_2HWEAPON", "worn type: read from the worn item")
eq(Equipment.WornType(17), nil, "worn type: nil for an empty slot")
rivals = Equipment.RuleRivals("INVTYPE_SHIELD", wornOf)
eq(#rivals, 1, "rivals: a shield with a two-hander worn has one alternative")
eq(rivals[1][1], "great", "rivals: the two-hander, not an empty off hand")
game.dualWield = true
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: dual wielding with a two-hander worn, a one-hander replaces it")
eq(rivals[1][1], "great", "rivals: the two-hander")
game.worn[16] = "main"
game.cachedItems.shield = { 4, "Armor", "Shields", "INVTYPE_SHIELD", 0, 4, 6 }
game.worn[17] = "shield"
eq(Equipment.WornType(17), "INVTYPE_SHIELD", "worn type: a shield")
rivals = Equipment.RuleRivals("INVTYPE_WEAPON", wornOf)
eq(#rivals, 1, "rivals: dual wielding with a shield worn, a one-hander is the main hand")
game.worn[17] = nil
rivals = Equipment.RuleRivals("INVTYPE_SHIELD", wornOf)
eq(#rivals[1], 0, "rivals: a shield with a one-hander worn takes the empty off hand")
game.dualWield = false
game.worn[17] = "off"
eq(Equipment.IsWorn("main"), true, "worn: by link")
eq(Equipment.IsWorn("other"), false, "worn: not by link")
eq(Equipment.LinkKey("|cnIQ2:|Hitem:6541::::::::19:1482:::1:12734::::::|h[Willow Gloves of Magic]|h|r"),
    "item:6541::::::::19:1482:::1:12734", "link key: the item with its suffix, without the tail")
eq(Equipment.LinkKey("item:6541::::::::19:1482:::1:12734:::::"), "item:6541::::::::19:1482:::1:12734",
    "link key: a bare link reads the same")
eq(Equipment.LinkKey("item:6541") == Equipment.LinkKey("item:6541::::::::19:1482:::1:12734"), false,
    "link key: the base item isn't the suffixed one")
game.worn[10] = "|cnIQ2:|Hitem:6541::::::::19:1482:::1:12734::::::|h[Willow Gloves of Magic]|h|r"
eq(Equipment.IsWorn("item:6541::::::::19:1482:::1:12734:::::"), true, "worn: a tooltip's link to the worn item")
eq(Equipment.IsWorn("item:6541"), false, "worn: not the base item")
eq(Equipment.IsWornGUID("Item-4618-0-4000000081C35317"), false, "worn guid: nothing without the item API")
eq(Equipment.Worn(11), "ring1", "worn: a slot's link")
eq(Equipment.CanDualWield(), false, "dual wield: off")
eq(Equipment.CanUse("item:1", 10), true, "can use: a level 30 can wear level 10 gear")
eq(Equipment.CanUse("item:1", 31), false, "can use: not level 31 gear")
local text = ItemStats.WeightString("Forever++ Frost (Mage)", "MAGE", "Frost",
    { INT = 0.35, SP = 1, SPELLHIT = 10, STA = 0, DPS_RANGED = 1.2 })
eq(text, '( Pawn: v1: "Forever++ Frost (Mage)": Class=Mage, Spec=Frost, Intellect=0.35, SpellPower=1, '
    .. 'SpellHitRating=10, RangedDps=1.2 )', "weight string: written in order, zeros left out")
local parsed, name, unknown = ItemStats.ParseWeightString(text)
eq(parsed and parsed.INT, 0.35, "weight string: read back")
eq(parsed and parsed.DPS_RANGED, 1.2, "weight string: ranged dps read back")
eq(name, "Forever++ Frost (Mage)", "weight string: its name")
eq(#unknown, 0, "weight string: nothing unknown")
parsed, name, unknown = ItemStats.ParseWeightString(' (Pawn:v1:"x": spelldamage = 2, Crit=3, MadeUp=4, Class=Rogue) ')
eq(parsed and parsed.SP, 2, "weight string: an alias and loose spacing")
eq(parsed and parsed.CRIT, 3, "weight string: a short name")
eq(unknown[1], "MadeUp", "weight string: an unknown stat is reported")
eq(ItemStats.ParseWeightString("hello"), nil, "weight string: not one")
eq(select(2, ItemStats.ParseWeightString("hello")), "format", "weight string: says why")
eq(ItemStats.ParseWeightString('( Pawn: v1: "x": )'), nil, "weight string: empty is not one")
local derived = ItemStats.DeriveAttributes({ AP = 0.5, RAP = 0.5, CRIT = 8, DODGE = 10, ARMOR = 0.05,
    HEALTH = 0.12, SPELLCRIT = 7, MANA = 0.02 },
    { AP_STR = 2, AP_AGI = 0, RAP_AGI = 2, CRIT_AGI = 0.05, DODGE_AGI = 0.05, ARMOR_AGI = 2, HEALTH_STA = 10,
        SPELLCRIT_INT = 0.0167, MANA_INT = 15 })
near(derived.STR, 1, "derived: strength from attack power")
near(derived.AGI, 2, "derived: agility from ranged attack power, crit, dodge, and armor")
near(derived.STA, 1.2, "derived: stamina from health")
near(derived.INT, 0.42, "derived: intellect from spell crit and mana, rounded")
derived = ItemStats.DeriveAttributes({ AP = 1 }, { AP_STR = 2 })
near(derived.STR, 2, "derived: strength alone")
eq(derived.AGI, nil, "derived: no agility without its rates")
eq(next(ItemStats.PlayerRates()) ~= nil, true, "rates: the flat armor rule is always there")
eq(ItemStats.PlayerRates().AP_STR, nil, "rates: nothing without the game's functions")
derived = ItemStats.DeriveAttributes({ AP = 0.25, BLOCKVALUE = 0.3 }, { AP_STR = 2, BLOCKVALUE_STR = 0.05 })
near(derived.STR, 0.52, "derived: strength's block value counts, rounded")
do
    -- The character sheet's functions answer 0 to 1 for the player's own points (stub: 25 Agility,
    -- 60 Intellect, 1% crit per 20 Agility, 1% dodge per 20, 1% spell crit per 60 Intellect).
    local saved = { UnitStat, GetCritChanceFromStat, GetDodgeChanceFromAttribute, GetSpellCritChanceFromStat,
        BLOCK_VALUE_PER_STRENGTH }
    local points = { [2] = 25, [4] = 60 }
    UnitStat = function(_, stat)
        return points[stat] or 10, points[stat] or 10
    end
    GetCritChanceFromStat = function(_, value)
        return value / 20 / 100
    end
    GetDodgeChanceFromAttribute = function(...)
        assert(select("#", ...) == 0, "dodge takes no arguments")
        return 25 / 20 / 100
    end
    GetSpellCritChanceFromStat = function(_, value)
        return value / 60 / 100
    end
    BLOCK_VALUE_PER_STRENGTH = 20
    -- ItemStats caches UnitStat at load, so reload it to see the stub.
    T.load("Lib/ItemStats")
    local rates = ns.ItemStats.PlayerRates()
    near(rates.CRIT_AGI, 0.05, "rates: crit per Agility in percent")
    near(rates.DODGE_AGI, 0.05, "rates: dodge per Agility in percent")
    near(rates.SPELLCRIT_INT, 1 / 60, "rates: spell crit per Intellect in percent")
    near(rates.BLOCKVALUE_STR, 0.05, "rates: block value per Strength")
    UnitStat, GetCritChanceFromStat, GetDodgeChanceFromAttribute, GetSpellCritChanceFromStat,
        BLOCK_VALUE_PER_STRENGTH = unpack(saved, 1, 5)
    ns.ItemStats = ItemStats
end
eq(Talents.Tabs(), nil, "talents: nothing without the trait API")
local tab, total = Talents.Dominant()
eq(tab, nil, "talents: no dominant tab without data")
eq(total, 0, "talents: no points without data")
