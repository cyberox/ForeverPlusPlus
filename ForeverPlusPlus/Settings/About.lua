-- The About page: what the addon is, how many modules are on, links, and the /fpp commands, with
-- the Defaults button at the top right like the Modules page. Built the first time it's shown; the
-- module count and the commands of the modules that are on update each time.
local _, ns = ...

local ipairs, format, max = ipairs, string.format, math.max
local CreateFrame, GameTooltip, GetBuildInfo = CreateFrame, GameTooltip, GetBuildInfo
local L = ns.L
local S = ns.SettingsUI

local COMMAND_WIDTH = 234 -- the command column, before its description

local WEBSITE = "https://github.com/xIGBClutchIx/ForeverPlusPlus"
local ISSUES = WEBSITE .. "/issues"

local metadata = ns.Metadata

-- A gold label at the left of a row, for a value beside it.
local function addLabel(frame, y, text)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 16, y)
    label:SetWidth(110)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

-- A link can't be clicked in the game, so it sits in a read-only box, selected on click, to copy.
local function addLink(frame, y, label, url)
    local left = addLabel(frame, y, label)
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(360, 20)
    box:SetPoint("LEFT", left, "RIGHT", 14, 0)
    box:SetAutoFocus(false)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Typing can't change it.
    box:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(url)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.HOME_COPY, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function addHeading(frame, y, text)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    heading:SetPoint("TOPLEFT", 16, y)
    heading:SetText(text)
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

function S.BuildAbout(frame)
    ns.SettingsKit.AddPageTitle(frame, L.ABOUT)
    -- The NEW tag on the Minimap Button can go. On every show, since Reset Welcome sets it again.
    ns.SetWelcome(false)
    frame:HookScript("OnShow", function() ns.SetWelcome(false) end)
    S.addPageDefaults(frame)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", 16, -64)
    icon:SetTexture(ns.icon)

    local welcome = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    welcome:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)
    welcome:SetText(format(L.HOME_WELCOME, ns.title))

    local tagline = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT", welcome, "BOTTOMLEFT", 0, -6)
    tagline:SetText(metadata("Notes") ~= "" and metadata("Notes") or L.HOME_TAGLINE)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -6)
    version:SetText(format(L.HOME_VERSION, ns.version, metadata("Author")))

    -- Under the version, since the command list below grows with every module.
    local gameVersion, build, _, interface = GetBuildInfo()
    local game = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    game:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -2)
    game:SetText(format(L.HOME_GAME_BUILD, gameVersion, build, interface))

    local y = -144
    local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 16, y)
    intro:SetWidth(560)
    intro:SetJustifyH("LEFT")
    intro:SetText(L.HOME_INTRO)
    y = y - intro:GetStringHeight() - 14

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", 16, y)
    local function update()
        status:SetText(format(L.HOME_MODULES_ON, countModules()))
    end
    update()
    frame:HookScript("OnShow", update) -- after /fpp or the Modules page changed some

    y = y - 52
    addHeading(frame, y, L.HOME_LINKS)
    y = y - 26
    addLink(frame, y, L.HOME_WEBSITE, WEBSITE)
    y = y - 24
    addLink(frame, y, L.HOME_ISSUES, ISSUES)
    y = y - 22
    local requests = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    requests:SetPoint("TOPLEFT", 16, y)
    requests:SetText(L.HOME_REQUESTS)

    y = y - 30
    addHeading(frame, y, L.HOME_COMMANDS)
    y = y - 24
    -- The commands scroll in the rest of the page: every module adds its own, so they outgrow it.
    local scroll = ns.SettingsKit.NewScroll(frame)
    scroll:SetPoint("TOPLEFT", 16, y)
    scroll:SetPoint("BOTTOMRIGHT", -32, 8)
    local width = frame:GetWidth()
    width = (width > 0 and width or 615) - 48
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)

    -- A row per command of a module that's on, so drawn again each time the page shows. Rows
    -- are kept and reused; the ones past the list are hidden. A long description wraps.
    local rows = {}
    local function drawCommands()
        local lines = ns.Commands()
        local rowY = 0
        for i, line in ipairs(lines) do
            local row = rows[i]
            if not row then
                row = {
                    command = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                    description = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"),
                }
                row.description:SetWidth(width - COMMAND_WIDTH)
                row.description:SetJustifyH("LEFT")
                rows[i] = row
            end
            row.command:SetPoint("TOPLEFT", 0, rowY)
            row.description:SetPoint("TOPLEFT", COMMAND_WIDTH, rowY)
            row.command:SetText(line[1])
            row.description:SetText(line[2])
            row.command:Show()
            row.description:Show()
            rowY = rowY - max(16, row.description:GetStringHeight() + 4)
        end
        for i = #lines + 1, #rows do
            rows[i].command:Hide()
            rows[i].description:Hide()
        end
        content:SetHeight(max(1, -rowY))
    end
    drawCommands()
    frame:HookScript("OnShow", drawCommands)
end
