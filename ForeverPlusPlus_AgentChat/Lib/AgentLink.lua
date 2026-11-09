-- AgentLink: how Agent Chat passes text to the Forever Agent program on the same PC. An addon can't
-- write files, but C_AddOns.SaveAddOns() writes the character's AddOns.txt at once. So the program
-- installs BITS helper addons, and a frame of text is which of them are on: helper i holds bit i,
-- least significant bit first, so helpers 0-7 are byte 1. A frame is FRAME bytes: a sequence number
-- (1-255; 0 only in the all-off idle frame that starts a session), a flags byte (FIRST, LAST, and the
-- payload's length), PAYLOAD bytes of the message, and a Fletcher-16 checksum (mod 255) of the rest.
-- The program reads each frame once by its sequence number and joins them from FIRST to LAST.
-- `agent/internal/link` in this repo reads the same format; change both together.
local ns = ForeverPlusPlusCompanion() -- Forever++'s own, as its files have (ForeverPlusPlus/Init.lua)

local floor, byte, sub = math.floor, string.byte, string.sub

local AgentLink = {}
ns.AgentLink = AgentLink

AgentLink.BITS = 256
AgentLink.FRAME = 32
AgentLink.PAYLOAD = 28

local PAYLOAD = AgentLink.PAYLOAD
local FIRST, LAST = 64, 128

---Fletcher-16 (mod 255) of `bytes[1..count]`.
---@param bytes number[]
---@param count number
---@return number a, number b
function AgentLink.Checksum(bytes, count)
    local a, b = 0, 0
    for i = 1, count do
        a = (a + bytes[i]) % 255
        b = (b + a) % 255
    end
    return a, b
end

---The sequence number after `seq`: 1 to 255, then 1 again.
---@param seq number
---@return number
function AgentLink.NextSeq(seq)
    return seq % 255 + 1
end

---The all-off frame that starts a session: sequence 0, no payload.
---@return number[]
function AgentLink.Idle()
    local frame = {}
    for i = 1, AgentLink.FRAME do
        frame[i] = 0
    end
    return frame
end

---A message as frames, numbered on from `seq`. An empty message is one empty frame.
---@param message string
---@param seq number the last sequence number sent
---@return number[][] frames
---@return number seq the last sequence number used
function AgentLink.Frames(message, seq)
    local frames, pos, length = {}, 1, #message
    repeat
        local chunk = sub(message, pos, pos + PAYLOAD - 1)
        pos = pos + PAYLOAD
        seq = AgentLink.NextSeq(seq)
        local flags = #chunk
        if #frames == 0 then
            flags = flags + FIRST
        end
        if pos > length then
            flags = flags + LAST
        end
        local frame = { seq, flags }
        for i = 1, PAYLOAD do
            frame[2 + i] = byte(chunk, i) or 0
        end
        frame[31], frame[32] = AgentLink.Checksum(frame, 30)
        frames[#frames + 1] = frame
    until pos > length
    return frames, seq
end

---Bit `index` (0 to BITS - 1) of a frame: 1 means that helper addon is on.
---@param frame number[]
---@param index number
---@return number
function AgentLink.Bit(frame, index)
    local value = frame[floor(index / 8) + 1]
    return floor(value / 2 ^ (index % 8)) % 2
end
