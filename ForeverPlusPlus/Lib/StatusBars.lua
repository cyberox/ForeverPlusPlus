-- Blizzard's status tracking bars (experience, reputation): the divider lines over them, which a
-- module can take off its bar. The lines belong to a bar's container, not the bar (Edit Mode's
-- two containers each show one bar at a time), so one place decides for each container: its lines
-- are faded out while the bar it shows is one a module wants solid. Nothing is hooked until a
-- module asks. From Blizzard_StatusTrackingBar (Mainline/StatusTrackingManagerOverrides.lua,
-- Forever build 70938). And a font string of ours over each bar of a kind, for a module that
-- shows its own bar text (see Our text over a bar).
local _, ns = ...

local ipairs, pairs, setmetatable, hooksecurefunc = ipairs, pairs, setmetatable, hooksecurefunc
local CreateFrame = CreateFrame

local L = ns.L

local StatusBars = {}
ns.StatusBars = StatusBars

local wanted = {} -- bar kind ("Experience", "Reputation") -> the module that owns its Solid Bar
local hooked = setmetatable({}, { __mode = "k" }) -- containers and bars already hooked

-- Whether the container shows a bar whose module has Solid Bar on.
local function solid(container)
    local kinds = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not (kinds and container.bars) then
        return false
    end
    for kind, module in pairs(wanted) do
        local bar = kinds[kind] and container.bars[kinds[kind]]
        if bar and bar:IsShown() and module.enabled and module.db.solid then
            return true
        end
    end
    return false
end

local apply

-- At login the lines came back after ours were faded, with nothing of the above run again
-- (in game, 2026-11-16: 19 lines at alpha 1 beside a shown bar with Solid Bar on). So every
-- change is also looked at a frame later and once more when the bar's fade-in is over.
local nextFrame = ns.Frames.Coalesce(function() apply() end)
local settled = ns.Frames.Coalesce(function() apply() end, 1)
local function onChange()
    apply()
    nextFrame()
    settled()
end

local listening

function apply()
    local manager = StatusTrackingBarManager
    if not (manager and manager.barContainers) then
        return
    end
    if not listening then
        listening = true
        -- Blizzard picks and shows the bars here, after the modules have turned on.
        ns.On("PLAYER_ENTERING_WORLD", onChange)
    end
    for _, container in ipairs(manager.barContainers) do
        if not hooked[container] then
            hooked[container] = true
            -- Blizzard lays the lines out again when the bar's width changes.
            hooksecurefunc(container, "UpdateDividers", onChange)
            for _, bar in pairs(container.bars or {}) do
                bar:HookScript("OnShow", onChange)
                bar:HookScript("OnHide", onChange)
            end
        end
        -- Made by UpdateDividers the first time it runs, not in the container's XML.
        local pool = container["HorizontalDividersPool"] ---@type table?
        if pool then
            local alpha = solid(container) and 0 or 1
            for divider in pool:EnumerateActive() do
                divider:SetAlpha(alpha)
            end
        end
    end
end

---Fades each container's divider lines out or back in, for what it shows now. A module calls it
---when it turns on or off and when its Solid Bar option changes.
function StatusBars.Refresh()
    onChange()
end

---Gives a module's bar its Solid Bar option: the bar's divider lines are off while the module is
---on with `module.db.solid` true. The module lists `StatusBars.SolidOption()` in its options and
---calls `StatusBars.Refresh()` as above.
---@param module table
---@param kind string a key of `StatusTrackingBarInfo.BarsEnum`: "Experience" or "Reputation"
function StatusBars.Solid(module, kind)
    wanted[kind] = module
end

-- Our text over a bar ------------------------------------------------------------------------------
-- A module that shows its own text on a bar (XP Bar Text, Reputation Bar Text) hides Blizzard's
-- bar text's frame and shows a font string of ours, in the same font and spot, instead. Each
-- container has its own bar of each kind, so each gets one.

local textsOf = {} -- bar kind -> { bars = the bars found, in order, texts = bar -> our font string }

---Our font string over each container's bar of `kind`, made the first time a bar is found, so
---calling it again makes only what's missing. Nil when the bars can't be found yet (before
---Blizzard_StatusTrackingBar has loaded). The tables are the same on every call: the module hooks
---the bars in `bars`, sets and shows its text in `texts[bar]`, and hides it again with
---`bar.OverlayFrame` shown once it turns off.
---@param kind string a key of `StatusTrackingBarInfo.BarsEnum`: "Experience" or "Reputation"
---@param needs? fun(bar: table): any more a bar must have to get one
---@param made? fun(bar: table) called right after a bar gets its font string
---@return table? bars
---@return table? texts
function StatusBars.Texts(kind, needs, made)
    local manager = StatusTrackingBarManager
    local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        and StatusTrackingBarInfo.BarsEnum[kind]
    if not (manager and manager.barContainers and index) then
        return nil, nil
    end
    local own = textsOf[kind]
    if not own then
        own = { bars = {}, texts = setmetatable({}, { __mode = "k" }) }
        textsOf[kind] = own
    end
    local bars, texts = own.bars, own.texts
    for _, container in ipairs(manager.barContainers) do
        local bar = container.bars and container.bars[index]
        if bar and bar.OverlayFrame and bar.OverlayFrame.Text and not texts[bar]
            and (not needs or needs(bar)) then
            -- Our own frame like Blizzard's OverlayFrame, so that one (holding only Blizzard's
            -- text) can be hidden while ours shows. Hidden, not alpha 0: on Forever something
            -- outside Lua put its alpha back to 1 just after login (2026-10-13).
            local holder = CreateFrame("Frame", nil, bar)
            holder:SetFrameStrata("MEDIUM")
            holder:SetAllPoints(bar.OverlayFrame)
            -- Above the bar's divider lines and border, as Blizzard's text is.
            holder:SetFrameLevel(bar.OverlayFrame:GetFrameLevel() + 1)
            local ours = holder:CreateFontString(nil, "ARTWORK", "TextStatusBarText")
            ours:SetDrawLayer("ARTWORK", 5)
            ours:SetPoint("CENTER", holder, "CENTER", 0, 0)
            ours:Hide()
            texts[bar] = ours
            if made then
                made(bar)
            end
            bars[#bars + 1] = bar
        end
    end
    return bars, texts
end

---The Solid Bar checkbox, for a module's options (its default, `solid = false`, in its defaults).
---@param fields? table more fields for the option, such as `section` and `added`
---@return table option
function StatusBars.SolidOption(fields)
    local option = { key = "solid", name = L.STATUSBARS_SOLID, description = L.STATUSBARS_SOLID_DESC }
    for key, value in pairs(fields or {}) do
        option[key] = value
    end
    return option
end
