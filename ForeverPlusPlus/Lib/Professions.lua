-- The player's profession skills by skill line, read once and again only after they change; the
-- herbs and veins in the world with the skill they take, and the chests and fishing pools; and
-- the professions window's recipe rows. Nothing is listened to until a module first asks.
local _, ns = ...

local _G, type, ipairs, pairs, select, setmetatable = _G, type, ipairs, pairs, select, setmetatable
local tinsert = table.insert
local floor, max, min = math.floor, math.max, math.min
local GetProfessions, GetProfessionInfo = GetProfessions, GetProfessionInfo

local Professions = {
    HERBALISM = 182,
    MINING = 186,
    SKINNING = 393,
    FISHING = 356,
    LOCKPICKING = 633,
    BLACKSMITHING = 164,
}
ns.Professions = Professions

-- Blizzard's difficulty colors, the same a trainer uses for recipes. Probe: QuestDifficultyColors
-- is FrameXML's; the values after it are its own.
local COLORS = QuestDifficultyColors or {}
local RED = COLORS.impossible or { r = 1, g = 0.1, b = 0.1 }
local ORANGE = COLORS.verydifficult or { r = 1, g = 0.5, b = 0.25 }
-- Yellow is fixed at the classic (1, 1, 0): this client's QuestDifficultyColors.difficult can be
-- close to the gold of a tooltip title, so "often" wouldn't stand out from the name.
local YELLOW = { r = 1, g = 1, b = 0 }
local GREEN = COLORS.standard or { r = 0.25, g = 0.75, b = 0.25 }
local GRAY = COLORS.trivial or { r = 0.5, g = 0.5, b = 0.5 }
Professions.STANDARD = GREEN -- Blizzard's green for a quest at your level, for "enough"
Professions.TRIVIAL = GRAY -- what Difficulty gives once gathering no longer raises the skill

local HERB, MINE = Professions.HERBALISM, Professions.MINING

-- Herbs and veins by their name in the world: the skill line that gathers them, the skill it
-- takes, and the item they give first. The seed is Classic's, in English; the game teaches the
-- rest (Professions.LearnRequirement, LearnNodeItem), so other languages and Forever's changes
-- fill in as the player meets them. A learned node may lack its skill or its item.
local NODES = ns.GameData.New("professionNodes", { -- object name -> { skill line, skill, item ID }
    ["Peacebloom"] = { HERB, 1, 2447 },
    ["Silverleaf"] = { HERB, 1, 765 },
    ["Earthroot"] = { HERB, 15, 2449 },
    ["Mageroyal"] = { HERB, 50, 785 },
    ["Briarthorn"] = { HERB, 70, 2450 },
    ["Stranglekelp"] = { HERB, 85, 3820 },
    ["Bruiseweed"] = { HERB, 100, 2453 },
    ["Wild Steelbloom"] = { HERB, 115, 3355 },
    ["Grave Moss"] = { HERB, 120, 3369 },
    ["Kingsblood"] = { HERB, 125, 3356 },
    ["Liferoot"] = { HERB, 150, 3357 },
    ["Fadeleaf"] = { HERB, 160, 3818 },
    ["Goldthorn"] = { HERB, 170, 3821 },
    ["Khadgar's Whisker"] = { HERB, 185, 3358 },
    ["Wintersbite"] = { HERB, 195, 3819 },
    ["Firebloom"] = { HERB, 205, 4625 },
    ["Purple Lotus"] = { HERB, 210, 8831 },
    ["Arthas' Tears"] = { HERB, 220, 8836 },
    ["Sungrass"] = { HERB, 230, 8838 },
    ["Blindweed"] = { HERB, 235, 8839 },
    ["Ghost Mushroom"] = { HERB, 245, 8845 },
    ["Gromsblood"] = { HERB, 250, 8846 },
    ["Golden Sansam"] = { HERB, 260, 13464 },
    ["Dreamfoil"] = { HERB, 270, 13463 },
    ["Mountain Silversage"] = { HERB, 280, 13465 },
    ["Plaguebloom"] = { HERB, 285, 13466 },
    ["Icecap"] = { HERB, 290, 13467 },
    ["Black Lotus"] = { HERB, 300, 13468 },

    ["Copper Vein"] = { MINE, 1, 2770 },
    ["Tin Vein"] = { MINE, 65, 2771 },
    ["Incendicite Mineral Vein"] = { MINE, 65, 3340 },
    ["Silver Vein"] = { MINE, 75, 2775 },
    ["Ooze Covered Silver Vein"] = { MINE, 75, 2775 },
    ["Lesser Bloodstone Deposit"] = { MINE, 75, 4278 },
    ["Iron Deposit"] = { MINE, 125, 2772 },
    ["Ooze Covered Iron Deposit"] = { MINE, 125, 2772 },
    ["Indurium Mineral Vein"] = { MINE, 150, 5833 },
    ["Gold Vein"] = { MINE, 155, 2776 },
    ["Ooze Covered Gold Vein"] = { MINE, 155, 2776 },
    ["Mithril Deposit"] = { MINE, 175, 3858 },
    ["Ooze Covered Mithril Deposit"] = { MINE, 175, 3858 },
    ["Truesilver Deposit"] = { MINE, 230, 7911 },
    ["Ooze Covered Truesilver Deposit"] = { MINE, 230, 7911 },
    ["Dark Iron Deposit"] = { MINE, 230, 11370 },
    ["Small Thorium Vein"] = { MINE, 245, 10620 },
    ["Ooze Covered Thorium Vein"] = { MINE, 245, 10620 },
    ["Rich Thorium Vein"] = { MINE, 275, 10620 },
    ["Ooze Covered Rich Thorium Vein"] = { MINE, 275, 10620 },
    ["Hakkari Thorium Vein"] = { MINE, 275, 10620 },
    ["Small Obsidian Chunk"] = { MINE, 305, 22202 },
    ["Large Obsidian Chunk"] = { MINE, 305, 22203 },
}, { label = "Herbs and veins" })

