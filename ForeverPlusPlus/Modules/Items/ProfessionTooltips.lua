-- Profession Tooltips: the skill a herb, vein, skinnable beast, or locked lockbox or chest needs,
-- in its tooltip, colored against the player's skill the way a trainer colors recipes: red can't
-- yet, then orange, yellow, green, and gray as it gets easier. Herbs, ore, and stone items say
-- the skill that gathers them. Gathering is shown only for professions the player has, or always
-- (red without it); Lockpicking only for characters who can pick locks. Ideas from
-- GatherSkillTooltip; none of its code.
--
-- Fishing isn't here: in Classic what a pool or a fish needs depends on the zone, not on it.
-- Herb and vein names start in English (Lib/Professions); a name in another language, or one a
-- patch changed, is learned from Blizzard's "Requires Herbalism (N)" line the first time its
-- tooltip shows one.
local _, ns = ...

local type, ipairs, setmetatable = type, ipairs, setmetatable
local gsub, gmatch, match, find, concat = string.gsub, string.gmatch, string.match, string.find, table.concat
local format = string.format
local TooltipDataProcessor, Enum = TooltipDataProcessor, Enum
local UnitIsPlayer, UnitPlayerControlled, UnitCreatureType = UnitIsPlayer, UnitPlayerControlled, UnitCreatureType
local UnitLevel, UnitIsDead, UnitCanAttack = UnitLevel, UnitIsDead, UnitCanAttack

local L = ns.L
local Colors = ns.Colors
local readable = ns.IsReadable
local Professions = ns.Professions
local ItemTooltip = ns.ItemTooltip

local HERB, MINE, SKIN = Professions.HERBALISM, Professions.MINING, Professions.SKINNING
local LOCK, SMITH = Professions.LOCKPICKING, Professions.BLACKSMITHING
local select = select
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

local module = ns.NewModule("ProfessionTooltips", L.PROFTOOLTIPS_DESC, {
    enabled = true,
    show = "known", -- "known" (only for professions you have) or "always"; gathering only
    herbalism = true,
    mining = true,
    skinning = true,
    lockpicking = true,
    blacksmithing = true,
    items = true,
})
module.title = L.PROFTOOLTIPS_TITLE
module.category = "items"

-- Gathering in the world, then locks, then the same skills on items in your bags.
local GATHERING, LOCKS = L.PROFTOOLTIPS_SECTION_GATHERING, L.PROFTOOLTIPS_SECTION_LOCKS
local ITEMS_SECTION = L.PROFTOOLTIPS_SECTION_ITEMS
module.options = {
    {
        key = "show", name = L.PROFTOOLTIPS_SHOW, description = L.PROFTOOLTIPS_SHOW_DESC,
        choices = {
            { "known", L.PROFTOOLTIPS_SHOW_KNOWN },
            { "always", L.PROFTOOLTIPS_SHOW_ALWAYS },
        },
        section = GATHERING,
    },
    {
        key = "herbalism", name = L.PROFTOOLTIPS_HERBALISM, description = L.PROFTOOLTIPS_HERBALISM_DESC,
        section = GATHERING,
    },
    {
        key = "mining", name = L.PROFTOOLTIPS_MINING, description = L.PROFTOOLTIPS_MINING_DESC,
        section = GATHERING,
    },
    {
        key = "skinning", name = L.PROFTOOLTIPS_SKINNING, description = L.PROFTOOLTIPS_SKINNING_DESC,
        section = GATHERING,
    },
    {
        key = "lockpicking", name = L.PROFTOOLTIPS_LOCKPICKING, description = L.PROFTOOLTIPS_LOCKPICKING_DESC,
        section = LOCKS,
    },
    {
        key = "blacksmithing", name = L.PROFTOOLTIPS_BLACKSMITHING,
        description = L.PROFTOOLTIPS_BLACKSMITHING_DESC, section = LOCKS,
    },
    {
        key = "items", name = L.PROFTOOLTIPS_ITEMS, description = L.PROFTOOLTIPS_ITEMS_DESC,
        section = ITEMS_SECTION,
    },
}

