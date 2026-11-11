-- What changed in the generated files between two copies of the repo, as Markdown lines for a
-- pull request: entries added, removed, and changed per file, by each generator's Entry keys.
--
--   lua5.1 tools/datagen/summary.lua <old repo root> <new repo root>
--
-- Prints one line per file, then "data: changed" or "data: same" last, for the workflow to read.
local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local old, new = arg[1], arg[2]
if not old or not new then
    io.stderr:write("usage: summary.lua <old root> <new root>\n")
    os.exit(2)
end

local function entries(generator, path)
    local list, state = {}, {}
    local file = io.open(path, "rb")
    if not file then
        return list
    end
    for line in file:lines() do
        local key, value = generator.Entry(line:gsub("\r$", ""), state)
        if key then
            list[key] = value
        end
    end
    file:close()
    return list
end

local anyChange = false
for _, generator in ipairs(require("generators")) do
    local before = entries(generator, old .. "/" .. generator.path)
    local after = entries(generator, new .. "/" .. generator.path)
    local added, removed, changed = 0, 0, 0
    for key, value in pairs(after) do
        if before[key] == nil then
            added = added + 1
        elseif before[key] ~= value then
            changed = changed + 1
        end
    end
    for key in pairs(before) do
        if after[key] == nil then
            removed = removed + 1
        end
    end
    if added + removed + changed == 0 then
        print(("- `%s`: no data changes"):format(generator.path))
    else
        anyChange = true
        print(("- `%s`: %d added, %d removed, %d changed"):format(generator.path, added, removed,
            changed))
    end
end
print(anyChange and "data: changed" or "data: same")
