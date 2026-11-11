-- Auto Open: opens the containers in your bags (clams, sacks, lockboxes once unlocked) by
-- themselves, one at a time, and says in chat what it opened. A container is whatever the game
-- says has loot (the bag item's `hasLoot`), so a new one needs no list; a short list says which to
-- leave for the player. It waits whenever opening would get in the way: in combat, while a loot,
-- merchant, mail, bank, trade, auction, quest, or gossip window is open, while stealthed (opening
-- breaks stealth) or casting, with something on the cursor, and while the bags are nearly full.
--
-- Probe: C_Container.UseContainerItem opens a container from a timer on Forever, with no click.
-- [addon] Open Sesame (github.com/Gogo1951/Open-Sesame, MIT, its Camelot TOC for interface 16001,
-- read 2026-11-11) opens them that way and owns no secure frames. Unverified in game by us.
local _, ns = ...

local format, pairs, ipairs, type, concat = string.format, pairs, ipairs, type, table.concat
local C_Container = C_Container
local InCombatLockdown, UnitIsDeadOrGhost, GetNumLootItems = InCombatLockdown, UnitIsDeadOrGhost, GetNumLootItems
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo

local L = ns.L

local LAST_BAG = 4     -- the backpack and four bags; the reagent bag holds no containers
local NEXT = 0.5       -- seconds between one container and the next, for its loot to land
local RETRY = 1        -- seconds before looking again while something is in the way
local SETTLE = 0.5     -- bags change in bursts as loot arrives

local module = ns.NewModule("AutoOpen", L.AUTOOPEN_DESC, {
    enabled = false,
    freeSlots = 4, -- open nothing while fewer bag slots than this are free
    special = false, -- also open the containers in KEPT
    chat = true,
})
module.title = L.AUTOOPEN_TITLE
module.category = "automation"
module.quickToggle = "loot"
module.added = "1.5.0"

module.options = {
    {
        key = "freeSlots", name = L.AUTOOPEN_FREE_SLOTS, description = L.AUTOOPEN_FREE_SLOTS_DESC,
        min = 1, max = 10, step = 1, format = "%d",
    },
    { key = "special", name = L.AUTOOPEN_SPECIAL, description = L.AUTOOPEN_SPECIAL_DESC },
    ns.ChatOption(L.AUTOOPEN_CHAT_DESC),
}

-- Containers left for the player to open, unless Open Special Containers is on: what's inside is
-- rolled on or traded in a raid, is a holiday gift, or is a quest's or a recipe's one chance.
-- Seed: Open Sesame's default ignore list for Forever (Data/Camelot/Default-Ignore-Items-
-- Camelot.lua, MIT, hand-picked by its maintainer, read 2026-11-11). Item IDs, so Self Test
-- checks the client still has them.
local KEPT = ns.GameData.New("autoOpenKept", {
    [17962] = true, -- Blue Sack of Gems (world bosses, Nefarian)
    [17963] = true, -- Green Sack of Gems
    [17964] = true, -- Gray Sack of Gems
    [17965] = true, -- Yellow Sack of Gems
    [17969] = true, -- Red Sack of Gems
    [13874] = true, -- Heavy Crate (Gahz'ranka)
    [11937] = true, -- Fat Sack of Coins (Fire Opal Necklace)
    [6352] = true, -- Waterlogged Crate (Hammer of the Vesper)
    [8049] = true, -- Gnarlpine Necklace (Tallonkai's Jewel)
    [9276] = true, -- Pirate's Footlocker (Ship Schedule, map fragments)
    [21150] = true, -- Iron Bound Trunk (Weather-Beaten Journal)
    [21228] = true, -- Mithril Bound Trunk (Weather-Beaten Journal)
    [20708] = true, -- Tightly Sealed Trunk (Weather-Beaten Journal)
    [21113] = true, -- Watertight Trunk (Weather-Beaten Journal)
    [20767] = true, -- Scum Covered Bag (Plans: Wicked Mithril Blade)
    [21979] = true, -- Gift of Adoration: Darnassus (Love is in the Air)
    [21980] = true, -- Gift of Adoration: Ironforge
    [22164] = true, -- Gift of Adoration: Orgrimmar
    [21981] = true, -- Gift of Adoration: Stormwind
    [22165] = true, -- Gift of Adoration: Thunder Bluff
    [22166] = true, -- Gift of Adoration: Undercity
    [22155] = true, -- Pledge of Adoration: Darnassus
    [22154] = true, -- Pledge of Adoration: Ironforge
    [22156] = true, -- Pledge of Adoration: Orgrimmar
    [21975] = true, -- Pledge of Adoration: Stormwind
    [22158] = true, -- Pledge of Adoration: Thunder Bluff
    [22157] = true, -- Pledge of Adoration: Undercity
}, { kind = "item", label = "Auto Open's containers to leave" })

-- When it's safe ---------------------------------------------------------------------------------

-- Blizzard's windows that use or take a bag item when it's right-clicked, or that opening a
-- container would close or replace.
local WINDOWS = { "LootFrame", "MerchantFrame", "MailFrame", "BankFrame", "TradeFrame", "AuctionHouseFrame",
    "AuctionFrame", "GossipFrame", "QuestFrame", "ClassTrainerFrame", "GuildBankFrame" }

local function windowOpen()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then
            return true
        end
    end
    -- Fast Loot and other addons hide the loot window while there's still loot in it.
    local loot = GetNumLootItems and GetNumLootItems()
    return ns.IsNumber(loot) and loot > 0
end

-- A cast or channel under way. One the game won't tell us about counts as one.
local function casting()
    local cast, channel = UnitCastingInfo and UnitCastingInfo("player"), UnitChannelInfo and UnitChannelInfo("player")
    return not ns.IsReadable(cast) or cast ~= nil or not ns.IsReadable(channel) or channel ~= nil
end

local function freeSlots()
    local free = 0
    for bag = 0, LAST_BAG do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        -- A quiver or a herb bag takes only its own kind (family 0 is an ordinary bag).
        if type(slots) == "number" and (family == nil or family == 0) then
            free = free + slots
        end
    end
    return free
end

local function safe()
    if InCombatLockdown() or (UnitIsDeadOrGhost and ns.IsTrueOrSecret(UnitIsDeadOrGhost("player"))) then
        return false
    end
    if windowOpen() or casting() then
        return false
    end
    if (IsStealthed and ns.IsTrueOrSecret(IsStealthed())) or (GetCursorInfo and GetCursorInfo() ~= nil) then
        return false
    end
    return freeSlots() >= module.db.freeSlots
end

-- What to open ---------------------------------------------------------------------------------

-- A lockbox still locked: the tooltip of the item in that slot has Blizzard's red "Locked" line.
-- Unknown counts as locked, so it's left alone.
local function locked(bag, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    local lines = data and ns.IsReadable(data) and data.lines
    if type(lines) ~= "table" then
        return true
    end
    local word = _G.LOCKED
    for i = 2, #lines do -- line 1 is the name
        local text = lines[i].leftText
        if word and ns.IsText(text) and text == word then
            return true
        end
    end
    return false
end

-- What was tried in each slot, as "itemID:count": one that didn't open (it needs a key, or the
-- game refused) isn't tried again until the slot holds something else. A stack loses one each
-- time, so the rest of it is still opened.
local tried = {}

local function slotKey(bag, slot)
    return bag * 100 + slot
end

-- The next container to open: its bag, slot, link, and what `tried` would say of it.
local function nextContainer()
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local key = slotKey(bag, slot)
            if not info then
                tried[key] = nil
            elseif ns.IsTrue(info.hasLoot) and not info.isLocked and type(info.itemID) == "number" then
                local mark = info.itemID .. ":" .. (info.stackCount or 1)
                if tried[key] ~= mark and (module.db.special or not KEPT:Get(info.itemID))
                    and not locked(bag, slot) then
                    return bag, slot, info.hyperlink, mark
                end
            end
        end
    end
end

-- Opening ----------------------------------------------------------------------------------------

local opened, order = {}, {} -- link -> how many this run, and the links in the order opened
local timer = ns.Frames.Timer(module)

-- One chat line for the run: "Opened [Big-mouth Clam] x3, [Small Barnacled Clam]."
local function report()
    if #order == 0 then
        return
    end
    local parts = {}
    for i, link in ipairs(order) do
        local count = opened[link]
        parts[i] = count > 1 and format(L.AUTOOPEN_COUNT, link, count) or link
        opened[link] = nil
        order[i] = nil
    end
    module:Print(format(L.AUTOOPEN_OPENED, concat(parts, ", ")))
end

local function step()
    local bag, slot, link, mark = nextContainer()
    if not bag then
        report()
        return
    end
    if not safe() then
        timer:Start(RETRY, step)
        return
    end
    tried[slotKey(bag, slot)] = mark
    C_Container.UseContainerItem(bag, slot)
    if ns.IsText(link, true) then
        if not opened[link] then
            order[#order + 1] = link
        end
        opened[link] = (opened[link] or 0) + 1
    end
    timer:Start(NEXT, step)
end

local look = ns.Frames.Coalesce(step, SETTLE, module)

function module:OnEnable()
    self:On("BAG_UPDATE_DELAYED", look)
    self:On("PLAYER_REGEN_ENABLED", look)
    look()
end

function module:OnDisable()
    for key in pairs(tried) do
        tried[key] = nil
    end
    for link in pairs(opened) do
        opened[link] = nil
    end
    for i in ipairs(order) do
        order[i] = nil
    end
end

-- Turning Open Special Containers on opens the ones already in the bags.
function module:OnOptionChanged()
    if self.enabled then
        look()
    end
end
