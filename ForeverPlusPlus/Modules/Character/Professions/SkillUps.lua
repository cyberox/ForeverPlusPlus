-- Professions' Skill-Ups Left: how long a recipe keeps giving skill-ups, from the skill it turns
-- gray at (the game's maxTrivialLevel): a number at the end of its row in the recipe list, and a
-- line under the selected recipe's name. Guild, NPC, and runeforging lists have no skill-ups, and
-- are left alone.
local _, ns = ...

local ipairs, pairs = ipairs, pairs
local format, tostring, type, sort, concat = string.format, tostring, type, table.sort, table.concat
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L
local Professions = ns.Professions -- ours; Blizzard's global of the same name is _G.Professions

local professions = ns.modules.Professions
local internal = professions.internal
local module = professions:NewPart({
    key = "skillUps", name = L.PROFESSIONS_SKILLUPS, description = L.PROFESSIONS_SKILLUPS_DESC,
    section = L.PROFESSIONS_SKILLUPS,
}, {
    points = "left", -- the number on a row: "left" (skill-ups left), "gray" (the skill it's gray at), "off"
    detail = true, -- "Skill-ups until 125 (7 more)" by the selected recipe's name
})

module:AddOptions({
    {
        key = "points", name = L.PROFESSIONS_POINTS, description = L.PROFESSIONS_POINTS_DESC,
        choices = {
            { "left", L.PROFESSIONS_POINTS_LEFT },
            { "gray", L.PROFESSIONS_POINTS_GRAY },
            { "off", L.PROFESSIONS_POINTS_OFF },
        },
    },
    { key = "detail", name = L.PROFESSIONS_DETAIL, description = L.PROFESSIONS_DETAIL_DESC },
})

-- Gray levels --------------------------------------------------------------------------------------
-- A recipe turns gray at its maxTrivialLevel: on Forever every known recipe has one, and it matched
-- Classic's gray levels and the colors the game showed (2026-11-09, docs/forever-api.md). The
-- yellow and green levels aren't given, so this says how long a recipe gives skill-ups, never the
-- chance of one.

-- The skill the recipe's colors are measured against: the profession's level as its window shows
-- it (Professions.Progress), by the recipe's skill line or its parent's, whichever the player has.
-- Probe: GetTradeSkillLineForRecipe is Mainline's; which of the two lines Forever's recipes give is
-- Unverified, so both are tried.
local function skillOf(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetTradeSkillLineForRecipe and recipeID) then
        return nil
    end
    local line, _, parent = T.GetTradeSkillLineForRecipe(recipeID)
    local progress = Professions.Progress
    return (parent and progress(parent)) or (line and progress(line)) or nil
end

-- The skill a learned recipe turns gray at, or nil when the game doesn't say.
local function grayAt(info)
    local level = info and info.maxTrivialLevel
    if type(level) == "number" and level > 0 then
        return level
    end
end

-- Whether a recipe gets a gray level shown: a known one, in a list with skill-ups.
local function counts(info)
    return info and info.learned and not info.disabled and grayAt(info) and internal.ListHasSkillUps()
end

-- Rows -------------------------------------------------------------------------------------------
-- The number on a row: the skill-ups left until gray, or the skill it turns gray at, as the Row
-- Number option says. Nothing on a recipe that's gray already. Its own column at the row's right
-- end (Professions.NewRowColumn), left of Appearance Icons' mark while that's in use, and taking
-- no space itself while the option is off or the list has no skill-ups.

local numberColumn = Professions.NewRowColumn(20, 20, 2) -- up to three digits
local numbers = ns.ItemButtons.Overlays(function(row)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("RIGHT")
    text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    return text
end)

local function numbersOn()
    return module.enabled and module.db.points ~= "off"
end

local function rowNumber(row, node)
    if not (row and row.Label) then
        return
    end
    local value
    if numbersOn() then
        local info = Professions.RowRecipe(row, node)
        local gray = counts(info) and info.canSkillUp and grayAt(info)
        value = gray
        if gray and module.db.points == "left" then
            local skill = skillOf(info.recipeID)
            value = skill and gray - skill
            if value and value <= 0 then
                value = nil -- the colors say it can still skill up; trust them over the sum
            end
        end
    end
    numberColumn:Use(numbersOn() and internal.ListHasSkillUps())
    local text = numbers:Set(row, value)
    if text then
        text:SetText(value)
    end
    numberColumn:Place(row, text)
end

local ROW_HOOKS = { Init = rowNumber }

-- The selected recipe ------------------------------------------------------------------------------
-- A line by the recipe's name on Blizzard's recipe form: "Skill-ups until 125 (7 more)". The form
-- (Blizzard_ProfessionsRecipeSchematicForm, Gethe forever branch) puts the name beside the output
-- icon, 17 pixels above its middle, and the tools it needs ("Requires: Anvil") under the name; this
-- line goes 17 below the icon's middle, so it sits under both without moving anything of Blizzard's.

local DETAIL_X, DETAIL_Y = 14, -17
local detail -- our font string on the form, made the first time a recipe shows

local function detailText(info)
    local gray = counts(info) and grayAt(info)
    if not gray then
        return nil
    elseif not info.canSkillUp then
        return format(L.PROFESSIONS_DETAIL_DONE, gray)
    end
    local skill = skillOf(info.recipeID)
    local left = skill and gray - skill
    if left and left > 0 then
        return format(L.PROFESSIONS_DETAIL_MORE, gray,
            GRAY_FONT_COLOR:WrapTextInColorCode(format(L.PROFESSIONS_DETAIL_LEFT, left)))
    end
    return format(L.PROFESSIONS_DETAIL_UNTIL, gray)
end

-- After the form shows a recipe (its Init), or with the recipe it shows now.
local function drawDetail(form, info)
    local icon, name = form and form.OutputIcon, form and form.OutputText
    local text = module.enabled and module.db.detail and icon and name and icon:IsShown()
        and name:IsShown() and detailText(info)
    if not text then
        if detail then
            detail:Hide()
        end
        return
    end
    if not detail then
        local font = _G.GameFontHighlightSmall2 and "GameFontHighlightSmall2" or "GameFontHighlightSmall"
        detail = form:CreateFontString(nil, "OVERLAY", font)
        detail:SetJustifyH("LEFT")
        detail:SetPoint("LEFT", icon, "RIGHT", DETAIL_X, DETAIL_Y)
    end
    detail:SetText(text)
    detail:Show()
end

local function catchUp()
    Professions.EachRecipeRow(rowNumber)
    local form = Professions.RecipeForm()
    if form then
        drawDetail(form, form.currentRecipeInfo)
    end
end

-- The rows' mixin and the form are in a load-on-demand Blizzard addon: hooked once they're there.
local function hook()
    module:Hook(Professions.RecipeForm(), "Init", drawDetail)
    return Professions.HookRecipeRows(module, ROW_HOOKS)
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
    -- A skill-up changes how many are left.
    self:On("SKILL_LINES_CHANGED", catchUpSoon)
    self:On("CHAT_MSG_SKILL", catchUpSoon)
    catchUp()
end

function module:OnDisable()
    numbers:HideAll()
    numberColumn:Use(false)
    if detail then
        detail:Hide()
    end
end

function module:OnOptionChanged()
    catchUp()
end

-- Debug: what the game says about the open profession's recipes, to see whether it gives the
-- skill each one turns gray at (maxTrivialLevel, undocumented), which a skill-up chance would
-- need. Probe: every call is Mainline's; whether Forever fills the field is Unverified.

local DUMP_ROWS = 10 -- recipes listed one per line; the count covers the rest

-- Every plain field of a recipe's info, sorted by name: "key=value, ...".
local function fields(info)
    local list = {}
    for key, value in pairs(info) do
        if type(value) ~= "table" and type(value) ~= "function" then
            list[#list + 1] = tostring(key) .. "=" .. tostring(value)
        end
    end
    sort(list)
    return concat(list, ", ")
end

local function dumpRecipes()
    local T = C_TradeSkillUI
    local ids = T and T.GetAllRecipeIDs and T.GetAllRecipeIDs()
    if not (ids and #ids > 0 and T.GetRecipeInfo) then
        ns.Print(L.PROFESSIONS_DUMP_NONE)
        return
    end
    -- The window's profession: on Forever the child profession's info came back empty (2026-11-09,
    -- "skill 0 of 0"), so both are printed with their skill line, to learn which one has it.
    for _, get in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
        local profession = T[get] and T[get]()
        if profession then
            ns.Print(format(L.PROFESSIONS_DUMP_SKILL, get, tostring(profession.professionName),
                tostring(profession.professionID), tostring(profession.skillLevel),
                tostring(profession.maxSkillLevel)))
        end
    end
    -- The recipe selected in the window, in full, or else the first one known.
    local form = Professions.RecipeForm()
    local selected = form and form.currentRecipeInfo
    local known, given, listed = 0, 0, 0
    for _, id in ipairs(ids) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then
            known = known + 1
            selected = selected or info
            if type(info.maxTrivialLevel) == "number" and info.maxTrivialLevel > 0 then
                given = given + 1
            end
            if listed < DUMP_ROWS then
                listed = listed + 1
                ns.Print(format(L.PROFESSIONS_DUMP_ROW, tostring(info.name), id,
                    tostring(info.maxTrivialLevel), tostring(info.relativeDifficulty),
                    tostring(info.numSkillUps)))
            end
        end
    end
    if selected then
        ns.Print(format(L.PROFESSIONS_DUMP_FIELDS, tostring(selected.name), fields(selected)))
        -- The skill line the recipe gives and the skill the row numbers count from.
        local line, parent
        if T.GetTradeSkillLineForRecipe then
            local first, _, third = T.GetTradeSkillLineForRecipe(selected.recipeID)
            line, parent = first, third
        end
        ns.Print(format(L.PROFESSIONS_DUMP_LINE, tostring(line), tostring(parent),
            tostring(skillOf(selected.recipeID))))
    end
    ns.Print(format(L.PROFESSIONS_DUMP_COUNT, given, known))
end

professions.debugActions = {
    {
        name = L.PROFESSIONS_DUMP, button = L.PROFESSIONS_DUMP_BUTTON,
        description = L.PROFESSIONS_DUMP_DESC, section = L.DEBUG_SECTION_DIAGNOSTICS,
        whileOff = true, fn = dumpRecipes,
    },
}
