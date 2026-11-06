-- Slash: commands a module adds and takes away live, left to another addon that already has the
-- same slash (TomTom's /way), said once after login, and cleared from chat's cache when taken away.
local T = ...
local ns, eq = T.ns, T.eq

SlashCmdList = { TOMTOM_WAY = function() end }
SLASH_TOMTOM_WAY1 = "/way"
local said = {}
ns.Print = function(text) said[#said + 1] = text end
local handlers = {}
ns.On = function(event, fn) handlers[event] = fn end
ns.L.SLASH_TAKEN = "%s belongs to another addon."
T.load("Lib/Slash")
local Slash = ns.Slash
local function ours() end

Slash.Add("FOREVERPLUSPLUS_RL", "/rl", ours)
eq(SlashCmdList.FOREVERPLUSPLUS_RL == ours and SLASH_FOREVERPLUSPLUS_RL1, "/rl", "slash: a free command is added")
Slash.Add("FOREVERPLUSPLUS_WAY", "/WAY", ours)
eq(SlashCmdList.FOREVERPLUSPLUS_WAY, nil, "slash: one another addon has is left to it, any case")
eq(#said, 0, "slash: not said before login")
handlers.PLAYER_ENTERING_WORLD()
Slash.Add("FOREVERPLUSPLUS_WAY", "/way", ours)
Slash.Add("FOREVERPLUSPLUS_WAY", "/way", ours)
eq(said[1], "/way belongs to another addon.", "slash: after login the player is told")
eq(#said, 1, "slash: once")

-- Chat's cache of typed commands counts as taken, and is cleared when ours goes.
hash_SlashCmdList = { ["/CLEAR"] = function() end }
Slash.Add("FOREVERPLUSPLUS_CLEAR", "/clear", ours)
eq(SlashCmdList.FOREVERPLUSPLUS_CLEAR, nil, "slash: one in chat's cache is taken")
hash_SlashCmdList["/RL"] = ours
Slash.Remove("FOREVERPLUSPLUS_RL", "/rl")
eq(SlashCmdList.FOREVERPLUSPLUS_RL == nil and SLASH_FOREVERPLUSPLUS_RL1 == nil, true, "slash: taken away")
eq(hash_SlashCmdList["/RL"], nil, "slash: and out of chat's cache")
Slash.Remove("FOREVERPLUSPLUS_WAY", "/way")
eq(type(SlashCmdList.TOMTOM_WAY), "function", "slash: removing one we never added leaves the other addon's")
Slash.Add("FOREVERPLUSPLUS_RL", "/rl", ours)
eq(SlashCmdList.FOREVERPLUSPLUS_RL, ours, "slash: added again after it was taken away")
