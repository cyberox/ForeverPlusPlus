-- Comprehend Scrolls: right-clicking a Mage's scroll in your bags ("Scroll: CHAP BALK WELLES",
-- read with the Comprehension skill) casts Comprehend Scroll on it, instead of casting the spell
-- from the spellbook and then clicking the scroll.
--
-- The scrolls have no use of their own, and a spell's item cursor can only be answered by a
-- hardware click, so each scroll in Blizzard's bags gets a secure overlay (ns.BagClicks) that
-- casts the spell and then targets its bag slot through Blizzard's own `target-bag` and
-- `target-slot` attributes. Not in combat, when the bags work as Blizzard's. A scroll that needs
-- more skill than the player has is still tried, so the game says why it can't be read.
--
-- The known scrolls are a seed (ns.GameData); a scroll a patch adds is found by its "Requires
-- Comprehension (N)" line, read in the client's language, and remembered for the account.
--
-- On by default, but only a Mage gets overlays, so nobody else notices it.
local _, ns = ...

local C_TooltipInfo, C_TradeSkillUI, UnitClass = C_TooltipInfo, C_TradeSkillUI, UnitClass

local L = ns.L

local module = ns.NewModule("ComprehendScrolls", L.COMPREHENDSCROLLS_DESC, {
    enabled = true,
})
module.title = L.COMPREHENDSCROLLS_TITLE
module.category = "automation"
module.added = "0.9.0"
-- The game's rule, not ours, so say it where the player turns it on; a notice with no button.
module.notice = {
    { text = L.COMPREHENDSCROLLS_NOTICE, description = L.COMPREHENDSCROLLS_NOTICE_DESC },
    ns.Gamepad.LimitedNotice(), -- the right click on a scroll in the bags (Lib/BagClicks.lua)
}

-- Comprehend Scroll, in the General tab of a Mage's spellbook (skill line 3012, Comprehension).
-- **[web]** (wago.tools SpellName and SkillLineAbility for 1.60.1.70374)
local COMPREHEND_SCROLL = ns.GameData.Spell(1296017, "Comprehend Scroll")
local COMPREHENSION = 3012

-- The scrolls that need Comprehension, Mage only. The seed is generated from the client's tables
-- (Lib/Generated/ComprehendScrolls.lua); any other bag item whose tooltip says "Requires
-- Comprehension (N)" is learned as one too.
local SCROLLS = ns.GameData.New("comprehendScrolls", ns.TableData and ns.TableData.comprehendScrolls or {},
    { kind = "item", label = "Comprehend Scrolls" })

local skillName -- Comprehension in the client's language, once known
local checked = {} -- itemID -> true once its tooltip was read this session

function module:IsAvailable()
    return ns.BagClicks.IsAvailable()
end

-- Whether this character could read a scroll: a Mage. The class, not whether the game says the
-- spell is known: that answer is Unverified on Forever for a skill line's spell like this one, and
-- a wrong no would leave the scrolls doing nothing. A Mage without the spell is told so by the game.
local function known()
    local _, class = UnitClass("player")
    return class == "MAGE"
end

-- Probe: the skill line's own name, when the client has profession info for it.
local function nameFromSkillLine()
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(COMPREHENSION)
        local name = info and info.professionName
        if ns.IsText(name, true) then
            return name
        end
    end
end

-- Set below; readTooltip refreshes it.
local overlays

-- Reads a bag item's "Requires <skill> (N)" line. A known scroll teaches the skill's name, in case
-- the skill line didn't; with the name, any other item that needs it is learned as a scroll.
local function readTooltip(itemID, bag, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    if not data then
        return -- not loaded yet; tried again next time
    end
    checked[itemID] = true
    local skill = ns.GameData.TooltipRequires(data)
    if not skill then
        return
    end
    if SCROLLS:Get(itemID) then
        -- A scroll's own line is the surest name, over the skill line's.
        if skill ~= skillName then
            skillName = skill
            checked = { [itemID] = true } -- read the rest again, now with the name
            overlays.refresh()
        end
    elseif skill == skillName then
        SCROLLS:Learn(itemID, true)
    end
end

-- Whether the player is a Mage: for anyone else the bags aren't looked through at all.
local knows = false

local function match(itemID, bag, slot)
    if not checked[itemID] then
        skillName = skillName or nameFromSkillLine()
        readTooltip(itemID, bag, slot)
    end
    return SCROLLS:Get(itemID)
end

local function click(overlay, _, bag, slot)
    overlay:SetAttribute("type2", "spell")
    overlay:SetAttribute("spell", COMPREHEND_SCROLL)
    overlay:SetAttribute("target-bag", bag)
    overlay:SetAttribute("target-slot", slot)
    return true
end

overlays = ns.BagClicks.New(module, match, click, function()
    return knows
end)

function module:OnEnable()
    knows = known()
    overlays:Enable()
end

function module:OnDisable()
    overlays:Disable()
end
