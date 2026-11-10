-- English text for the chat modules. Locales/enUS/Core.lua says how locale files work.
local _, ns = ...

local L = ns.NewLocale("enUS")
if not L then
    return
end

-- ChatCopy
L.CHATCOPY_TITLE = "Chat Copy"
L.CHATCOPY_DESC = "Add a button beside the chat window that opens the chat as text you can "
    .. "select and copy."
L.CHATCOPY_TOOLTIP = "Copy Chat"
L.CHATCOPY_TOOLTIP_DESC = "Open the chat as text you can select and copy."
L.CHATCOPY_STAMPS = "Click Timestamps"
L.CHATCOPY_STAMPS_DESC = "Click a chat line's timestamp to copy that line. Needs the game's chat "
    .. "timestamps turned on."
L.CHATCOPY_STAMPS_PROMPT = "Press Ctrl+C to copy this chat line."
L.CHATCOPY_BUTTON_HIDDEN = "The chat buttons are hidden, so its button can't show."
L.CHATCOPY_BUTTON_HIDDEN_DESC = "Blizzard's buttons beside the chat window are hidden, most likely "
    .. "by another chat addon, and Chat Copy's button sits with them. Click Timestamps still works."
L.CHATCOPY_HIDDEN ="(hidden by the game)"
L.CHATCOPY_EMPTY = "(no chat yet)"
L.CHATCOPY_SELECT_ALL = "Select All"
L.CHATCOPY_SELECT_HINT = "Press Ctrl+C to copy."

-- ChatLevels
L.CHATLEVELS_TITLE = "Chat Levels"
L.CHATLEVELS_DESC = "Show each player's level before their name in chat, colored like a quest of "
    .. "that level. Forever++ remembers the levels of players you group with, your guild and "
    .. "friends, /who results, and players you target or see nearby."
L.CHATLEVELS_TEST = "Test Chat"
L.CHATLEVELS_TEST_BUTTON = "Show"
L.CHATLEVELS_TEST_DESC = "Add a few made-up trade chat lines from made-up players, with their "
    .. "levels and class colors, to your first chat window. Nobody else sees them."
L.CHATLEVELS_TEST_LINE = "[2. T] %s: %s" -- the channel, then the player's name link and what they said
L.CHATLEVELS_TEST_1 = "LF healer for Scarlet Monastery, then we go"
L.CHATLEVELS_TEST_2 = "WTB Mageweave Cloth, paying well"
L.CHATLEVELS_TEST_3 = "anyone know where the Defias are?"
L.CHATLEVELS_TEST_4 = "Selling Heavy Leather, 20 stacks, pst"

-- ShortChannelNames
L.SHORTCHANNELNAMES_TITLE = "Short Channel Names"
L.SHORTCHANNELNAMES_DESC = "Show chat channels as [1], [G], or [1. G] instead of [1. General]."
L.SHORTCHANNELNAMES_STYLE = "Style"
L.SHORTCHANNELNAMES_STYLE_DESC = "How a channel shows: its number, its first letter, its initials "
    .. "(LFG for LookingForGroup), its name without the zone, or the number with one of those."
L.SHORTCHANNELNAMES_NUMBER = "Number: [1]"
L.SHORTCHANNELNAMES_LETTER = "Letter: [G]"
L.SHORTCHANNELNAMES_INITIALS = "Initials: [LFG]"
L.SHORTCHANNELNAMES_NAME = "Name: [General]"
L.SHORTCHANNELNAMES_BOTH = "Number and Letter: [1. G]"
L.SHORTCHANNELNAMES_NUMBER_INITIALS = "Number and Initials: [1. LFG]"
L.SHORTCHANNELNAMES_NUMBER_NAME = "Number and Name: [1. General]"
L.SHORTCHANNELNAMES_CHAT_TYPES = "Guild, Party, and Raid"
L.SHORTCHANNELNAMES_CHAT_TYPES_DESC = "Also shorten [Guild], [Officer], [Party], [Raid], [Raid "
    .. "Warning], and [Instance] to [GD], [O], [P], [R], [RW], and [I], their leaders' to [PL], "
    .. "[RL], and [IL], and the party guide's to [PG]."
