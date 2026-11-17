-- The About page: what the addon is and how many modules are on across the top, with its version
-- and the game's at the right, then two columns. On the left the links (a button each, which
-- shows the link to copy), who wrote the addon, and the addons it works with; on the right every
-- command, under the module that adds it, with a search box. The Defaults button is at the top
-- right like the Modules page's. Built the first time it's shown; the module count and the
-- commands of the modules that are on are drawn again each time.
local _, ns = ...

local ipairs, format, floor, concat = ipairs, string.format, math.floor, table.concat
local CreateFrame, GetBuildInfo = CreateFrame, GetBuildInfo
local L = ns.L
local S = ns.SettingsUI

local LEFT = 16 -- the page's left margin
local EDGE = 32 -- and its right one, which leaves room for the scroll bar
local LEFT_WIDTH = 222 -- the links and credits column
local GUTTER = 28 -- between the columns, the line down its middle
local RIGHT = LEFT + LEFT_WIDTH + GUTTER -- where the commands column starts
local COLUMNS_TOP = -152
local HEADING = 30 -- a heading, the line under it, and the space before what it heads
local SECTION = 14 -- the space after a section, before the next heading
local LINK_WIDTH, LINK_GAP = 108, 6 -- two link buttons fill the left column

local WEBSITE = "https://github.com/xIGBClutchIx/ForeverPlusPlus"

local metadata = ns.Metadata

-- A link can't be opened from the game, so each is a button that shows it in a popup to copy.
local LINKS = {
    { L.HOME_LINK_CURSEFORGE, "https://www.curseforge.com/wow/addons/foreverplusplus" },
    { L.HOME_LINK_WAGO, "https://addons.wago.io/addons/foreverplusplus" },
    { L.HOME_LINK_RELEASES, WEBSITE .. "/releases" },
    { L.HOME_LINK_SOURCE, WEBSITE },
    { L.HOME_LINK_REQUEST, WEBSITE .. "/issues/new?template=feature_request.yml" },
    { L.HOME_LINK_BUG, WEBSITE .. "/issues/new?template=bug_report.yml" },
}

-- Who else wrote part of the addon, by the name they go by on GitHub, and what they added. Keep
-- it the same as the README's Contributors list.
local CREDITS = {
    { "cyberox", concat({ L.TOOLTIPS_QUEST_LINES, L.QUESTPINS_TITLE }, ", ") },
}

-- The other addons a module reads when the player has them, and what for.
local WORKS_WITH = {
    { "QuestieDB", format(L.HOME_QUEST_DATA, concat({ L.QUESTPINS_TITLE, L.QUESTNAMEPLATES_TITLE }, ", ")) },
    { "Auctionator", format(L.HOME_SUPPORT, L.AUCTIONPRICES_TITLE) },
    { "DungeonJournal", format(L.HOME_SUPPORT, L.POI_DUNGEON_MAPS) },
}

-- A faint line, `width` wide, like the one under a section of Blizzard's own pages.
local function addLine(frame, point, x, y, width)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetSize(width, 1)
    line:SetPoint(point, x, y)
    return line
end

-- A section's heading with a line under it, the width of its column.
local function addHeading(frame, x, y, text, width)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    heading:SetPoint("TOPLEFT", x, y)
    heading:SetText(text)
    addLine(frame, "TOPLEFT", x, y - 21, width)
    return heading
end

-- A gold name with a line about it underneath, in the left column. Returns the height it took.
local function addEntry(frame, y, name, text)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(name)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    line:SetWidth(LEFT_WIDTH)
    line:SetJustifyH("LEFT")
    line:SetText(text)
    return title:GetStringHeight() + 2 + line:GetStringHeight()
end

-- How many modules the player can turn on, and how many are on.
local function countModules()
    local on, total = 0, 0
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if not (module.unavailable or module.alwaysOn) then
            total = total + 1
            if module.enabled then -- not a locked one, whatever was saved
                on = on + 1
            end
        end
    end
    return on, total
end

