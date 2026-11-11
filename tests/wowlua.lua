-- wowlua-ls against its baseline: fails on a finding the baseline doesn't have, so only new
-- problems break the build. From the repo root, with `wowlua_ls check .` written to a file:
--
--   lua tests/wowlua.lua out.txt            compare
--   lua tests/wowlua.lua out.txt --update   write the baseline from it
--
-- A finding is its file, code, and message, without the line, so editing a file elsewhere doesn't
-- move it. The baseline lists each with how many times it's there; fixing one shrinks it, and the
-- run says to drop it. See tests/README.md.

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

if update then
    local file = assert(io.open(BASELINE, "wb"))
    file:write("# wowlua-ls findings known when this was written (tests/wowlua.lua --update).\n")
    file:write("# count<TAB>file: severity[code] message\n")
    for _, key in ipairs(order) do
        file:write(found[key].count, "\t", key, "\n")
    end
    file:close()
    print(("Wrote %d findings to %s."):format(#order, BASELINE))
    os.exit(0)
end

local known = {}
for line in io.lines(BASELINE) do
    line = line:gsub("\r$", "")
    local count, key = line:match("^(%d+)\t(.*)$")
    if count then
        known[key] = tonumber(count)
    end
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