-- The stone a vein gives besides its ore, which no node lists as its item: item ID -> the Mining
-- skill of the lowest vein that gives it. Classic's values.
local STONES = ns.GameData.New("miningStones", {
    [2835] = 1, -- Rough Stone
    [2836] = 65, -- Coarse Stone
    [2838] = 125, -- Heavy Stone
    [7912] = 175, -- Solid Stone
    [12365] = 245, -- Dense Stone
}, { kind = "item", label = "Stones from veins" })

-- Profession tools a character can equip but carries for their profession, not to fight with:
-- item ID -> the skill line. Classic's IDs (Classic Era 1.15 item data); Self Test checks them.
-- Fishing poles are told by their weapon subclass instead, so every pole counts.
local TOOLS = ns.GameData.New("professionTools", {
    [2901] = Professions.MINING, -- Mining Pick
    [5956] = Professions.BLACKSMITHING, -- Blacksmith Hammer
    [7005] = Professions.SKINNING, -- Skinning Knife
    [6219] = 202, -- Arclight Spanner (Engineering)
}, { kind = "item", label = "Profession tools" })

---Whether an item is the stone a vein gives besides its ore (Rough Stone, Coarse Stone, ...).
---@param itemID number
---@return boolean
function Professions.IsStone(itemID)
    return STONES:Get(itemID) ~= nil
end

---Whether an item is a profession tool: a fishing pole, or a tool like the Mining Pick.
---@param itemID number
---@param classID? number
---@param subclassID? number
---@return boolean
function Professions.IsTool(itemID, classID, subclassID)
    -- At run time: Lib/Equipment.lua loads after this file.
    local Equipment = ns.Equipment
    if classID == Equipment.WEAPON and subclassID == Equipment.FISHING_POLE then
        return true
    end
    return TOOLS:Get(itemID) ~= nil
end

local itemSkills -- item ID -> { skill line, skill }, built from the nodes when first asked
local variants = {} -- name -> the known node it's a kind of, or false; emptied when one is learned

-- The known node `name` is a kind of: one whose whole name it starts or ends with, a word apart,
-- the longest such. Forever adds kinds of Classic's nodes, like "Poor Copper Vein", that give the
-- same item, so they get its icon and skill before the game has taught their own.
local function variantOf(name)
    local found = variants[name]
    if found ~= nil then
        return found or nil
    end
    local best, bestLength = false, 0
    for known, node in NODES:Pairs() do
        local length = #known
        if length > bestLength and length < #name and type(known) == "string"
            and ((name:sub(-length - 1) == " " .. known) or (name:sub(1, length + 1) == known .. " ")) then
            best, bestLength = node, length
        end
    end
    variants[name] = best
    return best or nil
end

---The herb or vein named `name` (as the world writes it): { skill line, skill, item ID }, any of
---which may be nil for one learned in game, or nil for a name that isn't a node. A name not known
---itself that is a kind of a known node ("Poor Copper Vein") takes what it lacks from that one.
---@param name string
---@return table? node
function Professions.Node(name)
    local node = NODES:Get(name)
    if (node and node[1] and node[2] and node[3]) or type(name) ~= "string" then
        return node
    end
    local base = variantOf(name)
    if not base then
        return node
    elseif not node then
        return base
    end
    return { node[1] or base[1], node[2] or base[2], node[3] or base[3] }
end

---The gathering skill an item comes from: the skill line and the skill of the lowest herb or vein
---that gives it (the nodes, seeded and learned, and the stones veins give), or nil.
---@param itemID number
---@return number? line
---@return number? skill
function Professions.ItemSkill(itemID)
    if not itemSkills then
        itemSkills = {}
        for _, node in NODES:Pairs() do
            local line, skill, item = node[1], node[2], node[3]
            local known = item and itemSkills[item]
            if line and skill and item and not (known and known[2] <= skill) then
                itemSkills[item] = { line, skill }
            end
        end
        for item, skill in STONES:Pairs() do
            itemSkills[item] = itemSkills[item] or { MINE, skill }
        end
    end
    local entry = itemSkills[itemID]
    if entry then
        return entry[1], entry[2]
    end
end

-- The gathering skill lines a node's requirement can name, and their English names (the seed's
-- language) for when the client can't say its own.
local GATHERING = { HERB, MINE }
local ENGLISH = { [HERB] = "Herbalism", [MINE] = "Mining" }
local lineNames = {} -- skill line -> its name in the client's language, once read

local function lineName(line)
    if lineNames[line] then
        return lineNames[line]
    end
    local name
    -- Probes: both are Mainline's; the second needs no profession info loaded.
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(line)
        name = info and info.professionName
    end
    if not (name and ns.IsText(name, true))
        and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        name = C_TradeSkillUI.GetTradeSkillDisplayName(line)
    end
    if name and ns.IsText(name, true) then
        lineNames[line] = name
        return name
    end
end

---A gathering skill line's name in the client's language ("Mining"), or the English one when the
---client can't say.
---@param line number
---@return string?
function Professions.LineName(line)
    return lineName(line) or ENGLISH[line]
