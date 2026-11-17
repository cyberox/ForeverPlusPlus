-- Core: modules and parts turning on and off, OnWhile following its option, and a locked module.
local T = ...
local eq = T.eq

local c = T.Core()
local core, fire, registered, heard = c.ns, c.fire, c.registered, c.heard
local m = c.Modules()
local plain, host, check, drop, side, locked = m.plain, m.host, m.check, m.drop, m.side, m.locked
local dropCalls = m.dropCalls

eq(host.defaults.extra, true, "lifecycle: a checkbox part defaults to on")
eq(host.defaults.where, "bottom", "lifecycle: a dropdown part keeps its default")
eq(host.defaults.side, nil, "lifecycle: a dropdown part isn't defaulted to true")

c.Login()

eq(locked.enabled and true or false, false, "lifecycle: a locked module stays off at login")
core.SetEnabled("Locked", true)
eq(m.lockedEnables, 0, "lifecycle: a locked module can't be turned on")

-- PartOn: a dropdown's "off" is off, any other choice on.
for value, want in pairs({ off = false, top = true, [true] = true, [false] = false }) do
    host.db.side = value
    eq(core.PartOn(host, "side"), want, "lifecycle: PartOn " .. tostring(value))
end
host.db.side = nil
eq(core.PartOn(host, "side"), false, "lifecycle: PartOn nil")

-- OnWhile follows its option, and the module.
eq(plain.enabled, true, "lifecycle: module on")
eq(registered("PLAYER_LEVEL_UP"), true, "lifecycle: OnEnable's event")
eq(registered("PLAYER_MONEY"), false, "lifecycle: OnWhile off with its checkbox")
eq(registered("BAG_UPDATE"), true, "lifecycle: OnWhile on with its dropdown")
core.SetOption("Plain", "loud", true)
eq(registered("PLAYER_MONEY"), true, "lifecycle: checkbox on: listened")
fire("PLAYER_MONEY")
eq(heard.money, 1, "lifecycle: OnWhile handler ran")
core.SetOption("Plain", "loud", false)
eq(registered("PLAYER_MONEY"), false, "lifecycle: checkbox off: stopped")
core.SetOption("Plain", "mode", "off")
eq(registered("BAG_UPDATE"), false, "lifecycle: dropdown off: stopped")
core.SetOption("Plain", "mode", "b")
eq(registered("BAG_UPDATE"), true, "lifecycle: dropdown back on: listened")
eq(registered("ZONE_CHANGED"), false, "lifecycle: OnWhile function false")
core.SetOption("Plain", "loud", true)
eq(registered("ZONE_CHANGED"), true, "lifecycle: OnWhile function true")
for _ = 1, 5 do
    core.SetOption("Plain", "loud", true)
end
local n = 0
for _, entry in ipairs(plain.events) do
    n = n + (entry[1] == "PLAYER_MONEY" and 1 or 0)
end
eq(n, 1, "lifecycle: syncing again doesn't pile up events")
core.SetEnabled("Plain", false)
eq(registered("PLAYER_MONEY"), false, "lifecycle: module off: OnWhile stopped")
eq(registered("PLAYER_LEVEL_UP"), false, "lifecycle: module off: its events stopped")
core.SetEnabled("Plain", true)
eq(registered("PLAYER_MONEY"), true, "lifecycle: module back on: saved option listens")
eq(registered("ZONE_CHANGED"), true, "lifecycle: module back on: OnWhile function listens")

-- A checkbox part: on with its checkbox, and its OnWhile follows its own option.
eq(check.enabled, true, "lifecycle: checkbox part on")
core.SetOption("Host", "loud2", true)
eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part option on: listened")
core.SetOption("Host", "extra", false)
eq(check.enabled, false, "lifecycle: checkbox part off")
eq(registered("PLAYER_XP_UPDATE"), false, "lifecycle: part off: OnWhile stopped")
core.SetOption("Host", "extra", true)
eq(registered("PLAYER_XP_UPDATE"), true, "lifecycle: part back on: OnWhile listens")

-- A dropdown part: on for any choice but "off", told when it moves between them.
eq(drop.enabled, true, "lifecycle: dropdown part on at its default")
eq(side.enabled or false, false, "lifecycle: dropdown part without a value is off")
eq(registered("MAIL_SHOW"), true, "lifecycle: dropdown part's OnWhile")
core.SetOption("Host", "where", "top")
eq(drop.enabled, true, "lifecycle: dropdown part stays on between choices")
eq(dropCalls.enable, 1, "lifecycle: not enabled again between choices")
eq(dropCalls.changed[#dropCalls.changed], "where", "lifecycle: told its choice changed")
core.SetOption("Host", "where", "off")
eq(drop.enabled, false, "lifecycle: dropdown part off at \"off\"")
eq(dropCalls.disable, 1, "lifecycle: dropdown part disabled once")
eq(registered("MAIL_SHOW"), false, "lifecycle: dropdown part off: OnWhile stopped")
core.SetOption("Host", "where", "bottom")
eq(drop.enabled, true, "lifecycle: dropdown part back on")
eq(dropCalls.enable, 2, "lifecycle: dropdown part enabled again")
core.SetEnabled("Host", false)
eq(drop.enabled, false, "lifecycle: module off: its parts off")
eq(registered("MAIL_SHOW"), false, "lifecycle: module off: part's OnWhile stopped")
core.SetEnabled("Host", true)
eq(drop.enabled and check.enabled, true, "lifecycle: module on: its parts on")
