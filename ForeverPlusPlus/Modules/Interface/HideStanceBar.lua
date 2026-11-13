-- Hide Stance Bar: Blizzard's stance bar (stances, forms, auras, stealth) out of sight, for players
-- who use keys or their own action buttons for them. Edit Mode has no setting to hide it.
--
-- It's faded out rather than hidden: Blizzard shows the bar again by itself (StanceBarMixin:Update,
-- ActionBarController's ValidateActionBarTransition), also in combat, when an addon can't hide a
-- secure frame, while its alpha is nobody else's and can be set at any time. Its buttons stop
-- taking the mouse, so nothing invisible is clicked or shows a tooltip; that part waits out combat.
-- The stance keys in Key Bindings don't go through the buttons, so they work as before.
local _, ns = ...

local pairs = pairs

local L = ns.L

local module = ns.NewModule("HideStanceBar", L.HIDESTANCEBAR_DESC, {
    enabled = false,
})
module.title = L.HIDESTANCEBAR_TITLE
module.category = "interface"
module.added = "1.6.0"

function module:IsAvailable()
    return StanceBar and StanceBar.SetAlpha and true or false
end

local mouseOff = false -- whether we turned the buttons' mouse off

local function setMouse()
    local want = module.enabled
    if want == mouseOff then
        return
    end
    mouseOff = want
    for _, button in pairs(StanceBar.actionButtons or {}) do
        if button.EnableMouse then
            button:EnableMouse(not want)
        end
    end
end

local function apply()
    StanceBar:SetAlpha(module.enabled and 0 or 1)
    ns.AfterCombat(setMouse)
end

function module:OnEnable()
    -- Each can bring the bar back as Blizzard draws it.
    self:HookScript(StanceBar, "OnShow", apply)
    self:Hook(StanceBar, "Update", apply)
    apply()
end

function module:OnDisable()
    apply()
end