-- Data ---------------------------------------------------------------------------------------
-- The skill each gathers at, from Classic. Forever may change some; fix them here. Herbs and
-- veins are in Lib/Professions, which Gathering Map shares and which learns them in game.

local NODES = setmetatable({ -- object name -> { skill line, skill }
    -- Locked chests in the world; add more (and doors) here as they're confirmed in game.
    ["Solid Chest"] = { LOCK, 1 },
    ["Large Solid Chest"] = { LOCK, 1 },
}, {
    -- Herbs and veins, seeded and learned, once their skill is known.
    __index = function(_, name)
        local node = Professions.Node(name)
        if node and node[1] and node[2] then
            return node
        end
    end,
})

-- Locked boxes: item ID -> the Lockpicking skill to open them. The seed is every lockbox in the
-- client's tables (Lib/LockboxSkills.lua, generated); the skill in Blizzard's "Requires
-- Lockpicking (25)" line on a box's tooltip is learned over it, and a box the seed lacks is
-- learned from that line too.
local LOCKBOXES = ns.GameData.New("lockboxes", ns.TableData and ns.TableData.lockboxSkills or {},
    { kind = "item", label = "Lockboxes" })

-- Blacksmiths make skeleton keys that open locks like Lockpicking: item ID, the skill it opens
-- up to, and the Blacksmithing skill that makes it. From Classic; fix them here.
local KEYS = {
    { id = 15869, skill = 100, smith = 100 }, -- Silver Skeleton Key
    { id = 15870, skill = 150, smith = 150 }, -- Golden Skeleton Key
    { id = 15871, skill = 200, smith = 200 }, -- Truesilver Skeleton Key
    { id = 15872, skill = 275, smith = 275 }, -- Arcanite Skeleton Key
}
local KEY_SKILL = {}
for _, key in ipairs(KEYS) do
    KEY_SKILL[key.id] = key.skill
end

local OPTION = { [HERB] = "herbalism", [MINE] = "mining", [SKIN] = "skinning", [LOCK] = "lockpicking" }
local FALLBACK_NAME = {
    [HERB] = L.PROFTOOLTIPS_HERBALISM_NAME,
    [MINE] = L.PROFTOOLTIPS_MINING_NAME,
    [SKIN] = L.PROFTOOLTIPS_SKINNING_NAME,
    [LOCK] = L.PROFTOOLTIPS_LOCKPICKING_NAME,
}

-- Beast and Dragonkin, the creature types that can be skinned (UnitCreatureType's second value).
local SKINNABLE_TYPES = { [1] = true, [2] = true }
local SKINNABLE_NAMES = { [L.PROFTOOLTIPS_BEAST] = true, [L.PROFTOOLTIPS_DRAGONKIN] = true }

-- The Lockpicking skill the player can open locks with: a rogue's own, or, with the Blacksmithing
-- option, that of the best skeleton key their Blacksmithing lets them make (0 when none yet).
-- Nil for anyone with neither.
local function lockRank()
    local rank, name = Professions.Rank(LOCK)
    if module.db.blacksmithing then
        local smith = Professions.Rank(SMITH)
        if smith then
            local best = 0
            for _, key in ipairs(KEYS) do
                if smith >= key.smith and key.skill > best then
                    best = key.skill
                end
            end
            rank = rank and rank > best and rank or best
        end
    end
    return rank, name
end

-- The line for a skill line and skill, colored, or nil when it's off or the player doesn't have
-- the profession and `show` is "known". Without the profession it's red: you can't gather it.
-- Lockpicking is never shown to characters who can't pick locks, whatever `show` says.
-- `text` is L.PROFTOOLTIPS_REQUIRES or _GATHERED.
local function skillLine(line, need, text)
    if not module.db[OPTION[line]] then
        return nil
    end
    local rank, name
    if line == LOCK then
        rank, name = lockRank()
        if not rank then
            return nil
        end
    else
        rank, name = Professions.Rank(line)
        if not rank and module.db.show ~= "always" then
            return nil
        end
    end
    local color = Professions.Difficulty(rank, need)
    return format(text, name or FALLBACK_NAME[line], need), color, rank, name or FALLBACK_NAME[line]
end

-- The "your skill" text that stands in for a bare profession name line under Blizzard's
-- requirement, colored like it: nil when the player has no skill to show.
local function yourSkill(color, rank, name)
    if rank then
        return Colors.Text(color, format(L.PROFTOOLTIPS_YOURS, name, rank))
    end
end

local function addLine(tooltip, text, color)
    tooltip:AddLine(text, color.r, color.g, color.b)
end

-- Blizzard's own "Requires Mining (1)" line on a node or creature: it's recolored in place
-- instead of adding ours. The pattern comes from its string, so it works in any language.
local REQUIRES = "^" .. ns.Text.FormatPattern(ITEM_MIN_SKILL or L.PROFTOOLTIPS_REQUIRES, true) .. "$"

-- World objects and minimap pins -------------------------------------------------------------

-- An object's name without the color codes, icons, and spaces a tooltip may wrap it in.
local function clean(text)
    return strtrim(ns.Text.Plain(text))
end

local leftLine = ns.Text.LeftLine

-- The skill line and its color for the node named in `text`, or nil.
local function nodeLine(text)
    local node = NODES[clean(text)]
    if node then
        return skillLine(node[1], node[2], L.PROFTOOLTIPS_REQUIRES)
    end
end

-- For Blizzard's requirement line `text` of skill line `line`: its color (nil when the option is
-- off or the profession not shown), its text without codes, and the player's rank and profession
-- name. Nothing when `text` isn't such a line.
local function requiresColor(text, line)
    local plain = clean(text)
    local _, digits = match(plain, REQUIRES)
    local need = tonumber(digits)
    if need then
        local _, color, rank, name = skillLine(line, need, L.PROFTOOLTIPS_REQUIRES)
        return color, plain, rank, name
    end