L.SHORTCHANNELNAMES_GUILD = "GD"
L.SHORTCHANNELNAMES_OFFICER = "O"
L.SHORTCHANNELNAMES_PARTY = "P"
L.SHORTCHANNELNAMES_PARTY_LEADER = "PL"
L.SHORTCHANNELNAMES_PARTY_GUIDE = "PG"
L.SHORTCHANNELNAMES_RAID = "R"
L.SHORTCHANNELNAMES_RAID_LEADER = "RL"
L.SHORTCHANNELNAMES_RAID_WARNING = "RW"
L.SHORTCHANNELNAMES_INSTANCE = "I"
L.SHORTCHANNELNAMES_INSTANCE_LEADER = "IL"

-- QuestLinks
L.QUESTLINKS_TITLE = "Quest Links"
L.QUESTLINKS_DESC = "Make the quests players with Questie link in chat, like [[34] A Grim Task (304)], "
    .. "into quest links you can click to see the quest, as if they'd linked it from their quest log."

-- ChatHistory
L.CHATHISTORY_TITLE = "Chat History"
L.CHATHISTORY_DESC = "Keep the chat windows' latest lines when you log out or reload, and "
    .. "show them again when you log in. Whispers aren't kept."
L.CHATHISTORY_LINES = "Lines Saved"
L.CHATHISTORY_LINES_DESC = "How many of each chat window's latest lines are kept."
L.CHATHISTORY_DIVIDER = "-- Earlier chat --"
L.CHATHISTORY_DIVIDER_OPTION = "Earlier Chat Line"
L.CHATHISTORY_DIVIDER_DESC = "Show a gray line between the restored chat and new chat."

-- SocialButton
L.SOCIALBUTTON_TITLE = "Social Button"
L.SOCIALBUTTON_DESC = "Move the social (Quick Join) button down beside the chat window's other "
    .. "buttons."
L.SOCIALBUTTON_MENU = "Social"

-- The column of chat buttons (Lib/Chat.lua), for every module with a button in it.
L.CHAT_BUTTON_FOLDED = "The chat window is too short for its button, so it's in the chat menu."
L.CHAT_BUTTON_FOLDED_DESC = "The button didn't fit above the speech bubble button beside the chat "
    .. "window, so it's listed at the bottom of that button's menu instead. Make the chat window "
    .. "taller to bring it back."

-- ChatFont
L.CHATFONT_TITLE = "Chat Font"
L.CHATFONT_DESC = "Draw the chat windows in another of the game's fonts. The size stays as you "
    .. "set it, and turning this off gives Blizzard's font back."
L.CHATFONT_FONT = "Font"
L.CHATFONT_FONT_DESC = "The font the chat windows use."
L.CHATFONT_INPUT = "Chat Input"
L.CHATFONT_INPUT_DESC = "Use the font for the text you type into the chat box too. Its size stays as it is."

-- PersistentChat
L.PERSISTENTCHAT_TITLE = "Persistent Chat"
L.PERSISTENTCHAT_DESC = "Keep chat text on screen instead of fading it out after a while. Turning "
    .. "this off gives Blizzard's fading back."

-- WhisperWindow
L.WHISPERWINDOW_TITLE = "Whisper Window"
L.WHISPERWINDOW_DESC = "Keep whispers in a window of their own, a conversation per person, with a "
    .. "box to reply in. Conversations are saved for each character."
L.WHISPERWINDOW_WINDOW_TITLE = "Whispers"
L.WHISPERWINDOW_SECTION_WINDOW = "Window"
L.WHISPERWINDOW_SECTION_OPACITY = "Opacity"
L.WHISPERWINDOW_OPEN = "Open for Whispers"
L.WHISPERWINDOW_OPEN_DESC = "Open the window when a whisper comes in, or when you send one from "
    .. "chat. In combat, it waits until combat ends."
L.WHISPERWINDOW_HIDE = "Hide Whispers in Chat"
L.WHISPERWINDOW_HIDE_DESC = "Leave whispers, and away and busy replies, out of the chat windows "
    .. "once the Whisper Window has them. A whisper the game hides the text of still shows in chat."
L.WHISPERWINDOW_BUTTON = "Chat Button"
L.WHISPERWINDOW_BUTTON_DESC = "Add a button beside the chat window that opens the Whisper Window "
    .. "and counts unread whispers. On a chat window too short for it, it's in the speech bubble "
    .. "button's menu, and the speech bubble counts the whispers instead."
L.WHISPERWINDOW_BUTTON_HIDDEN = "The chat buttons are hidden, so the Chat Button can't show."
L.WHISPERWINDOW_BUTTON_HIDDEN_DESC = "Blizzard's buttons beside the chat window are hidden, most "
    .. "likely by another chat addon, and the Chat Button sits with them. Open the window with "
    .. "/fpp whispers, or Show below."
