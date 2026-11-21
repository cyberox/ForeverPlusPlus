-- Auto Confirm: answers Yes to the popups an enchant asks before it goes on: "replace the enchant
-- this item has?" and, when asked for, "this will bind the item to you". Leveling Enchanting puts
-- the same enchant on the same bracers over and over, each with that popup.
--
-- Blizzard shows the popup on the same event, before ours runs (Blizzard_Game's
-- GameEvent.HandleReplaceEnchant, registered first), so it's up for an instant and is closed here,
-- as Auto Decline closes a duel's. The popup's own Yes calls the same C_Item function
-- (GameDialogDefs.lua, wow-ui-source's forever branch). **Unverified** in game: whether the client
-- takes that call from an event with no click of the player's behind it.
local _, ns = ...

local C_Item, pcall = C_Item, pcall

local L = ns.L

local module = ns.NewModule("AutoConfirm", L.AUTOCONFIRM_DESC, {
    enabled = false,
    replace = true, -- an enchant replacing the one the item has
    bind = false, -- an enchant that binds the item to you
    tradeBind = false, -- the trade window's warning that an enchant may bind the item
})
module.title = L.AUTOCONFIRM_TITLE
module.category = "automation"
module.notice = ns.Gamepad.LimitedNotice() -- the popup can't be closed for the player then (accept)
module.added = "1.7.0"

module.options = {
    { key = "replace", name = L.AUTOCONFIRM_REPLACE, description = L.AUTOCONFIRM_REPLACE_DESC },
    { key = "bind", name = L.AUTOCONFIRM_BIND, description = L.AUTOCONFIRM_BIND_DESC },
    { key = "tradeBind", name = L.AUTOCONFIRM_TRADEBIND, description = L.AUTOCONFIRM_TRADEBIND_DESC,
        added = "1.9.0" },
}

-- Says yes with the C_Item call the popup's own Yes makes, then closes the popup. A call the
-- client refuses leaves the popup up for the player to answer.
-- With the controller interface on the popup can't be closed from here (ns.ClosePopup), and a Yes
-- pressed on one already answered would answer twice, so it's left to the player whole.
local function accept(call, popup)
    local fn = C_Item and C_Item[call]
    if fn and not ns.Gamepad.On() and pcall(fn) then
        ns.ClosePopup(popup)
    end
end

local function onReplace()
    if module.db.replace then
        accept("ReplaceEnchant", "REPLACE_ENCHANT")
    end
end

-- An enchant cast from the professions window onto the item in its target slot asks with an event,
-- popup, and call of its own (Blizzard_Game's Mainline HandleReplaceTradeskillEnchant, and
-- REPLACE_TRADESKILL_ENCHANT in Blizzard_StaticPopup_Game's Mainline GameDialogDefs.lua).
local function onReplaceCrafted()
    if module.db.replace then
        accept("ReplaceTradeskillEnchant", "REPLACE_TRADESKILL_ENCHANT")
    end
end

-- And so does an enchant cast on the item in the trade window's last slot (Blizzard_Game's Shared
-- HandleTradeReplaceEnchant).
local function onReplaceTraded()
    if module.db.replace then
        accept("ReplaceTradeEnchant", "TRADE_REPLACE_ENCHANT")
    end
end

-- The trade window's warning that the enchant may bind the item. Its Okay makes no call: the popup
-- only holds the Trade button while it's up and gives it back as it hides (TradeFrame.lua's
-- TRADE_POTENTIAL_BIND_ENCHANT, and the popup's OnHide), so closing it is the whole answer. The
-- event comes with false when the game takes the warning down itself.
local function onTradeBind(_, canBind)
    if module.db.tradeBind and ns.IsTrue(canBind) then
        ns.ClosePopup("TRADE_POTENTIAL_BIND_ENCHANT")
    end
end

local function onBind()
    if module.db.bind then
        accept("BindEnchant", "BIND_ENCHANT")
    end
end

function module:IsAvailable()
    return C_Item ~= nil and C_Item.ReplaceEnchant ~= nil
end

function module:OnEnable()
    self:On("REPLACE_ENCHANT", onReplace)
    if ns.HasEvent("REPLACE_TRADESKILL_ENCHANT") then
        self:On("REPLACE_TRADESKILL_ENCHANT", onReplaceCrafted)
    end
    if ns.HasEvent("TRADE_REPLACE_ENCHANT") then
        self:On("TRADE_REPLACE_ENCHANT", onReplaceTraded)
    end
    if ns.HasEvent("TRADE_POTENTIAL_BIND_ENCHANT") then
        self:On("TRADE_POTENTIAL_BIND_ENCHANT", onTradeBind)
    end
    self:On("BIND_ENCHANT", onBind)
end
