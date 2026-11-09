-- Loaded last: every module has registered, so start them once the player is in the world.
local _, ns = ...

---Forever++'s own `ns`, for our companion addons: parts of the addon that ship apart from it
---(ForeverPlusPlus_AgentChat, which only the repository has). One lists Forever++ in its TOC's
---Dependencies, so it loads after this and before PLAYER_LOGIN, and adds its modules and
---libraries to `ns` as Forever++'s own files do. Not for other addons: ForeverPlusPlusAPI is theirs.
---@return table ns
function ForeverPlusPlusCompanion()
    return ns
end

ns.On("PLAYER_LOGIN", function()
    ns.Start()
    ns.RegisterSettings()
    ns.API.Fire("READY") -- other addons can read saved data now
end)
