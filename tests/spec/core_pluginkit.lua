-- Lib/Plugins.lua: what a plugin's module shares with ours beyond the basics in core_plugins. Its
-- quick toggle group, renamed settings, unit events, item tooltip lines, the options every module
-- fills alike, sounds and keys, a map layer's filter menu entry, marks on items, and a frame in
-- Edit Mode. The libraries behind them
-- draw on Blizzard's frames, so they're stand-ins here: what's checked is what a plugin may ask
-- for, and that it stops with its module.
local T = ...
local eq = T.eq

-- The bags' links the marks walk, and the keys, which Lib/Keys.lua keeps at load.
local links = { [1] = "item:1", [2] = "item:2" }
C_Container = { GetContainerItemLink = function(_, slot) return links[slot] end }
local shiftDown = false
IsShiftKeyDown = function() return shiftDown end
IsControlKeyDown = function() return false end
IsAltKeyDown = function() return false end

local c = T.Core()
local core, fire = c.ns, c.fire
T.load("Lib/Sounds", core)
T.load("Lib/Keys", core)

local function refused(fn)
    return not pcall(fn)
end

-- Stand-ins --------------------------------------------------------------------------------------

local played = {}
PlaySound = function(id) played[#played + 1] = id end
SOUNDKIT = { RAID_WARNING = 8959 }

local tooltipFns, tooltipLines = { OnInfo = {}, OnPrices = {} }, {}
core.ItemTooltip = {
    OnInfo = function(fn) tooltipFns.OnInfo[#tooltipFns.OnInfo + 1] = fn end,
    OnPrices = function(fn) tooltipFns.OnPrices[#tooltipFns.OnPrices + 1] = fn end,
    AddInfo = function(_, ...) tooltipLines[#tooltipLines + 1] = { ... } end,
    AddPrice = function(_, _, ...) tooltipLines[#tooltipLines + 1] = { ... } end,
    ItemID = function(data) return data.id end,
}

-- A map layer that counts, and the filter menu's two calls kept to run by hand.
local layer = { on = false, refreshes = 0 }
function layer:Enable() self.on = true end
function layer:Disable() self.on = false end
function layer:Refresh() self.refreshes = self.refreshes + 1 end
local filter = {}
core.MapPins = {
    New = function() return layer end,
    SizeOption = function(key) return { key = key, name = "Icon Size", min = 50, max = 200, step = 10,
        format = "%d%%", cvar = "nope" } end,
}
core.WorldMap = {
    AddFilter = function(order, shown, build) filter.order, filter.shown, filter.build = order, shown, build end,
    FilterLayer = function(_, name, get, set, kinds)
        filter.name, filter.get, filter.set, filter.kinds = name, get, set, kinds
    end,
}

-- Item buttons: the real walk over every place (ItemButtons.Walk), with one bag window of two
-- slots for it to find and overlays that remember what shows.
local shown, placed = {}, {}
local iconOne, iconTwo = {}, {}
T.load("Lib/ItemButtons", core)
for name, fn in pairs({
    Overlays = function()
        return {
            Set = function(_, icon, on)
                shown[icon] = on and true or nil
                return on and {} or nil
            end,
            HideAll = function() shown = {} end,
        }
    end,
    PlaceMark = function(_, icon, how) placed[icon] = how end,
    EachBagButton = function(_, fn)
        fn(nil, iconOne, 0, 1)
        fn(nil, iconTwo, 0, 2)
    end,
    EachOpenBag = function(update) update({}) end,
    EachBankButton = function() end,
    EachMerchantItem = function() end,
    EachAuctionRow = function() end,
    EachRoll = function() end,
    EachLootSlot = function() end,
    MerchantShown = function() return false end,
    HookBags = function() end,
    HookBank = function() end,
    HookMerchant = function() end,
    HookLoot = function() end,
    HookRolls = function() end,
    HookAuction = function() end,
    CancelAuction = function() end,
    CornerOption = function(description) return { key = "corner", name = "Corner", description = description,
        choices = { { "TOPLEFT", "Top Left" }, { "TOPRIGHT", "Top Right" } } } end,
}) do
    core.ItemButtons[name] = fn
end

local editFrames = {}
core.EditMode = {
    RegisterModule = function(_, frame, label, apply) editFrames[frame] = { label = label, apply = apply } end,
    Unregister = function(frame) editFrames[frame] = nil end,
    Place = function(frame, x, y) frame.at = x .. "," .. y end,
    IsActive = function() return true end,
}

-- A plugin -----------------------------------------------------------------------------------------

local Plugins = core.Plugins
local kit = Plugins.Kit()
local plugin = Plugins.Register("MyThing", "Does a thing.", {
    size = 20, loud = true, sound = "raidwarning", key = "shift", chat = true, show = true, rare = true,
    corner = "TOPRIGHT", bags = true, x = 0, y = 100, scale = 100, mapSize = 100, seen = {},
}, "MyAddon")
local real = core.modules.MyThing

-- Its place in the Minimap Button's quick toggles.
plugin.quickToggle = "loot"
eq(real.quickToggle, "loot", "kit: a quick toggle group")
eq(refused(function() plugin.quickToggle = "nope" end), true, "kit: a quick toggle group that isn't one")

-- Renamed settings and module names.
eq(refused(function() plugin.oldKeys = { nope = "bigness" } end), true, "kit: an old key for no default")
eq(refused(function() plugin.oldKeys = { size = "loud" } end), true, "kit: an old key that is still a default")
eq(refused(function() plugin.oldKeys = { enabled = "on" } end), true, "kit: no old key for enabled")
eq(refused(function() plugin.oldNames = { "not a name" } end), true, "kit: an old name that isn't one word")
eq(refused(function() plugin.oldNames = { "MyThing" } end), true, "kit: its own name as an old one")
plugin.oldKeys = { size = "bigness", seen = "found", sound = "noise" }
plugin.oldNames = { "OldThing", "Taken" }
local taken = core.NewModule("Taken", "A module of ours.", { enabled = false, size = 1 })

-- The options every module fills alike: copies, never our tables.
local sound = kit.Options.Sound("sound", "The sound it plays.", "loud")
eq(sound.key == "sound" and sound.requires == "loud" and sound.name == core.L.SOUND_NAME, true,
    "kit: the Sound option")
eq(sound.choices[1][1] ~= "off" and #sound.choices == #core.Sounds.CHOICES - 1, true,
    "kit: under a checkbox, the Sound option has no Off")
local plainSound = kit.Options.Sound("sound", "x")
eq(plainSound.choices ~= core.Sounds.CHOICES and plainSound.choices[1] ~= core.Sounds.CHOICES[1]
    and plainSound.choices[1][1] == "off", true, "kit: its choices are a copy")
local key = kit.Options.Key("key", "Skip Key", "Hold it to skip.")
eq(key.choices[1][1] == "shift" and key.choices ~= core.Keys.CHOICES, true, "kit: the Key option")
eq(kit.Options.Chat("What it says.").key, "chat", "kit: the Chat Messages option")
eq(kit.Options.MapIconSize("mapSize").cvar, nil, "kit: a builder's option has only what a plugin may set")
eq(kit.Options.MarkCorner("Where the mark sits.").choices[2][1], "TOPRIGHT", "kit: the Corner option")
eq(refused(function() kit.Options.Sound("sound") end), true, "kit: a builder missing its text")
eq(refused(function() kit.Options.MarkPlace("pocket", "x") end), true, "kit: a place marks don't go")
eq(refused(function() kit.Options.Nope = 1 end), true, "kit: the builders are read only")
plugin.options = {
    { key = "loud", name = "Loud" }, sound, key, kit.Options.Chat("What it says."),
    kit.Options.MapIconSize("mapSize"),
    { key = "scale", name = "Size", min = 50, max = 200, step = 10, editMode = true },
}
eq(#real.options == 6 and real.options[2].choices[1][1] == "buzz" and real.options[6].editMode, true,
    "kit: built options and an Edit Mode option pass")

-- A map layer with a filter menu entry.
eq(refused(function() kit.NewMapLayer(function() end, plugin, { name = "Things", key = "size" }) end), true,
    "kit: a filter on a setting that isn't true or false")
eq(refused(function() kit.NewMapLayer(function() end, plugin, { key = "show" }) end), true,
    "kit: a filter without a name")
eq(refused(function()
    kit.NewMapLayer(function() end, plugin, { name = "Things", key = "show", kinds = { { name = "x" } } })
end), true, "kit: a kind without a setting")
local mapLayer = kit.NewMapLayer(function() end, plugin,
    { name = "Things", key = "show", kinds = { { name = "Rare", key = "rare" } } })
eq(filter.order >= 100, true, "kit: a plugin's filter entry comes after ours")

-- Marks on items.
eq(refused(function() kit.NewItemMarks(function() end, plugin, {}) end), true, "kit: marks without art")
eq(refused(function() kit.NewItemMarks(function() end, plugin, { atlas = "a", color = { 1 } }) end), true,
    "kit: marks with half a color")
eq(refused(function() kit.NewItemMarks(nil, plugin, { atlas = "a" }) end), true, "kit: marks without a test")
local tested = {}
local wanted = { ["item:1"] = true }
local marks = kit.NewItemMarks(function(link, place)
    tested[#tested + 1] = link .. "@" .. place
    return wanted[link]
end, plugin, { atlas = "checkmark" })
local broken = kit.NewItemMarks(function() error("the plugin's mistake") end, plugin, { texture = 134400 })

-- Login --------------------------------------------------------------------------------------------

local changed = {}
function plugin:OnOptionChanged(name) changed[#changed + 1] = name end
local heard = {}
local frame = { SetPoint = function() end, IsProtected = function() return false end }
local addInfo = function(tooltip, data)
    kit.ItemTooltip.AddInfo(tooltip, "Mine", kit.ItemTooltip.ItemID(data), "gold")
end
function plugin:OnEnable()
    heard.unit = self:OnUnit("UNIT_HEALTH", { "player" }, function(_, unit) heard[#heard + 1] = unit end)
    self:OnItemInfo(addInfo)
    self:OnItemInfo(addInfo)
    heard.layer = mapLayer:Enable()
    heard.marks = marks:Enable()
    broken:Enable()
    heard.edit = kit.EditMode.Register(self, frame, "My Frame", function() heard.applied = true end)
end

eq(plugin:OnUnit("UNIT_HEALTH", { "player" }, function() end), false, "kit: no unit event before it's on")
c.Login({
    plugins = { OldThing = true },
    settings = {
        OldThing = { bigness = 30, loud = false, noise = 5, enabled = true },
        Taken = { size = 9 }, Removed = { size = 4 },
    },
    data = { OldThing = { found = { a = 1 } } },
    profiles = { p1 = { name = "Raid", settings = { OldThing = { bigness = "huge" } } } },
})
local saved = ForeverPlusPlusDB
eq(plugin.db.size == 30 and plugin.db.loud == false and plugin.db.seen.a == 1, true,
    "kit: settings and data follow a renamed module and renamed keys")
eq(saved.settings.OldThing == nil and saved.settings.MyThing.bigness == nil, true,
    "kit: nothing is left under the old names")
eq(plugin.db.sound, "raidwarning", "kit: a value of another type isn't moved")
eq(saved.profiles.p1.settings.MyThing == nil or saved.profiles.p1.settings.MyThing.size == nil, true,
    "kit: nor in another profile")
eq(taken.db.size, 9, "kit: an old name can't take a loaded module's settings")
eq(refused(function() plugin.oldKeys = { size = "other" } end), true, "kit: no old keys after login")

-- Unit events.
eq(plugin.enabled and heard.unit, true, "kit: a unit event while it's on")
fire("UNIT_HEALTH", "player")
fire("UNIT_HEALTH", "target")
eq(#heard == 1 and heard[1] == "player", true, "kit: only its units are heard")
eq(refused(function() plugin:OnUnit("UNIT_HEALTH", "player", function() end) end), true,
    "kit: units are a list")
eq(refused(function() plugin:OnUnit("UNIT_HEALTH", { "a", "b", "c" }, function() end) end), true,
    "kit: two units at most")

-- Item tooltip lines.
eq(#tooltipFns.OnInfo == 2 and tooltipFns.OnInfo[1] == tooltipFns.OnInfo[2], true,
    "kit: asking twice gives the tooltip the same function")
tooltipFns.OnInfo[1]({}, { id = 77 })
eq(#tooltipLines == 1 and tooltipLines[1][1] == "Mine" and tooltipLines[1][2] == "77"
    and tooltipLines[1][3] == "right" and tooltipLines[1][4] == "gold", true, "kit: a line in our style")
eq(refused(function() kit.ItemTooltip.AddInfo({}, "Mine", "x", "pink") end), true, "kit: a color that isn't one")
eq(refused(function() kit.ItemTooltip.AddInfo({}, "Mine", "x", nil, "left") end), true, "kit: an align that isn't one")
eq(refused(function() kit.ItemTooltip.AddPrice({}, {}, "Mine", -5) end), true, "kit: a price below nothing")
kit.ItemTooltip.AddPrice({}, {}, "Worth", 250, "inline")
eq(tooltipLines[2][1] == "Worth" and tooltipLines[2][2] == 250 and tooltipLines[2][4] == "inline", true,
    "kit: a price line")

-- Sounds and keys.
kit.PlaySound(plugin.db.sound)
eq(played[1], 8959, "kit: the sound picked plays")
shiftDown = true
eq(kit.IsKeyDown(plugin.db.key) and not kit.IsKeyDown("none") and not kit.IsKeyDown(5), true,
    "kit: whether the key picked is held")

-- The map layer's filter.
eq(heard.layer and layer.on and filter.shown(), true, "kit: the layer shows while its setting is on")
filter.build({})
eq(filter.name == "Things" and filter.get() == true and #filter.kinds == 1, true, "kit: its filter menu entry")
filter.set(false)
eq(layer.on == false and plugin.db.show == false and changed[#changed] == "show", true,
    "kit: unchecked, the layer comes off and the plugin hears of it")
eq(mapLayer:Enable(), false, "kit: enabling it again leaves it off while the setting is")
filter.set(true)
eq(layer.on, true, "kit: checked, it shows again")
filter.kinds[1].set(false)
eq(plugin.db.rare == false and layer.refreshes == 1 and changed[#changed] == "rare", true,
    "kit: a kind is a setting, and redraws the layer")

-- Marks on items.
eq(heard.marks and shown[iconOne] == true and shown[iconTwo] == nil, true, "kit: marks where the test says")
eq(tested[1], "item:1@bags", "kit: the test gets the item and the place")
eq(placed[iconOne].size == 30 and placed[iconOne].corner == "TOPRIGHT" and placed[iconOne].padding == 1, true,
    "kit: placed by the module's settings, and ours for one it lacks")
wanted["item:2"] = true
marks:Refresh()
eq(shown[iconTwo], true, "kit: a refresh asks again")
core.SetOption("MyThing", "bags", false)
marks:Refresh()
eq(shown[iconOne] == nil and shown[iconTwo] == nil, true, "kit: none in a place the player turned off")
core.SetOption("MyThing", "bags", true)
marks:Refresh()

-- A frame in Edit Mode.
eq(heard.edit and editFrames[frame].label == "My Frame", true, "kit: a frame in Edit Mode")
editFrames[frame].apply()
eq(heard.applied, true, "kit: apply puts it where the settings say")
kit.EditMode.Place(frame, 10, 20)
eq(frame.at == "10,20" and kit.EditMode.IsActive(), true, "kit: placing a frame")
eq(refused(function()
    kit.EditMode.Register(plugin, { SetPoint = function() end, IsProtected = function() return true end },
        "x", function() end)
end), true, "kit: no protected frame in Edit Mode")
eq(refused(function() kit.EditMode.Register(plugin, {}, "x", function() end) end), true,
    "kit: Edit Mode takes a frame")
local bare = Plugins.Module(plugin) and core.modules.Taken
eq(refused(function() kit.EditMode.Register(bare, frame, "x", function() end) end), true,
    "kit: Edit Mode takes a plugin's module")

-- Off: everything it put up comes down, and nothing starts.
core.SetEnabled("MyThing", false)
eq(layer.on == false and next(shown) == nil and editFrames[frame] == nil, true,
    "kit: off, its layer, marks, and Edit Mode box go")
fire("UNIT_HEALTH", "player")
eq(#heard, 1, "kit: off, its unit events stop")
tooltipFns.OnInfo[1]({}, { id = 1 })
eq(#tooltipLines, 2, "kit: off, its tooltip lines stop")
eq(mapLayer:Enable() or marks:Enable() or kit.EditMode.Register(plugin, frame, "x", function() end), false,
    "kit: nothing starts while it's off")
eq(refused(function() kit.NewItemMarks(function() end, plugin, { atlas = "a" }) end), true,
    "kit: no new marks after login")
eq(refused(function() marks.Enable() end), true, "kit: marks are called with a colon")
