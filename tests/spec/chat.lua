-- Chat: colored lines, timestamps, offsets between colored and plain text, the hook on each
-- window's messages, and quieting harmless "Interface action failed" lines.
local T = ...
local ns, eq = T.ns, T.eq

-- Chat.Colored, Chat.Uncolor, and offsets between them
local Chat = ns.Chat
eq(Chat.Colored("hi", 1, 0, 0), "|cffff0000hi|r", "colored line")
eq(Chat.Colored("hi"), "hi", "colored without a color")
eq(Chat.Colored("[|cff00ff00Bob|r]: hi", 0, 0, 1),
    "|cff0000ff[|r|cff00ff00Bob|r|cff0000ff]: hi|r", "colored keeps a name's color apart from the line's")
eq(Chat.Colored("|Hplayer:Bob|h[|cff00ff00Bob|r]|h: |cnIQ4:|Hitem:1|h[Axe]|h|r", 1, 1, 1),
    "|cffffffff[|r|cff00ff00Bob|r|cffffffff]: |r|cnIQ4:[Axe]|r|cffffffff|r",
    "colored keeps link colors apart from the line's")
ITEM_QUALITY_COLORS = { [4] = { r = 1, g = 0.5, b = 0 } }
eq(Chat.Colored("|cnIQ4:[Axe]|r |cnIQ9:[Odd]|r"), "|cffff8000[Axe]|r |cnIQ9:[Odd]|r",
    "colored turns item quality into a color code")
ITEM_QUALITY_COLORS = nil
eq(Chat.Colored("|Hplayer:Bob|h[Bob]|h |TIcon:0|tx", 1, 1, 1), "|cffffffff[Bob] x|r",
    "colored drops links and textures")
