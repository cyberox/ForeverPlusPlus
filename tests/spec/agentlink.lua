-- AgentLink: text as frames of helper addon bits, for the Forever Agent program. The vectors here
-- are the same as agent/internal/link/frame_test.go, so both sides agree on the format.
local T = ...
local eq, same, ok = T.eq, T.same, T.ok

local ns = {}
T.load("Lib/AgentLink", ns)
local A = ns.AgentLink

local frames, seq = A.Frames("hello", 0)
eq(#frames, 1, "agentlink: a short message is one frame")
eq(seq, 1, "agentlink: numbered from 1")
same(frames[1], { 1, 197, 104, 101, 108, 108, 111, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 220, 174 }, "agentlink: hello")

frames, seq = A.Frames("P|a1b2|0|1|ping across two frames!", 0)
eq(#frames, 2, "agentlink: 34 bytes are two frames")
eq(seq, 2, "agentlink: one number per frame")
same(frames[1], { 1, 92, 80, 124, 97, 49, 98, 50, 124, 48, 124, 49, 124, 112, 105, 110, 103, 32, 97, 99,
    114, 111, 115, 115, 32, 116, 119, 111, 32, 102, 135, 90 }, "agentlink: first frame")
same(frames[2], { 2, 134, 114, 97, 109, 101, 115, 33, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 195, 20 }, "agentlink: last frame")

frames = A.Frames("", 0)
eq(#frames, 1, "agentlink: an empty message is one frame")
eq(frames[1][2], 64 + 128, "agentlink: first and last, no payload")

frames = A.Frames(string.rep("x", 28), 0)
eq(#frames, 1, "agentlink: exactly a payload fits one frame")
eq(frames[1][2], 64 + 128 + 28, "agentlink: full payload")

eq(A.NextSeq(254), 255, "agentlink: up to 255")
eq(A.NextSeq(255), 1, "agentlink: 0 is only for idle")
frames, seq = A.Frames("hi", 255)
eq(frames[1][1], 1, "agentlink: wraps to 1")

local idle = A.Idle()
eq(#idle, 32, "agentlink: idle is a whole frame")
local a, b = A.Checksum(idle, 30)
ok(a == idle[31] and b == idle[32], "agentlink: idle's checksum holds")

-- 197 = 11000101: bits 0, 2, 6 and 7 of byte 2 (helpers 8, 10, 14, 15).
local hello = A.Frames("hello", 0)[1]
eq(A.Bit(hello, 0), 1, "agentlink: bit 0 of seq 1")
eq(A.Bit(hello, 1), 0, "agentlink: bit 1 of seq 1")
eq(A.Bit(hello, 8), 1, "agentlink: helper 8")
eq(A.Bit(hello, 9), 0, "agentlink: helper 9")
eq(A.Bit(hello, 10), 1, "agentlink: helper 10")
eq(A.Bit(hello, 15), 1, "agentlink: helper 15")
eq(A.Bit(hello, 255), 1, "agentlink: last helper, the checksum's top bit (174)")
eq(A.Bit(hello, 254), 0, "agentlink: the one before it")
