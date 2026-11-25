-- Colors: color codes, faction colors, and level ranges against the player's level.
local T = ...
local ns, eq, player = T.ns, T.eq, T.player

eq(ns.Colors.Code(1, 0, 0), "|cffff0000", "Code red")
eq(ns.Colors.Code(0.5, 0.5, 0.5), "|cff808080", "Code rounds")
eq(ns.Colors.Text({ r = 0, g = 1, b = 0 }, "hi"), "|cff00ff00hi|r", "Text wraps")
eq(ns.Colors.Faction("A").b > ns.Colors.Faction("A").r, true, "Alliance is blue")
eq(ns.Colors.Faction("H").r > ns.Colors.Faction("H").b, true, "Horde is red")
eq(ns.Colors.Faction("?"), ns.Colors.Faction(nil), "unknown side is neutral")
eq(ns.Colors.ClassToken(nil), nil, "no class token, no color")

player.level = 10 -- below the range: colored by its low end
eq(ns.Colors.LevelRange(20, 30).r, 20, "range above you uses low")
player.level = 25 -- inside
eq(ns.Colors.LevelRange(20, 30).r, "difficult", "range you are in")
player.level = 40 -- outleveled: two below the top
eq(ns.Colors.LevelRange(20, 30).r, 28, "outleveled uses high - 2")
eq(ns.Colors.LevelRange(29, 30).r, 29, "outleveled never goes under low")

-- The table Colors kept at load, so the hardest color can be told from a level's.
QuestDifficultyColors.impossible = { r = "impossible", g = 0, b = 0 }
eq(ns.Colors.Difficulty(33).r, 33, "a level gets its difficulty color")
eq(ns.Colors.Difficulty(-1).r, "impossible", "a skull level is the hardest")
eq(ns.Colors.Difficulty(0).r, "impossible", "so is level 0")