end

---The gathering skill line (Herbalism or Mining) named `skill` in the client's language, or nil.
---@param skill string
---@return number? line
function Professions.GatheringLine(skill)
    for _, line in ipairs(GATHERING) do
        if skill == ENGLISH[line] or skill == lineName(line) or skill == select(2, Professions.Rank(line)) then
            return line
        end
    end
end

---Learns what Blizzard's "Requires Herbalism (75)" line under node `name` says: the skill line
---and skill it takes. Does nothing when `skill` isn't Herbalism or Mining, or it's known already.
---@param name string
---@param skill string the profession as the line names it
---@param need number
---@return boolean changed
function Professions.LearnRequirement(name, skill, need)
    local line = type(name) == "string" and name ~= "" and type(need) == "number"
        and Professions.GatheringLine(skill)
    if not line then
        return false
    end
    local node = NODES:Get(name)
    if node and node[1] == line and node[2] == need then
        return false
    end
    itemSkills, variants = nil, {}
    return NODES:Learn(name, { line, need, node and node[3] })
end

---Learns the item node `name` gives, from the loot window after gathering it, and with `line`
---(Herbalism or Mining, from the spell that gathered it) its skill line when that isn't known.
---Keeps a known item: a vein gives stone too, and which comes first can vary.
---@param name string
---@param item number item ID
---@param line? number the skill line that gathered it
---@return boolean changed
function Professions.LearnNodeItem(name, item, line)
    if type(name) ~= "string" or name == "" or type(item) ~= "number" then
        return false
    end
    if line ~= HERB and line ~= MINE then
        line = nil
    end
    local node = NODES:Get(name)
    local knownItem, knownLine = node and node[3], node and node[1]
    if knownItem and (knownLine or not line) then
        return false
    end
    itemSkills, variants = nil, {}
    return NODES:Learn(name, { knownLine or line, node and node[2], knownItem or item })
end

-- Spots that spawn either of two veins: the rarer one -> the vein it takes the place of. Classic's
-- (the rare spawns GatherMate2 also knows); the game shows no list of them.
local SPAWNS = ns.GameData.New("sharedSpawns", {
    ["Silver Vein"] = "Tin Vein",
    ["Gold Vein"] = "Iron Deposit",
    ["Truesilver Deposit"] = "Mithril Deposit",
    ["Ooze Covered Silver Vein"] = "Tin Vein",
    ["Ooze Covered Gold Vein"] = "Iron Deposit",
    ["Ooze Covered Truesilver Deposit"] = "Mithril Deposit",
}, { label = "Shared vein spawns" })

---Whether a spot that spawned node `a` can spawn node `b` instead, so the two are one node on a
---map: the same name, a rare vein and the one it takes the place of (Silver for Tin), or two
---names that give the same item (Poor Copper Vein and Copper Vein).
---@param a string
---@param b string
---@return boolean
function Professions.SharesSpawn(a, b)
    if a == b then
        return true
    end
    local groupA, groupB = SPAWNS:Get(a) or a, SPAWNS:Get(b) or b
    if groupA == groupB then
        return true
    end
    local nodeA, nodeB = Professions.Node(a), Professions.Node(b)
    return nodeA ~= nil and nodeB ~= nil and nodeA[3] ~= nil and nodeA[3] == nodeB[3]
end

-- Kinds of node ---------------------------------------------------------------------------------
-- What maps sort, filter, and color nodes by. Herbs and veins are told by their skill line; a
-- chest or a fishing pool is never a node above, so its kind comes from the spell that took it.

---Every kind of node, in the order maps list them.
Professions.KINDS = { "herb", "ore", "treasure", "fish" }

local LINE_KINDS = {
    [HERB] = "herb",
    [MINE] = "ore",
    [Professions.LOCKPICKING] = "treasure",
    [Professions.FISHING] = "fish",
}
local KIND_LINES = {}
for line, kind in pairs(LINE_KINDS) do
    KIND_LINES[kind] = line
end

-- Chests ----------------------------------------------------------------------------------------
-- The chests in the world, by name: true, or the Lockpicking a locked one takes once its "Requires
-- Lockpicking (N)" line was read. The Opening spell opens much besides chests (quest objects, crates
-- a quest asks for), so only these count as treasure. Seed: Classic's world chests, from memory of
-- Classic Era (2026-11-07), unverified on Forever; a world object's Lockpicking line teaches more.
-- (Pick Lock doesn't: it's cast on lockboxes in the bags too.)
local CHESTS = ns.GameData.New("treasureNodes", {
    ["Battered Chest"] = true,
    ["Tattered Chest"] = true,
    ["Solid Chest"] = true,
    ["Large Battered Chest"] = true,
    ["Large Iron Bound Chest"] = true,
    ["Large Solid Chest"] = true,
    ["Large Mithril Bound Chest"] = true,
    ["Dented Footlocker"] = true,
    ["Mossy Footlocker"] = true,
    ["Waterlogged Footlocker"] = true,
    ["Buccaneer's Strongbox"] = true,
    ["Box of Assorted Parts"] = true,
    ["Burial Chest"] = true,
})

local LOCK = Professions.LOCKPICKING

---Whether `name` is a chest, and the Lockpicking a locked one takes when that's known.
---@param name string
---@return boolean chest
---@return number? need
function Professions.Chest(name)
    local value = type(name) == "string" and CHESTS:Get(name)
    if not value then
        return false
    end
    return true, type(value) == "number" and value or nil
end

