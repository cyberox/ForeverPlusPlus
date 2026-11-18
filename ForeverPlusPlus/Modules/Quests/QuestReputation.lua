-- Quest Reputation: shows the reputation a quest gives in the quest log on the map, with which
-- faction: as reward buttons in its Rewards, or as lines ("+250 reputation with Thorium
-- Brotherhood") at the bottom of its description. Blizzard's quest details show only a major
-- faction's reputation (QuestInfo_ShowRewards, Mainline/QuestInfo.lua), never a classic faction's,
-- so the quest log doesn't say it.
--
-- The numbers are the game's own: QuestInfo_ShowRewards calls ProcessQuestLogRewardFactions for
-- the selected quest, then GetNumQuestLogRewardFactions and GetQuestLogRewardFactionInfo hold the
-- factions and what each gives, in hundredths (25000 is 250; RepRewards, which does the same,
-- divides by 100). Blizzard's call comes first in the same QuestInfo_Display, so we don't make it
-- ourselves. It makes it before it gives up on a quest with no other rewards, so those count too.
-- A major faction's reputation is Blizzard's own button, so it isn't repeated here.
--
-- Description: our lines go on the end of QuestInfoDescriptionText after QuestInfo_Display sets
-- it (the elements below it are anchored to it, so they move down by themselves). The text is set
-- again from scratch on every display, so only a change of ours needs taking back off.
--
-- Rewards: the map shows a quest in two QuestInfo_Display calls, its details and then its rewards
-- (QuestMapFrame_ShowQuestDetails), and reads MapQuestInfoRewardsFrame's height after the second
-- to size the rewards panel. So after that call our buttons go in a frame of our own under
-- Blizzard's last row, in the same small reputation template, two to a row, and Blizzard's frame
-- grows by them. A quest with nothing else to give leaves Blizzard's frame hidden, with whatever
-- the last quest showed still in it, so ours stands alone where it would be, and the panel is
-- sized for it once Blizzard has sized it for nothing. The quest log's popup has no such panel,
-- so it gets the lines either way.
local _, ns = ...

local _G, ipairs, type, setmetatable = _G, ipairs, type, setmetatable
local floor, abs, ceil = math.floor, math.abs, math.ceil
local concat = table.concat

local L = ns.L
local Colors = ns.Colors
local Quests = ns.Quests

local module = ns.NewModule("QuestReputation", L.QUESTREPUTATION_DESC, {
    enabled = false,
    show = "rewards",
    icon = "handshake",
})
module.title = L.QUESTREPUTATION_TITLE
module.category = "quests"
module.added = "1.9.0"

module.options = {
    {
        key = "show",
        name = L.QUESTREPUTATION_SHOW,
        description = L.QUESTREPUTATION_SHOW_DESC,
        choices = {
            { "rewards", L.QUESTREPUTATION_SHOW_REWARDS },
            { "description", L.QUESTREPUTATION_SHOW_DESCRIPTION },
        },
    },
    {
        key = "icon",
        name = L.QUESTREPUTATION_ICON,
        description = L.QUESTREPUTATION_ICON_DESC,
        shown = function(db) return db.show == "rewards" end,
        choices = {
            { "handshake", L.QUESTREPUTATION_ICON_HANDSHAKE },
            { "banner", L.QUESTREPUTATION_ICON_BANNER },
        },
    },
}

-- Dark colors for the quest log's parchment, Blizzard's bright ones when it uses light text.
local GAIN, LOSS = { r = 0.1, g = 0.5, b = 0.1 }, { r = 0.7, g = 0.1, b = 0.1 }

-- The art and spacing of Blizzard's map rewards (QuestInfo.xml, QuestInfo.lua): the small
-- reputation button, its 8 between buttons in a row, 2 between rows, 5 before a new section,
-- and where QUEST_TEMPLATE_MAP_REWARDS puts the rewards frame.
local TEMPLATE = "SmallQuestInfoRewardReputationTemplate"
local HANDSHAKE = "Interface\\Icons\\Achievement_Reputation_01"
local BANNER = { Alliance = "Interface\\Icons\\INV_BannerPVP_02", Horde = "Interface\\Icons\\INV_BannerPVP_01" }
local BUTTON_WIDTH, BUTTON_HEIGHT = 130, 30
local COLUMN_GAP, ROW_GAP, SECTION_GAP = 8, 2, 5
local MAP_X, MAP_Y = 12, -52
local PANEL_PADDING = 62 -- what QuestMapFrame_ShowQuestDetails adds to the rewards frame's height

local suffix -- what we added to the description, to take off again
local holder -- our frame of reward buttons on the map
local buttons = {}
local rewardOf = setmetatable({}, { __mode = "k" }) -- our button -> its reward
local standalone -- our buttons stand alone, for a quest with no other rewards

-- The factions the selected quest changes, as { name, amount } in standing points, or an empty list.
-- Probe: all of these are the client's own, and a patch may drop them.
local function rewards()
    local list = {}
    local count, info = _G.GetNumQuestLogRewardFactions, _G.GetQuestLogRewardFactionInfo
    local getFaction = _G.C_Reputation and _G.C_Reputation.GetFactionDataByID
    if not (count and info and getFaction) then
        return list
    end
    local n = count()
    if not ns.IsNumber(n) then
        return list
    end
    for i = 1, n do
        local factionID, amount = info(i)
        if ns.IsNumber(factionID) and ns.IsNumber(amount) then
            -- To the nearest whole point, a loss the same as a gain: floor alone makes -2510 -26.
            amount = amount < 0 and -floor(-amount / 100 + 0.5) or floor(amount / 100 + 0.5)
            local data = getFaction(factionID)
            local name = type(data) == "table" and data.name
            if amount ~= 0 and ns.IsText(name, true) then
                list[#list + 1] = { name = name, amount = amount }
            end
        end
    end
    return list
end

-- The selected quest's rewards, while the module is on and Blizzard has just worked them out.
local function selected()
    local questID = module.enabled and Quests.DetailsID()
    -- Only for a quest whose rewards Blizzard just worked out: its call is the one that fills the list.
    -- A client without ShouldShowQuestRewards fills it every time, as older ones did.
    local shouldShow = _G.C_QuestLog.ShouldShowQuestRewards
    if questID and _G.QuestInfoFrame and _G.QuestInfoFrame.questLog
        and (not shouldShow or shouldShow(questID)) then
        return rewards()
    end
    return {}
end

-- "+250", green for a gain and red for a loss: dark on parchment, bright otherwise.
local function amountText(amount, bright)
    local gain, loss = GAIN, LOSS
    if bright then
        gain, loss = _G.GREEN_FONT_COLOR, _G.RED_FONT_COLOR
    end
    local text = (amount > 0 and "+" or "-") .. ns.Text.Number(abs(amount))
    return Colors.Text(amount > 0 and gain or loss, text)
end

-- "+250 reputation with Name".
local function line(reward, bright)
    return L.QUESTREPUTATION_LINE:format(amountText(reward.amount, bright), reward.name)
end

-- Takes our lines off the end of the description.
local function strip(text)
    if suffix and text:sub(-#suffix) == suffix then
        text = text:sub(1, -#suffix - 1)
    end
    suffix = nil
    return text
end

-- Puts the selected quest's reputation after its description when `wanted`, and takes ours off
-- otherwise.
local function applyDescription(wanted)
    local frame = _G.QuestInfoDescriptionText
    local text = frame and frame:GetText()
    if type(text) ~= "string" then
        return
    end
    local plain = strip(text)
    if wanted then
        local light = _G.QuestTextContrast and _G.QuestTextContrast.UseLightText and _G.QuestTextContrast.UseLightText()
        local shown = {}
        for _, reward in ipairs(selected()) do
            shown[#shown + 1] = line(reward, light)
        end
        if #shown > 0 then
            suffix = "\n\n" .. concat(shown, "\n")
            plain = plain .. suffix
        end
    end
    if plain ~= text then
        frame:SetText(plain)
    end
end

-- A reward button's tooltip: the faction, and what the quest does to your standing with it.
local function onEnter(self)
    local reward = rewardOf[self]
    if not reward then
        return
    end
    local tooltip = _G.GameTooltip
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetText(reward.name, 1, 1, 1)
    tooltip:AddLine(line(reward, true), nil, nil, nil, true)
    tooltip:Show()
end

local function onLeave()
    _G.GameTooltip:Hide()
end

local function hideButtons()
    if holder then
        holder:Hide()
    end
    standalone = nil
end

-- The icon every button wears: the handshake, or the banner of the player's side.
local function icon()
    if module.db.icon == "banner" then
        local side = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
        return ns.IsText(side, true) and BANNER[side] or HANDSHAKE
    end
    return HANDSHAKE
end

-- Our buttons for `list`, in rows of two from the holder's top; returns their height.
local function layout(list)
    local texture = icon()
    if not holder then
        holder = _G.CreateFrame("Frame")
        holder:SetSize(BUTTON_WIDTH * 2 + COLUMN_GAP, BUTTON_HEIGHT)
    end
    for _, button in ipairs(buttons) do
        button:Hide()
    end
    for i, reward in ipairs(list) do
        local button = buttons[i]
        if not button then
            button = _G.CreateFrame("Button", nil, holder, TEMPLATE)
            button:SetScript("OnEnter", onEnter)
            button:SetScript("OnLeave", onLeave)
            buttons[i] = button
        end
        rewardOf[button] = reward
        button.Icon:SetTexture(texture)
        button.Name:SetText(reward.name)
        button.RewardAmount:SetText(amountText(reward.amount, true))
        local column, row = (i - 1) % 2, floor((i - 1) / 2)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", holder, "TOPLEFT", column * (BUTTON_WIDTH + COLUMN_GAP),
            -row * (BUTTON_HEIGHT + ROW_GAP))
        button:Show()
    end
    local rows = ceil(#list / 2)
    local height = rows * BUTTON_HEIGHT + (rows - 1) * ROW_GAP
    holder:SetHeight(height)
    holder:Show()
    return height
end

-- After the map's rewards: our buttons under Blizzard's last row, and its frame taller by them.
-- With no rewards of Blizzard's, ours stand alone in the panel (`parent`) where its frame goes.
local function applyRewards(parent)
    hideButtons()
    local frame = _G.MapQuestInfoRewardsFrame
    local list = module.db.show == "rewards" and selected() or {}
    if not (frame and parent and #list > 0) then
        return
    end
    if frame:IsShown() then
        local top = frame:GetHeight() + SECTION_GAP
        local height = layout(list)
        holder:SetParent(frame)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
        frame:SetHeight(top + height)
    else
        layout(list)
        holder:SetParent(parent)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", parent, "TOPLEFT", MAP_X, MAP_Y - SECTION_GAP)
        standalone = true
    end
end

local function onDisplay(template, parent)
    local rewardsTemplate = template == _G.QUEST_TEMPLATE_MAP_REWARDS
    if template == _G.QUEST_TEMPLATE_MAP_DETAILS then
        hideButtons()
    elseif rewardsTemplate then
        applyRewards(parent)
    elseif template ~= nil then
        -- A quest giver's window or the quest log's popup, never the map's rewards.
        hideButtons()
    end
    -- The map's rewards call comes last, so the description is redone then with this quest's list.
    local popup = template == _G.QUEST_TEMPLATE_LOG
    applyDescription(module.enabled and (module.db.show == "description" or popup))
end

-- Blizzard sized the rewards panel for a quest with nothing to give; size it for ours instead, and
-- show its Rewards label, which it hides when its own rows are none.
local function onShowDetails()
    if not (standalone and holder and holder:IsShown()) then
        return
    end
    local details = _G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame
    if details and details.SetRewardsHeight then
        details:SetRewardsHeight(holder:GetHeight() + SECTION_GAP + PANEL_PADDING)
        local label = details.RewardsFrameContainer and details.RewardsFrameContainer.RewardsFrame
            and details.RewardsFrameContainer.RewardsFrame.Label
        if label then
            label:Show()
        end
    end
end

function module:OnEnable()
    self:Hook("QuestInfo_Display", onDisplay)
    self:Hook("QuestMapFrame_ShowQuestDetails", onShowDetails)
    applyDescription(false)
end

-- Hooks stop by themselves; what's open loses ours, and the next quest shown is Blizzard's alone.
function module:OnDisable()
    hideButtons()
    applyDescription(false)
end

-- The quest shown now gets the other kind at its next display; take off what no longer fits.
function module:OnOptionChanged(key)
    if key == "icon" then
        local texture = icon()
        for _, button in ipairs(buttons) do
            button.Icon:SetTexture(texture)
        end
    elseif module.db.show == "rewards" then
        applyDescription(false)
    else
        hideButtons()
    end
end
