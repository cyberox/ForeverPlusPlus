-- The Changelog page: the release notes from Changelog.lua as a split page, like the Modules page:
-- the releases on the left (Unreleased first, then newest first) with their dates, and the selected
-- one's notes on the right. A release newer than the version the player last saw on the Modules
-- page gets the NEW label. Built the first time it's shown, on the newest.
local _, ns = ...

local ipairs, pairs, format, type, sort = ipairs, pairs, string.format, type, table.sort
local strlower, min, pcall = string.lower, math.min, pcall
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local L = ns.L
local S = ns.SettingsUI
local Kit = ns.SettingsKit
local newStack, addEntry, layoutStack = Kit.NewStack, Kit.AddEntry, Kit.Layout
local CATEGORY_NAMES, CATEGORY_RANKS = S.CATEGORY_NAMES, S.CATEGORY_RANKS
local newLabel = S.newLabel

local CHANGELOG_LIST_WIDTH = 140 -- the release list, narrower than the module list
local RULE_WIDTH = 260 -- the gold line under a section's heading

-- Whether a release is newer than the version the player last saw. Unreleased notes always are.
local function isNewRelease(release)
    return not release.date or ns.Text.NewerVersion(release.version, ns.db.seenVersion) and true
        or false
end

-- An item of noteGroups as it shows: its text, after its name in gold when it has one.
local function itemText(item)
    if item[2] then
        return format("|cffffd100%s|r: %s", item[2], item[3]) -- gold, like GameFontNormal
    end
    return item[3]
end

-- Whether the search (lowercased, nil for none) finds an entry, by its module's name or its text.
local function entryMatches(entry, search)
    if not search then
        return true
    end
    local text = type(entry) == "table" and format("%s: %s", entry[1], entry[2]) or entry
    return strlower(text):find(search, 1, true) ~= nil
end

-- How many of a release's entries the search finds (all of them without one).
local function countMatches(release, search)
    local count = 0
    for _, section in ipairs(release.sections) do
        for _, entry in ipairs(section[2]) do
            if entryMatches(entry, search) then
                count = count + 1
            end
        end
    end
    return count
end

