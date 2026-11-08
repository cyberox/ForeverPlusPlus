-- Agent Chat: talk to coding agents (T3 Code's threads) from inside the game, through the Forever
-- Agent program on the same PC (agent/ in this repo). For now it's only the link test:
-- /fpp agent ping <text> sends text to the program and times the reply.
--
-- An addon can't write files or open sockets, so the link uses files the game reads and writes.
-- Out: Lib/AgentLink's frames, as which of 256 helper addons are on for this character, written
-- at once to its AddOns.txt by C_AddOns.SaveAddOns(); the program watches that file. In: the
-- program writes the reply into a load-on-demand helper addon (a slot), and this loads it with
-- C_AddOns.LoadAddOn, which runs its Data.lua: that sets ForeverPlusPlusAgentInbox, read and
-- cleared at once. A slot loads once per UI session. Before loading, this waits for the slot's
-- ready files, which the program creates only once the reply is written (see PROBES). The
-- helpers exist only once the program installs them, so
-- without it the module isn't offered at all.
local _, ns = ...

local _G, ipairs, format, type, tostring, floor, random, wipe = _G, ipairs, format, type, tostring,
    math.floor, math.random, wipe
local tremove = table.remove
local pcall = pcall
local C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound, CreateFrame =
    C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound, CreateFrame

local L = ns.L
local AgentLink = ns.AgentLink

local BIT, SLOT = "FPPAgentBit%03d", "FPPAgentSlot%03d"
local INBOX = "ForeverPlusPlusAgentInbox"
local HOLD = 0.1 -- seconds each frame stays written, so the program reads every one
local PROBE_EVERY = 0.05
local LOAD_AFTER = 1 -- load a slot this long after sending even if neither ready file showed up
local MAX_SLOTS = 999
local MAX_TEXT = 200

local module = ns.NewModule("AgentChat", L.AGENTCHAT_DESC, { enabled = true })
module.title = L.AGENTCHAT_TITLE
module.category = "chat"
module.added = "1.3.0"

-- Only with the program's helper addons installed.
function module:IsAvailable()
    return C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(BIT:format(0))
        and C_AddOns.DoesAddOnExist(SLOT:format(0)) or false
end

local sendTimer = ns.Frames.Timer(module)
local probeTimer = ns.Frames.Timer(module)

local character, session, slots
local seq = 0
local bits = {} -- helper index -> whether it's on, as last written; nil until written
local queue = {} -- frames waiting: { frame = bytes, sent = fn(time) on a message's last frame }
local pending -- the ping waiting for its reply
local pings = 0
local probeString

-- Sending ------------------------------------------------------------------------------------------

-- Writes a frame: only the helpers that change, then the file.
local function apply(frame)
    for i = 0, AgentLink.BITS - 1 do
        local on = AgentLink.Bit(frame, i) == 1
        if bits[i] ~= on then
            if on then
                C_AddOns.EnableAddOn(BIT:format(i), character)
            else
                C_AddOns.DisableAddOn(BIT:format(i), character)
            end
            bits[i] = on
        end
    end
    C_AddOns.SaveAddOns()
end

local function pump()
    local entry = tremove(queue, 1)
    if not entry then
        return
    end
    apply(entry.frame)
    if entry.sent then
        entry.sent(GetTimePreciseSec())
    end
    sendTimer:Start(HOLD, pump)
end

-- Queues a message; `sent` runs when its last frame is written.
local function send(message, sent)
    local frames
    frames, seq = AgentLink.Frames(message, seq)
    for i, frame in ipairs(frames) do
        queue[#queue + 1] = { frame = frame, sent = i == #frames and sent or nil }
    end
    if not sendTimer:IsPending() then
        pump()
    end
end

-- Replies ----------------------------------------------------------------------------------------------

-- The first slot this UI session hasn't loaded.
local function freeSlot()
    for i = 0, slots - 1 do
        local name = SLOT:format(i)
        if not C_AddOns.IsAddOnLoaded(name) and not (pending and pending.name == name) then
            return i, name
        end
    end
end

local function ms(seconds)
    return floor(seconds * 1000 + 0.5)
end

-- Ways to see whether a slot's reply is written, without loading the slot. The game only knows
-- files that existed when it started (it checks those on disk each time, but never finds a name
-- made later), so each slot has fixed ready files the program arms before the game starts.
-- ready.wav and ready.ttf are deleted while the slot is empty and made when it's filled;
-- check.ttf always exists, empty until filled. Which of these the game notices, with game sound
-- on and off, is what the test is for.
local function probeFont()
    if not probeString then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probeString = holder:CreateFontString()
    end
    return probeString
end

local PROBES = {
    { name = "sound made (ready.wav)", check = function(base)
        local willPlay, handle = PlaySoundFile(base .. "ready.wav", "Master")
        if willPlay and handle then
            StopSound(handle)
        end
        return willPlay
    end },
    { name = "font made (ready.ttf)", check = function(base)
        return probeFont():SetFont(base .. "ready.ttf", 12, "")
    end },
    { name = "font filled (check.ttf)", check = function(base)
        return probeFont():SetFont(base .. "check.ttf", 12, "")
    end },
}

local function check(probe, base)
    local ok, ready = pcall(probe.check, base)
    return ok and ready and true or false
end

local function probeText(before, at, sentAt)
    if before then
        return L.AGENTCHAT_PROBE_EARLY
    elseif at then
        return format(L.AGENTCHAT_PROBE_AT, ms(at - sentAt))
    end
    return L.AGENTCHAT_PROBE_NEVER
end

local function finish(p, now)
    pending = nil
    _G[INBOX] = nil
    local loaded, reason = C_AddOns.LoadAddOn(p.name)
    local inbox = _G[INBOX]
    _G[INBOX] = nil
    if not loaded then
        ns.Print(format(L.AGENTCHAT_LOAD_FAILED, p.name, tostring(reason)))
        return
    end
    local done = GetTimePreciseSec()
    if type(inbox) == "table" and inbox.id == p.id and inbox.session == session then
        ns.Print(format(L.AGENTCHAT_PONG, tostring(inbox.text), ms(done - p.start),
            ms(p.sentAt - p.start), ms(now - p.sentAt), ms(done - now)))
    else
        ns.Print(format(L.AGENTCHAT_STALE, p.name, ms(now - p.sentAt)))
    end
    for i, probe in ipairs(PROBES) do
        ns.PrintLine(format(L.AGENTCHAT_PROBE, probe.name, probeText(p.before[i], p.at[i], p.sentAt)))
    end
end

-- Loads the slot once any check that saw nothing before sees its file, or after LOAD_AFTER.
local function probe()
    local p = pending
    if not p then
        return
    end
    local now = GetTimePreciseSec()
    local ready = false
    for i, entry in ipairs(PROBES) do
        if not p.at[i] and check(entry, p.base) then
            p.at[i] = now
        end
        ready = ready or (p.at[i] and not p.before[i])
    end
    if ready or now - p.sentAt >= LOAD_AFTER then
        finish(p, now)
    else
        probeTimer:Start(PROBE_EVERY, probe)
    end
end

local function ping(text)
    if pending then
        ns.Print(L.AGENTCHAT_BUSY)
        return
    end
    local slot, name = freeSlot()
    if not slot then
        ns.Print(L.AGENTCHAT_NO_SLOTS)
        return
    end
    text = text ~= "" and text:sub(1, MAX_TEXT) or "ping"
    pings = pings + 1
    local id = tostring(pings)
    local p = {
        id = id, name = name, start = GetTimePreciseSec(), before = {}, at = {},
        base = format("Interface\\AddOns\\%s\\", name),
    }
    -- A missing file must not read as there; if one does, that check can't tell anything.
    for i, entry in ipairs(PROBES) do
        p.before[i] = check(entry, p.base)
    end
    pending = p
    send(format("P|%s|%d|%s|%s", session, slot, p.id, text), function(at)
        p.sentAt = at
        probe()
    end)
end

local function status()
    local used = 0
    for i = 0, slots - 1 do
        if C_AddOns.IsAddOnLoaded(SLOT:format(i)) then
            used = used + 1
        end
    end
    ns.Print(format(L.AGENTCHAT_STATUS, tostring(character), tostring(session), slots - used, slots, #queue))
end

ns.AddCommand("agent", L.AGENTCHAT_COMMAND_USAGE, L.AGENTCHAT_COMMAND, function(rest)
    local command, argument = rest:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "ping" then
        ping(argument)
    elseif command == "status" or command == "" then
        status()
    else
        ns.Print(format(L.AGENTCHAT_COMMAND_UNKNOWN, command))
    end
end, "AgentChat")

-- Lifecycle ------------------------------------------------------------------------------------------

-- A UI session starts with the idle frame, which tells the program to start reading afresh, and
-- a hello, which has it clear every slot: loaded ones can't load again until a /reload anyway.
function module:OnEnable()
    -- Blizzard's AddOns list names the character by GUID too; a name alone changes nothing.
    character = UnitGUID("player")
    slots = 0
    while slots < MAX_SLOTS and C_AddOns.DoesAddOnExist(SLOT:format(slots)) do
        slots = slots + 1
    end
    session = format("%04x%04x", random(0, 65535), random(0, 65535))
    wipe(bits)
    wipe(queue)
    seq, pending = 0, nil
    queue[1] = { frame = AgentLink.Idle() }
    send(format("H|%s|%d", session, slots))
end

function module:OnDisable()
    pending = nil
    wipe(queue)
end
