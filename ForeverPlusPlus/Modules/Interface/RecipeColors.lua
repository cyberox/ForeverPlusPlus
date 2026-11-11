-- Recipe Colors: colors each recipe in the professions window by its chance of a skill-up, as the
-- old trade skill window did: orange always, yellow usually, green sometimes, gray never. Blizzard
-- shows that with small arrows; this adds the color. Ideas from ColorCraft; none of its code.
-- It also shows how long a recipe keeps giving skill-ups: the skill it turns gray at, from the
-- game's recipe info (maxTrivialLevel), as a number on its row and a line on its details.
--
-- Blizzard's recipe row sets its name color when it is built (Init) and after the mouse leaves
-- (OnLeave), so both are hooked and the color put back after them. Guild, NPC, and runeforging
-- lists have no skill-ups, and are left alone.
local _, ns = ...

local setmetatable, ipairs, pairs, pcall = setmetatable, ipairs, pairs, pcall
local format, tostring, type, sort, concat = string.format, tostring, type, table.sort, table.concat
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L

local module = ns.NewModule("RecipeColors", L.RECIPECOLORS_DESC, {
    enabled = true,
    highlight = true, -- tint the row's selected and mouse-over highlights too
    gray = true, -- learned recipes that can't raise the skill any more are gray
    points = "left", -- the number on a row: "left" (skill-ups left), "gray" (the skill it's gray at), "off"
    detail = true, -- "Skill-ups until 125 (7 more)" by the selected recipe's name
})
module.title = L.RECIPECOLORS_TITLE
module.category = "interface"

module.options = {
    { key = "highlight", name = L.RECIPECOLORS_HIGHLIGHT, description = L.RECIPECOLORS_HIGHLIGHT_DESC },
    { key = "gray", name = L.RECIPECOLORS_GRAY, description = L.RECIPECOLORS_GRAY_DESC },
    {
        key = "points", name = L.RECIPECOLORS_POINTS, description = L.RECIPECOLORS_POINTS_DESC,
        choices = {
            { "left", L.RECIPECOLORS_POINTS_LEFT },
            { "gray", L.RECIPECOLORS_POINTS_GRAY },
            { "off", L.RECIPECOLORS_POINTS_OFF },
        },
        added = "1.5.0",
    },
    { key = "detail", name = L.RECIPECOLORS_DETAIL, description = L.RECIPECOLORS_DETAIL_DESC, added = "1.5.0" },
}

-- Blizzard's own difficulty colors (FrameXML's), by Enum.TradeskillRelativeDifficulty. Probe: the
-- enum and the constants are Mainline's.
local COLORS
local TRIVIAL
local function colors()
    if COLORS == nil then
        COLORS = false
        local E = Enum and Enum.TradeskillRelativeDifficulty
        if E and DIFFICULT_DIFFICULTY_COLOR and FAIR_DIFFICULTY_COLOR and EASY_DIFFICULTY_COLOR then
            TRIVIAL = TRIVIAL_DIFFICULTY_COLOR or GRAY_FONT_COLOR
            COLORS = {
                [E.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
                [E.Medium] = FAIR_DIFFICULTY_COLOR,
                [E.Easy] = EASY_DIFFICULTY_COLOR,
                [E.Trivial] = TRIVIAL,
            }
        end
    end
    return COLORS
end

-- Guild, NPC, and runeforging lists have no skill-ups. Probe: each call is Mainline's.
local function listHasSkillUps()
    local T = C_TradeSkillUI
    if not T then
        return false
    end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then
        return false
    end
    if T.IsNPCCrafting and T.IsNPCCrafting() then
        return false
    end
    if T.IsRuneforging and T.IsRuneforging() then
        return false
    end
    return true
end

-- Blizzard's gold highlight art turned gray, then colored, so the tint is clean instead of gold
-- times the color. Rows are reused, so a row without a color gets Blizzard's gold back.
local HIGHLIGHTS = { "SelectedOverlay", "HighlightOverlay" }
local tinted = setmetatable({}, { __mode = "k" }) -- rows with a tint now, shown or pooled

local function tint(row, r, g, b)
    tinted[row] = r and true or nil
    for _, key in ipairs(HIGHLIGHTS) do
        local texture = row[key]
        if texture and texture.SetVertexColor then
            if r then
                texture:SetDesaturated(true)
                texture:SetVertexColor(r, g, b)
            else
                texture:SetDesaturated(false)
                texture:SetVertexColor(1, 1, 1)
            end
        end
    end
end

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
    local progress = ns.Professions.Progress
    return (parent and progress(parent)) or (line and progress(line)) or nil
end

-- The skill a learned recipe turns gray at, or nil when the game doesn't say.
local function grayAt(info)
    local level = info and info.maxTrivialLevel
    if type(level) == "number" and level > 0 then
        return level
    end
end

-- The recipe a row or the form is about: a recipe with ranks shows its best one you know.
local function bestRank(info)
    if info and Professions and Professions.GetHighestLearnedRecipe then
        return Professions.GetHighestLearnedRecipe(info) or info
    end
    return info
end

-- Whether a recipe gets a gray level shown: a known one, in a list with skill-ups.
local function counts(info)
    return info and info.learned and not info.disabled and grayAt(info) and listHasSkillUps()
end

-- The number on a row: the skill-ups left until gray, or the skill it turns gray at, as the Row
-- Number option says. Nothing on a recipe that's gray already. Its own column at the row's right
-- end (Professions.NewRowColumn), left of Appearance Icons' mark while that's in use, and taking
-- no space itself while the option is off or the list has no skill-ups.
local numberColumn = ns.Professions.NewRowColumn(20, 20, 2) -- up to three digits
local numbers = ns.ItemButtons.Overlays(function(row)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("RIGHT")
    text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    return text
end)

local function rowNumber(row, info)
    local mode = module.db.points
    local gray = module.enabled and mode ~= "off" and counts(info) and info.canSkillUp and grayAt(info)
    local value = gray
    if gray and mode == "left" then
        local skill = skillOf(info.recipeID)
        value = skill and gray - skill
        if value and value <= 0 then
            value = nil -- the colors say it can still skill up; trust them over the sum
        end
    end
    numberColumn:Use(module.enabled and mode ~= "off" and listHasSkillUps())
    local text = numbers:Set(row, value)
    if text then
        text:SetText(value)
    end
    numberColumn:Place(row, text)
end

-- Rows -------------------------------------------------------------------------------------------

local function paint(row, node)
    if not (row and row.Label) then
        return
    end
    if not module.enabled then
        tint(row)
        numbers:Set(row, false)
        numberColumn:Use(false)
        return
    end
    node = node or (row.GetElementData and row:GetElementData())
    local data = node and (node.GetData and node:GetData() or node.data)
    local info = bestRank(data and data.recipeInfo)
    rowNumber(row, info)
    local all = colors()
    if not (all and info and info.learned and not info.disabled and listHasSkillUps()) then
        tint(row)
        return
    end
    local color
    if info.canSkillUp then
        color = all[info.relativeDifficulty]
    elseif module.db.gray then
        color = TRIVIAL
    end
    if not color then
        tint(row)
        return
    end
    local r, g, b = color:GetRGB()
    tint(row, module.db.highlight and r or nil, g, b)
    -- Blizzard's white mouse-over text stays while the mouse is on the row.
    if row.IsMouseOver and row:IsMouseOver() then
        return
    end
    row.Label:SetVertexColor(r, g, b)
    if row.Count then
        row.Count:SetVertexColor(r, g, b)
    end
end

local function onLeave(row)
    paint(row)
end

local recipeRows = ns.Professions.EachRecipeRow
local ROW_HOOKS = { Init = paint, OnLeave = onLeave }

-- The selected recipe ------------------------------------------------------------------------------
-- A line by the recipe's name on Blizzard's recipe form: "Skill-ups until 125 (7 more)". The form
-- (Blizzard_ProfessionsRecipeSchematicForm, Gethe forever branch) puts the name beside the output
-- icon, 17 pixels above its middle, and the tools it needs ("Requires: Anvil") under the name; this
-- line goes 17 below the icon's middle, so it sits under both without moving anything of Blizzard's.

local DETAIL_X, DETAIL_Y = 14, -17
local detail -- our font string on the form, made the first time a recipe shows

local function craftForm()
    local frame = _G.ProfessionsFrame
    local page = frame and frame.CraftingPage
    return page and page.SchematicForm
end

local function detailText(info)
    local gray = counts(info) and grayAt(info)
    if not gray then
        return nil
    elseif not info.canSkillUp then
        return format(L.RECIPECOLORS_DETAIL_DONE, gray)
    end
    local skill = skillOf(info.recipeID)
    local left = skill and gray - skill
    if left and left > 0 then
        return format(L.RECIPECOLORS_DETAIL_MORE, gray,
            GRAY_FONT_COLOR:WrapTextInColorCode(format(L.RECIPECOLORS_DETAIL_LEFT, left)))
    end
    return format(L.RECIPECOLORS_DETAIL_UNTIL, gray)
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
    recipeRows(paint)
    local form = craftForm()
    if form then
        drawDetail(form, form.currentRecipeInfo)
    end
end

-- The rows' mixin and the form are in a load-on-demand Blizzard addon: hooked once they're there.
local function hook()
    module:Hook(craftForm(), "Init", drawDetail)
    return ns.Professions.HookRecipeRows(module, ROW_HOOKS)
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

-- Blizzard draws the row's colors itself when it's built again; ours go back by clearing the
-- highlight tint of every row that has one (pooled rows too, since Blizzard never resets it), and
-- by building each visible row again, with the list's own second argument as Blizzard does.
function module:OnDisable()
    for row in pairs(tinted) do
        tint(row)
    end
    numbers:HideAll()
    numberColumn:Use(false)
    if detail then
        detail:Hide()
    end
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local hideCount = page and page.RecipeList and page.RecipeList.hideCraftableCount
    recipeRows(function(row)
        if row.Init and row.GetElementData then
            local node = row:GetElementData()
            if node then
                pcall(row.Init, row, node, hideCount)
            end
        end
    end)
end

function module:OnOptionChanged()
    if self.enabled then
        catchUp()
    end
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
        ns.Print(L.RECIPECOLORS_DUMP_NONE)
        return
    end
    -- The window's profession: on Forever the child profession's info came back empty (2026-11-09,
    -- "skill 0 of 0"), so both are printed with their skill line, to learn which one has it.
    for _, get in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
        local profession = T[get] and T[get]()
        if profession then
            ns.Print(format(L.RECIPECOLORS_DUMP_SKILL, get, tostring(profession.professionName),
                tostring(profession.professionID), tostring(profession.skillLevel),
                tostring(profession.maxSkillLevel)))
        end
    end
    -- The recipe selected in the window, in full, or else the first one known.
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
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
                ns.Print(format(L.RECIPECOLORS_DUMP_ROW, tostring(info.name), id,
                    tostring(info.maxTrivialLevel), tostring(info.relativeDifficulty),
                    tostring(info.numSkillUps)))
            end
        end
    end
    if selected then
        ns.Print(format(L.RECIPECOLORS_DUMP_FIELDS, tostring(selected.name), fields(selected)))
        -- The skill line the recipe gives and the skill the row numbers count from.
        local line, parent
        if T.GetTradeSkillLineForRecipe then
            local first, _, third = T.GetTradeSkillLineForRecipe(selected.recipeID)
            line, parent = first, third
        end
        ns.Print(format(L.RECIPECOLORS_DUMP_LINE, tostring(line), tostring(parent),
            tostring(skillOf(selected.recipeID))))
    end
    ns.Print(format(L.RECIPECOLORS_DUMP_COUNT, given, known))
end

module.debugActions = {
    {
        name = L.RECIPECOLORS_DUMP, button = L.RECIPECOLORS_DUMP_BUTTON,
        description = L.RECIPECOLORS_DUMP_DESC, section = L.DEBUG_SECTION_DIAGNOSTICS,
        whileOff = true, fn = dumpRecipes,
    },
}
