-- Blizzard's status tracking bars (experience, reputation): the divider lines over them, which a
-- module can take off its bar. The lines belong to a bar's container, not the bar (Edit Mode's
-- two containers each show one bar at a time), so one place decides for each container: its lines
-- are faded out while the bar it shows is one a module wants solid. Nothing is hooked until a
-- module asks. From Blizzard_StatusTrackingBar (Mainline/StatusTrackingManagerOverrides.lua,
-- Forever build 70938).
local _, ns = ...

local ipairs, pairs, hooksecurefunc = ipairs, pairs, hooksecurefunc

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
