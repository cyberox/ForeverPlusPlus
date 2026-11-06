-- Gear Probe: a Debug module button (and `/fpp gearprobe`) for the Upgrade Arrows work: reads what
-- this client says about the gear you wear and carry (stat tables, tooltip lines, item levels),
-- its own item comparison (C_TooltipComparison), your talent tabs, your stats, and the bag
-- buttons' upgrade art, and writes it to the module's saved log. `/reload` (or logging out)
-- saves it to the SavedVariables file, where it can be read. The log is developer output, so it
-- stays in English. Nothing runs until the button is pressed. Every call is probed and protected:
-- an API this build lacks is logged as missing, and a secret value as <secret>.
local _, ns = ...

local _G, ipairs, pairs, type, pcall, tostring, select, unpack = _G, ipairs, pairs, type, pcall, tostring, select, unpack
local format, sort, tconcat, date = string.format, table.sort, table.concat, date
local InCombatLockdown, GetBuildInfo = InCombatLockdown, GetBuildInfo
local L = ns.L

local module = ns.NewModule("GearProbe", L.GEARPROBE_DESC, { enabled = true, log = {} })
module.title = L.GEARPROBE_TITLE
module.alwaysOn = true -- a debugging tool, not a change to the game

local MAX_LINES = 900
local MAX_BAG_ITEMS = 8 -- gear from the bags that gets the full treatment
local MAX_COMPARED = 4 -- of those, how many are run through the comparison calls
local MAX_TOOLTIP_LINES = 30
local lines -- the log being written

-- Reading things safely ------------------------------------------------------------------------

-- A value as text, without touching a secret one.
local function text(value)
    if not ns.IsReadable(value) then
        return "<secret>"
    end
    if type(value) == "table" then
        return "<table>"
    end
    return tostring(value)
end