eq(Chat.Colored("a||rb", 1, 1, 1), "|cffffffffa||rb|r", "colored keeps an escaped pipe")
-- Chat.TimestampFormat and Chat.Stamp, as Blizzard's chat setting and BetterDate give them
eq(Chat.Stamp(), "", "no stamp while chat timestamps are off")
time, date = function() return 0 end, function(fmt) return "D(" .. fmt .. ")" end
ChatFrameUtil = { GetTimestampFormat = function() return "[%H:%M] " end }
eq(Chat.TimestampFormat(), "[%H:%M] ", "timestamp format from the chat setting")
eq(Chat.Stamp(), "D([%H:%M] )", "stamp without BetterDate")
TimeUtil = { BetterDate = function(fmt, t) return "B(" .. fmt .. t .. ")" end }
eq(Chat.Stamp(), "B([%H:%M] 0)", "stamp through BetterDate, like Blizzard's")
ChatFrameUtil.GetTimestampFormat = function() return nil end
eq(Chat.TimestampFormat(), nil, "timestamps off")
eq(Chat.Stamp(), "", "no stamp while off")
ChatFrameUtil, TimeUtil, time, date = nil, nil, nil, nil
local colored = "|cffff0000ab|cnRED:cd|r||e|r"
eq(Chat.Uncolor(colored), "abcd|e", "uncolor")
eq(Chat.Uncolor(Chat.Colored("[|cff00ff00Bob|r]: 5||6", 1, 0, 0)), "[Bob]: 5|6", "uncolor colored")
eq(Chat.PlainOffset(colored, 0), 0, "plain offset start")
eq(Chat.PlainOffset(colored, 12), 2, "plain offset after ab")
eq(Chat.PlainOffset(colored, 5), 0, "plain offset inside a code")
eq(Chat.PlainOffset(colored, #colored), 6, "plain offset end")
eq(Chat.ColoredOffset(colored, 0), 0, "colored offset start")
eq(Chat.ColoredOffset(colored, 2), 12, "colored offset after ab")
eq(Chat.ColoredOffset(colored, 3), 20, "colored offset after a code")
eq(Chat.ColoredOffset(colored, 5), 25, "colored offset after an escaped pipe")
eq(Chat.ColoredOffset(colored, 6), 26, "colored offset end, before the last code")

-- Chat.TimestampPattern
local function stamp(format, line)
    local _, finish = line:find(Chat.TimestampPattern(format))
    return finish and line:sub(1, finish)
end
eq(stamp("%I:%M ", "09:41 [Bob]: hi"), "09:41 ", "timestamp hours and minutes")
eq(stamp("[%H:%M:%S] ", "[21:05:09] hi"), "[21:05:09] ", "timestamp in brackets")
eq(stamp("%I:%M %p ", "9:41 PM hi"), "9:41 PM ", "timestamp with AM or PM")
eq(stamp("%I:%M ", "|Haddon:x|h09:41 |h hi"), nil, "timestamp not inside a link")
eq(stamp("%H:%M ", "[Bob]: 12:30 tonight"), nil, "timestamp only at the start")

-- Chat.OnMessage: one hook a function on each window, called only with text that can be read.
do
    T.game.secret = "<secret>"
    local windows = { {}, {} }
    Chat.EachWindow = function(_, fn)
        for _, window in ipairs(windows) do
            fn(window)
        end
    end
    local hooks, seen, visited = {}, {}, 0
    local watcher = { Hook = function(_, frame, method, fn) hooks[frame] = method == "AddMessage" and fn end }
    local function onMessage(frame, text) seen[#seen + 1] = text end
    Chat.OnMessage(watcher, onMessage, function() visited = visited + 1 end)
    eq(visited, 2, "on message: the module's own work on each window")
    local first = hooks[windows[1]]
    eq(first ~= nil and first == hooks[windows[2]], true, "on message: the same hook on every window")
    first(windows[1], "hello")
    first(windows[1], T.game.secret)
    first(windows[1], nil)
    eq(table.concat(seen, ","), "hello", "on message: a line the game hides is skipped")
    Chat.OnMessage(watcher, onMessage)
    eq(hooks[windows[1]], first, "on message: turned on again, the same hook, so it's hooked once")
    T.game.secret = nil
end

-- The yellow "Interface action failed" line: which refusals are harmless, and taking the line out.
do
    local Chat = ns.Chat
    local controller = false
    ns.Gamepad = { On = function() return controller end }
    local NAV = "[Interface/AddOns/Blizzard_GamepadSmartNavigation/SmartNavigation.lua]:84: in function"
    local LIST = NAV .. "\n[Interface/AddOns/Blizzard_Settings_Shared/Blizzard_CategoryList.lua]:120:"
    eq(Chat.HarmlessRefusal(NAV), true, "refusal: the controller navigation, controller interface off")
    eq(Chat.HarmlessRefusal("[Interface/AddOns/Other/Other.lua]:5:"), false, "refusal: anything else is real")
    eq(Chat.HarmlessRefusal(nil), false, "refusal: no stack")
    controller = true
    eq(Chat.HarmlessRefusal(NAV), false, "refusal: with the controller interface on it's worth knowing")
    eq(Chat.HarmlessRefusal(LIST), true, "refusal: but not the Settings sidebar's")
    eq(Chat.HarmlessRefusal(NAV .. "\n[Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua]:1041:"),
        true, "refusal: nor picking a page in Settings")
    controller = false

    local stack, hook = NAV, nil
    local lines = {}
    INTERFACE_ACTION_BLOCKED = "Interface action failed because of an AddOn"
    ChatFrameUtil = { AddSystemMessage = function() end }
    hooksecurefunc = function(_, _, fn) hook = fn end
    debugstack = function() return stack end
    DEFAULT_CHAT_FRAME = { RemoveMessagesByPredicate = function(_, test)
        for i = #lines, 1, -1 do
            if test(lines[i]) then
                table.remove(lines, i)
            end
        end
    end }
    Chat.QuietRefusals()
    local first = hook
    Chat.QuietRefusals()
    eq(hook, first, "quiet: hooked once")
    lines = { "hello", INTERFACE_ACTION_BLOCKED }
    hook(INTERFACE_ACTION_BLOCKED)
    eq(table.concat(lines, ","), "hello", "quiet: a harmless refusal's line is taken out")
    stack = "[Interface/AddOns/Other/Other.lua]:5:"
    lines = { "hello", INTERFACE_ACTION_BLOCKED }
    hook(INTERFACE_ACTION_BLOCKED)
    eq(#lines, 2, "quiet: a real one stays")
    stack = NAV
    hook("Something else")
    eq(#lines, 2, "quiet: another system message is left alone")
end
