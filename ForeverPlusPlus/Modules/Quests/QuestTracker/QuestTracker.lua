-- Quest Tracker: restyles Blizzard's own objective tracker instead of replacing it, so it keeps
-- its Edit Mode place, height, opacity and text size, its menus, quest items and clicks. It
-- changes the tracker's font objects (face, outline), draws a tooltip-style box that fits what the
-- tracker shows, can fade the tracker in combat, can sort tracked quests by level, and can show
-- only the tracked quests of the current zone, or leave out the completed ones.
-- It never calls the tracker's update or layout itself: that would run Blizzard's layout as
-- addon code and could taint the quest item buttons. A font change the tracker has already laid
-- out settles at its next update (any quest progress, or collapsing and expanding it).
-- The one exception is Collapse at Login, off by default, which has no other way (see it below).
local _, ns = ...

local pairs, ipairs, next, type, min, max = pairs, ipairs, next, type, math.min, math.max
local setmetatable, sort, select, huge = setmetatable, table.sort, select, math.huge
local InCombatLockdown, C_Timer, C_QuestLog, C_Map = InCombatLockdown, C_Timer, C_QuestLog, C_Map
local C_CVar, GameTooltip, GetQuestLink, EventRegistry = C_CVar, GameTooltip, GetQuestLink, EventRegistry
local GetRealZoneText = GetRealZoneText
local GetQuestUiMapID, Enum = GetQuestUiMapID, Enum

local L = ns.L
local Quests = ns.Quests

local module = ns.NewModule("QuestTracker", L.QUESTTRACKER_DESC, {
    enabled = true,
    font = "default",
    outline = "default",
    background = true,
    opacity = 40, -- percent
    border = false,
    padding = 10,
    fade = false,
    fadeOpacity = 30, -- percent: the tracker's alpha in combat with Fade in Combat
    sort = "off", -- or "low" / "high": which level comes first
    zone = false,
    completed = false, -- untrack quests once they're ready to turn in
    dim = false, -- fade the text of finished objectives
    dimOpacity = 40, -- percent: how visible a finished objective stays with Dim Finished Objectives
    progress = false, -- color a counted objective's text by how far along it is
    difficulty = false, -- Blizzard's own CVar, shown here; nothing of ours is saved
    tooltip = false, -- the quest's tooltip while the mouse is on its title
    collapse = false, -- collapse the tracker once at login and after a reload
    count = false, -- the quest log's count on the Quests header (Header.lua)
    zones = false, -- a click on the Quests header opens a menu of the quest log's zones (Header.lua)
    hidden = {}, -- [questID] = true: quests Current Zone Only untracked on this character
    -- [questID] = true: quests Hide Completed Quests untracked on this character; false: one the
    -- player tracked again by hand, to leave alone
    done = {},
})
module.title = L.QUESTTRACKER_TITLE
module.category = "quests"
module.presets = { developer = { options = { sort = "low" } } }
module.perCharacter = { hidden = true, done = true }
module.internal = {} -- what this folder's files share
local internal = module.internal

-- With the controller interface on, Collapse at Login and the Quests header's Zone Menu do nothing.
module.notice = ns.Gamepad.LimitedNotice()

-- 0.8.x saved every default as if the player chose it, so a 30% background from then is 0.8.4's
-- default, not a choice: let it take today's.
ns.Migrate(1, function(db)
    local saved = db.modules and db.modules.QuestTracker
    if saved and saved.opacity == 30 then
        saved.opacity = nil
    end
end)

-- Which quests and in what order, the Quests header, then the text, the box behind it, and combat.
local QUESTS, TEXT, BOX, COMBAT = L.QUESTTRACKER_SECTION_QUESTS, L.QUESTTRACKER_SECTION_TEXT,
    L.QUESTTRACKER_SECTION_BOX, L.QUESTTRACKER_SECTION_COMBAT
