-- Hide Bag and Menu Bars: Blizzard's bag bar and micro menu out of sight until the mouse is over
-- them, or always. Edit Mode moves and sizes them but has no setting to hide them. Asked for on
-- CurseForge.
--
-- Each bar is faded out rather than hidden, as Hide Stance Bar does: its alpha is nobody else's
-- and can be set at any time, also in combat, when an addon can't hide a frame holding secure
-- buttons. With Show on Mouseover off, its buttons stop taking the mouse, so nothing invisible is
-- clicked or shows a tooltip; that part waits out combat. The bag and menu keys in Key Bindings
-- don't go through the buttons, so they work as before.
--
-- With Show on Mouseover, the buttons keep the mouse and a bar shows while the mouse is over it:
-- a button's OnEnter brings it back, and a timer fades it again once the mouse has left the bar
-- (a button's OnLeave alone would miss the mouse leaving from the gap between two buttons).
-- Both bars show in Edit Mode, where they're moved.
local _, ns = ...

local ipairs = ipairs

local L = ns.L

local module = ns.NewModule("HideMenuBars", L.HIDEMENUBARS_DESC, {
    enabled = false,
    bags = true,
    micro = true,
    mouseover = true,
})
module.title = L.HIDEMENUBARS_TITLE
module.category = "interface"
module.added = "1.7.1"
module.notice = ns.Menus.PadHidesNotice()

module.options = {
    { key = "bags", name = L.HIDEMENUBARS_BAGS, description = L.HIDEMENUBARS_BAGS_DESC },
    { key = "micro", name = L.HIDEMENUBARS_MICRO, description = L.HIDEMENUBARS_MICRO_DESC },
    { key = "mouseover", name = L.HIDEMENUBARS_MOUSEOVER, description = L.HIDEMENUBARS_MOUSEOVER_DESC },
}

local WATCH = 0.2 -- seconds between looks at whether the mouse is still over a shown bar
local DEPTH = 3 -- how deep a bar's buttons sit: Forever's bag buttons are in a cluster in the bar

-- The two bars, by the option that hides each. `buttons` is what takes the mouse in the bar, found
-- the first time it's needed.
local bars = {
    { key = "bags", frame = function() return BagsBar end },
    { key = "micro", frame = function() return MicroMenu end },
}
for _, bar in ipairs(bars) do
    bar.over = false -- whether it shows because the mouse is over it
    bar.mouseOff = false -- whether we turned its buttons' mouse off
    bar.watch = ns.Frames.Timer(module)
end

function module:IsAvailable()
    for _, bar in ipairs(bars) do
        local frame = bar.frame()
        if frame and frame.SetAlpha then
            return true
        end
    end
    return false
end

-- Adds what takes the mouse under `frame` to `list`. Edit Mode's selection box is left out: it
-- has to keep the mouse for the bar to be dragged.
local function collect(frame, skip, list, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= skip then
            if child.IsMouseEnabled and child:IsMouseEnabled() and child.HookScript then
                list[#list + 1] = child
            end
            if depth > 1 then
                collect(child, skip, list, depth - 1)
            end
        end
    end
end

local apply

local function setMouse(bar)
    local want = module.enabled and module.db[bar.key] and not module.db.mouseover
    if want == bar.mouseOff then
        return
    end
    bar.mouseOff = want
    for _, button in ipairs(bar.buttons) do
        button:EnableMouse(not want)
    end
end

function apply(bar)
    local frame = bar.frame()
    if not (frame and bar.buttons) then
        return
    end
    local hide = module.enabled and module.db[bar.key] and not ns.EditMode.IsActive()
        and not (module.db.mouseover and bar.over)
    frame:SetAlpha(hide and 0 or 1)
    ns.AfterCombat(function() setMouse(bar) end)
end

local function applyAll()
    for _, bar in ipairs(bars) do
        apply(bar)
    end
end

-- While a bar shows for the mouse: fades it again once the mouse is off it.
local function check(bar)
    local frame = bar.frame()
    if module.db.mouseover and frame and frame:IsMouseOver() then
        bar.watch:Start(WATCH, function() check(bar) end)
        return
    end
    bar.over = false
    apply(bar)
end

local function onEnter(bar)
    if module.db.mouseover and module.db[bar.key] and not bar.over then
        bar.over = true
        apply(bar)
        bar.watch:Start(WATCH, function() check(bar) end)
    end
end

function module:OnEnable()
    for _, bar in ipairs(bars) do
        local frame = bar.frame()
        if frame and frame.SetAlpha and not bar.buttons then
            bar.buttons = {}
            collect(frame, frame.Selection, bar.buttons, DEPTH)
            for _, button in ipairs(bar.buttons) do
                self:HookScript(button, "OnEnter", function() onEnter(bar) end)
            end
        end
    end
    -- Probe: Edit Mode is Mainline's.
    if EditModeManagerFrame then
        self:HookScript(EditModeManagerFrame, "OnShow", applyAll)
        self:HookScript(EditModeManagerFrame, "OnHide", applyAll)
    end
    applyAll()
end

local function reset()
    for _, bar in ipairs(bars) do
        bar.over = false
        bar.watch:Cancel()
    end
    applyAll()
end

function module:OnDisable()
    reset()
end

function module:OnOptionChanged()
    reset()
end
