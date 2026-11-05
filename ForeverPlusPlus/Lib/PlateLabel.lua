-- The label friendly nameplate modules draw in place of Blizzard's name while the bar is hidden:
-- the name centered on the plate at the bar's height, a "<Subtitle>" line under it (a guild or an
-- NPC's title), the level beside it, and for players the group and friend icons. While the bar is
-- up, a second name of ours sits centered above the bar (Blizzard's stays hidden, since it sits at
-- the bar's left), with the icons after it and the subtitle under the bar.
--
-- A plate module decides what goes in the label through a `style` (see ns.FriendlyPlates):
--   style.db               its settings: level ("before"/"after"/"off"), nameSize (a percent of
--                          Blizzard's name size), centerLine, and for the icons
--                          socialIcons, groupIcon ("role"/"looking"), iconSide
--                          ("after"/"before" the name) and testIcons
--   style.NameColor(unit)  r, g, b for the name
--   style.BarNameColor(unit)  r, g, b for the name while the bar is up (optional; NameColor)
--   style.Subtitle(unit)   the subtitle text (nil for none; may be secret) and when it shows:
--                          "always", "hidden" (only without the bar), or "off"
--   style.SubtitleColor(unit)  { r, g, b }
--   style.icons            true to show the group, friend, and recent ally icons
--   style.ShowAllyIcon(unit)  whether this unit gets the recent ally icon (optional)
--   style.classIcons       true to show the class icon where db.classIcon says ("off"/"before"/
--                          "after"): next to the name, inside the level and the other icons
--   style.Alpha(unit)      how opaque the name and what's beside it are, 0 to 1 (optional; 1)
-- Labels are kept per Blizzard unit frame and shared by every module, since plates are pooled.
local _, ns = ...

local pairs, ipairs, setmetatable, unpack, floor = pairs, ipairs, setmetatable, unpack, math.floor
local type, lower = type, string.lower
local CreateFrame, UnitLevel, UnitClass = CreateFrame, UnitLevel, UnitClass
local UnitGroupRolesAssigned, GetTexCoordsForRoleSmallCircle =
    UnitGroupRolesAssigned, GetTexCoordsForRoleSmallCircle

local readable = ns.IsReadable
local Units, Nameplates = ns.Units, ns.Nameplates

local L = ns.L

local PlateLabel = {}
ns.PlateLabel = PlateLabel

-- Dropdown choices for the settings every plate module has.
PlateLabel.LEVEL_CHOICES = {
    { "before", L.PLATES_LEVEL_BEFORE },
    { "after", L.PLATES_LEVEL_AFTER },
    { "off", L.PLATES_LEVEL_OFF },
}
-- Where Blizzard's buff row sits while the bar is hidden (FriendlyPlates places it).
PlateLabel.BUFF_CHOICES = {
    { "above", L.PLATES_BUFFS_ABOVE },
    { "before", L.PLATES_BUFFS_BEFORE },
    { "after", L.PLATES_BUFFS_AFTER },
    { "blizzard", L.PLATES_BUFFS_BLIZZARD },
}
PlateLabel.SUBTITLE_CHOICES = {
    { "always", L.PLATES_SUBTITLE_ALWAYS },
    { "hidden", L.PLATES_SUBTITLE_HIDDEN },
    { "off", L.PLATES_SUBTITLE_OFF },
}

---The Name Size slider every plate module has (setting `nameSize`, a percent). A new table each
---call, so each module's list has its own.
---@param section? string the Settings section it goes under
---@return table option
function PlateLabel.NameSizeOption(section)
    return {
        key = "nameSize", name = L.PLATES_NAME_SIZE, description = L.PLATES_NAME_SIZE_DESC,
        min = 50, max = 200, step = 10, format = "%d%%", section = section,
    }
end

local GAP = 3 -- pixels between the name, the level, and the icons
local SUBTITLE_SCALE = 0.9 -- the subtitle is a touch smaller than the name

-- Icons ---------------------------------------------------------------------------------------
-- Friends get the Battle.net logo; group members get their role, or the Looking for Group icon;
-- recent allies get the icon Blizzard's Recent Allies tab uses.

-- `round` crops a spell-style icon round, like a minimap button; `role` picks that role from
-- Blizzard's round role icons; `atlas` is an atlas, the first of the list this client has.
local ART = {
    ally = { atlases = { "friendslist-recentallies-yellow", "friendslist-recentallies" } },
    battlenet = { file = "Interface\\FriendsFrame\\Battlenet-Battleneticon" },
    looking = { file = "Interface\\Icons\\INV_Misc_GroupLooking", round = true },
    TANK = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", role = "TANK" },
    HEALER = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", role = "HEALER" },
    DAMAGER = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", role = "DAMAGER" },
}
local ORDER = { "group", "friend", "ally" }
local ICON_SCALE = 1.4 -- icon size against the name's font size
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Which art an icon uses for this unit.
local function artFor(kind, unit, db)
    if kind == "friend" then
        return "battlenet"
    elseif kind == "ally" then
        return "ally"
    end
    if db.groupIcon ~= "looking" then
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
        -- No role (or not in a group, while testing) falls back to the LFG icon.
        return readable(role) and ART[role] and role or "looking"
    end
    return "looking"
end

-- The first of an art's atlases this client has (probed: atlas names change between builds).
local function findAtlas(art)
    if art.atlas == nil then
        art.atlas = ns.Frames.FirstAtlas(unpack(art.atlases)) or false
    end
    return art.atlas
end

-- Sets an icon's art; only does the work when it changed.
local function setArt(icon, key)
    if icon.art == key then
        return
    end
    icon.art = key
    local art = ART[key]
    if art.atlases then
        local atlas = findAtlas(art)
        if atlas then
            icon:SetAtlas(atlas, false)
        else
            icon:SetTexture(nil)
        end
        icon:SetTexCoord(0, 1, 0, 1)
    else
        icon:SetTexture(art.file)
        if art.role and GetTexCoordsForRoleSmallCircle then
            icon:SetTexCoord(GetTexCoordsForRoleSmallCircle(art.role))
        elseif art.round then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    if art.round and not icon.masked then
        icon:AddMaskTexture(icon.mask)
        icon.masked = true
    elseif not art.round and icon.masked then
        icon:RemoveMaskTexture(icon.mask)
        icon.masked = false
    end
end

local function shouldShow(kind, unit, style)
    local db = style.db
    if kind == "ally" then
        return style.icons and style.ShowAllyIcon and style.ShowAllyIcon(unit) or false
    end
    if not (style.icons and db.socialIcons) then
        return false
    end
    if db.testIcons == kind then
        return true
    end
    if kind == "group" then
        return Units.InGroup(unit)
    end
    return Units.IsFriend(unit)
end

-- One set of icons (hidden) on `parent`: kind -> texture.
local function createIcons(parent)
    local icons = {}
    for _, kind in ipairs(ORDER) do
        local icon = parent:CreateTexture(nil, "OVERLAY")
        icon.mask = parent:CreateMaskTexture()
        icon.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon.mask:SetAllPoints(icon)
        icon:Hide()
        icons[kind] = icon
    end
    return icons
end

-- Shows the icons this unit gets, in a row going away from `anchor` (leftward when `left`), and
-- returns the width they take.
local function placeIcons(icons, anchor, left, fontSize, unit, style)
    local size = fontSize * ICON_SCALE
    local previous, width = anchor, 0
    for _, kind in ipairs(ORDER) do
        local icon = icons[kind]
        local show = shouldShow(kind, unit, style)
        icon:ClearAllPoints()
        if show then
            setArt(icon, artFor(kind, unit, style.db))
            icon:SetSize(size, size)
            if left then
                icon:SetPoint("RIGHT", previous, "LEFT", -GAP, 0)
            else
                icon:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
            end
            previous = icon
            width = width + size + GAP
        end
        icon:SetShown(show)
    end
    return width
end

-- The class icon: Blizzard's round class art, the same size as the other icons. Probe: atlas
-- names change between builds; the first this client has, or none.
local classAtlases = {} -- class token -> atlas, or false without one

local function classAtlas(unit)
    local _, token = UnitClass(unit)
    if not (readable(token) and token) then
        return nil
    end
    local atlas = classAtlases[token]
    if atlas == nil then
        local name = lower(token)
        atlas = ns.Frames.FirstAtlas("classicon-" .. name, "groupfinder-icon-class-" .. name) or false
        classAtlases[token] = atlas
    end
    return atlas or nil
end

-- Shows the class icon beside `anchor` (left of it when `left`), or hides it without an atlas;
-- returns the width it takes.
local function placeClass(icon, anchor, left, size, atlas)
    icon:ClearAllPoints()
    if not atlas then
        icon:Hide()
        return 0
    end
    if icon.atlas ~= atlas then
        icon.atlas = atlas
        icon:SetAtlas(atlas, false)
    end
    icon:SetSize(size, size)
    if left then
        icon:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
    else
        icon:SetPoint("LEFT", anchor, "RIGHT", GAP, 0)
    end
    icon:Show()
    return size + GAP
end

-- Label ---------------------------------------------------------------------------------------

local labels = setmetatable({}, { __mode = "k" }) -- Blizzard unit frame -> our label on it

local function newText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFontObject("SystemFont_NamePlate")
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    return text
end

local function createLabel(frame)
    local label = CreateFrame("Frame", nil, frame)
    label:SetAllPoints(frame)
    -- Empty frames to center on: the bar's row (see placeRow), and the cast bar's (placeSubtitle).
    label.row = CreateFrame("Frame", nil, label)
    label.castRow = CreateFrame("Frame", nil, label)
    -- Debug (Show Plate Center): a thin line down the middle of the row, on a frame of its own so
    -- it shows with or without the bar.
    label.debugFrame = CreateFrame("Frame", nil, frame)
    label.debugFrame:SetAllPoints(frame)
    label.centerLine = label.debugFrame:CreateTexture(nil, "OVERLAY")
    label.centerLine:SetColorTexture(1, 0.2, 0.2, 0.9)
    label.centerLine:SetSize(1, 40)
    label.centerLine:SetPoint("CENTER", label.row, "CENTER")
    label.centerLine:Hide()
    label.name = newText(label)
    label.subtitle = newText(label)
    -- A separate frame so it can fade in with the bar while the rest of the label fades out.
    label.barFrame = CreateFrame("Frame", nil, frame)
    label.barFrame:SetAllPoints(frame)
    label.barSubtitle = newText(label.barFrame)
    -- Our own name for the bar view too: Blizzard's sits at the bar's left, off the unit's center.
    label.barName = newText(label.barFrame)
    label.barRow = CreateFrame("Frame", nil, label.barFrame)
    -- Our copy of the level badge, which sits beside the name instead of at the bar's end.
    label.level = CreateFrame("Frame", nil, label)
    label.level.text = label.level:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.level.text:SetPoint("CENTER")
    -- One set of icons for each view: beside our name, and beside our bar-view name.
    label.icons = createIcons(label)
    label.barIcons = createIcons(label.barFrame)
    label.classIcon = label:CreateTexture(nil, "OVERLAY")
    label.classIcon:Hide()
    label.barClassIcon = label.barFrame:CreateTexture(nil, "OVERLAY")
    label.barClassIcon:Hide()
    return label
end

---Our label on a Blizzard unit frame, made the first time and shown. Plates are pooled, so it's
---reused.
---@param frame table plate.UnitFrame
---@return table label
function PlateLabel.Show(frame)
    local label = labels[frame]
    if not label then
        label = createLabel(frame)
        labels[frame] = label
    end
    label:Show()
    label.barFrame:Show()
    label.debugFrame:Show()
    return label
end

---Hides a label as its plate goes back to the pool.
---@param label table
function PlateLabel.Hide(label)
    label:Hide()
    label.barFrame:Hide()
    label.debugFrame:Hide()
end

-- Copies the look of Forever's level badge (UnitFrame.LevelFrame): its atlas art and its
-- number's font. The art is copied once per label, since the badge is the same on every plate;
-- the size is retried until Blizzard has laid its badge out.
local function copyBadge(label, levelFrame)
    local badge = label.level
    local width, height = levelFrame:GetSize()
    if readable(width) and readable(height) and width and width > 0 then
        badge:SetSize(width, height)
    elseif not badge.sized then
        badge:SetSize(24, 14)
    end
    badge.sized = true
    if badge.copied then
        return
    end
    badge.copied = true
    local sources = { levelFrame }
    for _, child in pairs({ levelFrame:GetChildren() }) do
        sources[#sources + 1] = child
    end
    for _, source in pairs(sources) do
        for _, region in pairs({ source:GetRegions() }) do
            local kind = region:GetObjectType()
            if kind == "Texture" and region:GetAtlas() then
                local texture = badge:CreateTexture(nil, region:GetDrawLayer())
                texture:SetAtlas(region:GetAtlas())
                texture:SetAllPoints(badge)
                badge.hasArt = true
            elseif kind == "FontString" then
                local file, size, flags = region:GetFont()
                if file and size then
                    badge.text:SetFont(file, size, flags)
                end
            end
        end
    end
end

-- Use the size Blizzard's name is drawn at, not its font object's (nameplates set the size on the
-- string). Blizzard shrinks a long name's font to fit its plate, so every label uses the largest
-- size seen: the normal one. A nameplate CVar change (plate size among them) measures it again,
-- so a smaller size takes effect too.
local fullSize = 0
local watchingSize = false

local function onCVarUpdate(_, name)
    if type(name) == "string" and lower(name):find("^nameplate") then
        fullSize = 0
    end
end

-- Blizzard's nameplate font is a font family: a font per alphabet, so Chinese, Korean, and
-- Cyrillic names draw with fonts that have those glyphs. SetFont with the one file GetFont
-- returns (the roman one) dropped the rest, and those names came out blank. So, like Blizzard's
-- own plates, we take its font object and set only the height, which keeps the whole family.
local function setFont(text, base, size)
    text:SetFontObject(base)
    if text.SetFontHeight then
        text:SetFontHeight(size)
    else
        text:SetTextHeight(size) -- older clients: scales the text instead, a touch softer
    end
end

-- `scale` is the module's Name Size (1 = Blizzard's name size). Icons and the subtitle size from
-- this too, and the layout measures the text, so they fit around whatever size it is.
local function matchFont(label, name, scale)
    local _, size = name:GetFont()
    local base = name:GetFontObject() or _G.SystemFont_NamePlate
    if not (size and base) then
        return
    end
    if not watchingSize then
        watchingSize = true
        ns.On("CVAR_UPDATE", onCVarUpdate)
    end
    if size > fullSize then
        fullSize = size
    end
    size = floor(fullSize * scale * 10 + 0.5) / 10
    if label.nameSize == size and label.fontBase == base then
        return
    end
    label.nameSize, label.fontBase = size, base
    setFont(label.name, base, size)
    setFont(label.subtitle, base, size * SUBTITLE_SCALE)
    setFont(label.barSubtitle, base, size * SUBTITLE_SCALE)
    setFont(label.barName, base, size)
end

-- Puts the level beside `anchor` (the name, or the class icon on its side); returns the width it
-- takes.
local function placeLevel(label, record, unit, where, anchor)
    local badge = label.level
    if not record.levelFrame or where == "off" then
        badge:Hide()
        return 0
    end
    copyBadge(label, record.levelFrame)
    local level = UnitLevel(unit)
    if readable(level) and level <= 0 then
        badge.text:SetText("??")
    else
        badge.text:SetText(level)
    end
    -- Without copied art the badge is just the number, so it's as wide as the number.
    local textWidth = badge.text:GetStringWidth()
    if not badge.hasArt and readable(textWidth) and textWidth > 0 then
        badge:SetWidth(textWidth)
    end
    local width = badge:GetWidth()
    width = readable(width) and width + GAP or 0
    badge:ClearAllPoints()
    if where == "after" then
        badge:SetPoint("LEFT", anchor, "RIGHT", GAP, 0)
    else
        badge:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
    end
    badge:Show()
    return width
end

-- Sets a row frame to `target`'s height and the label's width.
local function span(row, target, label)
    row:ClearAllPoints()
    row:SetPoint("TOP", target, "TOP")
    row:SetPoint("BOTTOM", target, "BOTTOM")
    row:SetPoint("LEFT", label, "LEFT")
    row:SetPoint("RIGHT", label, "RIGHT")
end

-- The row our label is centered on: the bar's height, but the unit frame's width (the label covers
-- it), since the bar sits left of center with the level badge on its right end. Never anchor to
-- the nameplate base frame (NamePlateN) itself: on 12.x that fails with "anchor family
-- connection" and also breaks Blizzard's own nameplate anchors.
local function placeRow(label, record, style)
    local row = label.row
    span(row, record.container, label)
    label.centerLine:SetShown(style.db.centerLine)
    return row
end

local function placeSubtitle(label, record, unit, style, shift)
    local row = placeRow(label, record, style)
    local text, mode = style.Subtitle(unit)
    -- How far the name sits off the row's center, so things above it can center on the whole row.
    label.nameShift = shift
    label.name:ClearAllPoints()
    label.subtitle:ClearAllPoints()
    label.barSubtitle:ClearAllPoints()
    if mode == "off" or not (readable(text) and text and text ~= "") then
        label.name:SetPoint("CENTER", row, "CENTER", shift, 0)
        label.subtitle:Hide()
        label.barSubtitle:Hide()
        return
    end
    local color = style.SubtitleColor(unit)
    label.subtitle:SetTextColor(color[1], color[2], color[3])
    label.barSubtitle:SetTextColor(color[1], color[2], color[3])
    label.name:SetPoint("BOTTOM", row, "CENTER", shift, 1)
    -- While a cast bar is showing (under the bar), the subtitle moves below it, and back once the
    -- bar hides. Only then: friendly plates can hide cast bars, which left a gap under the name.
    local castBar = record.castBar
    if Nameplates.IsCastBarShown(castBar) then
        -- Centered on the unit like the row, at the cast bar's height.
        local castRow = label.castRow
        span(castRow, castBar, label)
        label.subtitle:SetPoint("TOP", castRow, "BOTTOM", 0, -1)
        label.barSubtitle:SetPoint("TOP", castRow, "BOTTOM", 0, -1)
    else
        label.subtitle:SetPoint("TOP", row, "CENTER", 0, 0)
        label.barSubtitle:SetPoint("TOP", row, "BOTTOM", 0, -2)
    end
    label.subtitle:SetFormattedText("<%s>", text)
    label.subtitle:Show()
    label.barSubtitle:SetFormattedText("<%s>", text)
    label.barSubtitle:SetShown(mode == "always")
end

---Lays the label out for this unit: name, color, level, icons, subtitle.
---@param label table from PlateLabel.Show
---@param record table the plate: container, name (Blizzard's), levelFrame, castBar
---@param unit string
---@param style table see the top of this file
function PlateLabel.Layout(label, record, unit, style)
    label.name:SetText(record.name:GetText())
    matchFont(label, record.name, (style.db.nameSize or 100) / 100)
    label.name:SetTextColor(style.NameColor(unit))
    -- Out from the name on each side: the class icon, then the level, then the other icons, on
    -- whichever side each one's setting puts it. The name then shifts by half the difference, so
    -- the whole row is centered over the bar. The subtitle stays centered.
    local db = style.db
    local fontSize = label.nameSize or 12
    local classWhere = style.classIcons and db.classIcon or "off"
    local atlas = classWhere ~= "off" and classAtlas(unit) or nil
    local classLeft = classWhere == "before"
    local where = db.level
    local levelLeft = where ~= "after"
    local iconsLeft = db.iconSide == "before"
    local size = fontSize * ICON_SCALE
    local classWidth = placeClass(label.classIcon, label.name, classLeft, size, atlas)
    local levelAnchor = atlas and classLeft == levelLeft and label.classIcon or label.name
    local levelWidth = placeLevel(label, record, unit, where, levelAnchor)
    local anchor = label.name
    if levelWidth > 0 and levelLeft == iconsLeft then
        anchor = label.level
    elseif atlas and classLeft == iconsLeft then
        anchor = label.classIcon
    end
    local iconsWidth = placeIcons(label.icons, anchor, iconsLeft, fontSize, unit, style)
    local leftWidth, rightWidth = 0, 0
    local function add(left, width)
        if left then
            leftWidth = leftWidth + width
        else
            rightWidth = rightWidth + width
        end
    end
    add(classLeft, classWidth)
    add(levelLeft, levelWidth)
    add(iconsLeft, iconsWidth)
    -- With the bar up: our bar-view name centered on the plate just above the bar, the class
    -- icon and other icons beside it, all shifted so they're centered together. Blizzard's level
    -- stays on the bar.
    label.barName:SetText(record.name:GetText())
    label.barName:SetTextColor((style.BarNameColor or style.NameColor)(unit))
    local barClassWidth = placeClass(label.barClassIcon, label.barName, classLeft, size, atlas)
    local barAnchor = atlas and classLeft == iconsLeft and label.barClassIcon or label.barName
    local barIconsWidth = placeIcons(label.barIcons, barAnchor, iconsLeft, fontSize, unit, style)
    local barLeft = (classLeft and barClassWidth or 0) + (iconsLeft and barIconsWidth or 0)
    local barRight = (classLeft and 0 or barClassWidth) + (iconsLeft and 0 or barIconsWidth)
    local barRow = label.barRow
    span(barRow, record.container, label)
    label.barName:ClearAllPoints()
    label.barNameShift = (barLeft - barRight) / 2
    label.barName:SetPoint("BOTTOM", barRow, "TOP", label.barNameShift, 2)
    -- What sits beside the name on each side, so things placed beside the row can clear it.
    label.leftWidth, label.rightWidth = leftWidth, rightWidth
    placeSubtitle(label, record, unit, style, (leftWidth - rightWidth) / 2)
    -- Dimmed (Player Nameplates' Dim Other Players): every part of both views. The views' own
    -- alpha is FriendlyPlates' fade, so this is set on what's inside them.
    local alpha = style.Alpha and style.Alpha(unit) or 1
    if label.alpha ~= alpha then
        label.alpha = alpha
        for _, region in ipairs({ label.name, label.subtitle, label.level, label.classIcon,
            label.barName, label.barSubtitle, label.barClassIcon }) do
            region:SetAlpha(alpha)
        end
        for _, kind in ipairs(ORDER) do
            label.icons[kind]:SetAlpha(alpha)
            label.barIcons[kind]:SetAlpha(alpha)
        end
    end
end
