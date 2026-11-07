-- Auto Repair: repairs all gear when a merchant who can repair opens, from the guild bank, the
-- player's own money, or the guild bank first, and says in chat what it cost. Hold the Skip Key
-- (Shift by default) while opening the merchant to skip it.
local _, ns = ...

local format, tonumber = string.format, tonumber
local CanMerchantRepair, GetRepairAllCost, RepairAllItems = CanMerchantRepair, GetRepairAllCost, RepairAllItems
local IsInGuild, CanGuildBankRepair, GetGuildBankWithdrawMoney = IsInGuild, CanGuildBankRepair, GetGuildBankWithdrawMoney
local GetMoney = GetMoney

local L = ns.L
local money = ns.Money

local module = ns.NewModule("AutoRepair", L.AUTOREPAIR_DESC, {
    enabled = true,
    funds = "guildFirst", -- "guildFirst", "guild", or "own"
    minCost = "0", -- copper; repairs cheaper than this are left alone
    skipKey = "shift",
    chat = true,
})
module.title = L.AUTOREPAIR_TITLE
module.category = "automation"
module.quickToggle = "loot"

-- Hold Shift to Skip was a checkbox, 0.8.4 and before.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    ns.Keys.MigrateShift(saved, "AutoRepair", "shiftSkips", "skipKey")
end)

module.options = {
    {
        key = "funds",
        name = L.AUTOREPAIR_FUNDS,
        description = L.AUTOREPAIR_FUNDS_DESC,
        choices = {
            { "guildFirst", L.AUTOREPAIR_FUNDS_GUILD_FIRST },
            { "guild", L.AUTOREPAIR_FUNDS_GUILD },
            { "own", L.AUTOREPAIR_FUNDS_OWN },
        },
    },
    {
        key = "minCost",
        name = L.AUTOREPAIR_MIN_COST,
        description = L.AUTOREPAIR_MIN_COST_DESC,
        choices = {
            { "0", L.AUTOREPAIR_MIN_COST_ANY },
            { "100", money(100) },
            { "1000", money(1000) },
            { "10000", money(10000) },
        },
    },
    ns.Keys.Option("skipKey", L.SKIP_KEY, L.AUTOREPAIR_KEY_DESC, nil, "0.9.0"),
    ns.ChatOption(L.AUTOREPAIR_CHAT_DESC),
}

-- The server says whether a guild bank repair worked only afterwards: durability updates when it
-- did. When it didn't (not enough in the bank, or over the daily limit), the gear still needs
-- repairing a moment later. That is checked instead of the error message, since any other error
-- shown meanwhile ("Out of range") would look the same.
local WAIT = 2 -- seconds to wait for the guild bank repair before calling it failed
local pending -- the cost of the guild bank repair waiting for an answer
local timer = ns.Frames.Timer(module)
local onDurability

local function stopWaiting()
    pending = nil
    timer:Cancel()
    module:Off("UPDATE_INVENTORY_DURABILITY", onDurability)
    module:Off("MERCHANT_CLOSED", stopWaiting)
end

local function repairOwn(cost)
    if GetMoney() < cost then
        module:Print(format(L.AUTOREPAIR_NO_MONEY, money(cost)))
        return
    end
    RepairAllItems()
    module:Print(format(L.AUTOREPAIR_REPAIRED, money(cost)))
end

function onDurability()
    module:Print(format(L.AUTOREPAIR_REPAIRED_GUILD, money(pending)))
    stopWaiting()
end

-- No durability update came: repaired after all if nothing needs it now, otherwise the guild bank
-- didn't pay. Only while the merchant is still open (closing it stops the wait).
local function checkGuildRepair()
    local cost = pending
    stopWaiting()
    local left, canRepair = GetRepairAllCost()
    if not canRepair or left <= 0 then
        module:Print(format(L.AUTOREPAIR_REPAIRED_GUILD, money(cost)))
    elseif module.db.funds == "guildFirst" then
        repairOwn(left)
    else
        module:Print(format(L.AUTOREPAIR_NO_GUILD_MONEY, money(left)))
    end
end

-- The guild bank can pay: in a guild, allowed to repair with it, and under today's limit
-- (-1 means no limit).
local function guildCanPay(cost)
    if not (IsInGuild() and CanGuildBankRepair()) then
        return false
    end
    local limit = GetGuildBankWithdrawMoney()
    return limit == -1 or limit >= cost
end

local function repairGuild(cost)
    stopWaiting()
    pending = cost
    module:On("UPDATE_INVENTORY_DURABILITY", onDurability)
    module:On("MERCHANT_CLOSED", stopWaiting)
    RepairAllItems(true)
    timer:Start(WAIT, checkGuildRepair)
end

local function onMerchantShow()
    if ns.Keys.IsDown(module.db.skipKey) or not CanMerchantRepair() then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 or cost < (tonumber(module.db.minCost) or 0) then
        return
    end
    local funds = module.db.funds
    if funds ~= "own" and guildCanPay(cost) then
        repairGuild(cost)
    elseif funds == "guild" then
        module:Print(format(L.AUTOREPAIR_NO_GUILD_MONEY, money(cost)))
    else
        repairOwn(cost)
    end
end

-- Turning off drops a guild repair wait: its events and timer stop with the module.
function module:OnEnable()
    self:On("MERCHANT_SHOW", onMerchantShow)
end
