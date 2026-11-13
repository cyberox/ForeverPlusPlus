-- Hide Stance Bar: Blizzard's stance bar (stances, forms, auras, stealth) out of sight, for players
-- who use keys or their own action buttons for them. Edit Mode has no setting to hide it.
--
-- It's faded out rather than hidden: Blizzard shows the bar again by itself (StanceBarMixin:Update,
-- ActionBarController's ValidateActionBarTransition), also in combat, when an addon can't hide a
-- secure frame, while its alpha is nobody else's and can be set at any time. Its buttons stop
-- taking the mouse, so nothing invisible is clicked or shows a tooltip; that part waits out combat.
-- The stance keys in Key Bindings don't go through the buttons, so they work as before.
--
-- With Show on Mouseover, the buttons keep the mouse and the bar shows while the mouse is over it:
-- a button's OnEnter brings it back, and a timer fades it again once the mouse has left the bar
-- (a button's OnLeave alone would miss the mouse leaving from the gap between two buttons).
local _, ns = ...

local pairs = pairs

local L = ns.L

local module = ns.NewModule("HideStanceBar", L.HIDESTANCEBAR_DESC, {
    enabled = false,
    mouseover = false,
})
module.title = L.HIDESTANCEBAR_TITLE
module.category = "interface"
module.added = "1.6.0"

module.options = {
    { key = "mouseover", name = L.HIDESTANCEBAR_MOUSEOVER, description = L.HIDESTANCEBAR_MOUSEOVER_DESC },
}

function module:IsAvailable()
    return StanceBar and StanceBar.SetAlpha and true or false
end

local WATCH = 0.2 -- seconds between looks at whether the mouse is still over the shown bar

local mouseOff = false -- whether we turned the buttons' mouse off
local over = false -- whether the bar shows because the mouse is over it
local watch = ns.Frames.Timer(module)
local hooked = setmetatable({}, { __mode = "k" }) -- the buttons whose OnEnter is hooked

local function setMouse()
    local want = module.enabled and not module.db.mouseover
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
    local hide = module.enabled and not (module.db.mouseover and over)
    StanceBar:SetAlpha(hide and 0 or 1)
    ns.AfterCombat(setMouse)
end

-- While the bar shows for the mouse: fades it again once the mouse is off it.
local function check()
    if module.db.mouseover and StanceBar:IsMouseOver() then
        watch:Start(WATCH, check)
        return
    end
    over = false
    apply()
end

local function onEnter()
    if module.db.mouseover and not over then
        over = true
        apply()
        watch:Start(WATCH, check)
    end
end

local function hookButtons()
    for _, button in pairs(StanceBar.actionButtons or {}) do
        if not hooked[button] and button.HookScript then
            hooked[button] = true
            module:HookScript(button, "OnEnter", onEnter)
        end
    end
end

function module:OnEnable()
    -- Each can bring the bar back as Blizzard draws it.
    self:HookScript(StanceBar, "OnShow", apply)
    self:Hook(StanceBar, "Update", apply)
    hookButtons()
    apply()
end

function module:OnDisable()
    over = false
    apply()
end

function module:OnOptionChanged()
    over = false
    watch:Cancel()
    apply()
end
