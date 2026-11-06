-- Upgrade Arrows: Blizzard's green arrow on gear that beats what you wear, judged by stat weights
-- for your class and talent tree (Weights.lua), in your bags and bank, at merchants, on loot and
-- loot rolls, on quest reward choices, and in the auction house, each with its own checkbox, and
-- the arrow with the percentage to the right of the item's name in its tooltip.
--
-- An item's score is its stats (Lib/ItemStats.lua) times the profile's weights; what it would
-- replace comes from the client's own item comparison (Lib/Equipment.lua), so a ring is judged
-- against the weaker ring and a two-hander against both hands. Scores are kept per item link
-- and forgotten when what you wear, your level, your talents, or the weights change.
--
-- The arrow is our own texture over the icon, with the atlas Blizzard's bag buttons keep in a
-- hidden UpgradeIcon region, in the corner and at the size the Arrow options pick, with the
-- percentage under it; nothing is written onto Blizzard's frames.
local _, ns = ...

local _G, ipairs, pairs, type, wipe, tonumber, tostring = _G, ipairs, pairs, type, wipe, tonumber, tostring
local format, floor, huge = string.format, math.floor, math.huge
local C_Container, C_AddOns, C_Item, UnitClass, UnitLevel = C_Container, C_AddOns, C_Item, UnitClass, UnitLevel

local L = ns.L
local ItemButtons, ItemStats, Equipment, Talents = ns.ItemButtons, ns.ItemStats, ns.Equipment, ns.Talents
local ItemTooltip = ns.ItemTooltip

