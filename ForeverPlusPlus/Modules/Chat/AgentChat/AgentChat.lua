-- Agent Chat: your T3 Code threads in a window in the game, through the Forever Agent program on
-- the same PC (agent/ in this repo). /fpp agent opens it. Read only for now.
--
-- An addon can't write files or open sockets, so the link uses files the game reads and writes.
-- Out: Lib/AgentLink's frames, as which of 256 helper addons are on for this character, written
-- at once to its AddOns.txt by C_AddOns.SaveAddOns(); the program watches that file. In: the
-- program writes into a load-on-demand helper addon (a slot), and this loads it with
-- C_AddOns.LoadAddOn, which runs its Data.lua: that sets ForeverPlusPlusAgentInbox, read and
-- cleared at once. A slot loads once per UI session.
--
-- This always keeps one slot offered to the program (an inbox), and the program fills it only
-- when something changed, so a slot is spent only on news. A signal says it's filled: a sound
-- file in the FPPAgentSignals helper, which the program makes after writing. PlaySoundFile
-- answers whether it's there, with game sound off too. The game knows only files that existed
-- when it started, and once it has found one it remembers it until it restarts, so each signal
-- works once per game launch: an offer takes the next one that reads as missing, from where the
-- last left off (saved, so a /reload goes on from there). With none left, the slot loads a second
-- after offering, while the window is open. What the tests showed is in docs/forever-api.md.
--
-- The helpers exist only once the program installs them, so without it the module isn't offered.
-- The program's side and the messages are in agent/internal/bridge.
local _, ns = ...

local _G, ipairs, pairs, format, type, tostring, tonumber, floor, random, wipe, min = _G, ipairs, pairs,
    format, type, tostring, tonumber, math.floor, math.random, wipe, math.min
local tremove, time = table.remove, time
local C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound, PlaySound =
    C_AddOns, UnitGUID, GetTimePreciseSec, PlaySoundFile, StopSound, PlaySound

local L = ns.L
local AgentLink = ns.AgentLink

local BIT, SLOT, SIGNALS = "FPPAgentBit%03d", "FPPAgentSlot%03d", "FPPAgentSignals"
local SIGNAL = "Interface\\AddOns\\FPPAgentSignals\\%04d.wav"
local INBOX = "ForeverPlusPlusAgentInbox"
local HOLD = 0.1 -- seconds each frame stays written, so the program reads every one
local CHECK_OPEN, CHECK_CLOSED = 0.1, 0.5 -- how often the signal is checked
local LOAD_AFTER = 1 -- with no signal, load the slot this long after offering it
local LOAD_AFTER_MOST = 5 -- doubling up to this while those loads find nothing new
local GIVE_UP = 30 -- while the window is open, load an offer this long unanswered and offer again
local MAX_SLOTS = 999
local MAX_SCAN = 200 -- signals checked per offer before going without one
local MAX_TEXT = 200

local module = ns.NewModule("AgentChat", L.AGENTCHAT_DESC, {
    enabled = true,
    sound = true,
    chat = true,
    chatButton = true,
    steps = true,
    reloadPrompt = true,
    link = {}, -- signal: the next signal to try
    layout = {}, -- where the window was left, and the list's tab
    seen = {}, -- thread id -> its updated time when last read, for unread marks
})
module.title = L.AGENTCHAT_TITLE
module.category = "chat"
module.added = "1.3.0"

-- When a thread finishes, fails, or needs you: a line in chat and a sound, window open or not.
module.options = {
    { key = "chatButton", name = L.AGENTCHAT_BUTTON, description = L.AGENTCHAT_BUTTON_DESC },
    { key = "steps", name = L.AGENTCHAT_STEPS, description = L.AGENTCHAT_STEPS_DESC },
    { key = "reloadPrompt", name = L.AGENTCHAT_RELOAD_PROMPT, description = L.AGENTCHAT_RELOAD_PROMPT_DESC },
    { key = "sound", name = L.AGENTCHAT_SOUND, description = L.AGENTCHAT_SOUND_DESC },
    ns.ChatOption(L.AGENTCHAT_CHAT_DESC),
}

