-- Loaded last: every module has registered, so start them once the player is in the world.
local _, ns = ...

ns.On("PLAYER_LOGIN", function()
    ns.Start()
    ns.RegisterSettings()
    ns.API.Fire("READY") -- other addons can read saved data now
end)
