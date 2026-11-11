-- Presets: registering, `extends` chains, what a preset says for a module's on/off and options,
-- the flat form ns.ApplyPreset takes, and the popup buttons (a menu once there are too many).
local T = ...
local ns, eq, same, raises = T.ns, T.eq, T.same, T.raises
local Presets = ns.Presets

-- What this version ships: Developer's Defaults alone.
eq(table.concat(Presets.List(), ","), "developer", "presets: the shipped list")
eq(Presets.Title("developer"), "Developer's Defaults", "presets: its title")
eq(Presets.Description("developer") ~= nil, true, "presets: and description")
eq(Presets.Mention(), "Developer's Defaults", "presets: one preset is named in sentences")

-- Registering: names, duplicates, and parents that must come first, so no chain can loop.
raises(function() Presets.Register("Bad Name", { title = "x" }) end, "lowercase key", "presets: a name is a key")
raises(function() Presets.Register("developer", { title = "x" }) end, "already exists", "presets: once each")
raises(function() Presets.Register("untitled", {}) end, "needs a title", "presets: a title")
raises(function() Presets.Register("orphan", { title = "x", extends = "nobody" }) end,
    "isn't registered", "presets: an unknown parent is an error at load")
raises(function() Presets.Register("loop", { title = "x", extends = "loop" }) end,
    "isn't registered", "presets: a preset can't extend itself")
eq(Presets.Exists("orphan") or Presets.Exists("loop"), false, "presets: a refused one isn't there")

-- A three-deep chain: streamer extends quiet extends developer.
eq(Presets.Register("quiet", { title = "Quiet", extends = "developer" }), "quiet", "presets: register")
Presets.Register("streamer", { title = "Streamer", description = "On stream.", extends = "quiet" })
eq(table.concat(Presets.List(), ","), "developer,quiet,streamer", "presets: in the order registered")
same(Presets.Chain("streamer"), { "streamer", "quiet", "developer" }, "presets: a chain, nearest first")
same(Presets.Chain("nothing"), {}, "presets: no chain for one that isn't there")
eq(Presets.Mention(), "a preset", "presets: more than one is \"a preset\"")
eq(Presets.Exists(nil) or Presets.Exists(5), false, "presets: only names exist")

ns.modules = {
    Bags = { name = "Bags", defaults = { enabled = false, size = 1, mode = "a", seen = {}, sound = true },
        options = { { key = "size" }, { key = "mode" }, { key = "sound", cvar = "Sound_Enable" } },
        presets = {
            developer = { enabled = true, options = { size = 4, mode = "b", sound = false, seen = { 1 } } },
            quiet = { enabled = false },
            streamer = { options = { size = 8 } },
        } },
    Chat = { name = "Chat", defaults = { enabled = true, fade = true },
        options = { { key = "fade" } },
        presets = { quiet = { options = { fade = false } }, streamer = { options = { fade = true } } } },
    Plain = { name = "Plain", defaults = { enabled = true, x = 1 }, options = { { key = "x" } } },
    Broken = { name = "Broken", locked = true, defaults = { enabled = false, x = 1 },
        options = { { key = "x" } }, presets = { developer = { enabled = true, options = { x = 2 } } } },
    Tool = { name = "Tool", alwaysOn = true, defaults = { enabled = true, x = 1 },
        options = { { key = "x" } }, presets = { developer = { options = { x = 2 } } } },
    Gone = { name = "Gone", unavailable = true, defaults = { enabled = false, x = 1 },
        options = { { key = "x" } }, presets = { developer = { enabled = true, options = { x = 2 } } } },
}
ns.order = { "Bags", "Chat", "Plain", "Broken", "Tool", "Gone" }

-- On and off, nearest first.
eq(Presets.Enabled("developer", "Bags"), true, "presets: a module the preset turns on")
eq(Presets.Enabled("quiet", "Bags"), false, "presets: one nearer turns it off")
eq(Presets.Enabled("streamer", "Bags"), false, "presets: and the one past it reads the nearer one")
eq(Presets.Enabled("developer", "Chat"), nil, "presets: says nothing about one it doesn't name")
eq(Presets.Enabled("developer", "Plain"), nil, "presets: nor one without presets")
eq(Presets.Enabled("developer", "Broken"), nil, "presets: never turns on a locked module")
eq(Presets.Enabled("developer", "Tool"), nil, "presets: nor speaks for one always on")
eq(Presets.Enabled("developer", "Gone"), nil, "presets: nor one this client doesn't get")
eq(Presets.Enabled("nothing", "Bags"), nil, "presets: a preset that isn't there says nothing")
eq(Presets.Enabled("developer", "Nobody"), nil, "presets: nor about a module that isn't there")

