-- Core and Lib/Plugins.lua: a module another addon adds, through a handle, and the kit it gets.
local T = ...
local eq = T.eq

local c = T.Core()
local core, fire, heard, count = c.ns, c.fire, c.heard, c.count

local Plugins = core.Plugins
local plugin = Plugins.Register("MyAddonThing", "Does a thing.", { size = 20, mode = "a", loud = true,
    seen = {} }, "MyAddon")
local real = core.modules.MyAddonThing
eq(real ~= nil and plugin ~= real and Plugins.Module(plugin) == real, true,
    "plugins: a handle, not Core's module")
eq(real.defaults.enabled, false, "plugins: off unless its defaults say on")
eq(real.notice[1].text:find("MyAddon", 1, true) ~= nil, true, "plugins: its page names the addon")
eq(plugin.name == "MyAddonThing" and plugin.enabled == false and plugin.defaults == nil, true,
    "plugins: a handle reads its name and state, nothing else")
plugin.title, plugin.category = "My Thing", "map"
eq(real.title .. "," .. real.category, "My Thing,map", "plugins: a title and category pass on")
local theirs = {
    { key = "size", name = "Size", min = 10, max = 40, step = 2, cvar = "someCVar", debug = true },
    { key = "mode", name = "Mode", choices = { { "a", "A" }, { "b", "B" } }, requires = "loud" },
    { key = "loud", name = "Loud" },
}
plugin.options = theirs
eq(real.options ~= theirs and real.options[1].min == 10 and real.options[2].choices[2][1] == "b", true,
    "plugins: options are copied")
eq(real.options[1].cvar == nil and real.options[1].debug == nil, true,
    "plugins: a field only our modules use is left out")
local function refused(fn)
    return not pcall(fn)
end
eq(refused(function() plugin.options = { { key = "nope", name = "x" } } end), true,
    "plugins: an option without a default")
eq(refused(function() plugin.options = { { key = "size", name = "x" } } end), true,
    "plugins: a checkbox on a number")
eq(refused(function() plugin.options = { { key = "mode", name = "x", choices = { { "z", "Z" } } } } end), true,
    "plugins: a dropdown whose default isn't a choice")
eq(refused(function() plugin.options = { { key = "loud", name = "x", requires = "gone" } } end), true,
    "plugins: an option that needs one that isn't there")
eq(refused(function() plugin.options = { { key = "enabled", name = "x" } } end), true,
    "plugins: no option for enabled")
eq(#real.options, 3, "plugins: a refused list changes nothing")
eq(refused(function() plugin.locked = true end), true, "plugins: a field outside the contract")
eq(refused(function() plugin.title = 5 end), true, "plugins: a field of the wrong type")
plugin.notice = { text = "Mine." }
eq(#real.notice == 2 and real.notice[2].text == "Mine.", true, "plugins: its notice follows ours")
plugin.actions = { { name = "Do", button = "Go", fn = function() end, key = "x" } }
eq(real.actions[1].button == "Go" and real.actions[1].key == nil, true, "plugins: buttons are copied")
plugin.perCharacter = { seen = true }
eq(real.perCharacter.seen, true, "plugins: data for each character")
eq(refused(function() plugin.perCharacter = { size = true } end), true, "plugins: only data can be per character")
local pluginCalls = {}
function plugin:OnEnable()
    pluginCalls[#pluginCalls + 1] = self == plugin and "enable" or "wrong self"
    self:On("PLAYER_MONEY", count("pluginMoney"))
end
function plugin:OnDisable()
    pluginCalls[#pluginCalls + 1] = "disable"
end
function plugin:OnOptionChanged(key)
    pluginCalls[#pluginCalls + 1] = "changed " .. key
end
eq(refused(function() Plugins.Register("MyAddonThing", "Again.", {}) end), true, "plugins: a name taken")
eq(refused(function() Plugins.Register("not a name", "x", {}) end), true, "plugins: a name that isn't one word")
eq(refused(function() Plugins.Register("NoDefaults", "x") end), true, "plugins: defaults are a table")

-- A plugin seen before whose addon isn't loaded this session keeps its settings.
c.Login({ plugins = { GoneAddonThing = true },
    settings = { GoneAddonThing = { size = 3 }, Removed = { size = 4 } } })
eq(ForeverPlusPlusDB.settings.GoneAddonThing ~= nil and ForeverPlusPlusDB.settings.Removed == nil, true,
    "plugins: an absent plugin's settings stay, a removed module's go")
eq(ForeverPlusPlusDB.plugins.MyAddonThing, true, "plugins: remembered once seen")

eq(plugin.db.size == 20 and #pluginCalls == 0, true, "plugins: settings at login, off by default")
core.SetEnabled("MyAddonThing", true)
eq(pluginCalls[1] == "enable" and plugin.enabled, true, "plugins: OnEnable gets the handle")
fire("PLAYER_MONEY")
eq(heard.pluginMoney, 1, "plugins: its events are heard while it's on")
core.SetOption("MyAddonThing", "size", 30)
eq(pluginCalls[2] == "changed size" and plugin.db.size == 30, true, "plugins: OnOptionChanged")
core.SetEnabled("MyAddonThing", false)
fire("PLAYER_MONEY")
eq(pluginCalls[3] == "disable" and heard.pluginMoney == 1, true, "plugins: off, its events stop")
eq(refused(function() Plugins.Register("TooLate", "x", {}) end), true, "plugins: no module after login")
eq(refused(function() plugin.options = theirs end), true, "plugins: no new options after login")
core.MapTooltip = { Note = function(text) return { text } end, Detail = 1, Pair = 1, Show = 1 }
core.QuestieDB = { IsReady = function() return true end, Reset = function() end }
local kit = Plugins.Kit()
eq(kit == Plugins.Kit() and refused(function() kit.Timer = nil end), true, "plugins: one kit, read only")
eq(kit.Tooltip.Note("x")[1] == "x" and kit.Tooltip.Show == nil, true, "plugins: the kit's tooltip lines")
eq(kit.QuestieDB.IsReady() and kit.QuestieDB.Reset == nil, true, "plugins: only the QuestieDB calls it lists")
eq(refused(function() kit.Timer(plugin) end) and kit.IsNumber(5), true, "plugins: no new timer after login")
