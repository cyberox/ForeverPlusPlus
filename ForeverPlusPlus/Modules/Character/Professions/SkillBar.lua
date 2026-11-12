-- Professions' Skill Bar: under the selected recipe's name, a bar of the skill levels the recipe
-- turns yellow, green, and gray at, with the player's skill marked on it, so a player buying
-- materials can see how long the recipe stays worth crafting (GitHub issue #9; the idea from
-- SkillUp Forever, none of its code).
--
-- The game's recipe info gives only the gray level (maxTrivialLevel) and the color now
-- (relativeDifficulty). The yellow level comes from its SkillLineAbility table (Data.lua, made by
-- tools/datagen), and green is worked out from the two (ns.Professions.RecipeLevels). A recipe
-- whose table entry doesn't match the game (another gray level, or levels that give another color
-- than the game shows at the player's skill) gets no bar, so a patch can't make it lie.
local _, ns = ...

local _G, ipairs, pairs, type, format, tostring = _G, ipairs, pairs, type, string.format, tostring
local CreateFrame = CreateFrame
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L
local Professions = ns.Professions -- ours; Blizzard's global of the same name is _G.Professions

local professions = ns.modules.Professions
local internal = professions.internal
local module = professions:NewPart({
    key = "skillBar", name = L.PROFESSIONS_BAR, description = L.PROFESSIONS_BAR_DESC,
    section = L.PROFESSIONS_BAR, added = "1.6.0",
}, {
    skillBarLevels = true, -- the level each color starts at, on the bar
})

module:AddOptions({
    { key = "skillBarLevels", name = L.PROFESSIONS_BAR_LEVELS, description = L.PROFESSIONS_BAR_LEVELS_DESC },
})

-- The levels are an estimate, said once on the Modules page while the part is on.
professions.notice[#professions.notice + 1] = {
    text = L.PROFESSIONS_BAR_ESTIMATE,
    description = L.PROFESSIONS_BAR_ESTIMATE_DESC,
    shown = function()
        return ns.PartOn(professions, "skillBar")
    end,
}

-- Levels -------------------------------------------------------------------------------------------

local DIFFICULTY = Professions.DIFFICULTY

-- The gray level the game gives, or nil.
local function grayOf(info)
    local level = info.maxTrivialLevel
    if type(level) == "number" and level > 0 then
        return level
    end
end

-- A known recipe's levels and the player's skill, or nil with why ("table" when the game's tables
-- have none or another gray level, "color" when they give another color than the game shows),
-- for the debug button.
local function levelsOf(info)
    if not (info and info.learned and not info.disabled and internal.ListHasSkillUps()) then
        return nil
    end
    local data = internal.recipeLevels
    local entry = data and data[info.skillLineAbilityID]
    local gray = grayOf(info)
    if not entry or (gray and gray ~= entry[2]) then
        return nil, "table"
    end
    local levels = Professions.RecipeLevels(entry[1], gray or entry[2])
    local skill = internal.SkillOf(info.recipeID)
    if not (levels and skill) then
        return nil
    end
    local shown = info.relativeDifficulty
    if type(shown) == "number" and Professions.LevelDifficulty(levels, skill) ~= shown then
        return nil, "color"
    end
    return levels, skill
end

-- The bar ------------------------------------------------------------------------------------------
-- Our frame on the form, on the row it shares with Skill-Ups Left's line (internal.PlaceOnForm):
-- Blizzard's status bar art in each color's share, with the level a color starts at on it, and a
-- white line at the player's skill. Its tooltip lists the levels.

local BAR_ORDER = 10 -- left of Skill-Ups Left's line (20)
local WIDTH, HEIGHT = 160, 12
local MARKER_OVERHANG = 3 -- how far the marker sticks out above and below the bar
local LABEL_INSET = 2
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local bar -- our frame, made the first time a recipe shows
local parts = {} -- a texture and a label for each color, by Professions.DIFFICULTY
local marker
local shown -- what the bar shows now: { levels, skill }, for its tooltip

