-- CSV as wago.tools writes it (RFC 4180): fields split by commas, a field in double quotes may
-- hold commas, newlines, and "" for a quote. The text is untrusted: it's only ever split and read
-- as strings and numbers, never run.
local CSV = {}

local find, sub = string.find, string.sub

---Splits CSV text into rows of fields.
---@param text string
---@return string[][] rows
function CSV.Parse(text)
    text = text:gsub("\r\n", "\n")
    local rows, row, i, n = {}, {}, 1, #text
    if n == 0 then
        return rows
    end
    while true do
        local field
        if sub(text, i, i) == '"' then
            local parts, j = {}, i + 1
            while true do
                local q = find(text, '"', j, true)
                if not q then
                    error("CSV: a quoted field never ends (at byte " .. i .. ")")
                end
                parts[#parts + 1] = sub(text, j, q - 1)
                if sub(text, q + 1, q + 1) == '"' then
                    parts[#parts + 1] = '"'
                    j = q + 2
                else
                    i = q + 1
                    break
                end
            end
            field = table.concat(parts)
        else
            local stop = find(text, "[,\n]", i) or n + 1
            field = sub(text, i, stop - 1)
            i = stop
        end
        row[#row + 1] = field
        local c = sub(text, i, i)
        if c == "," then
            i = i + 1
        elseif c == "\n" or c == "" then
            rows[#rows + 1] = row
            row = {}
            i = i + 1
            if i > n then
                return rows
            end
        else
            error("CSV: text after a quoted field (at byte " .. i .. ")")
        end
    end
end

---Rows as tables by column name, checking that the columns the caller reads are there, so a
---renamed column stops the run instead of writing empty data.
---@param text string
---@param name string the table's name, for errors
---@param columns string[] columns that must be present
---@return table[] records
function CSV.Records(text, name, columns)
    local rows = CSV.Parse(text)
    local header = rows[1]
    if not header then
        error(name .. ": empty table")
    end
    local index = {}
    for i, column in ipairs(header) do
        index[column] = i
    end
    for _, column in ipairs(columns) do
        if not index[column] then
            error(name .. ": no column " .. column)
        end
    end
    local records = {}
    for r = 2, #rows do
        local row, record = rows[r], {}
        if #row ~= #header then
            error(name .. ": row " .. r .. " has " .. #row .. " fields, not " .. #header)
        end
        for column, i in pairs(index) do
            record[column] = row[i]
        end
        records[#records + 1] = record
    end
    return records
end

---A field as a whole number; errors on anything else.
---@param value string
---@param what string for errors
---@return integer
function CSV.Int(value, what)
    if type(value) ~= "string" or not value:match("^%-?%d+$") then
        error((what or "field") .. ": not a whole number: " .. tostring(value))
    end
    return tonumber(value)
end

---A field as a number; errors on anything else.
---@param value string
---@param what string for errors
---@return number
function CSV.Number(value, what)
    local number = type(value) == "string" and value:match("^%-?%d+%.?%d*[eE]?[%-+]?%d*$")
        and tonumber(value)
    if not number then
        error((what or "field") .. ": not a number: " .. tostring(value))
    end
    return number
end

-- Checks the parser on the cases wago.tools' files can have.
function CSV.SelfTest()
    local function same(a, b)
        if #a ~= #b then
            return false
        end
        for r = 1, #a do
            if #a[r] ~= #b[r] then
                return false
            end
            for f = 1, #a[r] do
                if a[r][f] ~= b[r][f] then
                    return false
                end
            end
        end
        return true
    end
    local cases = {
        { "a,b\n1,2\n", { { "a", "b" }, { "1", "2" } } },
        { "a,b\r\n1,2", { { "a", "b" }, { "1", "2" } } },
        { 'a,b\n"x, y",2\n', { { "a", "b" }, { "x, y", "2" } } },
        { 'a,b\n"line\none",2\n', { { "a", "b" }, { "line\none", "2" } } },
        { 'a,b\n"say ""hi""",\n', { { "a", "b" }, { 'say "hi"', "" } } },
        { 'a\n""\n', { { "a" }, { "" } } },
        { "a,b,c\n,,\n", { { "a", "b", "c" }, { "", "", "" } } },
    }
    for i, case in ipairs(cases) do
        if not same(CSV.Parse(case[1]), case[2]) then
            error("CSV self test " .. i .. " failed")
        end
    end
    local ok = pcall(CSV.Parse, 'a\n"open\n')
    if ok then
        error("CSV self test: an unclosed quote should fail")
    end
    return #cases + 1
end

return CSV
