-- Which of Blizzard's stored values an addon wrote. A value written while addon code runs keeps
-- that addon's name, and whatever of Blizzard's reads it next runs as that addon's from then on,
-- so the game refuses what only its own code may do. The refusal comes later and names only the
-- read; what caused it is the write. A watcher checks a list of tables again and again and notes
-- each value the first time it carries an addon's name, with the time, so the write can be found.
--
-- issecurevariable only asks who wrote a value: nothing of Blizzard's is called or written, and
-- reading a table's keys taints nothing. Error Catcher watches the controller's tables this way,
-- and Taint Watcher the windows a tainted value breaks most.
local _, ns = ...

local pairs, ipairs, type, tostring, pcall, rawget = pairs, ipairs, type, tostring, pcall, rawget
local setmetatable = setmetatable
local concat = table.concat
local time, _G = time, _G

local Taint = {}
ns.Taint = Taint

local MAX_KEYS = 6000 -- values asked about in one check at most
local MAX_NOTES = 300 -- notes kept; a report groups them

local Watcher = {}
Watcher.__index = Watcher

---A watcher over `roots`. Each root is `{ name, depth }`: a global table's name and how many
---tables deep to look. A root with `tables` (a function giving `{ [name] = table }`) is for
---tables that aren't globals, each looked at `depth` deep. Frames are never gone into from
---another table: a frame's fields are its children, which is most of the interface.
---@param roots table[]
---@param opts? { context: (fun(): string|nil)?, only: string? } `context` is kept with each note; `only` notes just that addon's values
---@return table watcher
function Taint.New(roots, opts)
    return setmetatable({
        roots = roots,
        context = opts and opts.context,
        only = opts and opts.only,
        notes = {}, -- { path, by, time, context }, in the order found
        noted = setmetatable({}, { __mode = "k" }), -- table -> the keys of it already noted
        visited = {},
        trail = {},
        asked = 0,
    }, Watcher)
end

local function note(self, tbl, key, by, depth)
    if not ns.IsText(by, true) then
        by = nil -- hidden, or written by no addon the game names
    end
    if self.only and by ~= self.only then
        return
    end
    local keys = self.noted[tbl]
    if not keys then
        keys = {}
        self.noted[tbl] = keys
    end
    if keys[key] or #self.notes >= MAX_NOTES then
        return
    end
    keys[key] = true
    local trail = self.trail
    trail[depth] = tostring(key)
    local path = concat(trail, ".", 1, depth)
    -- A binding set or binding says whose it is in its `name` ("TabIndicatorBindings").
    local name = rawget(tbl, "name")
    if ns.IsText(name, true) then
        path = path .. " [" .. name .. "]"
    end
    local context = self.context
    self.notes[#self.notes + 1] = {
        path = path,
        by = by,
        time = time(),
        context = context and context() or nil,
    }
end

local function scan(self, tbl, depth, deepest, secureOf)
    if self.visited[tbl] then
        return
    end
    self.visited[tbl] = true
    for key, value in pairs(tbl) do
        if self.asked >= MAX_KEYS then
            return
        end
        local kind = type(key)
        if kind == "string" or kind == "number" then
            self.asked = self.asked + 1
            -- It takes a name, so a list's own entries can't be asked about; the list can.
            if kind == "string" then
                local ok, secure, by = pcall(secureOf, tbl, key)
                if ok and secure == false then
                    note(self, tbl, key, by, depth)
                end
            end
            if depth < deepest and type(value) == "table" and not value.GetObjectType then
                self.trail[depth] = tostring(key)
                scan(self, value, depth + 1, deepest, secureOf)
            end
        end
    end
end

local function scanRoot(self, name, tbl, depth, secureOf)
    if type(tbl) == "table" then
        self.trail[1] = name
        pcall(scan, self, tbl, 2, depth + 1, secureOf)
    end
end

---Notes every value in the watched tables that an addon wrote and wasn't noted before.
---@return number found how many notes this check added
function Watcher:Check()
    local secureOf = _G.issecurevariable
    if not secureOf then
        return 0
    end
    local before = #self.notes
    self.visited = {}
    self.asked = 0
    self.since = self.since or time()
    for _, root in ipairs(self.roots) do
        local depth = root[2] or 1
        if root.tables then
            local ok, tables = pcall(root.tables)
            if ok and type(tables) == "table" then
                for name, tbl in pairs(tables) do
                    scanRoot(self, tostring(name), tbl, depth, secureOf)
                end
            end
        else
            scanRoot(self, root[1], _G[root[1]], depth, secureOf)
        end
    end
    self.visited = {}
    return #self.notes - before
end

---Forgets what was noted, so the next check notes it all again. `only` changes whose values
---are noted from then on.
---@param only? string
function Watcher:Reset(only)
    self.only = only
    self.notes = {}
    self.noted = setmetatable({}, { __mode = "k" })
    self.since = nil
end

---Notes as a report's lines: a table whose every entry was written at once (the binding stack's
---forty buttons) is one group, its first note and how many more beside it.
---@param notes table[]
---@param from? number the first note to group, to group only the newest
---@return { note: table, more: number }[]
function Taint.Groups(notes, from)
    local groups, order = {}, {}
    for i = from or 1, #notes do
        local found = notes[i]
        local parent = found.path:match("^(.*)%.[^.]*$") or found.path
        parent = parent .. (found.path:match("( %[.*%])$") or "")
        local id = concat({ parent, found.by or "", found.time, found.context or "" }, "\1")
        local group = groups[id]
        if group then
            group.more = group.more + 1
        else
            group = { note = found, more = 0 }
            groups[id] = group
            order[#order + 1] = group
        end
    end
    return order
end
