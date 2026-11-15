-- wowlua-ls against its baseline: fails on a finding the baseline doesn't have, so only new
-- problems break the build, and on one it has that's gone, so the baseline keeps up with fixes.
-- From the repo root, with `wowlua_ls check .` written to a file:
--
--   lua tests/wowlua.lua out.txt            compare
--   lua tests/wowlua.lua out.txt --update   write the baseline from it
--
-- A finding is its file, code, and message, without the line, so editing a file elsewhere doesn't
-- move it. The baseline lists each with how many times it's there; fixing one shrinks it, and the
-- run fails saying to drop it. Its comments say why the findings under them stay; an update keeps
-- them, and puts a new finding in a group of its own at the end. See tests/README.md.

local BASELINE = "tests/wowlua-baseline.txt"

local input, update = arg[1], arg[2] == "--update"
assert(input, "usage: lua tests/wowlua.lua <wowlua_ls check output> [--update]")

local found, order, checked = {}, {}, false
for line in io.lines(input) do
    line = line:gsub("\r$", "")
    if line:match("^Checked %d+ files") then
        checked = true
    end
    local path, row, kind, code, message = line:match("^(.-):(%d+):%d+: (%a+)%[([%w%-]+)%] (.*)$")
    if path then
        local key = ("%s: %s[%s] %s"):format(path:gsub("\\", "/"), kind, code, message)
        if not found[key] then
            found[key] = { count = 0, lines = {} }
            order[#order + 1] = key
        end
        found[key].count = found[key].count + 1
        found[key].lines[#found[key].lines + 1] = row
    end
end
if not checked then
    print("wowlua-ls didn't finish a check (no \"Checked N files\" line in " .. input .. ").")
    os.exit(1)
end
table.sort(order)

-- The baseline: each finding's count, and the groups it's written in. A group is the "#" lines
-- saying why its findings stay, then the findings; a blank line ends it. The first "#" lines, with
-- no findings under them, are the file's header.
local UNSORTED = "# Not sorted yet: move each under the comment that says why it stays, or fix it."
local known, groups, group = {}, {}, nil
local baseline = io.open(BASELINE, "rb")
if baseline then
    for line in baseline:lines() do
        line = line:gsub("\r$", "")
        local count, key = line:match("^(%d+)\t(.*)$")
        if count then
            known[key] = tonumber(count)
            if not group then
                group = { why = {}, keys = {} }
                groups[#groups + 1] = group
            end
            group.keys[key], group.any = true, true
        elseif line:match("^#") then
            if not group or group.any then
                group = { why = {}, keys = {} }
                groups[#groups + 1] = group
            end
            group.why[#group.why + 1] = line
        else
            group = nil
        end
    end
    baseline:close()
end

if update then
    local file = assert(io.open(BASELINE, "wb"))
    local header = groups[1] and not groups[1].any and table.remove(groups, 1)
    for _, line in ipairs(header and header.why or {
        "# wowlua-ls findings known when this was written (tests/wowlua.lua --update), under why each",
        "# stays.",
        "# count<TAB>file: severity[code] message",
    }) do
        file:write(line, "\n")
    end
    -- Each group again with the findings still there, then the new ones in a group of their own.
    local placed, unsorted = {}, 0
    local function write(why, has)
        local wrote = false
        for _, key in ipairs(order) do
            if not placed[key] and has(key) then
                if not wrote then
                    file:write("\n")
                    for _, line in ipairs(why) do
                        file:write(line, "\n")
                    end
                    wrote = true
                end
                placed[key] = true
                file:write(found[key].count, "\t", key, "\n")
            end
        end
    end
    for _, entry in ipairs(groups) do
        write(entry.why, function(key) return entry.keys[key] end)
    end
    for _, key in ipairs(order) do
        unsorted = unsorted + (placed[key] and 0 or 1)
    end
    write({ UNSORTED }, function() return true end)
    file:close()
    print(("Wrote %d findings to %s%s."):format(#order, BASELINE,
        unsorted > 0 and (", %d not sorted yet"):format(unsorted) or ""))
    os.exit(0)
end

local new, gone = {}, {}
for _, key in ipairs(order) do
    local extra = found[key].count - (known[key] or 0)
    if extra > 0 then
        new[#new + 1] = ("%s (line %s)"):format(key, table.concat(found[key].lines, ", "))
    end
end
for key, count in pairs(known) do
    if (found[key] and found[key].count or 0) < count then
        gone[#gone + 1] = key
    end
end
table.sort(gone)

if #gone > 0 then
    print("Fixed, so drop from " .. BASELINE .. " (or run with --update):")
    for _, key in ipairs(gone) do
        print("  " .. key)
    end
end
if #new > 0 then
    print("New wowlua-ls findings:")
    for _, key in ipairs(new) do
        print("  " .. key)
    end
end
print(("%d findings, %d new, %d fixed."):format(#order, #new, #gone))
os.exit((#new == 0 and #gone == 0) and 0 or 1)