end

-- Whether `text` is just the profession's name (Blizzard or another addon repeating it under the
-- requirement), in either the client's language or ours.
local function isProfessionName(text, line)
    local plain = clean(text)
    local _, name = Professions.Rank(line)
    return plain == FALLBACK_NAME[line] or (name ~= nil and plain == name)
end

-- The index of the line after `index` in data when it only repeats the profession's name, or nil.
local function findNameLine(data, index, line)
    local entry = data.lines[index + 1]
    local text = entry and entry.leftText
    if ns.IsText(text) and isProfessionName(text, line) then
        return index + 1
    end
end

-- The first of data's lines after the first that is Blizzard's requirement line: its index, or nil.
local function findRequires(data)
    local lines = data.lines
    if not (readable(lines) and type(lines) == "table") then
        return nil
    end
    for i = 2, #lines do
        local text = lines[i] and lines[i].leftText
        if ns.IsText(text) and match(clean(text), REQUIRES) then
            return i
        end
    end
end

-- Recolors Blizzard's requirement line on `tooltip`, once it's drawn: `job` is { index, skill
-- line, text, index of a bare name line under it?, skill? }. With a skill, the line at index is a
-- bare profession name line that ours replaces.
local function restyle(tooltip, job)
    local fontString = leftLine(tooltip, job[1])
    if job[5] then
        -- Data lines and drawn lines don't always line up (the game may skip some): when the one
        -- at the data's index isn't the line we mean, find the drawn line with its text. Object
        -- tooltip text isn't secret; a secret one never matches.
        local want = clean(job[3])
        local function drawn(fs)
            local text = fs and fs.GetText and fs:GetText()
            return ns.IsText(text) and clean(text) == want
        end
        if not drawn(fontString) then
            fontString = nil
            for i = 2, tooltip.NumLines and tooltip:NumLines() or 0 do
                local fs = leftLine(tooltip, i)
                if drawn(fs) then
                    fontString = fs
                    break
                end
            end
        end
        -- Blizzard's bare profession name line: it says what we would, so ours replaces it.
        local text, color = skillLine(job[2], job[5], L.PROFTOOLTIPS_REQUIRES)
        if fontString and text then
            fontString:SetText(Colors.Text(color, text))
        end
        return
    end
    local color, _, rank, name = requiresColor(job[3], job[2])
    if fontString and color then
        fontString:SetText(Colors.Text(color, clean(job[3])))
        -- A bare name line below it becomes the player's skill against that requirement.
        local nameString = job[4] and leftLine(tooltip, job[4])
        local text = nameString and yourSkill(color, rank, name)
        if text then
            nameString:SetText(text)
        end
    end