-- The top of the page: the icon, the name, what the addon is, and how many modules are on, with
-- the addon's version and the game's at the right.
local function buildHeader(frame, pageWidth)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", LEFT, -66)
    icon:SetTexture(ns.icon)

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
    name:SetText(ns.title)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    version:SetPoint("TOPRIGHT", -EDGE, -70)
    version:SetText(ns.version)

    -- For a bug report: which game build this is.
    local gameVersion, build = GetBuildInfo()
    local game = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    game:SetPoint("TOPRIGHT", version, "BOTTOMRIGHT", 0, -5)
    game:SetText(format(L.HOME_GAME_BUILD, gameVersion, build))

    -- Wraps before it would run into the game's version.
    local tagline = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    tagline:SetJustifyH("LEFT")
    tagline:SetText(metadata("Notes") ~= "" and metadata("Notes") or L.HOME_TAGLINE)
    local room = pageWidth - (LEFT + 64 + 14) - EDGE - game:GetStringWidth() - 16
    if tagline:GetStringWidth() > room then
        tagline:SetWidth(room)
    end

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -6)
    local function update()
        status:SetText(format(L.HOME_MODULES_ON, countModules()))
    end
    update()
    frame:HookScript("OnShow", update) -- after /fpp or the Modules page changed some
end