local function onEnter(self)
    if not shown then
        return
    end
    local levels, skill = shown.levels, shown.skill
    local colors = internal.DifficultyColors()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.PROFESSIONS_BAR, 1, 1, 1)
    local rows = {
        { DIFFICULTY.MEDIUM, L.PROFESSIONS_BAR_YELLOW, levels.yellow },
        { DIFFICULTY.EASY, L.PROFESSIONS_BAR_GREEN, levels.green },
        { DIFFICULTY.TRIVIAL, L.PROFESSIONS_BAR_GRAY, levels.gray },
    }
    for _, row in ipairs(rows) do
        -- A recipe that goes from orange straight to gray has no yellow or green.
        if row[1] == DIFFICULTY.TRIVIAL or levels.yellow < levels.gray then
            local r, g, b = colors[row[1]]:GetRGB()
            GameTooltip:AddDoubleLine(row[2], row[3], r, g, b, 1, 1, 1)
        end
    end
    GameTooltip:AddDoubleLine(L.PROFESSIONS_BAR_SKILL, skill, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(L.PROFESSIONS_BAR_NOTE, 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function onLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function build(form)
    bar = CreateFrame("Frame", nil, form)
    bar:SetSize(WIDTH, HEIGHT)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", onEnter)
    bar:SetScript("OnLeave", onLeave)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    back:SetColorTexture(0, 0, 0, 0.75)
    local font = _G.GameFontHighlightSmallOutline and "GameFontHighlightSmallOutline" or "GameFontHighlightSmall"
    for _, difficulty in pairs(DIFFICULTY) do
        local texture = bar:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(TEXTURE)
        local label = bar:CreateFontString(nil, "OVERLAY", font)
        label:SetJustifyH("LEFT")
        parts[difficulty] = { texture = texture, label = label }
    end
    local edge = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetSize(4, HEIGHT + 2 * MARKER_OVERHANG + 2)
    marker = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    marker:SetColorTexture(1, 1, 1, 1)
    marker:SetSize(2, HEIGHT + 2 * MARKER_OVERHANG)
    edge:SetPoint("CENTER", marker)
end

local function hide(form)
    shown = nil
    if bar then
        bar:Hide()
        onLeave(bar)
        internal.PlaceOnForm(form, BAR_ORDER, nil)
    end
end

-- After the form shows a recipe (its Init), or with the recipe it shows now.
local function draw(form, info)
    local icon, name = form and form.OutputIcon, form and form.OutputText
    local colors = internal.DifficultyColors()
    local levels, skill
    if module.enabled and colors and icon and name and icon:IsShown() and name:IsShown() then
        levels, skill = levelsOf(info)
    end
    if not levels then
        hide(form)
        return
    end
    if not bar then
        build(form)
    end
    local layout = Professions.LevelBar(levels, skill)
    for _, part in pairs(parts) do
        part.texture:Hide()
        part.label:Hide()
    end
    for i, segment in ipairs(layout.segments) do
        local part = parts[segment[1]]
        local left, right = segment[2] * WIDTH, segment[3] * WIDTH
        part.texture:ClearAllPoints()
        part.texture:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
        part.texture:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", right, 0)
        part.texture:SetVertexColor(colors[segment[1]]:GetRGB())
        part.texture:Show()
        -- The level a color starts at, where it fits; the bar's start before yellow is no level.
        if i > 1 and module.db.skillBarLevels then
            local label = part.label
            label:SetText(segment[4])
            label:ClearAllPoints()
            label:SetPoint("LEFT", bar, "LEFT", left + LABEL_INSET, 0)
            label:SetShown(label:GetStringWidth() + LABEL_INSET <= right - left)
        end
    end
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", bar, "LEFT", layout.marker * WIDTH, 0)
    shown = { levels = levels, skill = skill }
    bar:Show()
    internal.PlaceOnForm(form, BAR_ORDER, bar)
end

-- The recipe the form shows, read again: a skill-up changes its color.
local function catchUp()
    local form = Professions.RecipeForm()
    if not form then
        return
    end
    local info = form.currentRecipeInfo
    local T = C_TradeSkillUI
    if info and info.recipeID and T and T.GetRecipeInfo then
        info = T.GetRecipeInfo(info.recipeID) or info
    end
    draw(form, info)
end

-- The form is in a load-on-demand Blizzard addon: hooked once it's there.
local function hook()
    local form = Professions.RecipeForm()
    module:Hook(form, "Init", draw)
    return form ~= nil
end

-- Once for a burst: the list update comes many times as the window fills.
local catchUpSoon = ns.Frames.Coalesce(catchUp, nil, module)

local function onEvent()
    if hook() then
        catchUpSoon()
    end
end

function module:OnEnable()
    hook()
    self:On("ADDON_LOADED", onEvent)
    self:On("TRADE_SKILL_SHOW", onEvent)
    self:On("TRADE_SKILL_LIST_UPDATE", onEvent)
    -- A skill-up moves the marker.
    self:On("SKILL_LINES_CHANGED", catchUpSoon)
    self:On("CHAT_MSG_SKILL", catchUpSoon)
    catchUp()
end

function module:OnDisable()
    hide(Professions.RecipeForm())
end

function module:OnOptionChanged()
    catchUp()
end

-- Debug: whether the game's tables fit the colors the game shows, for every recipe the open
-- profession knows, and the selected one's numbers.

local function dumpLevels()
    local T = C_TradeSkillUI
    local ids = T and T.GetAllRecipeIDs and T.GetAllRecipeIDs()
    if not (ids and #ids > 0 and T.GetRecipeInfo) then
        ns.Print(L.PROFESSIONS_DUMP_NONE)
        return
    end
    local fit, noTable, wrongColor = 0, 0, 0
    for _, id in ipairs(ids) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then
            local levels, why = levelsOf(info)
            if levels then
                fit = fit + 1
            elseif why == "table" then
                noTable = noTable + 1
            elseif why == "color" then
                wrongColor = wrongColor + 1
                ns.Print(format(L.PROFESSIONS_BAR_DUMP_WRONG, tostring(info.name), id,
                    tostring(info.relativeDifficulty)))
            end
        end
    end
    local form = Professions.RecipeForm()
    local selected = form and form.currentRecipeInfo
    if selected then
        local data = internal.recipeLevels
        local entry = data and data[selected.skillLineAbilityID]
        ns.Print(format(L.PROFESSIONS_BAR_DUMP_SELECTED, tostring(selected.name),
            tostring(selected.skillLineAbilityID), tostring(entry and entry[1]),
            tostring(entry and entry[2]), tostring(selected.maxTrivialLevel),
            tostring(selected.relativeDifficulty), tostring(internal.SkillOf(selected.recipeID))))
    end
    ns.Print(format(L.PROFESSIONS_BAR_DUMP_COUNT, fit, noTable, wrongColor))
end

professions.debugActions = professions.debugActions or {}
professions.debugActions[#professions.debugActions + 1] = {
    name = L.PROFESSIONS_BAR_DUMP, button = L.PROFESSIONS_DUMP_BUTTON,
    description = L.PROFESSIONS_BAR_DUMP_DESC, section = L.DEBUG_SECTION_DIAGNOSTICS,
    whileOff = true, fn = dumpLevels,
}
