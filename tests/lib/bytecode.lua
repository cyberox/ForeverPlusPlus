-- The globals a Lua 5.1 file reads and writes, from its compiled bytecode (string.dump), with the
-- line of each. The same GETGLOBAL and SETGLOBAL instructions `luac -l` lists, read in plain Lua
-- so the tests need no luac. Only Lua 5.1's format (lundump.c) is read.
local Bytecode = {}

local byte, floor = string.byte, math.floor

local GETGLOBAL, SETGLOBAL, SETLIST = 5, 7, 34

-- A reader over the dumped string, with the header's sizes.
local function Reader(data)
    local pos = 1
    local r = {}

    function r.Bytes(n)
        local s = data:sub(pos, pos + n - 1)
        pos = pos + n
        return s
    end

    function r.Byte()
        pos = pos + 1
        return byte(data, pos - 1)
    end

    -- An unsigned integer of `size` bytes, in the header's byte order.
    function r.Uint(size)
        local n, s = 0, r.Bytes(size)
        if r.little then
            for i = size, 1, -1 do
                n = n * 256 + byte(s, i)
            end
        else
            for i = 1, size do
                n = n * 256 + byte(s, i)
            end
        end
        return n
    end

    function r.Int()
        return r.Uint(r.int)
    end

    function r.String()
        local length = r.Uint(r.size_t)
        if length == 0 then
            return nil
        end
        return r.Bytes(length):sub(1, -2) -- without its trailing \0
    end

    return r
end

local function Function(r, out, strings)
    r.String() -- source
    r.Int() -- linedefined
    r.Int() -- lastlinedefined
    r.Bytes(4) -- nups, numparams, is_vararg, maxstacksize
    local code = {}
    for i = 1, r.Int() do
        code[i] = r.Uint(r.instruction)
    end
    local constants = {}
    for i = 1, r.Int() do
        local kind = r.Byte()
        if kind == 1 then
            r.Byte()
        elseif kind == 3 then
            r.Bytes(r.number)
        elseif kind == 4 then
            constants[i - 1] = r.String()
            strings[constants[i - 1]] = true
        end
    end
    for _ = 1, r.Int() do
        Function(r, out, strings)
    end
    local lines = {}
    for i = 1, r.Int() do
        lines[i] = r.Int()
    end
    for _ = 1, r.Int() do -- local variables
        r.String()
        r.Int()
        r.Int()
    end
    for _ = 1, r.Int() do -- upvalue names
        r.String()
    end

    local i = 1
    while i <= #code do
        local op = code[i] % 64
        if op == GETGLOBAL or op == SETGLOBAL then
            out[#out + 1] = {
                name = constants[floor(code[i] / 16384)],
                line = lines[i] or 0,
                write = op == SETGLOBAL,
            }
        elseif op == SETLIST and floor(code[i] / 16384) % 512 == 0 then
            i = i + 1 -- C == 0: the next instruction is a number, not an instruction
        end
        i = i + 1
    end
end

---Every global access in a chunk, in no particular order, and the strings in its code (global
---names, table keys, and literals, but not comments).
---@param chunk function from loadfile
---@return table[] uses { name, line, write }
---@return table<string, true> strings
function Bytecode.Globals(chunk)
    local r = Reader(string.dump(chunk))
    assert(r.Bytes(4) == "\27Lua" and r.Byte() == 0x51, "not Lua 5.1 bytecode")
    r.Byte() -- format
    r.little = r.Byte() == 1
    r.int, r.size_t, r.instruction, r.number = r.Byte(), r.Byte(), r.Byte(), r.Byte()
    r.Byte() -- integral numbers
    local out, strings = {}, {}
    Function(r, out, strings)
    return out, strings
end

return Bytecode
