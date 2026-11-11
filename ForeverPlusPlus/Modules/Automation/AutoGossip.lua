-- Auto Gossip: when an NPC's gossip has exactly one option (or one service beside plain chat) and
-- no quests, pick it, so a banker, vendor, trainer, flight master and the rest open straight
-- away. Each kind of NPC has its own checkbox. Hold the Skip Key (Shift by default) while talking
-- to the NPC to skip it.
local _, ns = ...

local pairs, ipairs, type, format, tostring = pairs, ipairs, type, string.format, tostring
local C_GossipInfo, Enum = C_GossipInfo, Enum
local GetTime = GetTime

local L = ns.L

local module = ns.NewModule("AutoGossip", L.AUTOGOSSIP_DESC, {
    enabled = false,
    banker = true,
    vendor = true,
    trainer = true,
    taxi = true,
    stable = true,
    other = false, -- any NPC, so it can pick something the player wanted to read
    skipKey = "shift",
    printOptions = false,
})
module.title = L.AUTOGOSSIP_TITLE
module.category = "automation"
module.quickToggle = "npcs"
module.presets = { developer = { enabled = true, options = { other = true } } }

-- Hold Shift to Skip was a checkbox, 0.8.4 and before.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    ns.Keys.MigrateShift(saved, "AutoGossip", "shiftSkips", "skipKey")
end)

local GENERAL, NPCS = L.AUTOGOSSIP_SECTION_GENERAL, L.AUTOGOSSIP_SECTION_NPCS

module.options = {
    ns.Keys.Option("skipKey", L.SKIP_KEY, L.AUTOGOSSIP_KEY_DESC, GENERAL, "0.9.0"),
    -- Alphabetical, with the catch-all last.
    { key = "banker", name = L.AUTOGOSSIP_BANKER, description = L.AUTOGOSSIP_BANKER_DESC, section = NPCS },
    { key = "taxi", name = L.AUTOGOSSIP_TAXI, description = L.AUTOGOSSIP_TAXI_DESC, section = NPCS },
    { key = "stable", name = L.AUTOGOSSIP_STABLE, description = L.AUTOGOSSIP_STABLE_DESC, section = NPCS },
    { key = "trainer", name = L.AUTOGOSSIP_TRAINER, description = L.AUTOGOSSIP_TRAINER_DESC, section = NPCS },
    { key = "vendor", name = L.AUTOGOSSIP_VENDOR, description = L.AUTOGOSSIP_VENDOR_DESC, section = NPCS },
    { key = "other", name = L.AUTOGOSSIP_OTHER, description = L.AUTOGOSSIP_OTHER_DESC, section = NPCS },
    {
        key = "printOptions",
        name = L.AUTOGOSSIP_PRINT,
        description = L.AUTOGOSSIP_PRINT_DESC,
        debug = true,
        section = L.DEBUG_SECTION_LOGGING,
    },
}

-- The kind of NPC, from the option's gossip icon. The seed is the Classic GossipFrame icon file
-- IDs; Forever sends the same ones (turn on the Debug option to see them, and docs/forever-api.md
-- "Gossip" for what was seen). An icon is also learned from the window its option opens (see
-- "Learning icons" below), so a different one on Forever is known after the first pick. false:
-- icons seen opening two kinds.
local SEED = {
    [132050] = "banker", -- BankerGossipIcon
    [132060] = "vendor", -- VendorGossipIcon, also repair vendors
    [132058] = "trainer", -- TrainerGossipIcon
    [132057] = "taxi", -- TaxiGossipIcon
}
local ICONS = ns.GameData.New("gossipIcons", SEED, { label = "Gossip icons" })

-- The plain speech-bubble icon (GossipGossipIcon) goes on all sorts of options, so it's never
-- learned as a service. Forever uses Classic's file ID (an innkeeper's dungeon option).
local CHAT_ICON = 132053

-- Stable masters have no icon of their own, so they go by the title under the NPC's name.
-- (Auctioneers on Forever open the auction house without any gossip.)
local TITLES = {
    [L.AUTOGOSSIP_TITLE_STABLE] = "stable",
}

-- The title under the NPC's name ("Stable Master"), or nil.
local function npcTitle()
    return ns.Units.Title("npc")
end

local function kindOf(option)
    return ICONS:Get(option.icon) or TITLES[npcTitle() or ""] or "other"
end

-- An option that is safe to pick without asking: available, and with no cost, reward, or spell
-- attached. Options that cost gold also ask first (GOSSIP_CONFIRM); that popup stays for the
-- player, since this only picks the option, never confirms.
local AVAILABLE = Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available or 0

