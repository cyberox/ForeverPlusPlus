-- Slash commands a module adds and takes away live, like /way and /rl. A command is the
-- SLASH_<key>1 global and SlashCmdList[key]. A slash another addon already answers to (TomTom's
-- /way) is left to that addon. Chat caches a command's function the first time it's typed
-- (hash_SlashCmdList), so taking one away clears that too, like AceConsole does.
local _, ns = ...

local pairs, type, format, sort, _G = pairs, type, string.format, table.sort, _G

local Slash = {}
ns.Slash = Slash

local added = {} -- key -> { slash, help } while our command is registered
local warned = {} -- slash -> true once the player has been told another addon has it
local ready = false -- true after login: commands added then are the player's own doing

ns.On("PLAYER_ENTERING_WORLD", function()
    ready = true
end)

-- Whether a command other than `key` already answers to `slash`. Chat moves every command it has
-- seen out of SlashCmdList (into its proxy, where pairs can't see them) and into
-- hash_SlashCmdList the first time any command is typed, so that's checked too.
local function taken(slash, key)
    slash = slash:upper()
    local hash = _G.hash_SlashCmdList
    if type(hash) == "table" and hash[slash] ~= nil then
        return true
    end
    for name in pairs(SlashCmdList) do
        if name ~= key then
            local i = 1
            local text = _G["SLASH_" .. name .. i]
            while text do
                if type(text) == "string" and text:upper() == slash then
                    return true
                end
                i = i + 1
                text = _G["SLASH_" .. name .. i]
            end
        end
    end
    return false
end

---Adds `slash` as command `key`, unless another addon already has that slash (then it says so in
---chat, once, if the player turned it on after login).
---@param key string the SlashCmdList key, FOREVERPLUSPLUS_<NAME>
---@param slash string like "/way"
---@param fn fun(message: string, editBox: table?)
---@param help? { usage: string?, description: string, owner: string? } for /fpp help and the About page: what follows the slash, one line about it, and the module that adds it
function Slash.Add(key, slash, fn, help)
    if added[key] then
        return
    end
    if taken(slash, key) then
        -- Said once, when the player turns it on: at login it would repeat every session.
        if ready and not warned[slash] then
            warned[slash] = true
            ns.Print(format(ns.L.SLASH_TAKEN, slash))
        end
        return
    end
    _G["SLASH_" .. key .. "1"] = slash
    SlashCmdList[key] = fn
    added[key] = { slash = slash, help = help }
end

---The commands added now that came with help, sorted by slash.
---@return { slash: string, usage: string, description: string, owner: string? }[]
function Slash.List()
    local list = {}
    for _, command in pairs(added) do
        local help = command.help
        if help then
            list[#list + 1] = {
                slash = command.slash, usage = help.usage or "",
                description = help.description, owner = help.owner,
            }
        end
    end
    sort(list, function(a, b) return a.slash < b.slash end)
    return list
end

---Takes away command `key`, if we added it.
---@param key string
---@param slash string
function Slash.Remove(key, slash)
    if not added[key] then
        return
    end
    SlashCmdList[key] = nil
    _G["SLASH_" .. key .. "1"] = nil
    -- Probe: Mainline keeps the cache in this global; without it there's nothing cached to clear.
    local hash = _G.hash_SlashCmdList
    if type(hash) == "table" then
        hash[slash:upper()] = nil
    end
    added[key] = nil
end