local HEADER, OBJECTIVES = L.QUESTTRACKER_SECTION_HEADER, L.QUESTTRACKER_SECTION_OBJECTIVES
local DIFFICULTY_CVAR = "showQuestDifficultyColor"
module.options = {
    {
        key = "sort",
        name = L.QUESTTRACKER_SORT,
        description = L.QUESTTRACKER_SORT_DESC,
        section = QUESTS,
        added = "0.8.2",
        changed = "1.9.0",
        choices = {
            { "off", L.QUESTTRACKER_SORT_OFF },
            { "low", L.QUESTTRACKER_SORT_LOW },
            { "high", L.QUESTTRACKER_SORT_HIGH },
            { "zone", L.QUESTTRACKER_SORT_ZONE },
        },
    },
    {
        key = "zone",
        name = L.QUESTTRACKER_ZONE,
        description = L.QUESTTRACKER_ZONE_DESC,
        section = QUESTS,
        added = "0.9.0",
    },
    {
        key = "completed",
        name = L.QUESTTRACKER_COMPLETED,
        description = L.QUESTTRACKER_COMPLETED_DESC,
        section = QUESTS,
        added = "1.9.0",
    },
    {
        -- Blizzard's own setting, which Forever's tracker and quest log read for a quest's title
        -- (QuestUtilsOverrides.GetQuestTitleDifficultyColor and ObjectiveTrackerBlockMixin's
        -- UpdateHighlight, on the forever branch). Titles change at the tracker's next update.
        key = "difficulty",
        name = L.QUESTTRACKER_DIFFICULTY,
        description = L.QUESTTRACKER_DIFFICULTY_DESC,
        section = QUESTS,
        cvar = DIFFICULTY_CVAR,
        available = function() return C_CVar.GetCVar(DIFFICULTY_CVAR) ~= nil end,
        needs = L.SETTINGS_NEEDS_CLIENT,
        added = "1.9.0",
    },
    {
        key = "tooltip",
        name = L.QUESTTRACKER_TOOLTIP,
        description = L.QUESTTRACKER_TOOLTIP_DESC,
        section = QUESTS,
        added = "1.9.0",
    },
    {
        key = "collapse",
        name = L.QUESTTRACKER_COLLAPSE,
        description = L.QUESTTRACKER_COLLAPSE_DESC,
        section = QUESTS,
        added = "1.8.0",
    },
    {
        key = "progress",
        name = L.QUESTTRACKER_PROGRESS,
        description = L.QUESTTRACKER_PROGRESS_DESC,
        section = OBJECTIVES,
        added = "1.9.0",
    },
    {
        key = "dim",
        name = L.QUESTTRACKER_DIM,
        description = L.QUESTTRACKER_DIM_DESC,
        section = OBJECTIVES,
        slider = "dimOpacity",
        added = "1.9.0",
    },
    {
        key = "dimOpacity",
        name = L.QUESTTRACKER_DIM_OPACITY,
        description = L.QUESTTRACKER_DIM_OPACITY_DESC,
        section = OBJECTIVES,
        requires = "dim",
        added = "1.9.0",
        min = 10, max = 80, step = 5, format = "%d%%",
    },
    {
        key = "count",
        name = L.QUESTTRACKER_COUNT,
        description = L.QUESTTRACKER_COUNT_DESC,
        section = HEADER,
        added = "1.9.0",
    },
    {
        key = "zones",
        name = L.QUESTTRACKER_ZONES,
        description = L.QUESTTRACKER_ZONES_DESC,
        section = HEADER,
        added = "1.9.0",
    },
    {
        key = "font",
        name = L.QUESTTRACKER_FONT,
        description = L.QUESTTRACKER_FONT_DESC,
        section = TEXT,
        choices = ns.Fonts.ChoicesAfter({ "default", L.QUESTTRACKER_DEFAULT }),
    },
    {
        key = "outline",
        name = L.QUESTTRACKER_OUTLINE,
        description = L.QUESTTRACKER_OUTLINE_DESC,
        section = TEXT,
        choices = {
            { "default", L.QUESTTRACKER_DEFAULT },
            { "", L.QUESTTRACKER_OUTLINE_NONE },
            { "OUTLINE", L.QUESTTRACKER_OUTLINE_THIN },
            { "THICKOUTLINE", L.QUESTTRACKER_OUTLINE_THICK },
        },
    },
    {
        key = "background",
        name = L.QUESTTRACKER_BACKGROUND,
        description = L.QUESTTRACKER_BACKGROUND_DESC,
        section = BOX,
        slider = "opacity",
    },
    {
        key = "opacity",
        name = L.QUESTTRACKER_OPACITY,
        description = L.QUESTTRACKER_OPACITY_DESC,
        section = BOX,
        requires = "background",
        min = 10, max = 100, step = 5, format = "%d%%", -- opacity steps by 5, as every opacity slider does
    },
    {
        key = "border",
        name = L.QUESTTRACKER_BORDER,
        description = L.QUESTTRACKER_BORDER_DESC,
        section = BOX,
        requires = "background",
    },
    {
        key = "padding",
        name = L.QUESTTRACKER_PADDING,
        description = L.QUESTTRACKER_PADDING_DESC,
        section = BOX,
        requires = "background",
        min = 0, max = 24, step = 2, format = L.ICONMARK_PIXELS,
    },
    {
        key = "fade",
        name = L.QUESTTRACKER_FADE,
        description = L.QUESTTRACKER_FADE_DESC,
        section = COMBAT,
        slider = "fadeOpacity",
    },
    {
        key = "fadeOpacity",
        name = L.QUESTTRACKER_FADE_OPACITY,
        description = L.QUESTTRACKER_FADE_OPACITY_DESC,
        section = COMBAT,
        requires = "fade",
        added = "0.9.0",
        min = 0, max = 80, step = 5, format = "%d%%",
    },
}

-- Font objects the tracker is known to use, set before its first layout when they exist. The
-- tracker's text is searched for more as it updates.
local KNOWN_FONTS = { "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont", "ObjectiveTrackerFont12",
    "ObjectiveTrackerFont14", "ObjectiveTrackerFont16", "ObjectiveTrackerFont18", "ObjectiveTrackerFont20" }

local original = setmetatable({}, { __mode = "k" }) -- font object -> { file, size, flags } before us
local box -- the background, made the first time it's needed
local faded = false -- we set the tracker's alpha for combat

local function tracker()
    return ObjectiveTrackerFrame
end

-- Fonts -------------------------------------------------------------------------------------------

---Sets one of the tracker's font objects to the chosen face and outline, from its own. Its size
---stays Blizzard's, which Edit Mode's Text Size sets.
---@param font table
local function applyFont(font)
    local saved = original[font]
    if not saved then
        local file, size, flags = font:GetFont()
        if not file then
            return
        end
        saved = { file, size, flags }
        original[font] = saved
    end
    local db = module.db
    local file = saved[1]
    -- Clients whose alphabets need the game's fallbacks keep Blizzard's face (ns.Fonts.CanChange)
    -- and only get the outline.
    if db.font ~= "default" and ns.Fonts.CanChange() then
        file = db.font
    end
    local flags = saved[3]
    if db.outline ~= "default" then
        flags = db.outline
    end
    -- The size it has now: Edit Mode's Text Size may have changed it since we first saw it.
    local _, size = font:GetFont()
    font:SetFont(file, size or saved[2], flags)
end

---Whether a font object is one of the tracker's own, not a shared one like GameFontNormal.
---@param font table?
---@return boolean
local function isTrackerFont(font)
    if type(font) ~= "table" or not font.GetName then
        return false
    end
    local name = font:GetName()
    return type(name) == "string" and name:find("^ObjectiveTracker") ~= nil
end

-- Finds the tracker's font objects in its text, a few frames deep, and styles any new ones.
local function findFonts(frame, depth)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetFontObject then
            local font = region:GetFontObject()
            if font and not original[font] and isTrackerFont(font) then
                applyFont(font)
            end
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            findFonts(child, depth - 1)
        end
    end
end

-- Whether the font or outline isn't Blizzard's, so the tracker's fonts need styling at all.
local function styled()
    local db = module.db
    return db.font ~= "default" or db.outline ~= "default"
end

local function applyFonts()
    for _, name in ipairs(KNOWN_FONTS) do
        local font = _G[name]
        if isTrackerFont(font) then
            applyFont(font)
        end
    end
    for font in pairs(original) do
        applyFont(font)
    end
