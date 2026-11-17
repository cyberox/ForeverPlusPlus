-- Docs: what AGENTS.md says the docs hold, checked against the code, and the click hints' format.
-- A new Lib file with no row, or a hint written another way, shows here instead of in a review.
local T = ...
local ns, eq = T.ns, T.eq

local agents = T.Read("AGENTS.md") or ""
local architecture = T.Read("docs/architecture.md") or ""

-- Every Lib file has a row in AGENTS.md's Lib tables (or is listed as generated there) and a
-- place in docs/architecture.md.
do
    local _, files = T.Toc()
    local unlisted, undescribed, count = {}, {}, 0
    for _, file in ipairs(files) do
        local name = file:gsub("\\", "/"):match("^Lib/([%w_]+%.lua)$")
        if name then
            count = count + 1
            local quoted = "`" .. name .. "`"
            if not agents:find(quoted, 1, true) then
                unlisted[#unlisted + 1] = name
            end
            if not architecture:find(quoted, 1, true) then
                undescribed[#undescribed + 1] = name
            end
        end
    end
    eq(count > 50, true, "docs: the TOC's Lib files are found (" .. count .. ")")
    eq(table.concat(unlisted, ", "), "", "docs: every Lib file is in AGENTS.md's Lib tables")
    eq(table.concat(undescribed, ", "), "", "docs: every Lib file is in docs/architecture.md")
end

-- A click hint is written as Blizzard's instruction lines are (AGENTS.md, "Click hints"): in
-- angle brackets, the keys and the click as separate words with no plus or hyphen, no full stop.
do
    -- What's wrong with one line of a hint, or nil.
    local function wrongLine(line)
        local inside = line:match("^<([^<>]*)>$")
        if not inside then
            return "has a line that isn't one hint in brackets"
        end
        if inside:find("%+") then
            return "has a plus"
        end
        if inside:lower():find("%-click") then
            return "hyphenates the click"
        end
        if inside:find("%.$") then
            return "ends with a full stop"
        end
        return nil
    end

    -- What's wrong with a hint, or nil: each of its lines is one click's hint.
    local function wrong(text)
        if not text:match("^<.*>$") then
            return nil -- not a hint
        end
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local why = wrongLine(line)
            if why then
                return why
            end
        end
        return nil
    end

    local bad, hints = {}, 0
    for key, text in pairs(ns.L) do
        if type(text) == "string" and text:match("^<.*>$") then
            hints = hints + 1
            local why = wrong(text)
            if why then
                bad[#bad + 1] = key .. " " .. why
            end
        end
    end
    table.sort(bad)
    eq(hints > 3, true, "hints: the locale's hints are found (" .. hints .. ")")
    eq(table.concat(bad, ", "), "", "hints: every click hint is written as Blizzard's are")

    -- The check itself, on strings with known answers.
    eq(wrong("<Ctrl click to set a map pin>"), nil, "hints: the right form passes")
    eq(wrong("<Ctrl+click to set a map pin>"), "has a plus", "hints: a plus is caught")
    eq(wrong("<Shift right-click to forget>"), "hyphenates the click", "hints: a hyphen is caught")
    eq(wrong("<Click to open.>"), "ends with a full stop", "hints: a full stop is caught")
    eq(wrong("Ctrl+click an icon to set a map pin."), nil, "hints: prose isn't a hint")
    eq(wrong("<Drag to move it>\n<Right click to put it back>"), nil, "hints: one click to a line passes")
    eq(wrong("<Drag to move it> <Right click to put it back>"), "has a line that isn't one hint in brackets",
        "hints: two clicks on a line are caught")
end
