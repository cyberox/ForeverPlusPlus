-- Agent Chat: talk to coding agents (T3 Code's threads) from inside the game, through the Forever
-- Agent program on the same PC (agent/ in this repo). For now it's only the link test:
-- /fpp agent ping <text> sends text to the program and times the reply.
--
-- An addon can't write files or open sockets, so the link uses files the game reads and writes.
-- Out: Lib/AgentLink's frames, as which of 256 helper addons are on for this character, written
-- at once to its AddOns.txt by C_AddOns.SaveAddOns(); the program watches that file. In: the
-- program writes the reply into a load-on-demand helper addon (a slot), and this loads it with
-- C_AddOns.LoadAddOn, which runs its Data.lua: that sets ForeverPlusPlusAgentInbox, read and
-- cleared at once. A slot loads once per UI session.
--
-- A signal says the reply is written, so the slot loads only then: a sound file in the
-- FPPAgentSignals helper, which the program makes after the reply. PlaySoundFile answers whether
-- it's there, with game sound off too. The game knows only files that existed when it started
-- (the program makes them all while it's closed, and deletes them at each hello), and once it
-- has found one it remembers it until it restarts, so each signal works once per game launch.
-- Requests take the next one that reads as missing, from where the last left off (saved, so a
-- /reload goes on from there). With none, or no program, a slot loads after LOAD_AFTER anyway.
-- The helpers exist only once the program installs them, so without it the module isn't
-- offered at all. What the tests showed is in docs/forever-api.md.
local _, ns = ...

local _G, ipairs, format, type, tostring, tonumber, floor, random, wipe = _G, ipairs, format, type,
    tostring, tonumber, math.floor, math.random, wipe
local tremove, min = table.remove, math.min
local C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound =
    C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound

local L = ns.L
local AgentLink = ns.AgentLink

local BIT, SLOT, SIGNALS = "FPPAgentBit%03d", "FPPAgentSlot%03d", "FPPAgentSignals"
local SIGNAL = "Interface\\AddOns\\FPPAgentSignals\\%04d.wav"
local INBOX = "ForeverPlusPlusAgentInbox"
local HOLD = 0.1 -- seconds each frame stays written, so the program reads every one
local PROBE_EVERY = 0.05
local LOAD_AFTER = 1 -- load a slot this long after sending when there's no signal to wait for
local MAX_SLOTS = 999
local MAX_SCAN = 200 -- signals checked per request before giving up on one
local MAX_TEXT = 200

local module = ns.NewModule("AgentChat", L.AGENTCHAT_DESC, {
    enabled = true,
    link = {}, -- signal: the next ready signal to try
})
module.title = L.AGENTCHAT_TITLE
module.category = "chat"
module.added = "1.3.0"

-- Only with the program's helper addons installed.
function module:IsAvailable()
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    return exists and exists(BIT:format(0)) and exists(SLOT:format(0)) and exists(SIGNALS) or false
end

local sendTimer = ns.Frames.Timer(module)
local probeTimer = ns.Frames.Timer(module)

local character, session, slots, signals
local seq = 0
local bits = {} -- helper index -> whether it's on, as last written; nil until written
local queue = {} -- frames waiting: { frame = bytes, sent = fn(time) on a message's last frame }
local pending -- the ping waiting for its reply
local pings = 0

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

-- Whether signal i reads as there. The sound is silent and stopped at once.
local function signalThere(i)
    local willPlay, handle = PlaySoundFile(SIGNAL:format(i), "Master")
    if willPlay and handle then
        StopSound(handle)
    end
    return willPlay and true or false
end

-- The next signal that reads as missing, or -1. Ones that read as there were used earlier this
-- game launch (or the program isn't running to clear them).
local function freeSignal()
    local link = module.db.link
    local start = tonumber(link.signal) or 0
    for n = 0, min(signals, MAX_SCAN) - 1 do
        local i = (start + n) % signals
        if not signalThere(i) then
            link.signal = (i + 1) % signals
            return i
        end
    end
    return -1
end

local function ms(seconds)
    return floor(seconds * 1000 + 0.5)
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
    if p.signal < 0 then
        ns.PrintLine(L.AGENTCHAT_SIGNAL_NONE)
    elseif p.signalAt then
        ns.PrintLine(format(L.AGENTCHAT_SIGNAL_AT, p.signal, ms(p.signalAt - p.sentAt)))
    else
        ns.PrintLine(format(L.AGENTCHAT_SIGNAL_NEVER, p.signal))
    end
end

-- Loads the slot once its signal reads as there, or after LOAD_AFTER.
local function probe()
    local p = pending
    if not p then
        return
    end
    local now = GetTimePreciseSec()
    if p.signal >= 0 and signalThere(p.signal) then
        p.signalAt = now
    end
    if p.signalAt or now - p.sentAt >= LOAD_AFTER then
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
    local p = { id = tostring(pings), name = name, start = GetTimePreciseSec(), signal = freeSignal() }
    pending = p
    send(format("P|%s|%d|%d|%s|%s", session, slot, p.signal, p.id, text), function(at)
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
    ns.Print(format(L.AGENTCHAT_STATUS, tostring(session), slots - used, slots,
        tonumber(module.db.link.signal) or 0, signals, #queue))
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
-- a hello, which has it clear every slot (loaded ones can't load again until a /reload anyway)
-- and every signal (so the ones this launch hasn't used read as missing).
function module:OnEnable()
    -- Blizzard's AddOns list names the character by GUID too; a name alone changes nothing.
    character = UnitGUID("player")
    slots = 0
    while slots < MAX_SLOTS and C_AddOns.DoesAddOnExist(SLOT:format(slots)) do
        slots = slots + 1
    end
    signals = tonumber(C_AddOns.GetAddOnMetadata(SIGNALS, "X-Signals")) or 0
    if signals < 1 then
        signals = 1
    end
    session = format("%04x%04x", random(0, 65535), random(0, 65535))
    wipe(bits)
    wipe(queue)
    seq, pending = 0, nil
    queue[1] = { frame = AgentLink.Idle() }
    send("H|" .. session)
end

function module:OnDisable()
    pending = nil
    wipe(queue)
end
