-- Debug: every module's debug options and buttons, and the testing tools (Self Test, Gear Probe,
-- Screenshots), on its own page in the Settings sidebar while it's on (drawn by Settings/Debug.lua).
-- While it's off the page is gone, those tools' commands are gone, and every debug option is back
-- at its default, so nothing set there goes on working out of sight.
local _, ns = ...

local ipairs, C_Timer = ipairs, C_Timer
local L = ns.L

local module = ns.NewModule("Debug", L.DEBUG_DESC, { enabled = false })
module.title = L.DEBUG
module.category = "tools"
module.added = "1.0.0-beta.1"
module.notice = { text = L.DEBUG_NOTICE, description = L.DEBUG_NOTICE_DESC }

-- Puts every module's debug options back to their defaults.
local function resetDebugOptions()
    for _, name in ipairs(ns.order) do
        local other = ns.modules[name]
        for _, option in ipairs(other.options or {}) do
            if option.debug and other.db then
                local before = other.db[option.key]
                ns.ResetOption(name, option.key) -- forgotten, so none stays saved at its default
                if before ~= other.db[option.key] then
                    ns.RefreshSetting(name)
                end
            end
        end
    end
end

-- Off at login: once every module has loaded its settings, anything a debug option still has on
-- from before goes back to its default.
function module:OnLoad()
    if not self.db.enabled and C_Timer then
        C_Timer.After(0, function()
            if not module.enabled then
                resetDebugOptions()
            end
        end)
    end
end

function module:OnDisable()
    resetDebugOptions()
end
