-- English text for Agent Chat. ForeverPlusPlus/Locales/enUS/Core.lua says how locale files work.
local ns = ForeverPlusPlusCompanion()

local L = ns.NewLocale("enUS")
if not L then
    return
end

L.AGENTCHAT_TITLE = "Agent Chat"
L.AGENTCHAT_DESC = "Read and write in your T3 Code threads from a window in the game, kept up to date while "
    .. "agents work, through the Forever Agent program on this PC. Type /fpp agent to open it."
L.AGENTCHAT_COMMAND = "Open your T3 Code threads, or test the link to the Forever Agent program."
L.AGENTCHAT_COMMAND_USAGE = "[ping <text> | status]"
L.AGENTCHAT_COMMAND_UNKNOWN = "Unknown agent command: %s. Try ping or status." -- what was typed
L.AGENTCHAT_STATUS = "Agent link: session %s, %d of %d reply slots left, next signal %d of %d, "
    .. "offered signal %d, %d frames waiting."
    -- session id, slots left, slots, next signal, signals, the signal offered now (-1 none), frames
L.AGENTCHAT_PONG = "Reply \"%s\" in %d ms." -- the text, milliseconds
L.AGENTCHAT_SUMMARY = "Your T3 Code threads"
L.AGENTCHAT_NO_THREADS = "No threads yet"
L.AGENTCHAT_UNTITLED = "New thread"
L.AGENTCHAT_PICK = "Pick a thread"
L.AGENTCHAT_LOADING = "Loading..."
L.AGENTCHAT_OLDER = "%d earlier messages are in T3 Code." -- a number of messages
L.AGENTCHAT_CUT = "(Cut short here. The rest is in T3 Code.)"
L.AGENTCHAT_ANSWER = "Answer"
L.AGENTCHAT_ANSWER_HINT = "Type your own answer. Enter sends it."
L.AGENTCHAT_ANSWER_HOW = "Pick an answer, or type your own below."
L.AGENTCHAT_ANSWER_ALL = "Pick or type an answer to every question first."
L.AGENTCHAT_APPROVAL = "It waits for your approval in T3 Code."
L.AGENTCHAT_APPROVALS = "It waits for %d approvals in T3 Code." -- a number of approvals
L.AGENTCHAT_IMAGE = "1 image attached"
L.AGENTCHAT_IMAGES = "%d images attached" -- a number of images
L.AGENTCHAT_FILE = "1 file attached"
L.AGENTCHAT_FILES = "%d files attached" -- a number of files
L.AGENTCHAT_YOU = "You"
L.AGENTCHAT_AGENT = "Agent"
L.AGENTCHAT_WORKING = "Working"
L.AGENTCHAT_NEEDS_YOU = "Needs you"
L.AGENTCHAT_FAILED = "Failed"
L.AGENTCHAT_WAITING = "Waiting for the Forever Agent program. Is it running?"
L.AGENTCHAT_BUTTON = "Chat Button"
L.AGENTCHAT_BUTTON_DESC = "Add a button beside the chat window that opens Agent Chat and counts the "
    .. "threads that need you."
L.AGENTCHAT_BUTTON_HIDDEN = "The chat buttons are hidden, so the Chat Button can't show."
L.AGENTCHAT_BUTTON_HIDDEN_DESC = "Blizzard's buttons beside the chat window are hidden, most likely by "
    .. "another chat addon, and the Chat Button sits with them. Open the window with /fpp agent."
L.AGENTCHAT_BUTTON_TIP = "Open your T3 Code threads."
L.AGENTCHAT_BUTTON_COUNTS = "%d need you, %d working" -- threads needing you, threads working
L.AGENTCHAT_USAGE = "%d of %d updates left" -- updates left, all this session has
L.AGENTCHAT_USAGE_TIP = "Each update the window gets uses one, and /reload gives them all back. A "
    .. "message the agent is still writing updates every few seconds."
L.AGENTCHAT_MODEL = "Model: %s" -- a model's name
L.AGENTCHAT_MODEL_DEFAULT = "T3's default"
L.AGENTCHAT_CHANGED_ONE = "Changed %s" -- a file name
L.AGENTCHAT_CHANGED = "Changed %d files: %s" -- how many, their names
L.AGENTCHAT_CHANGED_MORE = "%s, and %d more" -- some file names, how many more
L.AGENTCHAT_NEW = "+ New"
L.AGENTCHAT_NEW_TIP = "Start a thread in one of your T3 Code projects."
L.AGENTCHAT_NEW_IN = "Start a thread in"
L.AGENTCHAT_NO_PROJECT = "No project"
L.AGENTCHAT_NEW_HINT = "Write the first message below. Enter starts the thread."
L.AGENTCHAT_STARTING = "You (starting the thread)"
L.AGENTCHAT_RELOAD_PROMPT = "Reload Prompt"
L.AGENTCHAT_RELOAD_PROMPT_DESC = "Offer to reload the UI when Forever++'s own files change while you play, "
    .. "such as when an agent edits it, once you're out of combat."