---Every chest known, seeded and learned: `for name, value in Professions.EachChest()`, value as
---the set keeps it (true, or the Lockpicking a locked one takes).
---@return function iterator
function Professions.EachChest()
    return CHESTS:Pairs()
end

---Learns that `name` is a chest, and with `need` the Lockpicking it takes: from its "Requires
---Lockpicking (N)" line.
---@param name string
---@param need? number
---@return boolean changed
function Professions.LearnChest(name, need)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local chest, known = Professions.Chest(name)
    if chest and (known or not need) then
        return false
    end
    return CHESTS:Learn(name, type(need) == "number" and need or true)
end

-- Fishing pools -----------------------------------------------------------------------------------
-- The pools in the world, by name, and the world object ID each was seen with, so a pool's loot
-- (whose source is the pool) names it even when nothing else did. Seed: Classic's pools, from
-- memory of Classic Era (2026-11-07), unverified on Forever; play teaches more.
local POOLS = ns.GameData.New("fishingPools", {
    ["Floating Wreckage"] = true,
    ["Floating Debris"] = true,
    ["Oil Spill"] = true,
    ["Patch of Elemental Water"] = true,
    ["School of Deviate Fish"] = true,
    ["Oily Blackmouth School"] = true,
    ["Firefin Snapper School"] = true,
    ["Sagefish School"] = true,
    ["Greater Sagefish School"] = true,
    ["Stonescale Eel Swarm"] = true,
    ["Schooner Wreckage"] = true,
    ["Waterlogged Wreckage"] = true,
})
local POOL_OBJECTS = ns.GameData.New("fishingPoolObjects", {}) -- world object ID -> pool name

---Whether `name` is a fishing pool.
---@param name string
---@return boolean
function Professions.Pool(name)
    return type(name) == "string" and POOLS:Get(name) == true
end

---Every fishing pool known: `for name in Professions.EachPool()`.
---@return function iterator
function Professions.EachPool()
    return POOLS:Pairs()
end

---The pool a world object ID was seen as, or nil.
---@param objectID number
---@return string? name
function Professions.PoolByObject(objectID)
    return type(objectID) == "number" and POOL_OBJECTS:Get(objectID) or nil
end

---Learns that `name` is a fishing pool, and with `objectID` that its world object is that one.
---@param name string
---@param objectID? number
---@return boolean changed
function Professions.LearnPool(name, objectID)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local changed = POOLS:Learn(name, true)
    if type(objectID) == "number" then
        changed = POOL_OBJECTS:Learn(objectID, name) or changed
    end
    return changed
end

---Whether `skill`, as a requirement line names it, is Lockpicking.
---@param skill string
---@return boolean
function Professions.IsLockpicking(skill)
    return skill == "Lockpicking" or skill == select(2, Professions.Rank(LOCK))
end

---The kind of node a skill line gathers ("herb", "ore", "treasure", "fish"), or nil.
---@param line number
---@return string? kind
function Professions.LineKind(line)
    return LINE_KINDS[line]
end

---The skill line that gathers a kind of node, or nil. Treasure's is Lockpicking, though a chest
---anyone can open needs none.
---@param kind string
---@return number? line
function Professions.KindLine(kind)
    return KIND_LINES[kind]
end

---The kind of the herb or vein named `name` ("herb" or "ore"), or nil for a name that isn't one
---or whose skill line isn't known yet.
---@param name string
---@return string? kind
function Professions.Kind(name)
    local node = Professions.Node(name)
    return node and LINE_KINDS[node[1]]
end

---Every herb and vein known, seeded and learned: `for name, node in Professions.EachNode()`,
---with node as Professions.Node gives it. Don't change the tables.
---@return function iterator
function Professions.EachNode()
    return NODES:Pairs()
end

---Forgets every herb and vein learned in game; the seed stays.
function Professions.ForgetNodes()
    NODES:Forget()
    itemSkills, variants = nil, {}
end

