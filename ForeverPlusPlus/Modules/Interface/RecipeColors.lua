-- Recipe Colors: colors each recipe in the professions window by its chance of a skill-up, as the
-- old trade skill window did: orange always, yellow usually, green sometimes, gray never. Blizzard
-- shows that with small arrows; this adds the color. Ideas from ColorCraft; none of its code.
--
-- Blizzard's recipe row sets its name color when it is built (Init) and after the mouse leaves
-- (OnLeave), so both are hooked and the color put back after them. Guild, NPC, and runeforging
-- lists have no skill-ups, and are left alone.
local _, ns = ...

local setmetatable, ipairs, pairs, pcall = setmetatable, ipairs, pairs, pcall
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L

local module = ns.NewModule("RecipeColors", L.RECIPECOLORS_DESC, {
    enabled = true,
    highlight = true, -- tint the row's selected and mouse-over highlights too
    gray = true, -- learned recipes that can't raise the skill any more are gray
})
module.title = L.RECIPECOLORS_TITLE
module.category = "interface"

module.options = {
    { key = "highlight", name = L.RECIPECOLORS_HIGHLIGHT, description = L.RECIPECOLORS_HIGHLIGHT_DESC },
    { key = "gray", name = L.RECIPECOLORS_GRAY, description = L.RECIPECOLORS_GRAY_DESC },
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

local function paint(row, node)
    if not (row and row.Label) then
        return
    end
    if not module.enabled then
        tint(row)
        return
    end
    node = node or (row.GetElementData and row:GetElementData())
    local data = node and (node.GetData and node:GetData() or node.data)
    local info = data and data.recipeInfo
    -- A recipe with ranks shows its best one you know.
    if info and Professions and Professions.GetHighestLearnedRecipe then
        info = Professions.GetHighestLearnedRecipe(info) or info
    end
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

local function catchUp()
    recipeRows(paint)
end

-- The rows' mixin is in a load-on-demand Blizzard addon: hooked once it's there.
local function hook()
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
    catchUp()
end

-- Blizzard draws the row's colors itself when it's built again; ours go back by clearing the
-- highlight tint of every row that has one (pooled rows too, since Blizzard never resets it), and
-- by building each visible row again, with the list's own second argument as Blizzard does.
function module:OnDisable()
    for row in pairs(tinted) do
        tint(row)
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
        recipeRows(paint)
    end
end