local module = ns.NewModule("UpgradeArrows", L.UPGRADEARROWS_DESC, {
    enabled = false,
    threshold = 0, -- percent an item must beat what you wear by
    corner = "TOPLEFT", -- where the arrow sits on an icon (Blizzard's own UpgradeIcon's corner)
    downCorner = "TOPLEFT", -- where a downgrade's arrow sits
    size = 20, -- the arrow's size on a bag icon, in pixels
    padding = 1, -- how far the arrow sits in from its corner, in pixels
    percent = false, -- the percentage beside the arrow on icons (the tooltip has it)
    tooltip = "name", -- the arrow and percentage "name" (beside the item's name), on a "line" of their own, or "off"
    scores = false,
    downgrades = true, -- a red arrow down on gear worse than what you wear
    higher = true, -- judge gear you're up to `ahead` levels too low for, to grow into
    ahead = 5,
    later = "gray", -- gear you can't wear yet: a "gray" arrow, or the "same" as an upgrade's
    tools = true, -- leave profession tools (fishing poles, the Mining Pick) unmarked
    bags = true,
    reagentBag = true, -- leave the reagent bag unmarked: it holds profession tools, not gear to wear
    bank = true,
    merchant = true,
    loot = true,
    quests = true,
    auction = true,
    weights = {}, -- data: profile key -> { stat -> weight }, what the player changed
    -- data, per character: class -> the tree picked ("1" to "3", or "bear"); none is Auto (the
    -- tab with the most points). By class too, so a choice can only count for the class it was
    -- made for.
    trees = {},
})
module.title = L.UPGRADEARROWS_TITLE
module.pageTitle = L.UPGRADEARROWS_PAGE_TITLE
module.category = "items"
module.added = "1.0.0-beta.1"
module.perCharacter = { trees = true }
module.internal = {}
local internal = module.internal

-- Whether a tree choice fits a class: Auto, a tab, or Bear for a Druid only.
local function fitsClass(class, choice)
    if type(choice) ~= "string" then
        return false
    elseif choice == "bear" then
        return class == "DRUID"
    end
    local index = tonumber(choice)
    return choice == "auto" or (index == 1 or index == 2 or index == 3) and choice == tostring(index)
end

-- Up to 1.0.2 the tree choice was one setting for the whole account (`profile`), so every alt was
-- judged by the last character's pick. It's each character's own now: the first character to log
-- in keeps it, when it fits that character's class; the others start at Auto.
ns.MigrateCharacter(5, function(char, db)
    local saved = db.settings and db.settings.UpgradeArrows
    local choice = saved and saved.profile
    if saved then
        saved.profile = nil
    end
    local class = internal.PlayerClass()
    if type(choice) ~= "string" or choice == "auto" or not fitsClass(class, choice) then
        return
    end
    char.data = type(char.data) == "table" and char.data or {}
    local own = type(char.data.UpgradeArrows) == "table" and char.data.UpgradeArrows or {}
    char.data.UpgradeArrows = own
    own.trees = type(own.trees) == "table" and own.trees or {}
    own.trees[class] = choice
end)

-- The corners the arrow can sit in, for both arrows.
local CORNERS = {
    { "TOPLEFT", L.UPGRADEARROWS_CORNER_TOPLEFT },
    { "TOPRIGHT", L.UPGRADEARROWS_CORNER_TOPRIGHT },
    { "BOTTOMLEFT", L.UPGRADEARROWS_CORNER_BOTTOMLEFT },
    { "BOTTOMRIGHT", L.UPGRADEARROWS_CORNER_BOTTOMRIGHT },
}

-- The profile (Auto, a tab, or Bear) is picked on the module's own page (Page.lua), not here,
-- and saved for each character.
module.options = {
    {
        key = "threshold", name = L.UPGRADEARROWS_THRESHOLD, description = L.UPGRADEARROWS_THRESHOLD_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL, min = 0, max = 25, step = 1, format = "%d%%",
    },
    {
        key = "tooltip", name = L.UPGRADEARROWS_TOOLTIP, description = L.UPGRADEARROWS_TOOLTIP_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL,
        choices = {
            { "name", L.UPGRADEARROWS_TOOLTIP_NAME },
            { "line", L.UPGRADEARROWS_TOOLTIP_LINE },
            { "off", L.UPGRADEARROWS_TOOLTIP_OFF },
        },
    },
    {
        key = "scores", name = L.UPGRADEARROWS_SCORES, description = L.UPGRADEARROWS_SCORES_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL,
    },
    {
        key = "downgrades", name = L.UPGRADEARROWS_DOWNGRADES, description = L.UPGRADEARROWS_DOWNGRADES_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL,
    },
    {
        key = "higher", name = L.UPGRADEARROWS_HIGHER, description = L.UPGRADEARROWS_HIGHER_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL, slider = "ahead",
    },
    {
        key = "ahead", name = L.UPGRADEARROWS_AHEAD, description = L.UPGRADEARROWS_AHEAD_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL, requires = "higher",
        min = 1, max = 20, step = 1, format = L.UPGRADEARROWS_AHEAD_FORMAT,
    },
    {
        key = "later", name = L.UPGRADEARROWS_LATER, description = L.UPGRADEARROWS_LATER_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL, requires = "higher", added = "1.1.0",
        choices = {
            { "gray", L.UPGRADEARROWS_LATER_GRAY },
            { "same", L.UPGRADEARROWS_LATER_SAME },
        },
    },
    {
        key = "tools", name = L.UPGRADEARROWS_TOOLS, description = L.UPGRADEARROWS_TOOLS_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL,
    },
    {
        key = "reagentBag", name = L.UPGRADEARROWS_REAGENT_BAG, description = L.UPGRADEARROWS_REAGENT_BAG_DESC,
        section = L.UPGRADEARROWS_SECTION_GENERAL,
    },
    {
        key = "corner", name = L.UPGRADEARROWS_CORNER, description = L.UPGRADEARROWS_CORNER_DESC,
        section = L.UPGRADEARROWS_SECTION_ARROW, choices = CORNERS,
    },
    {
        key = "downCorner", name = L.UPGRADEARROWS_DOWNCORNER, description = L.UPGRADEARROWS_DOWNCORNER_DESC,
        section = L.UPGRADEARROWS_SECTION_ARROW, choices = CORNERS,
    },
    {
        key = "size", name = L.UPGRADEARROWS_SIZE, description = L.UPGRADEARROWS_SIZE_DESC,
        section = L.UPGRADEARROWS_SECTION_ARROW, min = 12, max = 32, step = 2, format = "%d px",
    },
    {
        key = "padding", name = L.UPGRADEARROWS_PADDING, description = L.UPGRADEARROWS_PADDING_DESC,
        section = L.UPGRADEARROWS_SECTION_ARROW, min = 0, max = 10, step = 1, format = "%d px",
    },
    {
        key = "percent", name = L.UPGRADEARROWS_PERCENT_ICON, description = L.UPGRADEARROWS_PERCENT_ICON_DESC,
        section = L.UPGRADEARROWS_SECTION_ARROW,
    },
    { key = "bags", name = L.UPGRADEARROWS_BAGS, description = L.UPGRADEARROWS_BAGS_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
    { key = "bank", name = L.UPGRADEARROWS_BANK, description = L.UPGRADEARROWS_BANK_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
    { key = "merchant", name = L.UPGRADEARROWS_MERCHANT, description = L.UPGRADEARROWS_MERCHANT_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
    { key = "loot", name = L.UPGRADEARROWS_LOOT, description = L.UPGRADEARROWS_LOOT_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
    { key = "quests", name = L.UPGRADEARROWS_QUESTS, description = L.UPGRADEARROWS_QUESTS_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
    { key = "auction", name = L.UPGRADEARROWS_AUCTION, description = L.UPGRADEARROWS_AUCTION_DESC, section = L.UPGRADEARROWS_SECTION_SHOW },
}

-- Gray rows in Settings: that the arrows are an estimate, and, while the UpgradeArrow addon is
-- on too, that every upgrade gets two arrows.
module.notice = {
    { text = L.UPGRADEARROWS_NOTICE, description = L.UPGRADEARROWS_NOTICE_DESC },
    {
        text = L.UPGRADEARROWS_OTHER_ADDON,
        description = L.UPGRADEARROWS_OTHER_ADDON_DESC,
        shown = function()
            return module.enabled and C_AddOns and C_AddOns.IsAddOnLoaded
                and ns.IsTrue(C_AddOns.IsAddOnLoaded("UpgradeArrow"))
        end,
    },
}

local ATLAS = "bags-greenarrow" -- the arrow Blizzard's bag buttons keep hidden
-- A red arrow pointing down for a downgrade in text, where the green arrow can't be turned over
-- or tinted: Blizzard's old streaming indicator, a plain red arrow down, when the client still
-- has the file (probe: GetFileIDFromPath is Mainline's), else the main menu button's download
-- indicator atlas (Blizzard_MicroMenu, MainMenuBarMicroButtons.lua).
local DOWN_FILE = "Interface\\Buttons\\UI-MicroStream-Red"
local DOWN_ATLAS = "UI-HUD-MicroMenu-StreamDLRed-Up"
local TEXT_ARROW = 14 -- the arrows' size in a tooltip's name line, about the name's height
local GREEN = { 0.1, 1, 0.1 } -- Blizzard's green font color
local RED = { 1, 0.125, 0.125 } -- Blizzard's red font color, for downgrades
local GRAY = { 0.5, 0.5, 0.5 } -- Blizzard's gray font color, for gear you can't wear yet
local PI = math.pi

-- The profile ---------------------------------------------------------------------------------

local profile -- { key, template, weights, guess }, from Weights.lua

---The character's class token, or "?" while the client doesn't say.
---@return string
function internal.PlayerClass()
    local _, class = UnitClass("player")
    return ns.IsText(class, true) and class or "?"
end

---The profile a class judges gear by for a Profile choice ("auto", "1" to "3", or "bear"), and
---whether it's a guess: Auto takes the tab with the most points, and the first tab while
---there's no talent data or no points spent. Bear is for a Druid only.
---@param class string
---@param choice string
---@return table profile from internal.Profile
---@return boolean guess
function internal.ResolveProfile(class, choice)
    if choice == "bear" and class == "DRUID" then
        return internal.Profile(class, 1, true), false
    elseif tonumber(choice) then
        return internal.Profile(class, tonumber(choice)), false
    end
    local best = Talents.Dominant()
    if best and best.spent > 0 then
        return internal.Profile(class, best.index), false
    end
    return internal.Profile(class, 1), true
end

---The character's tree choice: "auto", "1" to "3", or "bear" (a Druid's only).
---@return string
function internal.ProfileChoice()
    local class = internal.PlayerClass()
    local choice = module.db.trees[class]
    return fitsClass(class, choice) and choice or "auto"
end

-- Reads the profile the tree choice and the talents give. Guessed (the first tab) while
-- there's no talent data or no points spent, so it's read again when talents change.
local function updateProfile()
    local guess
    profile, guess = internal.ResolveProfile(internal.PlayerClass(), internal.ProfileChoice())
    profile.guess = guess
end

---The profile in use: `{ key, template, weights, guess }`, for the weights page.
---@return table?
function internal.CurrentProfile()
    return profile
end

-- Scores ----------------------------------------------------------------------------------------

local results = {} -- link -> { upgrade, percent, score, rival }, or false for an item that's no upgrade candidate
local waiting = {} -- itemID -> true while the game has no data for it yet

-- The scoring's own row on the Profiler page.
local Profiler = ns.Profiler
local PART_SCORE = Profiler.Part(module, L.UPGRADEARROWS_PART_SCORE)

-- Hand items, whose score can depend on what's in the bags (a partner for the other hand).
local HAND_SLOTS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local function scoreOf(info)
    return ItemStats.Score(ItemStats.Slotted(info.stats, info.slot), profile.weights)
end

-- What an item is worth against what it would replace, or nil while an item involved isn't
-- cached (noted in `waiting`). False for something that can't be an upgrade: not gear, can't be
-- used, or worn already.
local function compute(link)
    local info, itemID = ItemStats.Get(link)
    if not info then
        if itemID then
            waiting[itemID] = true
        end
        return nil
    end
    local ahead = module.db.higher and module.db.ahead or 0
    if not Equipment.Slots(info.slot) or not Equipment.CanUse(link, info.minLevel, ahead)
        or module.db.tools and ns.Professions.IsTool(info.id, info.classID, info.subclassID)
        or Equipment.IsWorn(link) then
        return false
    end
    local score = scoreOf(info)
    local alternatives, partners = Equipment.Rivals(link, info.slot)
    -- Against a worn two-hander, a one-hander or an off hand is judged with the best hand item in
    -- your bags for the other hand, as the client's own comparison pairs them.
    local partner, partnerScore
    for _, partnerLink in ipairs(partners or {}) do
        local partnerInfo, partnerID = ItemStats.Get(partnerLink)
        if not partnerInfo then
            if partnerID then
                waiting[partnerID] = true
            end
            return nil
        end
        local value = scoreOf(partnerInfo)
        if not partnerScore or value > partnerScore then
            partner, partnerScore = partnerLink, value
        end
    end
    score = score + (partnerScore or 0)
    local rival
    for _, alternative in ipairs(alternatives) do
        local sum = 0
        for _, wornLink in ipairs(alternative) do
            local wornInfo, wornID = ItemStats.Get(wornLink)
            if not wornInfo then
                if wornID then
                    waiting[wornID] = true
                end
                return nil
            end
            sum = sum + scoreOf(wornInfo)
        end
        if not rival or sum < rival then
            rival = sum
        end
    end
    rival = rival or 0
    local threshold = module.db.threshold
    local upgrade, percent = ItemStats.Compare(score, rival, threshold)
    -- A downgrade is worse by more than the threshold too; nothing is a downgrade against an
    -- empty slot.
    local downgrade = not upgrade and percent ~= nil and percent < -threshold
    -- The level it's usable at, for gear judged ahead (Higher Level Gear) that the character
    -- can't wear yet. Scores are forgotten at a level-up, so this never goes stale.
    local level = UnitLevel("player")
    local later = ns.IsNumber(level) and info.minLevel > level and info.minLevel or nil
    return { upgrade = upgrade, downgrade = downgrade, percent = percent, score = score, rival = rival,
        later = later, partner = partner, hand = HAND_SLOTS[info.slot] }
end

-- Whether a result is gear for later that gets the gray arrow (Gear for Later).
local function grayed(result)
    return type(result) == "table" and result.upgrade and result.later and module.db.later == "gray"
end

-- An item's result, kept per link until something it depends on changes.
local function evaluate(link)
    if not (link and profile) then
        return nil
    end
    local result = results[link]
    if result == nil then
        result = Profiler.Call(PART_SCORE, compute, link)
        if result ~= nil then
            results[link] = result
        end
    end
    return result
end

-- An item's result when it gets a mark: an upgrade, or a downgrade while Show Downgrades is on.
-- Else false.
local function markOf(link)
    local result = link and evaluate(link)
    if result and (result.upgrade or (result.downgrade and module.db.downgrades)) then
        return result
    end
    return false
end

local function forgetScores()
    wipe(results)
    ns.Providers.Changed("upgrades") -- other addons' scores are out of date too
end

-- What the public API (API.lua) reads while the module is on: copies, never `results` itself.
local provider = {
    -- An item link's result: { upgrade, downgrade, percent, score, rival }, false for an item
    -- that can't be an upgrade, or nil while the game hasn't cached it.
    Evaluate = function(link)
        local result = evaluate(link)
        if not result then
            return result
        end
        return { upgrade = result.upgrade, downgrade = result.downgrade, percent = result.percent,
            score = result.score, rival = result.rival }
    end,
    -- An item link's score by the weights in use, upgrade candidate or not.
    Score = function(link)
        local info = profile and ItemStats.Get(link)
        return info and scoreOf(info) or nil
    end,
    -- The profile in use: its key ("MAGE:3"), class, talent tab, whether it's a guess, and weights.
    Profile = function()
        if not profile then
            return nil
        end
        local weights = {}
        for stat, weight in pairs(profile.weights) do
            weights[stat] = weight
        end
        return { key = profile.key, class = profile.class, tab = not profile.bear and profile.index or nil,
            bear = profile.bear and true or false, guess = profile.guess and true or false, weights = weights }
    end,
}

-- Arrows ----------------------------------------------------------------------------------------

-- A mark on an icon: our own arrow texture in Blizzard's atlas, and the percentage under it in
-- the outlined number font stack counts use. Shown and hidden together (ItemButtons.Overlays
-- only needs Show and Hide); placed each time it shows, since the Arrow options can change.
local function makeMark(icon)
    local frame = icon.CreateTexture and icon or icon:GetParent()
    local arrow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetAtlas(ATLAS)
    local text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    text:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    local mark = { icon = icon, arrow = arrow, text = text }
    function mark:Show()
        arrow:Show()
    end
    function mark:Hide()
        arrow:Hide()
        text:Hide()
    end
    return mark
end

-- On item icons the mark sits on the icon itself; on a quest reward button on its icon region.
local arrows = ItemButtons.Overlays(makeMark)
local rewardArrows = ItemButtons.Overlays(function(button)
    return makeMark(ItemButtons.RewardIcon(button))
end)

local hasArt, hasDownArt, hasDownFile -- whether this client has the art (checked at enable)

-- Where the percentage goes for each corner the arrow can sit in: toward the icon's middle, so
-- under an arrow at the top and over one at the bottom. The last two values are also the way
-- "in" from that corner, for the Padding option.
local TEXT_ANCHORS = {
    TOPRIGHT = { "TOPRIGHT", "BOTTOMRIGHT", -1, 1 },
    TOPLEFT = { "TOPLEFT", "BOTTOMLEFT", 1, 1 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "TOPRIGHT", -1, -1 },
    BOTTOMLEFT = { "BOTTOMLEFT", "TOPLEFT", 1, -1 },
}

-- Shows the mark for an upgrade's `result` on an icon (or clears it), the arrow `size` wide in
-- the corner the Arrow options pick, with the percentage beside it when there is one.
local function setArrow(set, key, result, size)
    local mark = set:Set(key, hasArt and result)
    if not mark then
        return
    end
    -- A downgrade's arrow is the same art turned over and made red (desaturated first, since a
    -- tint multiplies the green), in its own corner. Gear for later gets it desaturated, gray.
    local down = type(result) == "table" and not result.upgrade
    local gray = grayed(result)
    local color = down and RED or gray and GRAY or GREEN
    local corner = down and module.db.downCorner or module.db.corner
    corner = TEXT_ANCHORS[corner] and corner or "TOPRIGHT"
    local arrow, text = mark.arrow, mark.text
    local anchor = TEXT_ANCHORS[corner]
    local padding = module.db.padding or 0
    -- In from the corner: right and down from the top left, left and up from the bottom right.
    arrow:ClearAllPoints()
    arrow:SetPoint(corner, mark.icon, corner, anchor[3] * padding, -anchor[4] * padding)
    arrow:SetSize(size, size)
    arrow:SetDesaturated(down or gray and true or false)
    arrow:SetRotation(down and PI or 0)
    if down then
        arrow:SetVertexColor(color[1], color[2], color[3])
    else
        arrow:SetVertexColor(1, 1, 1)
    end
    text:SetTextColor(color[1], color[2], color[3])
    local percent = module.db.percent and type(result) == "table" and result.percent
    if percent then
        text:SetText(format(L.UPGRADEARROWS_PERCENT, percent))
        text:ClearAllPoints()
        text:SetPoint(anchor[1], arrow, anchor[2], anchor[3], anchor[4])
        text:Show()
    else
        text:Hide()
    end
end

-- The arrow's size at a place, from the Arrow Size option (a bag icon's), scaled where the icons
-- are smaller.
local function sizeAt(scale)
    return floor(module.db.size * scale + 0.5)
end

local function clearArrows()
    arrows:HideAll()
    rewardArrows:HideAll()
end

-- Bags and bank ---------------------------------------------------------------------------------

-- The reagent bag, which holds profession tools too. Probe: Enum.BagIndex is Mainline's; 5 is
-- its slot there.
local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5

local function updateBag(frame)
    local on, skipReagent = module.db.bags, module.db.reagentBag
    ItemButtons.EachBagButton(frame, function(_, icon, bag, slot)
        local link = on and not (skipReagent and bag == REAGENT_BAG)
            and C_Container.GetContainerItemLink(bag, slot)
        setArrow(arrows, icon, link and markOf(link), sizeAt(1))
    end)
end

local function updateBank()
    local on = module.db.bank
    ItemButtons.EachBankButton(function(icon, tab, slot)
        local link = on and tab and C_Container.GetContainerItemLink(tab, slot)
        setArrow(arrows, icon, link and markOf(link), sizeAt(1))
    end)
end

-- Merchants -------------------------------------------------------------------------------------

local function updateMerchant()
    local on = module.db.merchant
    ItemButtons.EachMerchantItem(function(icon, index)
        local link = on and _G.GetMerchantItemLink(index)
        setArrow(arrows, icon, link and markOf(link), sizeAt(1))
    end)
end

-- The buyback tab reuses the same buttons.
local function clearMerchant()
    ItemButtons.EachMerchantItem(function(icon)
        setArrow(arrows, icon, false)
    end)
end

-- Auction house ---------------------------------------------------------------------------------

-- A browse row gives only an item ID, so an item with a random suffix ("of the Bear") is judged
-- by its base stats, without the suffix's.
local function updateAuction()
    local on = module.db.auction
    ItemButtons.EachAuctionRow(function(icon, itemID)
        setArrow(arrows, icon, on and itemID and markOf("item:" .. itemID), sizeAt(0.6))
    end)
end

-- Loot ------------------------------------------------------------------------------------------

local function markLoot(icon, _, link)
    setArrow(arrows, icon, module.db.loot and link and markOf(link), sizeAt(0.9))
end

local function markRoll(icon, link)
    setArrow(arrows, icon, module.db.loot and link and markOf(link), sizeAt(0.9))
end

-- Quest rewards ---------------------------------------------------------------------------------

local rewardsWaiting -- the rewards frame whose items weren't cached, until GET_ITEM_INFO_RECEIVED

-- Marks the choice that's the biggest upgrade (an empty slot beats any percentage); choices
-- that tie are all marked.
local function updateRewards(rewardsFrame)
    local best, bestValue, uncached = {}, nil, false
    local on = module.db.quests
    local walked = ItemButtons.EachRewardChoice(rewardsFrame, function(button, _, link)
        if not on then
            return
        end
        local result = ns.IsText(link, true) and evaluate(link)
        if result == nil and link then
            uncached = true
        elseif result and result.upgrade then
            local value = result.percent or huge
            if not bestValue or value > bestValue then
                best, bestValue = { { button, result } }, value
            elseif value == bestValue then
                best[#best + 1] = { button, result }
            end
        end
    end, rewardArrows)
    if not walked then
        return
    end
    rewardsWaiting = uncached and rewardsFrame or nil -- looked at again once its items load
    for _, entry in ipairs(best) do
        setArrow(rewardArrows, entry[1], entry[2], sizeAt(1))
    end
end

local function onQuestDisplay()
    local info = _G.QuestInfoFrame
    updateRewards(info and info.rewardsFrame)
end

-- Tooltips --------------------------------------------------------------------------------------

-- A score as text: two decimals, without trailing zeros (4.6, 4.17, 5), since low level gear
-- scores in single digits and rounding hid the difference.
local function scoreText(number)
    local text = format("%.2f", number):gsub("0+$", ""):gsub("%.$", "")
    return text
end

-- The link of a worn item a tooltip shows (the character sheet's, or the Equipped one), or nil.
local function wornLink(data)
    local guid = ns.IsText(data.guid, true) and data.guid
    if guid and Equipment.IsWornGUID(guid) and C_Item.GetItemLinkByGUID then
        local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
        return ok and ns.IsText(link, true) and link or nil
    end
    local link = ns.IsText(data.hyperlink, true) and data.hyperlink
    return link and Equipment.IsWorn(link) and link or nil
end

-- The item a tooltip shows, by its full link (suffix and enchant included): the data's link, or
-- the one its GUID names (the character sheet's tooltips carry a GUID), or else the bare item.
-- Nil for an item that's worn, which is no upgrade over itself and no downgrade either.
local function tooltipLink(data)
    local guid = ns.IsText(data.guid, true) and data.guid
    if guid and Equipment.IsWornGUID(guid) then
        return nil
    end
    if ns.IsText(data.hyperlink, true) then
        return data.hyperlink
    end
    if guid and C_Item.GetItemLinkByGUID then
        local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
        if ok and ns.IsText(link, true) then
            return link
        end
    end
    local id = ItemTooltip.ItemID(data)
    return id and ("item:" .. id) or nil
end

-- The arrow (when the client has the art) and the percentage, for a tooltip, and the color they
-- go in.
local function upgradeText(result)
    if not result.upgrade then
        local arrow = ""
        if hasDownFile then
            arrow = format("|T%s:%d:%d|t ", DOWN_FILE, TEXT_ARROW, TEXT_ARROW)
        elseif hasDownArt then
            arrow = format("|A:%s:%d:%d|a ", DOWN_ATLAS, TEXT_ARROW, TEXT_ARROW)
        end
        return arrow .. format(L.UPGRADEARROWS_PERCENT_TOOLTIP, result.percent), RED
    end
    -- Gear for later keeps the arrow (atlas markup can tint but not desaturate it) with its
    -- percentage in gray.
    local text = hasArt and format("|A:%s:%d:%d|a", ATLAS, TEXT_ARROW, TEXT_ARROW) or ""
    if result.percent then
        text = text .. " " .. format(L.UPGRADEARROWS_PERCENT_TOOLTIP, result.percent)
    elseif text == "" then
        text = L.UPGRADEARROWS_EMPTY_SLOT
    end
    return text, grayed(result) and GRAY or GREEN
end

-- Draws the name line again with the arrow and the percentage at its right, in green, and
-- returns true so Blizzard's is skipped. The name keeps its quality color.
local function onNameLine(tooltip, data, lineData)
    if not (module.enabled and module.db.tooltip == "name" and profile) then
        return
    end
    local lines = ns.IsReadable(data.lines) and data.lines
    if not (type(lines) == "table" and lines[1] == lineData) then
        return
    end
    local name = lineData.leftText
    if not ns.IsText(name, true) then
        return
    end
    local result = markOf(tooltipLink(data))
    if not result then
        return
    end
    local right, tint = upgradeText(result)
    local r, g, b = 1, 1, 1
    local color = lineData.leftColor
    if ns.IsReadable(color) and type(color) == "table" and color.GetRGB then
        r, g, b = color:GetRGB()
    end
    tooltip:AddDoubleLine(name, right, r, g, b, tint[1], tint[2], tint[3])
    return true
end

-- The Upgrade line (when the arrow goes on a line of its own), the level an upgrade for later is
-- usable at, and the Score line, among our other lines about the item.
local function onTooltip(tooltip, data)
    local ownLine, shown = module.db.tooltip == "line", module.db.tooltip ~= "off"
    if not (module.enabled and profile and (shown or module.db.scores)) then
        return
    end
    -- What you wear is no upgrade candidate, but its score is what others are measured by.
    local worn = module.db.scores and wornLink(data)
    if worn then
        local info = ItemStats.Get(worn)
        if info then
            ItemTooltip.AddInfo(tooltip, L.UPGRADEARROWS_SCORE_LINE,
                format(L.UPGRADEARROWS_SCORE_WORN, scoreText(scoreOf(info))), "right", "gray")
        end
        return
    end
    local result = evaluate(tooltipLink(data))
    if not result then
        return
    end
    if ownLine and (result.upgrade or (result.downgrade and module.db.downgrades)) then
        local text, tint = upgradeText(result)
        ItemTooltip.AddInfo(tooltip, L.UPGRADEARROWS_LINE, text, "right", tint)
    end
    -- The bag item it was judged with, by name, so the percentage makes sense.
    local partnerName = result.partner and result.partner:match("%[(.-)%]")
    local marked = result.upgrade or (result.downgrade and module.db.downgrades)
    if partnerName and (module.db.scores or shown and marked) then
        ItemTooltip.AddInfo(tooltip, L.UPGRADEARROWS_PAIRED_LINE, partnerName, "right", "gray")
    end
    if shown and result.upgrade and result.later then
        ItemTooltip.AddInfo(tooltip, L.UPGRADEARROWS_LATER_LINE, format(L.UPGRADEARROWS_LATER_LEVEL, result.later),
            "right", "gray")
    end
    if not module.db.scores then
        return
    end
    local text
    if result.rival > 0 then
        text = format(L.UPGRADEARROWS_SCORE_VALUE, scoreText(result.score), scoreText(result.rival))
    else
        text = format(L.UPGRADEARROWS_SCORE_NONE, scoreText(result.score))
    end
    ItemTooltip.AddInfo(tooltip, L.UPGRADEARROWS_SCORE_LINE, text, "right", "gray")
end

-- Module ----------------------------------------------------------------------------------------

local function refresh()
    ItemButtons.EachOpenBag(updateBag)
    local bank = _G.BankFrame
    if bank and bank:IsShown() then
        updateBank()
    end
    local merchant = _G.MerchantFrame
    if merchant and merchant:IsShown() and (merchant.selectedTab or 1) == 1 then
        updateMerchant()
    end
    updateAuction()
    ItemButtons.EachLootSlot(markLoot)
    ItemButtons.EachRoll(markRoll)
    local info = _G.QuestInfoFrame
    if info and info.rewardsFrame and info.rewardsFrame:IsVisible() then
        updateRewards(info.rewardsFrame)
    end
end

local refreshSoon = ns.Frames.Coalesce(function()
    if module.enabled then
        refresh()
    end
end, 0.5, module)

-- Item data arrives a little after a window opens; look again once it has, for items we
-- couldn't answer for yet. This fires for every item the game loads.
local function onItemInfo(_, itemID)
    if itemID and waiting[itemID] then
        waiting[itemID] = nil
        refreshSoon()
    elseif rewardsWaiting and rewardsWaiting:IsVisible() then
        refreshSoon()
    end
end

-- What you wear decides every rival, so every score is forgotten.
local function onGearChanged()
    forgetScores()
    refreshSoon()
end

-- While a two-hander is worn, a hand item is judged with a partner from the bags, so the bags
-- changing can change its score: those are forgotten (only those).
local function onBagsChanged()
    if Equipment.WornType(16) ~= "INVTYPE_2HWEAPON" then
        return
    end
    local any = false
    for link, result in pairs(results) do
        if type(result) == "table" and result.hand then
            results[link] = nil
            any = true
        end
    end
    if any then
        ns.Providers.Changed("upgrades")
        refreshSoon()
    end
end

-- A level-up changes what a point of Strength, Agility, and Intellect gives (Weights.lua takes
-- them from the client when it builds the profile), which gear is usable, and which is for
-- later, so the profile is built again and every score forgotten. A moment after the event,
-- since the client may still give the old level's rates during it.
local onLevelUp = ns.Frames.Coalesce(function()
    internal.WeightsChanged()
end, 1, module)

-- Training only makes gear usable that wasn't: only the "can't be an upgrade" answers can
-- change; a score against what you wear stays right.
local function onPlayerChanged()
    for link, result in pairs(results) do
        if result == false then
            results[link] = nil
        end
    end
    ns.Providers.Changed("upgrades")
    refreshSoon()
end

-- Talents may change the profile; when they do, every score goes with it.
local function onTalentsChanged()
    local before = profile and profile.key
    updateProfile()
    if profile.key ~= before or profile.guess then
        forgetScores()
    end
    refreshSoon()
end

function module:OnEnable()
    hasArt = ns.Frames.HasAtlas(ATLAS)
    hasDownArt = ns.Frames.HasAtlas(DOWN_ATLAS)
    local getFileID = _G.GetFileIDFromPath
    local ok, fileID = pcall(function()
        return getFileID and getFileID(DOWN_FILE)
    end)
    hasDownFile = ok and ns.IsNumber(fileID) and fileID > 0
    updateProfile()
    self:Hook("MerchantFrame_UpdateMerchantInfo", updateMerchant)
    self:Hook("MerchantFrame_UpdateBuybackInfo", clearMerchant)
    ItemButtons.HookBags(self, updateBag)
    ItemButtons.HookBank(self, updateBank)
    ItemButtons.HookLoot(self, markLoot)
    ItemButtons.HookRolls(self, markRoll)
    ItemButtons.HookAuction(self, updateAuction)
    self:Hook("QuestInfo_Display", onQuestDisplay)
    ItemTooltip.ReplaceLine(onNameLine, self)
    ItemTooltip.OnInfo(onTooltip, self)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
    self:On("PLAYER_EQUIPMENT_CHANGED", onGearChanged)
    self:On("BAG_UPDATE_DELAYED", onBagsChanged)
    self:On("PLAYER_LEVEL_UP", onLevelUp)
    self:On("SKILL_LINES_CHANGED", onPlayerChanged)
    self:On("PLAYER_ENTERING_WORLD", onTalentsChanged)
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        if ns.HasEvent(event) then
            self:On(event, onTalentsChanged)
        end
    end
    ns.Providers.Set("upgrades", provider)
    refresh()
end

function module:OnDisable()
    ns.Providers.Set("upgrades", nil)
    ItemButtons.CancelAuction(updateAuction)
    forgetScores()
    wipe(waiting)
    rewardsWaiting = nil
    clearArrows()
end

function module:OnOptionChanged(key)
    if not self.enabled then
        return
    end
    -- The profile isn't an option: it changes through internal.SetProfile. Gear for Later only
    -- changes how a mark looks.
    if key == "threshold" or key == "higher" or key == "ahead" or key == "tools" then
        forgetScores()
    end
    refreshSoon()
end

---Forgets every score, for the weights page after a weight changes.
function internal.WeightsChanged()
    if module.enabled then
        updateProfile()
        forgetScores()
        refreshSoon()
    end
end

---Picks the character's profile ("auto", "1" to "3", or "bear"), from the weights page. Auto,
---or a choice that doesn't fit the class, saves nothing.
---@param value string
function internal.SetProfile(value)
    local class = internal.PlayerClass()
    module.db.trees[class] = value ~= "auto" and fitsClass(class, value) and value or nil
    internal.WeightsChanged()
end

-- The stats met on items that no weight covers, so they can be added (Lib/ItemStats.lua).
module.debugActions = {
    {
        name = L.UPGRADEARROWS_UNKNOWN,
        button = L.UPGRADEARROWS_UNKNOWN_BUTTON,
        description = L.UPGRADEARROWS_UNKNOWN_DESC,
        whileOff = true,
        section = L.DEBUG_SECTION_DIAGNOSTICS,
        fn = function()
            local list = ItemStats.Unknown()
            if #list == 0 then
                ns.Print(L.UPGRADEARROWS_UNKNOWN_NONE)
            else
                ns.Print(format(L.UPGRADEARROWS_UNKNOWN_LIST, table.concat(list, ", ")))
            end
        end,
    },
}
