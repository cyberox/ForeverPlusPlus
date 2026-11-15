-- Best Quest Reward: puts a small gold coin on the quest reward choice that sells to a vendor for
-- the most (sell price times how many you get), in the quest window and the quest's details on
-- the map. It only marks; the choice is still yours. Rewards that tie for the most are all
-- marked, and nothing is marked when every choice sells for the same or for nothing.
--
-- The reward buttons are Blizzard's (QuestInfo_Display fills them, both for a quest giver and the
-- quest log; Lib/ItemButtons.lua walks them). Our coin is our own texture on the button's icon;
-- nothing is written onto Blizzard's frames.
local _, ns = ...

local _G, ipairs, select, type = _G, ipairs, select, type
local C_Item = C_Item

local L = ns.L
local ItemButtons = ns.ItemButtons

local module = ns.NewModule("BestQuestReward", L.BESTQUESTREWARD_DESC, {
    enabled = true,
    -- Where the coin sits on a reward's icon. Bottom left: Upgrade Arrows' arrow is top left on the
    -- same buttons by default and the stack count is bottom right, so the coin covers neither.
    corner = "BOTTOMLEFT",
})
module.title = L.BESTQUESTREWARD_TITLE
module.category = "quests"
-- The Corner every mark on an icon has, with the row every mark has for a corner another takes:
-- Upgrade Arrows marks the same reward buttons, in the same corner by default.
module.options = {
    ItemButtons.CornerOption(L.BESTQUESTREWARD_CORNER_DESC, nil, {
        added = "1.6.0",
        conflicts = {
            {
                module = "UpgradeArrows", key = "corner", text = L.BESTQUESTREWARD_CONFLICT_ARROW,
                when = function(db, other)
                    return other.quests and db.corner == other.corner
                end,
            },
        },
    }),
}

-- How far past the icon's corner the coin hangs (a negative padding pushes it out).
local COIN_OUT = -3

local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SIZE = 16

-- Our coin on a reward button, by its icon.
local coins = ItemButtons.Overlays(function(button)
    local coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture(COIN_TEXTURE)
    coin:SetSize(COIN_SIZE, COIN_SIZE)
    return coin -- placed each time it's shown, in the corner picked
end)
local waiting -- the rewards frame whose items weren't cached, until GET_ITEM_INFO_RECEIVED

-- How many of the choice you get and its item ID, from the quest log or the quest giver.
local function choiceInfo(index, link, questLog)
    local count, itemID
    if questLog then
        if _G.GetQuestLogChoiceInfo then
            count, _, _, itemID = select(3, _G.GetQuestLogChoiceInfo(index))
        end
    elseif _G.GetQuestItemInfo then
        count, _, _, itemID = select(3, _G.GetQuestItemInfo("choice", index))
    end
    if type(itemID) ~= "number" and link then
        itemID = C_Item.GetItemInfoInstant(link)
    end
    if type(count) ~= "number" or count < 1 then
        count = 1
    end
    return count, itemID
end

-- What the choice sells for in all, or nil while its item isn't cached (asked for meanwhile).
local function choiceValue(choice)
    local count, itemID = choiceInfo(choice.index, choice.link, choice.questLog)
    if not itemID then
        return nil
    end
    local price = ns.Prices.Vendor(itemID)
    if not price then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil
    end
    return price * count
end

local function update(rewardsFrame)
    -- The item choices among the frame's buttons (currency choices have no sell price).
    local choices = {}
    local walked = ItemButtons.EachRewardChoice(rewardsFrame, function(button, index, link, questLog)
        choices[#choices + 1] = { button = button, index = index, link = link, questLog = questLog }
    end, coins)
    if not walked then
        return
    end
    waiting = nil
    if #choices < 2 then
        return
    end
    local values, best, lowest = {}, 0, nil
    for i, choice in ipairs(choices) do
        local value = choiceValue(choice)
        if not value then
            -- Mark nothing until every choice's price is known, then look again.
            waiting = rewardsFrame
            return
        end
        values[i] = value
        if value > best then
            best = value
        end
        if not lowest or value < lowest then
            lowest = value
        end
    end
    if best <= 0 or best == lowest then
        return
    end
    for i, choice in ipairs(choices) do
        local coin = coins:Set(choice.button, values[i] == best)
        if coin then
            ItemButtons.PlaceInCorner(coin, ItemButtons.RewardIcon(choice.button), module.db.corner, COIN_OUT)
        end
    end
end

local function onDisplay()
    local info = _G.QuestInfoFrame
    update(info and info.rewardsFrame)
end

local function onItemInfo()
    local frame = waiting
    if frame and frame:IsVisible() then
        update(frame)
    end
end

function module:OnEnable()
    self:Hook("QuestInfo_Display", onDisplay)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
    local info = _G.QuestInfoFrame
    if info and info.rewardsFrame and info.rewardsFrame:IsVisible() then
        onDisplay()
    end
end

function module:OnDisable()
    waiting = nil
    coins:HideAll()
end

function module:OnOptionChanged()
    onDisplay() -- the coin moves to its new corner
end