-- The left column: links, credits, and the addons we work with.
local function buildLeft(frame)
    local y = COLUMNS_TOP
    addHeading(frame, LEFT, y, L.HOME_LINKS, LEFT_WIDTH)
    y = y - HEADING
    for i, link in ipairs(LINKS) do
        local column, row = (i - 1) % 2, floor((i - 1) / 2)
        local button = ns.SettingsKit.NewButton(frame, link[1], LINK_WIDTH, function()
            ns.Prompt("ABOUT_LINK", L.HOME_COPY, link[2])
        end)
        button:SetPoint("TOPLEFT", LEFT + column * (LINK_WIDTH + LINK_GAP), y - row * 26)
    end
    y = y - floor((#LINKS + 1) / 2) * 26 - 2
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", LEFT, y)
    hint:SetText(L.HOME_LINK_HINT)
    y = y - 12 - SECTION

    addHeading(frame, LEFT, y, L.HOME_CREDITS, LEFT_WIDTH)
    y = y - HEADING
    y = y - addEntry(frame, y, metadata("Author"), L.HOME_AUTHOR) - 8
    for _, credit in ipairs(CREDITS) do
        y = y - addEntry(frame, y, credit[1], credit[2]) - 8
    end
    -- And the players who report, fix, and suggest.
    y = y - addEntry(frame, y, L.HOME_EVERYONE, L.HOME_EVERYONE_THANKS) - 8
    y = y + 8 - SECTION

    addHeading(frame, LEFT, y, L.HOME_WORKS_WITH, LEFT_WIDTH)
    y = y - HEADING
    for _, addon in ipairs(WORKS_WITH) do
        y = y - addEntry(frame, y, addon[1], addon[2]) - 8
    end
end

-- A "|" would start an escape code in a font string, and a command's usage has them.
local function plain(text)
    return (text:gsub("|", "||"))
end

-- The right column: the commands, scrolling, under a search box.
local function buildCommands(frame, pageWidth)
    local width = pageWidth - RIGHT - EDGE
    addHeading(frame, RIGHT, COLUMNS_TOP, L.HOME_COMMANDS, width)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", RIGHT, 10)
    hint:SetText(ns.Keys.PadHint(L.HOME_COMMANDS_HINT))
    hint:SetTextColor(GREEN_FONT_COLOR:GetRGB())
    addLine(frame, "BOTTOMLEFT", RIGHT, 28, width)

    local scroll = ns.SettingsKit.NewScroll(frame)
    scroll:SetPoint("TOPLEFT", RIGHT, COLUMNS_TOP - HEADING)
    scroll:SetPoint("BOTTOMRIGHT", -EDGE, 34)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)

    -- A row per command: the command with what follows it in gray, and its description under
    -- it. Clicking one starts it in the chat box. Rows and group names are kept and reused.
    local rows, headers = {}, {}
    local query = ""

    local function newRow()
        local row = CreateFrame("Button", nil, content)
        row:SetWidth(width)
        local over = row:CreateTexture(nil, "HIGHLIGHT")
        over:SetAllPoints()
        over:SetColorTexture(1, 1, 1, 0.08)
        row.command = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.command:SetPoint("TOPLEFT", 8, -3)
        row.description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.description:SetPoint("TOPLEFT", row.command, "BOTTOMLEFT", 0, -1)
        for _, text in ipairs({ row.command, row.description }) do
            text:SetWidth(width - 16)
            text:SetJustifyH("LEFT")
        end
        row:SetScript("OnClick", function(self)
            local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
            local line = self.line
            if open and line then
                open(line.usage ~= "" and line.command .. " " or line.command)
            end
        end)
        return row
    end

    local function matches(line)
        return query == "" or (line[1] .. " " .. line[2]):lower():find(query, 1, true)
    end

    local function draw()
        -- The commands no module owns first, then each module's, in the order they were added.
        local groups, byOwner = {}, {}
        for _, line in ipairs(ns.Commands()) do
            if matches(line) then
                local key = line.owner or ""
                local group = byOwner[key]
                if not group then
                    local module = line.owner and ns.modules[line.owner]
                    group = { title = module and module.title or L.HOME_COMMANDS_GENERAL }
                    byOwner[key] = group
                    groups[#groups + 1] = group
                end
                group[#group + 1] = line
            end
        end

        local y, used = 0, 0
        for i, group in ipairs(groups) do
            local header = headers[i]
            if not header then
                header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                headers[i] = header
            end
            y = y - (i > 1 and 10 or 0)
            header:SetPoint("TOPLEFT", 0, y)
            header:SetText(group.title)
            header:Show()
            y = y - 14
            for _, line in ipairs(group) do
                used = used + 1
                local row = rows[used]
                if not row then
                    row = newRow()
                    rows[used] = row
                end
                row.line = line
                if line.usage ~= "" then
                    row.command:SetText(plain(line.command) .. " "
                        .. GRAY_FONT_COLOR:WrapTextInColorCode(plain(line.usage)))
                else
                    row.command:SetText(plain(line[1]))
                end
                row.description:SetText(line[2])
                local height = row.command:GetStringHeight() + row.description:GetStringHeight() + 7
                row:SetHeight(height)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y)
                row:Show()
                y = y - height
            end
        end
        for i = #groups + 1, #headers do
            headers[i]:Hide()
        end
        for i = used + 1, #rows do
            rows[i]:Hide()
        end
        content:SetHeight(-y > 1 and -y or 1)
    end

    -- On the heading's row, its right edge the column's.
    local box = ns.SettingsKit.AddSearchBox(frame, nil, L.HOME_COMMANDS_SEARCH, function(text)
        query = text:lower()
        draw()
    end)
    if box then
        box:ClearAllPoints()
        box:SetSize(150, 20)
        box:SetPoint("TOPRIGHT", -EDGE, COLUMNS_TOP + 3)
    end

    draw()
    frame:HookScript("OnShow", draw) -- after /fpp or the Modules page turned some on or off
end

---Draws the About page, the first time it's shown.
---@param frame table the empty page
function S.BuildAbout(frame)
    ns.SettingsKit.AddPageTitle(frame, L.ABOUT)
    -- The NEW tag on the Minimap Button can go. On every show, since Reset Welcome sets it again.
    ns.SetWelcome(false)
    frame:HookScript("OnShow", function() ns.SetWelcome(false) end)
    S.addPageDefaults(frame)

    local pageWidth = frame:GetWidth()
    pageWidth = pageWidth > 0 and pageWidth or 615

    buildHeader(frame, pageWidth)

    -- Down the middle of the gutter between the columns.
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", RIGHT - GUTTER / 2, COLUMNS_TOP)
    divider:SetPoint("BOTTOMLEFT", RIGHT - GUTTER / 2, 10)

    buildLeft(frame)
    buildCommands(frame, pageWidth)
end