-- Several values as one line.
local function join(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = text((select(i, ...)))
    end
    return tconcat(parts, ", ")
end

-- A global by its dotted name ("C_Item.GetItemStats"), or nil.
local function get(name)
    local value = _G
    for part in name:gmatch("[^.]+") do
        if type(value) ~= "table" or not ns.IsReadable(value[part]) then
            return nil
        end
        value = value[part]
    end
    return value
end

-- Calls a global by name in protected mode: whether it worked, then what it returned (or why not).
local function call(name, ...)
    local fn = get(name)
    if type(fn) ~= "function" then
        return false, "missing"
    end
    return pcall(fn, ...)
end

local function add(line)
    if #lines < MAX_LINES then
        lines[#lines + 1] = line
    elseif #lines == MAX_LINES then
        lines[#lines + 1] = "... (log full)"
    end
end

local function section(title)
    add("")
    add("## " .. title)
end

-- One line per key of a table, one level deep, keys sorted; nested tables are noted, not walked.
local function dump(prefix, value)
    if not ns.IsReadable(value) then
        add(prefix .. ": <secret>")
        return
    end
    if type(value) ~= "table" then
        add(prefix .. ": " .. text(value))
        return
    end
    local keys = {}
    local ok = pcall(function()
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
    end)
    if not ok then
        add(prefix .. ": <unreadable table>")
        return
    end
    sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    if #keys == 0 then
        add(prefix .. ": {}")
    end
    for _, key in ipairs(keys) do
        add(format("%s.%s = %s", prefix, tostring(key), text(value[key])))
    end
end

-- Logs a call by name and its first result, dumped a level deep when it's a table.
local function probe(label, name, ...)
    local ok, result = call(name, ...)
    if not ok then
        add(format("%s: %s (%s)", label, name, text(result)))
        return nil
    end
    dump(label, result)
    return result
end

-- Logs a call by name and every result on one line.
local function probeAll(label, name, ...)
    local results = { call(name, ...) }
    if not results[1] then
        add(format("%s: %s (%s)", label, name, text(results[2])))
        return
    end
    add(format("%s: %s", label, join(select(2, unpack(results)))))
end

-- The client ---------------------------------------------------------------------------------------

local function checkClient()
    section("client")
    probeAll("build", "GetBuildInfo")
    probeAll("class", "UnitClass", "player")
    probeAll("level", "UnitLevel", "player")
    add("in combat: " .. text(InCombatLockdown and InCombatLockdown()))
    probeAll("secrets", "C_Secrets.HasSecretRestrictions")
end

-- The functions and strings the plan leans on: which exist, and what the Equip: strings say.
local API = {
    "C_Item.GetItemStats", "GetItemStats", "C_Item.GetItemStatDelta", "C_Item.GetDetailedItemLevelInfo",
    "C_Item.IsEquippableItem", "C_Item.GetItemInventoryTypeByID", "C_Item.IsEquippedItemType",
    "C_Item.GetItemSetInfo", "C_PlayerInfo.CanUseItem", "C_Item.IsUsableItem",
    "C_TooltipComparison.GetItemComparisonInfo", "C_TooltipComparison.GetItemComparisonDelta",
    "C_TooltipInfo.GetInventoryItem", "C_TooltipInfo.GetBagItem", "C_TooltipInfo.GetMerchantItem",
    "C_TooltipInfo.GetLootItem", "C_TooltipInfo.GetLootRollItem", "C_TooltipInfo.GetQuestItem",
    "C_SpecializationInfo.IsInitialized", "C_SpecializationInfo.GetActiveSpecGroup", "GetNumSpecGroups",
    "C_Traits.GetGroupCurrencyInfo", "C_Traits.GetGroupDisplayInfoByTreeID", "C_ClassTalents.GetActiveConfigID",
    "GetHitModifier", "GetSpellHitModifier", "GetRangedHitModifier", "GetCritChance", "GetRangedCritChance",
    "GetSpellCritChance", "GetSpellBonusDamage", "GetSpellBonusHealing", "UnitStat", "UnitAttackPower",
    "UnitRangedAttackPower", "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetShieldBlock",
    "UnitDefenseSkill", "UnitArmor", "GetManaRegen", "GetExpertise", "GetMeleeHaste", "IsDualWielding",
    "CanDualWield", "C_SkillInfo.GetSkillLineInfoByID", "C_Texture.GetAtlasInfo", "ItemLocation.CreateFromBagAndSlot",
    "C_Item.GetItemGUID", "C_Item.RequestLoadItemDataByID",
}

local STRINGS = {
    "ITEM_SPELL_TRIGGER_ONEQUIP", "ITEM_MOD_HIT_RATING", "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING",
    "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_SPELL_POWER", "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE", "ITEM_MOD_SPELL_HEALING_DONE", "ITEM_MOD_MANA_REGENERATION",
    "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_ATTACK_POWER", "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING", "ITEM_MOD_DODGE_RATING", "ITEM_MOD_BLOCK_VALUE", "DAMAGE_TEMPLATE",
    "DAMAGE_TEMPLATE_WITH_SCHOOL", "SPEED", "ITEM_LEVEL", "ITEM_MIN_LEVEL", "DPS_TEMPLATE",
}

local function checkApi()
    section("functions")
    for _, name in ipairs(API) do
        add(format("%s: %s", name, type(get(name)) == "function" and "yes" or "missing"))
    end
    add("Enum.TooltipComparisonMethod: " .. text(get("Enum.TooltipComparisonMethod") and "yes" or "missing"))
    dump("Enum.TooltipComparisonMethod", get("Enum.TooltipComparisonMethod"))
    section("strings")
    for _, name in ipairs(STRINGS) do
        add(format("%s = %s", name, text(get(name))))
    end
end

-- Items --------------------------------------------------------------------------------------------

-- Everything the stat and info calls say about one item link.
local function describeItem(label, link)
    probeAll(label .. " instant", "C_Item.GetItemInfoInstant", link)
    local info = { call("C_Item.GetItemInfo", link) }
    if info[1] then
        add(format("%s info: name %s, level %s, minLevel %s, equipLoc %s, class %s/%s, setID %s",
            label, text(info[2]), text(info[5]), text(info[6]), text(info[10]), text(info[13]),
            text(info[14]), text(info[17])))
    else
        add(label .. " info: " .. text(info[2]))
    end
    probeAll(label .. " detailed level", "C_Item.GetDetailedItemLevelInfo", link)
    local stats = probe(label .. " stats", "C_Item.GetItemStats", link)
    if stats == nil and type(get("GetItemStats")) == "function" then
        probe(label .. " stats (global)", "GetItemStats", link)
    end
end

-- The tooltip's lines with their types, from a tooltip data table.
local function describeTooltip(label, ok, data)
    if not ok then
        add(label .. " tooltip: " .. text(data))
        return
    end
    local tooltipLines = type(data) == "table" and ns.IsReadable(data.lines) and data.lines
    if type(tooltipLines) ~= "table" then
        add(label .. " tooltip: no lines")
        return
    end
    for i, line in ipairs(tooltipLines) do
        if i > MAX_TOOLTIP_LINES then
            add(label .. " tooltip: ... more lines")
            break
        end
        if type(line) == "table" and ns.IsReadable(line) then
            add(format("%s tooltip %d [%s]: %s | %s", label, i, text(line.type), text(line.leftText),
                text(line.rightText)))
        end
    end
end

local mainHand -- the worn main hand's link, for the stat delta

local function checkWorn()
    section("worn")
    mainHand = nil
    for slot = 1, 19 do
        local ok, link = call("GetInventoryItemLink", "player", slot)
        link = ok and ns.IsText(link) and link or nil
        add(format("slot %d: %s", slot, text(link)))
        if link then
            describeItem("slot " .. slot, link)
            if slot == 16 then
                mainHand = link
            end
        end
    end
    section("worn tooltips")
    for _, slot in ipairs({ 16, 17, 18 }) do
        describeTooltip("slot " .. slot, call("C_TooltipInfo.GetInventoryItem", "player", slot))
    end
end

local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass

-- The gear in the bags: up to MAX_BAG_ITEMS links with where they are.
local function bagGear()
    local found = {}
    local bags = _G.NUM_BAG_SLOTS or 4
    for bag = 0, bags do
        local ok, slots = call("C_Container.GetContainerNumSlots", bag)
        for slot = 1, ok and ns.IsReadable(slots) and slots or 0 do
            local okLink, link = call("C_Container.GetContainerItemLink", bag, slot)
            if okLink and ns.IsText(link) then
                local okInstant, _, _, _, equipLoc, _, classID = call("C_Item.GetItemInfoInstant", link)
                if okInstant and ns.IsText(equipLoc, true) and (classID == WEAPON or classID == ARMOR) then
                    found[#found + 1] = { bag = bag, slot = slot, link = link }
                    if #found == MAX_BAG_ITEMS then
                        return found
                    end
                end
            end
        end
    end
    return found
end

-- The link an item GUID stands for, so a comparison answer can be read.
local function linkOf(guid)
    if not ns.IsText(guid) then
        return "?"
    end
    local ok, link = call("C_Item.GetItemLinkByGUID", guid)
    return ok and text(link) or "error " .. text(link)
end

-- A comparison item (`item` or one of `additionalItems`): its fields, and the link its GUID means.
local function dumpComparisonItem(label, entry)
    dump(label, entry)
    if type(entry) == "table" and ns.IsReadable(entry) then
        add(label .. " link: " .. linkOf(entry.guid))
    end
end

-- The comparison item as the API might want it: a hyperlink, then a GUID.
local function compareWith(label, item)
    local okInfo, info = call("C_TooltipComparison.GetItemComparisonInfo", { hyperlink = item.link })
    if okInfo then
        dump(label .. " compare(link)", info)
        if type(info) == "table" then
            dumpComparisonItem(label .. " compare(link).item", info.item)
            local extra = ns.IsReadable(info.additionalItems) and info.additionalItems
            for i, other in ipairs(type(extra) == "table" and extra or {}) do
                dumpComparisonItem(format("%s compare(link).additionalItems[%d]", label, i), other)
            end
        end
    else
        add(label .. " compare(link): error " .. text(info))
    end
    -- The location is made with a colon: ItemLocation is a mixin, not a namespace.
    local okLoc, location = pcall(function()
        return _G.ItemLocation and _G.ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
    end)
    local okGuid, guid = false, okLoc and "no location" or "error " .. text(location)
    if okLoc and location then
        okGuid, guid = call("C_Item.GetItemGUID", location)
    end
    add(label .. " guid: " .. text(guid))
    if okGuid and guid then
        local okG, infoG = call("C_TooltipComparison.GetItemComparisonInfo", { guid = guid })
        if okG then
            dump(label .. " compare(guid)", infoG)
            if type(infoG) == "table" then
                dumpComparisonItem(label .. " compare(guid).item", infoG.item)
            end
        else
            add(label .. " compare(guid): error " .. text(infoG))
        end
    end
    if mainHand then
        probe(label .. " delta vs main hand", "C_Item.GetItemStatDelta", mainHand, item.link)
        local okD, delta = call("C_TooltipComparison.GetItemComparisonDelta", { hyperlink = item.link },
            { hyperlink = mainHand })
        if okD then
            dump(label .. " delta lines", delta)
        else
            add(label .. " delta lines: error " .. text(delta))
        end
    end
end

local bagCount, compared -- for the chat summary

local function checkBags()
    section("bags")
    local gear = bagGear()
    bagCount, compared = #gear, false
    if #gear == 0 then
        add("no weapons or armor in the bags")
        return
    end
    for i, item in ipairs(gear) do
        local label = format("bag %d/%d", item.bag, item.slot)
        add(format("%s: %s", label, item.link))
        describeItem(label, item.link)
        local okID, itemID = call("C_Item.GetItemInfoInstant", item.link)
        if okID and itemID then
            probeAll(label .. " can use", "C_PlayerInfo.CanUseItem", itemID)
        end
        probeAll(label .. " equippable", "C_Item.IsEquippableItem", item.link)
        describeTooltip(label, call("C_TooltipInfo.GetBagItem", item.bag, item.slot))
        if i <= MAX_COMPARED then
            compareWith(label, item)
            compared = true
        end
    end
end

-- Talents ----------------------------------------------------------------------------------------

local function checkTalents()
    section("talents")
    probeAll("initialized", "C_SpecializationInfo.IsInitialized")
    probeAll("specialization", "C_SpecializationInfo.GetSpecialization")
    probeAll("spec group", "C_SpecializationInfo.GetActiveSpecGroup")
    probeAll("spec groups", "GetNumSpecGroups")
    local okConfig, configID = call("C_ClassTalents.GetActiveConfigID")
    add("config: " .. text(okConfig and configID or "error"))
    if not (okConfig and configID) then
        return
    end
    local info = probe("config info", "C_Traits.GetConfigInfo", configID)
    local treeID = type(info) == "table" and ns.IsReadable(info.treeIDs) and type(info.treeIDs) == "table"
        and info.treeIDs[1]
    add("tree: " .. text(treeID))
    if not treeID then
        return
    end
    probe("tree currency", "C_Traits.GetTreeCurrencyInfo", configID, treeID, false)
    local okGroups, groups = call("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
    for _, group in ipairs(okGroups and type(groups) == "table" and groups or {}) do
        local label = "tab " .. text(group.groupID)
        dump(label, group)
        local okSpent, spent = call("C_Traits.GetGroupCurrencyInfo", configID, { group.groupID })
        local entry = okSpent and type(spent) == "table" and spent[1]
        local currency = entry and type(entry.currencyInfos) == "table" and entry.currencyInfos[1]
        if currency then
            dump(label .. " points", currency)
        else
            add(label .. " points: " .. (okSpent and "none (0)" or "error " .. text(spent)))
        end
    end
end

-- The player --------------------------------------------------------------------------------------

local function checkStats()
    section("player stats" .. (InCombatLockdown and InCombatLockdown() and " (in combat)" or ""))
    probeAll("hit", "GetHitModifier")
    probeAll("ranged hit", "GetRangedHitModifier")
    probeAll("spell hit", "GetSpellHitModifier")
    probeAll("crit", "GetCritChance")
    probeAll("ranged crit", "GetRangedCritChance")
    for school = 2, 7 do
        probeAll("spell crit " .. school, "GetSpellCritChance", school)
        probeAll("spell damage " .. school, "GetSpellBonusDamage", school)
    end
    probeAll("healing", "GetSpellBonusHealing")
    for stat = 1, 5 do
        probeAll("stat " .. stat, "UnitStat", "player", stat)
    end
    probeAll("attack power", "UnitAttackPower", "player")
    probeAll("ranged attack power", "UnitRangedAttackPower", "player")
    probeAll("dodge", "GetDodgeChance")
    probeAll("parry", "GetParryChance")
    probeAll("block", "GetBlockChance")
    probeAll("block value", "GetShieldBlock")
    probeAll("defense", "UnitDefenseSkill", "player")
    probeAll("armor", "UnitArmor", "player")
    probeAll("mana regen", "GetManaRegen")
    probeAll("expertise", "GetExpertise")
    probeAll("melee haste", "GetMeleeHaste")
    probeAll("dual wielding", "IsDualWielding")
    probeAll("can dual wield", "CanDualWield")
end

-- What a point of each attribute gives, from the functions the character sheet's stat tooltips
-- use (Upgrade Arrows derives its attribute weights from them).
local function checkConversions()
    section("conversions")
    for stat = 1, 5 do
        probeAll("attack power from 100 of stat " .. stat, "GetAttackPowerForStat", stat, 100)
        probeAll("ranged attack power from 100 of stat " .. stat, "GetRangedAttackPowerForStat", stat, 100)
    end
    -- As the character sheet asks: the stat and its points, answering 0 to 1.
    probeAll("crit from 100 agility", "GetCritChanceFromStat", 2, 100)
    probeAll("dodge from own agility", "GetDodgeChanceFromAttribute")
    probeAll("spell crit from 100 intellect", "GetSpellCritChanceFromStat", 4, 100)
    probeAll("health per stamina", "UnitHPPerStamina", "player")
    add("mana per intellect: " .. text(_G.MANA_PER_INTELLECT) .. ", break " .. text(_G.INTELLECT_BREAK))
    probeAll("mana regen from spirit", "GetManaRegenFromSpirit")
    probeAll("health regen from spirit", "GetHealthRegenFromSpirit")
    probeAll("mana regen", "GetManaRegen")
    probeAll("health regen", "GetHealthRegen")
    local rates = ns.ItemStats and ns.ItemStats.PlayerRates and ns.ItemStats.PlayerRates()
    dump("rates (Lib/ItemStats.lua)", rates)
    -- Gear's ratings: what 100 points give, and the player's own.
    for _, name in ipairs({ "CR_HIT_MELEE", "CR_HIT_SPELL", "CR_CRIT_MELEE", "CR_CRIT_SPELL", "CR_HASTE_MELEE",
        "CR_EXPERTISE", "CR_DODGE", "CR_PARRY", "CR_BLOCK", "CR_DEFENSE_SKILL" }) do
        local index = _G[name]
        if type(index) == "number" then
            probeAll(name .. " from 100 rating", "GetCombatRatingBonusForCombatRatingValue", index, 100)
            probeAll(name .. " own rating", "GetCombatRating", index)
            probeAll(name .. " own bonus", "GetCombatRatingBonus", index)
        else
            add(name .. ": missing")
        end
    end
    local ratingRates, sources = ns.ItemStats and ns.ItemStats.RatingRates and ns.ItemStats.RatingRates()
    dump("rating rates per point (Lib/ItemStats.lua)", ratingRates)
    dump("rating rate sources", sources)
end

-- The weapon skill lines Forever's SkillsFrame lists (Character Window's Skills.lua has the map).
local SKILL_LINES = { 43, 44, 45, 46, 54, 55, 136, 160, 162, 172, 173, 176, 226, 228, 229 }

local function checkSkills()
    section("weapon skills")
    for _, line in ipairs(SKILL_LINES) do
        local ok, info = call("C_SkillInfo.GetSkillLineInfoByID", line)
        if ok and type(info) == "table" then
            dump("skill " .. line, info)
        else
            add(format("skill %d: %s", line, ok and "none" or text(info)))
        end
    end
end

-- Blizzard's own arrow: the atlas, and whether bag buttons still carry an UpgradeIcon region.
local function checkArt()
    section("arrow art")
    for _, atlas in ipairs({ "bags-greenarrow", "bags-newitem", "Bags-UpgradeArrow" }) do
        local ok, info = call("C_Texture.GetAtlasInfo", atlas)
        add(format("atlas %s: %s", atlas, ok and (info and "yes" or "no") or text(info)))
    end
    -- The first button of any bag window that's open: the combined bags, or a bag of its own.
    local found = false
    for _, frame in ipairs(ns.ItemButtons.Frames()) do
        if frame and frame:IsShown() and not found then
            local ok, err = pcall(function()
                ns.ItemButtons.EachBagButton(frame, function(button)
                    if button and not found then
                        found = true
                        local icon = button.UpgradeIcon
                        add(format("bag button (%s) UpgradeIcon: %s", text(frame:GetName()), text(icon and "yes" or "no")))
                        if icon and icon.GetAtlas then
                            add("bag button UpgradeIcon atlas: " .. text(icon:GetAtlas()))
                        end
                    end
                end)
            end)
            if not ok then
                add("bag button: error " .. text(err))
            end
        end
    end
    if not found then
        add("bag button: no bag window is open (open your bags and run /fpp gearprobe again)")
    end
end

-- Running it ---------------------------------------------------------------------------------

local CHECKS = { checkClient, checkApi, checkWorn, checkBags, checkTalents, checkStats, checkConversions,
    checkSkills, checkArt }

---Runs every probe and writes the results to the saved log.
---@return number count how many lines it wrote
function module.Run()
    lines = {}
    bagCount, compared = 0, false
    local _, build = GetBuildInfo()
    for _, fn in ipairs(CHECKS) do
        local ok, err = pcall(fn)
        if not ok then
            add("ERROR: " .. text(err))
        end
    end
    module.db.log = { when = date("%Y-%m-%d %H:%M:%S"), build = build, lines = lines }
    ns.Print(format(L.GEARPROBE_DONE, #lines, bagCount))
    if not compared then
        ns.Print(L.GEARPROBE_NO_GEAR)
    end
    return #lines
end

-- Shown in the Debug module's settings (Settings/Debug.lua).
module.debugActions = {
    {
        name = L.GEARPROBE_TITLE,
        button = L.GEARPROBE_BUTTON,
        description = L.GEARPROBE_BUTTON_DESC,
        fn = module.Run,
        section = L.DEBUG_SECTION_TOOLS,
    },
}

ns.AddCommand("gearprobe", "", L.GEARPROBE_COMMAND, module.Run, "Debug")
