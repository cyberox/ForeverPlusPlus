-- Taint: which of Blizzard's stored values an addon wrote, noted the first time each is seen.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

T.load("Lib/Secret")
T.load("Lib/Taint")
local Taint = ns.Taint

-- Who wrote what: table -> key -> addon. Anything not listed is the game's own.
local wrote = {}
local function write(tbl, key, by)
    wrote[tbl] = wrote[tbl] or {}
    wrote[tbl][key] = by
end

local frame = { GetObjectType = function() return "Frame" end, inside = 1 }
Tracker = { dirty = true, blocks = { first = 1, second = 2 }, child = frame, list = { 10, 20 } }
Other = { name = "OtherSet", value = 1 }
local hidden = { state = 1 }

local watcher = Taint.New({
    { "Tracker", 2 },
    { "Other", 1 },
    { "Missing", 1 },
    { tables = function() return { Hidden = hidden } end },
}, { context = function() return "windows" end })

eq(watcher:Check(), 0, "taint: no checker on this client, nothing found")

local asked = 0
issecurevariable = function(tbl, key)
    asked = asked + 1
    local by = wrote[tbl] and wrote[tbl][key]
    if by then
        return false, by
    end
    return true
end

game.clock = 100
eq(watcher:Check(), 0, "taint: nothing an addon wrote")
eq(watcher.since, 100, "taint: when watching began")

write(Tracker, "dirty", "SomeAddon")
write(Tracker.blocks, "first", "SomeAddon")
write(Tracker.blocks, "second", "SomeAddon")
write(frame, "inside", "SomeAddon")
write(Other, "value", "ForeverPlusPlus")
write(hidden, "state", "")
game.clock = 130
eq(watcher:Check(), 5, "taint: each value found once, and not inside a frame")
eq(watcher:Check(), 0, "taint: a value found isn't found again")
eq(watcher.since, 100, "taint: watching began at the first check")

local byPath = {}
for _, note in ipairs(watcher.notes) do
    byPath[note.path] = note
end
eq(byPath["Tracker.dirty"].by, "SomeAddon", "taint: the addon that wrote it")
eq(byPath["Tracker.dirty"].time, 130, "taint: the time it was found")
eq(byPath["Tracker.dirty"].context, "windows", "taint: what was going on")
eq(byPath["Tracker.blocks.first"] ~= nil, true, "taint: a table inside is looked into")
eq(byPath["Other.value [OtherSet]"].by, "ForeverPlusPlus", "taint: a table's name follows its path")
eq(byPath["Hidden.state"].by, nil, "taint: a table that isn't a global, written by nobody named")

-- A table whose entries were written at once is one group.
local groups = Taint.Groups(watcher.notes)
local blocks
for _, group in ipairs(groups) do
    if group.note.path:find("^Tracker%.blocks%.") then
        blocks = group
    end
end
eq(#groups, 4, "taint: groups by table, addon, and time")
eq(blocks.more, 1, "taint: a group counts the values beside its first")
eq(#Taint.Groups(watcher.notes, #watcher.notes + 1), 0, "taint: no groups past the last note")

-- Deeper than asked isn't looked at.
Tracker.blocks.deep = { far = 1 }
write(Tracker.blocks.deep, "far", "SomeAddon")
eq(watcher:Check(), 0, "taint: nothing deeper than the root's depth")

-- One addon's only.
watcher:Reset("ForeverPlusPlus")
eq(#watcher.notes, 0, "taint: a reset forgets the notes")
eq(watcher:Check(), 1, "taint: only the named addon's values")
eq(watcher.notes[1].path, "Other.value [OtherSet]", "taint: and it's that addon's")
watcher:Reset()
eq(watcher:Check(), 5, "taint: everyone's again after a reset without a name")
eq(asked > 0, true, "taint: the game was asked")