end

local function restoreFonts()
    for font, saved in pairs(original) do
        local _, size = font:GetFont() -- keep Edit Mode's Text Size
        font:SetFont(saved[1], size or saved[2], saved[3])
        original[font] = nil
    end
end

-- Background --------------------------------------------------------------------------------------

local function newBox()
    local frame = tracker()
    -- The same box Blizzard draws tooltips in, behind the tracker's own frames.
    local b = ns.Frames.TooltipBox(frame)
    b:SetFrameLevel(max(0, frame:GetFrameLevel() - 1))
    b:Hide()
    return b
end

local function setColors()
    local alpha = module.db.opacity / 100
    local borderAlpha = module.db.border and 1 or 0
    local r, g, b = 1, 1, 1
    if TOOLTIP_DEFAULT_COLOR then
        r, g, b = TOOLTIP_DEFAULT_COLOR:GetRGB()
    end
    local slice = box.NineSlice
    if slice and slice.SetCenterColor then
        slice:SetCenterColor(0, 0, 0, alpha)
        slice:SetBorderColor(r, g, b, borderAlpha)
    elseif box.SetBackdropColor then
        box:SetBackdropColor(0, 0, 0, alpha)
        box:SetBackdropBorderColor(r, g, b, borderAlpha)
    end
end

---Whether a texture or font string is drawn now: shown, not see-through, not a mouseover
---highlight, and for text, not empty.
---@param region table
---@return boolean
local function isDrawn(region)
    if not (region.IsVisible and region:IsVisible()) or region:GetAlpha() <= 0 then
        return false
    end
    if region.GetDrawLayer and region:GetDrawLayer() == "HIGHLIGHT" then
        return false
    end
    if region.GetText then
        local text = region:GetText()
        return text ~= nil and text ~= ""
    end
    return true
end

local fitBox
local SETTLE = 0.2 -- seconds; when to fit once more after a change
-- Its parts' own rows on the Profiler page: styling fonts, fitting the box, and sorting.
local Profiler = ns.Profiler
local PART_FONTS = Profiler.Part(module, L.QUESTTRACKER_PART_FONTS)
local PART_FIT = Profiler.Part(module, L.QUESTTRACKER_PART_FIT)
local PART_SORT = Profiler.Part(module, L.QUESTTRACKER_PART_SORT)

local fitSoon = ns.Frames.Coalesce(function() Profiler.Call(PART_FIT, fitBox) end)
local fitSettled = ns.Frames.Coalesce(function() Profiler.Call(PART_FIT, fitBox) end, SETTLE)
-- How far the header art and the quests' map buttons reach past the tracker's left edge (about
-- 5 pixels in game), so the padding on the left measures from them whether sections are open or
-- not. Measured from what's drawn, the buttons' glow made it jump.
local OVERHANG = 6

-- Fits the box on the next frame, once, however many of the tracker's frames changed. Opening a
-- section shows its quests a moment before Blizzard has moved them all into place, which fires
-- nothing we can hear, so it fits once more a little later too.
local function requestFit()
    if not module.enabled then
        return
    end
    fitSoon()
    fitSettled()
end

-- Collapsing a section, or a quest coming or going, shows, hides or resizes one of the tracker's
-- frames without always going through an update we can hook, so every frame measured refits the
-- box when that happens to it.
local function watch(frame)
    module:HookScript(frame, "OnShow", requestFit)
    module:HookScript(frame, "OnHide", requestFit)
    module:HookScript(frame, "OnSizeChanged", requestFit)
end

-- One reused list per walk depth (regions and children apart), so a walk makes no tables. Each
-- depth's lists are done with before a deeper level's could be filled again.
local buffers = {}
local function pack(key, ...)
    local list = buffers[key]
    if not list then
        list = {}
        buffers[key] = list
    end
    local n = select("#", ...)
    for i = 1, n do
        list[i] = select(i, ...)
    end
    for i = n + 1, #list do
        list[i] = nil
    end
    return list, n
end

-- Lowers `bounds.bottom` to the lowest thing a frame and its children draw: header art and text,
-- quest lines, map and item buttons. Only what's drawn counts, not frame sizes, since a
-- collapsed section can keep its full height.
local function measure(frame, bounds, depth)
    watch(frame)
    if not frame:IsVisible() or frame:GetEffectiveAlpha() <= 0 then
        return
    end
    local regions, count = pack(depth * 2, frame:GetRegions())
    for i = 1, count do
        local region = regions[i]
        if isDrawn(region) then
            local _, bottom, width, height = region:GetRect()
            if bottom and width > 1 and height > 1 then
                bounds.bottom = min(bounds.bottom or bottom, bottom)
            end
        end
    end
    if depth > 0 then
        local children, total = pack(depth * 2 + 1, frame:GetChildren())
        for i = 1, total do
            measure(children[i], bounds, depth - 1)
        end
    end
end

-- Fits the box to the tracker's width (Edit Mode's) and down to the last thing it draws, so a
-- collapsed tracker or section takes a short box. Blizzard's own background (Edit Mode's
-- Opacity) fills the whole height instead.
function fitBox()
    local frame = tracker()
    if not (module.enabled and module.db.background) or not frame:IsVisible() then
        if box then
            box:Hide()
        end
        return
    end
    box = box or newBox()
    local bounds = {}
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= box and child ~= frame.NineSlice and child ~= frame.Selection then
            measure(child, bounds, 5)
        end
    end
    local _, frameBottom, _, frameHeight = frame:GetRect()
    if not (bounds.bottom and frameBottom) then
        box:Hide()
        return
    end
    local frameTop = frameBottom + frameHeight
    local pad = module.db.padding -- how far the box reaches past what the tracker shows
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", -OVERHANG - pad, pad)
    box:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", pad, bounds.bottom - frameTop - pad)
    setColors()
    box:Show()
end

