-- Core and Lib/Presets.lua: a profile based on a preset, read live under the player's choices.
local T = ...
local eq = T.eq

local c = T.Core()
local core, registered = c.ns, c.registered
local m = c.Modules()
local plain, host, check, coords, locked, tool = m.plain, m.host, m.check, m.coords, m.locked, m.tool
c.Login()
core.Print = function() end
local Profiles = core.Profiles

-- Presets (Lib/Presets.lua): a profile based on one reads, for whatever the player hasn't set,
-- the preset's value (along `extends`) before the module's default, for options and on/off
-- alike, at read time, so what a later release adds to the preset reaches it.
local Presets = core.Presets
Presets.Register("base", { title = "Base" })
Presets.Register("spec", { title = "Spec", extends = "base" })
plain.presets = { base = { enabled = true, options = { mode = "b" } }, spec = { enabled = false } }
host.presets = { spec = { options = { loud2 = true } } }
locked.presets = { spec = { enabled = true } }
tool.presets = { spec = { options = { mode = "b" } } }
coords.presets = { spec = { options = { player = false } } }
core.ApplyPreset()
local defaultSaved = core.db.settings
eq(core.UsePreset("nothing"), false, "presets: one that isn't there does nothing")
c.refreshed = {}
eq(core.UsePreset("spec"), true, "presets: the Defaults popup's preset button")
eq(core.db.preset, "spec", "presets: links the profile in use")
eq(defaultSaved.Plain == nil or next(defaultSaved.Plain) == nil, true,
    "presets: and writes nothing of the preset's into its settings")
eq(plain.db.mode, "b", "presets: an option reads the preset it extends")
eq(plain.db.enabled == false and plain.enabled == false, true,
    "presets: the nearer preset wins: a module it turns off is off, live")
eq(registered("PLAYER_LEVEL_UP"), false, "presets: and its events stop")
eq(host.db.loud2 and registered("PLAYER_XP_UPDATE"), true, "presets: a part's option, and the part hears it")
eq(host.db.extra, true, "presets: what no preset sets reads the default")
eq(not locked.enabled and m.lockedEnables == 0, true, "presets: a locked module stays off")
eq(tool.db.mode, "a", "presets: a tool that's always on is left alone")
eq(coords.db.player, false, "presets: one of Blizzard's settings reads the CVar")
eq(#c.refreshed >= #core.order, true, "presets: every page redraws")

-- The three layers, and resets falling to the preset.
core.SetOption("Plain", "mode", "a")
eq(plain.db.mode, "a", "presets: the player's choice beats the preset")
eq(core.BaseValue(plain, "mode"), "b", "presets: whose value is what a reset gives")
eq(core.BaseValue(host, "extra"), true, "presets: else the default")
core.ResetOption("Plain", "mode")
eq(plain.db.mode .. "," .. tostring(defaultSaved.Plain and defaultSaved.Plain.mode), "b,nil",
    "presets: the undo arrow forgets the choice and the preset's value reads back")
core.SetEnabled("Plain", true)
eq(plain.enabled and defaultSaved.Plain.enabled, true, "presets: turning on a module the preset has off is a choice")
core.SetEnabled("Plain", false)
plain.db.enabled = nil
eq(plain.db.enabled, false, "presets: forgotten, on/off reads the preset again")
host.presets.spec.options.extra = false -- a later release adds to the preset
eq(host.db.extra, false, "presets: what a release adds to the preset reaches the profile")
host.presets.spec.options.extra = nil

-- A preset this version doesn't have (saved by a newer version) reads as none.
core.db.preset = "fromnewer"
eq(plain.db.mode .. "," .. tostring(core.BaseValue(plain, "mode")), "a,a", "presets: an unknown preset is none")
eq(plain.db.enabled, true, "presets: for on/off too")
eq(core.db.preset, "fromnewer", "presets: and stays saved")
core.db.preset = "spec"

-- Recommended Defaults bases the profile on none again.
core.ApplyPreset()
eq(core.db.preset, nil, "presets: plain Defaults drops the link")
eq(plain.enabled and plain.db.mode == "a" and not host.db.loud2, true, "presets: and the defaults read back, live")
eq(registered("PLAYER_XP_UPDATE"), false, "presets: and the part hears that too")

-- Switching live between a profile based on a preset and one on none, and unlinking.
local linked = Profiles.CreateFromPreset("Linked", "spec")
eq(next(core.db.profiles[linked].settings or {}), nil, "presets: a new profile from one has nothing set")
Profiles.Switch(linked)
eq(plain.enabled == false and plain.db.mode == "b" and host.db.loud2, true,
    "presets: switching to it reads the preset, live")
Profiles.Switch("default")
eq(plain.enabled and plain.db.mode == "a" and not host.db.loud2, true,
    "presets: and switching back reads Default's")
Profiles.Switch(linked)
core.SetOption("Host", "extra", false)
eq(Profiles.SetPreset(linked, nil), true, "presets: unlinking the profile in use")
local own = core.db.profiles[linked].settings
eq(core.db.profiles[linked].preset, nil, "presets: unlinked")
eq(plain.enabled == false and plain.db.mode == "b" and host.db.loud2 and not check.enabled, true,
    "presets: it looks the same, live")
eq(tostring(own.Plain.enabled) .. "," .. own.Plain.mode .. "," .. tostring(own.Host.loud2) .. ","
    .. tostring(own.Host.extra), "false,b,true,false", "presets: the preset's values are its own now")
eq(Profiles.SetPreset(linked, "spec"), true, "presets: linking again")
eq(own.Host.extra, false, "presets: keeps the player's choices")
Profiles.Switch("default")
