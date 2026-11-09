-- Markdown: text written in Markdown (an agent's reply) as lines the game can show, with color
-- codes in place of its marks: headings in gold, bold in white, code in green, links as their
-- text with the address in gray, quotes in gray, and bullets as a dot. The game can't change font
-- weight inside a line, so color stands in for it. Any | in the text is doubled first, so nothing
-- in it becomes one of the game's escape codes; only the codes added here are real.
local ns = ForeverPlusPlusCompanion() -- Forever++'s own, as its files have (ForeverPlusPlus/Init.lua)

local tostring, tonumber = tostring, tonumber

local Markdown = {}
ns.Markdown = Markdown

local HEAD = "|cffffd100"
local BOLD = "|cffffffff"
local CODE = "|cffa8dca8"
local DIM = "|cff9d9d9d"
local LINK = "|cff71d5ff"
local BULLET = "\226\128\162" -- a bullet, U+2022

-- Marks within a line: `code` (kept as written), **bold**, and [text](address).
local function inline(s)
    local codes = {}
    s = s:gsub("`([^`]+)`", function(code)
        codes[#codes + 1] = code
        return "\001" .. #codes .. "\002"
    end)
    s = s:gsub("%*%*(.-)%*%*", BOLD .. "%1|r")
    s = s:gsub("%[([^%]]+)%]%(([^%)%s]+)%)", LINK .. "%1|r " .. DIM .. "(%2)|r")
    s = s:gsub("\001(%d+)\002", function(i)
        return CODE .. codes[tonumber(i)] .. "|r"
    end)
    return s
end

---Markdown text as lines to show, a blank line as " " so it keeps its space.
---@param text string?
---@return string[]
function Markdown.Lines(text)
    text = tostring(text or ""):gsub("\r", ""):gsub("|", "||")
    local out, inCode = {}, false
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:match("^%s*```") then
            inCode = not inCode -- the fence itself isn't shown
        elseif inCode then
            out[#out + 1] = line ~= "" and CODE .. line .. "|r" or " "
        else
            local head = line:match("^#+%s+(.-)%s*#*$")
            local indent, item = line:match("^(%s*)[%-%*%+]%s+(.*)$")
            local quote = line:match("^%s*>%s?(.*)$")
            if head then
                out[#out + 1] = HEAD .. inline(head) .. "|r"
            elseif line:match("^%s*[%-%*_]%s*[%-%*_]%s*[%-%*_][%-%*_%s]*$") then
                out[#out + 1] = DIM .. "----------|r" -- a rule
            elseif line:match("^%s*||?[%s:%-||]*%-%-%-[%s:%-||]*$") then
                -- A table's divider row (|---|---|): left out; the rows show as written.
            elseif item then
                out[#out + 1] = indent .. "  " .. BULLET .. " " .. inline(item)
            elseif quote then
                out[#out + 1] = DIM .. "  " .. inline(quote) .. "|r"
            else
                out[#out + 1] = line ~= "" and inline(line) or " "
            end
        end
    end
    -- No blank line at the end, from the text's own last newline.
    while #out > 1 and out[#out] == " " do
        out[#out] = nil
    end
    return out
end