-- While another addon hides Blizzard's chat buttons, the Chat Button can't show.
module.notice = ns.Chat.HiddenNotice(L.AGENTCHAT_BUTTON_HIDDEN, L.AGENTCHAT_BUTTON_HIDDEN_DESC,
    function(db) return db.chatButton end)

local NOTICES = {
    done = L.AGENTCHAT_NOTICE_DONE,
    waiting = L.AGENTCHAT_NOTICE_WAITING,
    failed = L.AGENTCHAT_NOTICE_FAILED,
}

local function notify(events)
    local any = false
    for _, event in ipairs(events) do
        local text = NOTICES[event.kind]
        if text then
            any = true
            local title = tostring(event.title or ""):gsub("|", "||")
            module:Print(format(text, title ~= "" and title or L.AGENTCHAT_UNTITLED))
        end
    end
    if any and module.db.sound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        PlaySound(SOUNDKIT.TELL_MESSAGE)
    end
end

local internal = {}
module.internal = internal

-- The chat button: in the column beside the chat window, after Whisper Window's. It opens the
-- window, counts the threads that need the player, and glows while any do, as Whisper Window's
-- does for unread whispers.
local BUTTON_ICON = "Interface\\GossipFrame\\GossipGossipIcon" -- the speech bubble on gossip options
local BUTTON_ORDER = 40
local button

local function updateButton()
    if not button then
        return
    end
    local waiting = tonumber(internal.counts and internal.counts.waiting) or 0
    button.count:SetText(waiting > 0 and waiting or "")
    if waiting > 0 then
        button.glow:Show()
        if not button.pulse:IsPlaying() then
            button.pulse:Play()
        end
    else
        button.pulse:Stop()
        button.glow:Hide()
    end
end