L.AGENTCHAT_RELOAD_TEXT = "Forever++ was changed. Reload the UI now to use it?"
L.AGENTCHAT_STEPS = "Show Steps"
L.AGENTCHAT_STEPS_DESC = "Show what the agent does along the way, a gray line each: commands it runs and "
    .. "files it reads and changes."
L.AGENTCHAT_STEP_RAN = "Ran %s" -- a command
L.AGENTCHAT_STEP_EDITED = "Edited %s" -- a file name
L.AGENTCHAT_STEP_CREATED = "Created %s" -- a file name
L.AGENTCHAT_STEP_READ = "Read %s" -- a file name
L.AGENTCHAT_STEP_SEARCHED = "Searched for %s" -- what it looked for
L.AGENTCHAT_STEP_WEB = "Looked up %s" -- a web address or search
L.AGENTCHAT_STEP_USED = "Used %s" -- a tool's name
L.AGENTCHAT_STEP_FAILED = "%s (failed)" -- a step
L.AGENTCHAT_STEP_TIMES = "%s (%d times)" -- a step, how many times in a row
L.AGENTCHAT_SOUND = "Sound"
L.AGENTCHAT_SOUND_DESC = "Play the whisper sound when a thread finishes, fails, or needs you."
L.AGENTCHAT_CHAT_DESC = "Say in chat when a thread finishes, fails, or needs you, even with the window closed."
L.AGENTCHAT_NOTICE_DONE = "%s is done. Type /fpp agent to read it." -- the thread's title
L.AGENTCHAT_NOTICE_WAITING = "%s needs you. Type /fpp agent to answer it." -- the thread's title
L.AGENTCHAT_NOTICE_FAILED = "%s failed. Type /fpp agent to see why." -- the thread's title
L.AGENTCHAT_SEND_HINT ="Message this thread. Enter queues it."
L.AGENTCHAT_NEWLINE_HINT = "Shift+Enter for a new line"
L.AGENTCHAT_TAB_ACTIVE = "Active"
L.AGENTCHAT_TAB_ALL = "All"
L.AGENTCHAT_RECENT = "Recent"
L.AGENTCHAT_TAB_PROJECT = "Project"
L.AGENTCHAT_NO_PROJECTS = "No projects yet"
L.AGENTCHAT_SNOOZED = "Snoozed"
L.AGENTCHAT_NO_ACTIVE = "Nothing active today. All has every thread."
L.AGENTCHAT_WORKING_FOR = "Working for %s" -- how long, like "2m 10s"
L.AGENTCHAT_SECONDS = "%ds" -- seconds, short
L.AGENTCHAT_MINUTES = "%dm %ds" -- minutes and seconds, short
L.AGENTCHAT_HOURS = "%dh %dm" -- hours and minutes, short
L.AGENTCHAT_MODE_FULL = "Full access"
L.AGENTCHAT_MODE_AUTO = "Auto"
L.AGENTCHAT_MODE_EDITS = "Accepts edits"
L.AGENTCHAT_MODE_ASK = "Asks first"
L.AGENTCHAT_SENDING = "You (sending)"
L.AGENTCHAT_NOT_SENT = "You (not sent: %s)" -- T3 Code's reason
L.AGENTCHAT_T3_SAID = "T3 Code: %s" -- T3 Code's reason something didn't work
L.AGENTCHAT_QUEUED = "Queued"
L.AGENTCHAT_QUEUED_HIDDEN = "(a message)"
L.AGENTCHAT_MORE_QUEUED = "%d more queued" -- a number of messages
L.AGENTCHAT_STEER = "Steer"
L.AGENTCHAT_STEER_TIP = "Send it to the agent now, into the turn it's running, instead of after it."
L.AGENTCHAT_CANCEL = "Remove"
L.AGENTCHAT_CANCEL_TIP = "Take it out of the queue."
L.AGENTCHAT_STOP = "Stop"
L.AGENTCHAT_STOP_TIP = "Stop the turn the agent is running."
L.AGENTCHAT_EXPIRES_DAYS = "Your T3 sign-in runs out in %d days. Run forever-agent login again." -- days
L.AGENTCHAT_EXPIRES_DAY = "Your T3 sign-in runs out tomorrow. Run forever-agent login again."
L.AGENTCHAT_EXPIRES_TODAY = "Your T3 sign-in runs out today. Run forever-agent login again."
L.AGENTCHAT_EXPIRED = "Your T3 sign-in ran out. Run forever-agent login again."
L.AGENTCHAT_OUT_OF_SLOTS ="Updates are used up for this session. Type /reload to keep it updating."
L.AGENTCHAT_DEAF = "Updates are slow: the game started before the Forever Agent program. Restart the game to fix it."
