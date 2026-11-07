-- Small text helpers modules share: measuring a font string, lines of a tooltip, numbers with
-- thousands separators, how long as words ("3 Seconds", "12m ago"), comparing version strings,
-- text without its escape codes, the client's format strings as patterns, and a long chat message
-- cut into ones the game will send.
local _, ns = ...

local format, floor, max, type, _G = string.format, math.floor, math.max, type, _G
local gmatch, gsub, tonumber = string.gmatch, string.gsub, tonumber
local find, sub, match, ipairs = string.find, string.sub, string.match, ipairs
local BreakUpLargeNumbers = BreakUpLargeNumbers

-- Probe: WoW's strtrim, or the same in plain Lua (for tests/run.lua).
local strtrim = strtrim or function(text)
    return (gsub(text, "^%s*(.-)%s*$", "%1"))
end

local L = ns.L

local Text = {}
ns.Text = Text

---How wide a font string's text is unwrapped. Probe: GetUnboundedStringWidth is Mainline's.
---@param text table a FontString
---@return number
function Text.Width(text)
    return text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
end

---A tooltip's left font string on line `i`, or nil for tooltips without named lines.
---@param tooltip table
---@param i number
---@return table?
function Text.LeftLine(tooltip, i)
    local name = tooltip.GetName and tooltip:GetName()
    return type(name) == "string" and _G[name .. "TextLeft" .. i] or nil
end

---A tooltip's right font string on line `i`, or nil for tooltips without named lines.
---@param tooltip table
---@param i number
---@return table?
function Text.RightLine(tooltip, i)
    local name = tooltip.GetName and tooltip:GetName()
    return type(name) == "string" and _G[name .. "TextRight" .. i] or nil
end

---A number with the client's thousands separators ("12,345"), or the number itself on a client
---without BreakUpLargeNumbers.
---@param n number
---@return string|number
function Text.Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or n
end

---A number with up to `places` decimals and no trailing zeros: 4.6, 4.17, 5, never "-0".
---@param n number
---@param places? number 2 by default
---@return string
function Text.Decimal(n, places)
    places = places or 2
    local text = format("%." .. places .. "f", n or 0)
    if places > 0 then
        text = gsub(gsub(text, "0+$", ""), "%.$", "")
    end
    if text == "-0" then
        text = "0"
    end
    return text
end

---A bar's text as Blizzard's unit frame bars write it for mana (TextStatusBarMixin's
---UpdateTextStringWithValues, with capNumericDisplay), by the statusTextDisplay CVar: "BOTH" is
---the percent at the left and the value at the right, "PERCENT" the percent in the middle, and
---anything else (NUMERIC, NONE) "value / max" in the middle. Returns the middle, left, and right
---texts, "" where there's none. Probe: AbbreviateLargeNumbers ("12.3K") where the client has it.
---@param value number
---@param maxValue number above 0
---@param mode string?
---@return string middle
---@return string left
---@return string right
function Text.StatusText(value, maxValue, mode)
    local short = _G.AbbreviateLargeNumbers or Text.Number
    local percent = math.ceil(value / maxValue * 100) .. "%"
    if mode == "BOTH" then
        return "", percent, tostring(short(value))
    elseif mode == "PERCENT" then
        return percent, "", ""
    end
    return short(value) .. " / " .. short(maxValue), "", ""
end

---A number of seconds for a slider label: "1 Second", "5 Seconds".
---@param seconds number
---@return string
function Text.Seconds(seconds)
    return seconds == 1 and L.TEXT_ONE_SECOND or format(L.TEXT_SECONDS, seconds)
end

---A number of hours for a slider label: "1 Hour", "12 Hours".
---@param hours number
---@return string
function Text.Hours(hours)
    return hours == 1 and L.TEXT_ONE_HOUR or format(L.TEXT_HOURS, hours)
end

---A length of time as a clock: "0:42", "12:05", and from an hour "1:02:05".
---@param seconds number
---@return string
function Text.Clock(seconds)
    seconds = max(0, floor(seconds + 0.5)) -- an aura a moment past its end still reads 0:00
    if seconds >= 3600 then
        return format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
    end
    return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

---How long ago something was, as short as a price line: "just now", "12m ago", "3h ago", "2d ago".
---@param seconds number
---@return string
function Text.Ago(seconds)
    if seconds < 60 then
        return L.TEXT_AGO_NOW
    elseif seconds < 3600 then
        return format(L.TEXT_AGO_MINUTES, floor(seconds / 60))
    elseif seconds < 86400 then
        return format(L.TEXT_AGO_HOURS, floor(seconds / 3600))
    end
    return format(L.TEXT_AGO_DAYS, floor(seconds / 86400))
end