local function newButton()
    local b = ns.Chat.NewButton(BUTTON_ICON, function()
        internal.Toggle()
    end, L.AGENTCHAT_TITLE, L.AGENTCHAT_BUTTON_TIP)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", 0, 0)
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetAtlas("chatframe-button-highlight")
    glow:SetBlendMode("ADD")
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.1)
    fade:SetToAlpha(1)
    fade:SetDuration(0.8)
    fade:SetSmoothing("IN_OUT")
    b.glow, b.pulse = glow, pulse
    -- How things stand, under the tooltip's line.
    b:HookScript("OnEnter", function()
        local counts = internal.counts or {}
        GameTooltip:AddLine(format(L.AGENTCHAT_BUTTON_COUNTS, tonumber(counts.waiting) or 0,
            tonumber(counts.working) or 0), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    return b
end

local function showButton()
    if module.enabled and module.db.chatButton and ns.Chat.Anchor() ~= nil then
        button = button or newButton()
        button:Show()
        ns.Chat.AddButton(module.name, button, BUTTON_ORDER)
        updateButton()
    elseif button then
        ns.Chat.RemoveButton(module.name)
        button:Hide()
    end
end

function module:OnOptionChanged(key)
    if key == "chatButton" then
        showButton()
    elseif key == "steps" and internal.Refresh then
        internal.Refresh("thread")
    end
end

-- Only with the program's helper addons installed.
function module:IsAvailable()
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    return exists and exists(BIT:format(0)) and exists(SLOT:format(0)) and exists(SIGNALS) or false
end

local sendTimer = ns.Frames.Timer(module)
local checkTimer = ns.Frames.Timer(module)
local offerTimer = ns.Frames.Timer(module)
local SETTLE = 0.3 -- after the hello, time for the program to clear the signals before an offer
local SIGNAL_TRIES = 3 -- offers tried a second apart, while the window is open, before going without

-- What the window shows. The window (Window.lua) reads these.
internal.threads = {} -- the list, newest first: { h, id, title, status, model, project, updated }
internal.projects = {} -- T3's projects, by title: { id, title }, for starting a thread in one
internal.counts = { waiting = 0, working = 0 } -- threads needing the player and working, for the button
internal.composing = nil -- a new thread being written: { project, name, id, text, error }
-- T3's providers with their models: { name, instance, models = { { id, label }... } }
internal.models = {}
internal.slotsUsed, internal.slotsTotal = 0, 0 -- reply slots this UI session has loaded, of all
internal.conversations = {} -- thread id -> { items = { [pos] = item }, order = { pos... }, older }
internal.queues = {} -- thread id -> { active, items = { { q, text }... } }: its queued messages
internal.sending = {} -- what the player sent that T3 hasn't taken yet: { id, threadId, text, error }
-- thread id -> { approvals, items = { { a, questions = { { header, question, multi, options = {
-- { label, description }... } }... } }... } }: what its agent asks the player, and approvals waiting
internal.asks = {}
internal.picks = {} -- a -> question index -> option index -> true: what the player has picked
internal.answering = {} -- a -> true while an answer is on its way
internal.selected = nil -- the thread id shown
internal.note = nil -- what the program says about its link to T3, or nil when all's well
internal.heard = false -- whether the program has answered this session
internal.outOfSlots = false

local character, session, slots, signals
local seq = 0
local bits = {} -- helper index -> whether it's on, as last written; nil until written
local queue = {} -- frames waiting: { frame = bytes, sent = fn(time) on a message's last frame }
local offer -- the inbox offered: { slot, name, signal, offeredAt }
local noSignal = 0 -- offers in a row that found no free signal
-- How long after offering a slot without a signal it's loaded. Each such load spends a slot, so it
-- waits longer while they come back empty, and goes back to LOAD_AFTER when the player does something.
local loadAfter = LOAD_AFTER
local pings, pingStarts = 0, {}
local viewSent -- the last V message, so the same one isn't sent twice

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
    if message:sub(1, 2) ~= "O|" then
        loadAfter = LOAD_AFTER -- the player did something: the answer should come quickly
    end
    local frames
    frames, seq = AgentLink.Frames(message, seq)
    for i, frame in ipairs(frames) do
        queue[#queue + 1] = { frame = frame, sent = i == #frames and sent or nil }
    end
    if not sendTimer:IsPending() then
        pump()
    end
end

-- Receiving ---------------------------------------------------------------------------------------

-- The first slot this UI session hasn't loaded.
local function freeSlot()
    for i = 0, slots - 1 do
        local name = SLOT:format(i)
        if not C_AddOns.IsAddOnLoaded(name) then
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
-- game launch (or the program hasn't cleared them yet).
local function freeSignal()
    local link = module.db.link
    local start = tonumber(link.signal) or 0
    local scan = min(signals, MAX_SCAN)
    for n = 0, scan - 1 do
        local i = (start + n) % signals
        if not signalThere(i) then
            link.signal = (i + 1) % signals
            return i
        end
    end
    -- All used: look past them next time, or every later offer checks the same ones and the link
    -- goes without signals for the rest of the session. Only once the program has answered, since
    -- it clears the signals when it joins: one checked before that reads as used until the game
    -- restarts, and moving on would spend the rest the same way.
    if internal.heard and signals > 0 then
        link.signal = (start + scan) % signals
    end
    return -1
end

local function ms(seconds)
    return floor(seconds * 1000 + 0.5)
end

local function refresh(what)
    if internal.Refresh then
        internal.Refresh(what)
    end
end

local function byId(id)
    for _, thread in ipairs(internal.threads) do
        if thread.id == id then
            return thread
        end
    end
end

-- Tells the program which thread is shown and whether the window is open.
local function sendView()
    if not session then
        return
    end
    local thread = internal.selected and byId(internal.selected)
    local view = format("V|%s|%d|%d", session, thread and thread.h or 0, internal.IsShown() and 1 or 0)
    if view ~= viewSent then
        viewSent = view
        send(view)
    end
end

local function applyThread(update)
    local conversation = internal.conversations[update.id]
    if not conversation then
        conversation = { items = {}, order = {}, older = 0 }
        internal.conversations[update.id] = conversation
    end
    if type(update.older) == "number" and update.older > 0 then
        conversation.older = update.older
    end
    for _, item in ipairs(type(update.items) == "table" and update.items or {}) do
        if type(item.pos) == "number" then
            if not conversation.items[item.pos] then
                conversation.order[#conversation.order + 1] = item.pos
                table.sort(conversation.order)
            end
            conversation.items[item.pos] = item
        end
    end
    return update.id
end

-- T3 gives the program no way to renew its sign-in, so the player signs in again: say so as it
-- nears, in the window from WINDOW_WARN_DAYS out, and once a session in chat from CHAT_WARN_DAYS.
local WINDOW_WARN_DAYS, CHAT_WARN_DAYS = 5, 3
local expiryWarned = false

---What to say about the T3 sign-in running out within `days`, or nil.
---@param days number?
---@return string?
function internal.ExpiryWarning(days)
    local expires = tonumber(internal.expires)
    if not expires or expires <= 0 then
        return nil
    end
    local left = expires - time()
    if left > (days or WINDOW_WARN_DAYS) * 86400 then
        return nil
    elseif left <= 0 then
        return L.AGENTCHAT_EXPIRED
    elseif left < 86400 then
        return L.AGENTCHAT_EXPIRES_TODAY
    end
    local whole = floor(left / 86400)
    return whole == 1 and L.AGENTCHAT_EXPIRES_DAY or format(L.AGENTCHAT_EXPIRES_DAYS, whole)
end

-- Forever++'s own files changed (an agent edited it): offer a reload, like the game's own prompt
-- before it moves you to another layer, and like it not in combat.
local function askReload()
    if not module.db.reloadPrompt then
        return
    end
    ns.AfterCombat(function()
        if module.enabled then
            ns.Confirm("AGENTCHAT_RELOAD", L.AGENTCHAT_RELOAD_TEXT, ReloadUI)
        end
    end)
end

-- What the program sent.
local function receive(inbox, now)
    if type(inbox) ~= "table" or inbox.session ~= session then
        return
    end
    internal.heard = true
    if inbox.note ~= nil then
        internal.note = inbox.note ~= "" and inbox.note or nil
        refresh("status")
    end
    if type(inbox.reload) == "number" then
        askReload()
    end
    if type(inbox.counts) == "table" then
        internal.counts = inbox.counts
        updateButton()
    end
    if type(inbox.models) == "table" then
        internal.models = inbox.models
    end
    if type(inbox.projects) == "table" then
        internal.projects = inbox.projects
    end
    if type(inbox.expires) == "number" then
        internal.expires = inbox.expires
        local warning = internal.ExpiryWarning(CHAT_WARN_DAYS)
        if warning and not expiryWarned then
            expiryWarned = true
            module:Print(warning)
        end
        refresh("status")
    end
    if type(inbox.threads) == "table" then
        internal.threads = inbox.threads
        internal.MarkSeen(true)
        refresh("list")
        sendView() -- the shown thread's handle may be new
    end
    if type(inbox.thread) == "table" then
        if applyThread(inbox.thread) == internal.selected then
            refresh("thread")
        end
    end
    if type(inbox.events) == "table" then
        notify(inbox.events)
    end
    if type(inbox.queue) == "table" and inbox.queue.id then
        internal.queues[inbox.queue.id] = inbox.queue
        if inbox.queue.id == internal.selected then
            refresh("thread")
        end
    end
    if type(inbox.asks) == "table" and inbox.asks.id then
        internal.asks[inbox.asks.id] = inbox.asks
        if inbox.asks.id == internal.selected then
            refresh("thread")
        end
    end
    for _, ack in ipairs(type(inbox.acks) == "table" and inbox.acks or {}) do
        if ack.ask then
            internal.answering[ack.ask] = nil -- answered, it leaves with the next asks
        end
        local composing = internal.composing
        if composing and ack.id and ack.id == composing.id then
            -- A new thread: open it once T3 has it; otherwise say why, and let the player try again.
            if ack.ok and ack.thread then
                internal.composing = nil
                internal.Select(ack.thread)
            else
                composing.id, composing.error = nil, tostring(ack.error)
            end
        end
        local sent = ack.id and internal.SendingById(ack.id)
        if ack.ok and sent then
            tremove(internal.sending, sent) -- T3 has it: it shows in the queue or the thread now
        elseif not ack.ok then
            if sent then
                internal.sending[sent].error = tostring(ack.error)
            end
            ns.Print(format(L.AGENTCHAT_T3_SAID, tostring(ack.error)))
        end
        refresh("thread")
    end
    for _, pong in ipairs(type(inbox.pongs) == "table" and inbox.pongs or {}) do
        local start = pingStarts[pong.id]
        if start then
            pingStarts[pong.id] = nil
            ns.Print(format(L.AGENTCHAT_PONG, tostring(pong.text), ms(now - start)))
        end
    end
end

local offerNext

-- Loads the offered slot once its signal is there (or, with none, a second after offering).
local function check()
    local o = offer
    if not (o and o.offeredAt) then
        return
    end
    local now = GetTimePreciseSec()
    local ready
    if o.signal >= 0 then
        -- A program that restarted forgets the offer and clears its signal: while the window is
        -- open, give up after a while and offer again.
        ready = signalThere(o.signal) or (internal.IsShown() and now - o.offeredAt >= GIVE_UP)
    else
        ready = now - o.offeredAt >= loadAfter
    end
    if not ready then
        checkTimer:Start(internal.IsShown() and CHECK_OPEN or CHECK_CLOSED, check)
        return
    end
    offer = nil
    _G[INBOX] = nil
    C_AddOns.LoadAddOn(o.name)
    internal.slotsUsed = internal.slotsUsed + 1
    refresh("status")
    local inbox = _G[INBOX]
    _G[INBOX] = nil
    if o.signal < 0 then
        local empty = type(inbox) == "table"
        for key in pairs(empty and inbox or {}) do
            if key ~= "session" then
                empty = false
                break
            end
        end
        loadAfter = empty and min(LOAD_AFTER_MOST, loadAfter * 2) or LOAD_AFTER
    end
    receive(inbox, now)
    offerNext()
end

-- Offers the program the next inbox, unless one is out already.
function offerNext()
    if offer or not session then
        return
    end
    local slot, name = freeSlot()
    if not slot then
        internal.outOfSlots = true
        refresh("status")
        return
    end
    local signal = freeSignal()
    if signal < 0 then
        -- Every signal reads as used: the program may not have cleared them yet (it does at the
        -- hello, or when it joins a session it missed). Try again for a bit; after that, offer
        -- without one, loading every second, but only while the window is open.
        if not internal.IsShown() then
            return
        end
        noSignal = noSignal + 1
        if noSignal < SIGNAL_TRIES then
            offerTimer:Start(1, offerNext)
            return
        end
    else
        noSignal = 0
    end
    local o = { slot = slot, name = name, signal = signal }
    offer = o
    send(format("O|%s|%d|%d", session, slot, signal), function(at)
        o.offeredAt = at
        check()
    end)
end

-- The window's side --------------------------------------------------------------------------------

---Remembers the shown thread as read, and with `list`, takes in a new list: a thread seen for the
---first time counts as read (so nothing is unread on the first run), and threads gone from it are
---forgotten.
---@param list boolean?
function internal.MarkSeen(list)
    local seen = module.db.seen
    if list then
        local kept = {}
        for _, thread in ipairs(internal.threads) do
            local updated = tonumber(thread.updated) or 0
            kept[thread.id] = seen[thread.id] or updated
        end
        wipe(seen)
        for id, updated in pairs(kept) do
            seen[id] = updated
        end
    end
    local thread = internal.selected and internal.IsShown and internal.IsShown() and byId(internal.selected)
    if thread then
        seen[thread.id] = tonumber(thread.updated) or seen[thread.id]
    end
end

---Whether a thread changed since the player last read it.
---@param thread table
---@return boolean
function internal.IsUnread(thread)
    local seen = module.db.seen[thread.id]
    return seen ~= nil and (tonumber(thread.updated) or 0) > seen and thread.id ~= internal.selected
end

---The model new threads start on, as the player picked it in "+ New": its provider instance and
---model id, or nil for T3's own choice (also when the picked one is gone from T3's list).
---@return string? instance
---@return string? model
function internal.NewThreadModel()
    local picked = module.db.layout.newModel
    if type(picked) ~= "table" then
        return nil
    end
    for _, provider in ipairs(internal.models) do
        if provider.instance == picked.instance then
            for _, model in ipairs(type(provider.models) == "table" and provider.models or {}) do
                if model.id == picked.model then
                    return picked.instance, picked.model
                end
            end
        end
    end
end

---Picks the model new threads start on (nil for T3's own choice).
---@param instance string?
---@param model string?
function internal.PickNewThreadModel(instance, model)
    module.db.layout.newModel = model and { instance = instance, model = model } or nil
    refresh("thread")
end

---Starts writing a new thread in a project (its T3 id, "" for none), shown in place of a thread
---until its first message is sent and T3 has it.
---@param project string
---@param name string? the project's title, to show
function internal.NewThread(project, name)
    internal.composing = { project = project or "", name = name }
    internal.Select(nil, true)
end

---Shows a thread, or none, and tells the program.
---@param id string?
---@param keepComposing boolean? leave a new thread being written open
function internal.Select(id, keepComposing)
    if not keepComposing then
        internal.composing = nil
    end
    internal.selected = id
    internal.MarkSeen()
    refresh("thread")
    refresh("list")
    sendView()
end

local sends = 0

---Where in internal.sending the send with this id is.
---@param id string
---@return number?
function internal.SendingById(id)
    for i, sent in ipairs(internal.sending) do
        if sent.id == id then
            return i
        end
    end
end

---Sends text to the shown thread, queued: an idle thread starts on it, a busy one runs it next.
---@param text string as an edit box gives it, with a typed | doubled
---@return boolean sent
function internal.Send(text)
    text = text and text:gsub("||", "|"):match("^%s*(.-)%s*$")
    local composing = internal.composing
    if composing then
        -- The first message of a new thread: it starts it.
        if not (session and text and text ~= "") or composing.id then
            return false
        end
        sends = sends + 1
        composing.id, composing.text, composing.error = "g" .. sends, text, nil
        local instance, model = internal.NewThreadModel()
        send(format("N|%s|%s|%s|%s|%s|%s", session, composing.id, composing.project, instance or "", model or "",
            text))
        offerNext()
        refresh("thread")
        return true
    end
    local thread = session and internal.selected and byId(internal.selected)
    if not (thread and text and text ~= "") then
        return false
    end
    sends = sends + 1
    local id = "g" .. sends
    internal.sending[#internal.sending + 1] = { id = id, threadId = thread.id, text = text }
    send(format("M|%s|%d|%s|%s", session, thread.h, id, text))
    offerNext()
    refresh("thread")
    return true
end

---Steers a queued message into the running turn now.
---@param q number
function internal.Steer(q)
    if session then
        send(format("S|%s|%d", session, q))
        offerNext()
    end
end

---Takes a message out of the queue.
---@param q number
function internal.Cancel(q)
    if session then
        send(format("D|%s|%d", session, q))
        offerNext()
    end
end

---The question the shown thread's agent asks first, if it asks one.
---@return table? request { a, questions }
function internal.ShownAsk()
    local asks = internal.selected and internal.asks[internal.selected]
    return asks and type(asks.items) == "table" and asks.items[1] or nil
end

---Picks an option of a question the agent asked, or takes it back: a question that takes one
---answer keeps only the last picked.
---@param a number the request
---@param q number the question
---@param o number the option
function internal.Pick(a, q, o)
    local picks = internal.picks[a] or {}
    internal.picks[a] = picks
    local request = internal.ShownAsk()
    local question = request and request.a == a and request.questions[q]
    if not question then
        return
    end
    local picked = picks[q] or {}
    if picked[o] then
        picked[o] = nil
    elseif question.multi then
        picked[o] = true
    else
        picked = { [o] = true }
    end
    picks[q] = picked
    refresh("thread")
end

---Answers the question the shown thread's agent asks: with the options picked, and the text for
---each question with none picked.
---@param text string? as an edit box gives it, with a typed | doubled
---@return boolean sent
function internal.Answer(text)
    local request = session and internal.ShownAsk()
    if not request or internal.answering[request.a] then
        return false
    end
    text = (text or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
    local picks = internal.picks[request.a] or {}
    local lines = {}
    for q, question in ipairs(request.questions) do
        local picked = {}
        for o in ipairs(question.options or {}) do
            if picks[q] and picks[q][o] then
                picked[#picked + 1] = o
            end
        end
        if #picked > 0 then
            lines[q] = "o:" .. table.concat(picked, ",")
        elseif text ~= "" then
            lines[q] = "t:" .. text
        else
            ns.Print(L.AGENTCHAT_ANSWER_ALL)
            return false
        end
    end
    internal.answering[request.a] = true
    send(format("A|%s|%d|%s", session, request.a, table.concat(lines, "\n")))
    offerNext()
    refresh("thread")
    return true
end

---Stops the shown thread's running turn.
function internal.Stop()
    local thread = session and internal.selected and byId(internal.selected)
    if thread then
        send(format("X|%s|%d", session, thread.h))
        offerNext()
    end
end

---The window opened or closed.
function internal.ViewChanged()
    internal.MarkSeen()
    if not session then
        return
    end
    sendView()
    offerNext() -- after running out of signals, an offer waits for the window
end

-- Commands -----------------------------------------------------------------------------------------

local function ping(text)
    text = text ~= "" and text:sub(1, MAX_TEXT) or "ping"
    pings = pings + 1
    local id = tostring(pings)
    pingStarts[id] = GetTimePreciseSec()
    send(format("P|%s|%s|%s", session, id, text))
    offerNext()
end

local function status()
    local used = 0
    for i = 0, slots - 1 do
        if C_AddOns.IsAddOnLoaded(SLOT:format(i)) then
            used = used + 1
        end
    end
    ns.Print(format(L.AGENTCHAT_STATUS, tostring(session), slots - used, slots,
        tonumber(module.db.link.signal) or 0, signals, offer and offer.signal or -1, #queue))
end

ns.AddCommand("agent", L.AGENTCHAT_COMMAND_USAGE, L.AGENTCHAT_COMMAND, function(rest)
    local command, argument = rest:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "ping" then
        ping(argument)
    elseif command == "status" then
        status()
    elseif command == "" then
        internal.Toggle()
    else
        ns.Print(format(L.AGENTCHAT_COMMAND_UNKNOWN, command))
    end
end, "AgentChat")

-- Lifecycle ------------------------------------------------------------------------------------------

-- A UI session starts with the idle frame, which tells the program to start reading afresh, a
-- hello, which has it clear every slot (loaded ones can't load again until a /reload anyway) and
-- every signal (so the ones this launch hasn't used read as missing), and the first offer.
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
    wipe(internal.threads)
    wipe(internal.conversations)
    wipe(internal.queues)
    wipe(internal.sending)
    seq, offer, viewSent, noSignal = 0, nil, nil, 0
    internal.heard, internal.note, internal.outOfSlots = false, nil, false
    internal.counts, internal.composing = { waiting = 0, working = 0 }, nil
    -- Slots this UI session has loaded already (a module turned off and on keeps them used).
    internal.slotsUsed = 0
    for i = 0, slots - 1 do
        if C_AddOns.IsAddOnLoaded(SLOT:format(i)) then
            internal.slotsUsed = internal.slotsUsed + 1
        end
    end
    internal.slotsTotal = slots
    showButton()
    queue[1] = { frame = AgentLink.Idle() }
    send("H|" .. session, function()
        offerTimer:Start(SETTLE, function()
            offerNext()
            sendView()
        end)
    end)
end

function module:OnDisable()
    offer, session = nil, nil
    wipe(queue)
    showButton() -- module.enabled is false by now, so it goes
    if internal.Hide then
        internal.Hide()
    end
end