-- Dim finished objectives -------------------------------------------------------------------------
-- Hiding a finished objective would leave a gap (see Completed quests below), so this only fades
-- its text: an alpha on the line's own font string, which the tracker never sets or reads for
-- layout.
--
-- When: after each update of the two quest sections (QuestObjectiveTracker and
-- CampaignQuestObjectiveTracker), by a hook on each one's own Update. A hook on
-- ObjectiveTrackerFrame.Update misses nearly all of them: the tracker's updates after a quest
-- event go through a closure its OnLoad made of the function itself
-- (ObjectiveTrackerContainerMixin:OnLoad, SetDirtyMethod(GenerateClosure(self.Update, ...))), so
-- they never look up the frame's Update key a hook replaces. Only a direct call (collapsing the
-- tracker, Edit Mode's text size) reaches it. The container calls each section as
-- module:Update(...), which a hook on the section does hear.
--
-- Which: a line of a numbered objective (its objectiveKey, the index DoQuestObjectives gives it)
-- whose objective the quest log calls finished. The line's own state (ObjectiveTrackerAnimLineState,
-- Blizzard_ObjectiveTrackerAnimTemplates.lua on the forever branch) is the fallback: Completing and
-- Completed are a finished objective, Fading one already on its way out.
--
-- Lines are pooled and reused for other objectives, so every line a pass doesn't dim goes back to
-- full, the ones the section has let go of too.

