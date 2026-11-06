-- Release: what the release jobs and the Changelog page rely on agreeing. The TOC's version is the
-- newest release in Changelog.lua, CHANGELOG.md has the same releases in the same order with the
-- same dates, and every file the TOC loads is there.
local T = ...
local eq = T.eq

local fields, files = T.Toc()

-- Every file the TOC loads exists.
local absent = {}
for _, path in ipairs(files) do
    if not T.Read(T.ROOT .. path) then
        absent[#absent + 1] = path
    end
end
eq(#files > 100, true, "release: the TOC lists the addon's files")
eq(table.concat(absent, ", "), "", "release: every file the TOC loads is there")
eq(files[#files], "Init.lua", "release: Init.lua loads last")
eq(fields.SavedVariables, "ForeverPlusPlusDB, ForeverPlusPlusPlayersDB", "release: the saved variables")

-- Changelog.lua needs every module's title, so every enUS file goes in first.
for _, path in ipairs(files) do
    if path:match("^Locales/enUS/") then
        T.load((path:gsub("%.lua$", "")))
    end
end
T.load("Changelog")
local L, releases = T.ns.L, T.ns.changelog
eq(type(releases) == "table" and #releases > 0, true, "release: Changelog.lua has releases")

-- Its releases, newest first, as CHANGELOG.md heads them: "1.0.1 (2026-11-05)" or "Unreleased".
local inGame = {}
for i, release in ipairs(releases) do
    local unreleased = release.version == L.CHANGELOG_UNRELEASED
    inGame[i] = unreleased and "Unreleased" or (release.version .. " (" .. tostring(release.date) .. ")")
    eq(unreleased or (release.date or ""):match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, true,
        "release: " .. tostring(release.version) .. " has a date")
    eq(not unreleased or i == 1, true, "release: only the first can be unreleased")
    -- Each entry is a line of text, or a name (a module's title, from ns.L) and its text.
    local entries, odd = 0, 0
    for _, section in ipairs(release.sections or {}) do
        eq(type(section[1]), "string", "release: " .. tostring(release.version) .. " headings are text")
        for _, entry in ipairs(section[2]) do
            entries = entries + 1
            local fine = type(entry) == "string"
                or type(entry) == "table" and type(entry[1]) == "string" and type(entry[2]) == "string"
            odd = odd + (fine and 0 or 1)
        end
    end
    eq(entries > 0, true, "release: " .. tostring(release.version) .. " has notes")
    eq(odd, 0, "release: " .. tostring(release.version) .. "'s entries are text, or a name and text")
end

local markdown = {}
for heading in (T.Read("CHANGELOG.md") or ""):gmatch("\n## ([^\r\n]+)") do
    markdown[#markdown + 1] = heading
end
eq(table.concat(markdown, " | "), table.concat(inGame, " | "),
    "release: CHANGELOG.md and Changelog.lua have the same releases")

-- The TOC's version is the newest release, so a tag on it finds its notes.
local newest = releases[1].version == L.CHANGELOG_UNRELEASED and releases[2] or releases[1]
eq(fields.Version, newest and newest.version, "release: the TOC's version is the newest release")
