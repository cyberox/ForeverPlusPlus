-- Professions: what Forever++ adds to the professions window, in one module with a part for each,
-- in its own file: Recipe Colors (the recipe list colored by the chance of a skill-up), Skill-Ups
-- Left (how long each recipe keeps giving skill-ups), Skill Bar (the levels the selected recipe
-- changes color at, from the game's tables in Data.lua), Crafting Costs (what a recipe costs
-- and makes, from auction and merchant prices), and Unknown Recipes (the recipes not known yet,
-- from Data.lua too). Each part has its own checkbox heading its section
-- in Settings, works without the others, and shares only `module.internal` with them.
local _, ns = ...

local type, ipairs, pairs, sort = type, ipairs, pairs, table.sort
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L

local module = ns.NewModule("Professions", L.PROFESSIONS_DESC, {
    enabled = true,
})
module.title = L.PROFESSIONS_TITLE
module.category = "character"
module.added = "1.5.0"

-- Up to 1.4.0, Recipe Colors was a module of its own and Crafting Costs (with the merchant prices
-- it learns) was an option of Item Tooltips' Auction Prices. Each now is a part here, on or off as
-- the player saw it: Crafting Costs showed nothing while Item Tooltips or its Auction Prices was
-- off, so it starts off then; and Skill-Ups Left, new in 1.5.0 and Recipe Colors' until then,
-- follows Recipe Colors. The module is on while any part is. Every profile is moved alike (1.4.0
-- had only Default; profiles came in 1.5.0 too, so others are already in the new layout and only
-- the leftovers are cleared).
ns.Migrate(7, function(db)
    for _, root in ipairs(ns.Store.Roots(db)) do
        local settings = type(root.settings) == "table" and root.settings
        local colors = settings and type(settings.RecipeColors) == "table" and settings.RecipeColors
        local tooltips = settings and type(settings.ItemTooltips) == "table" and settings.ItemTooltips
        if colors or (tooltips and (tooltips.crafting ~= nil or tooltips.enabled == false
            or tooltips.auction == false)) then
            local new = type(settings.Professions) == "table" and settings.Professions or {}
            settings.Professions = new
            if colors then
                ns.MoveSettings(colors, new, { recipeColors = "enabled", "highlight", "gray" })
                if colors.enabled == false then
                    new.skillUps = false
                end
            end
            if tooltips then
                local shown = tooltips.enabled ~= false and tooltips.auction ~= false
                if not shown then
                    new.crafting = false
                elseif tooltips.crafting ~= nil then
                    new.crafting = tooltips.crafting
                end
            end
            local any = false
            for _, key in ipairs({ "recipeColors", "skillUps", "crafting" }) do
                any = any or new[key] ~= false
            end
            if not any then
                new.enabled = false
            end
        end
        if settings then
            settings.RecipeColors = nil
            if tooltips then
                tooltips.crafting, tooltips.craftingRows = nil, nil
            end
        end
        -- The Minimap Button's quick toggles kept by module name, in each profile.
        local data = type(root.data) == "table" and root.data
        local minimap = data and type(data.MinimapButton) == "table" and data.MinimapButton
        local picks = minimap and type(minimap.quickToggles) == "table" and minimap.quickToggles
        if picks then
            if picks.RecipeColors ~= nil and picks.Professions == nil then
                picks.Professions = picks.RecipeColors
            end
            picks.RecipeColors = nil
        end
    end
    -- What merchants charge, learned for the account (Default's data holds account data).
    local data = type(db.data) == "table" and db.data
    local tooltips = data and type(data.ItemTooltips) == "table" and data.ItemTooltips
    if tooltips and type(tooltips.vendor) == "table" then
        local new = type(data.Professions) == "table" and data.Professions or {}
        data.Professions = new
        if type(new.vendor) ~= "table" then
            new.vendor = tooltips.vendor
        end
        tooltips.vendor = nil
    end
    -- The version Recipe Colors was last seen in, for its NEW marks.
    local seen = type(db.seenModules) == "table" and db.seenModules
    if seen and seen.RecipeColors ~= nil then
        if seen.Professions == nil then
            seen.Professions = seen.RecipeColors
        end
        seen.RecipeColors = nil
    end
end)

local internal = {}
module.internal = internal

-- Guild, NPC, and runeforging lists have no skill-ups, so neither colors nor counts. Probe: each
-- call is Mainline's.
function internal.ListHasSkillUps()
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

-- The skill a recipe's colors are measured against: the profession's level as its window shows
-- it (ns.Professions.Progress), by the recipe's skill line or its parent's, whichever the player
-- has. Probe: GetTradeSkillLineForRecipe is Mainline's; which of the two lines Forever's recipes
-- give is Unverified, so both are tried.
function internal.SkillOf(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetTradeSkillLineForRecipe and recipeID) then
        return nil
    end
    local line, _, parent = T.GetTradeSkillLineForRecipe(recipeID)
    local progress = ns.Professions.Progress
    return (parent and progress(parent)) or (line and progress(line)) or nil
end

-- Blizzard's own difficulty colors (FrameXML's), by Enum.TradeskillRelativeDifficulty, or false
-- without them. Probe: the enum and the constants are Mainline's.
local difficultyColors
function internal.DifficultyColors()
    if difficultyColors == nil then
        difficultyColors = false
        local E = Enum and Enum.TradeskillRelativeDifficulty
        if E and DIFFICULT_DIFFICULTY_COLOR and FAIR_DIFFICULTY_COLOR and EASY_DIFFICULTY_COLOR then
            difficultyColors = {
                [E.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
                [E.Medium] = FAIR_DIFFICULTY_COLOR,
                [E.Easy] = EASY_DIFFICULTY_COLOR,
                [E.Trivial] = TRIVIAL_DIFFICULTY_COLOR or GRAY_FONT_COLOR,
            }
        end
    end
    return difficultyColors
end

-- The row under the selected recipe's name on Blizzard's recipe form, where Skill Bar's bar and
-- Skill-Ups Left's line sit side by side, in `order` from the left, whichever of them shows. The
-- form (Blizzard_ProfessionsRecipeSchematicForm, Gethe forever branch) puts the name beside the
-- output icon, 17 pixels above its middle, and the tools it needs ("Requires: Anvil") under the
-- name; this row is 17 below the icon's middle, so it sits under both without moving anything of
-- Blizzard's.
local ROW_X, ROW_Y, ROW_GAP = 14, -17, 10
local ROW_RIGHT = 16 -- kept clear at the form's right edge
local onRow = {} -- order -> our region on the form, while it shows
local fitRow = {} -- order -> fn(width): that region takes the room the others leave

-- The room the row has, from where it starts to the form's right edge, or nil before the form
-- has been laid out.
local function rowWidth(form, icon)
    local right, left = form.GetRight and form:GetRight(), icon.GetRight and icon:GetRight()
    if right and left then
        return right - left - ROW_X - ROW_RIGHT
    end
end

---Puts `region` on the row (nil takes it off). With `fit`, the region is the one that gives way:
---`fit(width)` is called with the room the row's other regions leave it, to size itself.
function internal.PlaceOnForm(form, order, region, fit)
    onRow[order] = region
    fitRow[order] = region and fit or nil
    local icon = form and form.OutputIcon
    if not icon then
        return
    end
    local orders = {}
    for key in pairs(onRow) do
        orders[#orders + 1] = key
    end
    sort(orders)
    local room = rowWidth(form, icon)
    if room then
        for _, key in ipairs(orders) do
            if not fitRow[key] then
                room = room - onRow[key]:GetWidth() - ROW_GAP
            end
        end
        for _, key in ipairs(orders) do
            if fitRow[key] then
                fitRow[key](room)
            end
        end
    end
    local previous
    for _, key in ipairs(orders) do
        local item = onRow[key]
        item:ClearAllPoints()
        if previous then
            item:SetPoint("LEFT", previous, "RIGHT", ROW_GAP, 0)
        else
            item:SetPoint("LEFT", icon, "RIGHT", ROW_X, ROW_Y)
        end
        previous = item
    end
end

-- Crafting Costs prices what it can from auction prices, which only Item Tooltips' Auction Prices
-- (or Auctionator through it) gives. Without them it counts merchant prices alone. A list, since
-- parts add their own.
module.notice = {
    {
        text = L.PROFESSIONS_NO_PRICES,
        description = L.PROFESSIONS_NO_PRICES_DESC,
        shown = function()
            return ns.PartOn(module, "crafting") and not ns.Prices.Available()
        end,
    },
}
