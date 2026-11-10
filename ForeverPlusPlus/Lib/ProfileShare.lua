-- A profile as one line of text, to copy and paste: Export on the Profiles page shows it, Import
-- takes it back. The text starts with its version, "FPP1z:" when it's compressed (C_EncodingUtil,
-- which Forever has: docs/forever-api.md) or "FPP1:" when it's plain, so a client without the
-- compression still makes text any client reads.
--
-- Pasted text is untrusted: Validate keeps only modules this addon has, their declared settings
-- (an option's value of its kind, a slider's within its range, a dropdown's among its choices; a
-- setting without an option, such as an Edit Mode place, of its default's type), and the data
-- they mark as the profile's, as plain values. Everything else is dropped, and the name loses its
-- codes as any profile's does. Options that are one of Blizzard's settings (`cvar`) aren't in a
-- profile.
local _, ns = ...

local pairs, ipairs, type, tonumber, next, pcall = pairs, ipairs, type, tonumber, next, pcall
local format, byte, char, sub, find, gsub = string.format, string.byte, string.char, string.sub,
    string.find, string.gsub
local concat, sort, huge = table.concat, table.sort, math.huge

local L = ns.L

local Share = {}
ns.ProfileShare = Share

Share.VERSION = 1
local PLAIN, PACKED = "FPP1:", "FPP1z:"
local MAX_TEXT = 500000 -- characters of pasted text
local MAX_NODES = 20000 -- values in it
local MAX_DEPTH = 12
local MAX_STRING = 200 -- characters in one string of profile data
local DATA_DEPTH = 4 -- tables inside one key of profile data

-- Serializing ------------------------------------------------------------------------------------
-- s<length>:<bytes>, n<number>;, t, f, and { key value ... } for a table, keys in a set order so the
-- same profile always makes the same text.

local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta < tb
    end
    return a < b
end

local function write(value, out)
    local kind = type(value)
    if kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "number" then
        out[#out + 1] = "n" .. format("%.14g", value) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = value and "t" or "f"
    elseif kind == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for key in pairs(value) do
            local k = type(key)
            if k == "string" or k == "number" then
                keys[#keys + 1] = key
            end
        end
        sort(keys, keyOrder)
        for _, key in ipairs(keys) do
            write(key, out)
            write(value[key], out)
        end
        out[#out + 1] = "}"
    end
end

---A value (tables of strings, numbers and booleans) as text.
---@param value any
---@return string
function Share.Serialize(value)
    local out = {}
    write(value, out)
    return concat(out)
end

---Text made by Serialize as the value again, or nil when it isn't well formed or is too big.
---@param text string
---@return any?
function Share.Parse(text)
    if type(text) ~= "string" or #text > MAX_TEXT then
        return nil
    end
    local pos, nodes = 1, 0
    local read
    function read(depth)
        nodes = nodes + 1
        if nodes > MAX_NODES or depth > MAX_DEPTH then
            return nil, false
        end
        local tag = sub(text, pos, pos)
        if tag == "s" then
            local colon = find(text, ":", pos + 1, true)
            local length = colon and tonumber(sub(text, pos + 1, colon - 1))
            if not length or length < 0 or colon + length > #text then
                return nil, false
            end
            local value = sub(text, colon + 1, colon + length)
            pos = colon + length + 1
            return value, true
        elseif tag == "n" then
            local semi = find(text, ";", pos + 1, true)
            local value = semi and tonumber(sub(text, pos + 1, semi - 1))
            if not value then
                return nil, false
            end
            pos = semi + 1
            return value, true
        elseif tag == "t" or tag == "f" then
            pos = pos + 1
            return tag == "t", true
        elseif tag == "{" then
            pos = pos + 1
            local t = {}
            while sub(text, pos, pos) ~= "}" do
                if pos > #text then
                    return nil, false
                end
                local key, okKey = read(depth + 1)
                if not okKey or (type(key) ~= "string" and type(key) ~= "number") or key ~= key then
                    return nil, false
                end
                local value, okValue = read(depth + 1)
                if not okValue then
                    return nil, false
                end
                t[key] = value
            end
            pos = pos + 1
            return t, true
        end
        return nil, false
    end
    local value, ok = read(1)
    if not ok or pos ~= #text + 1 then
        return nil
    end
    return value
end

-- The plain form keeps to printable characters an edit box takes as they are: anything else, and
-- % and |, as %XX.
local function escape(text)
    return (gsub(text, "[^\33-\36\38-\123\125\126]", function(c)
        return format("%%%02X", byte(c))
    end))
end

local function unescape(text)
    if find(text, "%%[^%x]") or find(text, "%%%x?$") or find(text, "%%%x[^%x]") then
        return nil
    end
    return (gsub(text, "%%(%x%x)", function(hex)
        return char(tonumber(hex, 16))
    end))
end

-- C_EncodingUtil's compression and Base64, when this client has them all. Probe: Mainline's.
local function codec()
    local util = C_EncodingUtil
    if util and util.CompressString and util.DecompressString and util.EncodeBase64
        and util.DecodeBase64 then
        return util
    end
end

local function deflate()
    return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

-- Encoding --------------------------------------------------------------------------------------

---A profile as one line of text.
---@param name string
---@param settings table { [module] = { [key] = value } }
---@param data table { [module] = { [key] = table } }
---@return string
function Share.Encode(name, settings, data)
    local body = Share.Serialize({ v = Share.VERSION, name = name, addon = ns.version,
        s = settings or {}, d = data or {} })
    local util = codec()
    if util then
        local ok, packed = pcall(util.CompressString, body, deflate())
        local ok2, text = false, nil
        if ok and type(packed) == "string" then
            ok2, text = pcall(util.EncodeBase64, packed)
        end
        if ok2 and type(text) == "string" then
            return PACKED .. text
        end
    end
    return PLAIN .. escape(body)
end

---The raw contents of exported text, or nil and why not. Not checked against the modules yet:
---see Share.Validate.
---@param text string
---@return table? raw { v, name, addon, s, d }
---@return string? reason
function Share.Decode(text)
    if type(text) ~= "string" then
        return nil, L.PROFILES_IMPORT_BAD
    end
    text = gsub(gsub(text, "^%s+", ""), "%s+$", "")
    local body
    if sub(text, 1, #PACKED) == PACKED then
        local util = codec()
        if not util then
            return nil, L.PROFILES_IMPORT_CANT
        end
        local ok, packed = pcall(util.DecodeBase64, sub(text, #PACKED + 1))
        if ok and type(packed) == "string" then
            local ok2, unpacked = pcall(util.DecompressString, packed, deflate())
            body = ok2 and type(unpacked) == "string" and unpacked or nil
        end
    elseif sub(text, 1, #PLAIN) == PLAIN then
        body = unescape(sub(text, #PLAIN + 1))
    else
        return nil, L.PROFILES_IMPORT_BAD
    end
    local raw = body and Share.Parse(body)
    if type(raw) ~= "table" then
        return nil, L.PROFILES_IMPORT_BAD
    end
    if type(raw.v) ~= "number" or raw.v > Share.VERSION then
        return nil, L.PROFILES_IMPORT_NEWER
    end
    return raw
end

-- Validating ------------------------------------------------------------------------------------

local function finite(value)
    return type(value) == "number" and value == value and value ~= huge and value ~= -huge
end

-- Whether `value` fits `option` (a checkbox, a dropdown or a slider).
local function fits(option, value)
    local kind = ns.OptionKind(option)
    if kind == "checkbox" then
        return type(value) == "boolean"
    elseif kind == "dropdown" then
        for _, choice in ipairs(option.choices) do
            if choice[1] == value then
                return true
            end
        end
        return false
    end
    return finite(value) and value >= option.min and value <= option.max
end

-- Profile data as plain values: tables of strings (no codes), finite numbers and booleans, so
-- far deep. Nil when nothing is left of it.
local function plain(value, depth, budget)
    local kind = type(value)
    if kind == "string" then
        value = gsub(ns.Text.Plain(sub(value, 1, MAX_STRING)), "[|%c]", "")
        return value
    elseif kind == "boolean" then
        return value
    elseif kind == "number" then
        return finite(value) and value or nil
    elseif kind == "table" and depth <= DATA_DEPTH then
        local out = {}
        for key, inner in pairs(value) do
            budget.left = budget.left - 1
            if budget.left < 0 then
                break
            end
            local k = type(key) == "string" and plain(key, depth, budget) or finite(key) and key or nil
            local v = plain(inner, depth + 1, budget)
            if k ~= nil and k ~= "" and v ~= nil then
                out[k] = v
            end
        end
        return out
    end
end

---What of an import this addon can take: its name cleaned, the settings of known modules that fit
---their options or defaults, and their profile data, with the counts the Import popup shows.
---@param raw table from Share.Decode
---@param modules? table name -> module, ns.modules by default
---@return table profile { name, addon, settings, data, modulesOn, changed }
function Share.Validate(raw, modules)
    modules = modules or ns.modules
    local settings, data = {}, {}
    for name, saved in pairs(type(raw.s) == "table" and raw.s or {}) do
        local module = type(name) == "string" and modules[name]
        if module and type(saved) == "table" then
            local byKey = {}
            for _, option in ipairs(module.options or {}) do
                byKey[option.key] = option
            end
            local own = {}
            for key, value in pairs(saved) do
                local option = type(key) == "string" and byKey[key]
                local default = type(key) == "string" and module.defaults[key]
                if key == "enabled" then
                    if type(value) == "boolean" and not module.alwaysOn then
                        own.enabled = value
                    end
                elseif option then
                    if not option.cvar and fits(option, value) then
                        own[key] = value
                    end
                elseif default ~= nil and type(default) ~= "table" and type(value) == type(default)
                    and (type(value) ~= "number" or finite(value)) then
                    own[key] = type(value) == "string" and gsub(sub(value, 1, MAX_STRING), "[|%c]", "") or value
                end
            end
            if next(own) then
                settings[name] = own
            end
        end
    end
    local budget = { left = MAX_NODES }
    for name, saved in pairs(type(raw.d) == "table" and raw.d or {}) do
        local module = type(name) == "string" and modules[name]
        if module and type(saved) == "table" then
            for key, value in pairs(saved) do
                if type(key) == "string" and module.perProfile and module.perProfile[key]
                    and type(module.defaults[key]) == "table" and type(value) == "table" then
                    local clean = plain(value, 1, budget)
                    if clean and next(clean) then
                        data[name] = data[name] or {}
                        data[name][key] = clean
                    end
                end
            end
        end
    end
    local name = ns.Profiles.CleanName(raw.name)
    if name == "" then
        name = L.PROFILES_IMPORTED
    end
    local addon = type(raw.addon) == "string" and gsub(sub(raw.addon, 1, 20), "[^%w%.%-]", "") or "?"
    local modulesOn, changed = ns.Profiles.CountSettings(settings)
    return { name = name, addon = addon, settings = settings, data = data, modulesOn = modulesOn,
        changed = changed }
end

---Exported text for one of the profiles.
---@param id string
---@return string
function Share.Export(id)
    local settings, data = ns.Profiles.Contents(id)
    return Share.Encode(ns.Profiles.Name(id), settings, data)
end

---Pasted text as a profile ready to import (see Share.Validate), or nil and why not.
---@param text string
---@return table? profile
---@return string? reason
function Share.Import(text)
    local raw, reason = Share.Decode(text)
    if not raw then
        return nil, reason
    end
    return Share.Validate(raw)
end