-- Options, nearest first.
eq(Presets.Value("developer", "Bags", "size"), 4, "presets: an option value")
eq(Presets.Value("quiet", "Bags", "size"), 4, "presets: from the parent when the child says nothing")
eq(Presets.Value("streamer", "Bags", "size"), 8, "presets: the nearest wins, three deep")
eq(Presets.Value("streamer", "Bags", "mode"), "b", "presets: from the grandparent")
eq(Presets.Value("quiet", "Chat", "fade"), false, "presets: false is a value, not nothing")
eq(Presets.Value("streamer", "Chat", "fade"), true, "presets: and a child can set it back")
eq(Presets.Value("developer", "Chat", "fade"), nil, "presets: a parent the child overrode")
eq(Presets.Value("streamer", "Bags", "enabled"), false, "presets: enabled reads as Presets.Enabled")
eq(Presets.Value("developer", "Bags", "sound"), nil, "presets: never one of Blizzard's settings")
eq(Presets.Value("developer", "Bags", "seen"), nil, "presets: never data")
eq(Presets.Value("developer", "Bags", "nope"), nil, "presets: nor a setting the module hasn't")
eq(Presets.Value("developer", "Broken", "x"), 2, "presets: a locked module's options are still set")
eq(Presets.Value("developer", "Tool", "x"), nil, "presets: not an always-on tool's")
eq(Presets.Value("developer", "Gone", "x"), nil, "presets: not one this client doesn't get")

-- Everything a preset says, and the flat form ns.ApplyPreset takes.
same(Presets.Resolve("streamer"), {
    Bags = { enabled = false, size = 8, mode = "b" },
    Chat = { fade = true },
    Broken = { x = 2 },
}, "presets: resolved along the chain")
same(Presets.Resolve("nothing"), {}, "presets: nothing for one that isn't there")
local enables, options = Presets.Flat("developer")
same(enables, { "Bags" }, "presets: flat: the modules it turns on, in load order")
same(options, { Bags = { size = 4, mode = "b" }, Broken = { x = 2 } }, "presets: flat: the values it sets")

-- The popup buttons: one each while they fit, else one that opens a menu of them all.
local picked = {}
local function pick(name) picked[#picked + 1] = name end
local buttons = Presets.Buttons(3, pick)
eq(#buttons .. "," .. buttons[1].text .. "," .. buttons[3].text, "3,Developer's Defaults,Streamer",
    "presets: a button each when they fit")
buttons[2].fn()
eq(picked[1], "quiet", "presets: a button picks its preset")
eq(#Presets.Buttons(0, pick), 0, "presets: no room, no buttons")
local menuRoot
MenuUtil = { CreateContextMenu = function(_, generate)
    local items = {}
    menuRoot = { items = items }
    function menuRoot:CreateButton(text, fn)
        items[#items + 1] = { text = text, fn = fn }
        return { SetTooltip = function(_, tip) items[#items].tip = tip end }
    end
    generate(nil, menuRoot)
end }
buttons = Presets.Buttons(2, pick)
eq(#buttons .. "," .. buttons[1].text, "1,Presets...", "presets: too many: one button for a menu")
buttons[1].fn()
eq(#menuRoot.items .. "," .. menuRoot.items[3].text, "3,Streamer", "presets: the menu lists them all")
eq(menuRoot.items[3].tip ~= nil and menuRoot.items[2].tip == nil, true, "presets: with a description's tooltip")
menuRoot.items[3].fn()
eq(picked[2], "streamer", "presets: a menu item picks its preset")
MenuUtil = nil
buttons[1].fn() -- no menu on this client: nothing, and no error
eq(#picked, 2, "presets: without MenuUtil nothing is picked")

-- The Defaults popup as Settings builds it, with these three presets: the menu button, Cancel,
-- and Recommended Defaults (Lib/Confirm.lua's list form, against a stub of Blizzard's popups).
StaticPopupDialogs, CANCEL = {}, "Cancel"
local shown
StaticPopup_Show = function(which) shown = which end
T.load("Lib/Confirm")
buttons = Presets.Buttons(2, pick)
buttons[#buttons + 1] = { text = "Recommended Defaults", fn = function() picked[#picked + 1] = "plain" end }
ns.ConfirmButtons("DEFAULTS_CHOICE", "Reset?", buttons)
local dialog = StaticPopupDialogs.FOREVERPLUSPLUS_DEFAULTS_CHOICE
eq(shown .. "|" .. dialog.button1 .. "|" .. dialog.button2 .. "|" .. dialog.button3 .. "|" .. tostring(dialog.button4),
    "FOREVERPLUSPLUS_DEFAULTS_CHOICE|Presets...|Cancel|Recommended Defaults|nil",
    "presets: too many for the popup: Presets... | Cancel | Recommended Defaults")
dialog.OnAlt()
eq(picked[#picked], "plain", "presets: the button right of Cancel")
raises(function() ns.ConfirmButtons("ONE", "?", { buttons[1] }) end, "two or three", "presets: a popup needs two")
