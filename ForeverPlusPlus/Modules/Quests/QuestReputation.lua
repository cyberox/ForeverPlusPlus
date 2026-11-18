-- Quest Reputation: lists the reputation a quest gives, "+250 reputation with Thorium Brotherhood",
-- at the bottom of the quest's description in the quest log on the map. Blizzard's quest details
-- show only a major faction's reputation (QuestInfo_ShowRewards, Mainline/QuestInfo.lua), never a
-- classic faction's, so the quest log doesn't say it.
--
-- The numbers are the game's own: QuestInfo_ShowRewards calls ProcessQuestLogRewardFactions for
-- the selected quest, then GetNumQuestLogRewardFactions and GetQuestLogRewardFactionInfo hold the
-- factions and what each gives, in hundredths (25000 is 250; RepRewards, which does the same,
-- divides by 100). Blizzard's call comes first in the same QuestInfo_Display, so we don't make it
-- ourselves. A major faction's reputation is Blizzard's own row, so it isn't repeated here.
--
-- The lines are ours, added to the end of QuestInfoDescriptionText after QuestInfo_Display sets
-- it (the elements below it are anchored to it, so they move down by themselves). The text is
-- set again from scratch on every display, so only a change of ours needs taking back off.
local _, ns = ...

local _G, ipairs, type = _G, ipairs, type
local floor, abs = math.floor, math.abs
local concat = table.concat

local L = ns.L
local Colors = ns.Colors
local Quests = ns.Quests

local module = ns.NewModule("QuestReputation", L.QUESTREPUTATION_DESC, { enabled = false })
module.title = L.QUESTREPUTATION_TITLE
module.category = "quests"
module.added = "1.9.0"

-- Dark colors for the quest log's parchment, Blizzard's bright ones when it uses light text.
local GAIN, LOSS = { r = 0.1, g = 0.5, b = 0.1 }, { r = 0.7, g = 0.1, b = 0.1 }

local suffix -- what we added to the description, to take off again

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

-- The lines for a list of rewards: "+250 reputation with Name", green for a gain, red for a loss.
local function lines(list)
    local light = _G.QuestTextContrast and _G.QuestTextContrast.UseLightText and _G.QuestTextContrast.UseLightText()
    local gain = light and _G.GREEN_FONT_COLOR or GAIN
    local loss = light and _G.RED_FONT_COLOR or LOSS
    local out = {}
    for _, reward in ipairs(list) do
        local amount = reward.amount
        local text = (amount > 0 and "+" or "-") .. ns.Text.Number(abs(amount))
        out[#out + 1] = L.QUESTREPUTATION_LINE:format(Colors.Text(amount > 0 and gain or loss, text), reward.name)
    end
    return out
end

-- Takes our lines off the end of the description.
local function strip(text)
    if suffix and text:sub(-#suffix) == suffix then
        text = text:sub(1, -#suffix - 1)
    end
    suffix = nil
    return text
end

-- Puts the selected quest's reputation after its description, or just takes ours off while the
-- module is off or the quest gives none.
local function apply()
    local frame = _G.QuestInfoDescriptionText
    local text = frame and frame:GetText()
    if type(text) ~= "string" then
        return
    end
    local plain = strip(text)
    local questID = module.enabled and Quests.DetailsID()
    -- Only for a quest whose rewards Blizzard just worked out: its call is the one that fills the list.
    -- A client without ShouldShowQuestRewards fills it every time, as older ones did.
    local shouldShow = _G.C_QuestLog.ShouldShowQuestRewards
    if questID and _G.QuestInfoFrame and _G.QuestInfoFrame.questLog
        and (not shouldShow or shouldShow(questID)) then
        local shown = lines(rewards())
        if #shown > 0 then
            suffix = "\n\n" .. concat(shown, "\n")
            plain = plain .. suffix
        end
    end
    if plain ~= text then
        frame:SetText(plain)
    end
end

function module:OnEnable()
    self:Hook("QuestInfo_Display", apply)
    apply()
end

-- Hooks stop by themselves; what's open gets its own text back.
function module:OnDisable()
    apply()
end
