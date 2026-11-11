-- Writing table text into Lua files safely: the addon's files are ASCII only, and a name from a
-- table must never end a comment or a string early.
local Out = {}

---Text for a line comment: printable ASCII only, anything else a "?".
---@param text string
---@return string
function Out.Comment(text)
    return (tostring(text):gsub("[^\32-\126]", "?"))
end

---A Lua string literal in ASCII, with everything outside printable ASCII as a \ddd escape.
---@param text string
---@return string
function Out.String(text)
    return '"' .. tostring(text):gsub('[%c"\\\128-\255]', function(c)
        return ("\\%03d"):format(c:byte())
    end) .. '"'
end

return Out
