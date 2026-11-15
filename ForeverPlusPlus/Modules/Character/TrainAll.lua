-- Train All: a button beside the trainer window's Train that learns everything you can learn and
-- afford, one after another. Its tooltip says how many and what they cost together.
--
-- The game takes one purchase at a time and the list's rows move after each, so each is bought
-- once the trainer has answered the one before (TRAINER_UPDATE), looking the list over again. A
-- new profession is never bought: that asks first (Blizzard's CONFIRM_PROFESSION) and is the
-- player's to choose. Nor a hunter's pet skills, which cost training points, not money.
--
-- BuyTrainerService is what Blizzard's Train button calls (Blizzard_TrainerUI.lua, wow-ui-source's
-- forever branch). **Unverified** in game: whether the client takes it once a click has passed.
local _, ns = ...

local _G, format, pcall = _G, string.format, pcall
local GetNumTrainerServices, GetTrainerServiceInfo = GetNumTrainerServices, GetTrainerServiceInfo
local GetTrainerServiceCost, BuyTrainerService = GetTrainerServiceCost, BuyTrainerService
local GetMoney, GameTooltip, C_Trainer, Enum = GetMoney, GameTooltip, C_Trainer, Enum

local L = ns.L

local module = ns.NewModule("TrainAll", L.TRAINALL_DESC, {
    enabled = false,
})
module.title = L.TRAINALL_TITLE
module.category = "character"
module.added = "1.7.0"

local WIDTH = 80 -- as wide as Blizzard's Train button
local SETTLE = 0.1 -- seconds after the trainer answers before the next is bought
local GIVE_UP = 3 -- seconds to wait for an answer before stopping

local button -- ours, made when the trainer window first loads
local left = 0 -- how many are still to buy; 0 while not training
local timer = ns.Frames.Timer(module)

-- A pet trainer's skills cost training points.
local function petTrainer()
    local kind = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    return kind ~= nil and C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType() == kind
end

-- What can be bought now: how many, their cost together, and the first one's row. Bought from
-- the top with the money left after each, so the count is what the money reaches.
local function buyable()
    local count, total, first = 0, 0, nil
    if petTrainer() then
        return count, total, first
    end
    local money = GetMoney()
    for index = 1, GetNumTrainerServices() do
        local _, kind = GetTrainerServiceInfo(index)
        if kind == "available" then
            local cost, isProfession = GetTrainerServiceCost(index)
            cost = cost or 0
            if not isProfession and total + cost <= money then
                count, total = count + 1, total + cost
                first = first or index
            end
        end
    end
    return count, total, first
end

local function refresh()
    if button then
        button:SetShown(module.enabled and not petTrainer())
        button:SetEnabled(left == 0 and buyable() > 0)
    end
end

local function stop()
    left = 0
    timer:Cancel()
    refresh()
end

local function buyNext()
    local _, _, first = buyable()
    if left <= 0 or not first then
        stop()
        return
    end
    left = left - 1
    if not pcall(BuyTrainerService, first) then
        stop()
        return
    end
    timer:Start(GIVE_UP, stop) -- the trainer's answer starts the next one sooner
end

local function onUpdate()
    if left > 0 then
        timer:Start(SETTLE, buyNext)
    else
        refresh()
    end
end

local function onEnter(self)
    local count, total = buyable()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.TRAINALL_BUTTON, 1, 1, 1)
    if count > 0 then
        GameTooltip:AddLine(format(L.TRAINALL_TOOLTIP, count, ns.Money(total)), nil, nil, nil, true)
    else
        GameTooltip:AddLine(L.TRAINALL_NOTHING, nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local function build()
    local train = _G.ClassTrainerTrainButton
    if button or not (train and _G.ClassTrainerFrame) then
        return
    end
    button = ns.Frames.Button(_G.ClassTrainerFrame, L.TRAINALL_BUTTON, WIDTH, function()
        left = buyable()
        refresh()
        buyNext()
    end)
    button:SetPoint("RIGHT", train, "LEFT", -2, 0)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    refresh()
end

function module:IsAvailable()
    return GetNumTrainerServices ~= nil and GetTrainerServiceInfo ~= nil and BuyTrainerService ~= nil
end

function module:OnEnable()
    ns.AddOns.WhenLoaded("Blizzard_TrainerUI", build)
    self:On("TRAINER_SHOW", onUpdate)
    self:On("TRAINER_UPDATE", onUpdate)
    self:On("PLAYER_MONEY", onUpdate)
    self:On("TRAINER_CLOSED", stop)
    refresh()
end

function module:OnDisable()
    ns.AddOns.Cancel("Blizzard_TrainerUI", build)
    stop()
end
