-- ProfileShare: a profile as a line of text and back, and what an import may hold.
local T = ...
local ns, eq, same, ok = T.ns, T.eq, T.same, T.ok

ns.AddCommand = function() end
ns.OptionKind = function(option) -- as Core's
    if option.choices then return "dropdown" elseif option.min then return "slider" end
    return "checkbox"
end
ns.version = "1.6.0"
ns.modules = {
    Win = { name = "Win", defaults = { enabled = false, size = 10, mode = "a", loud = false, x = 0,
        coords = false, positions = {}, prices = {} },
        options = {
            { key = "size", min = 5, max = 20, step = 1 },
            { key = "mode", choices = { { "a" }, { "b" } } },
            { key = "loud" },
            { key = "coords", cvar = "showCoords" },
        },
        perProfile = { positions = true } },
    Tool = { name = "Tool", alwaysOn = true, defaults = { enabled = true } },
}
T.load("Lib/Profiles")
T.load("Lib/ProfileShare")
local Share = ns.ProfileShare

-- Serializing round-trips, and refuses what isn't well formed.
local value = { a = 1, b = "x:y{}", c = { true, false, 2.5 }, [3] = "three" }
same(Share.Parse(Share.Serialize(value)), value, "share: serialize and parse round-trip")
eq(Share.Serialize({ b = 1, a = 2 }), Share.Serialize({ a = 2, b = 1 }), "share: the same table makes the same text")
eq(Share.Parse("{s1:a"), nil, "share: a cut-off table")
eq(Share.Parse("s9:ab"), nil, "share: a string longer than the text")
eq(Share.Parse("n12;t"), nil, "share: text after the value")
eq(Share.Parse("nabc;"), nil, "share: a number that isn't one")
eq(Share.Parse(("{"):rep(50) .. ("}"):rep(50)), nil, "share: too deep")

-- Plain text (no C_EncodingUtil) round-trips, with only safe characters.
local settings = { Win = { enabled = true, size = 12, mode = "b" } }
local data = { Win = { positions = { Bags = { "TOP", "TOP", 1, -2 } } } }
local text = Share.Encode("Raid |cffff0000Night|r", settings, data)
eq(text:sub(1, 5), "FPP1:", "share: plain text has its version prefix")
eq(text:find("[^%w%p]") == nil and text:find("|", 1, true) == nil, true, "share: plain text is one safe line")
local raw = Share.Decode(text)
same(raw.s, settings, "share: settings come back")
same(raw.d, data, "share: data comes back")
local profile = Share.Validate(raw)
eq(profile.name, "Raid Night", "share: an imported name loses its codes")
eq(profile.addon, "1.6.0", "share: the version it was made with")
eq(profile.modulesOn .. "," .. profile.changed, "1,2", "share: counts for the Import popup")

-- Compressed when the client can.
C_EncodingUtil = {
    CompressString = function(s) return "Z" .. s end,
    DecompressString = function(s) return s:sub(2) end,
    EncodeBase64 = function(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end,
    DecodeBase64 = function(s) return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end,
}
local packed = Share.Encode("Raid", settings, data)
eq(packed:sub(1, 6), "FPP1z:", "share: compressed text has its own prefix")
same(Share.Decode(packed).s, settings, "share: compressed text round-trips")
ok(Share.Decode(text), "share: plain text still reads with compression there")
C_EncodingUtil = nil
local _, why = Share.Decode(packed)
eq(why, ns.L.PROFILES_IMPORT_CANT, "share: compressed text without the client's codec says so")

-- Bad text.
eq(select(2, Share.Decode("hello")), ns.L.PROFILES_IMPORT_BAD, "share: text that isn't a profile")
eq(select(2, Share.Decode("FPP1:%zz")), ns.L.PROFILES_IMPORT_BAD, "share: a broken escape")
eq(select(2, Share.Decode("FPP1:" .. Share.Serialize({ v = 9 }))), ns.L.PROFILES_IMPORT_NEWER,
    "share: a newer version is refused")

-- A hand-edited import: only known modules, declared settings of the right kind, and profile data.
local evil = Share.Validate({ v = 1, name = "|Hitem:1|h[x]|h|T1:0|t%s", addon = "1.6|cff", s = {
    Win = { enabled = "yes", size = 99, mode = "z", loud = true, x = "far", coords = true, junk = 1,
        positions = { a = 1 } },
    Gone = { enabled = true },
    Tool = { enabled = false },
}, d = {
    Win = { positions = { Bags = { "TOP|cffff0000", 0 / 0, 3, { { { { { "deep" } } } } } }, Map = "x" },
        prices = { a = 1 } },
    Gone = { list = {} },
} })
same(evil.settings, { Win = { loud = true } }, "share: only fitting settings of known modules stay")
eq(evil.name, "[x]s", "share: a name loses links, textures and %")
eq(evil.addon, "1.6cff", "share: the version loses what isn't one")
eq(evil.data.Win.prices, nil, "share: data that isn't the profile's is dropped")
eq(evil.data.Gone, nil, "share: data of an unknown module is dropped")
same(evil.data.Win.positions.Bags[1], "TOP", "share: strings in data lose codes")
eq(evil.data.Win.positions.Bags[2], nil, "share: not-a-number is dropped")
eq(Share.Validate({ v = 1, name = "", s = "x" }).name, ns.L.PROFILES_IMPORTED, "share: an empty name gets one")
eq(Share.Validate({ v = 1, s = { Win = { size = 20, mode = "a", x = 5 } } }).settings.Win.x, 5,
    "share: a setting without an option keeps its default's type")