-- A release's entries in the groups its notes show, `{ heading, items }`, where an item is
-- `{ entry, name, text }`: the entry from Changelog.lua and what shows of it, `name` in gold
-- before `text`. As written, the groups are its sections and the names its modules'. With
-- `byModule`, the groups are its modules', and the names the sections': first those of no one
-- module (General for entries without a name, then Settings), marked `apart`, then the modules'
-- by their `category` in the Modules page's order, and alphabetical within it. A name that's no
-- module's title now (a module since renamed or removed) goes under Other.
local function noteGroups(release, byModule)
    local groups, byName = {}, {}
    local apart = { [L.CHANGELOG_GENERAL] = 1, [L.CHANGELOG_SETTINGS] = 2 }
    local categories -- module title -> its category, made only with byModule
    if byModule then
        categories = {}
        for _, module in pairs(ns.modules) do
            if module.title then
                categories[module.title] = S.categoryOf(module)
            end
        end
    end
    for _, section in ipairs(release.sections) do
        local items = {}
        for _, entry in ipairs(section[2]) do
            local named = type(entry) == "table"
            if byModule then
                local heading = named and entry[1] or L.CHANGELOG_GENERAL
                local group = byName[heading]
                if not group then
                    group = { heading, {}, apart = apart[heading] }
                    if not group.apart then
                        group.category = categories[heading] or "other"
                    end
                    byName[heading] = group
                    groups[#groups + 1] = group
                end
                group[2][#group[2] + 1] = { entry, section[1], named and entry[2] or entry }
            else
                items[#items + 1] = { entry, named and entry[1], named and entry[2] or entry }
            end
        end
        if not byModule then
            groups[#groups + 1] = { section[1], items }
        end
    end
    if byModule then
        sort(groups, function(a, b)
            local x, y = a.apart or 3, b.apart or 3 -- the modules' after General and Settings
            if x ~= y then
                return x < y
            end
            if a.category ~= b.category then
                return CATEGORY_RANKS[a.category] < CATEGORY_RANKS[b.category]
            end
            return strlower(a[1]) < strlower(b[1])
        end)
    end
    return groups
end

-- "N changes" for a release's notes.
local function countText(count)
    return count == 1 and L.CHANGELOG_ONE_CHANGE or format(L.CHANGELOG_CHANGES, count)
end

-- Gold fading out to the right. Probe: SetGradient with colors is Mainline's; without it, a faint
-- gold line like the one between the list and the pane.
local function fadeGold(texture)
    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
    texture:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and texture.SetGradient and pcall(texture.SetGradient, texture,
        "HORIZONTAL", CreateColor(r, g, b, 0.45), CreateColor(r, g, b, 0))) then
        texture:SetColorTexture(r, g, b, 0.25)
    end
end

-- A release's row in the list: its version, the NEW label while it's new, and its date (MM-DD) in
-- gray at the right. Returns the row and an update for its label.
local function newReleaseRow(list, release, isSelected)
    local row = Kit.NewListButton(list, isSelected)
    local date = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    date:SetPoint("RIGHT", -6, 0)
    date:SetText(release.date and release.date:sub(6) or "")
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(release.version)
    local mark = newLabel(row, text, row:GetWidth() - 18 - ns.Text.Width(date))
    return row, function() mark(isNewRelease(release)) end
end

-- A release's notes, a stack: its title, the NEW label while it's new, and how many changes the
-- search finds, then each section's heading in gold over a fading gold line, and its entries after
-- a dash, their wrapped lines lined up after it and a module's name in gold. Only the entries the
-- search finds show, under their sections' headings. With `byModule`, the headings are the
-- modules' and the names in gold the sections' (noteGroups), with each category's name and a
-- gray line above its modules. `view.search(text)` lays it out for a search (lowercased, nil for
-- none), and `view.update` keeps its NEW label.
local function buildNotes(content, width, release, byModule)
    local view = newStack(content, width, 0)
    view:SetPoint("TOPLEFT")
    view.top, view.bottom = 4, 12
    local search

    local header = CreateFrame("Frame", nil, view)
    header:SetWidth(width)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    -- Unreleased notes have no date.
    title:SetText(release.date and format(L.CHANGELOG_RELEASE, release.version, release.date)
        or release.version)
    header:SetHeight(title:GetStringHeight())
    addEntry(view, header)
    local count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetText(countText(countMatches(release)))
    local mark = newLabel(header, title, width - 18 - ns.Text.Width(count))
    function view.update()
        local after = mark(isNewRelease(release))
        local x = min(ns.Text.Width(title), title:GetWidth()) + after + 10
        count:ClearAllPoints()
        count:SetPoint("LEFT", title, "LEFT", x, 0)
    end

    -- Whether the search finds one of a group's items.
    local function anyMatch(items)
        for _, item in ipairs(items) do
            if entryMatches(item[1], search) then
                return true
            end
        end
        return false
    end

    local groups = noteGroups(release, byModule)
    local previous
    for _, group in ipairs(groups) do
        local items = group[2]
        -- Before each category's modules, its name in gray and a gray line after it to the right
        -- edge, while the search finds something in one of them.
        local category = group.category
        if category and category ~= previous then
            local separator = CreateFrame("Frame", nil, view)
            local label = separator:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetPoint("LEFT", 4, 0)
            label:SetText(CATEGORY_NAMES[category])
            local line = separator:CreateTexture(nil, "ARTWORK")
            line:SetPoint("LEFT", label, "RIGHT", 6, 0)
            line:SetPoint("RIGHT", -4, 0)
            line:SetHeight(1)
            line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
            separator:SetSize(width, label:GetStringHeight())
            addEntry(view, separator, function()
                for _, other in ipairs(groups) do
                    if other.category == category and anyMatch(other[2]) then
                        return true
                    end
                end
                return false
            end, 18)
        end
        previous = category
        local top = CreateFrame("Frame", nil, view)
        top:SetWidth(width)
        local heading = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", 4, 0)
        heading:SetText(group[1])
        local rule = top:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 4, -heading:GetStringHeight() - 6)
        rule:SetSize(min(RULE_WIDTH, width - 8), 1)
        fadeGold(rule)
        top:SetHeight(heading:GetStringHeight() + 6 + 1 + 5)
        addEntry(view, top, function() return anyMatch(items) end, 18)
        for _, item in ipairs(items) do
            local row = CreateFrame("Frame", nil, view)
            row:SetWidth(width)
            local dash = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            dash:SetPoint("TOPLEFT", 12, 0)
            dash:SetText("-")
            local line = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", 24, 0)
            line:SetWidth(width - 28)
            line:SetJustifyH("LEFT")
            line:SetText(itemText(item))
            row:SetHeight(line:GetStringHeight())
            addEntry(view, row, function() return entryMatches(item[1], search) end, 8)
        end
    end

    function view.search(text)
        search = text
        count:SetText(countText(countMatches(release, search)))
        layoutStack(view)
    end
    return view
end

---Draws the Changelog page, the first time it's shown.
---@param frame table the empty page
function S.BuildChangelog(frame)
    Kit.AddPageTitle(frame, L.CHANGELOG)
    local split = Kit.NewSplit(frame, CHANGELOG_LIST_WIDTH)
    local releases = ns.changelog or {}
    local rows, updates = {}, {}
    local views = { [false] = {}, [true] = {} } -- by byModule, then release
    local shown -- the release on the right
    local search -- the search, lowercased, or nil while the box is empty

    local function matches(i)
        return countMatches(releases[i], search) > 0
    end

    -- Shows release `i` on the right (nil for none), laid out for the search and grouped as By
    -- Module says.
    local function show(i)
        shown = i
        local byModule = ns.db.changelogByModule ~= false
        for _, row in ipairs(rows) do
            Kit.Paint(row)
        end
        for mode, list in pairs(views) do
            for other, view in pairs(list) do
                view:SetShown(mode == byModule and other == i)
            end
        end
        if not i then
            split.paneContent:SetHeight(1)
            return
        end
        local view = views[byModule][i]
        if not view then
            view = buildNotes(split.paneContent, split.paneWidth, releases[i], byModule)
            views[byModule][i] = view
            updates[#updates + 1] = view.update
            view.update()
        end
        view.search(search)
        split.paneContent:SetHeight(view:GetHeight())
        split.pane:SetVerticalScroll(0)
    end

    -- "No changes match" while the search finds nothing.
    local empty = Kit.NewEmptyRow(split.list, CHANGELOG_LIST_WIDTH)
    addEntry(split.list, empty, function()
        for i in ipairs(releases) do
            if matches(i) then
                return false
            end
        end
        return true
    end)

    for i, release in ipairs(releases) do
        local row, update = newReleaseRow(split.list, release, function() return shown == i end)
        row:SetScript("OnClick", function()
            if shown ~= i then
                show(i)
            end
        end)
        rows[i] = row
        updates[#updates + 1] = update
        addEntry(split.list, row, function() return matches(i) end)
    end
    layoutStack(split.list)

    -- Defaults and the search box at the top, as on the Modules page. The list keeps the releases
    -- the search finds something in, and stays on the one shown while it's one of them, or else
    -- shows the first.
    local defaults = S.addPageDefaults(frame)
    local searchBox = Kit.AddSearchBox(frame, defaults, L.CHANGELOG_SEARCH, function(text)
        search = text ~= "" and strlower(text) or nil
        empty.text:SetText(format(L.CHANGELOG_NO_MATCH, text))
        layoutStack(split.list)
        if shown and matches(shown) then
            show(shown)
            return
        end
        local first
        for i in ipairs(releases) do
            if matches(i) then
                first = i
                break
            end
        end
        show(first)
    end)

    -- A By Module checkbox left of the search box, like the Modules page's New, that groups the
    -- notes on the right under their modules instead of Added, Changed, and Fixed. Saved for the
    -- account, on by default: ns.db.changelogByModule is false once it's unchecked, nil while on.
    local byModule = Kit.AddLabeledCheck(frame, searchBox or defaults, L.CHANGELOG_BY_MODULE,
        function(checked)
            if checked then
                ns.db.changelogByModule = nil
            else
                ns.db.changelogByModule = false
            end
            show(shown)
        end)
    byModule:SetChecked(ns.db.changelogByModule ~= false)

    -- The NEW labels follow the version last seen, which the Modules page moves on.
    local function refresh()
        for _, update in ipairs(updates) do
            update()
        end
    end
    refresh()
    if releases[1] then
        show(1)
    end
    -- Again a frame later: on the first visit the release with a NEW label stayed blank until the
    -- page was shown again, as if its text wasn't measured yet while the page was being built.
    if C_Timer then
        C_Timer.After(0, refresh)
    end
    frame:HookScript("OnShow", refresh)
end