--
-- Color Objectives by Progress rides the same pass. It colors the text of an objective that
-- counts ("3/8 Prowler slain") by how far along it is: Blizzard's own gray until it's started,
-- toward yellow at half, toward green as it nears done. A color changes no size, so the layout
-- is untouched. Two things of Blizzard's to work with (Blizzard_ObjectiveTrackerBlock.lua):
-- SetStringText only sets a color when the line's colorStyle changes, so ours stays until we put
-- the style's color back ourselves, and UpdateHighlight sets every line's color as the mouse
-- enters and leaves the quest's title, so a block is colored again after the mouse leaves it and
-- left white (Blizzard's highlight) while the mouse is on it.

local dimmed = setmetatable({}, { __mode = "k" }) -- font string -> the section whose line we faded
local colored = setmetatable({}, { __mode = "k" }) -- font string -> the section whose line we colored
local seen = {} -- font string -> true: the lines of the pass under way

local function finishedLine(line, objective)
    if objective then
        return ns.IsTrue(objective.finished)
    end
    local states = ObjectiveTrackerAnimLineState
    local state = line.state
    return states ~= nil and state ~= nil and (state == states.Completing or state == states.Completed
        or state == states.Fading)
end

-- Blizzard's color for the line's style, which it won't set again by itself.
local function restoreColor(text)
    local style = text.colorStyle
    if type(style) == "table" and style.r then
        text:SetTextColor(style.r, style.g, style.b)
    end
end

local function undim()
    for text in pairs(dimmed) do
        text:SetAlpha(1)
        dimmed[text] = nil
    end
end

local function uncolor()
    for text in pairs(colored) do
        restoreColor(text)
        colored[text] = nil
    end
end

-- The tracker's own text gray (OBJECTIVE_TRACKER_COLOR.Normal), then Blizzard's yellow and green.
local PROGRESS_START = { r = 0.8, g = 0.8, b = 0.8 }
local PROGRESS_HALF = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
local PROGRESS_DONE = GREEN_FONT_COLOR or { r = 0.1, g = 1, b = 0.1 }

---The color of a counted objective that's under way, or nil for one to leave Blizzard's: not
---started, counting to 1, or with numbers that can't be read.
---@param objective table one of C_QuestLog.GetQuestObjectives
---@return number? r
---@return number? g
---@return number? b
local function progressColor(objective)
    local have, need = objective.numFulfilled, objective.numRequired
    if not (ns.IsNumber(have) and ns.IsNumber(need)) or need <= 1 or have <= 0 then
        return nil
    end
    local part = min(have / need, 1) * 2
    local from, to = PROGRESS_START, PROGRESS_HALF
    if part > 1 then
        from, to, part = PROGRESS_HALF, PROGRESS_DONE, part - 1
    end
    return from.r + (to.r - from.r) * part, from.g + (to.g - from.g) * part, from.b + (to.b - from.b) * part
end

local QUEST_TRACKERS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

---Dims and colors the objective lines of one quest, each as its option says, and notes them in
---`seen`.
---@param block table one of a quest section's blocks
---@param section table the section it's in
local function styleBlock(block, section)
    local lines = block.usedLines
    if type(lines) ~= "table" then
        return
    end
    local db = module.db
    local alpha = db.dim and db.dimOpacity / 100 or nil
    -- Blizzard's highlight has the lines while the mouse is on the quest's title.
    local color = db.progress and not block.isHighlighted
    local questID = block.id
    local objectives = type(questID) == "number" and C_QuestLog.GetQuestObjectives
        and C_QuestLog.GetQuestObjectives(questID) or nil
    for _, line in pairs(lines) do
        local text = line.Text
        if text and text.SetAlpha then
            seen[text] = true
            local key = line.objectiveKey
            local objective = objectives and type(key) == "number" and objectives[key] or nil
            if type(objective) ~= "table" then
                objective = nil
            end
            local finished = finishedLine(line, objective)
            if alpha and finished then
                text:SetAlpha(alpha)
                dimmed[text] = section
            elseif dimmed[text] then
                text:SetAlpha(1)
                dimmed[text] = nil
            end
            local r, g, b
            if color and objective and not finished then
                r, g, b = progressColor(objective)
            end
            if r then
                text:SetTextColor(r, g, b)
                colored[text] = section
            elseif colored[text] then
                colored[text] = nil
                if not block.isHighlighted then
                    restoreColor(text)
                end
            end
        end
    end
end

local function clearSeen()
    for text in pairs(seen) do
        seen[text] = nil
    end
end

-- After the mouse leaves a quest's title: Blizzard has just set its lines back to their styles.
local function onBlockLeave(button)
    local block = button:GetParent()
    if module.db.progress and block and type(block.parentModule) == "table" then
        styleBlock(block, block.parentModule)
        clearSeen()
    end
end

---Styles the objective lines of one quest section, and puts back the lines it no longer shows.
---@param section table QuestObjectiveTracker or CampaignQuestObjectiveTracker
local function styleSection(section)
    if not section.EnumerateActiveBlocks then
        return
    end
    local watchLeave = module.db.progress
    section:EnumerateActiveBlocks(function(block)
        styleBlock(block, section)
        if watchLeave then
            module:HookScript(block.HeaderButton, "OnLeave", onBlockLeave)
        end
    end)
    -- A line the section freed keeps our alpha and color until something else uses it.
    for text, owner in pairs(dimmed) do
        if owner == section and not seen[text] then
            text:SetAlpha(1)
            dimmed[text] = nil
        end
    end
    for text, owner in pairs(colored) do
        if owner == section and not seen[text] then
            restoreColor(text)
            colored[text] = nil
        end
    end
    clearSeen()
end

-- Whether any option that styles objective lines is on.
local function stylesLines()
    return module.db.dim or module.db.progress
end

local function styleLines()
    if not module.db.dim and next(dimmed) ~= nil then
        undim()
    end
    if not module.db.progress and next(colored) ~= nil then
        uncolor()
    end
    if not stylesLines() then
        return
    end
    for _, name in ipairs(QUEST_TRACKERS) do
        local section = _G[name]
        if type(section) == "table" then
            styleSection(section)
        end
    end
end

-- After a quest section's own update (see above), with the section as `self`.
local function onSectionUpdate(section)
    if stylesLines() then
        styleSection(section)
    end
end

-- After a tracker update called directly (collapsing it, Edit Mode's text size), and when the
-- module turns on: style fonts it has started using, and fit the box. At Blizzard's font and
-- outline there's nothing to style, so its text isn't searched. The box is fitted now, so it
-- never trails a frame behind, and once more as the tracker settles, but not next frame as well
-- (as requestFit would), since nothing has moved since. The updates a quest event causes don't
-- come through here (see Dim finished objectives); the frames `measure` watches refit the box then.
local function onUpdate()
    if styled() then
        Profiler.Call(PART_FONTS, findFonts, tracker(), 4)
    end
    styleLines()
    Profiler.Call(PART_FIT, fitBox)
    fitSettled()
end

-- Fading ------------------------------------------------------------------------------------------

local function setFaded(on)
    on = on and module.db.fade
    if on == faded then
        return
    end
    faded = on
    tracker():SetAlpha(on and module.db.fadeOpacity / 100 or 1)
end

-- Sorting -----------------------------------------------------------------------------------------
-- The tracker lists quests in watch list order (after callings and quests that set their own
-- place) and has no sort of its own, and the comparison is a local in its code. So Sort Quests
-- reorders the watch list: it untracks the quests out of place and tracks them again in level
-- order. These are plain C_QuestLog calls, not the tracker's code; the tracker only marks itself
-- dirty on QUEST_WATCH_LIST_CHANGED and redraws on its own next frame, and since the blocks still
-- exist then, it plays no "quest added" fanfare. Out of combat only, to keep well away from the
-- quest item buttons.
-- On Forever, tracking a quest again puts it at the top of the list, not the end (seen when Lowest
-- First came out highest first), so the first sort checks which end it goes to and learns.

local SORT_DELAY = 0.2 -- seconds; one sort after a burst of quest log events
local sortAfterCombat = false
local sortGaveUp = false -- the client kept neither order, so stop trying until turned on again
local addsToTop = true -- AddQuestWatch puts the quest first rather than last
local addEndKnown = false -- a sort has shown which end it goes to

-- Whether the watch list holds exactly `ids`, in that order.
local function watchesMatch(ids)
    if C_QuestLog.GetNumQuestWatches() ~= #ids then
        return false
    end
    for i = 1, #ids do
        if C_QuestLog.GetQuestIDForQuestWatchIndex(i) ~= ids[i] then
            return false
        end
    end
    return true
end

local requestSort
local questHeaders -- under Current zone, below

local function sortWatches()
    local order = module.db.sort
    if not module.enabled or order == "off" or sortGaveUp then
        return
    end
    if InCombatLockdown() then
        sortAfterCombat = true
        return
    end
    -- Current Zone First: each quest's zone is its quest log header, as Current Zone Only reads
    -- it. The zone you're in is group 0, the rest follow in the quest log's order, and a quest
    -- under no header (or a collapsed one) goes last.
    local headers, zoneOrder, here
    if order == "zone" then
        headers, zoneOrder = questHeaders()
        here = GetRealZoneText()
        here = type(here) == "string" and here:lower() or nil
    end
    local watched = {}
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        local level = Quests.Level(questID)
        if not level then
            return -- the quest log isn't ready; its next update sorts again
        end
        local group = 0
        if headers then
            local header = headers[questID]
            if not header then
                group = huge
            elseif header:lower() ~= here then
                group = zoneOrder[header] or huge
            end
        end
        watched[i] = { id = questID, level = level, index = i, group = group }
    end
    local sorted = {}
    for i, quest in ipairs(watched) do
        sorted[i] = quest
    end
    -- Same level keeps the order they were tracked in.
    local highFirst = order == "high"
    sort(sorted, function(a, b)
        if a.group ~= b.group then
            return a.group < b.group
        end
        if a.level ~= b.level then
            if highFirst then
                return a.level > b.level
            end
            return a.level < b.level
        end
        return a.index < b.index
    end)
    -- The quests already in place at the end they're added at stay; the rest are tracked again.
    -- Adding to the top, they go in from the last out of place to the first.
    local from, to, step
    if addsToTop then
        for i = #sorted, 1, -1 do
            if sorted[i] ~= watched[i] then
                from, to, step = i, 1, -1
                break
            end
        end
    else
        for i = 1, #sorted do
            if sorted[i] ~= watched[i] then
                from, to, step = i, #sorted, 1
                break
            end
        end
    end
    if not from then
        return
    end
    local ids = {}
    for i, quest in ipairs(sorted) do
        ids[i] = quest.id
    end
    -- Untracking a quest can drop it as the quest the map and arrow follow, so put that back.
    local super = ns.Quests.Selected()
    for i = from, to, step do
        C_QuestLog.RemoveQuestWatch(ids[i])
    end
    for i = from, to, step do
        C_QuestLog.AddQuestWatch(ids[i])
    end
    if super and C_SuperTrack.SetSuperTrackedQuestID and ns.Quests.Selected() ~= super then
        C_SuperTrack.SetSuperTrackedQuestID(super)
    end
    -- Check the order once the client has it. Wrong the first time means quests go to the other
    -- end, so sort again that way; wrong after that, and this client keeps its own order.
    C_Timer.After(0, function()
        if watchesMatch(ids) then
            addEndKnown = true
        elseif not addEndKnown then
            addEndKnown = true
            addsToTop = not addsToTop
            requestSort()
        else
            sortGaveUp = true
        end
    end)
end

requestSort = ns.Frames.Coalesce(function() Profiler.Call(PART_SORT, sortWatches) end, SORT_DELAY)

local function onCombatEnd()
    if sortAfterCombat then
        sortAfterCombat = false
        requestSort()
    end
end

-- Listens for new quests and tracking only while Sort Quests is on. A new zone matters to Current
-- Zone First, and Blizzard's tracker reorders the watch list itself then
-- (ObjectiveTrackerFrameMixin:OnEvent, C_QuestLog.SortQuestWatches).
module:OnWhile("sort", {
    QUEST_WATCH_LIST_CHANGED = requestSort,
    QUEST_LOG_UPDATE = requestSort,
    ZONE_CHANGED_NEW_AREA = requestSort,
    PLAYER_REGEN_ENABLED = onCombatEnd,
})

local function setSorting(on)
    if on then
        sortGaveUp = false
        requestSort()
    else
        sortAfterCombat = false
    end
end

-- Current zone ------------------------------------------------------------------------------------
-- Current Zone Only works on the watch list too: it untracks the tracked quests of other zones and
-- tracks them again once you're there, remembering which it untracked (per character, so a reload
-- or logout keeps them). A quest's zone is its quest log header, as the log groups them. A header
-- that names no map or instance (a class, a profession, a holiday) goes by the zone of the quest's
-- objective on the map instead, and shows when the map doesn't know it. The quest the map and
-- arrow follow always shows. It filters once each time you arrive in a zone, so a quest tracked
-- by hand stays until you leave. Out of combat only, like sorting; Sort Quests then sorts
-- what's left as the watch list changes.

local AZEROTH = ns.WorldMap.AZEROTH -- Forever's Azeroth map, over every zone and instance
local mapNames -- lowercase name -> true for every map under Azeroth, made when first needed
local filteredZone -- the zone the watch list was last filtered for
local zoneAfterCombat = false

-- The quests Current Zone Only untracked on this character (saved per character), or nil when it
-- untracked none, unless `create` asks for the table anyway.
local function hiddenQuests(create)
    local hidden = module.db.hidden
    if next(hidden) == nil and not create then
        return nil
    end
    return hidden
end

---Whether a quest log header names a place: a map under Azeroth, or a dungeon or raid.
---@param header string
---@return boolean
local function isPlace(header)
    if not mapNames then
        mapNames = {}
        if C_Map and C_Map.GetMapChildrenInfo then
            for _, info in ipairs(C_Map.GetMapChildrenInfo(AZEROTH, nil, true) or {}) do
                if type(info.name) == "string" then
                    mapNames[info.name:lower()] = true
                end
            end
        end
    end
    -- Without the map list, every header counts as a place rather than none.
    return next(mapNames) == nil or mapNames[header:lower()] or ns.Instances.ByName(header) ~= nil
end

local ZONE_MAP = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

---The zone a map is in: the map itself, or the zone over a dungeon, building, or cave in it. Nil
---for a continent or the world, or no map (GetQuestUiMapID gives 0 when it doesn't know).
---@param mapID number?
---@return number?
local function zoneMap(mapID)
    local info = mapID and mapID ~= 0 and C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType > ZONE_MAP do
        local parent = info.parentMapID and info.parentMapID ~= 0 and C_Map.GetMapInfo(info.parentMapID)
        if not (parent and parent.mapType and parent.mapType >= ZONE_MAP) then
            return info.mapID -- a dungeon right under a continent counts as its own zone
        end
        info = parent
    end
    return info and info.mapType == ZONE_MAP and info.mapID or nil
end

-- Each quest in the log by ID -> the title of the header it's under, and each header's title ->
-- its place among the headers.
function questHeaders()
    local headers, order, header, count = {}, {}, nil, 0
    for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            header = info.title
            if type(header) == "string" and not order[header] then
                count = count + 1
                order[header] = count
            end
        elseif info and info.questID and type(header) == "string" then
            headers[info.questID] = header
        end
    end
    return headers, order
end

-- The watch list as questID -> true.
local function watchedQuests()
    local watched = {}
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            watched[questID] = true
        end
    end
    return watched
end
internal.watchedQuests = watchedQuests

-- Whether a quest in the log is ready to turn in.
local function questComplete(questID)
    return C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and true or false
end

-- Drops every quest that's tracked again from the hidden list: one the player tracks again by hand
-- is theirs to keep, and one filterZone tracked again in its zone is no longer hidden.
local function onWatchListChanged()
    local hidden = hiddenQuests()
    if not hidden then
        return
    end
    local watched = watchedQuests()
    for questID in pairs(hidden) do
        if watched[questID] then
            hidden[questID] = nil
        end
    end
end

local function filterZone()
    if not (module.enabled and module.db.zone) then
        return
    end
    local zone = GetRealZoneText()
    if type(zone) ~= "string" or zone == "" or zone == filteredZone then
        return
    end
    if InCombatLockdown() then
        zoneAfterCombat = true
        return
    end
    if (C_QuestLog.GetNumQuestLogEntries()) == 0 then
        return -- the quest log isn't ready (or is empty); its next update filters
    end
    filteredZone = zone
    zone = zone:lower()
    local headers = questHeaders()
    local super = ns.Quests.Selected()
    -- A quest not under any header (or under a collapsed one) shows, rather than going unseen.
    local here = C_Map and C_Map.GetBestMapForUnit and zoneMap(C_Map.GetBestMapForUnit("player"))
    local function belongs(questID)
        local header = headers[questID]
        if questID == super or not header or header:lower() == zone then
            return true
        end
        -- Where its objective is, when the map knows.
        local there = here and GetQuestUiMapID and zoneMap(GetQuestUiMapID(questID, true))
        if isPlace(header) then
            -- A dungeon's quest sits under the zone that gave it, but belongs inside the dungeon.
            if there and there == here then
                return true
            end
            return C_QuestLog.IsOnMap and (C_QuestLog.IsOnMap(questID)) and true or false
        end
        -- A class or profession quest goes by where its objective is.
        return not there or there == here
    end
    -- Untrack first, so the quests tracked again here have room under the watch limit.
    local leaving = {}
    for questID in pairs(watchedQuests()) do
        if not belongs(questID) then
            leaving[#leaving + 1] = questID
        end
    end
    local hidden = hiddenQuests(#leaving > 0)
    for _, questID in ipairs(leaving) do
        C_QuestLog.RemoveQuestWatch(questID)
        hidden[questID] = true
    end
    if not hidden then
        return
    end
    local holdDone = module.db.completed
    for questID in pairs(hidden) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then
            hidden[questID] = nil -- turned in or abandoned
        elseif holdDone and questComplete(questID) then
            -- Left hidden: Hide Completed Quests takes it over at its next pass.
        elseif belongs(questID) then
            C_QuestLog.AddQuestWatch(questID)
        end
    end
    -- One the watch limit kept out stays hidden, to try again in the next zone.
    onWatchListChanged()
end

local function onZoneCombatEnd()
    if zoneAfterCombat then
        zoneAfterCombat = false
        filterZone()
    end
end

-- Tracks every quest Current Zone Only untracked on this character again.
local function restoreHidden()
    ns.AfterCombat(function()
        local hidden = hiddenQuests()
        if not hidden then
            return
        end
        for questID in pairs(hidden) do
            C_QuestLog.AddQuestWatch(questID)
        end
        module.db.hidden = {}
    end)
end

module:OnWhile("zone", {
    ZONE_CHANGED_NEW_AREA = filterZone,
    PLAYER_ENTERING_WORLD = filterZone,
    -- Only acts on a new zone, so this just catches the quest log becoming ready.
    QUEST_LOG_UPDATE = filterZone,
    QUEST_WATCH_LIST_CHANGED = onWatchListChanged,
    PLAYER_REGEN_ENABLED = onZoneCombatEnd,
})

local function setZoneFilter(on)
    filteredZone = nil
    zoneAfterCombat = false
    if on then
        filterZone()
    else
        restoreHidden()
    end
end

-- Completed quests --------------------------------------------------------------------------------
-- Hide Completed Quests untracks a tracked quest once it's ready to turn in, and remembers it per
-- character, as Current Zone Only does. The two never track again a quest the other still hides:
-- a quest Current Zone Only hid that is completed moves to this list, and one this list gives back
-- while Current Zone Only is on goes to that list, for it to place. A quest the player tracks
-- again by hand is theirs to keep. Out of combat only. The quest the map and arrow follow keeps
-- being followed after it leaves the tracker.
-- Hiding a quest's finished objectives instead isn't offered: the tracker's block adds up its own
-- height line by line as it lays out (Blizzard_ObjectiveTrackerBlock.lua, AddObjective), so a
-- line can only leave without a gap by changing that sum, a field of Blizzard's that the
-- tracker's layout of the quest item buttons reads. Dim Finished Objectives fades them instead.

local DONE_DELAY = 0.5 -- seconds; one pass after a burst of quest log events
local doneAfterCombat = false

-- Gives back a quest Hide Completed Quests untracked: to Current Zone Only when `toZone`, else
-- tracked again. Returns whether it went to Current Zone Only, which then has to filter again.
local function giveBack(questID, toZone)
    if toZone then
        module.db.hidden[questID] = true
        return true
    end
    C_QuestLog.AddQuestWatch(questID)
    return false
end

local function refilterZone()
    filteredZone = nil
    filterZone()
end

local function hideCompleted()
    if not (module.enabled and module.db.completed) then
        return
    end
    if InCombatLockdown() then
        doneAfterCombat = true
        return
    end
    if (C_QuestLog.GetNumQuestLogEntries()) == 0 or not C_QuestLog.IsComplete then
        return -- the quest log isn't ready (or is empty); its next update looks again
    end
    local done, hidden = module.db.done, module.db.hidden
    local toZone = module.db.zone and true or false
    local refilter = false
    for questID, untracked in pairs(done) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then
            done[questID] = nil -- turned in or abandoned
        elseif not questComplete(questID) then
            done[questID] = nil -- some objectives can be undone, like an item sold
            if untracked and giveBack(questID, toZone) then
                refilter = true
            end
        end
    end
    for questID in pairs(hidden) do
        if questComplete(questID) then
            hidden[questID] = nil
            if done[questID] == nil then
                done[questID] = true
            end
        end
    end
    -- One already on the list (or kept by hand) and tracked stays.
    local super = ns.Quests.Selected()
    local removed = false
    for questID in pairs(watchedQuests()) do
        if done[questID] == nil and questComplete(questID) then
            C_QuestLog.RemoveQuestWatch(questID)
            done[questID] = true
            removed = true
        end
    end
    if removed and super and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
        and ns.Quests.Selected() ~= super then
        C_SuperTrack.SetSuperTrackedQuestID(super)
    end
    if refilter then
        refilterZone()
    end
end

local requestDone = ns.Frames.Coalesce(hideCompleted, DONE_DELAY, module)

-- A quest on the list that's tracked again was tracked by hand: this list never tracks one, and
-- Current Zone Only never gets one back while it's on the list.
local function onDoneWatchListChanged()
    local done = module.db.done
    if next(done) ~= nil then
        local watched = watchedQuests()
        for questID, untracked in pairs(done) do
            if untracked and watched[questID] then
                done[questID] = false
            end
        end
    end
    requestDone()
end

local function onDoneCombatEnd()
    if doneAfterCombat then
        doneAfterCombat = false
        requestDone()
    end
end

-- Gives back every quest Hide Completed Quests untracked on this character: to Current Zone Only
-- when `toZone`, else tracked again.
local function restoreDone(toZone)
    ns.AfterCombat(function()
        local done = module.db.done
        if next(done) == nil then
            return
        end
        module.db.done = {}
        local refilter = false
        for questID, untracked in pairs(done) do
            if untracked and giveBack(questID, toZone) then
                refilter = true
            end
        end
        if refilter then
            refilterZone()
        end
    end)
end

module:OnWhile("completed", {
    QUEST_LOG_UPDATE = requestDone,
    QUEST_WATCH_LIST_CHANGED = onDoneWatchListChanged,
    PLAYER_REGEN_ENABLED = onDoneCombatEnd,
})

local function setDoneFilter(on)
    doneAfterCombat = false
    if on then
        requestDone()
    else
        restoreDone(module.db.zone and true or false)
    end
end

-- Collapse at login -------------------------------------------------------------------------------
-- The tracker starts every session expanded and keeps no setting for it, so the only way to start
-- collapsed is its own SetCollapsed, as its header button calls and as other addons do (Quest Log
-- Collapse, MinimizeAllObjectives). That runs one tracker update as addon code, the thing the rest
-- of this file avoids, so it's off by default, runs only at login and after a reload (not on
-- other loading screens), and waits out combat. Idea from afrayedknot1337 on CurseForge.
local function collapseAtLogin(_, isLogin, isReload)
    -- Not with the controller interface on: the tracker's update also steers the controller's
    -- cursor then (Blizzard_ObjectiveTracker.lua), which refuses a call from addon code.
    if not (isLogin or isReload) or ns.Gamepad.On() then
        return
    end
    ns.AfterCombat(function()
        local frame = tracker()
        if module.enabled and module.db.collapse and frame.SetCollapsed and frame.IsCollapsed
            and not frame:IsCollapsed() then
            frame:SetCollapsed(true)
        end
    end)
end

module:OnWhile("collapse", { PLAYER_ENTERING_WORLD = collapseAtLogin })

-- Quest tooltip -----------------------------------------------------------------------------------
-- Quest Tooltip on Mouseover shows the quest's own tooltip (its link's: the title, what it asks,
-- and what's done) while the mouse is on its title in the tracker. Blizzard shows one there only
-- in a group (the party's progress, QuestObjectiveTrackerMixin:OnBlockHeaderEnter), and that one
-- stays. Either way it says the mouse came with EventRegistry's "OnQuestBlockHeader.OnEnter",
-- the last thing its handler does, which is what this hears; its OnBlockHeaderLeave hides
-- GameTooltip for us too.

local TOOLTIP_GAP = 30 -- pixels left of the title, clear of the quest's map button
local tooltipHeard = false -- the callback is registered; it can't be taken back per module

local function onBlockEnter(_, block, questID, inGroup)
    if not (module.enabled and module.db.tooltip) or inGroup or type(block) ~= "table" then
        return
    end
    local link = type(questID) == "number" and GetQuestLink and GetQuestLink(questID)
    if not ns.IsText(link, true) then
        return
    end
    GameTooltip:SetOwner(block, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", block, "TOPLEFT", -TOOLTIP_GAP, 0)
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

local function setTooltip()
    if module.db.tooltip and not tooltipHeard and EventRegistry and EventRegistry.RegisterCallback then
        tooltipHeard = true
        EventRegistry:RegisterCallback("OnQuestBlockHeader.OnEnter", onBlockEnter, module)
    end
end

-- Module ------------------------------------------------------------------------------------------

function module:IsAvailable()
    return ObjectiveTrackerFrame ~= nil
end

local updateLater = ns.Frames.Coalesce(onUpdate, nil, module)

function module:OnEnable()
    local frame = tracker()
    if styled() then
        applyFonts() -- at Blizzard's font and outline its fonts are left alone
    end
    if frame.Update then
        self:Hook(frame, "Update", onUpdate)
    else
        -- Mainline's tracker has Update; this covers a client where it doesn't.
        self:On("QUEST_LOG_UPDATE", updateLater)
        self:On("QUEST_WATCH_LIST_CHANGED", updateLater)
    end
    for _, name in ipairs(QUEST_TRACKERS) do
        self:Hook(_G[name], "Update", onSectionUpdate)
    end
    -- The header's collapse and Edit Mode's height change what shows without always updating.
    self:HookScript(frame, "OnSizeChanged", requestFit)
    self:HookScript(frame, "OnShow", requestFit)
    self:On("PLAYER_REGEN_DISABLED", function() setFaded(true) end)
    self:On("PLAYER_REGEN_ENABLED", function() setFaded(false) end)
    setFaded(InCombatLockdown())
    setSorting(self.db.sort ~= "off")
    setZoneFilter(self.db.zone)
    setDoneFilter(self.db.completed)
    internal.updateHeader()
    setTooltip()
    onUpdate()
end

function module:OnDisable()
    internal.updateHeader()
    restoreFonts()
    undim()
    uncolor()
    restoreHidden()
    restoreDone(false)
    if box then
        box:Hide()
    end
    if faded then
        faded = false
        tracker():SetAlpha(1)
    end
end

function module:OnOptionChanged(key)
    if not self.enabled then
        return
    end
    if key == "count" or key == "zones" then
        internal.updateHeader()
    elseif key == "tooltip" then
        setTooltip()
    elseif key == "font" or key == "outline" then
        if styled() then
            applyFonts()
        else
            restoreFonts()
        end
        fitBox()
    elseif key == "fade" then
        setFaded(InCombatLockdown())
    elseif key == "fadeOpacity" then
        if faded then
            tracker():SetAlpha(self.db.fadeOpacity / 100)
        end
    elseif key == "sort" then
        setSorting(self.db.sort ~= "off")
    elseif key == "zone" then
        setZoneFilter(self.db.zone)
    elseif key == "completed" then
        setDoneFilter(self.db.completed)
    elseif key == "dim" or key == "dimOpacity" or key == "progress" then
        styleLines()
    else
        fitBox()
    end
end