---How hard gathering something that needs `need` is at skill `rank`, as a color (r, g, b): red
---can't yet, then orange (a skill point every time), yellow (often), green (sometimes), and gray
---(never). Without a rank (the player doesn't have the profession) it's red.
---@param rank number?
---@param need number
---@return table color
function Professions.Difficulty(rank, need)
    if not rank or rank < need then
        return RED
    elseif rank < need + 25 then
        return ORANGE
    elseif rank < need + 50 then
        return YELLOW
    elseif rank < need + 100 then
        return GREEN
    end
    return GRAY
end

---The Skinning skill a creature of `level` needs.
---@param level number
---@return number
function Professions.SkinningNeed(level)
    if level <= 10 then
        return 1
    elseif level <= 20 then
        return level * 10 - 100
    end
    return level * 5
end

-- A recipe's colors by skill ---------------------------------------------------------------------
-- A recipe is orange (a skill-up every time) below its yellow level, yellow (usually) from there,
-- green (sometimes) from halfway to gray, and gray (never) from its gray level on. The game's
-- recipe info gives only the gray level (maxTrivialLevel) and the color now (relativeDifficulty);
-- the yellow level is in its SkillLineAbility table (docs/forever-api.md), and green is worked out
-- as Classic's servers did, halfway between rounded down. Difficulties are
-- Enum.TradeskillRelativeDifficulty's numbers, written out so this needs no client.

local DIFFICULTY = { OPTIMAL = 0, MEDIUM = 1, EASY = 2, TRIVIAL = 3 }
Professions.DIFFICULTY = DIFFICULTY

local BAR_PAD = 5 -- the fewest skill points the bar shows before yellow and after gray

---The skill levels a recipe turns yellow, green, and gray at, or nil when the numbers don't make
---sense (missing, or yellow past gray). A recipe whose yellow level is its gray level goes from
---orange straight to gray.
---@param yellow number?
---@param gray number?
---@return table|nil levels `{ yellow, green, gray }`
function Professions.RecipeLevels(yellow, gray)
    if type(yellow) ~= "number" or type(gray) ~= "number" or yellow < 1 or yellow > gray then
        return nil
    end
    return { yellow = yellow, green = floor((yellow + gray) / 2), gray = gray }
end

---The difficulty `levels` (Professions.RecipeLevels) give at `skill`, one of Professions.DIFFICULTY:
---OPTIMAL (orange), MEDIUM (yellow), EASY (green), or TRIVIAL (gray), as relativeDifficulty is.
---@param levels table
---@param skill number
---@return number
function Professions.LevelDifficulty(levels, skill)
    if skill >= levels.gray then
        return DIFFICULTY.TRIVIAL
    elseif skill >= levels.green then
        return DIFFICULTY.EASY
    elseif skill >= levels.yellow then
        return DIFFICULTY.MEDIUM
    end
    return DIFFICULTY.OPTIMAL
end

---A bar of a recipe's colors from a little before yellow to a little after gray, in proportion to
---the skill: `from` and `to` are the skill it starts and ends at, `segments` each color's part as
---`{ difficulty, left, right, level }` (fractions of the bar, and the skill it starts at; none for
---a color the recipe skips), and `marker` where `skill` falls (0 to 1, held at the ends).
---@param levels table Professions.RecipeLevels
---@param skill number?
---@return table bar `{ from, to, segments, marker }`
function Professions.LevelBar(levels, skill)
    local pad = max(floor((levels.gray - levels.yellow) / 2), BAR_PAD)
    local from, to = levels.yellow - pad, levels.gray + pad
    local span = to - from
    local function at(level)
        return (level - from) / span
    end
    local bounds = {
        { DIFFICULTY.OPTIMAL, from, levels.yellow },
        { DIFFICULTY.MEDIUM, levels.yellow, levels.green },
        { DIFFICULTY.EASY, levels.green, levels.gray },
        { DIFFICULTY.TRIVIAL, levels.gray, to },
    }
    local segments = {}
    for _, bound in ipairs(bounds) do
        if bound[3] > bound[2] then
            segments[#segments + 1] = { bound[1], at(bound[2]), at(bound[3]), bound[2] }
        end
    end
    local marker
    if type(skill) == "number" then
        marker = min(max(at(skill), 0), 1)
    end
    return { from = from, to = to, segments = segments, marker = marker }
end

-- Recipes the player doesn't know ---------------------------------------------------------------
-- Professions' Data.lua has every recipe of the game's SkillLineAbility table as
-- `{ yellow, gray, line, spell, item, learn }`, by its ability ID: the item that teaches it and
-- the skill that item needs, where the tables say. A recipe no item teaches comes from a trainer
-- or elsewhere, and the tables don't say what skill that takes (docs/table-survey.md, section 6).
-- What's here is the pure part of Professions' Unlearned Recipes: whether one can be learned,
-- the filters, the search match, and the categories it goes under in the recipe list.

---Whether the player can learn a recipe that needs `learn` now, at their skill `skill` and with
---their rank's most `max`: "now", "soon" (within `soon` points), "rank" (past what their rank
---allows: they need the next rank first), "later", or "unknown" without a learn skill.
---@param learn number?
---@param skill number?
---@param max number? the most the player's rank allows
---@param soon number how many points away still counts as soon
---@return string state
function Professions.LearnState(learn, skill, max, soon)
    if type(learn) ~= "number" or type(skill) ~= "number" then
        return "unknown"
    end
    if skill >= learn then
        return "now"
    elseif type(max) == "number" and max > 0 and learn > max then
        return "rank"
    elseif learn - skill <= soon then
        return "soon"
    end
    return "later"
end

-- When a recipe can be learned, as the filter menu groups it: a recipe past the rank's most can be
-- learned later, once the next rank is. One without a learn skill has none.
local LEARN_WHEN = { now = "now", soon = "soon", later = "later", rank = "later" }

---Which of the filter menu's Now, Soon, and Later a learn state (Professions.LearnState) is in, or
---nil for "unknown".
---@param state string
---@return string|nil when
function Professions.LearnWhen(state)
    return LEARN_WHEN[state]
end

---Where a recipe the player doesn't know comes from, as the filter menu offers them, in its order:
---a recipe is the first kind whose `test(recipe)` is true, `recipe` being `{ item }` (the item that
---teaches it, from Data.lua, or nil). The tables say only whether an item teaches it; a later source
---of where recipes come from (QuestieDB: vendors, drops, quests, trainers) adds kinds before "other"
---and gives the recipe what their tests read. Each kind's label is the module's.
Professions.RECIPE_SOURCES = {
    { key = "item", test = function(recipe) return recipe.item ~= nil end },
    { key = "other", test = function() return true end },
}

---The key of the source kind (Professions.RECIPE_SOURCES) a recipe is.
---@param recipe table `{ item? }`
---@return string key
function Professions.RecipeSource(recipe)
    for _, kind in ipairs(Professions.RECIPE_SOURCES) do
        if kind.test(recipe) then
            return kind.key
        end
    end
    return "other"
end

---Whether a recipe the player doesn't know passes the unlearned filters: its source kind is on in
---`filters.sources` (by key), its time to learn (Professions.LearnWhen of `recipe.state`) is on in
---`filters.when` (one without a learn skill always is, since when isn't known), and, with
---`filters.bags`, the item that teaches it is in the bags (`recipe.inBags`).
---@param recipe table `{ item?, state, inBags? }`
---@param filters table `{ sources = { [key] = boolean }, when = { now, soon, later }, bags = boolean }`
---@return boolean
function Professions.PassesUnlearned(recipe, filters)
    if not filters.sources[Professions.RecipeSource(recipe)] then
        return false
    end
    local when = Professions.LearnWhen(recipe.state)
    if when and not filters.when[when] then
        return false
    end
    if filters.bags and not recipe.inBags then
        return false
    end
    return true
end

---Whether a recipe's name matches the recipe list's search text the way a player reads it: the text
---anywhere in the name, letters in any case, taken as plain text. Empty text matches everything.
---@param name string
---@param text string|nil
---@return boolean
function Professions.MatchesSearch(name, text)
    if not text or text == "" then
        return true
    end
    return name:lower():find(text:lower(), 1, true) ~= nil
end

-- Names the game's data gives test, placeholder, and retired recipes (as it does items: "[DNT]
-- ...", "Deprecated ..."), which no player can learn.
local JUNK_NAMES = { "^%[DNT%]", "^%[PH%]", "^Deprecated", "^DEPRECATED", "^zz", "^Test " }

---Whether a recipe's info is one the game knows but no player can learn: disabled, a dummy, without
---a name, or named as test or retired data.
---@param info table a recipe's info (C_TradeSkillUI.GetRecipeInfo)
---@return boolean
function Professions.IsJunkRecipe(info)
    local name = info.name
    if info.disabled or info.isDummyRecipe or type(name) ~= "string" or name == "" then
        return true
    end
    for _, pattern in ipairs(JUNK_NAMES) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

local function byOrderThenName(a, b)
    local oa, ob = a.info.uiOrder or 0, b.info.uiOrder or 0
    if oa ~= ob then
        return oa < ob
    end
    return (a.info.name or ""):lower() < (b.info.name or ""):lower()
end

-- Blizzard's order for a category's recipes (SortCategoryData, Blizzard_ProfessionsTemplates):
-- the skill a recipe turns gray at, highest first, then item level, highest first, then name.
local NO_DIFFICULTY = 99

local function byRecipe(a, b)
    -- Blizzard's first key: orange before yellow, green, and gray. A recipe without one (the
    -- game gives none) goes after those, so the order stays one order whatever is compared.
    local da = type(a.difficulty) == "number" and a.difficulty or NO_DIFFICULTY
    local db = type(b.difficulty) == "number" and b.difficulty or NO_DIFFICULTY
    if da ~= db then
        return da < db
    end
    local ga, gb = a.maxTrivialLevel or 0, b.maxTrivialLevel or 0
    if ga ~= gb then
        return ga > gb
    end
    local la, lb = a.itemLevel or 0, b.itemLevel or 0
    if la ~= lb then
        return la > lb
    end
    local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
    if na ~= nb then
        return na < nb
    end
    return (a.recipeID or 0) < (b.recipeID or 0)
end

---The categories `recipes` go under in the recipe list, as Blizzard's list builds them for its
---unlearned recipes (Professions.GenerateCraftingDataProvider): each recipe in its category, and
---each category under its parent. With `keepEmpty` false (not searching) a category with no recipes
---of its own is left out, and what was under it stands at the top, as Blizzard's does. A recipe
---whose category `categoryOf` doesn't know is left out. Returns the top categories, each
---`{ info, categories, recipes }`, categories by `uiOrder` then name and recipes in Blizzard's order.
---@param recipes table[] recipe infos: `{ recipeID, categoryID, name, maxTrivialLevel?, itemLevel? }`
---@param categoryOf fun(id: number): table|nil a category's info: `{ categoryID, parentCategoryID?, name, uiOrder? }`
---@param keepEmpty boolean
---@return table[] top
function Professions.RecipeTree(recipes, categoryOf, keepEmpty)
    local nodes = {} -- category ID -> node, or false for one not known
    local function nodeOf(id)
        local node = nodes[id]
        if node == nil then
            local info = id and categoryOf(id)
            node = info and { info = info, categories = {}, recipes = {} } or false
            nodes[id] = node
            if node and info.parentCategoryID then
                nodeOf(info.parentCategoryID)
            end
        end
        return node
    end
    for _, recipe in ipairs(recipes) do
        local node = nodeOf(recipe.categoryID)
        if node then
            node.recipes[#node.recipes + 1] = recipe
        end
    end
    ---@type table[]
    local top = {}
    for _, node in pairs(nodes) do
        if node and (keepEmpty or #node.recipes > 0) then
            local parent = nodes[node.info.parentCategoryID]
            if parent and (keepEmpty or #parent.recipes > 0) then
                parent.categories[#parent.categories + 1] = node
            else
                top[#top + 1] = node
            end
        end
    end
    local function sortNode(node)
        table.sort(node.categories, byOrderThenName)
        table.sort(node.recipes, byRecipe)
        for _, child in ipairs(node.categories) do
            sortNode(child)
        end
    end
    for _, node in ipairs(top) do
        sortNode(node)
    end
    table.sort(top, byOrderThenName)
    return top
end

local known -- skill line -> { rank, name, icon }, or nil until read
local listening = false

local function readable(value)
    return ns.IsReadable(value) and value ~= nil
end

local function add(index)
    if not index then
        return
    end
    local name, icon, level, maxLevel, _, _, line, modifier = GetProfessionInfo(index)
    if readable(line) and ns.IsNumber(level) then
        -- The modifier (from gear or racials) counts toward what the player can gather.
        local rank = level + (ns.IsNumber(modifier) and modifier or 0)
        known[line] = { rank = rank, name = readable(name) and name or nil,
            icon = readable(icon) and icon or nil, level = level,
            max = ns.IsNumber(maxLevel) and maxLevel or nil }
    end
end

local function read()
    known = {}
    -- Two primary professions, archaeology, fishing, cooking; any may be nil.
    local first, second, archaeology, fishing, cooking = GetProfessions()
    add(first)
    add(second)
    add(archaeology)
    add(fishing)
    add(cooking)
end

local function forget()
    known = nil
end

-- Lockpicking isn't a profession in the list above: rogues have it as a skill they learn with
-- Pick Lock, and, as in Classic, it's five times their level up to 300.
local PICK_LOCK = ns.GameData.Spell(1804, "Pick Lock")
local LOCKPICKING_CAP = 300

local function lockpicking()
    -- At run time: Lib/Spellbook.lua loads after this file.
    if not ns.Spellbook.IsKnown(PICK_LOCK) then
        return nil
    end
    local level = UnitLevel("player")
    if not (ns.IsNumber(level)) then
        return nil
    end
    local rank = level * 5
    if rank > LOCKPICKING_CAP then
        rank = LOCKPICKING_CAP
    end
    local name, icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(PICK_LOCK)
    end
    -- Probe: the skill line's own name, when the client has profession info for it.
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(Professions.LOCKPICKING)
        name = info and readable(info.professionName) and info.professionName ~= "" and info.professionName or nil
    end
    return rank, name, readable(icon) and icon or nil
end

---The player's skill in a profession (with bonuses from gear), its name in the client's language,
---and its icon, or nil when the player doesn't have it. `line` is a skill line ID such as
---`Professions.HERBALISM`. For `Professions.LOCKPICKING` it's the rogue's Lockpicking skill.
---@param line number
---@return number? rank
---@return string? name
---@return number|string|nil icon
function Professions.Rank(line)
    if line == Professions.LOCKPICKING then
        return lockpicking()
    end
    if not (GetProfessions and GetProfessionInfo) then
        return nil
    end
    if not listening then
        listening = true
        ns.On("SKILL_LINES_CHANGED", forget)
        ns.On("CHAT_MSG_SKILL", forget)
    end
    if not known then
        read()
    end
    local info = known[line]
    if info then
        return info.rank, info.name, info.icon
    end
end

---The player's skill in a profession as its window shows it, without gear or racial bonuses, and
---the most its rank allows (131 and 150), or nil without the profession. Not for Lockpicking.
---@param line number
---@return number? level
---@return number? max
function Professions.Progress(line)
    if line == Professions.LOCKPICKING or not Professions.Rank(line) then
        return nil
    end
    local info = known and known[line]
    return info and info.level, info and info.max
end

-- The professions window's recipe list -------------------------------------------------------------
-- Its rows are ProfessionsRecipeListRecipeMixin buttons (Blizzard_ProfessionsTemplates, load on
-- demand) in a scroll box: name, skill-up arrow, craftable count, lock icon.

---Calls `fn(row)` for each recipe row the professions window shows now. A row hook (`fn(row,
---node)`, with the node left out) can be given as it is.
---@param fn fun(row: table, node?: table)
function Professions.EachRecipeRow(fn)
    local frame = _G.ProfessionsFrame
    local page = frame and frame.CraftingPage
    local box = page and page.RecipeList and page.RecipeList.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(fn)
    end
end

---Hooks the recipe rows while `module` is on: each of `hooks` (a row method such as "Init" or
---"OnLeave" -> `fn(row, ...)`) runs after the row's own. Rows built from now on carry the hooked
---mixin; rows built before (another addon opened the window first) keep the old methods and are
---hooked one by one. Returns false while the mixin's addon hasn't loaded: call again on
---ADDON_LOADED or TRADE_SKILL_SHOW. Keep `hooks` and its functions the same every call, since a
---hook is made once per function.
---@param module table
---@param hooks table<string, function>
---@return boolean
function Professions.HookRecipeRows(module, hooks)
    local mixin = _G.ProfessionsRecipeListRecipeMixin
    if not mixin then
        return false
    end
    for method, fn in pairs(hooks) do
        module:Hook(mixin, method, fn)
    end
    Professions.EachRecipeRow(function(row)
        for method, fn in pairs(hooks) do
            if row[method] ~= mixin[method] then
                module:Hook(row, method, fn)
            end
        end
    end)
    return true
end

---The recipe to show for `info`: a recipe with ranks stands for the best rank the player knows, as
---Blizzard's form and list show it. Probe: Professions.GetHighestLearnedRecipe is Blizzard's own
---global `Professions` (Blizzard_ProfessionsTemplates, Mainline), not this table.
---@param info table|nil a recipe's info (C_TradeSkillUI.GetRecipeInfo)
---@return table|nil
function Professions.BestRank(info)
    local blizzard = _G.Professions
    if info and type(blizzard) == "table" and blizzard.GetHighestLearnedRecipe then
        return blizzard.GetHighestLearnedRecipe(info) or info
    end
    return info
end

---The recipe a row of the recipe list is about, at its best known rank, or nil (a category header).
---@param row table a recipe row
---@param node? table the row's element data, when the caller has it (Init's argument)
---@return table|nil
function Professions.RowRecipe(row, node)
    node = node or (row.GetElementData and row:GetElementData())
    local data = node and (node.GetData and node:GetData() or node.data)
    return Professions.BestRank(data and data.recipeInfo)
end

---Blizzard's recipe form on the professions window's crafting page (the selected recipe, its
---reagents), or nil before Blizzard_Professions has loaded.
---@return table|nil
function Professions.RecipeForm()
    local frame = _G.ProfessionsFrame
    local page = frame and frame.CraftingPage
    return page and page.SchematicForm
end

-- Columns at the right end of a row ----------------------------------------------------------------
-- What modules draw at the right end of a recipe row, each in a column of its own, so they line up
-- down the list. A column takes its space only while its module uses it (its option is on and the
-- list can have it), on every row then, whether a row has something in it or not; the columns left
-- of it sit further right while it doesn't. Orders in use, nearest the row's end first: 10 Appearance
-- Icons' mark, 20 the Professions module's Skill-Ups Left number, 30 its Crafting Costs profit.
--
-- Blizzard's Init gives the name the row's width less the lock, the craftable count, the skill-up
-- arrow, and 10 pixels, cuts a longer name short with "...", and shows the whole name in a tooltip
-- then. Our columns need more than those 10 pixels, so the name is sized the same way but ending
-- before the furthest-left thing a row shows; on a row too narrow for the name and all of them,
-- the furthest-left ones are left out.

local ROW_PADDING = 10 -- Blizzard's own, in ProfessionsRecipeListRecipeMixin:Init
local LABEL_MIN = 40   -- less of a name than this isn't worth showing beside a column of ours
local LABEL_GAP = 6    -- between the name (and its craftable count) and the nearest column
local LOCK_NUDGE = 2   -- a disabled recipe's lock has that much empty at its left

local columns = {}                                -- every column, nearest the row's end first
local placed = setmetatable({}, { __mode = "k" }) -- row -> { [column] = { region, width, x } }

local Column = {}
Column.__index = Column

-- How far a column's right edge is from the row's end: past every column in use before it.
local function offsetOf(column)
    local x = 0
    for _, other in ipairs(columns) do
        if other == column then
            return x + other.gap
        elseif other.used then
            x = x + other.gap + other.width
        end
    end
    return x
end

-- Puts what a row shows in its columns where they go now, and sizes the name to end before them.
local function layout(row)
    local label, here = row.Label, placed[row]
    if not (label and here) then
        return
    end
    local lock, count, skill = row.LockedIcon, row.Count, row.SkillUps
    lock = lock and lock:IsShown() and lock or nil
    local taken = skill and skill:GetWidth() or 0
    if lock then
        taken = taken + lock:GetWidth()
    end
    if count and count:IsShown() then
        taken = taken + count:GetStringWidth()
    end
    local full, room = label:GetStringWidth(), row:GetWidth() - taken
    local reserved
    repeat
        reserved = ROW_PADDING
        local last -- the furthest-left column this row shows something in
        for column, entry in pairs(here) do
            entry.x = offsetOf(column)
            local need = entry.x + entry.width + LABEL_GAP
            if need > reserved then
                reserved, last = need, column
            end
        end
        local fits = room - reserved >= LABEL_MIN or full <= room - reserved
        if not fits and last then
            here[last].region:Hide()
            here[last] = nil
        end
    until fits or not last
    for _, entry in pairs(here) do
        local region = entry.region
        region:ClearAllPoints()
        if lock then
            region:SetPoint("RIGHT", lock, "LEFT", LOCK_NUDGE - entry.x, 0)
        else
            region:SetPoint("RIGHT", row, "RIGHT", -entry.x, 0)
        end
    end
    local width = room - reserved
    label:SetWidth(width < full and width or full)
end

---Whether the column takes its space on the rows: true while the module draws in it at all (its
---option is on, and the open list can have it). Off, what it had on the rows is forgotten (the
---module hides its own regions) and the columns left of it move right. Cheap to call again with
---the same answer.
---@param on any
function Column:Use(on)
    on = on and true or false
    if self.used == on then
        return
    end
    self.used = on
    if not on then
        for _, here in pairs(placed) do
            here[self] = nil
        end
    end
    Professions.EachRecipeRow(layout)
end

---Puts `region` (the module's own texture or font string on the row, shown) in the column on this
---row, its right edge at the column's, or says the row has nothing there with nil. Call it each
---time the row is drawn, after the region has its text or size. On a row too narrow, the region
---may be hidden.
---@param row table a recipe row
---@param region? table
---@param width? number what the region takes, when it isn't the column's own width
function Column:Place(row, region, width)
    if not (row and row.Label) then
        return
    end
    local here = placed[row]
    if not here then
        here = {}
        placed[row] = here
    end
    here[self] = region and { region = region, width = width or self.width } or nil
    layout(row)
end

---A column at the right end of the recipe rows, for one module. Not in use until `column:Use(true)`.
---@param order number where it goes among the others, lowest nearest the row's end
---@param width number its width, which the columns left of it are moved by
---@param gap number the space at its right
---@return table column with `Use` and `Place`
function Professions.NewRowColumn(order, width, gap)
    local column = setmetatable({ order = order, width = width, gap = gap, used = false }, Column)
    local at = #columns + 1
    for i, other in ipairs(columns) do
        if order < other.order then
            at = i
            break
        end
    end
    tinsert(columns, at, column)
    return column
end