local function isSafe(option)
    if option.status and option.status ~= AVAILABLE then
        return false
    end
    if option.spellID or (option.rewards and #option.rewards > 0) or not option.gossipOptionID then
        return false
    end
    -- Blizzard picks these itself; picking again would select twice.
    return not option.selectOptionWhenOnlyOption
end

local function printOptions(options)
    ns.Print(format(L.AUTOGOSSIP_PRINT_HEADER, tostring(npcTitle())))
    for _, option in ipairs(options) do
        ns.Print(format(L.AUTOGOSSIP_PRINT_LINE, tostring(option.gossipOptionID),
            tostring(option.icon), tostring(option.status), tostring(option.flags),
            tostring(option.name)))
    end
end

-- A page that shows right after a pick is the next page of the same conversation (story text),
-- so leave it for the player to read. A time, not GOSSIP_CLOSED: that doesn't always fire when
-- the pick opens another window (bank, flight map), which left later NPCs never picked.
local REPICK_DELAY = 1
local lastPick = 0

-- The option to pick: the only one, or the one service option among plain chat ones. A weapon
-- master on Forever offers "What can other weapon masters teach?" (the plain icon) beside its
-- training, and that chat shouldn't keep the trainer from opening. An innkeeper's vendor and
-- hearthstone options are two services, so it's left alone.
local function choose(options)
    if #options == 1 then
        return options[1]
    end
    local service
    for _, option in ipairs(options) do
        if option.icon ~= CHAT_ICON then
            if service then
                return nil
            end
            service = option
        end
    end
    if service and kindOf(service) ~= "other" then
        return service
    end
end

-- Why no option is picked, or nil and the option to pick.
local function skipReason(options)
    if GetTime() - lastPick < REPICK_DELAY then
        return "just picked"
    elseif ns.Keys.IsDown(module.db.skipKey) then
        return "skip key"
    end
    local option = choose(options)
    if not option then
        return "options"
    end
    local available = C_GossipInfo.GetAvailableQuests() or {}
    local active = C_GossipInfo.GetActiveQuests() or {}
    if #available > 0 or #active > 0 then
        return "quests"
    elseif not isSafe(option) then
        return "not safe"
    end
    local kind = kindOf(option)
    if not module.db[kind] then
        return kind .. " off"
    end
    -- ForceGossip asks for the text to be read. Forever sets it on flight masters too, so it only
    -- holds back NPCs that aren't a known service.
    if kind == "other" and C_GossipInfo.ForceGossip and C_GossipInfo.ForceGossip() then
        return "ForceGossip"
    end
    return nil, option
end

-- Learning icons --------------------------------------------------------------------------------
-- An option picked (by us or the player) is remembered with its icon; if one of these windows
-- opens soon after, that icon is that kind of NPC's.
local WINDOWS = {
    BANKFRAME_OPENED = "banker",
    MERCHANT_SHOW = "vendor",
    TRAINER_SHOW = "trainer",
    TAXIMAP_OPENED = "taxi",
}
local LEARN_WINDOW = 3 -- seconds from the pick to the window

local shown = {} -- the options of the gossip page on screen
local picked, pickedAt -- the picked option's icon, and when

local function onPick(option)
    local icon = option and option.icon
    if type(icon) == "number" and icon ~= CHAT_ICON then
        picked, pickedAt = icon, GetTime()
    else
        picked = nil
    end
end

local function onSelectOption(optionID)
    for _, option in ipairs(shown) do
        if option.gossipOptionID == optionID then
            return onPick(option)
        end
    end
    picked = nil
end

-- Blizzard's gossip buttons pick by index; match it to the option's orderIndex, never guess.
local function onSelectOptionByIndex(index)
    for _, option in ipairs(shown) do
        if option.orderIndex == index then
            return onPick(option)
        end
    end
    picked = nil
end

local function onWindow(event)
    local icon = picked
    picked = nil
    if not icon or GetTime() - pickedAt > LEARN_WINDOW then
        return
    end
    local kind = WINDOWS[event]
    local known = ICONS:Get(icon)
    if known == false or known == kind then
        return
    end
    -- One seen opening another kind before is ambiguous; a seed that disagrees was Classic's.
    if known and SEED[icon] ~= known then
        ICONS:Learn(icon, false)
    else
        ICONS:Learn(icon, kind)
    end
    if module.db.printOptions then
        ns.Print(format(L.AUTOGOSSIP_PRINT_LEARNED, tostring(icon), tostring(ICONS:Get(icon))))
    end
end

local function onGossipShow()
    local options = C_GossipInfo.GetOptions() or {}
    shown, picked = options, nil
    local reason, option = skipReason(options)
    if module.db.printOptions then
        printOptions(options)
        ns.Print(format(L.AUTOGOSSIP_PRINT_RESULT, reason or kindOf(option)))
    end
    if reason then
        return
    end
    lastPick = GetTime()
    C_GossipInfo.SelectOption(option.gossipOptionID)
end

function module:OnEnable()
    self:On("GOSSIP_SHOW", onGossipShow)
    self:Hook(C_GossipInfo, "SelectOption", onSelectOption)
    self:Hook(C_GossipInfo, "SelectOptionByIndex", onSelectOptionByIndex)
    for event in pairs(WINDOWS) do
        self:On(event, onWindow)
    end
end

function module:OnDisable()
    lastPick = 0
    shown, picked = {}, nil
end
