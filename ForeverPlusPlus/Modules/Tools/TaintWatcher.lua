-- Taint Watcher: finds the values of Blizzard's that an addon wrote. The game remembers which
-- addon's code was running when a value was stored, and Blizzard's own code that reads it later
-- runs as that addon's, so the game blocks what it does next ("Interface action failed because of
-- an AddOn"), often minutes after and far from the cause. This checks the windows that breaks
-- most, twice a second (ns.Taint), and says the first time a value carries an addon's name, so
-- what was done just before is known. `/fpp taint` lists what it found, and each one is an entry
-- in Error Catcher's list too, which is saved, with what was going on then.
--
-- Only Forever++'s own writes by default; Other AddOns notes everyone's. It only asks who wrote a
-- value: nothing of Blizzard's is called, hooked, or written.
local addonName, ns = ...

local format, ipairs, pairs, type, pcall, tostring = string.format, ipairs, pairs, type, pcall, tostring
local rawget, date, _G = rawget, date, _G

local L = ns.L

local module = ns.NewModule("TaintWatcher", L.TAINTWATCHER_DESC, {
    enabled = false,
    chat = true,
    others = false, -- also what other addons wrote
})
module.title = L.TAINTWATCHER_TITLE
module.category = "system"
module.added = "1.9.0"
module.presets = { developer = { enabled = true } }

-- It says when, not what: the check finds a value after it was written.
module.notice = { text = L.TAINTWATCHER_NOTICE, description = L.TAINTWATCHER_NOTICE_DESC }

local EVERY = 0.5 -- seconds between checks
local CHAT_LINES = 3 -- found values said in chat from one check; the rest are counted
local REPORTS = 10 -- entries one check adds to Error Catcher at most, so it can't push the errors out
local LIST_LINES = 30 -- /fpp taint's lines at most

-- The objective tracker's parts (quests, achievements, professions), which aren't globals on
-- every client: the tracker's manager knows them all.
local function trackerParts()
    local manager = _G.ObjectiveTrackerManager
    -- A plain table of the manager's own (Blizzard_ObjectiveTrackerManager.lua, `forever` branch).
    local map = type(manager) == "table" and rawget(manager, "moduleToContainerMap")
    local found = {}
    if type(map) ~= "table" then
        return found
    end
    local count = 0
    for part in pairs(map) do
        if type(part) == "table" then
            count = count + 1
            local ok, name = pcall(part.GetDebugName, part)
            found[ok and ns.IsText(name, true) and name or ("ObjectiveTracker" .. count)] = part
        end
    end
    return found
end

-- The quest log's open quest, which the tracker reads.
local function questDetails()
    local log = _G.QuestMapFrame
    return { ["QuestMapFrame.DetailsFrame"] = type(log) == "table" and log.DetailsFrame or nil }
end

-- What's watched: a global's name and how many tables deep to look, or `tables` for ones that
-- aren't globals. Add to it whenever a bug shows another of Blizzard's values written by an
-- addon. Seen in game: none yet; these are the ones other addons' authors report (the tracker
-- throws in combat once it's an addon's, the quest log and map pass it on, and the window list is
-- read each time a window opens or closes).
local ROOTS = {
    { "ObjectiveTrackerFrame", 2 },
    { tables = trackerParts, [2] = 2 },
    { "QuestMapFrame", 1 },
    { tables = questDetails },
    { "WorldMapFrame", 1 },
    { "UIPanelWindows", 2 },
}

local watcher = ns.Taint.New(ROOTS)
local timer = ns.Frames.Timer(module)
local started -- false until the first check, whose finds were written before watching began

-- Whose values to note: ours, or with Other AddOns, anyone's.
local function only()
    return not module.db.others and addonName or nil
end

local function describe(group)
    local note = group.note
    local path = group.more > 0 and format(L.TAINTWATCHER_MORE, note.path, group.more) or note.path
    return format(L.TAINTWATCHER_LINE, path, note.by or L.TAINTWATCHER_UNKNOWN)
end

local function check()
    local first = #watcher.notes + 1
    if watcher:Check() > 0 then
        local groups = ns.Taint.Groups(watcher.notes, first)
        for i, group in ipairs(groups) do
            local line = describe(group)
            if i <= REPORTS then
                ns.Errors.Report(format(L.TAINTWATCHER_REPORT, line))
            end
            if started and i <= CHAT_LINES then
                module:Print(format(L.TAINTWATCHER_FOUND, line))
            end
        end
        if not started then
            module:Print(format(L.TAINTWATCHER_ALREADY, #groups))
        elseif #groups > CHAT_LINES then
            module:Print(format(L.TAINTWATCHER_FOUND_MORE, #groups - CHAT_LINES))
        end
    end
    started = true
    timer:Start(EVERY, check)
end

-- Starts over: nothing noted, and the next check's finds count as written before it.
local function restart()
    watcher:Reset(only())
    started = false
    timer:Start(EVERY, check)
end

-- /fpp taint, and the List button: what was found this session, oldest first.
local function list()
    local groups = ns.Taint.Groups(watcher.notes)
    if #groups == 0 then
        ns.Print(L.TAINTWATCHER_NONE)
        return
    end
    for i, group in ipairs(groups) do
        if i > LIST_LINES then
            ns.Print(format(L.TAINTWATCHER_FOUND_MORE, #groups - LIST_LINES))
            break
        end
        ns.Print(format(L.TAINTWATCHER_LIST_LINE, tostring(date("%H:%M:%S", group.note.time)), describe(group)))
    end
end

module.options = {
    { key = "others", name = L.TAINTWATCHER_OTHERS, description = L.TAINTWATCHER_OTHERS_DESC },
    ns.ChatOption(L.TAINTWATCHER_CHAT_DESC),
}

module.actions = {
    {
        name = L.TAINTWATCHER_LIST,
        button = L.TAINTWATCHER_LIST_BUTTON,
        description = L.TAINTWATCHER_LIST_DESC,
        fn = list,
    },
}

-- Only on a client that says who wrote a value.
function module:IsAvailable()
    return _G.issecurevariable ~= nil
end

function module:OnOptionChanged(key)
    if key == "others" and self.enabled then
        restart()
    end
end

function module:OnEnable()
    restart()
end

-- Only while the module is on: Core says so otherwise.
ns.AddCommand("taint", "", L.TAINTWATCHER_COMMAND, list, "TaintWatcher")