-- The numbers of a version, or of its pre-release suffix, in order.
local function versionParts(text)
    local parts = {}
    for part in gmatch(text or "", "%d+") do
        parts[#parts + 1] = tonumber(part)
    end
    return parts
end

-- 1, -1, or 0 as `left` comes after, before, or with `right`, part by part.
local function comparePartLists(left, right)
    for i = 1, max(#left, #right) do
        local x, y = left[i] or 0, right[i] or 0
        if x ~= y then
            return x > y and 1 or -1
        end
    end
    return 0
end

---Whether version `a` comes after version `b`, part by part: "0.10.0" is newer than "0.9.2".
---A pre-release comes before its release: "1.0.0-beta.2" is newer than "1.0.0-beta.1" and
---older than "1.0.0".
---@param a string such as "0.8.0"
---@param b string
---@return boolean
function Text.NewerVersion(a, b)
    local coreA, preA = match(a, "^([^-]*)%-?(.*)$")
    local coreB, preB = match(b, "^([^-]*)%-?(.*)$")
    local order = comparePartLists(versionParts(coreA), versionParts(coreB))
    if order ~= 0 then
        return order > 0
    end
    if preA == "" or preB == "" then
        return preA == "" and preB ~= ""
    end
    return comparePartLists(versionParts(preA), versionParts(preB)) > 0
end

---Text without its escape codes: colors, links (their text stays), textures, and atlases.
---Nothing here may be given a secret value; test with `ns.IsReadable` first.
---@param text string
---@return string
function Text.Plain(text)
    if not find(text, "|", 1, true) then
        return text -- most lines have no codes; skip the eight passes
    end
    -- An escaped pipe is set aside first, so "||r" or "||cff..." isn't read as a code.
    text = gsub(text, "||", "\1")
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|cn[^:|]*:", "")
    text = gsub(text, "|r", "")
    text = gsub(text, "|H[^|]*|h(.-)|h", "%1")
    text = gsub(text, "|T[^|]*|t", "")
    text = gsub(text, "|A[^|]*|a", "")
    text = gsub(text, "\1", "|")
    return text
end

local CAPTURES = { s = "(.+)", d = "(%d+)" }
local MATCHES = { s = ".-", d = "%d+" }

---A Lua pattern for one of the client's format strings, such as ITEM_MIN_SKILL ("Requires %s
---(%d)"), so it matches in any language. Each %s and %d is captured, or only matched without
---`capture`. "%1$s" (reordered, in some languages) counts as "%s". Not anchored.
---@param formatString string
---@param capture? boolean
---@return string
function Text.FormatPattern(formatString, capture)
    local pattern = gsub(formatString, "%%%d+%$", "%%")
    pattern = gsub(pattern, "[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    return (gsub(pattern, "%%([sd])", capture and CAPTURES or MATCHES))
end

-- Where the links are in a chat message: { start, finish } byte ranges a cut mustn't fall inside,
-- each with the color code before it and the |r after it.
local function linkSpans(text)
    local spans, from = {}, 1
    while true do
        local s, e = find(text, "|H.-|h.-|h", from)
        if not s then
            return spans
        end
        local colorStart = find(sub(text, 1, s - 1), "|c%x%x%x%x%x%x%x%x$")
            or find(sub(text, 1, s - 1), "|cn[^:|]*:$")
        s = colorStart or s
        if sub(text, e + 1, e + 2) == "|r" then
            e = e + 2
        end
        spans[#spans + 1] = { s, e }
        from = e + 1
    end
end

---A chat message cut into pieces of at most `limit` bytes, the way to send one longer than the
---game allows: between words where it can, and never inside a link.
---@param text string
---@param limit number
---@return string[]
function Text.Split(text, limit)
    local pieces = {}
    text = strtrim(text)
    while #text > limit do
        local spans = linkSpans(text)
        -- Whether cutting before byte i would cut through a link.
        local function inside(i)
            for _, span in ipairs(spans) do
                if span[1] < i and i <= span[2] then
                    return true
                end
            end
            return false
        end
        local cut
        for i = limit + 1, 2, -1 do
            if sub(text, i, i) == " " and not inside(i) then
                cut = i
                break
            end
        end
        if not cut then
            cut = limit + 1
            while cut > 2 and inside(cut) do
                cut = cut - 1
            end
            -- A link longer than the limit on its own: kept whole, past the limit.
            for _, span in ipairs(spans) do
                if span[1] < cut and cut <= span[2] then
                    cut = span[2] + 1
                end
            end
        end
        pieces[#pieces + 1] = strtrim(sub(text, 1, cut - 1))
        text = strtrim(sub(text, cut))
    end
    if text ~= "" then
        pieces[#pieces + 1] = text
    end
    return pieces
end