end

local restyling = setmetatable({}, { __mode = "k" }) -- tooltip -> job for its post call

-- A herb or vein under the mouse, or a minimap pin. A world object's tooltip has its name alone
-- on the first line, and the skill line is added after it. A minimap pin's first line holds
-- everything on separate lines, overlapping pins and their quest objectives too, so the skill
-- line goes into that text under its node's name.
local function addNodeLines(tooltip, data)
    if not (module.enabled and readable(data.lines) and type(data.lines) == "table") then
        return
    end
    local first = data.lines[1]
    local text = first and first.leftText
    if not ns.IsText(text) then
        return
    end
    text = gsub(text, "|n", "\n")
    if not find(text, "\n", 1, true) then
        -- Blizzard's own requirement line names the profession and skill in the client's
        -- language: what a herb or vein needs is learned from it, for every language and patch.
        local skill, need = ns.GameData.TooltipRequires(data)
        if skill then
            Professions.LearnRequirement(clean(text), skill, need)
        end
        local node = NODES[clean(text)]
        if not node then
            return
        end
        -- Blizzard already says what it needs: recolor that once it's drawn, don't add another.
        local index = findRequires(data)
        if index then
            restyling[tooltip] = { index, node[1], data.lines[index].leftText,
                findNameLine(data, index, node[1]) }
            return
        end
        -- The game's own "Mining" line under a vein: ours takes its place instead of repeating it.
        for i = 2, #data.lines do
            local other = data.lines[i] and data.lines[i].leftText
            if ns.IsText(other) and isProfessionName(other, node[1]) then
                restyling[tooltip] = { i, node[1], other, nil, node[2] }
                return
            end
        end
        local line, color = nodeLine(text)
        if line then
            addLine(tooltip, line, color)
        end
        return
    end
    local raw, parts, changed = {}, {}, false
    for part in gmatch(text .. "\n", "(.-)\n") do
        raw[#raw + 1] = part
    end
    local i = 1
    while i <= #raw do
        local part = raw[i]
        parts[#parts + 1] = part
        local nextPart = raw[i + 1]
        if nextPart then
            local skill, need = ns.GameData.Requires(clean(nextPart))
            if skill then
                Professions.LearnRequirement(clean(part), skill, need)
            end
        end
        local node = NODES[clean(part)]
        local color, plain, rank, skillName = nil, nil, nil, nil
        if node and nextPart then
            color, plain, rank, skillName = requiresColor(nextPart, node[1])
        end
        if node and nextPart and match(clean(nextPart), REQUIRES) then
            -- Blizzard's own line follows the name: color it, and a bare name line after it
            -- becomes the player's skill.
            if color then
                parts[#parts + 1] = Colors.Text(color, plain)
                changed = true
                local after = raw[i + 2]
                local yours = after and isProfessionName(after, node[1]) and yourSkill(color, rank, skillName)
                if yours then
                    parts[#parts + 1] = yours
                    i = i + 1
                end
            else
                parts[#parts + 1] = nextPart
            end
            i = i + 1
        else
            local line, lineColor = nodeLine(part)
            if line then
                parts[#parts + 1] = Colors.Text(lineColor, line)
                changed = true
                -- The game's own bare name line after it is replaced, not repeated.
                if node and nextPart and isProfessionName(nextPart, node[1]) then
                    i = i + 1
                end
            end
        end
        i = i + 1
    end
    local fontString = changed and leftLine(tooltip, 1)
    if fontString then
        fontString:SetText(concat(parts, "\n"))
    end
end

-- The lines go right under the name, before quest objectives and anything else Blizzard adds:
-- the tooltip's data is kept from its pre call, and they're added once its first line is drawn.
-- Without line calls they go at the end, from the post call.
local pending = setmetatable({}, { __mode = "k" }) -- tooltip -> object data not yet handled

local function onObjectPre(tooltip, data)
    pending[tooltip] = data
    restyling[tooltip] = nil
end

local function onLinePost(tooltip, lineData)
    local data = pending[tooltip]
    local lines = data and data.lines
    if lines and readable(lines) and type(lines) == "table" and lines[1] == lineData then
        pending[tooltip] = nil
        addNodeLines(tooltip, data)
    end
end

local function onObject(tooltip, data)
    local waiting = pending[tooltip]
    pending[tooltip] = nil
    if data and (waiting or not TooltipDataProcessor.AddTooltipPreCall) then
        addNodeLines(tooltip, data)
    end
    local job = restyling[tooltip]
    restyling[tooltip] = nil
    if job then
        restyle(tooltip, job)
    end
end

-- Creatures ----------------------------------------------------------------------------------

-- Unit state can be secret; then it counts as no (ns.IsTrue).
local yes = ns.IsTrue

local function canSkin(unit)
    if yes(UnitIsPlayer(unit)) or yes(UnitPlayerControlled(unit)) then
        return false
    end
    -- Probe: the type's ID is a second value on Mainline; without it, the name the game shows.
    local name, kind = UnitCreatureType(unit)
    if ns.IsNumber(kind) then
        if not SKINNABLE_TYPES[kind] then
            return false
        end
    elseif not (readable(name) and SKINNABLE_NAMES[name]) then
        return false
    end
    -- Dead ones, or ones you could fight: not a friendly flight master's gryphon.
    return yes(UnitIsDead(unit)) or yes(UnitCanAttack("player", unit))
end

local unitData = setmetatable({}, { __mode = "k" }) -- tooltip -> the unit's tooltip data

local function addSkinLine(tooltip)
    if not (module.enabled and module.db.skinning and tooltip.GetUnit) then
        return
    end
    local _, unit = tooltip:GetUnit()
    if not ns.IsText(unit) or not canSkin(unit) then
        return
    end
    -- Blizzard already says what it needs: recolor that once it's drawn, don't add another.
    local data = unitData[tooltip]
    local index = data and findRequires(data)
    if index then
        restyling[tooltip] = { index, SKIN, data.lines[index].leftText, findNameLine(data, index, SKIN) }
        return
    end
    local level = UnitLevel(unit)
    if not (ns.IsNumber(level) and level > 0) then
        return -- a "??" boss, or secret
    end
    local line, color = skillLine(SKIN, Professions.SkinningNeed(level), L.PROFTOOLTIPS_REQUIRES)
    if line then
        addLine(tooltip, line, color)
    end
end

-- The line goes under the name and level, before the quest lines: it's added just before the
-- first quest line is drawn, or at the end when there's none.
local unitPending = setmetatable({}, { __mode = "k" }) -- tooltip -> true until the line is added

local function onUnitPre(tooltip, data)
    unitPending[tooltip] = true
    unitData[tooltip] = data
    restyling[tooltip] = nil
end

local function onQuestLinePre(tooltip)
    if unitPending[tooltip] then
        unitPending[tooltip] = nil
        addSkinLine(tooltip)
    end
end

local function onUnit(tooltip, data)
    local waiting = unitPending[tooltip]
    unitPending[tooltip] = nil
    if data and (waiting or not TooltipDataProcessor.AddTooltipPreCall) then
        addSkinLine(tooltip)
    end
    local job = restyling[tooltip]
    restyling[tooltip] = nil
    unitData[tooltip] = nil
    if job then
        restyle(tooltip, job)
    end
end

-- Items --------------------------------------------------------------------------------------

-- itemID -> { line index, Lockpicking needed } of the item's "Requires Lockpicking (N)" line, or
-- false for an item without one. Looked for once per item, since this runs before every line of
-- every item tooltip; later builds only compare line tables.
local lockLines = {}

-- An item's Lockpicking line, learned for the box, or false. A box we know counts whatever the
-- skill's name says.
local function lockLine(id, data)
    local cached = lockLines[id]
    if cached == nil then
        local skill, need, index = ns.GameData.TooltipRequires(data)
        -- Lockpicking's name in English or the client's language (known only to characters who
        -- can pick locks).
        cached = skill and (LOCKBOXES:Get(id) or isProfessionName(skill, LOCK)) and { index, need } or false
        if cached then
            LOCKBOXES:Learn(id, need)
        end
        -- An item not loaded yet has a lone "Retrieving" line: don't remember that as "none".
        local lines = data.lines
        if cached or (type(lines) == "table" and #lines > 1) then
            lockLines[id] = cached
        end
    end
    return cached
end

-- Blizzard's own "Requires Lockpicking (25)" line on a lockbox: learned, and drawn again in the
-- difficulty color instead of adding a second line under it.
local function onItemLine(tooltip, data, lineData)
    if not module.enabled then
        return
    end
    local id = ItemTooltip.ItemID(data)
    local lock = id and lockLine(id, data)
    if not (lock and module.db.items and data.lines[lock[1]] == lineData) then
        return
    end
    local need = lock[2]
    local line, color = skillLine(LOCK, need, L.PROFTOOLTIPS_REQUIRES)
    if line then
        addLine(tooltip, line, color)
        return true
    end
end

-- The skill line and skill an item's line is about: a lockbox's Lockpicking, or a herb's or ore's
-- gathering skill. Nil for a lockbox whose tooltip already says it (onItemLine handles that).
local function itemNeed(id, data)
    local lock = LOCKBOXES:Get(id)
    if lock then
        if lockLine(id, data) then
            return nil
        end
        return LOCK, lock
    end
    return Professions.ItemSkill(id)
end

local function onItem(tooltip, data)
    if not (module.enabled and module.db.items) then
        return
    end
    local id = ItemTooltip.ItemID(data)
    local keySkill = id and module.db.blacksmithing and KEY_SKILL[id]
    if keySkill then
        local name = select(2, lockRank())
        addLine(tooltip, format(L.PROFTOOLTIPS_KEY, name or L.PROFTOOLTIPS_LOCKPICKING_NAME, keySkill),
            NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 })
    end
    local skillLineID, need = nil, nil
    if id then
        skillLineID, need = itemNeed(id, data)
    end
    if skillLineID then
        local text = skillLineID == LOCK and L.PROFTOOLTIPS_REQUIRES or L.PROFTOOLTIPS_GATHERED
        local line, color = skillLine(skillLineID, need, text)
        if line then
            addLine(tooltip, line, color)
        end
    end
end

local preHooked = false

function module:OnEnable()
    local types = Enum.TooltipDataType
    -- Probe: MinimapMouseover is Mainline's type for minimap pins.
    self:TooltipPostCall(types.Object, onObject)
    self:TooltipPostCall(types.MinimapMouseover, onObject)
    self:TooltipPostCall(types.Unit, onUnit)
    ItemTooltip.OnInfo(onItem, module)
    ItemTooltip.ReplaceLine(onItemLine, module)
    -- Pre and line calls can't be removed and have no hook-once helper: hooked once here, they
    -- only keep state for the post calls, and what they add checks module.enabled.
    if preHooked then
        return
    end
    preHooked = true
    if TooltipDataProcessor.AddTooltipPreCall then
        for _, key in ipairs({ "Object", "MinimapMouseover" }) do
            if types[key] then
                TooltipDataProcessor.AddTooltipPreCall(types[key], onObjectPre)
            end
        end
        TooltipDataProcessor.AddTooltipPreCall(types.Unit, onUnitPre)
    end
    -- Probe: AllTypes (every line type) and line calls are Mainline's.
    if TooltipDataProcessor.AllTypes and TooltipDataProcessor.AddLinePostCall then
        TooltipDataProcessor.AddLinePostCall(TooltipDataProcessor.AllTypes, onLinePost)
    end
    -- Probe: quest line types and line pre calls are Mainline's.
    local lineTypes = Enum.TooltipDataLineType
    if lineTypes and TooltipDataProcessor.AddLinePreCall then
        for _, key in ipairs({ "QuestTitle", "QuestObjective", "QuestPlayer" }) do
            if lineTypes[key] then
                TooltipDataProcessor.AddLinePreCall(lineTypes[key], onQuestLinePre)
            end
        end
    end
end