L.WHISPERWINDOW_ALPHA ="Opacity"
L.WHISPERWINDOW_ALPHA_DESC = "How solid the window is while you stand still, and while the mouse "
    .. "is over it or you type in it."
L.WHISPERWINDOW_MOVING = "While Moving"
L.WHISPERWINDOW_MOVING_DESC = "How solid the window is while you move, out of combat."
L.WHISPERWINDOW_COMBAT = "In Combat"
L.WHISPERWINDOW_COMBAT_DESC = "How solid the window is in combat."
L.WHISPERWINDOW_SHOW = "Whispers"
L.WHISPERWINDOW_SHOW_BUTTON = "Show"
L.WHISPERWINDOW_SHOW_DESC = "Open the Whisper Window."
L.WHISPERWINDOW_CLEAR = "Clear"
L.WHISPERWINDOW_CLEAR_NAME = "Saved Conversations"
L.WHISPERWINDOW_CLEAR_DESC = "Forget every conversation of this character."
L.WHISPERWINDOW_CLEAR_CONFIRM = "Forget every conversation of this character?"
L.WHISPERWINDOW_COMMAND = "open the Whisper Window, on a conversation with a name"
L.WHISPERWINDOW_COMMAND_USAGE = "[name]"
L.WHISPERWINDOW_TOOLTIP = "Whispers"
L.WHISPERWINDOW_TOOLTIP_DESC = "Open your conversations."
L.WHISPERWINDOW_SUMMARY_ONE = "1 conversation"
L.WHISPERWINDOW_SUMMARY = "%d conversations" -- how many
L.WHISPERWINDOW_SUMMARY_UNREAD = "%s, %d unread" -- "3 conversations", unread whispers
L.WHISPERWINDOW_PREVIEW_YOU = "You: %s" -- your last whisper, in the list
L.WHISPERWINDOW_REPLY_HINT = "Whisper %s" -- name
L.WHISPERWINDOW_UNREAD = "%d new" -- unread whispers in a conversation
L.WHISPERWINDOW_NONE = "No conversation picked."
L.WHISPERWINDOW_YOU = "You"
L.WHISPERWINDOW_LINE = "%s %s: %s" -- time, who, the whisper
L.WHISPERWINDOW_INFO_LINE = "%s %s" -- time, what happened
L.WHISPERWINDOW_FULL_NAME = "%s %s" -- first name, surname
L.WHISPERWINDOW_LEVEL = "Level %d"
L.WHISPERWINDOW_PLAYING = "Playing %s" -- a Battle.net friend's character
L.WHISPERWINDOW_GUILD_NAME = "<%s>" -- their guild, as Blizzard's tooltips show it
L.WHISPERWINDOW_FRIEND = "Friend"
L.WHISPERWINDOW_GUILD = "Guild"
L.WHISPERWINDOW_OFFLINE = "Offline"
L.WHISPERWINDOW_UNKNOWN = "Level and zone show for friends, guildmates, and players nearby."
L.WHISPERWINDOW_AFK = "Away: %s" -- the away message
L.WHISPERWINDOW_DND = "Busy: %s" -- the busy message
L.WHISPERWINDOW_INVITE = "Invite"
L.WHISPERWINDOW_REMOVE = "Remove Conversation"
L.WHISPERWINDOW_REMOVE_CONFIRM = "Forget your conversation with %s?" -- name
L.WHISPERWINDOW_NEW = "New Whisper"
L.WHISPERWINDOW_NEW_PROMPT = "Whisper who?"
L.WHISPERWINDOW_LOCKED = "Chat is restricted here right now."
L.WHISPERWINDOW_TEST = "Test Conversation"
L.WHISPERWINDOW_TEST_BUTTON = "Send"
L.WHISPERWINDOW_TEST_DESC = "Add a made-up conversation to the Whisper Window, a few whispers back "
    .. "and forth with a Night Elf Druid, to see how it looks. It doesn't open the window, so its "
    .. "whispers count as unread on the chat button. Replies to it go nowhere."
L.WHISPERWINDOW_TEST_NAME = "Testy Moonwhisper"
L.WHISPERWINDOW_TEST_RACE = "Night Elf"
L.WHISPERWINDOW_TEST_CLASS = "Druid"
L.WHISPERWINDOW_BNET_OFFLINE ="This Battle.net friend isn't online."
