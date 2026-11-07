-- Skip Cinematics: skips the game's in-world cinematics (CinematicFrame) and movies (MovieFrame),
-- either every one or only ones already seen on any character of the account. Hold the Watch Key
-- (Shift by default) as one starts to watch it anyway.
local _, ns = ...

local format, tostring, select = string.format, tostring, select
local StopCinematic = StopCinematic
local C_Map, GetSubZoneText, GetInstanceInfo = C_Map, GetSubZoneText, GetInstanceInfo

local L = ns.L

local module = ns.NewModule("SkipCinematics", L.SKIPCINEMATICS_DESC, {
    enabled = false,
    skip = "seen", -- "seen" or "all"
    watchKey = "shift",
    chat = true,
    printKeys = false,
    -- What has played before, for the whole account: movies by movie ID, cinematics by where they
    -- played ("mapID:subzone"), since a cinematic has no ID. Data, not a setting.
    seen = { movies = {}, cinematics = {} },
})
module.title = L.SKIPCINEMATICS_TITLE
module.category = "automation"
module.quickToggle = "npcs"
module.developer = { enabled = true }

-- Hold Shift to Watch was a checkbox, 0.8.4 and before.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    ns.Keys.MigrateShift(saved, "SkipCinematics", "shiftWatches", "watchKey")
end)

module.options = {
    {
        key = "skip",
        name = L.SKIPCINEMATICS_SKIP,
        description = L.SKIPCINEMATICS_SKIP_DESC,
        choices = {
            { "seen", L.SKIPCINEMATICS_SKIP_SEEN },
            { "all", L.SKIPCINEMATICS_SKIP_ALL },
        },
    },
    ns.Keys.Option("watchKey", L.SKIPCINEMATICS_KEY, L.SKIPCINEMATICS_KEY_DESC, nil, "0.9.0"),
    ns.ChatOption(L.SKIPCINEMATICS_CHAT_DESC),
    {
        key = "printKeys",
        name = L.SKIPCINEMATICS_PRINT,
        description = L.SKIPCINEMATICS_PRINT_DESC,
        debug = true,
        section = L.DEBUG_SECTION_LOGGING,
    },
}

local function forgetSeen()
    module.db.seen = { movies = {}, cinematics = {} }
    ns.Print(L.SKIPCINEMATICS_RESET_DONE)
end

module.actions = {
    {
        name = L.SKIPCINEMATICS_RESET,
        button = L.SKIPCINEMATICS_RESET_BUTTON,
        description = L.SKIPCINEMATICS_RESET_DESC,
        confirm = L.SKIPCINEMATICS_RESET_CONFIRM,
        fn = forgetSeen,
    },
}

-- Where a cinematic plays: the map, or the instance when there is no map, and the subzone.
local function cinematicKey()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then
        map = "i" .. tostring(select(8, GetInstanceInfo()))
    end
    return format("%s:%s", tostring(map), GetSubZoneText() or "")
end

-- Whether to skip one that is starting. One that plays is remembered as seen.
local function shouldSkip(list, key)
    local skip
    if ns.Keys.IsDown(module.db.watchKey) then
        skip = false
    else
        skip = module.db.skip == "all" or list[key] == true
    end
    if module.db.printKeys then
        ns.Print(format(L.SKIPCINEMATICS_PRINT_LINE, tostring(key), tostring(list[key] == true),
            tostring(skip)))
    end
    if not skip then
        list[key] = true
    end
    return skip
end

-- After MovieFrame:PlayMovie. movieID is only set when the movie really started.
local function onPlayMovie(frame, movieID)
    if not movieID or frame.movieID ~= movieID then
        return
    end
    if shouldSkip(module.db.seen.movies, movieID) then
        -- What the skip dialog's confirm button does.
        frame:FinishMovie()
        module:Print(L.SKIPCINEMATICS_SKIPPED_MOVIE)
    end
end

-- After CinematicFrame's own OnEvent has shown the frame. Only cinematics the game lets you
-- cancel: the others are vehicle rides and scenes, where skipping would drop you off a vehicle.
local stopTimer = ns.Frames.Timer(module)
local function onCinematicEvent(_, event, canBeCancelled)
    if event ~= "CINEMATIC_START" or not canBeCancelled then
        return
    end
    if shouldSkip(module.db.seen.cinematics, cinematicKey()) then
        -- A frame later, once the cinematic is under way.
        stopTimer:Start(0, StopCinematic)
        module:Print(L.SKIPCINEMATICS_SKIPPED_CINEMATIC)
    end
end

-- Both frames are part of the always-loaded FrameXML.
function module:OnEnable()
    self:Hook(MovieFrame, "PlayMovie", onPlayMovie)
    self:HookScript(CinematicFrame, "OnEvent", onCinematicEvent)
end
