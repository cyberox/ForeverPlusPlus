-- Commands: short slash commands players expect from other games' addons, each its own checkbox.
-- /rl reloads the UI; /clear empties a chat window. A command another addon already has is left
-- to that addon (Lib/Slash). /fpp is Core's and is always there, whatever this module does. /way
-- is the Waypoints module's.
local _, ns = ...

local ipairs = ipairs

local L = ns.L

local module = ns.NewModule("Commands", L.COMMANDS_DESC, {
    enabled = true,
    reload = true,
    clear = true,
})
module.title = L.COMMANDS_TITLE
module.category = "system"
module.added = "0.8.0"

module.options = {
    { key = "reload", name = L.COMMANDS_RELOAD, description = L.COMMANDS_RELOAD_DESC },
    { key = "clear", name = L.COMMANDS_CLEAR, description = L.COMMANDS_CLEAR_DESC },
}

-- /rl -----------------------------------------------------------------------------------------

local function reload()
    if module.enabled and module.db.reload then
        ReloadUI()
    end
end

-- /clear --------------------------------------------------------------------------------------

-- Empties the chat window the command was typed in: the edit box's own window, else the one
-- selected, else the main one. Only its lines go; Chat History's saved lines stay.
local function clear(_, editBox)
    if not (module.enabled and module.db.clear) then
        return
    end
    local frame = editBox and editBox.chatFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if frame and frame.Clear then
        frame:Clear()
    end
end

-- The commands, each behind the option with its key.
local COMMANDS = {
    { option = "reload", key = "FOREVERPLUSPLUS_RELOAD", slash = "/rl", fn = reload,
        help = { description = L.COMMANDS_RELOAD_HELP, owner = "Commands" } },
    { option = "clear", key = "FOREVERPLUSPLUS_CLEAR", slash = "/clear", fn = clear,
        help = { description = L.COMMANDS_CLEAR_HELP, owner = "Commands" } },
}

local function sync()
    for _, command in ipairs(COMMANDS) do
        if module.enabled and module.db[command.option] then
            ns.Slash.Add(command.key, command.slash, command.fn, command.help)
        else
            ns.Slash.Remove(command.key, command.slash)
        end
    end
end

function module:OnEnable()
    sync()
end

function module:OnDisable()
    sync()
end

function module:OnOptionChanged()
    sync()
end
